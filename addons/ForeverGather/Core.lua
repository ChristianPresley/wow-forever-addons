local _, ns = ...

-- Saved data, in ForeverGatherDB (for all characters):
--   version = 2   (1 had quest objects as treasure: its treasure nodes are dropped)
--   options = { herb, ore, fish, treasure, quest, worldMap, minimap, hideTrivial, minSkill, size,
--               alert, alertSound, alertYards, dimMinutes, skillColours, route }
--   nodes   = { [mapID] = { { kind = s, name = s, x = n, y = n, count = n, first = n, last = n,
--               loot = { [item] = n }, looted = n, imported = true, seen = true }, ... } }
--             x, y from 0 to 1. first, last: time() of the first and the last gather (nil for a
--             node of a version before 0.3.0). loot: what the node gave, summed over looted loot
--             windows. imported with count 0: a node from an import that was not gathered yet.
--             seen with count 0: a node that the player could not gather (the skill is too low).
--   names   = { [name] = { kind = s, skill = n, needs = n } }
--             skill: the lowest skill rank seen at a gather. needs: the skill that the game
--             asked for when the player could not gather it.
--   history = { { spell = n, spellName = s, target = s, kind = s, result = s, at = n }, ... }
--             the last gathering casts and what came of each, the newest last, for
--             /fgather status and /fgather history. at is time().
--   last    = { other = { spell = n, spellName = s, target = s, at = n },
--               error = { message = s, name = s, lines = { s, ... }, at = n } }
--             other: the last other cast at a target, the spell to report when a gather is not
--             known. error: the last red message of the game with a thing under the pointer,
--             to report when a node that needs more skill is not stored as seen.

local DATA_VERSION = 2

function ns.Print(msg)
  print("|cff6fc96fForever Gather|r: " .. tostring(msg))
end

-- True for a number that the addon can calculate with.
function ns.Usable(value)
  return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

-- True for a string that the addon can compare and keep.
function ns.PlainString(value)
  return type(value) == "string" and not (issecretvalue and issecretvalue(value)) and value ~= ""
end

-- The kinds of nodes: key, name, the skill line, the icon.
ns.KINDS = {
  { key = "herb", name = "Herbs", skill = "Herbalism", icon = "Interface\\Icons\\INV_Misc_Herb_07" },
  { key = "ore", name = "Ore", skill = "Mining", icon = "Interface\\Icons\\INV_Ore_Copper_01" },
  { key = "fish", name = "Fish", skill = "Fishing", icon = "Interface\\Icons\\INV_Misc_Fish_02" },
  { key = "treasure", name = "Treasure", icon = "Interface\\Icons\\INV_Box_01" },
  { key = "quest", name = "Quest objects", icon = "Interface\\GossipFrame\\AvailableQuestIcon" },
}
-- "herb, ore, fish, treasure, quest", for the texts of the commands.
local keys = {}
for _, kind in ipairs(ns.KINDS) do
  keys[#keys + 1] = kind.key
end
ns.KIND_KEYS = table.concat(keys, ", ")
ns.KIND = {}
for _, kind in ipairs(ns.KINDS) do
  ns.KIND[kind.key] = kind
end

ns.OPTION_DEFAULTS = {
  herb = true,
  ore = true,
  fish = true,
  treasure = true,
  quest = true,
  worldMap = true,
  minimap = true,
  hideTrivial = false, -- hide nodes that the skill has outgrown (no more skill ups)
  minSkill = 0, -- hide nodes learned at a skill below this
  size = 14, -- pixels, of a pin on the minimap; world map pins are a little larger
  alert = true, -- say when a learned node comes near
  alertSound = true, -- with a sound
  alertYards = 60, -- near is within this many yards
  dimMinutes = 5, -- a pin is dim for this long after its gather; 0: never
  skillColours = true, -- a dot on the pin in the colour of the difficulty for your skill
  route = false, -- a line through the nodes of the zone on the world map
}
ns.OPTION_LIMITS = {
  minSkill = { 0, 300 },
  size = { 8, 32 },
  alertYards = { 20, 200 },
  dimMinutes = { 0, 30 },
}

local listeners = {}
function ns.OnChange(fn)
  listeners[#listeners + 1] = fn
end
function ns.Changed()
  for _, fn in ipairs(listeners) do
    local ok, err = pcall(fn)
    if not ok then
      geterrorhandler()(err)
    end
  end
end

function ns.GetOption(key)
  local value = ForeverGatherDB and ForeverGatherDB.options[key]
  if value == nil then
    return ns.OPTION_DEFAULTS[key]
  end
  return value
end

-- Returns true when the key exists and the value was set.
function ns.SetOption(key, value)
  local default = ns.OPTION_DEFAULTS[key]
  if default == nil or not ForeverGatherDB then
    return false
  end
  if type(default) == "number" then
    local limit = ns.OPTION_LIMITS[key]
    value = math.floor((tonumber(value) or default) + 0.5)
    value = math.max(limit[1], math.min(limit[2], value))
  else
    value = value and true or false
  end
  ForeverGatherDB.options[key] = value
  ns.Changed()
  return true
end

-- True for a map that is a continent or larger. A place on such a map is not the place of a
-- node: the game gives the continent where a zone has no map of its own, as inside a dungeon.
function ns.MapTooLarge(mapID)
  local info = C_Map.GetMapInfo(mapID)
  local mapType = info and info.mapType
  return ns.Usable(mapType) and mapType <= Enum.UIMapType.Continent
end

-- Drops the stored nodes of maps that are a continent or larger. Returns how many.
function ns.DropMisplaced()
  local dropped = 0
  for mapID, list in pairs(ForeverGatherDB.nodes) do
    if type(list) ~= "table" then
      ForeverGatherDB.nodes[mapID] = nil
    elseif ns.MapTooLarge(mapID) then
      dropped = dropped + #list
      ForeverGatherDB.nodes[mapID] = nil
    end
  end
  return dropped
end

-- Version 1 could not tell a chest from a quest object: every treasure of it goes.
-- Returns how many nodes went.
local function dropOldTreasure(db)
  local dropped = 0
  if type(db.nodes) == "table" then
    for _, list in pairs(db.nodes) do
      if type(list) == "table" then
        for index = #list, 1, -1 do
          if type(list[index]) ~= "table" or list[index].kind == "treasure" then
            table.remove(list, index)
            dropped = dropped + 1
          end
        end
      end
    end
  end
  if type(db.names) == "table" then
    for name, entry in pairs(db.names) do
      if type(entry) ~= "table" or entry.kind == "treasure" then
        db.names[name] = nil
      end
    end
  end
  return dropped
end
ns.DropOldTreasure = dropOldTreasure

-- What validate dropped or moved, for one line each at login.
local dropped = { treasure = 0, misplaced = 0, moved = 0 }

local function validate()
  local db = ForeverGatherDB
  if type(db) == "table" and db.version == 1 then
    dropped.treasure = dropOldTreasure(db)
    db.version = DATA_VERSION
  end
  if type(db) ~= "table" or db.version ~= DATA_VERSION then
    db = { version = DATA_VERSION }
  end
  if type(db.options) ~= "table" then
    db.options = {}
  end
  for key, default in pairs(ns.OPTION_DEFAULTS) do
    if type(db.options[key]) ~= type(default) then
      db.options[key] = default
    end
  end
  if type(db.nodes) ~= "table" then
    db.nodes = {}
  end
  if type(db.names) ~= "table" then
    db.names = {}
  end
  if type(db.last) ~= "table" then
    db.last = {}
  end
  db.last.gather = nil -- of 0.2.0: the history has it now
  if type(db.history) ~= "table" then
    db.history = {}
  end
  ForeverGatherDB = db
  dropped.misplaced = ns.DropMisplaced()
  if db.caves ~= 2 then
    dropped.moved = ns.MoveCaveNodes()
    db.caves = 2
  end
  ns.DropEmptyMaps()
end

-- The last map of a zone that the player stood on. A cave without a map of its own lies under
-- the zone that the player walked in from, also where the maps of two zones overlap.
local lastZone
function ns.LastZone()
  return lastZone
end

-- The player's map and position on it. Without a place for a node: nil and the reason, for
-- /fgather status.
function ns.PlayerPosition()
  if IsInInstance() then
    return nil, "you were inside an instance"
  end
  local mapID = C_Map.GetBestMapForUnit("player")
  if not ns.Usable(mapID) then
    return nil, "the game gave no map"
  end
  local position = C_Map.GetPlayerMapPosition(mapID, "player")
  if not position then
    return nil, string.format("the game gave no position on map %d", mapID)
  end
  local x, y = position.x, position.y
  if not ns.Usable(x) or not ns.Usable(y) or (x == 0 and y == 0) then
    return nil, string.format("the game gave no position on map %d", mapID)
  end
  if ns.MapTooLarge(mapID) then
    -- Outside an instance the game gives the continent where a place has no map of its own
    -- (a cave). The zone under that point of the continent is the map of the node.
    local zone, zx, zy = ns.ZoneAt(mapID, x, y, lastZone)
    if not zone then
      return nil, string.format("the game gave only the map of a continent (map %d), with no zone at your place", mapID)
    end
    return zone, zx, zy
  end
  lastZone = mapID
  return mapID, x, y
end

-- The point of a larger map on the map of a zone: the zone and the point, or nil when the
-- point is not on that map.
local function onZone(zone, mapID, x, y)
  if not ns.Usable(zone) or zone == mapID or ns.MapTooLarge(zone) then
    return nil
  end
  local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(zone, mapID)
  if not (ns.Usable(minX) and ns.Usable(maxX) and ns.Usable(minY) and ns.Usable(maxY)) or maxX <= minX or maxY <= minY then
    return nil
  end
  local zx, zy = (x - minX) / (maxX - minX), (y - minY) / (maxY - minY)
  if zx < 0 or zx > 1 or zy < 0 or zy > 1 then
    return nil
  end
  return zone, zx, zy
end

-- The zone under a point of a larger map, and the point on the map of that zone, or nil.
-- The maps of two zones can overlap: the preferred zone wins when the point is on its map.
function ns.ZoneAt(mapID, x, y, preferred)
  if preferred then
    local zone, zx, zy = onZone(preferred, mapID, x, y)
    if zone then
      return zone, zx, zy
    end
  end
  local info = C_Map.GetMapInfoAtPosition(mapID, x, y)
  return onZone(info and info.mapID, mapID, x, y)
end

-- True for a number that the game gave as a position: it has the 24 bits of a single float.
-- A place that was worked out from a point of a continent has more.
local function single(value)
  if value <= 0 or value >= 1 then
    return true
  end
  while value < 8388608 do
    value = value * 2
  end
  return value == math.floor(value)
end

-- Once, for the nodes of a cave where the maps of two zones overlap. 0.5.0 stored them on the
-- zone that the game names at that point of the continent, and the first move of 0.5.1 guessed
-- the zone from the place alone; both can be the wrong zone. The proof of the right zone is a
-- newer node of the same thing in the same cave, stored on the zone that the player came from.
-- So a node that was worked out from the continent moves to the map of a newer node with its
-- kind and name, when its place on that map is within a tenth of the map of that node.
-- Returns how many moved.
local NEAR = 0.1
function ns.MoveCaveNodes()
  local nodes = ForeverGatherDB.nodes
  local moves = {}
  for mapID, list in pairs(nodes) do
    local info = type(list) == "table" and C_Map.GetMapInfo(mapID)
    local parent = info and info.parentMapID
    local minX, maxX, minY, maxY
    if ns.Usable(parent) and parent ~= 0 then
      minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(mapID, parent)
    end
    if ns.Usable(minX) and ns.Usable(maxX) and ns.Usable(minY) and ns.Usable(maxY) and maxX > minX and maxY > minY then
      for index = #list, 1, -1 do
        local node = list[index]
        local x, y = type(node) == "table" and node.x, type(node) == "table" and node.y
        if type(x) == "number" and type(y) == "number" and not (single(x) and single(y)) then
          local px, py = minX + x * (maxX - minX), minY + y * (maxY - minY)
          local best, bestX, bestY, bestFirst
          for otherMap, others in pairs(nodes) do
            local otherInfo = otherMap ~= mapID and type(others) == "table" and C_Map.GetMapInfo(otherMap)
            if otherInfo and otherInfo.parentMapID == parent then
              local zone, zx, zy = onZone(otherMap, parent, px, py)
              for _, other in ipairs(zone and others or {}) do
                local newer = type(other) == "table" and other.kind == node.kind and other.name == node.name and (other.first or 0) > (node.first or 0)
                if newer and type(other.x) == "number" and type(other.y) == "number" and math.abs(other.x - zx) < NEAR and math.abs(other.y - zy) < NEAR then
                  if not best or other.first > bestFirst then
                    best, bestX, bestY, bestFirst = zone, zx, zy, other.first
                  end
                end
              end
            end
          end
          if best then
            moves[#moves + 1] = { from = list, map = best, node = node, x = bestX, y = bestY }
          end
        end
      end
    end
  end
  -- The nodes move after the search, so that each is judged by the data as it was.
  for _, move in ipairs(moves) do
    for index, node in ipairs(move.from) do
      if node == move.node then
        table.remove(move.from, index)
        break
      end
    end
    move.node.x, move.node.y = move.x, move.y
    table.insert(nodes[move.map], move.node)
  end
  return #moves
end

-- Drops the maps that have no node left.
function ns.DropEmptyMaps()
  for mapID, list in pairs(ForeverGatherDB.nodes) do
    if type(list) ~= "table" or next(list) == nil then
      ForeverGatherDB.nodes[mapID] = nil
    end
  end
end

-- The player's rank in a skill line by its name, or nil.
function ns.SkillRank(skillName)
  if not skillName or not C_SkillInfo or not C_SkillInfo.GetNumSkillLines then
    return nil
  end
  local count = C_SkillInfo.GetNumSkillLines()
  if not ns.Usable(count) then
    return nil
  end
  for index = 1, count do
    local info = C_SkillInfo.GetSkillLineInfo(index)
    if info and info.name == skillName and ns.Usable(info.rank) then
      return info.rank
    end
  end
  return nil
end

-- The zone is kept as the player moves, so that it is known inside a cave.
local zoneFrame = CreateFrame("Frame")
zoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
zoneFrame:RegisterEvent("ZONE_CHANGED")
zoneFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneFrame:SetScript("OnEvent", function()
  local mapID = C_Map.GetBestMapForUnit("player")
  if ns.Usable(mapID) and not IsInInstance() and not ns.MapTooLarge(mapID) then
    lastZone = mapID
  end
end)

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" and name == "ForeverGather" then
    validate()
    self:UnregisterEvent("ADDON_LOADED")
    ns.Changed()
  elseif event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    if dropped.treasure > 0 then
      ns.Print(string.format("dropped %d treasure nodes of the earlier version: it stored quest objects as treasure. Chests are learned again as you open them.", dropped.treasure))
    end
    if dropped.moved > 0 then
      ns.Print(string.format("moved %d |4node:nodes; of a cave to the map of the zone that the cave is in.", dropped.moved))
    end
    if dropped.misplaced > 0 then
      ns.Print(string.format("dropped %d nodes that were stored on the map of a continent, at a wrong place.", dropped.misplaced))
    end
  end
end)
