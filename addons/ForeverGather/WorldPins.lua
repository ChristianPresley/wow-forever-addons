local _, ns = ...

-- Pins of the learned nodes on the world map. ForeverAtlas keeps its pin layer to itself, so
-- this is a layer of its own on the map canvas. The pins take no clicks, so the map under them
-- still zooms; the pointer over one shows its tooltip.

local layer
local active, pool = {}, {}
local shownMap, shownWidth, shownHeight
local dirty = true

local TOOLTIP_LOOT = 3 -- the items of a node that its tooltip names

local function fillTooltip(tooltip, node, withMenu)
  tooltip:AddLine(node.name)
  tooltip:AddLine(ns.KIND[node.kind].name, 0.8, 0.8, 0.8)
  if node.count == 0 then
    tooltip:AddLine("From an import, not gathered yet", 1, 1, 1)
  else
    tooltip:AddLine(string.format("Gathered %d |4time:times;", node.count), 1, 1, 1)
  end
  local skill = ns.LearnedSkill(node.name)
  if skill then
    tooltip:AddLine(string.format("Gathered at %s %d", ns.KIND[node.kind].skill, skill), 1, 1, 1)
    local word, r, g, b = ns.Difficulty(node)
    if word then
      tooltip:AddLine("For your skill: " .. word, r, g, b)
    end
  end
  local days = ns.DaysSince(node.last)
  if days then
    tooltip:AddLine(days == 0 and "Last gathered today" or string.format("Last gathered %d |4day:days; ago", days), 0.8, 0.8, 0.8)
  end
  for index, entry in ipairs(ns.LootOf(node)) do
    if index > TOOLTIP_LOOT then
      break
    end
    tooltip:AddLine(string.format("%s: %d, %.1f for each gather", entry.item, entry.count, entry.count / math.max(1, node.looted or 1)), 0.6, 0.8, 1)
  end
  if withMenu then
    tooltip:AddLine("Right-click: map pin, forget", 0.5, 0.5, 0.5)
  end
end

-- Puts the map pin of the game on a node. Returns a line for the player.
function ns.SetWaypoint(mapID, node)
  if not C_Map.CanSetUserWaypointOnMap(mapID) then
    return "the game takes no map pin on this map."
  end
  if not C_Map.SetUserWaypoint({ uiMapID = mapID, position = CreateVector2D(node.x, node.y) }) then
    return "the game refused the map pin."
  end
  C_SuperTrack.SetSuperTrackedUserWaypoint(true)
  return "the map pin is on " .. node.name .. "."
end

-- The menu of a pin: a map pin on the node, and forget the node.
function ns.PinMenu(pin)
  local node, mapID = pin.node, pin.mapID
  if not node or not mapID then
    return
  end
  MenuUtil.CreateContextMenu(pin, function(_, root)
    root:CreateTitle(node.name)
    root:CreateButton("Put the map pin here", function()
      ns.Print(ns.SetWaypoint(mapID, node))
    end)
    root:CreateButton("Forget this node", function()
      if ns.ForgetNode(mapID, node) then
        ns.Print("Forgot " .. node.name .. ".")
      end
    end)
  end)
end

-- Whole days since a time() value, or nil without one.
function ns.DaysSince(at)
  if type(at) ~= "number" then
    return nil
  end
  return math.max(0, math.floor((time() - at) / 86400))
end

local function showTooltip(pin)
  if not pin.node then
    return
  end
  GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
  fillTooltip(GameTooltip, pin.node, pin.clicks)
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
  -- The dot of the difficulty, in the lower right corner.
  pin.dot = pin:CreateTexture(nil, "OVERLAY")
  pin.dot:SetPoint("BOTTOMRIGHT", 1, -1)
  pin.dot:Hide()
  pin:SetMouseClickEnabled(false)
  pin:SetMouseMotionEnabled(true)
  pin:SetScript("OnEnter", showTooltip)
  pin:SetScript("OnLeave", hideTooltip)
  pin:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
      ns.PinMenu(self)
    end
  end)
  return pin
end

-- The right button of a pin opens its menu; the left button goes on to the map under the pin.
-- The game refuses this change of a frame in a fight, so a pin made in a fight gets it later.
local function takeClicks(pin)
  if pin.clicks or InCombatLockdown() then
    return
  end
  pin:SetMouseClickEnabled(true)
  pin:SetPassThroughButtons("LeftButton", "MiddleButton", "Button4", "Button5")
  pin.clicks = true
end

function ns.SetPinNode(pin, node, size, mapID)
  pin.node = node
  pin.mapID = mapID
  pin.icon:SetTexture(ns.KIND[node.kind].icon)
  pin:SetSize(size, size)
  pin:SetAlpha(ns.RecentlyGathered(node) and 0.4 or 1)
  local word, r, g, b
  if ns.GetOption("skillColours") then
    word, r, g, b = ns.Difficulty(node)
  end
  if word then
    pin.dot:SetSize(size * 0.4, size * 0.4)
    pin.dot:SetColorTexture(r, g, b, 1)
    pin.dot:Show()
  else
    pin.dot:Hide()
  end
  takeClicks(pin)
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
    ns.SetPinNode(pin, node, size, shownMap)
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
