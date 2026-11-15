local _, ns = ...

-- Records each named area the character enters:
-- ForeverAtlasCharDB.zones[zone][area] = { t = time(), mapID = n, x = n, y = n }

local function record()
  if not ForeverAtlasCharDB then
    return
  end
  local zone = GetRealZoneText()
  if not zone or zone == "" then
    return
  end
  local area = GetSubZoneText()
  if not area or area == "" then
    area = zone
  end
  local zones = ForeverAtlasCharDB.zones
  zones[zone] = zones[zone] or {}
  if zones[zone][area] then
    return
  end
  local mapID = C_Map.GetBestMapForUnit("player")
  local x, y = ns.PlayerPosition(mapID)
  zones[zone][area] = { t = time(), mapID = mapID, x = x, y = y }
  if ForeverAtlasDB.options.announce then
    ns.Print("first visit to " .. area .. " (" .. zone .. ").")
  end
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
