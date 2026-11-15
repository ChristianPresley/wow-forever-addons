local _, ns = ...

local function help()
  ns.Print("commands:")
  print("  /fatlas zone - show how much of the current zone you have visited")
  print("  /fatlas list - list the areas visited in the current zone")
  print("  /fatlas where - print your coordinates")
  print("  /fatlas coords - turn the world map coordinates on or off")
  print("  /fatlas announce - turn the first-visit chat message on or off")
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
  local options = ForeverAtlasDB.options
  options[option] = not options[option]
  ns.Print(label .. " " .. (options[option] and "on" or "off") .. ".")
end

SLASH_FOREVERATLAS1 = "/fatlas"
SLASH_FOREVERATLAS2 = "/foreveratlas"
SlashCmdList["FOREVERATLAS"] = function(input)
  local command = (input or ""):match("^(%S*)"):lower()
  if command == "zone" then
    zoneSummary()
  elseif command == "list" then
    list()
  elseif command == "where" then
    where()
  elseif command == "coords" then
    toggle("coords", "world map coordinates")
  elseif command == "announce" then
    toggle("announce", "first-visit messages")
  else
    help()
  end
end
