
---------------------------------------------------------------------------------------------------
-- Part 4: the world
--
-- One character with a few items, two quests, an auction house, mail, a fight, and, when the
-- driver or a scenario says so, a party. Each function here takes the place of the stand-in
-- from the snapshot, to give the code of an addon data to work with.
--
-- `set` and `setGlobal` keep the documented argument check, and fail for a name that the
-- snapshot does not have. A function that Blizzard's documentation lacks gets, as its third
-- argument, the file of the game's own UI code that uses it. Do not add a name without one:
-- a missing name is what the test is for.
--
-- H.world switches: secret (in a fight), group ("party" or "raid"), dead, alt, shift, sayNo,
-- cvars. H.did lists what the addon asked the game to do: accepted quests, sent messages.

local set, setGlobal = H.set, H.setGlobal

H.did = {}
local function did(what, ...)
  H.did[#H.did + 1] = { what, ... }
end
-- The number of entries of H.did of one kind.
function H.count(what)
  local n = 0
  for _, entry in ipairs(H.did) do
    if entry[1] == what then
      n = n + 1
    end
  end
  return n
end

-- A value that is secret in a fight.
local function hidden(value)
  return H.world.secret and H.secret(value) or value
end

local ITEMS = {
  [2589] = { name = "Linen Cloth", quality = 1, class = 7, sell = 13, icon = 132889 },
  [769] = { name = "Chunk of Boar Meat", quality = 1, class = 7, sell = 4, icon = 133970 },
  [117] = { name = "Tough Jerky", quality = 1, class = 0, sell = 1, icon = 134004 },
  [2211] = { name = "Bent Large Shield", quality = 0, class = 4, sell = 7, icon = 134955 },
  [6948] = { name = "Hearthstone", quality = 1, class = 15, sell = 0, icon = 134414 },
  -- Two items of the item class Quest (12). `bind` is the bind type of the item: 4 is a quest
  -- item (the tooltip says "Quest Item"), 1 binds when picked up (the tooltip says "Soulbound").
  -- The book is of the class Quest and is not for a quest: a collectible.
  [5001] = { name = "Gnoll Paw", quality = 1, class = 12, sell = 0, icon = 133721, bind = 4 },
  [5002] = { name = "Baxtan: On Destructive Magics", quality = 1, class = 12, sell = 0, icon = 133733, bind = 1 },
  -- The item that the quest 176 gives to use. It is not in the bags.
  -- A gem of the item class Gem (Enum.ItemClass.Gem = 3 in the snapshot). Its ID and icon are
  -- made up: no file of the game in the sources gives a gem's ID here, so the icon is that of
  -- Tough Jerky. It is in bag 0, slot 6.
  [5004] = { name = "Test Gem", quality = 1, class = 3, sell = 0, icon = 134004 },
  [5003] ={ name = "Stormwind Hunting Horn", quality = 1, class = 12, sell = 0, icon = 133706, bind = 4 },
}
H.items = ITEMS
local BAG_CONTENTS = {
  [0] = { size = 16, slots = { [1] = { 6948, 1 }, [2] = { 2589, 12 }, [3] = { 117, 5 }, [5] = { 2211, 1 }, [6] = { 5004, 1 } } },
  [1] = { size = 6, slots = { [1] = { 769, 8 }, [2] = { 2589, 20 }, [3] = { 5001, 3 }, [4] = { 5002, 1 } } },
}
local function itemLink(itemID)
  return "|cffffffff|Hitem:" .. itemID .. "::::::::20:::::|h[" .. ITEMS[itemID].name .. "]|h|r"
end
H.itemLink = itemLink

---------------------------------------------------------------------------------------------------
-- The character and the group

local GROUP_UNITS = { party1 = true, raid1 = true, raid2 = true }
-- The NPC of the world (H.world.npc): the unit "npc" that the player talks to, and in a fight
-- the player's target too. Out of a fight the player has no target.
local function isNpc(unit)
  return H.world.npc ~= nil and (unit == "npc" or (unit == "target" and H.world.secret == true))
end
local function unitExists(unit)
  return unit == "player" or (H.world.group ~= nil and GROUP_UNITS[unit] == true) or isNpc(unit)
end
setGlobal("UnitExists", unitExists)
-- UnitDocumentation.lua: the name can be secret for a unit that is not the player's or in the
-- group, where the game hides who a unit is. Here: the NPC, in a fight.
-- The game client (tools/ingame-probe/answers.txt): two values for the player, the name and
-- the realm; the name and nil for an NPC; nil and nil for a unit that is not there.
setGlobal("UnitName", function(unit)
  if unit == "player" then
    return "Tester", "TestRealm"
  elseif unit == "raid1" and H.world.group == "raid" then
    return "Tester", nil
  elseif H.world.group and (unit == "party1" or unit == "raid2") then
    return "Friend", nil
  elseif isNpc(unit) then
    return hidden(H.world.npc), nil
  end
  return nil, nil
end)
H.allowNil("UnitName", "The game gives no name for a unit that does not exist, and no realm for a unit of the player's own realm: Blizzard_FriendsFrame/Mainline/FriendsFrame.lua tests the realm with `if server and`.")
-- The realm can be empty text on a server whose name the game does not give (Forever Bags:
-- the realm then has no key). "s||" in the documentation allows an empty string.
setGlobal("GetRealmName", function() return H.world.realmEmpty and "" or "TestRealm" end)
setGlobal("GetNormalizedRealmName", function() return H.world.realmEmpty and "" or "TestRealm" end)
-- For a unit that does not exist the game gives nothing.
setGlobal("UnitClass", function(unit)
  if unitExists(unit) then
    return "Warrior", "WARRIOR", 1
  end
end)
H.allowNil("UnitClass", "The game gives no class for a unit that does not exist: Blizzard_InspectUI/Mainline/InspectPaperDollFrame.lua tests the result with `if (not class) then`.")
setGlobal("UnitLevel", function(unit) return unitExists(unit) and 20 or 0 end)
setGlobal("UnitFactionGroup", function(unit)
  if unitExists(unit) then
    return "Alliance", "Alliance"
  end
end)
H.allowNil("UnitFactionGroup", "The game gives no faction for a unit that does not exist or has none: Blizzard_Calendar/Mainline/Blizzard_Calendar.lua tests the result with `if ( factionGroup and`.")
setGlobal("UnitGUID", function(unit)
  if isNpc(unit) then
    return "Creature-0-1-0-0-240-0000000001"
  end
  return unitExists(unit) and "Player-1-00000001" or nil
end)
-- The game client (tools/ingame-probe/answers.txt): out of a fight nil, in a fight a plain
-- number for the player, alone and with its target.
setGlobal("UnitThreatSituation", function(unit)
  if H.world.secret and unit == "player" then
    return 0
  end
  return nil
end)
-- Nobody casts a spell in this world: the game client gives nothing then (answers.txt).
setGlobal("UnitCastingInfo", function() end)
H.allowNil("UnitCastingInfo", "The game client gives nothing for a unit that casts no spell: tools/ingame-probe/answers.txt, the case UnitCastingInfo('target').")
-- The player has one buff. The game client (answers.txt): out of a fight its fields are plain;
-- in a fight the call is an error for addon code, with this text.
set("C_UnitAuras", "GetAuraDataByIndex", function(unit, index, filter)
  if unit ~= "player" or index ~= 1 or (filter ~= nil and not filter:find("HELPFUL", 1, true)) then
    return nil
  end
  if H.world.secret then
    fail("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by an addon")
  end
  return { name = "Well Fed", icon = 136000, applications = 0, duration = 1800, expirationTime = H.now + 900, spellId = 19705, isHelpful = true, isHarmful = false, auraInstanceID = 1 }
end)
setGlobal("UnitAffectingCombat", function() return H.world.secret end)
setGlobal("InCombatLockdown", function() return H.world.secret end)
setGlobal("UnitIsDeadOrGhost", function() return H.world.dead == true end)
setGlobal("GetMoney", function() return 123456 end)
setGlobal("IsInInstance", function() return false, "none" end)
setGlobal("GetPlayerFacing", function() return 1.0 end)
setGlobal("UnitPosition", function(unit)
  if unitExists(unit) then
    -- The player stands where GetPlayerMapPosition says (0.42, 0.65), in the yards of GetWorldPosFromMapPos.
    return unit == "player" and 420 or 480, unit == "player" and 650 or 690, 0, 0
  end
end)
-- H.world.zone: the player is in another zone (Westfall, map 52), for the code that asks which quests are of this zone.
setGlobal("GetZoneText", function() return H.world.zone or "Elwynn Forest" end)
-- The game gives no position for a unit that does not exist, and none in an instance. The
-- game's own UI code does not show this (it asks for units that exist); it is how the client
-- is known to behave, and the addons test the result before they use it.
H.allowNil("UnitPosition", "The client gives no position for a unit that does not exist or in an instance; not shown by the game's own UI code.")
setGlobal("GetRealZoneText", function() return H.world.zone or "Elwynn Forest" end)
setGlobal("GetSubZoneText", function() return "Goldshire" end)
setGlobal("GetLocale", function() return "enUS" end)
-- Ambiguate takes the realm off a name of the player's own realm, and keeps another realm.
setGlobal("Ambiguate", function(name, context)
  local short, realm = name:match("^([^-]+)-(.+)$")
  if short and (realm == "TestRealm" or context == "short") then
    return short
  end
  return name
end)
setGlobal("IsAltKeyDown", function() return H.world.alt == true end)
setGlobal("IsShiftKeyDown", function() return H.world.shift == true end)

setGlobal("IsInGroup", function() return H.world.group ~= nil end, "Blizzard_CooldownBroadcaster/Blizzard_CooldownBroadcaster.lua")
setGlobal("IsInRaid", function() return H.world.group == "raid" end, "Blizzard_CompactRaidFrames/Blizzard_CompactRaidFrameContainer.lua")
setGlobal("GetNumSubgroupMembers", function() return H.world.group and 1 or 0 end, "Blizzard_CompactRaidFrames/Blizzard_CompactRaidFrameContainer.lua")
setGlobal("GetNumGroupMembers", function() return H.world.group and 2 or 0 end, "Blizzard_CompactRaidFrames/Blizzard_CompactRaidFrameContainer.lua")
UNKNOWNOBJECT = "Unknown" -- Blizzard_RaidUI/Mainline/Blizzard_RaidUI.lua
setGlobal("GetInventoryItemID", function(_, slot) return slot == 16 and 2211 or nil end, "Blizzard_BoostTutorial/Blizzard_TutorialLogic.lua")
setGlobal("IsModifiedClick", function() return false end, "Blizzard_ArtifactUI/Blizzard_ArtifactPowerButton.lua")
setGlobal("CanMerchantRepair", function() return true end, "Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua")

-- Settings of the game. H.world.cvars has the values; a name that is not there is not a CVar.
-- showQuestObjectivesInLog: the quest log shows the objectives under each quest. No file of the
-- game gives its default; the game client says "1" (tools/ingame-probe/answers.txt). A
-- scenario can set it to "0".
H.world.cvars = { damageMeterEnabled = "1", combinedBags = "1", showQuestObjectivesInLog = "1" }
-- The defaults are the values of a new character, which the world starts with.
local CVAR_DEFAULTS = { damageMeterEnabled = "1", combinedBags = "1", showQuestObjectivesInLog = "1" }
set("C_CVar", "GetCVarDefault", function(name) return CVAR_DEFAULTS[name] end)
set("C_CVar", "GetCVar", function(name) return H.world.cvars[name] end)
set("C_CVar", "SetCVar", function(name, value)
  H.world.cvars[name] = realTostring(value)
  did("cvar", name, realTostring(value))
  return true
end)
-- Blizzard_SharedXMLBase/CvarUtil.lua: the globals call C_CVar.
setGlobal("GetCVar", function(name) return C_CVar.GetCVar(name) end, "Blizzard_SharedXMLBase/CvarUtil.lua")
setGlobal("SetCVar", function(name, value, ...)
  -- CvarUtil.lua: a boolean becomes "1" or "0" first.
  if realType(value) == "boolean" then
    value = value and "1" or "0"
  end
  return C_CVar.SetCVar(name, value, ...)
end, "Blizzard_SharedXMLBase/CvarUtil.lua")
setGlobal("GetCVarBool", function(name) return C_CVar.GetCVar(name) == "1" end, "Blizzard_SharedXMLBase/CvarUtil.lua")

set("C_ChatInfo", "SendAddonMessage", function(prefix, text, channel)
  if #text > 255 then
    fail("SendAddonMessage: the text has more than 255 bytes")
  end
  did("addon message", prefix, text, channel)
  -- Enum.SendAddonMessageResult: 0 is Success. H.world.addonMessageResult gives another answer.
  return H.world.addonMessageResult or 0
end)
set("C_ChatInfo", "RegisterAddonMessagePrefix", function(prefix)
  did("prefix", prefix)
  return 0
end)
set("C_ChatInfo", "SendChatMessage", function(text, channel)
  did("chat", text, channel)
end)

-- The game's callbacks for its own frames (Blizzard_SharedXMLBase/GlobalCallbackRegistry.lua).
EventRegistry = { callbacks = {} }
function EventRegistry:RegisterCallback(event, fn, owner)
  if realType(event) ~= "string" or realType(fn) ~= "function" then
    fail("EventRegistry:RegisterCallback: (event, function, owner) is needed")
  end
  self.callbacks[#self.callbacks + 1] = { event = event, fn = fn, owner = owner }
end
function EventRegistry:TriggerEvent(event, ...)
  for _, callback in ipairs(self.callbacks) do
    if callback.event == event then
      callback.fn(callback.owner, ...)
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Maps

set("C_Map", "GetBestMapForUnit", function() return H.world.zone and 52 or 37 end)
set("C_Map", "GetMapInfo", function(mapID)
  if mapID == 37 then
    return { mapID = 37, name = "Elwynn Forest", mapType = Enum.UIMapType.Zone, parentMapID = 13, flags = 0 }
  elseif mapID == 52 then
    return { mapID = 52, name = "Westfall", mapType = Enum.UIMapType.Zone, parentMapID = 13, flags = 0 }
  elseif mapID == 13 then
    return { mapID = 13, name = "Eastern Kingdoms", mapType = Enum.UIMapType.Continent, parentMapID = 947, flags = 0 }
  elseif mapID == 947 then
    return { mapID = 947, name = "Azeroth", mapType = Enum.UIMapType.World, parentMapID = 0, flags = 0 }
  end
end)
set("C_Map", "GetMapChildrenInfo", function(mapID)
  if mapID == 13 then
    return {
      { mapID = 37, name = "Elwynn Forest", mapType = Enum.UIMapType.Zone, parentMapID = 13, flags = 0 },
      { mapID = 52, name = "Westfall", mapType = Enum.UIMapType.Zone, parentMapID = 13, flags = 0 },
    }
  elseif mapID == 947 then
    return { { mapID = 13, name = "Eastern Kingdoms", mapType = Enum.UIMapType.Continent, parentMapID = 947, flags = 0 } }
  end
  return {}
end)
-- The player, and the member of the group a little away. Nothing for a unit that is not there.
set("C_Map", "GetPlayerMapPosition", function(_, unit)
  if unit == "player" then
    return CreateVector2D(0.42, 0.65)
  elseif unitExists(unit) and not isNpc(unit) then
    return CreateVector2D(0.48, 0.69)
  end
end)
setGlobal("UnitIsUnit", function(a, b) return a == b or (a == "raid1" and b == "player") or (a == "player" and b == "raid1") end)
-- Where a zone is on the continent: Elwynn Forest the left half, Westfall the right half.
set("C_Map", "GetMapRectOnMap", function(mapID, onMapID)
  if onMapID == 13 and mapID == 37 then
    return 0, 0.5, 0, 1
  elseif onMapID == 13 and mapID == 52 then
    return 0.5, 1, 0, 1
  end
  return 0, 0, 0, 0
end)
-- The picture that lights a zone up under the pointer: on the continent, one for each half.
set("C_Map", "GetMapHighlightInfoAtPosition", function(mapID, x)
  if mapID == 13 then
    local left = x < 0.5
    return left and 9001 or 9002, "", 0.8, 0.9, 0.5, 1, left and 0 or 0.5, 0
  end
  -- On the map of a zone the game names the zone itself: a picture over the whole map.
  if mapID == 37 then
    return 9003, "", 1, 1, 1, 1, 0, 0
  end
  return 0, "", 0, 0, 0, 0, 0, 0
end)
-- Points of interest of Elwynn Forest: a town with a picture from the sheet of map icons, and an
-- abbey with an atlas. A graveyard, and a way to Westfall. Westfall has a dungeon entrance.
local AREA_POIS = {
  [101] = { areaPoiID = 101, name = "Goldshire", description = "Town", position = CreateVector2D(0.42, 0.64), textureIndex = 5 },
  [102] = { areaPoiID = 102, name = "Northshire Abbey", position = CreateVector2D(0.5, 0.42), atlasName = "poi-town" },
}
local function poiDefaults(info)
  for key, value in pairs({
    highlightVignettesOnHover = false, highlightWorldQuestsOnHover = false, isAlwaysOnFlightmap = false, isCurrentEvent = false,
    isLocked = false, isPrimaryMapForPOI = true, isSuppressible = false, shouldGlow = false,
  }) do
    if info[key] == nil then
      info[key] = value
    end
  end
  return info
end
set("C_AreaPoiInfo", "GetAreaPOIForMap", function(mapID) return mapID == 37 and { 101, 102 } or {} end)
set("C_AreaPoiInfo", "GetAreaPOIInfo", function(mapID, id)
  if mapID == 37 and AREA_POIS[id] then
    return poiDefaults(AREA_POIS[id])
  end
end)
set("C_Minimap", "GetPOITextureCoords", function(index) return index * 0.1, index * 0.1 + 0.1, 0.25, 0.5 end)
set("C_DeathInfo", "GetGraveyardsForMap", function(mapID)
  if mapID ~= 37 then
    return {}
  end
  return { { areaPoiID = 103, graveyardID = 1, isGraveyardSelectable = false, name = "Goldshire Graveyard", position = CreateVector2D(0.39, 0.6), textureIndex = 8 } }
end)
set("C_EncounterJournal", "GetDungeonEntrancesForMap", function(mapID)
  if mapID ~= 52 then
    return {}
  end
  return { { areaPoiID = 104, atlasName = "Dungeon", description = "Dungeon", journalInstanceID = 63, name = "The Deadmines", position = CreateVector2D(0.42, 0.72) } }
end)
set("C_Map", "GetMapLinksForMap", function(mapID)
  if mapID ~= 37 then
    return {}
  end
  return { { areaPoiID = 105, atlasName = "poi-door", linkedUiMapID = 52, name = "Westfall", position = CreateVector2D(0.05, 0.7) } }
end)
set("C_Map", "GetWorldPosFromMapPos", function(_, position) return 0, CreateVector2D(position.x * 1000, position.y * 1000) end)
set("C_Map", "GetUserWaypoint", function() return { uiMapID = 37, position = CreateVector2D(0.6, 0.6) } end)
-- The art of a map: layers of image tiles. The first layer is the whole map as one picture; a
-- second one is a finer picture for a closer look, which the map of the game fades to as the
-- player zooms in (Blizzard_MapCanvas/MapCanvas_ScrollContainerMixin.lua, AdjustDetailLayerAlpha).
--   Elwynn Forest (37): a finer layer of the same size, with the zoom numbers of the game:
--     the second layer starts at 2.5 times the scale of the first.
--   Westfall (52): a finer layer with twice the pixels and no zoom numbers.
--   The continent and the world: one layer.
-- Another map has no art.
local ZONE_LAYER = { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 1, maxScale = 2.5, additionalZoomSteps = 0 }
local PLAIN_LAYER = { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 0, maxScale = 0, additionalZoomSteps = 0 }
local MAP_ART = {
  [37] = { ZONE_LAYER, { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 2.5, maxScale = 4, additionalZoomSteps = 1 } },
  [52] = { PLAIN_LAYER, { layerWidth = 2004, layerHeight = 1336, tileWidth = 256, tileHeight = 256, minScale = 0, maxScale = 0, additionalZoomSteps = 0 } },
  [13] = { PLAIN_LAYER },
  [947] = { PLAIN_LAYER },
}
set("C_Map", "GetMapArtLayers", function(mapID)
  return MAP_ART[mapID] or {}
end)
set("C_Map", "GetMapArtLayerTextures", function(mapID, layerIndex)
  local layer = MAP_ART[mapID] and MAP_ART[mapID][layerIndex]
  local files = {}
  if layer then
    local count = math.ceil(layer.layerWidth / layer.tileWidth) * math.ceil(layer.layerHeight / layer.tileHeight)
    for index = 1, count do
      files[index] = mapID * 1000 + layerIndex * 100 + index
    end
  end
  return files
end)
-- One uncovered part of Elwynn Forest: 300 by 200 pixels, so two tiles wide and one tall.
set("C_MapExplorationInfo", "GetExploredMapTextures", function(mapID)
  if mapID ~= 37 then
    return {}
  end
  return { {
    textureWidth = 300, textureHeight = 200, offsetX = 100, offsetY = 50, fileDataIDs = { 370001, 370002 },
    isShownByMouseOver = false, isDrawOnTopLayer = false, hitRect = { left = 100, right = 400, top = 50, bottom = 250 },
  } }
end)
-- The map of a place of a map: on the continent, the left half is Elwynn Forest and the right
-- half Westfall. On a zone it is the zone itself.
set("C_Map", "GetMapInfoAtPosition", function(mapID, x)
  if mapID == 13 then
    return C_Map.GetMapInfo(x < 0.5 and 37 or 52)
  elseif mapID == 947 then
    return C_Map.GetMapInfo(13)
  end
  return C_Map.GetMapInfo(mapID)
end)
set("C_Map", "OpenWorldMap", function(mapID) did("open world map", mapID) end)

-- Key bindings (Blizzard_ActionBar/Shared/ActionButton.lua asks GetBindingKey;
-- Blizzard_GamepadSharedUtility/InputBindingStack/InputButtonBinding.lua sets an override
-- binding that clicks a button). The game refuses a change of bindings in a fight.
-- H.pressKey(key) presses a key: the override binding, or the action of the game.
local BINDING_FILE = "Blizzard_GamepadSharedUtility/InputBindingStack/InputButtonBinding.lua"
H.bindings = { TOGGLEWORLDMAP = { "M" } }
H.overrideBindings = {} -- [key] = { owner, button name }
setGlobal("GetBindingKey", function(action)
  if realType(action) ~= "string" then
    fail("GetBindingKey: the name of an action is needed")
  end
  return unpack(H.bindings[action] or {})
end, "Blizzard_ActionBar/Shared/ActionButton.lua")
local function bindingAllowed(name)
  if H.world.secret then
    fail(name .. ": the game refuses a change of key bindings in a fight (blocked action)")
  end
end
setGlobal("SetOverrideBindingClick", function(owner, _, key, buttonName)
  bindingAllowed("SetOverrideBindingClick")
  if not H.isWidget(owner) or realType(key) ~= "string" or realType(buttonName) ~= "string" then
    fail("SetOverrideBindingClick: an owner frame, a key and the name of a button are needed")
  end
  if not H.isWidget(_G[buttonName]) then
    fail("SetOverrideBindingClick: no button with the name " .. buttonName)
  end
  H.overrideBindings[key] = { owner, buttonName }
end, BINDING_FILE)
setGlobal("ClearOverrideBindings", function(owner)
  bindingAllowed("ClearOverrideBindings")
  for key, entry in pairs(H.overrideBindings) do
    if entry[1] == owner then
      H.overrideBindings[key] = nil
    end
  end
end, "Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua")
function H.pressKey(key)
  local entry = H.overrideBindings[key]
  if entry then
    H.click(_G[entry[2]], "LeftButton", false)
    return "override"
  end
  for action, keys in pairs(H.bindings) do
    for _, bound in ipairs(keys) do
      if bound == key then
        did("game binding", action)
        return action
      end
    end
  end
end
set("C_QuestLine", "GetAvailableQuestLines", function()
  local floors = Enum.QuestLineFloorLocation
  return {
    { questID = 61, questName = "Shipment to Stormwind", x = 0.44, y = 0.66, isHidden = false, inProgress = false, floorLocation = floors.Same },
    { questID = 63, questName = "Hidden", x = 0.1, y = 0.1, isHidden = true, inProgress = false, floorLocation = floors.Same },
    { questID = 64, questName = "In the cellar", x = 0.2, y = 0.2, isHidden = false, inProgress = false, floorLocation = floors.Below },
  }
end)
-- H.world.questLines[questLineID] = { name = ..., quests = { questID, ... } }: the quest chains;
-- none at first. H.world.completedQuests[questID]: a quest the character has done.
local function questLineOf(questID)
  for questLineID, line in pairs(H.world.questLines or {}) do
    for _, id in ipairs(line.quests) do
      if id == questID then
        return questLineID, line
      end
    end
  end
end
set("C_QuestLine", "GetQuestLineInfo", function(questID)
  local questLineID, line = questLineOf(questID)
  if not questLineID then
    return nil
  end
  return {
    questLineID = questLineID, questLineName = line.name, questID = questID,
    questName = C_QuestLog.GetTitleForQuestID(questID) or "", x = 0.5, y = 0.5,
    isHidden = false, isLegendary = false, isDaily = false, isCampaign = false,
    isImportant = false, isAccountCompleted = false, isCombatAllyQuest = false, isMeta = false,
    inProgress = C_QuestLog.GetLogIndexForQuestID(questID) ~= nil, isQuestStart = false,
    isLocalStory = false, floorLocation = Enum.QuestLineFloorLocation.Same, startMapID = 37,
  }
end)
H.allowNil("C_QuestLine.GetQuestLineInfo", "The game gives nothing for a quest of no quest line: Blizzard_FrameXMLUtil/Mainline/QuestUtils.lua tests the result with `if questLineInfo then`.")
set("C_QuestLine", "GetQuestLineQuests", function(questLineID)
  local line = H.world.questLines and H.world.questLines[questLineID]
  local quests = {}
  for index, id in ipairs(line and line.quests or {}) do
    quests[index] = id
  end
  return quests
end)
set("C_QuestLog", "IsQuestFlaggedCompleted", function(questID)
  return H.world.completedQuests ~= nil and H.world.completedQuests[questID] == true
end)
set("C_SuperTrack", "GetSuperTrackedQuestID", function() return 176 end)
set("C_VignetteInfo", "GetVignettes", function() return { "Vignette-1", "Vignette-2" } end)
set("C_VignetteInfo", "GetVignetteInfo", function(guid)
  return { name = guid == "Vignette-1" and "Gruff Swiftbite" or "", isDead = false, vignetteGUID = guid, atlasName = "VignetteKill" }
end)
set("C_VignetteInfo", "GetVignettePosition", function() return CreateVector2D(0.25, 0.9) end)
set("C_TaxiMap", "GetTaxiNodesForMap", function()
  return {
    { name = "Goldshire", position = CreateVector2D(0.43, 0.66), faction = Enum.FlightPathFaction.Alliance, atlasName = "TaxiNode_Alliance", isUndiscovered = false },
    { name = "Orc camp", position = CreateVector2D(0.8, 0.1), faction = Enum.FlightPathFaction.Horde, atlasName = "TaxiNode_Horde", isUndiscovered = true },
  }
end)
set("C_DeathInfo", "GetCorpseMapPosition", function() return CreateVector2D(0.41, 0.6) end)

-- More of what a map shows, for the kinds of Forever Atlas (MapKinds.lua). Each is what the
-- game's own map reads in Blizzard_SharedMapDataProviders.
-- An event of Elwynn Forest with time left (AreaPOIEventDataProvider.lua). H.world.eventSeconds
-- is the time left, 90 minutes at first.
AREA_POIS[106] = { areaPoiID = 106, name = "Harvest Festival", description = "A feast", position = CreateVector2D(0.7, 0.3), atlasName = "poi-event" }
set("C_AreaPoiInfo", "GetEventsForMap", function(mapID) return mapID == 37 and { 106 } or {} end)
set("C_AreaPoiInfo", "GetAreaPOISecondsLeft", function(id) return id == 106 and (H.world.eventSeconds or 5400) or 0 end)
-- The place that a guard pointed out (GossipDataProvider.lua): none until H.world.guide is set.
set("C_GossipInfo", "GetPoiForUiMapID", function(mapID) return mapID == 37 and H.world.guide and 7 or nil end)
set("C_GossipInfo", "GetPoiInfo", function(mapID, id)
  if mapID == 37 and id == 7 and H.world.guide then
    return { inBattleMap = false, name = "Goldshire Smithy", position = CreateVector2D(0.75, 0.8), textureIndex = 6 }
  end
end)
-- A bonus objective of Elwynn Forest, and one of a map under it, which the game lists too
-- (BonusObjectiveDataProvider.lua).
set("C_TaskQuest", "GetQuestsOnMap", function(mapID)
  if mapID ~= 37 then
    return {}
  end
  return {
    { questID = 900, x = 0.15, y = 0.25, mapID = 37, inProgress = false, numObjectives = 1, isQuestStart = false, isDaily = false },
    { questID = 901, x = 0.16, y = 0.26, mapID = 425, inProgress = false, numObjectives = 1, isQuestStart = false, isDaily = false },
  }
end)
set("C_TaskQuest", "GetQuestInfoByQuestID", function(questID) return questID == 900 and "Clear the Fields" or "", nil, false, false end)
-- The next step on the way to a quest with its goal on another map (QuestDataProvider.lua):
-- none until H.world.questWaypoint is set.
set("C_QuestLog", "GetNextWaypointForMap", function(_, mapID)
  if mapID == 37 and H.world.questWaypoint then
    return 0.85, 0.45
  end
end)
H.allowNil("C_QuestLog.GetNextWaypointForMap", "The game gives nothing for a quest without a step on this map: Blizzard_SharedMapDataProviders/QuestDataProvider.lua tests the result with `if x and y then`.")
-- Two bosses on the map of Westfall, the second one defeated (EncounterJournalDataProvider.lua).
set("C_EncounterJournal", "GetEncountersOnMap", function(mapID)
  if mapID ~= 52 then
    return {}
  end
  return { { encounterID = 1, mapX = 0.3, mapY = 0.3 }, { encounterID = 2, mapX = 0.6, mapY = 0.35 } }
end)
set("C_EncounterJournal", "IsEncounterComplete", function(encounterID) return encounterID == 2 end)
-- Where the spirit comes back after a release (DeathMapDataProvider.lua tests the result with
-- `if deathReleasePosition then`; the documentation has it as a value that can be nil): none
-- until H.world.release is set.
set("C_DeathInfo", "GetDeathReleasePosition", function(mapID) return mapID == 37 and H.world.release and CreateVector2D(0.3, 0.55) or nil end)
-- A quest hub of Elwynn Forest, and the abbey, which is a landmark too
-- (QuestOfferDataProvider.lua reads GetQuestHubsForMap).
AREA_POIS[107] = { areaPoiID = 107, name = "Eastvale Logging Camp", description = "Quests", position = CreateVector2D(0.8, 0.65), atlasName = "poi-hub" }
set("C_AreaPoiInfo", "GetQuestHubsForMap", function(mapID) return mapID == 37 and { 102, 107 } or {} end)
-- A pet tamer of Elwynn Forest (PetTamerDataProvider.lua; the structure is PetTamerMapInfo).
set("C_PetInfo", "GetPetTamersForMap", function(mapID)
  return mapID == 37 and { { areaPoiID = 108, name = "Julia Stevens", position = CreateVector2D(0.3, 0.8), atlasName = "WildBattlePetCapturable" } } or {}
end)

---------------------------------------------------------------------------------------------------
-- Bags and items

set("C_Container", "GetContainerNumSlots", function(bag)
  return BAG_CONTENTS[bag] and BAG_CONTENTS[bag].size or 0
end)
set("C_Container", "GetContainerItemInfo", function(bag, slot)
  local entry = BAG_CONTENTS[bag] and BAG_CONTENTS[bag].slots[slot]
  if not entry then
    return nil
  end
  local item = ITEMS[entry[1]]
  return {
    iconFileID = item.icon, stackCount = entry[2], isLocked = false, quality = item.quality, isReadable = false,
    hasLoot = false, hyperlink = itemLink(entry[1]), isFiltered = false, hasNoValue = item.sell == 0,
    itemID = entry[1], isBound = entry[1] == 6948, itemName = item.name,
  }
end)
-- isQuestItem is true for each item of the item class Quest, a quest item or not.
set("C_Container", "GetContainerItemQuestInfo", function(bag, slot)
  local entry = BAG_CONTENTS[bag] and BAG_CONTENTS[bag].slots[slot]
  return { isQuestItem = entry ~= nil and ITEMS[entry[1]].class == 12, isActive = false }
end)
set("C_Container", "SortBags", function() did("sort bags") end)

-- An item by its number, its link or its name.
local function itemOf(value)
  local itemID = tonumber(value) or tonumber(realTostring(value):match("item:(%d+)"))
  if not itemID then
    for id, item in pairs(ITEMS) do
      if item.name == value then
        return id
      end
    end
  end
  return itemID
end
-- How many of an item are in the bags.
set("C_Item", "GetItemCount", function(value)
  local itemID, count = itemOf(value), 0
  for _, bag in pairs(BAG_CONTENTS) do
    for _, entry in pairs(bag.slots) do
      if entry[1] == itemID then
        count = count + entry[2]
      end
    end
  end
  return count
end)
set("C_Item", "GetItemInfo", function(value)
  local itemID = itemOf(value)
  local item = ITEMS[itemID]
  if not item then
    return nil
  end
  return item.name, itemLink(itemID), item.quality, 10, 1, "Type", "Subtype", 20, "", item.icon, item.sell, item.class, 0, item.bind or 1, 0,
    nil, false, ""
end)
set("C_Item", "GetItemInfoInstant", function(value)
  local itemID = itemOf(value)
  local item = ITEMS[itemID]
  if item then
    return itemID, "Type", "Subtype", "", item.icon, item.class, 0
  end
end)
set("C_Item", "GetItemNameByID", function(value) return ITEMS[itemOf(value)] and ITEMS[itemOf(value)].name end)
set("C_Item", "GetItemIconByID", function(value) return ITEMS[itemOf(value)] and ITEMS[itemOf(value)].icon end)
-- An item location of a bag slot.
local function slotOf(location)
  local bag, slot = location.bagID, location.slotIndex
  return BAG_CONTENTS[bag] and BAG_CONTENTS[bag].slots[slot]
end
set("C_Item", "DoesItemExist", function(location) return slotOf(location) ~= nil end)
set("C_Item", "GetItemID", function(location) return slotOf(location) and slotOf(location)[1] end)
set("C_Item", "GetStackCount", function(location) return slotOf(location) and slotOf(location)[2] or 0 end)

-- The bank that all characters share: not to see (H.world.bankHidden) or locked, because
-- another character of the account has it open (H.world.bankLocked).
set("C_Bank", "CanViewBank", function() return not H.world.bankHidden end)
set("C_Bank", "FetchBankLockedReason", function() return H.world.bankLocked and 0 or nil end)

-- The bag window of the game: the functions behind the bag key and the bag buttons.
-- H.gameBags counts the calls that reach the game.
-- H.gameBagsOpen: the bag window of the game is open. As in the game, a function calls the
-- others by their global names (ToggleAllBags closes the backpack with CloseBackpack), so a
-- hook of an addon on an inner function runs before the hook on the outer one.
H.gameBags = 0
H.gameBagsOpen = false
local CONTAINER_FRAME = "Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua"
-- The bag windows of the game (ContainerFrame.xml): the one for all bags of the character, and
-- one for a single bag, which here is a bag of the bank.
local combinedBags = CreateFrame("Frame", "ContainerFrameCombinedBags", UIParent)
combinedBags:Hide()
local singleBag = CreateFrame("Frame", "ContainerFrame1", UIParent)
singleBag:Hide()
function singleBag:GetBagID()
  return self.bagID
end
-- The window that opened the bags (a vendor, the bank): only that one closes them again.
local bagOpener
-- ContainerFrame_AllowedToOpenBags: false while the game does not allow the bags (H.world.bagsRefused).
local function bagsAllowed()
  return not H.world.bagsRefused
end
local function bagFunction(name, fn)
  setGlobal(name, function(...)
    H.gameBags = H.gameBags + 1
    local result = fn(...)
    H.gameBagsOpen = combinedBags:IsShown()
    return result
  end, CONTAINER_FRAME)
end
local function isBankBag(bag)
  return realType(bag) == "number" and bag > 5
end
bagFunction("OpenBackpack", function()
  if bagsAllowed() then
    combinedBags:Show()
  end
end)
bagFunction("CloseBackpack", function()
  local was = combinedBags:IsShown()
  combinedBags:Hide()
  return was
end)
bagFunction("OpenBag", function(bag)
  if not bagsAllowed() then
    return
  end
  if isBankBag(bag) then
    singleBag.bagID = bag
    singleBag:Show()
  else
    combinedBags:Show()
  end
end)
bagFunction("CloseBag", function(bag)
  if isBankBag(bag) and singleBag:IsShown() and singleBag.bagID == bag then
    singleBag:Hide()
    return true
  end
  return false
end)
bagFunction("OpenAllBags", function(frame)
  if not bagsAllowed() or combinedBags:IsShown() then
    return
  end
  if frame and not bagOpener then
    bagOpener = frame:GetName()
  end
  OpenBackpack()
end)
bagFunction("CloseAllBags", function(frame)
  if frame and frame:GetName() ~= bagOpener then
    return false -- "This frame wasn't the one that opened the bags, nothing closed."
  end
  bagOpener = nil
  local closed = CloseBackpack()
  if singleBag:IsShown() then
    closed = CloseBag(singleBag.bagID) or closed
  end
  return closed
end)
bagFunction("ToggleBackpack", function()
  if not bagsAllowed() then
    return
  end
  if combinedBags:IsShown() then
    CloseBackpack()
  else
    OpenBackpack()
  end
end)
bagFunction("ToggleAllBags", function()
  if not bagsAllowed() then
    return
  end
  if combinedBags:IsShown() then
    CloseBackpack()
  else
    OpenAllBags()
  end
end)
bagFunction("ToggleBag", function(bag)
  if isBankBag(bag) then
    if not CloseBag(bag) then
      OpenBag(bag)
    end
  elseif combinedBags:IsShown() then
    CloseBackpack()
  else
    OpenBag(bag)
  end
end)
-- The Escape key (Blizzard_UIParentPanelManager, CloseAllWindows): closes the bags and the
-- windows named in UISpecialFrames. Only if nothing was open does the game menu open.
-- Returns true if the game menu opened.
function H.pressEscape()
  local closed = CloseAllBags()
  for _, name in ipairs(UISpecialFrames) do
    local frame = _G[name]
    if frame and frame:IsShown() then
      frame:Hide()
      closed = true
    end
  end
  if not closed then
    H.did[#H.did + 1] = { "game menu" }
  end
  return not closed
end
H.bagFunctions = { "OpenAllBags", "CloseAllBags", "ToggleAllBags", "ToggleBackpack", "OpenBackpack", "CloseBackpack" }

---------------------------------------------------------------------------------------------------
-- Quests

local QUEST_LOG = {
  { title = "Elwynn Forest", isHeader = true, questLogIndex = 1, questID = 0, isCollapsed = false },
  { title = "Wanted: Hogger", questID = 176, isHeader = false, isHidden = false, isTask = false, questLogIndex = 2, level = 11 },
  { title = "A Fishy Peril", questID = 40, isHeader = false, isHidden = false, isTask = false, questLogIndex = 3, level = 10 },
}
H.questProgress = 3
H.watched = { [176] = true } -- the quests on the tracker
set("C_QuestLog", "GetNumQuestLogEntries", function() return #QUEST_LOG, 2 end)
set("C_QuestLog", "GetInfo", function(index) return QUEST_LOG[index] end)
set("C_QuestLog", "GetLogIndexForQuestID", function(questID)
  for index, entry in ipairs(QUEST_LOG) do
    if entry.questID == questID and not entry.isHeader then
      return index
    end
  end
end)
-- The items of quest 176. H.world.questItems: the quest also has items to collect.
local QUEST_UTILS = "Blizzard_FrameXMLUtil/Mainline/QuestUtils.lua"
setGlobal("GetQuestLogSpecialItemInfo", function(logIndex)
  if QUEST_LOG[logIndex] and QUEST_LOG[logIndex].questID == 176 then
    return itemLink(5003), ITEMS[5003].icon, 0, false
  end
end, QUEST_UTILS)
local QUEST_REWARDS = { reward = { { 2211, 1 } }, choice = { { 117, 5 }, { 2589, 10 } } }
local function rewardInfo(kind)
  return function(index, questID)
    local entry = questID == 176 and QUEST_REWARDS[kind][index]
    if entry then
      local item = ITEMS[entry[1]]
      return item.name, item.icon, entry[2], item.quality, true, entry[1], 20
    end
  end
end
setGlobal("GetNumQuestLogRewards", function(questID) return questID == 176 and #QUEST_REWARDS.reward or 0 end, QUEST_UTILS)
setGlobal("GetQuestLogRewardInfo", rewardInfo("reward"), QUEST_UTILS)
setGlobal("GetNumQuestLogChoices", function(questID) return questID == 176 and #QUEST_REWARDS.choice or 0 end, QUEST_UTILS)
setGlobal("GetQuestLogChoiceInfo", rewardInfo("choice"), QUEST_UTILS)
set("C_QuestLog", "GetQuestObjectives", function(questID)
  if questID == 176 and H.world.questItems then
    return {
      { text = "Hogger slain: " .. H.questProgress .. "/8", type = "monster", finished = false, numFulfilled = H.questProgress, numRequired = 8 },
      { text = "Gnoll Paw: 3/8", type = "item", finished = false, numFulfilled = 3, numRequired = 8 },
      { text = "8/8 Linen Cloth", type = "item", finished = true, numFulfilled = 8, numRequired = 8 },
    }
  end
  if questID == 176 then
    return { { text = "Hogger slain: " .. H.questProgress .. "/8", type = "monster", finished = false, numFulfilled = H.questProgress, numRequired = 8 } }
  end
  return { { text = "Speak with Remy", type = "event", finished = true, numFulfilled = 1, numRequired = 1 } }
end)
-- H.world.completed[questID]: the quest is ready to turn in.
set("C_QuestLog", "IsComplete", function(questID) return questID == 40 or (H.world.completed ~= nil and H.world.completed[questID] == true) end)
set("C_QuestLog", "GetTitleForQuestID", function(questID)
  for _, entry in ipairs(QUEST_LOG) do
    if entry.questID == questID and not entry.isHeader then
      return entry.title
    end
  end
end)
set("C_QuestLog", "GetQuestsOnMap", function(mapID)
  if mapID == 52 then
    return { { questID = 176, x = 0.9, y = 0.1 } }
  end
  return { { questID = 176, x = 0.3, y = 0.8 }, { questID = 40, x = 0.5, y = 0.2 } }
end)
set("C_QuestLog", "GetQuestWatchType", function(questID)
  return H.watched[questID] and Enum.QuestWatchType.Manual or nil
end)
-- The game tracks a limited number of quests (H.world.watchLimit; none at first): past it,
-- AddQuestWatch does nothing and returns false.
local function watchCount()
  local count = 0
  for _ in pairs(H.watched) do
    count = count + 1
  end
  return count
end
H.watchCount = watchCount
set("C_QuestLog", "GetNumQuestWatches", watchCount)
set("C_QuestLog", "AddQuestWatch", function(questID)
  if H.world.watchLimit and not H.watched[questID] and watchCount() >= H.world.watchLimit then
    return false
  end
  H.watched[questID] = true
  did("watch", questID)
  return true
end)
set("C_QuestLog", "RemoveQuestWatch", function(questID)
  H.watched[questID] = nil
  did("unwatch", questID)
  return true
end)
-- H.world.questDifficulty[questID]: a value of Enum.RelativeContentDifficulty; Easy when unset.
-- The game's QuestMapFrame.lua gives it to GetDifficultyColor.
set("C_PlayerInfo", "GetContentDifficultyQuestForPlayer", function(questID)
  local difficulty = H.world.questDifficulty and H.world.questDifficulty[questID]
  return difficulty or Enum.RelativeContentDifficulty.Easy
end)
-- The quest menu's "Abandon" of Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua. The game
-- selects the quest, calls C_QuestLog.SetAbandonQuest and shows the ABANDON_QUEST dialog; the
-- stand-in keeps the quest and notes the call in H.abandonAsked.
H.abandonAsked = nil
setGlobal("QuestMapQuestOptions_AbandonQuest", function(questID)
  if not C_QuestLog.GetLogIndexForQuestID(questID) then
    error("QuestMapQuestOptions_AbandonQuest: quest " .. tostring(questID) .. " is not in the quest log", 2)
  end
  H.abandonAsked = questID
  did("abandon asked", questID)
end, "Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua")

-- Builds the quest log, as the function of the same name in QuestMapFrame.lua: a header button
-- and a title button for each entry, each with its place in the layout.
function QuestLogQuests_Update()
  local titles, headers, objectives, pois = {}, {}, {}, {}
  for index, entry in ipairs(QUEST_LOG) do
    local button = H.questLogFrames[index]
    if not button then
      button = CreateFrame("Button", nil, QuestScrollFrame.Contents)
      H.questLogFrames[index] = button
      H.gameFrameSet[button] = true
    end
    button:Show()
    button.layoutIndex = index
    button.questLogIndex = index
    if entry.isHeader then
      button.topPadding = 8
      headers[#headers + 1] = button
    else
      button.topPadding = #titles == 0 and 2 or -3
      button.questID = entry.questID
      button.info = entry
      -- QuestLogQuests_AddQuestButton writes the title and gives it the colour of the level of
      -- the quest, each time it builds the log.
      if not button.Text then
        button.Text = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        -- The tag at the right of the name. The game gives it the colour of the name
        -- (QuestMapFrame.lua: button.TagText:SetTextColor in the same function as button.Text).
        button.TagText = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        -- QuestMapLogTitleButton_OnEnter and _OnLeave: the game gives the title and the lines
        -- of the quest their own colours again.
        local function gameColours(self)
          self.Text:SetTextColor(1, 0.82, 0)
          self.TagText:SetTextColor(1, 0.82, 0)
          for _, line in ipairs(QuestScrollFrame.objectiveFramePool.active or {}) do
            if line.questID == self.questID then
              line.Text:SetTextColor(0.8, 0.8, 0.8)
            end
          end
        end
        button:SetScript("OnEnter", gameColours)
        button:SetScript("OnLeave", gameColours)
      end
      button.Text:SetText(entry.title)
      button.Text:SetTextColor(1, 0.82, 0)
      button.TagText:SetText("Elite")
      button.TagText:SetTextColor(1, 0.82, 0)
      -- QuestMapFrame.lua, QuestLogQuests_AddQuestButton: the box that tracks the quest.
      if not button.Checkbox then
        button.Checkbox = CreateFrame("Button", nil, button)
        button.Checkbox:SetSize(16, 16)
        button.Checkbox:SetPoint("RIGHT", button, "RIGHT", -4, 0)
        H.gameFrameSet[button.Checkbox] = true
      end
      titles[#titles + 1] = button
      -- The icon of the quest at the left of its name. It is not a child of the title button:
      -- it comes from a pool of the list (Blizzard_POIButton/POIButtonOwner.lua), is shown on
      -- its own and only hangs on the title (QuestMapFrame.lua: poiButton:SetPoint, .parent).
      local poi = H.questLogFrames["poi" .. index]
      if not poi then
        poi = CreateFrame("Button", nil, QuestScrollFrame.Contents)
        H.questLogFrames["poi" .. index] = poi
        H.gameFrameSet[poi] = true
        function poi:GetQuestID()
          return self.questID
        end
      end
      poi.questID = entry.questID
      poi.parent = button
      poi:SetPoint("TOPLEFT", button, "TOPLEFT", 6, -4)
      poi:Show()
      pois[#pois + 1] = poi
      local line = H.questLogFrames["line" .. index]
      if not line then
        line = CreateFrame("Frame", nil, QuestScrollFrame.Contents)
        H.questLogFrames["line" .. index] = line
        H.gameFrameSet[line] = true
      end
      if not line.Text then
        line.Text = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      end
      line.Text:SetText("- objective")
      line.Text:SetTextColor(0.8, 0.8, 0.8)
      line:Show()
      line.questID = entry.questID
      objectives[#objectives + 1] = line
      -- The height of the title button, as QuestLogQuests_AddQuestButton sets it
      -- (Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua): 8 and the height of the title;
      -- 4 more if the CVar showQuestObjectivesInLog is off; else for a quest that is ready
      -- its one line and 3, and for another quest each objective that is not finished, with
      -- 3 above the first and 2 above each later one; then 6 for the icon. The height of a
      -- text is 12 here, as GetStringHeight of the stand-in: the game's number depends on the
      -- font. No quest of this world needs money, so the line for money is left out. The
      -- stand-in still shows one line frame for each quest, whatever the number here.
      local TEXT_HEIGHT = 12
      local height = 8 + TEXT_HEIGHT
      if not GetCVarBool("showQuestObjectivesInLog") then
        height = height + 4
      elseif C_QuestLog.IsComplete(entry.questID) then
        height = height + TEXT_HEIGHT + 3
      else
        local first = true
        for _, objective in ipairs(C_QuestLog.GetQuestObjectives(entry.questID)) do
          if not objective.finished then
            height = height + TEXT_HEIGHT + (first and 3 or 2)
            first = false
          end
        end
      end
      button:SetHeight(height + 6)
    end
  end
  QuestScrollFrame.titleFramePool.active = titles
  QuestScrollFrame.headerFramePool.active = headers
  QuestScrollFrame.objectiveFramePool.active = objectives
  QuestScrollFrame.Contents.buttonPool.active = pois
end

-- Lays out the quest tracker, as ObjectiveTrackerModuleMixin:Update does
-- (Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerModule.lua and
-- Blizzard_ObjectiveTrackerBlock.lua): one block for each watched quest, in the order of the
-- quest log. The functions of the game are named beside each part.
--   module: firstBlock, lastBlock; block: id, parentModule, nextBlock, usedLines,
--   rightEdgeOffset, HeaderText and HeaderButton (of the template), height.
-- A text gets its colour only when its style changes (SetStringText), so a colour that an
-- addon gave a text stays until the style changes or the pointer leaves the header.
-- H.world.trackerRightEdge[questID]: the room that the game takes at the right of the block
-- for a button (AddRightEdgeFrame), a number below zero.
do
  local tracker = QuestObjectiveTracker
  -- OBJECTIVE_TRACKER_COLOR of the game (Blizzard_ObjectiveTrackerShared.lua): the header of a
  -- block and a line, each with the style under the pointer as `reverse`, and the line of a
  -- quest that is ready, which has no other style. The game's file gives 0.8 and 0.6; the
  -- other numbers are colours of the client by name (OBJECTIVE_TRACKER_BLOCK_HEADER_COLOR,
  -- NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR), which no file of the game holds.
  local NORMAL, NORMAL_HIGHLIGHT = { r = 0.8, g = 0.8, b = 0.8 }, { r = 1, g = 1, b = 1 }
  local HEADER, HEADER_HIGHLIGHT = { r = 0.75, g = 0.61, b = 0 }, { r = 1, g = 0.82, b = 0 }
  NORMAL.reverse, NORMAL_HIGHLIGHT.reverse = NORMAL_HIGHLIGHT, NORMAL
  HEADER.reverse, HEADER_HIGHLIGHT.reverse = HEADER_HIGHLIGHT, HEADER
  local COMPLETE = { r = 0.6, g = 0.6, b = 0.6 }
  local TEXT_HEIGHT = 12

  -- ObjectiveTrackerBlockMixin:SetStringText
  local function setStringText(fontString, text, colorStyle, useHighlight)
    fontString:SetText(text)
    colorStyle = colorStyle or NORMAL
    if useHighlight and colorStyle.reverse then
      colorStyle = colorStyle.reverse
    end
    if fontString.colorStyle ~= colorStyle then
      fontString:SetTextColor(colorStyle.r, colorStyle.g, colorStyle.b)
      fontString.colorStyle = colorStyle
    end
    return TEXT_HEIGHT
  end
  -- ObjectiveTrackerBlockMixin:UpdateHighlight: the header and each line get the colours of
  -- the game again, with the pointer on the header and without it.
  local function updateHighlight(block)
    local headerColor = block.isHighlighted and HEADER_HIGHLIGHT or HEADER
    block.HeaderText:SetTextColor(headerColor.r, headerColor.g, headerColor.b)
    block.HeaderText.colorStyle = headerColor
    for _, line in pairs(block.usedLines) do
      local colorStyle = line.Text.colorStyle.reverse
      if colorStyle then
        line.Text:SetTextColor(colorStyle.r, colorStyle.g, colorStyle.b)
        line.Text.colorStyle = colorStyle
      end
    end
  end
  -- ObjectiveTrackerModuleMixin:GetBlock, and ObjectiveTrackerBlockMixin:Init for a new one.
  local function getBlock(questID)
    local block = H.trackerBlocks[questID]
    if not block then
      block = CreateFrame("Frame", nil, tracker.ContentsFrame, tracker.blockTemplate)
      block.parentModule = tracker
      block.usedLines = {}
      block.rightEdgeOffset = 0
      -- OnHeaderEnter and OnHeaderLeave, which the header button of the template calls.
      block.HeaderButton:SetAllPoints(block.HeaderText)
      block.HeaderButton:SetScript("OnEnter", function()
        block.isHighlighted = true
        updateHighlight(block)
      end)
      block.HeaderButton:SetScript("OnLeave", function()
        block.isHighlighted = false
        updateHighlight(block)
      end)
      H.trackerBlocks[questID] = block
      H.gameFrameSet[block], H.gameFrameSet[block.HeaderButton] = true, true
    end
    block.id = questID
    -- ObjectiveTrackerBlockMixin:Reset
    block.nextBlock = nil
    block.rightEdgeOffset = 0
    block.height = 0
    for _, line in pairs(block.usedLines) do
      line.used = nil
    end
    return block
  end
  -- ObjectiveTrackerBlockMixin:GetLine and AddObjective.
  local function addObjective(block, objectiveKey, text, colorStyle)
    local line = block.usedLines[objectiveKey]
    if not line then
      line = CreateFrame("Frame", nil, block, tracker.lineTemplate)
      line.objectiveKey = objectiveKey
      line.parentBlock = block
      block.usedLines[objectiveKey] = line
      H.gameFrameSet[line] = true
    end
    line.used = true
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -(block.height + tracker.lineSpacing))
    line:SetPoint("RIGHT", block.rightEdgeOffset, 0)
    line:SetHeight(TEXT_HEIGHT)
    line:Show()
    setStringText(line.Text, text, colorStyle, block.isHighlighted)
    block.height = block.height + tracker.lineSpacing + TEXT_HEIGHT
  end

  function tracker:Update()
    H.trackerLayouts = H.trackerLayouts + 1
    -- BeginLayout
    self.firstBlock, self.lastBlock = nil, nil
    local used = {}
    for _, entry in ipairs(QUEST_LOG) do
      local questID = entry.questID
      if not entry.isHeader and H.watched[questID] then
        local block = getBlock(questID)
        used[block] = true
        -- AnchorBlock: under the block before it, the first one under the contents frame.
        block:ClearAllPoints()
        if self.lastBlock then
          block:SetPoint("TOP", self.lastBlock, "BOTTOM", 0, self.fromBlockOffsetY)
        else
          block:SetPoint("TOP", self.ContentsFrame, "TOP", 0, self.fromHeaderOffsetY)
        end
        block:SetPoint("LEFT", self.blockOffsetX, 0)
        block:SetPoint("RIGHT")
        -- The button of a quest with an item to use: AddRightEdgeFrame, before the header.
        local rightEdge = H.world.trackerRightEdge and H.world.trackerRightEdge[questID]
        if rightEdge then
          block.rightEdgeOffset = block.rightEdgeOffset + rightEdge
        end
        -- SetHeader
        block.HeaderText:SetPoint("RIGHT", block.rightEdgeOffset, 0)
        block.height = setStringText(block.HeaderText, entry.title, HEADER, block.isHighlighted)
        if C_QuestLog.IsComplete(questID) then
          -- QuestObjectiveTrackerMixin:UpdateSingle, for a quest without a text of its own
          -- for this: the key "QuestComplete", QUEST_WATCH_QUEST_READY, the colour "Complete".
          addObjective(block, "QuestComplete", "Ready for turn-in", COMPLETE)
        else
          for index, objective in ipairs(C_QuestLog.GetQuestObjectives(questID)) do
            if not objective.finished then
              addObjective(block, index, objective.text)
            end
          end
        end
        -- FreeUnusedLines
        for key, line in pairs(block.usedLines) do
          if not line.used then
            line:Hide()
            block.usedLines[key] = nil
          end
        end
        block:SetHeight(block.height)
        block:Show()
        -- InternalAddBlock
        if self.lastBlock then
          self.lastBlock.nextBlock = block
        end
        self.lastBlock = block
        if not self.firstBlock then
          self.firstBlock = block
        end
      end
    end
    -- EndLayout: a block of a quest that is not watched any more is free.
    for questID, block in pairs(H.trackerBlocks) do
      if not used[block] then
        block:Hide()
        block.nextBlock = nil
        H.trackerBlocks[questID] = nil
      end
    end
  end
end

-- Quest givers. C_GossipInfo is in the documentation; the functions of the quest window are not.
local QUEST_FRAME = "Blizzard_UIPanels_Game/Mainline/QuestFrame.lua"
local GOSSIP = {
  active = { { questID = 40, title = "A Fishy Peril", isComplete = true }, { questID = 176, title = "Wanted: Hogger", isComplete = false } },
  available = { { questID = 62, title = "Daily Bread", repeatable = true }, { questID = 61, title = "Shipment to Stormwind", repeatable = false } },
}
set("C_GossipInfo", "GetActiveQuests", function() return GOSSIP.active end)
set("C_GossipInfo", "GetAvailableQuests", function() return GOSSIP.available end)
set("C_GossipInfo", "SelectActiveQuest", function(questID) did("gossip turn in", questID) end)
set("C_GossipInfo", "SelectAvailableQuest", function(questID) did("gossip accept", questID) end)
setGlobal("GetNumActiveQuests", function() return 2 end, QUEST_FRAME)
setGlobal("GetActiveTitle", function(index) return index == 1 and "Wanted: Hogger" or "A Fishy Peril", index == 2 end, QUEST_FRAME)
setGlobal("SelectActiveQuest", function(index) did("greeting turn in", index) end, QUEST_FRAME)
setGlobal("GetNumAvailableQuests", function() return 1 end, QUEST_FRAME)
setGlobal("SelectAvailableQuest", function(index) did("greeting accept", index) end, QUEST_FRAME)
setGlobal("AcceptQuest", function() did("accept") end, "Blizzard_StaticPopup_Game/GameDialogDefs.lua")
setGlobal("QuestGetAutoAccept", function() return H.world.autoAcceptQuest == true end, QUEST_FRAME)
setGlobal("AcknowledgeAutoAcceptQuest", function() did("acknowledge") end, QUEST_FRAME)
setGlobal("IsQuestCompletable", function() return true end, QUEST_FRAME)
setGlobal("CompleteQuest", function() did("complete") end, QUEST_FRAME)
setGlobal("GetQuestReward", function(choice) did("reward", choice) end, QUEST_FRAME)

-- The rewards of the quest that the quest window shows: H.world.choices is their item IDs.
local QUEST_INFO = "Blizzard_UIPanels_Game/Mainline/QuestInfo.lua"
H.world.choices = { 2211, 117, 2589 }
setGlobal("GetNumQuestChoices", function() return #H.world.choices end, "Blizzard_BoostTutorial/Blizzard_TutorialLogic.lua")
setGlobal("GetQuestItemLink", function(kind, index)
  local itemID = kind == "choice" and H.world.choices[index]
  return itemID and itemLink(itemID) or nil
end, QUEST_INFO)
setGlobal("GetQuestItemInfo", function(kind, index)
  local itemID = kind == "choice" and H.world.choices[index]
  if itemID then
    return ITEMS[itemID].name, ITEMS[itemID].icon, itemID == 2589 and 10 or 1, ITEMS[itemID].quality, true, itemID, 0
  end
end, QUEST_INFO)
QuestInfoRewardsFrame = CreateFrame("Frame", "QuestInfoRewardsFrame", UIParent)
QuestInfoRewardsFrame.RewardButtons = {}
for index = 1, 3 do
  local button = CreateFrame("Button", nil, QuestInfoRewardsFrame)
  button:SetID(index)
  button.type, button.objectType = "choice", "item"
  QuestInfoRewardsFrame.RewardButtons[index] = button
end
function QuestInfo_Display() end

---------------------------------------------------------------------------------------------------
-- The auction house and mail

-- One commodity with three sellers, one of them the player.
set("C_AuctionHouse", "GetNumCommoditySearchResults", function() return 3 end)
set("C_AuctionHouse", "GetCommoditySearchResultInfo", function(itemID, index)
  local rows = {
    { itemID = itemID, quantity = 20, unitPrice = 145, containsOwnerItem = false, numOwnerItems = 0 },
    { itemID = itemID, quantity = 5, unitPrice = 160, containsOwnerItem = true, numOwnerItems = 5 },
    { itemID = itemID, quantity = 40, unitPrice = 175, containsOwnerItem = false, numOwnerItems = 0 },
  }
  return rows[index]
end)
set("C_AuctionHouse", "GetBrowseResults", function()
  return { { itemKey = { itemID = 2589 }, minPrice = 150, totalQuantity = 65 }, { itemKey = { itemID = 769 }, minPrice = 40, totalQuantity = 8 } }
end)
set("C_AuctionHouse", "GetNumOwnedAuctions", function() return 1 end)
set("C_AuctionHouse", "GetOwnedAuctionInfo", function()
  -- Enum.AuctionStatus.Active is 0.
  return { auctionID = 1, itemKey = { itemID = 2589 }, itemLink = itemLink(2589), status = Enum.AuctionStatus.Active, quantity = 5, buyoutAmount = 160 }
end)
set("C_AuctionHouse", "GetNumItemSearchResults", function() return 2 end)
set("C_AuctionHouse", "GetItemSearchResultInfo", function(itemKey, index)
  local rows = {
    { itemKey = itemKey, buyoutAmount = 5200, containsOwnerItem = false },
    { itemKey = itemKey, buyoutAmount = 4900, containsOwnerItem = true },
  }
  return rows[index]
end)
set("C_AuctionHouse", "GetItemKeyFromItem", function() return { itemID = 2589, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end)
set("C_AuctionHouse", "SupportsCopperValues", function() return true end)
set("C_AuctionHouse", "IsThrottledMessageSystemReady", function() return true end)
set("C_AuctionHouse", "ReplicateItems", function() did("full scan") end)
set("C_AuctionHouse", "GetNumReplicateItems", function() return 3 end)
-- AuctionHouseDocumentation.lua: 18 values, the index starts at 0. Count is the third, the
-- buyout of the stack the tenth, the item ID the seventeenth.
set("C_AuctionHouse", "GetReplicateItemInfo", function(index)
  local rows = { { 2589, 20, 3000 }, { 2589, 10, 1400 }, { 769, 8, 280 } }
  local row = rows[index + 1]
  if row then
    return "Item", 1, row[2], 1, true, 1, "", 0, 0, row[3], 0, nil, "", "", nil, 0, row[1], true
  end
end)

-- Mail: one invoice of a sale.
local MAIL_FRAME = "Blizzard_MailFrame/MailFrame.lua"
setGlobal("GetInboxNumItems", function() return 1, 1 end, MAIL_FRAME)
setGlobal("GetInboxInvoiceInfo", function(index)
  if index == 1 then
    return "seller", "Linen Cloth", "Buyer", 1000, 1000, 50, 50, 0, 0, 0, 20, false
  end
end, MAIL_FRAME)
setGlobal("GetInboxHeaderInfo", function()
  return nil, nil, "Auction House", "Auction successful: Linen Cloth", 1000, 0, 29.5, 0, false
end, MAIL_FRAME)
-- The game's MailFrame.lua calls TakeInboxMoney(self.mailIndex) and AutoLootMailItem(index).
-- The stand-in notes each call; the mail stays.
setGlobal("TakeInboxMoney", function(index) did("take inbox money", index) end, MAIL_FRAME)
setGlobal("AutoLootMailItem", function(index) did("loot mail", index) end, MAIL_FRAME)
-- The loot window: H.world.loot is the list of its items, each { name, quest, questID }. The
-- window is empty until a scenario sets it. LootFrame.lua:227-228 calls GetNumLootItems and
-- GetLootSlotInfo(slot) and takes ten results from the second: texture, item, quantity,
-- currencyID, quality, locked, isQuestItem, questID, isActive, isCoin. Not in the documentation.
local LOOT_FRAME = "Blizzard_UIPanels_Game/Mainline/LootFrame.lua"
H.world.loot = {}
setGlobal("GetNumLootItems", function() return #H.world.loot end, LOOT_FRAME)
setGlobal("GetLootSlotInfo", function(slot)
  local item = H.world.loot[slot]
  if not item then
    return nil
  end
  return "Interface\\Icons\\INV_Misc_Note_01", item.name, 1, nil, 1, false, item.quest or false, item.questID, false, false
end, LOOT_FRAME)
-- The equipment sets of the character: H.world.equipmentSets is the list, each { id, name, icon,
-- items }. The default is one set with the two items of the world (2589 and 2211). The game's
-- own code calls these functions (EquipmentManager.lua, ActionBarEditFrame.lua,
-- SecureTemplates.lua), and they are documented in EquipmentManagerDocumentation.lua. The
-- driver fires EQUIPMENT_SETS_CHANGED with the other events that an addon registers.
H.world.equipmentSets = { { id = 1, name = "Tank", icon = 133, items = { 2589, 2211 } } }
local function equipmentSet(id)
  for _, set in ipairs(H.world.equipmentSets) do
    if set.id == id then
      return set
    end
  end
  return nil
end
set("C_EquipmentSet", "GetEquipmentSetIDs", function()
  local ids = {}
  for _, entry in ipairs(H.world.equipmentSets) do
    ids[#ids + 1] = entry.id
  end
  return ids
end)
set("C_EquipmentSet", "GetNumEquipmentSets", function() return #H.world.equipmentSets end)
set("C_EquipmentSet", "GetEquipmentSetID", function(name)
  for _, entry in ipairs(H.world.equipmentSets) do
    if entry.name == name then
      return entry.id
    end
  end
  return nil
end)
set("C_EquipmentSet", "GetEquipmentSetInfo", function(id)
  local entry = equipmentSet(id)
  if not entry then
    return nil
  end
  -- name, iconFileID, setID, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored
  return entry.name, entry.icon, entry.id, false, #entry.items, 0, #entry.items, 0, 0
end)
set("C_EquipmentSet", "GetItemIDs", function(id)
  local entry = equipmentSet(id)
  if not entry then
    return nil
  end
  local items = {}
  for index, item in ipairs(entry.items) do
    items[index] = item
  end
  return items
end)
-- The mail window (Blizzard_MailFrame/MailFrame.xml), hidden until the mailbox opens.
MailFrame = CreateFrame("Frame", "MailFrame", UIParent)
MailFrame:Hide()
H.gameFrameSet[MailFrame] = true

---------------------------------------------------------------------------------------------------
-- The fight
--
-- DamageMeterDocumentation.lua: the four session functions are secret in a fight. Every field
-- is secret then, but the ones marked NeverSecret: classFilename, isLocalPlayer, deathRecapID
-- and classification. specIconID is secret at all times. The data here is plain: 01-api.lua
-- makes the values secret from the marks of the documentation, as for every function.

local function fightSources()
  return {
    {
      sourceGUID = "Player-1-00000002", name = "Otherplayer", classFilename = "MAGE",
      specIconID = 0, totalAmount = 5400, amountPerSecond = 180, isLocalPlayer = false,
      deathRecapID = 0, deathTimeSeconds = -1, classification = "",
      sourceDisplayType = Enum.DamageMeterSourceDisplayType.Ally,
    },
    {
      sourceGUID = "Player-1-00000001", name = "Tester", classFilename = "WARRIOR",
      specIconID = 0, totalAmount = 3600, amountPerSecond = 120, isLocalPlayer = true,
      deathRecapID = 0, deathTimeSeconds = -1, classification = "",
      sourceDisplayType = Enum.DamageMeterSourceDisplayType.Ally,
    },
  }
end
local function fight()
  return { combatSources = fightSources(), maxAmount = 5400, totalAmount = 9000, durationSeconds = 30 }
end
set("C_DamageMeter", "IsDamageMeterAvailable", function() return true, "" end)
set("C_DamageMeter", "GetCombatSessionFromType", fight)
set("C_DamageMeter", "GetCombatSessionFromID", fight)
set("C_DamageMeter", "GetSessionDurationSeconds", function() return 30 end)
set("C_DamageMeter", "GetAvailableCombatSessions", function()
  return { { sessionID = 1, name = "Hogger", durationSeconds = 30 } }
end)
set("C_DamageMeter", "ResetAllCombatSessions", function() did("reset damage data") end)
-- The documentation does not open these two to a secret argument from addon code: `set` refuses
-- a secret source GUID before this function runs.
local function fightSource()
  return {
    maxAmount = 2000, totalAmount = 3600,
    combatSpells = { {
      spellID = 78, totalAmount = 2000, amountPerSecond = 66, creatureName = "",
      overkillAmount = 0, isAvoidable = false, isDeadly = false, combatSpellDetails = {},
    } },
  }
end
set("C_DamageMeter", "GetCombatSessionSourceFromType", fightSource)
set("C_DamageMeter", "GetCombatSessionSourceFromID", fightSource)
-- SpellDocumentation.lua: open to a secret spell ID from addon code. The name is secret then.
set("C_Spell", "GetSpellName", function(spellID)
  if secrets[spellID] ~= nil then
    return H.secret("Heroic Strike")
  end
  return "Heroic Strike"
end)

-- The frames above are the game's own: the driver does not use them as frames of the addon.
H.gameFrames = #H.frames

return H
