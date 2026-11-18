local _, ns = ...

-- The compass is one bar at the top of the screen that shows the heading. Up to four trackers put
-- a marker on the bar, each at the bearing of the nearest thing of its kind.
--
-- Saved data, in ForeverCompassDB (for all characters):
--   version   = 2
--   options   = { show, lock, hideInCombat, showDegrees, barAlpha, barWidth, fov }
--   compasses = { [1..4] = { enabled, kind, color, size, alpha, showName, showDistance, icon, maxYards } }
--               (the four trackers; the key has its name from version 1, which had four dials)
--   frames    = { bar = { point, relativePoint, x, y } }
--   places    = { [kind] = { { mapID = n, x = n, y = n, name = s }, ... } }   -- see Places.lua

local DATA_VERSION = 2

ns.COUNT = 4

function ns.Print(msg)
  print("|cffc9a227Forever Compass|r: " .. tostring(msg))
end

-- True for a number that the addon can calculate with (see docs/addon-development.md).
function ns.Usable(value)
  return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

-- The colours a compass can have: key, name, red, green, blue.
ns.COLORS = {
  { "gold", "Gold", 1.00, 0.82, 0.00 },
  { "green", "Green", 0.25, 0.85, 0.35 },
  { "blue", "Blue", 0.30, 0.65, 1.00 },
  { "red", "Red", 0.95, 0.30, 0.25 },
  { "purple", "Purple", 0.70, 0.45, 0.95 },
  { "white", "White", 0.95, 0.95, 0.95 },
}

-- Settings of the bar. The type of the default is the type of the setting.
ns.OPTION_DEFAULTS = {
  show = true, -- the bar
  lock = false, -- a locked bar does not move and lets clicks through
  hideInCombat = false,
  showDegrees = true, -- the heading in degrees, above the bar
  barAlpha = 75, -- percent
  barWidth = 67, -- percent of the width of the screen
  fov = 180, -- degrees of the circle that the bar shows at one time
}

ns.OPTION_LIMITS = {
  barAlpha = { 20, 100 },
  barWidth = { 30, 100 },
  fov = { 90, 360 },
}

-- Settings of a tracker. The type of the default is the type of the setting.
ns.COMPASS_DEFAULTS = {
  enabled = false,
  kind = "questObjectives", -- what it points to: a key of ns.KINDS (Trackers.lua)
  color = "gold",
  size = 20, -- pixels, of the marker
  alpha = 75, -- percent, of the marker
  showName = true, -- the name of the target under the marker
  showDistance = true,
  icon = true, -- the marker is the icon of what the tracker points to; off: a round marker in the colour
  maxYards = 0, -- ignore targets farther than this; 0 is no limit
  questID = 0, -- for the kind "quest": the quest it points to; 0 is none
}

ns.COMPASS_LIMITS = {
  size = { 12, 40 },
  alpha = { 20, 100 },
  maxYards = { 0, 2000 },
  questID = { 0, 2147483647 },
}

-- What the four compasses are at first. The first two are on.
local FIRST = {
  { enabled = true, kind = "questObjectives", color = "gold" },
  { enabled = true, kind = "questTurnIns", color = "green" },
  { kind = "questGivers", color = "blue" },
  { kind = "rares", color = "red" },
}

local listeners = {}

-- fn runs after each change of an option or of a compass setting.
function ns.OnChange(fn)
  listeners[#listeners + 1] = fn
end

local function changed()
  for _, fn in ipairs(listeners) do
    local ok, err = pcall(fn)
    if not ok then
      geterrorhandler()(err)
    end
  end
end

function ns.GetOption(key)
  return ForeverCompassDB and ForeverCompassDB.options[key] or false
end

function ns.SetOption(key, value)
  local default = ns.OPTION_DEFAULTS[key]
  if default == nil then
    return
  end
  if type(default) == "number" then
    local limit = ns.OPTION_LIMITS[key]
    value = math.floor((tonumber(value) or default) + 0.5)
    value = math.max(limit[1], math.min(limit[2], value))
  else
    value = value and true or false
  end
  ForeverCompassDB.options[key] = value
  changed()
end

function ns.GetCompass(index, key)
  local compass = ForeverCompassDB and ForeverCompassDB.compasses[index]
  return compass and compass[key]
end

local function colorExists(key)
  for _, color in ipairs(ns.COLORS) do
    if color[1] == key then
      return true
    end
  end
  return false
end

-- Returns false for a value that the setting cannot have.
function ns.SetCompass(index, key, value)
  local compass = ForeverCompassDB and ForeverCompassDB.compasses[index]
  local default = ns.COMPASS_DEFAULTS[key]
  if not compass or default == nil then
    return false
  end
  if type(default) == "number" then
    local limit = ns.COMPASS_LIMITS[key]
    value = math.floor((tonumber(value) or default) + 0.5)
    value = math.max(limit[1], math.min(limit[2], value))
  elseif type(default) == "boolean" then
    value = value and true or false
  elseif key == "kind" then
    if not ns.KindByKey[value] then
      return false
    end
  elseif key == "color" then
    if not colorExists(value) then
      return false
    end
  end
  compass[key] = value
  changed()
  return true
end

---------------------------------------------------------------------------------------------------
-- For other addons: ForeverCompass.TrackQuest(questID) and its two companions. Forever Quests
-- calls them from the compass button of a quest in the quest log.

-- The tracker that points to this quest now, or nil.
local function trackerOfQuest(questID)
  for index = 1, ns.COUNT do
    if ns.GetCompass(index, "enabled") and ns.GetCompass(index, "kind") == "quest" and ns.GetCompass(index, "questID") == questID then
      return index
    end
  end
  return nil
end

ForeverCompass = ForeverCompass or {}

-- The number of the tracker that points to the quest, or nil.
function ForeverCompass.QuestTracker(questID)
  if type(questID) ~= "number" or not ForeverCompassDB then
    return nil
  end
  return trackerOfQuest(questID)
end

-- Makes a tracker point to one quest: the tracker that has it already, else the first tracker
-- that is off. Returns the number of the tracker, or nil and why not.
function ForeverCompass.TrackQuest(questID)
  if type(questID) ~= "number" or questID <= 0 or not ForeverCompassDB then
    return nil, "not a quest"
  end
  local index = trackerOfQuest(questID)
  if index then
    return index
  end
  for free = 1, ns.COUNT do
    if not ns.GetCompass(free, "enabled") then
      ns.SetCompass(free, "kind", "quest")
      ns.SetCompass(free, "questID", questID)
      ns.SetCompass(free, "enabled", true)
      return free
    end
  end
  return nil, "all " .. ns.COUNT .. " trackers of the compass are in use"
end

-- Turns off the tracker that points to the quest. Returns true if there was one.
function ForeverCompass.UntrackQuest(questID)
  local index = ForeverCompass.QuestTracker(questID)
  if not index then
    return false
  end
  ns.SetCompass(index, "enabled", false)
  ns.SetCompass(index, "questID", 0)
  return true
end

-- Makes a tracker point to the map pin (the caller sets the pin, with C_Map.SetUserWaypoint): the
-- tracker that points to it already, else the first tracker that is off. Returns the number of the
-- tracker, or nil and why not.
function ForeverCompass.TrackMapPin()
  if not ForeverCompassDB then
    return nil, "the compass is not loaded yet"
  end
  for index = 1, ns.COUNT do
    if ns.GetCompass(index, "enabled") and ns.GetCompass(index, "kind") == "mapPin" then
      return index
    end
  end
  for free = 1, ns.COUNT do
    if not ns.GetCompass(free, "enabled") then
      ns.SetCompass(free, "kind", "mapPin")
      ns.SetCompass(free, "enabled", true)
      return free
    end
  end
  return nil, "all " .. ns.COUNT .. " trackers of the compass are in use"
end

-- A quest that left the log (turned in or abandoned) gives its tracker back: else the tracker
-- would point to nothing and stay in use.
local questWatcher = CreateFrame("Frame")
questWatcher:RegisterEvent("QUEST_REMOVED")
questWatcher:SetScript("OnEvent", function(_, _, questID)
  if ns.Usable(questID) and ForeverCompass.UntrackQuest(questID) then
    ns.Print("the quest left your log: its tracker on the compass is free again.")
  end
end)

function ns.ColorOf(index)
  local key = ns.GetCompass(index, "color")
  for _, color in ipairs(ns.COLORS) do
    if color[1] == key then
      return color[3], color[4], color[5]
    end
  end
  return 1, 0.82, 0
end

---------------------------------------------------------------------------------------------------
-- Positions

function ns.PlayerMap()
  return C_Map.GetBestMapForUnit("player")
end

-- Position of the player on a map, two numbers from 0 to 1, or nil where the game hides it.
function ns.PlayerMapPosition(mapID)
  if not mapID then
    return nil
  end
  local ok, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
  if not ok or not position then
    return nil
  end
  local x, y = position:GetXY()
  if not ns.Usable(x) or not ns.Usable(y) then
    return nil
  end
  return x, y
end

-- World position of a unit: continent, north, west, in yards. Nil where the game hides it (instances).
function ns.UnitWorld(unit)
  local ok, north, west, _, continent = pcall(UnitPosition, unit)
  if not ok or not ns.Usable(north) or not ns.Usable(west) then
    return nil
  end
  return continent, north, west
end

-- World position of a point of a map (x and y from 0 to 1): continent, north, west. Nil if not known.
function ns.WorldPosition(mapID, x, y)
  if not (mapID and ns.Usable(x) and ns.Usable(y) and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
    return nil
  end
  local ok, continent, position = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
  if not ok or not ns.Usable(continent) or not position then
    return nil
  end
  local north, west = position:GetXY()
  if not ns.Usable(north) or not ns.Usable(west) then
    return nil
  end
  return continent, north, west
end

---------------------------------------------------------------------------------------------------
-- Start

local logins = {}

-- fn runs at PLAYER_LOGIN, when the saved data is ready. An error stops that part only.
function ns.OnLogin(fn)
  logins[#logins + 1] = fn
end

local function tableAt(parent, key)
  if type(parent[key]) ~= "table" then
    parent[key] = {}
  end
  return parent[key]
end

local function fill(target, defaults, first)
  for key, default in pairs(defaults) do
    if type(target[key]) ~= type(default) then
      local value = first and first[key]
      target[key] = value == nil and default or value
    end
  end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
  if event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    for key, limit in pairs(ns.OPTION_LIMITS) do
      local options = ForeverCompassDB.options
      options[key] = math.max(limit[1], math.min(limit[2], math.floor(options[key] + 0.5)))
    end
    -- A kind or a colour that no longer exists goes back to the default.
    for index = 1, ns.COUNT do
      local compass = ForeverCompassDB.compasses[index]
      if not ns.KindByKey[compass.kind] then
        compass.kind = ns.COMPASS_DEFAULTS.kind
      end
      if not colorExists(compass.color) then
        compass.color = ns.COMPASS_DEFAULTS.color
      end
      for key, limit in pairs(ns.COMPASS_LIMITS) do
        compass[key] = math.max(limit[1], math.min(limit[2], math.floor(compass[key] + 0.5)))
      end
    end
    for _, fn in ipairs(logins) do
      local ok, err = pcall(fn)
      if not ok then
        geterrorhandler()(err)
      end
    end
    return
  end
  if name ~= "ForeverCompass" then
    return
  end
  self:UnregisterEvent("ADDON_LOADED")
  if type(ForeverCompassDB) ~= "table" then
    ForeverCompassDB = {}
  end
  local db = ForeverCompassDB
  if type(db.version) ~= "number" or db.version < DATA_VERSION then
    -- Version 1 had four dials. Their sizes and places do not fit the bar, and their opacity
    -- of 100 percent was the default of then: these go to the defaults of now.
    if type(db.compasses) == "table" then
      for _, tracker in pairs(db.compasses) do
        if type(tracker) == "table" then
          tracker.size = nil
          tracker.hideEmpty = nil
          if tracker.alpha == 100 then
            tracker.alpha = nil
          end
        end
      end
    end
    db.frames = nil
    db.version = DATA_VERSION
  end
  fill(tableAt(ForeverCompassDB, "options"), ns.OPTION_DEFAULTS)
  local compasses = tableAt(ForeverCompassDB, "compasses")
  for index = 1, ns.COUNT do
    fill(tableAt(compasses, index), ns.COMPASS_DEFAULTS, FIRST[index])
  end
  tableAt(ForeverCompassDB, "frames")
  tableAt(ForeverCompassDB, "places")
end)
