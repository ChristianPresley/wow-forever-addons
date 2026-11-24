local _, ns = ...

-- The outdoor zones of the two old continents, with the levels that a character of one class
-- can quest in with ease. These ranges are this addon's own judgement, written for it; they
-- are not taken from a guide or another addon. side: "A" Alliance towns, "H" Horde towns, "C" both.

ns.ZONES = {
  -- Eastern Kingdoms
  { name = "Elwynn Forest", min = 1, max = 10, side = "A" },
  { name = "Dun Morogh", min = 1, max = 10, side = "A" },
  { name = "Tirisfal Glades", min = 1, max = 10, side = "H" },
  { name = "Westfall", min = 9, max = 18, side = "A" },
  { name = "Loch Modan", min = 10, max = 18, side = "A" },
  { name = "Silverpine Forest", min = 10, max = 19, side = "H" },
  { name = "Redridge Mountains", min = 15, max = 25, side = "A" },
  { name = "Duskwood", min = 18, max = 29, side = "A" },
  { name = "Wetlands", min = 20, max = 29, side = "A" },
  { name = "Hillsbrad Foothills", min = 20, max = 30, side = "C" },
  { name = "Alterac Mountains", min = 29, max = 38, side = "C" },
  { name = "Arathi Highlands", min = 29, max = 39, side = "C" },
  { name = "Stranglethorn Vale", min = 30, max = 44, side = "C" },
  { name = "Badlands", min = 35, max = 44, side = "C" },
  { name = "Swamp of Sorrows", min = 35, max = 44, side = "C" },
  { name = "The Hinterlands", min = 40, max = 49, side = "C" },
  { name = "Searing Gorge", min = 43, max = 50, side = "C" },
  { name = "Blasted Lands", min = 45, max = 54, side = "C" },
  { name = "Burning Steppes", min = 50, max = 58, side = "C" },
  { name = "Western Plaguelands", min = 51, max = 59, side = "C" },
  { name = "Eastern Plaguelands", min = 53, max = 60, side = "C" },
  -- Kalimdor
  { name = "Teldrassil", min = 1, max = 10, side = "A" },
  { name = "Durotar", min = 1, max = 10, side = "H" },
  { name = "Mulgore", min = 1, max = 10, side = "H" },
  { name = "Darkshore", min = 10, max = 19, side = "A" },
  { name = "The Barrens", min = 10, max = 24, side = "H" },
  { name = "Stonetalon Mountains", min = 15, max = 26, side = "C" },
  { name = "Ashenvale", min = 19, max = 30, side = "C" },
  { name = "Thousand Needles", min = 24, max = 35, side = "C" },
  { name = "Desolace", min = 30, max = 39, side = "C" },
  { name = "Dustwallow Marsh", min = 35, max = 45, side = "C" },
  { name = "Feralas", min = 40, max = 49, side = "C" },
  { name = "Tanaris", min = 40, max = 50, side = "C" },
  { name = "Azshara", min = 45, max = 55, side = "C" },
  { name = "Felwood", min = 47, max = 55, side = "C" },
  { name = "Un'Goro Crater", min = 48, max = 55, side = "C" },
  { name = "Winterspring", min = 53, max = 60, side = "C" },
  { name = "Silithus", min = 54, max = 60, side = "C" },
}

-- The zones that suit a level, with a spread of levels on each side: the ones whose middle is
-- nearest to the level first. faction "Alliance" or "Horde" leaves out the towns of the other side.
function ns.ZonesFor(level, spread, faction)
  local result = {}
  if not ns.Usable(level) then
    return result
  end
  local other = faction == "Alliance" and "H" or faction == "Horde" and "A" or nil
  for _, zone in ipairs(ns.ZONES) do
    if zone.side ~= other and level >= zone.min - spread and level <= zone.max + spread then
      result[#result + 1] = zone
    end
  end
  table.sort(result, function(a, b)
    local da, db = math.abs((a.min + a.max) / 2 - level), math.abs((b.min + b.max) / 2 - level)
    if da ~= db then
      return da < db
    end
    return a.name < b.name
  end)
  return result
end

-- How a zone fits: "low" (below you), "high" (above you) or "even".
function ns.Fit(zone, level)
  if level > zone.max then
    return "low"
  elseif level < zone.min then
    return "high"
  end
  return "even"
end

---------------------------------------------------------------------------------------------------
-- The map of a zone, found by its name on the maps of the game: the mapIDs differ between clients.

local mapIDs

local function walk(mapID, depth)
  if depth > 3 then
    return
  end
  local ok, children = pcall(C_Map.GetMapChildrenInfo, mapID)
  if not ok or type(children) ~= "table" then
    return
  end
  for _, child in ipairs(children) do
    if child.mapType == Enum.UIMapType.Zone and type(child.name) == "string" then
      mapIDs[child.name] = mapIDs[child.name] or child.mapID
    elseif child.mapType == Enum.UIMapType.Continent or child.mapType == Enum.UIMapType.World then
      walk(child.mapID, depth + 1)
    end
  end
end

-- The top map above the player: the world.
local function topMap()
  local current = C_Map.GetBestMapForUnit("player")
  for _ = 1, 8 do
    local info = current and C_Map.GetMapInfo(current)
    if not info or not info.parentMapID or info.parentMapID == 0 then
      return current
    end
    current = info.parentMapID
  end
  return current
end

function ns.MapOfZone(name)
  -- An empty list is not kept: the game knows no map for the player while a screen loads.
  if not mapIDs or next(mapIDs) == nil then
    mapIDs = {}
    local top = topMap()
    if top then
      walk(top, 0)
      -- The zones at any depth under the top map, for a world with more levels than the walk knows.
      local ok, all = pcall(C_Map.GetMapChildrenInfo, top, Enum.UIMapType.Zone, true)
      if ok and type(all) == "table" then
        for _, child in ipairs(all) do
          if child.mapType == Enum.UIMapType.Zone and type(child.name) == "string" then
            mapIDs[child.name] = mapIDs[child.name] or child.mapID
          end
        end
      end
    end
  end
  return mapIDs[name]
end

-- Puts the map pin of the game in the middle of a zone, and asks Forever Compass to point a
-- tracker at the pin. Returns a line for the player.
function ns.PointAt(zone)
  local mapID = ns.MapOfZone(zone.name)
  if not mapID then
    return "the map of " .. zone.name .. " is not known: the game has no zone with this name."
  end
  if not C_Map.CanSetUserWaypointOnMap(mapID) then
    return "the game takes no map pin on " .. zone.name .. "."
  end
  local point = { uiMapID = mapID, position = CreateVector2D(0.5, 0.5) }
  if not C_Map.SetUserWaypoint(point) then
    return "the game refused a map pin on " .. zone.name .. "."
  end
  local compass = rawget(_G, "ForeverCompass")
  if type(compass) == "table" and type(compass.TrackMapPin) == "function" then
    local index, why = compass.TrackMapPin()
    if index then
      return string.format("tracker %d of the compass points to %s.", index, zone.name)
    end
    return "a map pin is on " .. zone.name .. ", but the compass said: " .. tostring(why)
  elseif type(compass) == "table" then
    return "a map pin is on " .. zone.name .. ". Point a tracker of the compass to \"Map pin\" (/fcompass 1 mappin)."
  end
  return "a map pin is on " .. zone.name .. ". Forever Compass can point to it."
end
