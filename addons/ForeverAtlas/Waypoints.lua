local _, ns = ...

-- Waypoints: ForeverAtlasCharDB.waypoints = { { mapID = n, x = n, y = n, label = s }, ... } with x, y from 0 to 100.
-- The arrow follows the newest one. Direction and distance come from world positions,
-- so they are known only where the game gives the player's position.

local INTERVAL = 0.05
local ARRIVAL_YARDS = 5
local WORLD_MAP = 947
local PIN_LOOK = { atlas = "Waypoint-MapPin-Tracked", texture = "Interface\\Minimap\\Ping\\ping5" }

local arrow, driver
local world = setmetatable({}, { __mode = "k" })

local function waypoints()
  return ForeverAtlasCharDB.waypoints
end

-- World position of a waypoint: { continent, north, west } in yards, or false.
local function worldPosition(waypoint)
  local known = world[waypoint]
  if known ~= nil then
    return known
  end
  local result = false
  if C_Map.GetWorldPosFromMapPos and CreateVector2D then
    local ok, continent, position = pcall(C_Map.GetWorldPosFromMapPos, waypoint.mapID, CreateVector2D(waypoint.x / 100, waypoint.y / 100))
    if ok and ns.Usable(continent) and position then
      local north, west = position:GetXY()
      if ns.Usable(north) and ns.Usable(west) then
        result = { continent, north, west }
      end
    end
  end
  world[waypoint] = result
  return result
end

local function describe(waypoint)
  return string.format("%s (%s %.1f, %.1f)", waypoint.label, ns.MapName(waypoint.mapID), waypoint.x, waypoint.y)
end

local function changed()
  ns.RefreshPins()
  if driver then
    driver:SetShown(#waypoints() > 0)
    if #waypoints() == 0 then
      arrow:Hide()
    end
  end
end

function ns.AddWaypoint(mapID, x, y, label)
  if not label or label == "" then
    label = ns.MapName(mapID)
  end
  local waypoint = { mapID = mapID, x = x, y = y, label = label }
  table.insert(waypoints(), waypoint)
  changed()
  return waypoint
end

function ns.RemoveWaypoint(waypoint)
  local list = waypoints()
  for i = #list, 1, -1 do
    if list[i] == waypoint then
      table.remove(list, i)
    end
  end
  changed()
end

function ns.ClearWaypoints()
  local list = waypoints()
  for i = #list, 1, -1 do
    list[i] = nil
  end
  changed()
end

local function update()
  local list = waypoints()
  local waypoint = list[#list]
  if not waypoint then
    arrow:Hide()
    return
  end
  local target = worldPosition(waypoint)
  local ok, north, west, _, continent = pcall(UnitPosition, "player")
  if not target or not ok or not ns.Usable(north) or not ns.Usable(west) then
    arrow:Hide()
    return
  end
  arrow.label:SetText(waypoint.label)
  if ns.Usable(continent) and continent ~= target[1] then
    arrow.texture:Hide()
    arrow.distance:SetText("on another continent")
    arrow:Show()
    return
  end
  local dNorth, dWest = target[2] - north, target[3] - west
  local yards = math.sqrt(dNorth * dNorth + dWest * dWest)
  if yards <= ARRIVAL_YARDS then
    ns.Print("arrived at " .. describe(waypoint) .. ".")
    ns.RemoveWaypoint(waypoint)
    return
  end
  arrow.distance:SetText(string.format("%d yd", yards))
  local facing = GetPlayerFacing and GetPlayerFacing()
  if ns.Usable(facing) then
    -- Facing and bearing both turn counterclockwise from north.
    arrow.texture:SetRotation(math.atan2(dWest, dNorth) - facing)
    arrow.texture:Show()
  else
    arrow.texture:Hide()
  end
  arrow:Show()
end

local function build()
  arrow = CreateFrame("Frame", "ForeverAtlasArrow", UIParent)
  arrow:SetSize(140, 84)
  ns.MakeMovable(arrow, "arrow", "TOP", 0, -140)
  arrow:EnableMouse(not ns.GetOption("hudLock"))
  ns.OnOption(function(key, value)
    if key == "hudLock" then
      arrow:EnableMouse(not value)
    end
  end)
  arrow:Hide()

  arrow.texture = arrow:CreateTexture(nil, "ARTWORK")
  arrow.texture:SetSize(48, 48)
  arrow.texture:SetPoint("TOP")
  arrow.texture:SetTexture("Interface\\Minimap\\MinimapArrow")

  arrow.distance = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  arrow.distance:SetPoint("TOP", arrow.texture, "BOTTOM", 0, -2)
  arrow.label = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  arrow.label:SetPoint("TOP", arrow.distance, "BOTTOM", 0, -2)
  arrow.label:SetWidth(200)

  driver = CreateFrame("Frame")
  local elapsed = INTERVAL
  driver:SetScript("OnUpdate", function(self, delta)
    elapsed = elapsed + delta
    if elapsed < INTERVAL then
      return
    end
    elapsed = 0
    local ok, err = pcall(update)
    if not ok then
      self:Hide()
      arrow:Hide()
      geterrorhandler()(err)
    end
  end)
  driver:SetShown(#waypoints() > 0)
end

ns.AddPinProvider(function(mapID, add)
  for _, waypoint in ipairs(waypoints()) do
    local x, y = ns.ProjectToMap(waypoint.mapID, waypoint.x, waypoint.y, mapID)
    if x then
      add(x, y, {
        look = PIN_LOOK,
        size = 24,
        tooltip = function(tooltip)
          tooltip:AddLine(waypoint.label, 1, 0.82, 0)
          tooltip:AddLine(string.format("%s  %.1f, %.1f", ns.MapName(waypoint.mapID), waypoint.x, waypoint.y), 1, 1, 1)
          tooltip:AddLine("Click to remove", 0.6, 0.6, 0.6)
        end,
        click = function()
          ns.RemoveWaypoint(waypoint)
        end,
      })
    end
  end
end)

-- Finds a map by name among the maps of the world. Returns mapID, or nil and a message.
local function findMap(name)
  local wanted = name:lower()
  local ok, maps = pcall(C_Map.GetMapChildrenInfo, WORLD_MAP, nil, true)
  if not ok or type(maps) ~= "table" or #maps == 0 then
    ok, maps = pcall(C_Map.GetMapChildrenInfo, WORLD_MAP, Enum.UIMapType.Zone, true)
  end
  if not ok or type(maps) ~= "table" then
    return nil, "the game gives no list of zones here."
  end
  local exact, partial, names, seen = nil, {}, {}, {}
  for _, info in ipairs(maps) do
    local mapName = type(info.name) == "string" and info.name:lower()
    if mapName == wanted then
      if not exact or info.mapType == Enum.UIMapType.Zone then
        exact = info.mapID
      end
    elseif mapName and mapName:find(wanted, 1, true) and not seen[mapName] then
      seen[mapName] = true
      partial[#partial + 1] = info.mapID
      names[#names + 1] = info.name
    end
  end
  if exact then
    return exact
  end
  if #partial == 1 then
    return partial[1]
  end
  if #partial == 0 then
    return nil, "no zone is named \"" .. name .. "\"."
  end
  table.sort(names)
  return nil, "more than one zone matches: " .. table.concat(names, ", ", 1, math.min(#names, 6)) .. "."
end

local function usage()
  ns.Print("waypoints:")
  print("  /way 45.2 61.8 - a waypoint in the zone you are in")
  print("  /way Elwynn Forest 45.2 61.8 - a waypoint in another zone")
  print("  /way 45.2 61.8 Old mine - a waypoint with a name")
  print("  /way list - list your waypoints")
  print("  /way clear - remove all waypoints")
  print("  (/fatlas way ... does the same)")
end

function ns.WaypointCommand(input)
  local text = (input or ""):gsub(",", " "):match("^%s*(.-)%s*$")
  local command = text:lower()
  if command == "" or command == "help" then
    usage()
    return
  end
  if command == "clear" then
    ns.ClearWaypoints()
    ns.Print("waypoints removed.")
    return
  end
  if command == "list" then
    if #waypoints() == 0 then
      ns.Print("no waypoints.")
    end
    for _, waypoint in ipairs(waypoints()) do
      ns.Print(describe(waypoint))
    end
    return
  end
  local words = {}
  for word in text:gmatch("%S+") do
    words[#words + 1] = word
  end
  local at
  for i = 1, #words - 1 do
    if tonumber(words[i]) and tonumber(words[i + 1]) then
      at = i
      break
    end
  end
  if not at then
    usage()
    return
  end
  local x, y = tonumber(words[at]), tonumber(words[at + 1])
  if x < 0 or x > 100 or y < 0 or y > 100 then
    ns.Print("coordinates are numbers from 0 to 100.")
    return
  end
  local mapID
  if at > 1 then
    local message
    mapID, message = findMap(table.concat(words, " ", 1, at - 1))
    if not mapID then
      ns.Print(message)
      return
    end
  else
    mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
      ns.Print("the game does not give your zone here. Name the zone: /way Elwynn Forest 45.2 61.8")
      return
    end
  end
  local waypoint = ns.AddWaypoint(mapID, x, y, table.concat(words, " ", at + 2))
  ns.Print("waypoint set: " .. describe(waypoint) .. ".")
end

local function slashTaken(command)
  for name in pairs(SlashCmdList) do
    local i = 1
    while type(_G["SLASH_" .. name .. i]) == "string" do
      if _G["SLASH_" .. name .. i]:lower() == command then
        return true
      end
      i = i + 1
    end
  end
  return false
end

ns.OnLogin(function()
  local list = waypoints()
  for i = #list, 1, -1 do
    local waypoint = list[i]
    if type(waypoint) ~= "table" or not ns.Usable(waypoint.mapID) or not ns.Usable(waypoint.x) or not ns.Usable(waypoint.y) then
      table.remove(list, i)
    elseif type(waypoint.label) ~= "string" then
      waypoint.label = ns.MapName(waypoint.mapID)
    end
  end
  build()
  -- All addons have loaded by now: /way stays with an addon that already has it.
  if not slashTaken("/way") then
    SLASH_FOREVERATLASWAY1 = "/way"
    SlashCmdList["FOREVERATLASWAY"] = ns.WaypointCommand
  end
end)
