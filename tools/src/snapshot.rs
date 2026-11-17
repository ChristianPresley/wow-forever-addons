//! Builds the API snapshot: a list of what the game client gives an addon.
//!
//! Blizzard ships the documentation of the game's Lua API as Lua files
//! (`Interface/AddOns/Blizzard_APIDocumentationGenerated` in the UI source). This module runs
//! those files and writes what they say to one JSON file, which `cargo dev test` uses to build
//! its stand-in for the game. The snapshot is in the repository, so the tests need no copy of
//! the UI source.
//!
//! The JSON:
//!
//! ```text
//! namespaces  { "C_Item": { "GetItemInfo": SPEC, ... }, ... }
//! globals     { "UnitName": SPEC, ... }
//! widgets     { "SimpleFrameAPI": { "objectType": "", "methods": { "SetShown": SPEC, ... } }, ... }
//! events      { "PLAYER_LOGIN": "", "CHAT_MSG_ADDON": "sss...", ... }   the payload
//! eventFlags  { "UNIT_SPELLCAST_START": "R", ... }   only the events that have a flag
//! enums       { "BagIndex": { "Backpack": 0, ... }, ... }
//! enumMeta    { "BagIndex": [numValues, minValue, maxValue], ... }
//! constants   { "AuctionConstants": { "DEFAULT_AUCTION_PRICE_MULTIPLIER": 1.5 }, ... }
//! structures  { "ContainerItemInfo": { "stackCount": "n", "quality": "n?", ... }, ... }
//! secretFields { "DamageMeterCombatSource": { "totalAmount": "S", ... }, ... }   S: always
//!             secret, R: secret under a restriction
//! ```
//!
//! SPEC is `"returns|arguments|flags"`. Each value is one letter:
//! `n` number, `s` string, `b` boolean, `t` table, `f` function, `o` object (a frame, a region
//! or a userdata with methods), `a` any value. After the letter, `?` marks a value that can be
//! nil (for an argument: one that can be left out), `*` a list of zero or more values, and
//! `{Name}` the structure of a table. The flags:
//! `T`, `U`, `N`: a secret value as an argument is allowed for addon code, allowed for the
//! game's own code only, or never allowed. `C`: the results are secret in a fight. `S`: the
//! results are always secret. `R`: the results can be secret under another restriction.
//! `M`: the function can return nothing. `P`: protected, addon code cannot call it in a fight.
//! `A`: the results are secret when the object has a secret aspect (a text or a colour that was
//! set from a secret value). `H`: the function has restrictions that the documentation does
//! not describe further. For an event, in `eventFlags`: `S` the payload is secret, `R` it can
//! be secret under a restriction, `H` as above.

use std::fs;
use std::path::Path;

use mlua::{Lua, LuaOptions, LuaSerdeExt, StdLib};

/// Runs every documentation file, more than once: a file can calculate a constant from an
/// enumeration or a constant of another file, so the values of one pass feed the next.
const BUILD: &str = r#"
local FILES = ...   -- { { name = "...", run = function } }

-- A name that is not known yet. It stays a table through arithmetic and indexing, so a value
-- made from it is not taken for a number.
local unknown
unknown = setmetatable({}, {
  __index = function() return unknown end,
  __add = function() return unknown end, __sub = function() return unknown end,
  __mul = function() return unknown end, __div = function() return unknown end,
  __unm = function() return unknown end,
})

local function lookup(known)
  return setmetatable({}, { __index = function(_, key)
    local value = known[key]
    if value == nil then
      return unknown
    end
    if type(value) == "table" then
      return setmetatable({}, { __index = function(_, field)
        local inner = value[field]
        if inner == nil then return unknown end
        return inner
      end })
    end
    return value
  end })
end

local DOCS, failed
local enums, enumMeta, constants = {}, {}, {}

local function runAll()
  DOCS, failed = {}, {}
  APIDocumentation = { AddDocumentationTable = function(_, doc) DOCS[#DOCS + 1] = doc end }
  local enumView = {}
  for name, fields in pairs(enums) do
    enumView[name] = fields
  end
  for name, meta in pairs(enumMeta) do
    enumView[name .. "Meta"] = { NumValues = meta[1], MinValue = meta[2], MaxValue = meta[3] }
  end
  Enum = lookup(enumView)
  Constants = lookup(constants)
  -- A file can name a global of the game that the documentation does not define (a default of
  -- `MAX_RAID_MARKERS`). While the files run, such a name is `unknown`, not nil, so that the
  -- field is seen to be there.
  setmetatable(_G, { __index = function() return unknown end })
  for _, file in ipairs(FILES) do
    local ok, err = pcall(file.run)
    if not ok then
      failed[#failed + 1] = file.name .. ": " .. tostring(err)
    end
  end
  setmetatable(_G, nil)
end

-- Enumerations and constants of the files as they are now. Returns the number of values that
-- are new or changed, and the constants that have no value yet.
local function collect()
  local changed, unresolved = 0, {}
  for _, doc in ipairs(DOCS) do
    for _, entry in ipairs(doc.Tables or {}) do
      if entry.Type == "Enumeration" then
        local fields = enums[entry.Name] or {}
        for _, field in ipairs(entry.Fields or {}) do
          if type(field.EnumValue) == "number" and fields[field.Name] ~= field.EnumValue then
            fields[field.Name] = field.EnumValue
            changed = changed + 1
          end
        end
        enums[entry.Name] = fields
        if type(entry.NumValues) == "number" then
          enumMeta[entry.Name] = { entry.NumValues, entry.MinValue or 0, entry.MaxValue or 0 }
        end
      elseif entry.Type == "Constants" then
        local values = constants[entry.Name] or {}
        for _, value in ipairs(entry.Values or {}) do
          local found = value.Value
          -- A constant of an enumeration type can name the field of the enumeration.
          if type(found) == "string" and enums[value.Type] and enums[value.Type][found] ~= nil then
            found = enums[value.Type][found]
          end
          local kind = type(found)
          if kind == "number" or kind == "string" or kind == "boolean" then
            if values[value.Name] ~= found then
              values[value.Name] = found
              changed = changed + 1
            end
          else
            unresolved[#unresolved + 1] = entry.Name .. "." .. tostring(value.Name)
          end
        end
        constants[entry.Name] = values
        -- The documentation names three tables of this client with the suffix _Camelot. The
        -- game's own code reads them without it, and never with it:
        -- Constants.PetConsts (Blizzard_StableUI/Camelot/Blizzard_StableUI.lua),
        -- Constants.LevelConstsExposed (Blizzard_Game/Mainline/EventImplementation.lua),
        -- Constants.LootConsts (Blizzard_UIPanels_Game/Mainline/GroupLootFrame.lua).
        -- The documentation's own values name Constants.PetConsts too. So the table is also
        -- there under the name without the suffix.
        local short = entry.Name:match("^(.+)_Camelot$")
        if short then
          local alias = constants[short] or {}
          for key, value in pairs(values) do
            alias[key] = value
          end
          constants[short] = alias
        end
      end
    end
  end
  return changed, unresolved
end

local unresolved
for _ = 1, 6 do
  runAll()
  local changed
  changed, unresolved = collect()
  if changed == 0 then
    break
  end
end
table.sort(unresolved)

---------------------------------------------------------------------------------------------------
-- Kinds of values

local BASIC = {
  number = "n", luaIndex = "n", time_t = "n", fileID = "n", BigUInteger = "n", BigInteger = "n",
  WOWMONEY = "n", size_t = "n", uiMapID = "n", SingleColorValue = "n", normalizedValue = "n",
  uiUnit = "n", Seconds = "n", FrameTime = "n", size = "n", ArtifactTiers = "n", SoundHandle = "n",
  uiFontHeight = "n", Milliseconds = "n", EncounterTimelineEventID = "n", VoiceChatID = "n",
  -- Enumerations that the documentation uses and does not define.
  AccountStoreState = "n", AccountStoreCategoryType = "n", AccountStoreItemStatus = "n",
  AccountStoreItemMode = "n", AccountStoreItemFlag = "n", AccountStoreTransactionResult = "n",
  StoreError = "n", ConnectionIptype = "n", ConnectionProtocol = "n", AnimationDataEnum = "n",
  GameMode = "n", GameRule = "n", PurchaseHouseDisabledReason = "n", InvalidPlotScreenshotReason = "n",
  HouseSettingFlags = "n", PartyPlaylistEntry = "n", PreferredPlaySettingsStatus = "n",
  NeighborhoodType = "n", NeighborhoodOwnerType = "n", ResidentType = "n",
  CachedRewardType = "n", WeeklyRewardChestThresholdType = "n",
  ItemCreationContext = "n", ItemSoundType = "n", Vocalerrorsounds = "n",
  bool = "b",
  string = "s", cstring = "s", stringView = "s", WOWGUID = "s", textureAtlas = "s", FramePoint = "s",
  TBFFlags = "s", JustifyHorizontal = "s", JustifyVertical = "s", DrawLayer = "s", textureKit = "s",
  ClubId = "s", Orientation = "s", BlendMode = "s", ClubStreamId = "s", CurveType = "s",
  DiscordMemberOpaqueID = "s", FrameStrata = "s", InsertMode = "s", KStringDiscordUserName = "s",
  LoopType = "s", SimpleButtonStateToken = "s", SmoothingType = "s", UnitToken = "s",
  UnitTokenVariant = "s", UnitTokenPvPRestrictedForAddOns = "s", UnitTokenRestrictedForAddOns = "s",
  UnitTokenNamePlate = "s", ScriptTypeName = "s", HTMLTextType = "s", AuraFilters = "s",
  FilterMode = "s", MouseButton = "s", ClickButton = "s",
  SendChatMessageType = "s",   -- the documentation: "Chat type string ('SAY', 'EMOTE', etc.)"
  -- The documentation defines UnitTokenType as an enumeration, and the game takes the unit
  -- name: Frame:RegisterUnitEvent("UNIT_FLAGS", "pet") in
  -- Blizzard_ActionBar/Shared/ActionButton.lua, and 130 more calls of the game's code with a
  -- text, none with a number. This table is read before the documented kinds.
  UnitTokenType = "s",
  -- A wrong kind here makes the stand-in refuse a correct call. A name that is not surely a
  -- number or a string stays out of this table, and counts as "any value".
  kstringLfgListApplicant = "s", kstringLfgListSearch = "s", kstringLfgListChat = "s",
  kstringAuroraName = "s", kstringClubMessage = "s",
  table = "t", TooltipData = "t", UiMapPoint = "t", uiRect = "t", AuraData = "t",
  TooltipComparisonItem = "t",
  LuaFunctionReference = "f", ["function"] = "f",
  LuaValueReference = "a", LuaValueVariant = "a", any = "a", LuaCurveEvaluatedResult = "a",
}

local kinds, structures, secretFields = {}, {}, {}
local objects = {}  -- names of object types: each script object, with and without "API"
for _, doc in ipairs(DOCS) do
  if doc.Type == "ScriptObject" then
    local name = doc.Name
    objects[name] = true
    objects[(name:gsub("API$", ""))] = true
    objects[(name:gsub("^FrameAPI", ""))] = true
    objects[(name:gsub("^Simple", ""):gsub("API$", ""))] = true
    -- DurationTextBindingObjectAPI is the object type DurationTextBinding.
    objects[(name:gsub("ObjectAPI$", ""))] = true
  end
  for _, entry in ipairs(doc.Tables or {}) do
    if entry.Type == "Enumeration" then
      kinds[entry.Name] = "n"
    elseif entry.Type == "Structure" then
      kinds[entry.Name] = "t{" .. entry.Name .. "}"
    elseif entry.Type == "CallbackType" then
      kinds[entry.Name] = "f"
    end
  end
end
for _, name in ipairs({
  "ScriptRegion", "CScriptObject", "FrameScriptObject", "NamePlateFrame", "SimpleWindow", "CooldownFrame",
  "SimplePathAnim",
}) do
  objects[name] = true
end

local unknownTypes = {}

-- Where the game takes more than its documentation says. Each line needs a call of the game's
-- own code as the proof. The key is the function, the value the code of an argument by its
-- position. An entry for a function that the documentation does not have stops the tool.
local WIDER_ARGUMENTS = {
  -- frame:SetAttribute("checkselfcast", true), and tables and numbers as the value:
  -- Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua. Documented as a text.
  ["SimpleFrameAPI:SetAttribute"] = { [2] = "a" },
  ["SimpleFrameAPI:SetAttributeNoHandler"] = { [2] = "a" },
  -- texture:SetTexture(path, true, true): Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua.
  -- The wrap modes are documented as texts.
  ["SimpleTextureBaseAPI:SetTexture"] = { [2] = "a?", [3] = "a?" },
}
-- The same for what a function returns.
local WIDER_RESULTS = {
  -- An attribute has the value that SetAttribute got, of any kind, or nil:
  -- `if not frame:GetAttribute("UIPanelLayout-defined") then` in
  -- Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua. Documented as a text.
  ["SimpleFrameAPI:GetAttribute"] = { [1] = "a?" },
}
local widerUsed = {}

-- The letter of a documented value, without the marks for nil and lists.
local function letter(value)
  local kind = BASIC[value.Type] or kinds[value.Type]
  if kind then
    return kind
  end
  if value.Mixin then
    return "t"
  end
  if objects[value.Type] then
    return "o"
  end
  unknownTypes[value.Type] = (unknownTypes[value.Type] or 0) + 1
  return "a"
end

-- Codes of a list of values. `optional`: a value with a default counts as one that can be nil.
local function codes(list, optional, wider)
  local out = {}
  for index, value in ipairs(list or {}) do
    local code = letter(value)
    if value.StrideIndex then
      code = code .. "*"
    elseif value.Nilable or (optional and value.Default ~= nil) then
      code = code .. "?"
    end
    if wider and wider[index] then
      code = wider[index]
    end
    out[#out + 1] = code
  end
  return table.concat(out)
end

for _, doc in ipairs(DOCS) do
  for _, entry in ipairs(doc.Tables or {}) do
    if entry.Type == "Structure" then
      local fields = {}
      for _, field in ipairs(entry.Fields or {}) do
        local code = letter(field)
        if field.Nilable then
          code = code .. "?"
        end
        fields[field.Name] = code
        if field.SecretValue or field.ConditionalSecret then
          secretFields[entry.Name] = secretFields[entry.Name] or {}
          secretFields[entry.Name][field.Name] = field.SecretValue and "S" or "R"
        end
      end
      structures[entry.Name] = fields
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Functions and events

local out = {
  namespaces = {}, globals = {}, widgets = {}, events = {}, enums = enums, enumMeta = enumMeta,
  constants = constants, structures = structures, secretFields = secretFields, eventFlags = {},
}
local secureOnly = 0

local SECRET_ARGUMENTS = { AllowedWhenTainted = "T", AllowedWhenUntainted = "U", NotAllowed = "N" }

-- True if the entry has a `SecretWhen...` or `SecretIn...` key other than SecretWhenInCombat.
local function secretUnderRestriction(entry)
  for key in pairs(entry) do
    if type(key) == "string" and (key:find("^SecretWhen") or key:find("^SecretIn")) and key ~= "SecretWhenInCombat" then
      return true
    end
  end
  return false
end

local function spec(fn, key)
  local wider = key and WIDER_ARGUMENTS[key]
  local widerResults = key and WIDER_RESULTS[key]
  if wider or widerResults then
    widerUsed[key] = true
  end
  local flags = SECRET_ARGUMENTS[fn.SecretArguments] or ""
  if fn.SecretWhenInCombat then
    flags = flags .. "C"
  end
  if fn.SecretReturns then
    flags = flags .. "S"
  end
  if secretUnderRestriction(fn) then
    flags = flags .. "R"
  end
  if fn.MayReturnNothing then
    flags = flags .. "M"
  end
  if fn.IsProtectedFunction then
    flags = flags .. "P"
  end
  if fn.SecretReturnsForAspect then
    flags = flags .. "A"
  end
  if fn.HasRestrictions then
    flags = flags .. "H"
  end
  return codes(fn.Returns, false, widerResults) .. "|" .. codes(fn.Arguments, true, wider) .. "|" .. flags
end

local function eventFlags(event)
  local flags = ""
  if event.SecretPayloads then
    flags = flags .. "S"
  end
  if secretUnderRestriction(event) then
    flags = flags .. "R"
  end
  if event.HasRestrictions then
    flags = flags .. "H"
  end
  return flags
end

for _, doc in ipairs(DOCS) do
  if doc.Environment == "SecureOnly" then
    -- For the game's own code only: an addon cannot call these.
    secureOnly = secureOnly + #(doc.Functions or {})
  else
    if doc.Type == "ScriptObject" and not out.widgets[doc.Name] then
      -- Also a script object without methods of its own (SimpleMaskTextureAPI) is a kind.
      out.widgets[doc.Name] = { objectType = doc.ObjectType or "", methods = {} }
    end
    for _, fn in ipairs(doc.Functions or {}) do
      if type(fn.Name) == "string" then
        if fn.Environment == "SecureOnly" then
          secureOnly = secureOnly + 1
        elseif doc.Type == "ScriptObject" then
          local object = out.widgets[doc.Name]
          if not object then
            object = { objectType = doc.ObjectType or "", methods = {} }
            out.widgets[doc.Name] = object
          end
          object.methods[fn.Name] = spec(fn, doc.Name .. ":" .. fn.Name)
        else
          -- A function can name its own namespace; "" is the global one.
          local namespace = fn.Namespace
          if namespace == nil then
            namespace = doc.Namespace
          end
          if namespace == nil or namespace == "" then
            out.globals[fn.Name] = spec(fn, fn.Name)
          else
            out.namespaces[namespace] = out.namespaces[namespace] or {}
            out.namespaces[namespace][fn.Name] = spec(fn, namespace .. "." .. fn.Name)
          end
        end
      end
    end
  end
  for _, event in ipairs(doc.Events or {}) do
    if type(event.LiteralName) == "string" then
      out.events[event.LiteralName] = codes(event.Payload, false)
      local flags = eventFlags(event)
      if flags ~= "" then
        out.eventFlags[event.LiteralName] = flags
      end
    end
  end
end

local unknownList = {}
for name, count in pairs(unknownTypes) do
  unknownList[#unknownList + 1] = name .. " (" .. count .. ")"
end
table.sort(unknownList)

local widerList = {}
for _, list in ipairs({ WIDER_ARGUMENTS, WIDER_RESULTS }) do
  for key in pairs(list) do
    if not widerUsed[key] then
      error("WIDER_ARGUMENTS or WIDER_RESULTS names " .. key .. ", which the documentation does not have")
    end
    widerList[#widerList + 1] = key
  end
end
table.sort(widerList)

return out, failed, unresolved, unknownList, secureOnly, widerList
"#;

fn count_map(value: Option<&serde_json::Value>) -> usize {
    value.and_then(|value| value.as_object()).map(|map| map.len()).unwrap_or(0)
}

fn count_inner(value: Option<&serde_json::Value>, key: Option<&str>) -> usize {
    value
        .and_then(|value| value.as_object())
        .map(|map| {
            map.values()
                .map(|inner| match key {
                    Some(key) => count_map(inner.get(key)),
                    None => count_map(Some(inner)),
                })
                .sum()
        })
        .unwrap_or(0)
}

/// Reads the documentation files in `docs_dir` and writes the snapshot to `out`.
/// Returns the lines that say what the snapshot holds and what it could not take.
pub fn build(docs_dir: &Path, out: &Path, source_note: &str) -> Result<Vec<String>, String> {
    let mut files: Vec<_> = fs::read_dir(docs_dir)
        .map_err(|error| format!("Cannot read {}: {error}", docs_dir.display()))?
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|extension| extension == "lua"))
        .collect();
    files.sort();
    if files.is_empty() {
        return Err(format!("{} has no .lua files. Give the Blizzard_APIDocumentationGenerated folder.", docs_dir.display()));
    }

    // The documentation files come from outside this repository. They run with the table, string
    // and math libraries only: no file, OS, package or debug access.
    let lua = Lua::new_with(StdLib::TABLE | StdLib::STRING | StdLib::MATH, LuaOptions::default()).map_err(|error| error.to_string())?;
    let run = || -> mlua::Result<(serde_json::Value, Vec<String>, Vec<String>, Vec<String>, i64, Vec<String>)> {
        // The base library has functions that read files and load binary code.
        for name in ["dofile", "loadfile", "load", "loadstring", "require", "collectgarbage"] {
            lua.globals().set(name, mlua::Value::Nil)?;
        }
        let list = lua.create_table()?;
        for file in &files {
            let name = file.file_name().unwrap_or_default().to_string_lossy().into_owned();
            let source = fs::read(file).map_err(mlua::Error::external)?;
            let entry = lua.create_table()?;
            entry.set("name", name.as_str())?;
            entry.set("run", lua.load(&source[..]).set_name(format!("={name}")).into_function()?)?;
            list.push(entry)?;
        }
        let (table, failed, unresolved, unknown, secure_only, wider): (mlua::Value, Vec<String>, Vec<String>, Vec<String>, i64, Vec<String>) =
            lua.load(BUILD).set_name("=build").call(list)?;
        Ok((lua.from_value(table)?, failed, unresolved, unknown, secure_only, wider))
    };
    let (mut snapshot, failed, unresolved, unknown, secure_only, wider) = run().map_err(|error| error.to_string())?;

    // A file that does not run would take a part of the API away without a word.
    if !failed.is_empty() {
        return Err(format!("{} documentation file(s) did not run, so no snapshot was written:\n  {}", failed.len(), failed.join("\n  ")));
    }

    let mut lines = vec![format!(
        "{} files: {} namespaces with {} functions, {} global functions, {} widget kinds with {} methods, {} events, {} enumerations, {} structures, {} constants",
        files.len(),
        count_map(snapshot.get("namespaces")),
        count_inner(snapshot.get("namespaces"), None),
        count_map(snapshot.get("globals")),
        count_map(snapshot.get("widgets")),
        count_inner(snapshot.get("widgets"), Some("methods")),
        count_map(snapshot.get("events")),
        count_map(snapshot.get("enums")),
        count_map(snapshot.get("structures")),
        count_inner(snapshot.get("constants"), None),
    )];
    lines.push(format!("left out: {secure_only} functions that only the game's own code can call"));
    if !unresolved.is_empty() {
        lines.push(format!(
            "{} constants have no value in the documentation (they name something that it does not define): {}",
            unresolved.len(),
            unresolved.join(", ")
        ));
    }
    if !unknown.is_empty() {
        lines.push(format!("{} kinds of values are not known and count as \"any value\": {}", unknown.len(), unknown.join(", ")));
    }
    if !wider.is_empty() {
        lines.push(format!("{} functions take more than the documentation says (WIDER_ARGUMENTS in snapshot.rs): {}", wider.len(), wider.join(", ")));
    }
    if let Some(map) = snapshot.as_object_mut() {
        map.insert("widerArguments".to_string(), serde_json::json!(wider));
        map.insert("source".to_string(), serde_json::Value::String(source_note.to_string()));
        map.insert("unresolvedConstants".to_string(), serde_json::json!(unresolved));
    }
    if let Some(parent) = out.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let text = serde_json::to_string_pretty(&snapshot).map_err(|error| error.to_string())?;
    fs::write(out, text + "\n").map_err(|error| format!("Cannot write {}: {error}", out.display()))?;
    Ok(lines)
}

/// The differences between two snapshots, one line for each name that was added, removed or
/// changed, for the message of `cargo dev api-snapshot --check`.
pub fn differences(old: &serde_json::Value, new: &serde_json::Value) -> Vec<String> {
    fn walk(path: &str, old: Option<&serde_json::Value>, new: Option<&serde_json::Value>, depth: usize, out: &mut Vec<String>) {
        match (old, new) {
            (Some(a), Some(b)) if a == b => {}
            (Some(serde_json::Value::Object(a)), Some(serde_json::Value::Object(b))) if depth < 3 => {
                let keys: std::collections::BTreeSet<&String> = a.keys().chain(b.keys()).collect();
                for key in keys {
                    let inner = if path.is_empty() { key.clone() } else { format!("{path}.{key}") };
                    walk(&inner, a.get(key), b.get(key), depth + 1, out);
                }
            }
            (Some(a), Some(b)) => out.push(format!("changed  {path}: {a} -> {b}")),
            (None, Some(_)) => out.push(format!("added    {path}")),
            (Some(_), None) => out.push(format!("removed  {path}")),
            (None, None) => {}
        }
    }
    let mut out = Vec::new();
    for section in ["namespaces", "globals", "widgets", "events", "eventFlags", "enums", "enumMeta", "constants", "structures", "secretFields"] {
        walk(section, old.get(section), new.get(section), 0, &mut out);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn differences_name_what_was_added_removed_and_changed() {
        let old = serde_json::json!({ "namespaces": { "C_A": { "Keep": "n||", "Drop": "||", "Edit": "s||" } }, "events": { "ONE": "" } });
        let new = serde_json::json!({ "namespaces": { "C_A": { "Keep": "n||", "Edit": "n||", "New": "||" }, "C_B": { "F": "||" } }, "events": { "ONE": "" } });
        assert_eq!(differences(&old, &new), [
            "removed  namespaces.C_A.Drop",
            "changed  namespaces.C_A.Edit: \"s||\" -> \"n||\"",
            "added    namespaces.C_A.New",
            "added    namespaces.C_B",
        ]);
        assert!(differences(&old, &old).is_empty());
    }
}