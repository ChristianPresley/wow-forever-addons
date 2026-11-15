local _, ns = ...

local function help()
  ns.Print("commands:")
  print("  /fatlas zone - show how much of the current zone you have visited")
  print("  /fatlas list - list the areas visited in the current zone")
  print("  /fatlas where - print your coordinates")
  print("  /fatlas way 45.2 61.8 - set a waypoint (also /way; /fatlas way for more)")
  print("  /fatlas note <text> - add a map note where you stand (Alt-click the world map to add one there)")
  print("  /fatlas hud - turn the on-screen coordinates on or off")
  print("  /fatlas lock - lock or unlock the on-screen coordinates and the waypoint arrow")
  print("  /fatlas arrow - turn the waypoint arrow on or off")
  print("  /fatlas arrive 10 - remove a waypoint when you are within 10 yards")
  print("  /fatlas reset - put the read-out and the arrow back where they were at first")
  print("  /fatlas pins - turn the visited-area pins on the world map on or off")
  print("  /fatlas notes - show or hide your map notes")
  print("  /fatlas coords - turn the world map coordinates on or off")
  print("  /fatlas announce - turn the first-visit chat message on or off")
  print("  /fatlas options - open the settings page")
end

local function zoneSummary()
  local zone = GetRealZoneText() or ""
  local line = string.format("%s: %d areas visited", zone, ns.CountAreas(zone))
  local explored = ns.CountExplored(C_Map.GetBestMapForUnit("player"))
  if explored then
    line = line .. string.format(", %d map sections uncovered", explored)
  end
  ns.Print(line .. ".")
end

local function list()
  local zone = GetRealZoneText() or ""
  local names = {}
  for area in pairs(ForeverAtlasCharDB.zones[zone] or {}) do
    names[#names + 1] = area
  end
  table.sort(names)
  ns.Print(zone .. ": " .. (#names > 0 and table.concat(names, ", ") or "nothing visited yet") .. ".")
end

local function where()
  local x, y = ns.PlayerPosition()
  if not x then
    ns.Print("the game does not give your position here.")
    return
  end
  ns.Print(string.format("%s %.1f, %.1f", GetSubZoneText() ~= "" and GetSubZoneText() or GetRealZoneText(), x, y))
end

local function toggle(option, label)
  ns.SetOption(option, not ns.GetOption(option))
  ns.Print(label .. " " .. (ns.GetOption(option) and "on" or "off") .. ".")
end

local TOGGLES = {
  coords = { "coords", "world map coordinates" },
  announce = { "announce", "first-visit messages" },
  hud = { "hud", "on-screen coordinates" },
  lock = { "hudLock", "frame lock" },
  pins = { "pins", "visited-area pins" },
  notes = { "notes", "map notes" },
  arrow = { "arrow", "waypoint arrow" },
}

-- /fatlas arrive 10
local function arrive(rest)
  local yards = tonumber(rest)
  if yards then
    ns.SetOption("arrivalYards", yards)
  end
  ns.Print("a waypoint is removed when you are within " .. ns.GetOption("arrivalYards") .. " yards. Change it with /fatlas arrive 10.")
end

SLASH_FOREVERATLAS1 = "/fatlas"
SLASH_FOREVERATLAS2 = "/foreveratlas"
SlashCmdList["FOREVERATLAS"] = function(input)
  local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = command:lower()
  if command == "zone" then
    zoneSummary()
  elseif command == "list" then
    list()
  elseif command == "where" then
    where()
  elseif command == "way" then
    ns.WaypointCommand(rest)
  elseif command == "note" then
    ns.NoteCommand(rest)
  elseif command == "arrive" then
    arrive(rest)
  elseif command == "reset" then
    ns.ResetFrames()
    ns.Print("the read-out and the arrow are back where they were at first.")
  elseif command == "options" or command == "config" then
    ns.OpenSettings()
  elseif TOGGLES[command] then
    toggle(TOGGLES[command][1], TOGGLES[command][2])
  else
    help()
  end
end
