local _, ns = ...

-- A route through the nodes of a zone: the visible nodes in an order that is short to ride, as
-- a closed line on the world map. The order starts with "always to the nearest node that is
-- left", and is then made shorter by turning parts of it around where two legs cross (2-opt).

local MAX_NODES = 120 -- of a zone with more, the nodes with the most gathers
local PASSES = 6 -- rounds of making the order shorter
local COLOUR = { 1, 0.82, 0.2, 0.7 }

local routes = {} -- [mapID] = { nodes = { node, ... }, yards = n }
ns.OnChange(function()
  wipe(routes)
end)

-- The nodes of a map in the order of the route, and the length of the closed route in yards
-- (0 where the game gives no yards for the map).
function ns.Route(mapID)
  if not mapID then
    return {}, 0
  end
  local known = routes[mapID]
  if known then
    return known.nodes, known.yards
  end
  local width, height = ns.MapYards(mapID)
  local hasYards = width ~= nil
  width, height = width or 1, height or 1
  local left = {}
  for _, node in ipairs(ns.VisibleNodes(mapID)) do
    left[#left + 1] = node
  end
  if #left > MAX_NODES then
    table.sort(left, function(a, b)
      if a.count ~= b.count then
        return a.count > b.count
      end
      return a.x < b.x
    end)
    for index = #left, MAX_NODES + 1, -1 do
      left[index] = nil
    end
  end
  local function distance(a, b)
    local dx, dy = (a.x - b.x) * width, (a.y - b.y) * height
    return math.sqrt(dx * dx + dy * dy)
  end
  -- Start at the node farthest to the west, then always the nearest node that is left.
  local order = {}
  if #left > 0 then
    local first = 1
    for index, node in ipairs(left) do
      if node.x < left[first].x then
        first = index
      end
    end
    order[1] = table.remove(left, first)
  end
  while #left > 0 do
    local from, best, bestDistance = order[#order], 1, nil
    for index, node in ipairs(left) do
      local d = distance(from, node)
      if not bestDistance or d < bestDistance then
        best, bestDistance = index, d
      end
    end
    order[#order + 1] = table.remove(left, best)
  end
  -- 2-opt: where the legs a-b and c-d are longer than a-c and b-d, the part from b to c turns around.
  local count = #order
  if count > 3 then
    for _ = 1, PASSES do
      local shorter = false
      for i = 1, count - 2 do
        for j = i + 2, count do
          local a, b = order[i], order[i + 1]
          local c, d = order[j], order[j % count + 1]
          if a ~= d and distance(a, b) + distance(c, d) > distance(a, c) + distance(b, d) + 1e-9 then
            local low, high = i + 1, j
            while low < high do
              order[low], order[high] = order[high], order[low]
              low, high = low + 1, high - 1
            end
            shorter = true
          end
        end
      end
      if not shorter then
        break
      end
    end
  end
  local yards = 0
  if hasYards and count > 1 then
    for index = 1, count do
      yards = yards + distance(order[index], order[index % count + 1])
    end
  end
  routes[mapID] = { nodes = order, yards = yards }
  return order, yards
end

-- The lines of the route on the layer of the world map.
local lines, shown = {}, 0

function ns.HideRoute()
  for index = 1, shown do
    lines[index]:Hide()
  end
  shown = 0
end

-- Draws the route of a map on a layer of the given size. scale is the zoom of the map: the line
-- keeps its thickness on the screen.
function ns.DrawRoute(layer, mapID, width, height, scale)
  ns.HideRoute()
  if not ns.GetOption("route") then
    return
  end
  local order = ns.Route(mapID)
  local count = #order
  if count < 2 then
    return
  end
  local legs = count == 2 and 1 or count -- two nodes: one line, not there and back
  for index = 1, legs do
    local from, to = order[index], order[index % count + 1]
    local line = lines[index]
    if not line then
      line = layer:CreateLine(nil, "ARTWORK")
      line:SetColorTexture(COLOUR[1], COLOUR[2], COLOUR[3], COLOUR[4])
      lines[index] = line
    end
    line:SetThickness(2 / scale)
    line:SetStartPoint("TOPLEFT", layer, from.x * width, -from.y * height)
    line:SetEndPoint("TOPLEFT", layer, to.x * width, -to.y * height)
    line:Show()
  end
  shown = legs
end

function ns.RouteLineCount()
  return shown
end
