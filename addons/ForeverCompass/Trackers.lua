local _, ns = ...

-- The kinds of things that a compass can point to.
--
-- Each kind has a function find(mapID, add, addWorld) that reports the things it knows now:
--   add(x, y, name, onMapID, questID, look)   a point of a map, x and y from 0 to 1; onMapID is mapID if left
--   addWorld(continent, north, west, name)   a world position in yards
-- A kind has a look: the icon of the game for what it points to, { atlas = , texture = ,
-- coords = }. The texture is the picture for a client without the atlas. A target can have a
-- look of its own (a quest that is ready has the icon of a turn-in). A kind without a look
-- has the round marker in the colour of the tracker.
-- mapID is the map the player is on. ns.FindTargets turns all of them into world positions.

local function questsOnMap(mapID)
  if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then
    return {}
  end
  local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
  return ok and type(list) == "table" and list or {}
end

local function questName(questID)
  local name = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
  return type(name) == "string" and name ~= "" and name or "Quest"
end

local function isComplete(questID)
  return C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) and true or false
end

-- Every objective of the quest is done. The game can leave a quest unflagged as complete after
-- its last objective, so a quest with all of them done is ready to hand in too.
local function allObjectivesDone(questID)
  if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then
    return false
  end
  local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
  if not ok or type(list) ~= "table" or #list == 0 then
    return false
  end
  for _, objective in ipairs(list) do
    if type(objective) ~= "table" or objective.finished ~= true then
      return false
    end
  end
  return true
end

-- Ready to hand in: flagged complete, or every objective done.
local function readyToTurnIn(questID)
  return isComplete(questID) or allObjectivesDone(questID)
end

-- The icons of the game, as the map and the minimap show them.
local OBJECTIVE = { atlas = "QuestObjective", texture = "Interface\\GossipFrame\\IncompleteQuestIcon" }
local TURN_IN = { atlas = "QuestTurnin", texture = "Interface\\GossipFrame\\ActiveQuestIcon" }
local GIVER = { atlas = "QuestNormal", texture = "Interface\\GossipFrame\\AvailableQuestIcon" }
local RARE = { atlas = "VignetteKill", texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" }
local LOOKS = {
  vendor = { texture = "Interface\\GossipFrame\\VendorGossipIcon" },
  repair = { atlas = "Repair", texture = "Interface\\Minimap\\Tracking\\Repair" },
  flight = { atlas = "FlightMaster", texture = "Interface\\GossipFrame\\TaxiGossipIcon" },
  mailbox = { atlas = "Mailbox", texture = "Interface\\Minimap\\Tracking\\Mailbox" },
  trainer = { atlas = "Profession", texture = "Interface\\GossipFrame\\TrainerGossipIcon" },
  bank = { atlas = "Banker", texture = "Interface\\GossipFrame\\BankerGossipIcon" },
  auction = { atlas = "Auctioneer", texture = "Interface\\Minimap\\Tracking\\Auctioneer" },
  -- The cross of a corpse, a part of the sheet of map icons.
  corpse = { texture = "Interface\\Minimap\\POIIcons", coords = { 0.56640625, 0.6328125, 0.001953125, 0.03515625 } },
  mapPin = { atlas = "Waypoint-MapPin-Tracked", texture = "Interface\\Minimap\\Ping\\ping5" },
}

-- The look of a quest of the log: ready to turn in, or with something left to do.
local function questLook(questID)
  return readyToTurnIn(questID) and TURN_IN or OBJECTIVE
end

-- Quests of the log with a point on the map. wantComplete chooses the turn-ins or the objectives.
local function logQuests(mapID, add, wantComplete)
  for _, quest in ipairs(questsOnMap(mapID)) do
    if quest.questID and quest.x and quest.y and readyToTurnIn(quest.questID) == wantComplete then
      add(quest.x, quest.y, questName(quest.questID), nil, quest.questID)
    end
  end
end

-- The game sends the quests that an area offers after a request. One request for each map, and
-- again after a while, is enough.
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
  local ok, list = pcall(C_QuestLine.GetAvailableQuestLines, mapID)
  if not ok or type(list) ~= "table" then
    return
  end
  local sameFloor = Enum and Enum.QuestLineFloorLocation and Enum.QuestLineFloorLocation.Same
  local seen = {}
  for _, quest in ipairs(list) do
    local id = quest.questID
    if id and quest.x and quest.y and not quest.isHidden and not quest.inProgress and not seen[id]
      and (quest.floorLocation == nil or sameFloor == nil or quest.floorLocation == sameFloor) then
      seen[id] = true
      add(quest.x, quest.y, type(quest.questName) == "string" and quest.questName or "Quest giver")
    end
  end
end

local function trackedQuest(mapID, add)
  local tracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
  if not tracked or tracked == 0 then
    return
  end
  for _, quest in ipairs(questsOnMap(mapID)) do
    if quest.questID == tracked and quest.x and quest.y then
      add(quest.x, quest.y, questName(tracked), nil, tracked, questLook(tracked))
    end
  end
end

-- Vignettes are the game's markers for rare enemies, treasures and events near the player.
local function rares(mapID, add)
  if not (C_VignetteInfo and C_VignetteInfo.GetVignettes and C_VignetteInfo.GetVignetteInfo and C_VignetteInfo.GetVignettePosition) then
    return
  end
  for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
    local info = C_VignetteInfo.GetVignetteInfo(guid)
    if info and not info.isDead then
      local ok, position = pcall(C_VignetteInfo.GetVignettePosition, guid, mapID)
      if ok and position then
        local x, y = position:GetXY()
        -- The game can hide the name and the icon of a rare (a secret value): a secret value is
        -- not compared, so a hidden name is a plain "Rare" and a hidden icon is the skull.
        local name, atlas = info.name, info.atlasName
        local hiddenName = (issecretvalue and issecretvalue(name)) or type(name) ~= "string" or name == ""
        local hiddenAtlas = (issecretvalue and issecretvalue(atlas)) or type(atlas) ~= "string" or atlas == ""
        local own = not hiddenAtlas and { atlas = atlas, texture = RARE.texture } or nil
        add(x, y, hiddenName and "Rare" or name, nil, nil, own)
      end
    end
  end
end

-- The continent that a map is on, or the map itself.
local function continentOf(mapID)
  local continentType = Enum and Enum.UIMapType and Enum.UIMapType.Continent
  local current = mapID
  for _ = 1, 6 do
    local info = current and C_Map.GetMapInfo(current)
    if not info or not continentType then
      return mapID
    end
    if info.mapType == continentType then
      return current
    end
    current = info.parentMapID
  end
  return mapID
end

-- One quest of the log, chosen by the player (ForeverCompass.TrackQuest): its point on the
-- map of the player, or on the map of the continent if the quest is in another zone.
local function oneQuest(mapID, add, _, questID)
  if not questID or questID == 0 then
    return
  end
  local continent = continentOf(mapID)
  for _, onMap in ipairs(continent ~= mapID and { mapID, continent } or { mapID }) do
    for _, quest in ipairs(questsOnMap(onMap)) do
      if quest.questID == questID and quest.x and quest.y then
        add(quest.x, quest.y, questName(questID), onMap, questID, questLook(questID))
        return
      end
    end
  end
end

local function flightMasters(mapID, add)
  if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then
    return
  end
  -- The continent map lists the flight masters of all its zones.
  local onMap = continentOf(mapID)
  local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, onMap)
  if not ok or type(nodes) ~= "table" then
    return
  end
  local factions = Enum and Enum.FlightPathFaction
  local other
  if factions then
    local mine = UnitFactionGroup("player")
    other = mine == "Alliance" and factions.Horde or mine == "Horde" and factions.Alliance or nil
  end
  for _, node in ipairs(nodes) do
    if node.position and (other == nil or node.faction ~= other) then
      local x, y = node.position:GetXY()
      add(x, y, type(node.name) == "string" and node.name or "Flight master", onMap)
    end
  end
end

local function partyMembers(_, _, addWorld)
  for i = 1, 4 do
    local unit = "party" .. i
    if UnitExists(unit) then
      local continent, north, west = ns.UnitWorld(unit)
      if continent then
        -- The game can hide the name of a unit (a secret value): no test of it then, not
        -- even for nil. The marker gets a plain name.
        local name = UnitName(unit)
        if (issecretvalue and issecretvalue(name)) or type(name) ~= "string" then
          name = "Party member"
        end
        addWorld(continent, north, west, name)
      end
    end
  end
end

local function corpse(mapID, add)
  if not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then
    return
  end
  local ok, position = pcall(C_DeathInfo.GetCorpseMapPosition, mapID)
  if ok and position then
    local x, y = position:GetXY()
    add(x, y, "Your corpse")
  end
end

local function mapPin(_, add)
  if not (C_Map.GetUserWaypoint) then
    return
  end
  local ok, point = pcall(C_Map.GetUserWaypoint)
  if ok and point and point.uiMapID and point.position then
    local x, y = point.position:GetXY()
    add(x, y, "Map pin", point.uiMapID)
  end
end

-- A kind whose places the addon learns (Places.lua).
local function learned(kind)
  return function(_, add)
    for _, place in ipairs(ns.Places(kind)) do
      add(place.x, place.y, place.name, place.mapID)
    end
  end
end

local LEARNED = "The addon learns these places as you visit them, for all your characters."

ns.KINDS = {
  { key = "questObjectives", name = "Quest objectives", look = OBJECTIVE, find = function(mapID, add) logQuests(mapID, add, false) end,
    hint = "The quests of your log that still have something to do in this zone." },
  { key = "questTurnIns", name = "Quest turn-ins", look = TURN_IN, find = function(mapID, add) logQuests(mapID, add, true) end,
    hint = "The quests of your log that are ready to turn in." },
  { key = "questGivers", name = "Quest givers", look = GIVER, find = questGivers,
    hint = "The quests that you can start in this zone." },
  { key = "trackedQuest", name = "Tracked quest", look = OBJECTIVE, find = trackedQuest,
    hint = "The quest that you track on the map (the one with the arrow)." },
  { key = "quest", name = "One quest (chosen in the quest log)", look = OBJECTIVE, find = oneQuest,
    hint = "One quest of your log. Forever Quests sets it with the compass button of a quest." },
  { key = "rares", name = "Rare enemies and treasures", look = RARE, find = rares,
    hint = "The rare enemies, treasures and events that the game marks near you." },
  { key = "vendor", name = "Vendors", find = learned("vendor"), learned = true, hint = LEARNED },
  { key = "repair", name = "Repairers", find = learned("repair"), learned = true, hint = LEARNED },
  { key = "flight", name = "Flight masters", find = flightMasters,
    hint = "The flight masters of your faction on this continent." },
  { key = "mailbox", name = "Mailboxes", find = learned("mailbox"), learned = true, hint = LEARNED },
  { key = "trainer", name = "Trainers", find = learned("trainer"), learned = true, hint = LEARNED },
  { key = "bank", name = "Bankers", find = learned("bank"), learned = true, hint = LEARNED },
  { key = "auction", name = "Auctioneers", find = learned("auction"), learned = true, hint = LEARNED },
  { key = "party", name = "Party members", find = partyMembers,
    hint = "The members of your party. The game hides them in instances." },
  { key = "corpse", name = "Your corpse", find = corpse,
    hint = "Your corpse, while you are a ghost." },
  { key = "mapPin", name = "Map pin", find = mapPin,
    hint = "The pin that you put on the world map." },
}

ns.KindByKey = {}
for _, kind in ipairs(ns.KINDS) do
  ns.KindByKey[kind.key] = kind
  kind.look = kind.look or LOOKS[kind.key]
end

-- World positions of map points are the same each time, so they are kept.
local cache, cached = {}, 0

local function worldOf(mapID, x, y)
  local id = mapID .. ":" .. x .. ":" .. y
  local known = cache[id]
  if known == nil then
    local continent, north, west = ns.WorldPosition(mapID, x, y)
    known = continent and { continent, north, west } or false
    if cached > 4000 then
      cache, cached = {}, 0
    end
    cache[id] = known
    cached = cached + 1
  end
  return known
end

-- The things of a kind that are known now: { { continent, north, west, name, questID, look }, ... }.
-- look: the icon of this one, where it is not the icon of its kind.
-- questID: for the kind "quest", the quest to point to.
function ns.FindTargets(kindKey, questID)
  local kind = ns.KindByKey[kindKey]
  local mapID = ns.PlayerMap()
  local targets = {}
  if not kind or not mapID then
    return targets
  end
  local function add(x, y, name, onMapID, questID, look)
    if ns.Usable(x) and ns.Usable(y) then
      local world = worldOf(onMapID or mapID, x, y)
      if world then
        targets[#targets + 1] = { world[1], world[2], world[3], name, questID, look }
      end
    end
  end
  local function addWorld(continent, north, west, name)
    targets[#targets + 1] = { continent, north, west, name }
  end
  local ok, err = pcall(kind.find, mapID, add, addWorld, questID)
  if not ok then
    geterrorhandler()(err)
  end
  return targets
end
