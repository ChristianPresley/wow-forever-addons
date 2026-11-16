local _, ns = ...

-- What the Forever Atlas map shows on top of the art: one kind for each sort of thing that the
-- game tells an addon about. Each kind can be turned off (the button "Show" of the map, and the
-- settings page).
--
-- A kind has find(mapID, add). It calls add(x, y, data) for each thing, with x, y from 0 to 100
-- and data = { look, size, tooltip = fn(tooltip), click = fn(button), quest = questID }.
-- The icon is the one that the map of the game uses where the game names it (an atlas), with a
-- picture of an old icon file for a client that lacks the atlas.

local POI_ICONS = "Interface/Minimap/POIIcons"

-- x, y (0 to 1) of a position object of the game, or nil.
local function xy(position)
  if type(position) ~= "table" or type(position.GetXY) ~= "function" then
    return nil
  end
  local x, y = position:GetXY()
  if not ns.Usable(x) or not ns.Usable(y) then
    return nil
  end
  return x, y
end

local function text(value, fallback)
  return type(value) == "string" and value ~= "" and not (issecretvalue and issecretvalue(value)) and value or fallback
end

-- A tooltip with a title and lines under it.
local function lines(title, ...)
  local rest = { ... }
  return function(tooltip)
    tooltip:AddLine(title, 1, 0.82, 0)
    for _, line in ipairs(rest) do
      if type(line) == "string" and line ~= "" then
        tooltip:AddLine(line, 1, 1, 1, true)
      end
    end
  end
end

-- The look of a point of interest: its atlas, or its picture in the sheet of map icons.
local function poiLook(info, fallback)
  if type(info.atlasName) == "string" and info.atlasName ~= "" then
    return { atlas = info.atlasName, texture = fallback }
  end
  if ns.Usable(info.textureIndex) and C_Minimap and C_Minimap.GetPOITextureCoords then
    local ok, left, right, top, bottom = pcall(C_Minimap.GetPOITextureCoords, info.textureIndex)
    if ok and ns.Usable(left) and ns.Usable(right) and ns.Usable(top) and ns.Usable(bottom) then
      return { texture = POI_ICONS, coords = { left, right, top, bottom } }
    end
  end
  return { texture = fallback }
end

local function openQuest(questID)
  return function()
    if type(QuestMapFrame_OpenToQuestDetails) == "function" then
      ns.HideMap()
      pcall(QuestMapFrame_OpenToQuestDetails, questID)
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Quests

local TURN_IN = { atlas = "QuestTurnin", texture = "Interface\\GossipFrame\\ActiveQuestIcon" }
local OBJECTIVE = { atlas = "QuestObjective", texture = "Interface\\GossipFrame\\IncompleteQuestIcon" }

-- The quests of the quest log with a place on this map: ready to turn in, or not yet.
local function logQuests(wantReady)
  return function(mapID, add)
    local ok, quests = pcall(C_QuestLog.GetQuestsOnMap, mapID)
    if not ok or type(quests) ~= "table" then
      return
    end
    for _, quest in ipairs(quests) do
      local questID = quest.questID
      if questID and ns.Usable(quest.x) and ns.Usable(quest.y) then
        local ready = C_QuestLog.IsComplete(questID) and true or false
        if ready == wantReady then
          local title = text(C_QuestLog.GetTitleForQuestID(questID), "Quest")
          add(quest.x * 100, quest.y * 100, {
            look = ready and TURN_IN or OBJECTIVE,
            size = ready and 24 or 20,
            quest = questID,
            tooltip = lines(title, ready and "Ready to turn in" or "In progress", "Click to open the quest"),
            click = openQuest(questID),
          })
        end
      end
    end
  end
end

-- The icon of a quest that can be started, as in Blizzard_SharedMapDataProviders/QuestOfferDataProvider.lua.
local function offerLook(quest)
  local atlas = "QuestNormal"
  if quest.isLegendary then
    atlas = "UI-QuestPoiLegendary-QuestBang"
  elseif quest.isImportant then
    atlas = "importantavailablequesticon"
  elseif quest.isCampaign then
    atlas = "Quest-Campaign-Available"
  elseif quest.isMeta then
    atlas = "quest-wrapper-available"
  elseif quest.isDaily then
    atlas = "UI-QuestPoiRecurring-QuestBang"
  end
  return { atlas = atlas, texture = "Interface\\GossipFrame\\AvailableQuestIcon" }
end

-- The game sends the quests that a map offers after a request: one request for each map, and
-- again after a minute.
local requested = {}

local function questGivers(mapID, add)
  if not (C_QuestLine and C_QuestLine.GetAvailableQuestLines) then
    return
  end
  local now = GetTime()
  if C_QuestLine.RequestQuestLinesForMap and (not requested[mapID] or now - requested[mapID] > 60) then
    requested[mapID] = now
    pcall(C_QuestLine.RequestQuestLinesForMap, mapID)
  end
  local ok, offers = pcall(C_QuestLine.GetAvailableQuestLines, mapID)
  if not ok or type(offers) ~= "table" then
    return
  end
  -- A quest giver on another floor (a cellar, a tower) is not at that place of this map.
  local sameFloor = Enum and Enum.QuestLineFloorLocation and Enum.QuestLineFloorLocation.Same
  local seen = {}
  for _, quest in ipairs(offers) do
    local questID = quest.questID
    if questID and not seen[questID] and ns.Usable(quest.x) and ns.Usable(quest.y) and not quest.isHidden and not quest.inProgress
      and (quest.floorLocation == nil or sameFloor == nil or quest.floorLocation == sameFloor) then
      seen[questID] = true
      local kind = quest.isDaily and "Daily quest" or quest.isCampaign and "Campaign quest" or "Quest to start"
      add(quest.x * 100, quest.y * 100, {
        look = offerLook(quest),
        size = 22,
        tooltip = lines(text(quest.questName, "Quest"), kind, text(quest.questLineName, nil)),
      })
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Places of the game

local function flightMasters(mapID, add)
  if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then
    return
  end
  local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
  if not ok or type(nodes) ~= "table" then
    return
  end
  local factions = Enum and Enum.FlightPathFaction
  local mine = UnitFactionGroup("player")
  local other = factions and (mine == "Alliance" and factions.Horde or mine == "Horde" and factions.Alliance) or nil
  for _, node in ipairs(nodes) do
    local x, y = xy(node.position)
    if x and (other == nil or node.faction ~= other) then
      local look = poiLook(node, "Interface\\TaxiFrame\\UI-Taxi-Icon-White")
      if node.isUndiscovered then
        look.color = { 0.55, 0.55, 0.55 }
      end
      add(x * 100, y * 100, {
        look = look,
        size = 20,
        tooltip = lines(text(node.name, "Flight master"), node.isUndiscovered and "Flight master, not visited yet" or "Flight master"),
      })
    end
  end
end

local function areaPOIs(mapID, add)
  if not (C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap and C_AreaPoiInfo.GetAreaPOIInfo) then
    return
  end
  local ok, ids = pcall(C_AreaPoiInfo.GetAreaPOIForMap, mapID)
  if not ok or type(ids) ~= "table" then
    return
  end
  for _, id in ipairs(ids) do
    local okInfo, info = pcall(C_AreaPoiInfo.GetAreaPOIInfo, mapID, id)
    if okInfo and type(info) == "table" then
      local x, y = xy(info.position)
      if x then
        add(x * 100, y * 100, {
          look = poiLook(info, "Interface\\Minimap\\Tracking\\None"),
          size = 22,
          tooltip = lines(text(info.name, "Place"), text(info.description, nil)),
        })
      end
    end
  end
end

-- A list of the game where each entry has a name, a position and an icon.
local function poiList(get, fallback, label)
  return function(mapID, add)
    local fn = get()
    if type(fn) ~= "function" then
      return
    end
    local ok, list = pcall(fn, mapID)
    if not ok or type(list) ~= "table" then
      return
    end
    for _, info in ipairs(list) do
      local x, y = xy(info.position)
      if x then
        local linked = ns.Usable(info.linkedUiMapID) and info.linkedUiMapID > 0 and info.linkedUiMapID or nil
        add(x * 100, y * 100, {
          look = poiLook(info, fallback),
          size = 22,
          tooltip = lines(text(info.name, label), label, text(info.description, nil), linked and "Click to open that map" or nil),
          click = linked and function()
            ns.ShowMap(linked)
          end or nil,
        })
      end
    end
  end
end

local function rares(mapID, add)
  if not (C_VignetteInfo and C_VignetteInfo.GetVignettes and C_VignetteInfo.GetVignetteInfo and C_VignetteInfo.GetVignettePosition) then
    return
  end
  for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
    local info = C_VignetteInfo.GetVignetteInfo(guid)
    if type(info) == "table" and not info.isDead then
      local ok, position = pcall(C_VignetteInfo.GetVignettePosition, guid, mapID)
      local x, y = xy(ok and position or nil)
      if x then
        add(x * 100, y * 100, {
          look = poiLook(info, "Interface\\Minimap\\ObjectIconsAtlas"),
          size = 24,
          tooltip = lines(text(info.name, "Rare"), "Rare enemy, treasure or event"),
        })
      end
    end
  end
end

---------------------------------------------------------------------------------------------------
-- The player and the group

local GROUP_LOOK = { atlas = "WhiteCircle-RaidBlips", texture = "Interface\\Buttons\\WHITE8X8", color = { 0.35, 0.7, 1 } }

local function groupMembers(mapID, add)
  if not (IsInGroup and IsInGroup()) then
    return
  end
  local raid = IsInRaid and IsInRaid()
  for index = 1, raid and 40 or 4 do
    local unit = (raid and "raid" or "party") .. index
    if UnitExists(unit) and not (UnitIsUnit and UnitIsUnit(unit, "player")) then
      local ok, position = pcall(C_Map.GetPlayerMapPosition, mapID, unit)
      local x, y = xy(ok and position or nil)
      if x then
        add(x * 100, y * 100, {
          look = GROUP_LOOK,
          size = 12,
          tooltip = lines(text(UnitName(unit), "Group member"), raid and "Member of your raid" or "Member of your party"),
        })
      end
    end
  end
end

local function corpse(mapID, add)
  if not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then
    return
  end
  local ok, position = pcall(C_DeathInfo.GetCorpseMapPosition, mapID)
  local x, y = xy(ok and position or nil)
  if x then
    add(x * 100, y * 100, {
      look = { atlas = "poi-torghast", texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
      size = 22,
      tooltip = lines("Your corpse"),
    })
  end
end

local function mapPin(mapID, add)
  if not C_Map.GetUserWaypoint then
    return
  end
  local ok, point = pcall(C_Map.GetUserWaypoint)
  if not ok or type(point) ~= "table" or not point.uiMapID then
    return
  end
  local x, y = xy(point.position)
  if not x then
    return
  end
  local onMapX, onMapY = ns.ProjectToMap(point.uiMapID, x * 100, y * 100, mapID)
  if onMapX then
    add(onMapX, onMapY, {
      look = { atlas = "Waypoint-MapPin-Tracked", texture = "Interface\\Minimap\\Ping\\ping5" },
      size = 24,
      tooltip = lines("Map pin", "The pin that you put on the map of the game"),
    })
  end
end

-- The places that Forever Compass has learned, if that addon is there: vendors, repairers,
-- mailboxes, trainers, bankers and auctioneers.
local LEARNED = {
  vendor = { "Vendor", { 1, 0.85, 0.3 } }, repair = { "Repairer", { 0.8, 0.8, 0.8 } }, mailbox = { "Mailbox", { 1, 1, 0.6 } },
  trainer = { "Trainer", { 0.5, 1, 0.5 } }, bank = { "Banker", { 1, 0.7, 0.2 } }, auction = { "Auctioneer", { 0.9, 0.6, 1 } },
}

local function learnedPlaces(mapID, add)
  local db = _G["ForeverCompassDB"]
  local places = type(db) == "table" and db.places
  if type(places) ~= "table" then
    return
  end
  for kind, entry in pairs(LEARNED) do
    for _, place in ipairs(type(places[kind]) == "table" and places[kind] or {}) do
      if type(place) == "table" and place.mapID == mapID and ns.Usable(place.x) and ns.Usable(place.y) then
        add(place.x * 100, place.y * 100, {
          look = { atlas = "WhiteCircle-RaidBlips", texture = "Interface\\Buttons\\WHITE8X8", color = entry[2] },
          size = 10,
          tooltip = lines(text(place.name, entry[1]), entry[1], "Learned by Forever Compass"),
        })
      end
    end
  end
end

---------------------------------------------------------------------------------------------------
-- The kinds, in the order of the menu. A later kind is drawn over an earlier one.

ns.MAP_KINDS = {
  { key = "areaPOIs", name = "Towns and landmarks", find = areaPOIs },
  { key = "learned", name = "Vendors, mailboxes and trainers (Forever Compass)", find = learnedPlaces },
  { key = "graveyards", name = "Graveyards", find = poiList(function() return C_DeathInfo and C_DeathInfo.GetGraveyardsForMap end, "Interface\\Minimap\\Tracking\\None", "Graveyard") },
  { key = "dungeons", name = "Dungeon entrances", find = poiList(function() return C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap end, "Interface\\Minimap\\Tracking\\None", "Dungeon entrance") },
  { key = "links", name = "Ways to other maps", find = poiList(function() return C_Map.GetMapLinksForMap end, "Interface\\Minimap\\Tracking\\None", "Way to another map") },
  { key = "flight", name = "Flight masters", find = flightMasters },
  { key = "rares", name = "Rare enemies and treasures", find = rares },
  { key = "questObjectives", name = "Quest objectives", find = logQuests(false) },
  { key = "questGivers", name = "Quest givers", find = questGivers },
  { key = "questTurnIns", name = "Quest turn-ins", find = logQuests(true) },
  { key = "group", name = "Group members", find = groupMembers },
  { key = "corpse", name = "Your corpse", find = corpse },
  { key = "mapPin", name = "Your map pin", find = mapPin },
}

-- The name of the option of a kind, in ForeverAtlasDB.options.
function ns.MapKindOption(key)
  return "show_" .. key
end

for _, kind in ipairs(ns.MAP_KINDS) do
  ns.defaults[ns.MapKindOption(kind.key)] = true
end
ns.defaults.zoneNames = true -- the names of the zones on a map of a continent
ns.defaults.zoneHighlight = true -- the zone under the pointer lights up
