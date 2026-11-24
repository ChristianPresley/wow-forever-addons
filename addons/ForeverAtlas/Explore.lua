local _, ns = ...

-- Records each named area the character enters:
-- ForeverAtlasCharDB.zones[zone][area] = { t = time(), mapID = n, x = n, y = n }

-- An area is recorded once the character has stayed in it this long: at a border the game
-- changes the zone and the map for a moment, several times a second in some places.
local SETTLE_SECONDS = 1.5
local waiting = 0

local function here()
  local zone = GetRealZoneText()
  if not zone or zone == "" then
    return nil
  end
  local area = GetSubZoneText()
  if not area or area == "" then
    area = zone
  end
  return zone, area
end

-- Whether the map is a zone or a dungeon, not a continent or the world. Where the game cannot
-- tell the kind of the map, it is taken.
local function isZoneMap(mapID)
  if not (mapID and C_Map.GetMapInfo and Enum and Enum.UIMapType) then
    return mapID ~= nil
  end
  local ok, info = pcall(C_Map.GetMapInfo, mapID)
  if not (ok and type(info) == "table" and info.mapType) then
    return true
  end
  return info.mapType == Enum.UIMapType.Zone or info.mapType == Enum.UIMapType.Dungeon
end

local function store(zone, area)
  local zones = ForeverAtlasCharDB.zones
  zones[zone] = zones[zone] or {}
  if zones[zone][area] then
    return
  end
  local mapID = C_Map.GetBestMapForUnit("player")
  -- Not for a continent that the game names for a moment at a border: the next reading does it.
  if not isZoneMap(mapID) then
    return
  end
  local x, y = ns.PlayerPosition(mapID)
  zones[zone][area] = { t = time(), mapID = mapID, x = x, y = y }
  ns.RefreshPins()
  if ForeverAtlasDB.options.announce then
    ns.Print("first visit to " .. area .. " (" .. zone .. ").")
  end
end

local function record()
  if not ForeverAtlasCharDB then
    return
  end
  local zone, area = here()
  if not zone then
    return
  end
  local zones = ForeverAtlasCharDB.zones
  if zones[zone] and zones[zone][area] then
    return
  end
  waiting = waiting + 1
  local token = waiting
  C_Timer.After(SETTLE_SECONDS, function()
    -- A later event has started its own wait, or the character has left the area.
    if token ~= waiting or not ForeverAtlasCharDB then
      return
    end
    local nowZone, nowArea = here()
    if nowZone == zone and nowArea == area then
      store(zone, area)
    end
  end)
end

-- Number of areas visited in a zone.
function ns.CountAreas(zone)
  local count = 0
  for _ in pairs(ForeverAtlasCharDB.zones[zone] or {}) do
    count = count + 1
  end
  return count
end

-- Number of map sections the game has uncovered on a map, or nil if the client cannot tell.
function ns.CountExplored(mapID)
  if not mapID or not C_MapExplorationInfo or not C_MapExplorationInfo.GetExploredMapTextures then
    return nil
  end
  local ok, textures = pcall(C_MapExplorationInfo.GetExploredMapTextures, mapID)
  if not ok or type(textures) ~= "table" then
    return nil
  end
  return #textures
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:SetScript("OnEvent", record)
