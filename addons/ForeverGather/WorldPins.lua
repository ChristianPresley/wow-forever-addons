local _, ns = ...

-- Pins of the learned nodes on the world map. ForeverAtlas keeps its pin layer to itself, so
-- this is a layer of its own on the map canvas. The pins take no clicks, so the map under them
-- still zooms; the pointer over one shows its tooltip.

local layer
local active, pool = {}, {}
local shownMap, shownWidth, shownHeight
local dirty = true

local function fillTooltip(tooltip, node)
  tooltip:AddLine(node.name)
  tooltip:AddLine(ns.KIND[node.kind].name, 0.8, 0.8, 0.8)
  tooltip:AddLine(string.format("Gathered %d |4time:times;", node.count), 1, 1, 1)
  local skill = ns.LearnedSkill(node.name)
  if skill then
    tooltip:AddLine(string.format("Gathered at %s %d", ns.KIND[node.kind].skill, skill), 1, 1, 1)
  end
end

local function showTooltip(pin)
  if not pin.node then
    return
  end
  GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
  fillTooltip(GameTooltip, pin.node)
  GameTooltip:Show()
end

local function hideTooltip(pin)
  if GameTooltip:IsOwned(pin) then
    GameTooltip:Hide()
  end
end

-- A pin frame with an icon; shared by the world map and the minimap.
function ns.NewPin(parent)
  local pin = CreateFrame("Frame", nil, parent)
  pin.icon = pin:CreateTexture(nil, "ARTWORK")
  pin.icon:SetAllPoints()
  pin:SetMouseClickEnabled(false)
  pin:SetMouseMotionEnabled(true)
  pin:SetScript("OnEnter", showTooltip)
  pin:SetScript("OnLeave", hideTooltip)
  return pin
end

function ns.SetPinNode(pin, node, size)
  pin.node = node
  pin.icon:SetTexture(ns.KIND[node.kind].icon)
  pin:SetSize(size, size)
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
  shownMap = WorldMapFrame:GetMapID()
  if not layer or not ns.GetOption("worldMap") or not ns.Usable(shownMap) then
    return
  end
  local canvas = layer:GetParent()
  local width, height = canvas:GetWidth(), canvas:GetHeight()
  shownWidth, shownHeight = width, height
  if not ns.Usable(width) or not ns.Usable(height) or width <= 0 or height <= 0 then
    return
  end
  -- The canvas grows as the map zooms in; pins keep their size on the screen.
  local scale = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
  if not ns.Usable(scale) or scale <= 0 then
    scale = 1
  end
  local size = (ns.GetOption("size") + 2) / scale
  for _, node in ipairs(ns.VisibleNodes(shownMap)) do
    local pin = table.remove(pool) or ns.NewPin(layer)
    ns.SetPinNode(pin, node, size)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", layer, "TOPLEFT", node.x * width, -node.y * height)
    pin:Show()
    active[#active + 1] = pin
  end
end

function ns.WorldPinCount()
  return #active
end

local function setup()
  if layer or not WorldMapFrame or not WorldMapFrame.GetCanvas then
    return
  end
  local canvas = WorldMapFrame:GetCanvas()
  layer = CreateFrame("Frame", nil, canvas)
  layer:SetAllPoints(canvas)
  layer:SetFrameLevel(canvas:GetFrameLevel() + 20)
  local since = 0
  layer:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 0.2 then
      return
    end
    since = 0
    if dirty or WorldMapFrame:GetMapID() ~= shownMap or layer:GetParent():GetWidth() ~= shownWidth or layer:GetParent():GetHeight() ~= shownHeight then
      dirty = false
      draw()
    end
  end)
end

function ns.RefreshWorldPins()
  setup()
  dirty = false
  if layer and WorldMapFrame:IsShown() then
    draw()
  else
    dirty = true
  end
end

-- With the public pin interface of ForeverAtlas (ForeverAtlasAPI, planned by its owner), its
-- pin layer shows the nodes, on the game's map and in its own map window, and this layer stays off.
local atlas = rawget(_G, "ForeverAtlasAPI")
if type(atlas) == "table" and type(atlas.AddPinProvider) == "function" then
  ns.usesAtlas = true
  atlas.AddPinProvider(function(mapID, add)
    if not ns.GetOption("worldMap") then
      return
    end
    for _, node in ipairs(ns.VisibleNodes(mapID)) do
      add(node.x * 100, node.y * 100, {
        look = { texture = ns.KIND[node.kind].icon },
        size = ns.GetOption("size") + 2,
        tooltip = function(tooltip)
          fillTooltip(tooltip, node)
        end,
      })
    end
  end)
  ns.OnChange(function()
    if type(atlas.RefreshPins) == "function" then
      atlas.RefreshPins()
    end
  end)
  ns.RefreshWorldPins = function() end
  return
end

ns.OnChange(function()
  dirty = true
  if layer and WorldMapFrame:IsShown() then
    ns.RefreshWorldPins()
  end
end)
setup()
