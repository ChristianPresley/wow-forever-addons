local _, ns = ...

-- Pins of the learned nodes on the minimap. The minimap shows a circle of C_Minimap.GetViewRadius()
-- yards around the player. A node's offset in yards comes from the size of its zone in yards
-- (C_Map.GetWorldPosFromMapPos at the corners of the map), so no axis of world space is assumed.

local UPDATE_SECONDS = 0.1
local FALLBACK_RADIUS = 150 -- yards, when the client gives no radius

local layer
local active, pool = {}, {}
local zoneSizes = {} -- [mapID] = { width, height } in yards, or false

-- The width and height of a map in yards, or nil.
function ns.MapYards(mapID)
  local known = zoneSizes[mapID]
  if known ~= nil then
    if known then
      return known[1], known[2]
    end
    return nil
  end
  local function at(x, y)
    local _, position = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if position and ns.Usable(position.x) and ns.Usable(position.y) then
      return position.x, position.y
    end
  end
  local ax, ay = at(0, 0)
  local bx, by = at(1, 0)
  local cx, cy = at(0, 1)
  if not (ax and bx and cx) then
    zoneSizes[mapID] = false
    return nil
  end
  local width = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
  local height = math.sqrt((cx - ax) ^ 2 + (cy - ay) ^ 2)
  if width <= 0 or height <= 0 then
    zoneSizes[mapID] = false
    return nil
  end
  zoneSizes[mapID] = { width, height }
  return width, height
end

-- Where a node is on the minimap, in pixels from its centre (right, up), or nil off the circle.
-- facing is the player's facing in radians when the minimap turns with the player, else nil.
function ns.MinimapOffset(node, px, py, width, height, radius, half, facing)
  local east = (node.x - px) * width
  local north = (py - node.y) * height
  if east * east + north * north > radius * radius then
    return nil
  end
  if facing then
    local c, s = math.cos(facing), math.sin(facing)
    east, north = east * c + north * s, north * c - east * s
  end
  return east / radius * half, north / radius * half
end

local function release()
  for index = #active, 1, -1 do
    local pin = active[index]
    pin:Hide()
    pin.node = nil
    active[index] = nil
    pool[#pool + 1] = pin
  end
end

local function draw()
  release()
  if not layer or not ns.GetOption("minimap") then
    return
  end
  local mapID, px, py = ns.PlayerPosition()
  if not mapID then
    return
  end
  local width, height = ns.MapYards(mapID)
  if not width then
    return
  end
  local radius = C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
  if not ns.Usable(radius) or radius <= 0 then
    radius = FALLBACK_RADIUS
  end
  local half = Minimap:GetWidth() / 2
  local facing
  if GetCVar("rotateMinimap") == "1" then
    facing = GetPlayerFacing()
    if not ns.Usable(facing) then
      return -- the game hides the facing here; a wrong turn would put pins in wrong places
    end
  end
  local size = ns.GetOption("size")
  for _, node in ipairs(ns.VisibleNodes(mapID)) do
    local x, y = ns.MinimapOffset(node, px, py, width, height, radius, half, facing)
    if x then
      local pin = table.remove(pool) or ns.NewPin(layer)
      ns.SetPinNode(pin, node, size)
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", layer, "CENTER", x, y)
      pin:Show()
      active[#active + 1] = pin
    end
  end
end

function ns.MinimapPinCount()
  return #active
end

function ns.RefreshMinimapPins()
  if layer then
    draw()
  end
end

if Minimap then
  layer = CreateFrame("Frame", nil, Minimap)
  layer:SetAllPoints(Minimap)
  layer:SetFrameLevel(Minimap:GetFrameLevel() + 5)
  local since = 0
  layer:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since >= UPDATE_SECONDS then
      since = 0
      draw()
    end
  end)
  ns.OnChange(draw)
end
