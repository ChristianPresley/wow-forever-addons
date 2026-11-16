//! `cargo dev test`: loads each addon in a stand-in for the game client and uses everything in it.
//!
//! The stand-in is the four files `tools/harness/01-api.lua` to `04-world.lua`, built on the API
//! snapshot (`tools/api/forever-api.json`). The driver, `tools/harness/driver.lua`, loads the
//! files of an addon in the order of its TOC, logs in, opens each settings page, runs each slash
//! command, uses each frame and fires each event: alone, in a party, and in a fight in a raid.
//! `tools/harness/scenarios/<Addon>.lua` has what only one addon does, with checks. Each addon
//! runs twice: the second run starts from the saved variables of the first, as after a reload.

use std::fs;
use std::path::Path;

use mlua::{Lua, LuaOptions, LuaSerdeExt, StdLib, Table};

use crate::addons::Addon;

/// The stand-in for the game: one Lua chunk, so that the parts share their local names.
const STAND_IN: [&str; 4] = [
    include_str!("../harness/01-api.lua"),
    include_str!("../harness/02-widgets.lua"),
    include_str!("../harness/03-gameui.lua"),
    include_str!("../harness/04-world.lua"),
];
const DRIVER: &str = include_str!("../harness/driver.lua");
const NAMES: &str = include_str!("../harness/names.lua");
/// Names of the game that the documentation does not list (`cargo dev ui-names`).
const UI_NAMES: &str = include_str!("../api/forever-ui.json");

/// Puts the names of the game's UI files into the snapshot, under the key `ui`.
pub fn with_ui_names(snapshot: &mut serde_json::Value) -> Result<(), String> {
    let names: serde_json::Value = serde_json::from_str(UI_NAMES).map_err(|error| format!("tools/api/forever-ui.json is not valid JSON: {error}"))?;
    if let Some(map) = snapshot.as_object_mut() {
        map.insert("ui".to_string(), names);
    }
    Ok(())
}

/// The global names and the method names that the stand-in for the game has, for the
/// conformance check.
pub fn known_names(snapshot: &serde_json::Value) -> Result<(Vec<String>, Vec<String>), String> {
    let run = || -> mlua::Result<(Vec<String>, Vec<String>)> {
        let lua = unsafe { Lua::unsafe_new_with(StdLib::TABLE | StdLib::STRING | StdLib::MATH | StdLib::DEBUG, LuaOptions::default()) };
        let stand_in = STAND_IN.join("\n");
        let harness: Table = lua.load(stand_in.as_str()).set_name("=harness/stand-in").call(lua.to_value(snapshot)?)?;
        let names: Table = lua.load(NAMES).set_name("=harness/names.lua").call(harness)?;
        Ok((strings(&names, "globals")?, strings(&names, "methods")?))
    };
    run().map_err(|error| format!("The names of the stand-in could not be read: {error}"))
}

/// What one run of one addon found.
#[derive(Debug, Default)]
pub struct Outcome {
    /// Errors that reached the game.
    pub failures: Vec<String>,
    /// Errors that a `pcall` of the addon caught.
    pub caught: Vec<String>,
    /// Names that the addon looked for and that the stand-in does not have.
    pub absent: Vec<String>,
    /// The saved variables after the run, as Lua source.
    pub saved: String,
    /// What the run used: files, frames, events, commands, scripts, menu actions.
    pub summary: String,
    pub coverage: Vec<FileCoverage>,
}

/// Which code lines of one file ran. The count of code lines is an estimate: a line counts if
/// it has code and is not only the end of a block, and a statement over several lines counts
/// as several lines although Lua reports only some of them.
#[derive(Debug, Default, Clone)]
pub struct FileCoverage {
    pub name: String,
    pub total: u32,
    /// The code lines that did not run, in order.
    pub missed: Vec<u32>,
}

impl FileCoverage {
    pub fn percent(&self) -> u32 {
        if self.total == 0 {
            return 100;
        }
        let ran = self.total - self.missed.len() as u32;
        ran * 100 / self.total
    }
}

/// "12-15, 20, 31-40" for the lines 12, 13, 14, 15, 20, 31, ..., 40.
pub fn ranges(lines: &[u32]) -> String {
    let mut parts: Vec<String> = Vec::new();
    let mut index = 0;
    while index < lines.len() {
        let start = lines[index];
        let mut end = start;
        // Lines without code between two missed lines do not split a range.
        while index + 1 < lines.len() && lines[index + 1] <= end + 3 {
            index += 1;
            end = lines[index];
        }
        parts.push(if start == end { start.to_string() } else { format!("{start}-{end}") });
        index += 1;
    }
    parts.join(", ")
}

/// The names in `## SavedVariables` and `## SavedVariablesPerCharacter`.
fn saved_variables(addon: &Addon) -> Vec<String> {
    let Some(toc) = &addon.toc else { return Vec::new() };
    ["SavedVariables", "SavedVariablesPerCharacter"]
        .iter()
        .filter_map(|field| toc.fields.get(*field))
        .flat_map(|value| value.split(','))
        .map(|name| name.trim().to_string())
        .filter(|name| !name.is_empty())
        .collect()
}

fn strings(table: &Table, key: &str) -> mlua::Result<Vec<String>> {
    let list: Table = table.get(key)?;
    list.sequence_values::<String>().collect()
}

/// Runs one addon once. `saved` is the saved variables of an earlier run, or `None` for a first login.
pub fn run_addon(addon: &Addon, snapshot: &serde_json::Value, saved: Option<&str>) -> Result<Outcome, String> {
    let toc = addon.toc.as_ref().ok_or_else(|| format!("{}: no TOC file", addon.folder))?;
    // What only this addon does, with checks of the results.
    let scenario_file = Path::new(env!("CARGO_MANIFEST_DIR")).join("harness").join("scenarios").join(format!("{}.lua", addon.folder));
    let scenario = fs::read_to_string(scenario_file).ok();
    let scenario = scenario.as_deref();
    let run = || -> mlua::Result<Outcome> {
        // No file, OS or package library. The debug library is for the coverage count and for
        // the place of an error: the stand-in keeps it in a local table and takes the global
        // away, with the other names that an addon in the game does not have (loadfile, dofile,
        // string.dump). mlua calls a state with the debug library unsafe, because Lua code can
        // use it to break the memory safety of the state. The Lua code that runs here is this
        // repository's own: the stand-in, the driver and the addons.
        let lua = unsafe { Lua::unsafe_new_with(StdLib::TABLE | StdLib::STRING | StdLib::MATH | StdLib::DEBUG, LuaOptions::default()) };
        let files = lua.create_table()?;
        for name in &toc.files {
            if !name.to_lowercase().ends_with(".lua") {
                continue;
            }
            let source = fs::read(addon.dir.join(name)).map_err(mlua::Error::external)?;
            let file = lua.create_table()?;
            file.set("name", name.as_str())?;
            file.set("source", lua.create_string(&source)?)?;
            files.push(file)?;
        }
        let description = lua.create_table()?;
        description.set("name", addon.folder.as_str())?;
        description.set("files", files)?;
        description.set("saved", saved_variables(addon))?;
        if let Some(saved) = saved {
            description.set("savedSource", saved)?;
        }
        if let Some(scenario) = scenario {
            description.set("scenario", scenario)?;
        }

        let stand_in = STAND_IN.join("\n");
        let harness: Table = lua.load(stand_in.as_str()).set_name("=harness/stand-in").call(lua.to_value(snapshot)?)?;
        let result: Table = lua.load(DRIVER).set_name("=harness/driver.lua").call((harness, description))?;
        let counts: Table = result.get("counts")?;
        let count = |key: &str| counts.get::<i64>(key).unwrap_or(0);
        let mut coverage = Vec::new();
        for file in result.get::<Table>("coverage")?.sequence_values::<Table>() {
            let file = file?;
            let missed: Table = file.get("missed")?;
            coverage.push(FileCoverage {
                name: file.get("name")?,
                total: file.get("total")?,
                missed: missed.sequence_values::<u32>().collect::<mlua::Result<_>>()?,
            });
        }
        Ok(Outcome {
            coverage,
            failures: strings(&result, "failures")?,
            caught: strings(&result, "caught")?,
            absent: strings(&result, "absent")?,
            saved: result.get("saved")?,
            summary: format!(
                "{} files, {} frames, {} events, {} commands, {} scripts, {} menu actions, {} checks",
                count("files"),
                count("frames"),
                count("events"),
                count("commands"),
                count("scripts"),
                count("menuActions"),
                count("checks")
            ),
        })
    };
    run().map_err(|error| format!("{}: the test could not run: {error}", addon.folder))
}

/// The result of both runs of one addon.
pub struct Report {
    pub addon: String,
    pub summary: String,
    pub failures: Vec<String>,
    pub caught: Vec<String>,
    /// Names that the addon looked for and that the stand-in does not have.
    pub absent: Vec<String>,
    /// A line is missed if neither run reached it.
    pub coverage: Vec<FileCoverage>,
}

impl Report {
    /// Percent of the code lines of the addon that ran.
    pub fn percent(&self) -> u32 {
        let total: u32 = self.coverage.iter().map(|file| file.total).sum();
        let missed: u32 = self.coverage.iter().map(|file| file.missed.len() as u32).sum();
        if total == 0 {
            100
        } else {
            (total - missed) * 100 / total
        }
    }
}

fn merge(target: &mut Vec<String>, lines: Vec<String>, run: &str) {
    for line in lines {
        // The second run finds most things again: one line for each.
        let found = target.iter().any(|known| known.ends_with(&line));
        if !found {
            target.push(format!("{run} {line}"));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::addons::read_addons;

    const SNAPSHOT: &str = include_str!("../api/forever-api.json");

    /// Runs an addon with one Lua file, `Core.lua`, and returns its failures and its caught errors.
    fn check(lua: &str) -> (Vec<String>, Vec<String>) {
        let tmp = tempfile::TempDir::new().unwrap();
        let dir = tmp.path().join("Probe");
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("Probe.toc"), "## Interface: 16001\n## Title: Probe\n## SavedVariables: ProbeDB\n\nCore.lua\n").unwrap();
        fs::write(dir.join("Core.lua"), lua).unwrap();
        let addons = read_addons(tmp.path()).unwrap();
        let reports = run(&addons, SNAPSHOT).unwrap();
        let report = reports.into_iter().next().unwrap();
        (report.failures, report.caught)
    }

    fn fails_with(lua: &str, expected: &str) {
        let (failures, _) = check(lua);
        assert!(failures.iter().any(|failure| failure.contains(expected)), "expected a failure with {expected:?}, got {failures:?}");
    }

    #[test]
    fn a_correct_addon_has_no_failures() {
        let (failures, caught) = check(
            r#"
            local name, ns = ...
            local frame = CreateFrame("Frame")
            frame:RegisterEvent("ADDON_LOADED")
            frame:RegisterEvent("PLAYER_LOGIN")
            frame:SetScript("OnEvent", function(self, event, addon)
              if event == "ADDON_LOADED" and addon == name then
                ProbeDB = ProbeDB or { logins = 0 }
              elseif event == "PLAYER_LOGIN" then
                ProbeDB.logins = ProbeDB.logins + 1
                ns.text = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                ns.text:SetText(UnitName("player") .. " " .. C_Map.GetBestMapForUnit("player"))
              end
            end)
            SLASH_PROBE1 = "/probe"
            SlashCmdList["PROBE"] = function(input) print("/probe help - this text") end
            "#,
        );
        assert!(failures.is_empty(), "{failures:?}");
        assert!(caught.is_empty(), "{caught:?}");
    }

    #[test]
    fn errors_at_load_and_in_handlers_are_failures_with_the_file_and_line() {
        fails_with("local x = nil\nx.field = 1\n", "Probe/Core.lua:2");
        fails_with("local f = CreateFrame('Frame')\nf:RegisterEvent('PLAYER_LOGIN')\nf:SetScript('OnEvent', function() NoSuchFunction() end)\n", "Probe/Core.lua:3");
        fails_with("local f = CreateFrame('Frame')\nf:SetScript('OnUpdate', function() local n = nil + 1 end)\n", "Probe/Core.lua:2");
        fails_with("local f = CreateFrame('Button')\nf:SetScript('OnClick', function() error('clicked') end)\n", "clicked");
        fails_with("SLASH_PROBE1 = '/probe'\nSlashCmdList['PROBE'] = function(input) return input.missing.field end\n", "Probe/Core.lua:2");
        fails_with("C_Timer.After(1, function() error('timer ran') end)\n", "timer ran");
    }

    #[test]
    fn names_that_the_game_does_not_have_are_failures() {
        // A function that is not in the API, in a namespace and as a global.
        fails_with("C_Container.GetContainerItemCount(0, 1)\n", "GetContainerItemCount");
        fails_with("local id = GetContainerItemID(0, 1)\n", "Probe/Core.lua:1");
        // A widget method that does not exist.
        fails_with("local f = CreateFrame('Frame')\nf:SetBackdropColour(1, 1, 1)\n", "SetBackdropColour");
        // An event, a frame type and a template that do not exist.
        fails_with("CreateFrame('Frame'):RegisterEvent('PLAYER_LOGGED_IN')\n", "unknown event");
        fails_with("CreateFrame('Buton')\n", "unknown frame type");
        fails_with("CreateFrame('Button', nil, UIParent, 'UIPanelButonTemplate')\n", "Couldn't find inherited node");
        fails_with("hooksecurefunc('NoSuchGlobalFunction', function() end)\n", "is not a function");
    }

    #[test]
    fn wrong_arguments_are_failures() {
        fails_with("local f = CreateFrame('Frame')\nf:SetPoint('TOPLEFFT')\n", "unknown point");
        fails_with("local f = CreateFrame('Frame')\nf:SetSize('wide', 10)\n", "number expected, got string");
        fails_with("local t = CreateFrame('Frame'):CreateFontString()\nt:SetText({})\n", "string expected, got table");
        fails_with("local t = CreateFrame('Frame'):CreateFontString()\nt:SetFormattedText('%d', 'x')\n", "Probe/Core.lua:2");
    }

    #[test]
    fn a_secret_value_can_be_shown_but_not_calculated_with() {
        // In a fight the numbers of the damage meter are secret: showing one works.
        let shown = r#"
            local f = CreateFrame("Frame")
            local text = f:CreateFontString()
            f:SetScript("OnUpdate", function()
              local session = C_DamageMeter.GetCombatSessionFromType(1, 1)
              text:SetText(AbbreviateNumbers(session.totalAmount))
            end)
        "#;
        assert!(check(shown).0.is_empty());
        // Arithmetic with one is an error, and the failure says that it was in a fight.
        let calculated = shown.replace("AbbreviateNumbers(session.totalAmount)", "session.totalAmount / 2");
        let (failures, _) = check(&calculated);
        assert!(failures.iter().any(|failure| failure.contains("secret value") && failure.contains("in a fight")), "{failures:?}");
        // Time passes at the start of the fight too: that phase is named "fight".
        assert!(failures.iter().all(|failure| failure.contains("in a fight") || failure.contains("[fight]")), "out of a fight the numbers are plain: {failures:?}");
    }

    #[test]
    fn an_error_that_the_addon_catches_is_reported_with_its_place() {
        let (failures, caught) = check("local ok = pcall(function() error('probe failed') end)\n");
        assert!(failures.is_empty(), "{failures:?}");
        assert!(caught.iter().any(|line| line.contains("Probe/Core.lua:1") && line.contains("probe failed")), "{caught:?}");
    }

    #[test]
    fn the_second_run_starts_from_the_saved_variables_of_the_first() {
        // The first run saves a table of the wrong shape: the second run fails on it.
        let (failures, _) = check(
            r#"
            local name = ...
            local f = CreateFrame("Frame")
            f:RegisterEvent("ADDON_LOADED")
            f:RegisterEvent("PLAYER_LOGOUT")
            f:SetScript("OnEvent", function(_, event, addon)
              if event == "ADDON_LOADED" and addon == name and ProbeDB then
                local total = ProbeDB.count + 1
              elseif event == "PLAYER_LOGOUT" then
                ProbeDB = { count = "many", [3] = true }
              end
            end)
            "#,
        );
        assert!(failures.iter().any(|failure| failure.starts_with("after a reload:")), "{failures:?}");
        assert!(!failures.iter().any(|failure| failure.starts_with("first login:")), "{failures:?}");
    }

    #[test]
    fn saved_variables_load_after_the_files_as_in_the_game() {
        // A saved variable that is read while the file loads is nil in the game, also after a
        // reload: `local db = ProbeDB or {}` at the top of a file keeps a table that the game
        // then replaces.
        let (failures, _) = check(
            r#"
            if ProbeDB ~= nil then
              error("the saved variable was there while the file loaded")
            end
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_LOGIN")
            f:SetScript("OnEvent", function() ProbeDB = { logins = 1 } end)
            "#,
        );
        assert!(failures.is_empty(), "{failures:?}");
    }

    #[test]
    fn what_the_game_cannot_save_is_a_failure() {
        fails_with("ProbeDB = { callback = function() end }\n", "The game cannot save it");
        fails_with("ProbeDB = {}\nProbeDB.self = ProbeDB\n", "contains itself");
        fails_with("ProbeDB = { frame = CreateFrame('Frame') }\n", "saved variables");
        // A number that is not finite comes back as it was, and the run of the other addons goes on.
        let (failures, _) = check("ProbeDB = ProbeDB or { big = math.huge, third = 1 / 3 }\nif ProbeDB.third ~= 1 / 3 or ProbeDB.big ~= math.huge then error('a number changed') end\n");
        assert!(failures.is_empty(), "{failures:?}");
    }

    #[test]
    fn a_widget_has_the_methods_of_its_own_kind_only() {
        // Each of these is "attempt to call method ... (a nil value)" in the game.
        fails_with("local f = CreateFrame('Frame')\nf:CreateTexture():SetText('x')\n", "SetText");
        fails_with("local f = CreateFrame('Frame')\nf:SetText('x')\n", "SetText");
        fails_with("local f = CreateFrame('Frame')\nf:SetStatusBarColor(1, 1, 1)\n", "SetStatusBarColor");
        fails_with("local f = CreateFrame('Frame')\nf:CreateFontString():SetTexture('x')\n", "SetTexture");
        fails_with("local f = CreateFrame('Button')\nf:SetChecked(true)\n", "SetChecked");
        fails_with("local f = CreateFrame('Frame')\nf:CreateTexture():RegisterEvent('PLAYER_LOGIN')\n", "RegisterEvent");
        fails_with("local f = CreateFrame('Frame')\nf:AddLine('x')\n", "AddLine");
        fails_with("local f = CreateFrame('Frame')\nf:Click()\n", "Click");
        // The same calls on the right kind work.
        let (failures, _) = check(
            r#"
            local f = CreateFrame("Frame")
            f:CreateFontString():SetText("x")
            f:CreateFontString():EnableMouseWheel(true)
            f:CreateTexture():SetTexture("x")
            CreateFrame("StatusBar"):SetStatusBarColor(1, 1, 1)
            CreateFrame("CheckButton"):SetChecked(true)
            CreateFrame("BUTTON"):Click()
            GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
            GameTooltip:AddLine("x")
            assert(CreateFrame("Button"):IsObjectType("frame"))
            "#,
        );
        assert!(failures.is_empty(), "{failures:?}");
    }

    #[test]
    fn a_script_name_that_the_widget_does_not_have_is_a_failure() {
        fails_with("CreateFrame('Button'):SetScript('OnClik', function() end)\n", "doesn't have a \"OnClik\" script");
        fails_with("CreateFrame('Frame'):SetScript('OnClick', function() end)\n", "OnClick");
        fails_with("CreateFrame('Button'):HookScript('OnValueChanged', function() end)\n", "OnValueChanged");
        fails_with("GameTooltip:HookScript('OnTooltipSetItem', function() end)\n", "OnTooltipSetItem");
    }

    #[test]
    fn widgets_behave_as_in_the_game() {
        let (failures, _) = check(
            r#"
            local shown, hidden = 0, 0
            local parent = CreateFrame("Frame")
            local child = CreateFrame("Frame", nil, parent)
            child:SetScript("OnShow", function() shown = shown + 1 end)
            child:SetScript("OnHide", function() hidden = hidden + 1 end)
            parent:Hide()
            parent:Show()
            assert(hidden == 1 and shown == 1, "a child is hidden and shown with its parent")

            -- The forms of SetPoint, also (point, relativeTo, x, y), which the game's own code uses.
            child:SetPoint("TOPLEFT", parent, 10, -10)
            child:SetPoint("topleft", parent, "TOPLEFT", 4, 4)
            assert(child:GetNumPoints() == 1, "the same point again replaces the first")
            child:SetAllPoints(parent)
            assert(child:GetNumPoints() == 2)

            local slider = CreateFrame("Slider")
            slider:SetMinMaxValues(1, 10)
            slider:SetValue(99)
            assert(slider:GetValue() == 10, "a slider keeps its value in its range")

            local clicks = 0
            local button = CreateFrame("Button")
            button:SetScript("OnClick", function() clicks = clicks + 1 end)
            button:Disable()
            button:Click()
            assert(clicks == 0, "a disabled button does not click")
            button:SetText("hi")
            assert(button:GetFontString():GetText() == "hi", "a button and its font string share the text")

            local frame = CreateFrame("Frame")
            frame:SetFrameLevel(7)
            frame:SetFrameStrata("DIALOG")
            assert(frame:GetFrameLevel() == 7 and frame:GetFrameStrata() == "DIALOG")

            local close = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
            close:Click()
            assert(not parent:IsShown(), "the close button hides its parent")
            "#,
        );
        assert!(failures.is_empty(), "{failures:?}");
        fails_with("CreateFrame('Frame', nil, UIParent, 'UISliderTemplate')\n", "is for a Slider");
        fails_with("CreateFrame('Frame'):CreateFontString(nil, 'ARTWORK', 'GameFontNormall')\n", "Couldn't find inherited node");
        fails_with("CreateFrame('Frame'):CreateTexture(nil, 'ARTWRK')\n", "unknown draw layer");
        fails_with("CreateFrame('Frame'):SetFrameStrata('HIHG')\n", "unknown strata");
    }

    #[test]
    fn a_documented_function_checks_its_arguments() {
        fails_with("C_Item.GetItemInfo()\n", "requires a value");
        fails_with("C_Container.GetContainerNumSlots('backpack')\n", "number expected, got string");
        fails_with("C_Container.GetContainerNumSlots({})\n", "number expected, got table");
        // A function that only the game's own code can call is not there.
        fails_with("C_CombatLogSecure.GetCurrentEventInfo()\n", "Probe/Core.lua:1");
        // A documented value that cannot be nil is there, with its documented fields.
        let (failures, _) = check(
            r#"
            assert(type(UnitGUID("player")) == "string")
            assert(InCombatLockdown() == false)
            local info = C_Container.GetContainerItemInfo(0, 2)
            assert(info.stackCount == 12 and info.itemName == "Linen Cloth")
            assert(C_DateAndTime.GetCurrentCalendarTime().year == 0, "a structure has its documented fields")
            assert(bit.band(12, 10) == 8 and bit.bor(12, 10) == 14)
            "#,
        );
        assert!(failures.is_empty(), "{failures:?}");
    }

    #[test]
    fn pcall_keeps_every_result_and_the_addon_has_no_debug_library() {
        let (failures, _) = check(
            r##"
            local ok, a, b, c = pcall(function() return nil, 5, nil end)
            assert(ok and a == nil and b == 5 and c == nil)
            assert(select("#", pcall(function() return nil, nil end)) == 3)
            assert(debug == nil and dofile == nil and loadfile == nil and string.dump == nil and __H == nil)
            local first, second = strsplit(":", "a:b:c", 2)
            assert(first == "a" and second == "b:c")
            assert(select("#", strsplit(",;", "a;b,c")) == 3)
            "##,
        );
        assert!(failures.is_empty(), "{failures:?}");
    }

    #[test]
    fn a_secret_value_has_its_real_type_and_is_refused_as_an_argument() {
        // `type` of a secret number is "number", as in the game, so a guard that tests the type
        // first and calculates after it fails. Only in a fight.
        let guarded = r#"
            local f = CreateFrame("Frame")
            f:SetScript("OnUpdate", function()
              local amount = C_DamageMeter.GetCombatSessionFromType(1, 1).totalAmount
              if type(amount) == "number" then
                local half = amount / 2
              end
            end)
        "#;
        let (failures, _) = check(guarded);
        assert!(failures.iter().any(|failure| failure.contains("secret value") && failure.contains("in a fight")), "{failures:?}");
        // The right order: is it secret, then the type.
        let (failures, _) = check(&guarded.replace("type(amount) == \"number\"", "not issecretvalue(amount) and type(amount) == \"number\""));
        assert!(failures.is_empty(), "{failures:?}");

        // A function that the documentation does not open to a secret value refuses it: here
        // the width of a frame. A font string can show it.
        let widget = r#"
            local f = CreateFrame("Frame")
            local text = f:CreateFontString()
            f:SetScript("OnUpdate", function()
              local amount = C_DamageMeter.GetCombatSessionFromType(1, 1).totalAmount
              text:SetText(amount)
              WIDGET
            end)
        "#;
        assert!(check(&widget.replace("WIDGET", "")).0.is_empty());
        let (failures, _) = check(&widget.replace("WIDGET", "f:SetWidth(amount)"));
        assert!(failures.iter().any(|failure| failure.contains("secret value is not allowed")), "{failures:?}");

        // A secret value as a table key is an error in the game.
        let (failures, _) = check(
            r#"
            local name, ns = ...
            ns.totals = {}
            local f = CreateFrame("Frame")
            f:SetScript("OnUpdate", function()
              local source = C_DamageMeter.GetCombatSessionFromType(1, 1).combatSources[1]
              ns.totals[source.name] = true
            end)
            "#,
        );
        assert!(failures.iter().any(|failure| failure.contains("a secret value is a key")), "{failures:?}");
    }

    #[test]
    fn an_event_comes_with_its_documented_arguments() {
        let (failures, _) = check(
            r#"
            local name = ...
            local f = CreateFrame("Frame")
            f:RegisterEvent("ADDON_LOADED")
            f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            f:RegisterEvent("PLAYER_LOGIN")
            local logins = 0
            f:SetScript("OnEvent", function(_, event, a, b)
              if event == "ADDON_LOADED" then
                assert(a == name, "ADDON_LOADED has the name of the addon")
              elseif event == "GET_ITEM_INFO_RECEIVED" then
                assert(type(a) == "number" and type(b) == "boolean")
              elseif event == "PLAYER_LOGIN" then
                logins = logins + 1
                assert(logins == 1, "PLAYER_LOGIN comes once")
              end
            end)
            "#,
        );
        assert!(failures.is_empty(), "{failures:?}");
    }

    /// Calls that the game's own UI code makes, each with its file. The documentation is
    /// narrower than the game for some of them, and the stand-in once refused them.
    #[test]
    fn calls_of_the_games_own_code_pass() {
        let (failures, _) = check(
            r##"
            local f = CreateFrame("Frame")
            -- Blizzard_ActionBar/Shared/ActionButton.lua
            f:RegisterUnitEvent("UNIT_FLAGS", "pet")
            f:RegisterUnitEvent("UNIT_AURA", "player", "target")
            -- Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua
            f:SetAttribute("checkselfcast", true)
            f:SetAttribute("data", { 1 })
            -- Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua
            local texture = f:CreateTexture(nil, "ARTWORK")
            texture:SetTexture("Interface\\Buttons\\WHITE8X8", true, true)
            -- Blizzard_StableUI/Camelot/Blizzard_StableUI.lua
            assert(Constants.PetConsts.NUM_PET_SLOTS_HUNTER == 3, "PetConsts")
            -- Blizzard_Fonts_Shared: fonts of the game's XML files
            f:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
            f:CreateFontString(nil, "ARTWORK", "QuestFont")
            -- An event that the game's code registers and the documentation does not list.
            f:RegisterEvent("PLAYTIME_CHANGED")
            f:UnregisterEvent("PLAYTIME_CHANGED")
            -- An EventEditBox is an EditBox, so it takes the template of one.
            local box = CreateFrame("EventEditBox", nil, f, "InputBoxTemplate")
            assert(box:IsObjectType("EditBox"), "IsObjectType")
            -- The checked texture of a check button is a texture object.
            local check = CreateFrame("CheckButton", nil, f)
            check:GetCheckedTexture():SetVertexColor(1, 1, 1)
            -- Blizzard_AutoComplete/AutoComplete.lua: bit.bor with three values
            assert(bit.bor(1, 2, 4) == 7, "bit.bor")
            assert(bit.band(7, 6, 3) == 2, "bit.band")
            -- Blizzard_SharedXMLBase/CvarUtil.lua: a boolean for SetCVar
            SetCVar("damageMeterEnabled", true)
            assert(GetCVar("damageMeterEnabled") == "1", "SetCVar")
            -- Blizzard_FrameXMLBase/IconDataProvider.lua
            assert(type(collectgarbage("count")) == "number", "collectgarbage")
            -- Blizzard_BuffFrame/BuffFrame.lua, Blizzard_AnimatedShine/Shared/AnimatedShine.lua
            assert(securecall(function(a) return a + 1 end, 1) == 2, "securecall")
            local list = { "a", "b", "a" }
            assert(tDeleteItem(list, "a") == 2 and #list == 1, "tDeleteItem")
            assert(not issecure(), "issecure")
            assert(select("#", strsplit(",", 12)) == 1, "strsplit with a number")
            f:SetWidth("10")
            assert(f:GetWidth() == 10, "a numeric text as a width")
            -- A realm of the player's own realm is taken off a name.
            assert(Ambiguate("Friend-TestRealm", "none") == "Friend", "Ambiguate")
            assert(Ambiguate("Friend-OtherRealm", "none") == "Friend-OtherRealm", "Ambiguate keeps another realm")
            assert(date("%y-%m-%d %%", 0) == "70-01-01 %", date("%y-%m-%d %%", 0))
            assert(date("%A %B", 0) == "Thursday January", date("%A %B", 0))
            "##,
        );
        assert!(failures.is_empty(), "{failures:?}");
    }

    #[test]
    fn a_library_function_that_is_not_written_fails_and_gives_no_wrong_value() {
        fails_with("local half = math.lerp(0, 10, 0.5)", "does not have math.lerp yet");
        fails_with("local text = date('%Z')", "date letter %Z");
    }

    #[test]
    fn a_tooltip_with_lines_is_not_on_the_screen_before_show() {
        let (failures, _) = check(
            r#"
            GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
            GameTooltip:AddLine("A line")
            assert(not GameTooltip:IsShown(), "shown after AddLine")
            GameTooltip:Show()
            assert(GameTooltip:IsShown(), "not shown after Show")
            GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
            assert(not GameTooltip:IsShown() and GameTooltip:NumLines() == 0, "SetOwner clears and hides")
            GameTooltip:SetItemByID(2589)
            assert(GameTooltip:IsShown(), "an item shows the tooltip")
            GameTooltip:Hide()
            "#,
        );
        assert!(failures.is_empty(), "{failures:?}");
    }

    #[test]
    fn an_endless_loop_in_a_handler_ends_with_a_failure() {
        let (failures, _) = check(
            r#"
            local f = CreateFrame("Frame")
            f:SetScript("OnUpdate", function()
              while true do
                pcall(error, "caught by the addon")
              end
            end)
            "#,
        );
        assert!(failures.iter().any(|failure| failure.contains("does not come to an end")), "{failures:?}");
    }

    /// The snapshot is well formed: what the stand-in reads from it has only the letters and
    /// marks that the stand-in knows.
    #[test]
    fn the_snapshot_is_well_formed() {
        let snapshot: serde_json::Value = serde_json::from_str(SNAPSHOT).unwrap();
        let structures = snapshot["structures"].as_object().unwrap();
        let mut problems = Vec::new();
        let codes = |place: &str, text: &str, problems: &mut Vec<String>| {
            let mut rest = text;
            while let Some(letter) = rest.chars().next() {
                rest = &rest[1..];
                if !"nsbtfoa".contains(letter) {
                    problems.push(format!("{place}: unknown letter {letter:?} in {text:?}"));
                    return;
                }
                if let Some(inner) = rest.strip_prefix('{') {
                    let Some(end) = inner.find('}') else {
                        problems.push(format!("{place}: no end of the structure name in {text:?}"));
                        return;
                    };
                    if !structures.contains_key(&inner[..end]) {
                        problems.push(format!("{place}: unknown structure {}", &inner[..end]));
                    }
                    rest = &inner[end + 1..];
                }
                rest = rest.strip_prefix(['?', '*']).unwrap_or(rest);
            }
        };
        let spec = |place: &str, value: &serde_json::Value, problems: &mut Vec<String>| {
            let text = value.as_str().unwrap_or("");
            let parts: Vec<&str> = text.split('|').collect();
            if parts.len() != 3 {
                problems.push(format!("{place}: {text:?} does not have three parts"));
                return;
            }
            codes(place, parts[0], problems);
            codes(place, parts[1], problems);
            if let Some(flag) = parts[2].chars().find(|flag| !"TUNCSRMPAH".contains(*flag)) {
                problems.push(format!("{place}: unknown flag {flag:?}"));
            }
        };
        for (name, value) in snapshot["globals"].as_object().unwrap() {
            spec(name, value, &mut problems);
        }
        for (namespace, functions) in snapshot["namespaces"].as_object().unwrap() {
            let functions = functions.as_object().unwrap();
            if functions.is_empty() {
                problems.push(format!("{namespace}: a namespace without functions"));
            }
            for (name, value) in functions {
                spec(&format!("{namespace}.{name}"), value, &mut problems);
            }
        }
        for (object, entry) in snapshot["widgets"].as_object().unwrap() {
            for (name, value) in entry["methods"].as_object().unwrap() {
                spec(&format!("{object}:{name}"), value, &mut problems);
            }
        }
        for (event, payload) in snapshot["events"].as_object().unwrap() {
            codes(event, payload.as_str().unwrap_or("?"), &mut problems);
        }
        for (structure, fields) in structures {
            for (field, code) in fields.as_object().unwrap() {
                codes(&format!("{structure}.{field}"), code.as_str().unwrap_or("?"), &mut problems);
            }
        }
        let enums = snapshot["enums"].as_object().unwrap();
        for (name, meta) in snapshot["enumMeta"].as_object().unwrap() {
            let Some(fields) = enums.get(name).and_then(|fields| fields.as_object()) else {
                problems.push(format!("enumMeta.{name}: no such enumeration"));
                continue;
            };
            let values: Vec<i64> = fields.values().filter_map(|value| value.as_i64()).collect();
            let (count, least, greatest) = (meta[0].as_i64().unwrap_or(-1), meta[1].as_i64().unwrap_or(0), meta[2].as_i64().unwrap_or(0));
            if count != values.len() as i64 || values.iter().min().is_some_and(|min| *min != least) || values.iter().max().is_some_and(|max| *max != greatest) {
                problems.push(format!("enumMeta.{name}: {meta} does not fit the {} values", values.len()));
            }
        }
        for event in snapshot["eventFlags"].as_object().unwrap().keys() {
            if snapshot["events"].get(event).is_none() {
                problems.push(format!("eventFlags.{event}: no such event"));
            }
        }
        let constants = snapshot["constants"].as_object().unwrap();
        for name in snapshot["unresolvedConstants"].as_array().unwrap() {
            let (table, value) = name.as_str().unwrap().split_once('.').unwrap();
            if constants.get(table).and_then(|values| values.get(value)).is_some() {
                problems.push(format!("{table}.{value} has a value and is listed as without one"));
            }
        }
        assert!(problems.is_empty(), "{} problems, the first: {:?}", problems.len(), &problems[..problems.len().min(10)]);
    }
}

/// Runs every addon: a first login, then a reload with the saved variables of the first run.
pub fn run(addons: &[Addon], snapshot_json: &str) -> Result<Vec<Report>, String> {
    let mut snapshot: serde_json::Value = serde_json::from_str(snapshot_json).map_err(|error| format!("The API snapshot is not valid JSON: {error}"))?;
    with_ui_names(&mut snapshot)?;
    let mut reports = Vec::new();
    for addon in addons {
        let first = run_addon(addon, &snapshot, None)?;
        let second = run_addon(addon, &snapshot, Some(&first.saved))?;
        let mut coverage = first.coverage;
        for (file, again) in coverage.iter_mut().zip(&second.coverage) {
            file.missed.retain(|line| again.missed.contains(line));
        }
        let mut report = Report { addon: addon.folder.clone(), summary: first.summary, failures: Vec::new(), caught: Vec::new(), absent: first.absent, coverage };
        merge(&mut report.failures, first.failures, "first login:");
        merge(&mut report.failures, second.failures, "after a reload:");
        merge(&mut report.caught, first.caught, "first login:");
        merge(&mut report.caught, second.caught, "after a reload:");
        reports.push(report);
    }
    Ok(reports)
}
