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
use std::sync::OnceLock;

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

/// `tools/api/forever-ui.json`, read once.
fn ui_names() -> Result<&'static serde_json::Value, String> {
    static NAMES: OnceLock<Result<serde_json::Value, String>> = OnceLock::new();
    NAMES
        .get_or_init(|| serde_json::from_str(UI_NAMES).map_err(|error| format!("tools/api/forever-ui.json is not valid JSON: {error}")))
        .as_ref()
        .map_err(Clone::clone)
}

/// The small lists of the game's UI files, which the stand-in reads when it loads. The
/// templates, the mixins and the calls are large: the stand-in asks for one of them when it
/// needs it (see `stand_in`).
const UI_LISTS: [&str; 8] = ["animationTypes", "enumerations", "fonts", "frameTypes", "intrinsics", "scripts", "tooltipAnchors", "undocumentedEvents"];

/// Puts the names of the game's UI files into the snapshot, under the key `ui`.
pub fn with_ui_names(snapshot: &mut serde_json::Value) -> Result<(), String> {
    let names = ui_names()?;
    let mut lists = serde_json::Map::new();
    for key in UI_LISTS {
        if let Some(value) = names.get(key) {
            lists.insert(key.to_string(), value.clone());
        }
    }
    if let Some(map) = snapshot.as_object_mut() {
        map.insert("ui".to_string(), serde_json::Value::Object(lists));
    }
    Ok(())
}

/// Loads the stand-in alone, without an addon, and returns its table `H`.
///
/// The stand-in gets the snapshot, and a table of functions that give one entry of the large
/// parts of `forever-ui.json`: `template(name)`, `mixin(name)` and `calls()`.
fn stand_in(lua: &Lua, snapshot: &serde_json::Value) -> mlua::Result<Table> {
    let names = ui_names().map_err(mlua::Error::external)?;
    let lookup = lua.create_table()?;
    // Without the names of the UI files (a snapshot that `with_ui_names` did not fill) the
    // stand-in has its own hand-written templates only.
    if snapshot.get("ui").is_some() {
        for (function, key) in [("template", "templates"), ("mixin", "mixins")] {
            lookup.set(
                function,
                lua.create_function(move |lua, name: String| match names.get(key).and_then(|entries| entries.get(&name)) {
                    Some(entry) => lua.to_value(entry),
                    None => Ok(mlua::Value::Nil),
                })?,
            )?;
        }
        lookup.set("calls", lua.create_function(move |lua, ()| lua.to_value(names.get("calls").unwrap_or(&serde_json::Value::Null)))?)?;
    }
    let stand_in = STAND_IN.join("\n");
    lua.load(stand_in.as_str()).set_name("=harness/stand-in").call((lua.to_value(snapshot)?, lookup))
}

/// The global names and the method names that the stand-in for the game has, for the
/// conformance check.
pub fn known_names(snapshot: &serde_json::Value) -> Result<(Vec<String>, Vec<String>), String> {
    let run = || -> mlua::Result<(Vec<String>, Vec<String>)> {
        let lua = unsafe { Lua::unsafe_new_with(StdLib::TABLE | StdLib::STRING | StdLib::MATH | StdLib::DEBUG, LuaOptions::default()) };
        let harness = stand_in(&lua, snapshot)?;
        let names: Table = lua.load(NAMES).set_name("=harness/names.lua").call(harness)?;
        Ok((strings(&names, "globals")?, strings(&names, "methods")?))
    };
    run().map_err(|error| format!("The names of the stand-in could not be read: {error}"))
}

/// The names of the methods that a widget of the stand-in can have: the documented ones of every
/// kind, and the undocumented ones that the stand-in adds with a file of the game as the proof.
pub fn widget_methods(snapshot: &serde_json::Value) -> Result<Vec<String>, String> {
    let run = || -> mlua::Result<Vec<String>> {
        let lua = unsafe { Lua::unsafe_new_with(StdLib::TABLE | StdLib::STRING | StdLib::MATH | StdLib::DEBUG, LuaOptions::default()) };
        let harness = stand_in(&lua, snapshot)?;
        let names: Table = harness.get::<mlua::Function>("widgetMethodNames")?.call(())?;
        names.sequence_values::<String>().collect()
    };
    run().map_err(|error| format!("The method names of the widgets could not be read: {error}"))
}

/// Compares the stand-in with what `tools/api/forever-ui.json` has from the game's UI files:
/// frame types, scripts, templates, and the calls of the game's own code. Returns the
/// differences, one text for each.
pub fn ui_check(snapshot: &serde_json::Value) -> Result<Vec<String>, String> {
    let run = || -> mlua::Result<Vec<String>> {
        let lua = unsafe { Lua::unsafe_new_with(StdLib::TABLE | StdLib::STRING | StdLib::MATH | StdLib::DEBUG, LuaOptions::default()) };
        let harness = stand_in(&lua, snapshot)?;
        let problems: Table = harness.get::<mlua::Function>("uiCheck")?.call(())?;
        problems.sequence_values::<String>().collect()
    };
    run().map_err(|error| format!("The check of the stand-in against the UI files could not run: {error}"))
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

        let harness = stand_in(&lua, snapshot)?;
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

    /// Taint: the game refuses protected actions after its own code ran a function of an addon.
    #[test]
    fn a_function_of_the_game_replaced_by_the_addon_is_a_failure() {
        fails_with("local old = ToggleAllBags\nToggleAllBags = function(...) return old(...) end\n", "in the place of the game's ToggleAllBags");
        // A hook is what the game allows.
        let (failures, _) = check("local count = 0\nhooksecurefunc('ToggleAllBags', function() count = count + 1 end)\nToggleAllBags()\nassert(count == 1)\n");
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

    /// A template gives a frame what the game's XML file of the template has: child keys, names,
    /// key values and the names of the mixin methods. Behaviour is written by hand on top.
    #[test]
    fn a_template_has_what_the_games_xml_file_gives_it() {
        let (failures, _) = check(
            r#"
            -- Blizzard_UIPanelTemplates/Mainline/UIPanelTemplates.xml
            local window = CreateFrame("Frame", "ProbeWindow", UIParent, "BasicFrameTemplateWithInset")
            assert(window.TitleText and window.CloseButton and window.Bg and window.InsetBg and window.InsetBorderTop, "child keys")
            assert(window.Inset == nil, "the template has no Inset")
            window.CloseButton:Click()
            assert(not window:IsShown(), "the close button hides the window")
            -- Blizzard_SharedXML/SecureUIPanelTemplates.xml: the button text, and a key value
            local button = CreateFrame("Button", "ProbeButton", UIParent, "UIPanelButtonTemplate")
            assert(button.Text == button:GetFontString() and ProbeButtonText == button.Text, "the text of the button")
            assert(button.Left and button.Middle and button.Right and button.fitTextWidthPadding == 40, "parts and key value")
            button:SetText("Scan")
            assert(button.Text:GetText() == "Scan", "one text")
            -- Blizzard_SharedXML/Shared/Button/CheckButtonTemplates.xml
            local check = CreateFrame("CheckButton", "ProbeCheck", UIParent, "UICheckButtonTemplate")
            assert(check.Text and check.text == check.Text and ProbeCheckText == check.Text, "check button text")
            -- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml: the thumb is the thumb texture
            local slider = CreateFrame("Slider", nil, UIParent, "UISliderTemplate")
            assert(slider.Thumb == slider:GetThumbTexture() and slider.NineSlice and slider.Low == nil, "slider")
            -- Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml
            local box = CreateFrame("EditBox", nil, UIParent, "SearchBoxTemplate")
            assert(box.Instructions and box.searchIcon and box.clearButton and box.clearButton.Icon and box.Left, "search box")
            box:SetFocus()
            box:GetScript("OnEscapePressed")(box)
            assert(not box:HasFocus(), "Escape takes the focus away")
            -- An intrinsic frame type has the parts of its own XML definition (ItemButton).
            local item = CreateFrame("ItemButton", nil, UIParent)
            assert(item.icon and item.Count and item.IconBorder and item.searchOverlay, "item button")
            local slot = CreateFrame("ItemButton", nil, CreateFrame("Frame", nil, UIParent), "ContainerFrameItemButtonTemplate")
            slot:GetParent():SetID(3)
            assert(slot:GetBagID() == 3 and slot.Cooldown and slot.JunkIcon, "bag slot")
            slot:SetBagID(1)
            assert(slot:GetBagID() == 1, "SetBagID")
            -- A template that the stand-in has nothing written for is made from the XML file alone.
            local cooldown = CreateFrame("Cooldown", nil, window, "CooldownFrameTemplate")
            cooldown:SetCooldown(0, 0)
            local panel = CreateFrame("Frame", nil, UIParent, "ButtonFrameTemplate")
            assert(panel.Inset and panel.CloseButton and type(panel.SetTitle) == "function", "ButtonFrameTemplate")
            local backdrop = CreateFrame("Button", nil, UIParent, "BackdropTemplate, UIPanelButtonTemplate")
            backdrop:SetBackdrop({ edgeSize = 1 })
            backdrop:SetBackdropColor(0, 0, 0, 0.5)
            assert(select(4, backdrop:GetBackdropColor()) == 0.5, "backdrop colour")
            "#,
        );
        assert!(failures.is_empty(), "{failures:?}");
        fails_with("CreateFrame('Frame', nil, UIParent, 'NoSuchTemplate')\n", "Couldn't find inherited node");
        fails_with("CreateFrame('Frame', nil, UIParent, 'UIPanelButtonTemplate')\n", "is for a Button, not for a Frame");
        // A method of a mixin of the game that nobody wrote: the name is there, the call fails.
        fails_with("local panel = CreateFrame('Frame', nil, UIParent, 'ButtonFrameTemplate')\npanel:SetTitle('Prices')\n", "does not have the method SetTitle");
        fails_with("CreateFrame('Frame'):CreateTexture(nil, 'ARTWORK', 'NoSuchTextureTemplate')\n", "Couldn't find inherited node");
    }

    /// Every frame type and animation type of the game can be made, and behaves as its kind.
    #[test]
    fn every_frame_type_of_the_game_can_be_made() {
        let (failures, _) = check(
            r#"
            for _, kind in ipairs({ "ModelFFX", "DropDownToggleButton", "ContainedAlertFrame", "FogOfWarFrame", "UnitPositionFrame",
              "QuestPOIFrame", "ScenarioPOIFrame", "ArchaeologyDigSiteFrame", "Checkout", "MapScene", "TaxiRouteFrame", "AuraButton" }) do
              CreateFrame(kind)
            end
            assert(CreateFrame("ContainedAlertFrame"):IsObjectType("Button"), "an alert frame is a button")
            CreateFrame("QuestPOIFrame"):DrawNone()
            local group = CreateFrame("Frame"):CreateAnimationGroup()
            for _, kind in ipairs({ "Alpha", "Scale", "LineScale", "Translation", "LineTranslation", "Rotation", "Path", "FlipBook", "VertexColor", "TextureCoordTranslation", "RadialProgress" }) do
              assert(group:CreateAnimation(kind):GetObjectType() == kind, kind)
            end
            -- Scripts of the game's XML files: Blizzard_RecruitAFriend, Blizzard_HelpFrame, DressUpFrames.xml
            CreateFrame("Model"):SetScript("OnAnimStarted", function() end)
            CreateFrame("Browser"):SetScript("OnExternalLink", function() end)
            CreateFrame("ModelScene"):SetScript("OnDressModel", function() end)
            "#,
        );
        assert!(failures.is_empty(), "{failures:?}");
        fails_with("CreateFrame('QuestPOIFrame'):SetText('x')\n", "SetText");
        fails_with("CreateFrame('Frame'):SetScript('OnAnimStarted', function() end)\n", "doesn't have a \"OnAnimStarted\" script");
    }

    /// What a widget does when its state changes, as far as the game's own code shows it.
    #[test]
    fn a_change_of_state_does_what_the_game_does() {
        let (failures, _) = check(
            r#"
            local f = CreateFrame("Frame", nil, UIParent)
            -- A widget under a hidden parent is not on the screen: OnHide, and OnShow on the way back.
            local hidden = CreateFrame("Frame", nil, UIParent)
            hidden:Hide()
            local seen = ""
            f:SetScript("OnHide", function() seen = seen .. "h" end)
            f:SetScript("OnShow", function() seen = seen .. "s" end)
            f:SetParent(hidden)
            f:SetParent(UIParent)
            assert(seen == "hs", seen)
            -- ClearPoint takes one anchor away.
            f:SetPoint("LEFT")
            f:SetPoint("RIGHT")
            f:ClearPoint("LEFT")
            assert(f:GetNumPoints() == 1 and f:GetPoint(1) == "RIGHT", "ClearPoint")
            -- The corners of a texture: Blizzard_SharedXMLBase/TextureUtil.lua reads eight values.
            local texture = f:CreateTexture()
            local ulX, ulY, llX, llY, urX, urY, lrX, lrY = texture:GetTexCoord()
            assert(ulX == 0 and ulY == 0 and llY == 1 and urX == 1 and lrX == 1 and lrY == 1 and llX == 0 and urY == 0, "the whole picture")
            texture:SetTexCoord(0.1, 0.9, 0.2, 0.8)
            ulX, ulY, llX, llY, urX, urY, lrX, lrY = texture:GetTexCoord()
            assert(ulX == 0.1 and ulY == 0.2 and llX == 0.1 and llY == 0.8 and urX == 0.9 and urY == 0.2 and lrX == 0.9 and lrY == 0.8, "left, right, top, bottom")
            texture:SetDrawLayer("overlay", 2)
            assert(select(2, texture:GetDrawLayer()) == 2 and texture:GetDrawLayer() == "OVERLAY", "draw layer")
            texture:SetBlendMode("ADD")
            assert(texture:GetBlendMode() == "ADD", "blend mode")
            -- The number of an edit box is its text (NumericInputBoxMixin).
            local box = CreateFrame("EditBox", nil, f)
            local changes = 0
            box:SetScript("OnTextChanged", function(_, userInput) changes = changes + (userInput and 100 or 1) end)
            box:SetNumber(42)
            assert(box:GetText() == "42" and box:GetNumber() == 42 and changes == 1, "SetNumber")
            box:Insert("0")
            assert(box:GetNumber() == 420 and changes == 2, "Insert")
            -- A font by its name: Blizzard_GuildControlUI/Localization.lua.
            local text = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            text:SetFontObject("GameFontHighlight")
            assert(text:GetFontObject() == GameFontHighlight, "font object")
            text:SetJustifyH("right")
            assert(text:GetJustifyH() == "RIGHT", "justify")
            -- An animation group that plays.
            local group = f:CreateAnimationGroup()
            local played = 0
            group:SetScript("OnPlay", function() played = played + 1 end)
            group:Play()
            assert(group:IsPlaying() and played == 1, "Play")
            group:Stop()
            assert(not group:IsPlaying(), "Stop")
            -- An attribute keeps a value of any kind.
            f:SetAttribute("shown", true)
            assert(f:GetAttribute("shown") == true, "attribute")
            -- A widget without a name, a parent or a script gives nil.
            local top = CreateFrame("Frame")
            assert(top:GetName() == nil and top:GetParent() == nil and top:GetScript("OnUpdate") == nil, "nil")
            top:SetPoint("CENTER")
            assert(select(2, top:GetPoint(1)) == nil, "an anchor to the screen")
            assert(CreateFrame("Button"):GetText() == nil, "a button without a text")
            -- More of the older tooltip methods.
            GameTooltip:SetOwner(UIParent, "ANCHOR_CENTER")
            assert(GameTooltip:SetUnit("player") and GameTooltip:IsShown(), "SetUnit")
            GameTooltip:AddTexture(134400)
            GameTooltip_Hide()
            assert(not GameTooltip:IsShown(), "GameTooltip_Hide")
            -- SetAllPoints: the parent without an argument, the screen for nil, a region by its name.
            local filler = f:CreateTexture()
            filler:SetAllPoints()
            assert(select(2, filler:GetPoint(1)) == f and filler:GetNumPoints() == 2, "the parent")
            filler:SetAllPoints(nil)
            assert(select(2, filler:GetPoint(1)) == nil, "the screen")
            filler:SetAllPoints("UIParent")
            assert(select(2, filler:GetPoint(2)) == UIParent, "by name")
            -- Alpha stays between 0 and 1 (patch 12.0.0).
            f:SetAlpha(2)
            assert(f:GetAlpha() == 1, "alpha above 1")
            f:SetAlpha(-1)
            assert(f:GetAlpha() == 0, "alpha below 0")
            -- One offset: Blizzard_CharacterCustomize/Camelot/Blizzard_CharacterCustomize.lua.
            f:SetPoint("LEFT", 40)
            -- An intrinsic frame is of the type that it is made from.
            local item = CreateFrame("ItemButton")
            assert(item:GetObjectType() == "Button" and CreateFrame("EventFrame"):GetObjectType() == "Frame", "the type of an intrinsic frame")
            assert(item:IsObjectType("Button") and item:IsObjectType("Frame") and not item:IsObjectType("ItemButton"), "IsObjectType of an intrinsic frame")
            -- An anchor to the screen does not hang on the parent: the parent can hang on the child.
            local outer = CreateFrame("Frame", nil, UIParent)
            local inner = CreateFrame("Frame", nil, outer)
            inner:SetPoint("CENTER", nil, "CENTER")
            outer:SetPoint("LEFT", inner, "RIGHT")
            "#,
        );
        assert!(failures.is_empty(), "{failures:?}");
        // Two regions that hang on each other: the text of the game's error.
        fails_with("local a, b = CreateFrame('Frame'), CreateFrame('Frame')\na:SetPoint('LEFT', b, 'RIGHT')\nb:SetPoint('LEFT', a, 'RIGHT')\n", "Cannot anchor to a region dependent on it");
        fails_with("local f = CreateFrame('Frame')\nf:SetPoint('CENTER', f, 'CENTER')\n", "Cannot anchor to a region dependent on it");
        fails_with("local parent = CreateFrame('Frame')\nlocal child = CreateFrame('Frame', nil, parent)\nchild:SetPoint('CENTER')\nparent:SetAllPoints(child)\n", "Cannot anchor to a region dependent on it");
        fails_with("CreateFrame('Frame', nil, UIParent):CreateTexture():SetAllPoints(true)\n", "is not a region");
        // A name for the parent is not taken since patch 10.0.0.
        fails_with("CreateFrame('Frame'):SetParent('UIParent')\n", "is not a frame");
        // WORLD is the strata of the world frame alone.
        fails_with("CreateFrame('Frame'):SetFrameStrata('WORLD')\n", "unknown strata");
        fails_with("GameTooltip:SetOwner(UIParent, 'ANCHOR_CURSOR_LEFT')\n", "unknown anchor");
        fails_with("CreateFrame('Frame'):CreateTexture():SetDrawLayer('TOPMOST')\n", "unknown draw layer");
        fails_with("CreateFrame('Frame'):CreateTexture():SetBlendMode('ADDITIVE')\n", "unknown value");
        fails_with("CreateFrame('Frame'):CreateFontString():SetFontObject('NoSuchFont')\n", "there is no font with the name");
        fails_with("CreateFrame('Frame'):CreateTexture():SetTexCoord(0, 1)\n", "a number is needed");
    }

    /// `tools/ingame-probe/ForeverProbe` asks the game client what it does where no source says
    /// it. It must stay a correct addon: it loads and runs in the stand-in without a failure.
    #[test]
    fn the_probe_for_the_game_is_a_correct_addon() {
        let (failures, _) = check(include_str!("../ingame-probe/ForeverProbe/Core.lua"));
        assert!(failures.is_empty(), "{failures:?}");
    }

    /// The stand-in against the game's own UI files (`tools/api/forever-ui.json`): every frame
    /// type and animation type of the game is a widget kind, every script that an XML file of
    /// the game puts on a kind is a script of that kind, every hand-written template is a
    /// template of the game without a field of its own, and every call of a widget method with
    /// written-out arguments in the game's Lua code is accepted.
    #[test]
    fn the_stand_in_agrees_with_the_games_ui_files() {
        let mut snapshot: serde_json::Value = serde_json::from_str(SNAPSHOT).unwrap();
        with_ui_names(&mut snapshot).unwrap();
        let problems = ui_check(&snapshot).unwrap();
        assert!(problems.is_empty(), "{} differences:\n{}", problems.len(), problems.join("\n"));
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
