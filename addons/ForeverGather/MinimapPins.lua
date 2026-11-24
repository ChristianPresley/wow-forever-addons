local _, ns = ...

-- Pins of the learned nodes on the minimap. The minimap shows C_Minimap.GetViewRadius() yards
-- around the player. Where a map lies in the world comes from C_Map.GetWorldPosFromMapPos at
-- three corners of the map, so no axis of world space is assumed. With that, a node of another
-- zone of the same continent has a place on the player's map too (outside 0 to 1), and shows
-- on the minimap near the border.

local UPDATE_SECONDS = 0.1
local LIST_SECONDS = 5 -- the list of nodes is built again after this long (the skill can change)
local FALLBACK_RADIUS = 150 -- yards, when the client gives no radius

local layer
local pins, shown = {}, 0
local frames = {} -- [mapID] = { continent, ox, oy, ux, uy, vx, vy, width, height }, or false

-- Where a map lies in the world: its corner (ox, oy), the vectors of its width (ux, uy) and its
-- height (vx, vy) in yards, and the continent. Nil for a map without a place.
function ns.MapFrame(mapID)
  local known = frames[mapID]
  if known ~= nil then
    return known or nil
  end
  local continent
  local function at(x, y)
    local id, position = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if position and ns.Usable(position.x) and ns.Usable(position.y) then
      continent = id
      return position.x, position.y
    end
  end
  local ax, ay = at(0, 0)
  local bx, by = at(1, 0)
  local cx, cy = at(0, 1)
  frames[mapID] = false
  if not (ax and bx and cx) or not ns.Usable(continent) then
    return nil
  end
  local frame = { continent = continent, ox = ax, oy = ay, ux = bx - ax, uy = by - ay, vx = cx - ax, vy = cy - ay }
  frame.width = math.sqrt(frame.ux ^ 2 + frame.uy ^ 2)
  frame.height = math.sqrt(frame.vx ^ 2 + frame.vy ^ 2)
  if frame.width <= 0 or frame.height <= 0 then
    return nil
  end
  frames[mapID] = frame
  return frame
end

-- The width and height of a map in yards, or nil.
function ns.MapYards(mapID)
  local frame = ns.MapFrame(mapID)
  if frame then
    return frame.width, frame.height
  end
  return nil
end

-- A point of one map as a point of another map of the same continent (it can be outside 0 to
-- 1), or nil.
function ns.OnOtherMap(fromMap, x, y, toMap)
  local from, to = ns.MapFrame(fromMap), ns.MapFrame(toMap)
  if not from or not to or from.continent ~= to.continent then
    return nil
  end
  local dx = from.ox + x * from.ux + y * from.vx - to.ox
  local dy = from.oy + x * from.uy + y * from.vy - to.oy
  return (dx * to.ux + dy * to.uy) / (to.width * to.width), (dx * to.vx + dy * to.vy) / (to.height * to.height)
end

-- The nodes that can show on the minimap of a player on mapID, each with its place on that
-- map: { { node = node, mapID = n, x = n, y = n }, ... }. The nodes of the map itself, and the
-- nodes of the other zones of its continent.
function ns.NodesAround(mapID)
  local out = {}
  for _, node in ipairs(ns.VisibleNodes(mapID)) do
    out[#out + 1] = { node = node, mapID = mapID, x = node.x, y = node.y }
  end
  for otherMap in pairs(ForeverGatherDB and ForeverGatherDB.nodes or {}) do
    if otherMap ~= mapID and ns.Usable(otherMap) and not ns.MapTooLarge(otherMap) then
      for _, node in ipairs(ns.VisibleNodes(otherMap)) do
        local x, y = ns.OnOtherMap(otherMap, node.x, node.y, mapID)
        if not x then
          break -- the map has no place on this continent
        end
        out[#out + 1] = { node = node, mapID = otherMap, x = x, y = y }
      end
    end
  end
  return out
end

-- The same list, kept until the nodes or the options change, the player is on another map, or
-- LIST_SECONDS passed. The second result is a number that changes with each new list.
local list, listMap, listTime
local listDirty, listNumber = true, 0
function ns.NearList(mapID)
  local now = GetTime()
  if listDirty or mapID ~= listMap or now - listTime > LIST_SECONDS then
    list, listMap, listTime = ns.NodesAround(mapID), mapID, now
    listDirty = false
    listNumber = listNumber + 1
  end
  return list, listNumber
end
ns.OnChange(function()
  listDirty = true
end)

-- Where a node is on the minimap, in pixels from its centre (right, up), or nil off the minimap.
-- facing is the player's facing in radians when the minimap turns with the player, else nil.
-- square is true for a square minimap: its corners show too.
function ns.MinimapOffset(node, px, py, width, height, radius, half, facing, square)
  local east = (node.x - px) * width
  local north = (py - node.y) * height
  if not square and east * east + north * north > radius * radius then
    return nil
  end
  if facing then
    local c, s = math.cos(facing), math.sin(facing)
    east, north = east * c + north * s, north * c - east * s
  end
  if square and (math.abs(east) > radius or math.abs(north) > radius) then
    return nil
  end
  return east / radius * half, north / radius * half
end

-- Addons that change the form of the minimap say so with the global function GetMinimapShape
-- (a convention among addons; the game has no such function).
local function isSquare()
  local shape = rawget(_G, "GetMinimapShape")
  return type(shape) == "function" and shape() == "SQUARE"
end

local function hideAll()
  for index = 1, shown do
    pins[index]:Hide()
  end
  shown = 0
end

-- What the pins were last placed for. Nothing is done while none of it changes.
local last = {}
local dirty = true

local function draw()
  if not layer then
    return
  end
  local mapID, px, py
  if ns.GetOption("minimap") then
    mapID, px, py = ns.PlayerPosition()
  end
  local width, height
  if mapID then
    width, height = ns.MapYards(mapID)
  end
  if not width then
    if shown > 0 or dirty then
      hideAll()
      wipe(last)
    end
    return
  end
  local radius = C_Minimap.GetViewRadius()
  if not ns.Usable(radius) or radius <= 0 then
    radius = FALLBACK_RADIUS
  end
  local half = Minimap:GetWidth() / 2
  local facing = false
  if GetCVar("rotateMinimap") == "1" then
    facing = GetPlayerFacing()
    if not ns.Usable(facing) then
      -- The game hides the facing here; a wrong turn would put pins in wrong places.
      hideAll()
      wipe(last)
      return
    end
  end
  local size = ns.GetOption("size")
  local square = isSquare()
  local near, number = ns.NearList(mapID)
  if not dirty and last.number == number and last.px == px and last.py == py and last.radius == radius
    and last.half == half and last.facing == facing and last.size == size and last.square == square then
    return
  end
  dirty = false
  last.number = number
  last.px, last.py, last.radius, last.half, last.facing, last.size, last.square = px, py, radius, half, facing, size, square
  local count = 0
  for _, entry in ipairs(near) do
    local x, y = ns.MinimapOffset(entry, px, py, width, height, radius, half, facing or nil, square)
    if x then
      count = count + 1
      local pin = pins[count]
      if not pin then
        pin = ns.NewPin(layer)
        pins[count] = pin
      end
      ns.SetPinNode(pin, entry.node, size, entry.mapID)
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", layer, "CENTER", x, y)
      pin:Show()
    end
  end
  for index = count + 1, shown do
    pins[index]:Hide()
  end
  shown = count
end

function ns.MinimapPinCount()
  return shown
end

function ns.RefreshMinimapPins()
  dirty = true
  draw()
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
  ns.OnChange(ns.RefreshMinimapPins)
end
