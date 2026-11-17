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

-- A secret text cannot be compared, not even with "": that test is first.
local function text(value, fallback)
  if issecretvalue and issecretvalue(value) then
    return fallback
  end
  return type(value) == "string" and value ~= "" and value or fallback
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
      -- The game does not let an addon open a window in a fight: it would show an error and
      -- still change the chosen quest of the log.
      if InCombatLockdown and InCombatLockdown() then
        ns.Print("the quest log cannot open in a fight. Click again after it.")
        return
      end
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
            -- The objectives are read when the tooltip shows: they change while the map is open.
            tooltip = function(tooltip)
              tooltip:AddLine(title, 1, 0.82, 0)
              local shown = 0
              if ready then
                tooltip:AddLine("Ready to turn in", 0.4, 1, 0.4, true)
              elseif C_QuestLog.GetQuestObjectives then
                local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
                for _, objective in ipairs(ok and type(objectives) == "table" and objectives or {}) do
                  local line = text(objective.text, nil)
                  if line then
                    shown = shown + 1
                    local grey = objective.finished == true
                    tooltip:AddLine((grey and "Done: " or "") .. line, grey and 0.6 or 1, grey and 0.6 or 1, grey and 0.6 or 1, true)
                  end
                end
              end
              if not ready and shown == 0 then
                tooltip:AddLine("In progress", 1, 1, 1, true)
              end
              tooltip:AddLine("Click to open the quest", 0.6, 0.6, 0.6, true)
            end,
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

-- World quests and bonus objectives: quests of an area that are not in the quest log
-- (Blizzard_SharedMapDataProviders/BonusObjectiveDataProvider.lua).
local TASK = { atlas = "QuestBonusObjective", texture = "Interface\\GossipFrame\\AvailableQuestIcon", fallbackColor = { 0.5, 0.8, 1 } }

local function taskQuests(mapID, add)
  if not (C_TaskQuest and C_TaskQuest.GetQuestsOnMap) then
    return
  end
  local ok, tasks = pcall(C_TaskQuest.GetQuestsOnMap, mapID)
  if not ok or type(tasks) ~= "table" then
    return
  end
  for _, task in ipairs(tasks) do
    local questID = task.questID
    -- The game lists the quests of the maps under this one too, each with its own map.
    if ns.Usable(questID) and ns.Usable(task.x) and ns.Usable(task.y) and (task.mapID == nil or task.mapID == mapID) then
      local okTitle, title = pcall(C_TaskQuest.GetQuestInfoByQuestID, questID)
      add(task.x * 100, task.y * 100, {
        look = TASK,
        size = 22,
        task = questID,
        tooltip = lines(text(okTitle and title or nil, "Quest of this area"), task.inProgress and "In progress" or "World quest or bonus objective"),
      })
    end
  end
end

-- The next step on the way to the quest that the player follows, when its goal is not on this
-- map (Blizzard_SharedMapDataProviders/QuestDataProvider.lua).
local function questWaypoint(mapID, add)
  if not (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_QuestLog.GetNextWaypointForMap) then
    return
  end
  local okQuest, questID = pcall(C_SuperTrack.GetSuperTrackedQuestID)
  if not okQuest or not ns.Usable(questID) or questID <= 0 then
    return
  end
  local ok, x, y = pcall(C_QuestLog.GetNextWaypointForMap, questID, mapID)
  if ok and ns.Usable(x) and ns.Usable(y) then
    add(x * 100, y * 100, {
      look = { atlas = "Waypoint-MapPin-Untracked", texture = "Interface\\Minimap\\Ping\\ping5", color = { 1, 0.82, 0 } },
      size = 22,
      wayTo = questID,
      tooltip = lines(text(C_QuestLog.GetTitleForQuestID(questID), "Quest"), "The way to the quest that you follow", "Click to open the quest"),
      click = openQuest(questID),
    })
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
  local treasure = Enum and Enum.VignetteType and Enum.VignetteType.Treasure
  for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
    local info = C_VignetteInfo.GetVignetteInfo(guid)
    if type(info) == "table" and not info.isDead then
      local ok, position = pcall(C_VignetteInfo.GetVignettePosition, guid, mapID)
      local x, y = xy(ok and position or nil)
      if x then
        local isTreasure = treasure ~= nil and info.type == treasure
        add(x * 100, y * 100, {
          look = poiLook(info, "Interface\\Minimap\\ObjectIconsAtlas"),
          size = 24,
          tooltip = lines(text(info.name, isTreasure and "Treasure" or "Rare"), isTreasure and "Treasure" or "Rare enemy, treasure or event"),
        })
      end
    end
  end
end

-- The place that a guard of a town pointed out ("Where is the bank?"): the game keeps one for
-- each map (Blizzard_SharedMapDataProviders/GossipDataProvider.lua).
local function guardPlace(mapID, add)
  if not (C_GossipInfo and C_GossipInfo.GetPoiForUiMapID and C_GossipInfo.GetPoiInfo) then
    return
  end
  local okID, id = pcall(C_GossipInfo.GetPoiForUiMapID, mapID)
  if not okID or not ns.Usable(id) then
    return
  end
  local ok, info = pcall(C_GossipInfo.GetPoiInfo, mapID, id)
  local x, y = xy(ok and type(info) == "table" and info.position or nil)
  if x then
    add(x * 100, y * 100, {
      look = poiLook(info, "Interface\\Minimap\\Tracking\\None"),
      size = 26,
      tooltip = lines(text(info.name, "Place"), "A guard showed you this place"),
    })
  end
end

local function timeLeft(seconds)
  if seconds >= 3600 then
    return string.format("%d h %d min left", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
  end
  return string.format("%d min left", math.max(1, math.floor(seconds / 60)))
end

-- Events of the game on this map, with the time that is left
-- (Blizzard_SharedMapDataProviders/AreaPOIEventDataProvider.lua).
local function events(mapID, add)
  if not (C_AreaPoiInfo and C_AreaPoiInfo.GetEventsForMap and C_AreaPoiInfo.GetAreaPOIInfo) then
    return
  end
  local ok, ids = pcall(C_AreaPoiInfo.GetEventsForMap, mapID)
  if not ok or type(ids) ~= "table" then
    return
  end
  for _, id in ipairs(ids) do
    local okInfo, info = pcall(C_AreaPoiInfo.GetAreaPOIInfo, mapID, id)
    local x, y = xy(okInfo and type(info) == "table" and info.position or nil)
    if x then
      local name, description = text(info.name, "Event"), text(info.description, nil)
      add(x * 100, y * 100, {
        look = poiLook(info, "Interface\\Minimap\\Tracking\\None"),
        size = 24,
        -- The time that is left is read when the tooltip shows, not when the pin is made.
        tooltip = function(tooltip)
          local left
          if C_AreaPoiInfo.GetAreaPOISecondsLeft then
            local okLeft, seconds = pcall(C_AreaPoiInfo.GetAreaPOISecondsLeft, id)
            left = okLeft and ns.Usable(seconds) and seconds > 0 and timeLeft(seconds) or nil
          end
          lines(name, "Event", description, left)(tooltip)
        end,
      })
    end
  end
end

-- The bosses of a dungeon, on the map of the dungeon
-- (Blizzard_SharedMapDataProviders/EncounterJournalDataProvider.lua). The documented API of
-- this client has their places and whether they are defeated, not their names.
local function bosses(mapID, add)
  if not (C_EncounterJournal and C_EncounterJournal.GetEncountersOnMap) then
    return
  end
  local ok, list = pcall(C_EncounterJournal.GetEncountersOnMap, mapID)
  if not ok or type(list) ~= "table" then
    return
  end
  for _, boss in ipairs(list) do
    if ns.Usable(boss.mapX) and ns.Usable(boss.mapY) then
      local okDone, done = false, false
      if C_EncounterJournal.IsEncounterComplete and ns.Usable(boss.encounterID) then
        okDone, done = pcall(C_EncounterJournal.IsEncounterComplete, boss.encounterID)
      end
      local defeated = okDone and done == true
      add(boss.mapX * 100, boss.mapY * 100, {
        look = { atlas = "DungeonSkull", texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", color = defeated and { 0.5, 0.5, 0.5 } or nil },
        size = 24,
        tooltip = lines("Dungeon boss", defeated and "Defeated" or "Not defeated yet"),
      })
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
      -- The picture of the game's own corpse pin (Blizzard_SharedMapDataProviders/DeathMapDataProvider.xml).
      look = { texture = POI_ICONS, coords = { 0.56640625, 0.6328125, 0.001953125, 0.03515625 } },
      size = 24,
      tooltip = lines("Your corpse"),
    })
  end
  -- Where the spirit comes back to life after a release (the same file of the game).
  if C_DeathInfo.GetDeathReleasePosition then
    local okRelease, release = pcall(C_DeathInfo.GetDeathReleasePosition, mapID)
    local releaseX, releaseY = xy(okRelease and release or nil)
    if releaseX then
      add(releaseX * 100, releaseY * 100, {
        look = { texture = POI_ICONS, coords = { 0.56640625, 0.6328125, 0.001953125, 0.03515625 }, color = { 0.6, 0.8, 1 } },
        size = 20,
        release = true,
        tooltip = lines("Spirit healer", "Your spirit appears here when you release it"),
      })
    end
  end
end

-- Places that the game lists apart from its points of interest, each where this client has
-- them: quest hubs, delves, flying races, pet tamers and dig sites (the files of the same
-- names in Blizzard_SharedMapDataProviders). A place that is a landmark too is left to that kind.
local OTHER_IDS = {
  { "GetQuestHubsForMap", "Quest hub" }, { "GetDelvesForMap", "Delve" }, { "GetDragonridingRacesForMap", "Flying race" },
}
local OTHER_LISTS = {
  { function() return C_PetInfo and C_PetInfo.GetPetTamersForMap end, "Pet tamer" },
  { function() return C_ResearchInfo and C_ResearchInfo.GetDigSitesForMap end, "Dig site" },
}

local function otherPlaces(mapID, add)
  local landmarks = {}
  if C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap then
    local ok, ids = pcall(C_AreaPoiInfo.GetAreaPOIForMap, mapID)
    for _, id in ipairs(ok and type(ids) == "table" and ids or {}) do
      landmarks[id] = true
    end
  end
  for _, source in ipairs(OTHER_IDS) do
    local fn = C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIInfo and C_AreaPoiInfo[source[1]]
    local ok, ids = pcall(fn or error, mapID)
    for _, id in ipairs(ok and type(ids) == "table" and ids or {}) do
      if not landmarks[id] then
        landmarks[id] = true
        local okInfo, info = pcall(C_AreaPoiInfo.GetAreaPOIInfo, mapID, id)
        local x, y = xy(okInfo and type(info) == "table" and info.position or nil)
        if x then
          add(x * 100, y * 100, {
            look = poiLook(info, "Interface\\Minimap\\Tracking\\None"),
            size = 22,
            tooltip = lines(text(info.name, source[2]), source[2], text(info.description, nil)),
          })
        end
      end
    end
  end
  for _, source in ipairs(OTHER_LISTS) do
    local ok, list = pcall(source[1]() or error, mapID)
    for _, info in ipairs(ok and type(list) == "table" and list or {}) do
      local x, y = xy(type(info) == "table" and info.position or nil)
      if x then
        add(x * 100, y * 100, {
          look = poiLook(info, "Interface\\Minimap\\Tracking\\None"),
          size = 22,
          tooltip = lines(text(info.name, source[2]), source[2]),
        })
      end
    end
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

---------------------------------------------------------------------------------------------------
-- People and things that the player has used. The game does not tell an addon where a vendor,
-- a trainer or another NPC is: the addon remembers the place where the player used one.
--   ForeverAtlasDB.npcs[mapID] = { { name = s, x = n, y = n, roles = { vendor = true }, t = n }, ... }
-- with x, y from 0 to 100. They are for all characters.

-- The roles, the most telling one first: an NPC with more than one has the icon of the first.
-- The icon is an atlas of the game where the client has it, else a dot of the colour.
local ROLES = {
  { "inn", "Innkeeper", "Innkeeper", { 1, 0.6, 0.6 } },
  { "bank", "Banker", "Banker", { 1, 0.7, 0.2 } },
  { "auction", "Auctioneer", "Auctioneer", { 0.9, 0.6, 1 } },
  { "mailbox", "Mailbox", "Mailbox", { 1, 1, 0.6 } },
  { "stable", "Stable master", "StableMaster", { 0.7, 0.5, 0.3 } },
  { "trainer", "Trainer", "Profession", { 0.5, 1, 0.5 } },
  { "repair", "Repairer", "Repair", { 0.8, 0.8, 0.8 } },
  { "vendor", "Vendor", nil, { 1, 0.85, 0.3 } },
  { "quests", "Quests", nil, { 1, 1, 0 } },
  { "talk", "Talks to you", nil, { 0.6, 0.8, 1 } },
}
local ROLE = {}
for _, role in ipairs(ROLES) do
  ROLE[role[1]] = role
end

local function roleLook(role)
  return { atlas = role[3], fallbackAtlas = "WhiteCircle-RaidBlips", texture = "Interface\\Buttons\\WHITE8X8", fallbackColor = role[4] }
end

-- The size of the icon of a role: an icon of the game, or the dot.
local function roleSize(role)
  return role[3] and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(role[3]) and 18 or 10
end

-- Two things without a name (mailboxes) nearer than this, in hundredths of the map, are one.
local SAME_PLACE = 0.6

local function npcList(mapID)
  local all = ForeverAtlasDB and ForeverAtlasDB.npcs
  return type(all) == "table" and type(all[mapID]) == "table" and all[mapID] or nil
end

-- Remembers the NPC that the player talks to, or a thing without a name, with this role.
local function remember(roleKey, thing)
  if type(ForeverAtlasDB) ~= "table" then
    return
  end
  local name = thing
  if not name then
    if not UnitExists("npc") or UnitIsPlayer("npc") then
      return -- a quest from an item or from another player
    end
    name = text(UnitName("npc"), nil)
    if not name then
      return -- in a fight the game can hide the name
    end
  end
  local mapID = C_Map.GetBestMapForUnit("player")
  local x, y = ns.PlayerPosition(mapID)
  if not x then
    return -- the game hides the position here (an instance)
  end
  if type(ForeverAtlasDB.npcs) ~= "table" then
    ForeverAtlasDB.npcs = {}
  end
  local list = npcList(mapID)
  if not list then
    list = {}
    ForeverAtlasDB.npcs[mapID] = list
  end
  local entry
  for _, known in ipairs(list) do
    if type(known) == "table" and known.name == name
      and (not thing or (ns.Usable(known.x) and ns.Usable(known.y) and math.abs(known.x - x) < SAME_PLACE and math.abs(known.y - y) < SAME_PLACE)) then
      entry = known
      break
    end
  end
  if not entry then
    entry = { name = name, roles = {} }
    list[#list + 1] = entry
  end
  if type(entry.roles) ~= "table" then
    entry.roles = {}
  end
  entry.x, entry.y, entry.t = x, y, time()
  entry.roles[roleKey] = true
  ns.RefreshPins()
end

-- How many NPCs and things the addon remembers, and a way to forget them (for the settings).
function ns.CountNpcs()
  local count = 0
  for _, list in pairs(type(ForeverAtlasDB.npcs) == "table" and ForeverAtlasDB.npcs or {}) do
    count = count + (type(list) == "table" and #list or 0)
  end
  return count
end

function ns.ForgetNpcs()
  ForeverAtlasDB.npcs = {}
  ns.RefreshPins()
end

local function metNpcs(mapID, add)
  for _, entry in ipairs(npcList(mapID) or {}) do
    if type(entry) == "table" and type(entry.name) == "string" and type(entry.roles) == "table" and ns.Usable(entry.x) and ns.Usable(entry.y) then
      local first, labels = nil, {}
      for _, role in ipairs(ROLES) do
        if entry.roles[role[1]] then
          first = first or role
          labels[#labels + 1] = role[2]
        end
      end
      if first then
        local x, y, name = entry.x, entry.y, entry.name
        add(x, y, {
          look = roleLook(first),
          size = roleSize(first),
          npc = name,
          tooltip = lines(name, table.concat(labels, ", "), ns.Usable(entry.t) and ("Last used: " .. date("%Y-%m-%d", entry.t)) or nil, "Click for a waypoint to this place"),
          click = function()
            ns.AddWaypoint(mapID, x, y, name)
          end,
        })
      end
    end
  end
end

local npcEvents = {
  MERCHANT_SHOW = function()
    remember("vendor")
    if CanMerchantRepair and CanMerchantRepair() then
      remember("repair")
    end
  end,
  TRAINER_SHOW = function() remember("trainer") end,
  BANKFRAME_OPENED = function() remember("bank") end,
  AUCTION_HOUSE_SHOW = function() remember("auction") end,
  PET_STABLE_SHOW = function() remember("stable") end,
  CONFIRM_BINDER = function() remember("inn") end,
  MAIL_SHOW = function() remember("mailbox", "Mailbox") end,
  QUEST_DETAIL = function() remember("quests") end,
  QUEST_GREETING = function() remember("quests") end,
  QUEST_COMPLETE = function() remember("quests") end,
  GOSSIP_SHOW = function() remember("talk") end,
  -- Not about an NPC: the game changed something that a kind above shows, and Map.lua does not
  -- listen for it.
  DYNAMIC_GOSSIP_POI_UPDATED = function() ns.RefreshPins() end,
  SUPER_TRACKING_CHANGED = function() ns.RefreshPins() end,
}

local watcher = CreateFrame("Frame")
for event in pairs(npcEvents) do
  pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function(_, event)
  local ok, err = pcall(npcEvents[event])
  if not ok then
    geterrorhandler()(err)
  end
end)

-- The places that Forever Compass has learned, if that addon is there: vendors, repairers,
-- mailboxes, trainers, bankers and auctioneers. A place that this addon remembers too (the kind
-- above, when it is on) is left out here.
local LEARNED = { "vendor", "repair", "mailbox", "trainer", "bank", "auction" }

local function learnedPlaces(mapID, add)
  local db = _G["ForeverCompassDB"]
  local places = type(db) == "table" and db.places
  if type(places) ~= "table" then
    return
  end
  local own = ns.GetOption(ns.MapKindOption("npcs")) and npcList(mapID) or {}
  local function known(x, y)
    for _, entry in ipairs(own) do
      if type(entry) == "table" and ns.Usable(entry.x) and ns.Usable(entry.y) and math.abs(entry.x - x) < SAME_PLACE and math.abs(entry.y - y) < SAME_PLACE then
        return true
      end
    end
    return false
  end
  for _, kind in ipairs(LEARNED) do
    local role = ROLE[kind]
    for _, place in ipairs(type(places[kind]) == "table" and places[kind] or {}) do
      if type(place) == "table" and place.mapID == mapID and ns.Usable(place.x) and ns.Usable(place.y) and not known(place.x * 100, place.y * 100) then
        add(place.x * 100, place.y * 100, {
          look = roleLook(role),
          size = roleSize(role),
          tooltip = lines(text(place.name, role[2]), role[2], "Learned by Forever Compass"),
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
  { key = "npcs", name = "Vendors, trainers and other NPCs you have used", find = metNpcs },
  { key = "graveyards", name = "Graveyards", find = poiList(function() return C_DeathInfo and C_DeathInfo.GetGraveyardsForMap end, "Interface\\Minimap\\Tracking\\None", "Graveyard") },
  { key = "dungeons", name = "Dungeon entrances", find = poiList(function() return C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap end, "Interface\\Minimap\\Tracking\\None", "Dungeon entrance") },
  { key = "links", name = "Ways to other maps", find = poiList(function() return C_Map.GetMapLinksForMap end, "Interface\\Minimap\\Tracking\\None", "Way to another map") },
  { key = "flight", name = "Flight masters", find = flightMasters },
  { key = "bosses", name = "Dungeon bosses", find = bosses },
  { key = "events", name = "Events", find = events },
  { key = "otherPlaces", name = "Quest hubs, delves, races, pet tamers and dig sites", find = otherPlaces },
  { key = "guide", name = "Place a guard showed you", find = guardPlace },
  { key = "rares", name = "Rare enemies and treasures", find = rares },
  { key = "taskQuests", name = "World quests and bonus objectives", find = taskQuests },
  { key = "questWaypoint", name = "Way to the quest you follow", find = questWaypoint },
  { key = "questObjectives", name = "Quest objectives", find = logQuests(false) },
  { key = "questGivers", name = "Quest givers", find = questGivers },
  { key = "questTurnIns", name = "Quest turn-ins", find = logQuests(true) },
  { key = "group", name = "Group members", find = groupMembers },
  { key = "corpse", name = "Your corpse and the spirit healer", find = corpse },
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
ns.defaults.terrainDetail = true -- the terrain images of the minimap over the map, when zoomed in
