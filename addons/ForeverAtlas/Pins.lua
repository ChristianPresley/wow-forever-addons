local _, ns = ...

-- One pin layer on the world map canvas, shared by waypoints, visited areas and notes.
-- A provider is fn(mapID, add); it calls add(x, y, data) with x, y from 0 to 100 and
-- data = { look = , size = , tooltip = fn(tooltip), click = fn(button) }.
-- Pins without click take no mouse input, so the map under them still zooms on a click.

local HOVER_INTERVAL = 0.1

local providers = {}
local active, pool = {}, {}
local layer, hovered
local dirty = true
local shownMap, shownScale, shownWidth, shownHeight
local sinceHover = 0

function ns.AddPinProvider(fn)
  providers[#providers + 1] = fn
end

-- The providers, for the Forever Atlas map (Map.lua), which shows the same pins.
function ns.PinProviders()
  return providers
end

function ns.RefreshPins()
  dirty = true
  if ns.RefreshMapPins then
    ns.RefreshMapPins()
  end
end

-- x, y (0 to 100) of a point of mapID on the shown map, when that is the same map or one above it.
function ns.ProjectToMap(mapID, x, y, shown)
  if mapID == shown then
    return x, y
  end
  if not C_Map.GetMapRectOnMap then
    return nil
  end
  local id = mapID
  for _ = 1, 8 do
    local ok, info = pcall(C_Map.GetMapInfo, id)
    id = ok and info and info.parentMapID
    if not id or id == 0 then
      return nil
    end
    if id == shown then
      local found, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, mapID, shown)
      if not found or not ns.Usable(left) or not ns.Usable(right) or not ns.Usable(top) or not ns.Usable(bottom) then
        return nil
      end
      if right <= left or bottom <= top then
        return nil
      end
      return (left + (right - left) * x / 100) * 100, (top + (bottom - top) * y / 100) * 100
    end
  end
  return nil
end

local function showTooltip(pin)
  if not pin.data or not pin.data.tooltip then
    return
  end
  GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
  pin.data.tooltip(GameTooltip)
  GameTooltip:Show()
end

local function hideTooltip(pin)
  if GameTooltip:IsOwned(pin) then
    GameTooltip:Hide()
  end
end

local function acquire()
  local pin = table.remove(pool)
  if not pin then
    pin = CreateFrame("Frame", nil, layer)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin:SetScript("OnEnter", showTooltip)
    pin:SetScript("OnLeave", hideTooltip)
    pin:SetScript("OnMouseUp", function(self, button)
      if self.data and self.data.click and self:IsMouseOver() then
        self.data.click(button)
      end
    end)
  end
  return pin
end

local function releaseAll()
  if hovered then
    hideTooltip(hovered)
    hovered = nil
  end
  for i = #active, 1, -1 do
    local pin = active[i]
    hideTooltip(pin)
    pin:Hide()
    pin.data = nil
    pool[#pool + 1] = pin
    active[i] = nil
  end
end

local function rebuild(mapID)
  releaseAll()
  if not mapID then
    return
  end
  local function add(x, y, data)
    if not ns.Usable(x) or not ns.Usable(y) or x < 0 or x > 100 or y < 0 or y > 100 then
      return
    end
    local pin = acquire()
    pin.x, pin.y, pin.data = x / 100, y / 100, data
    pin:SetSize(data.size or 16, data.size or 16)
    ns.SetIcon(pin.icon, data.look)
    pin:EnableMouse(data.click ~= nil)
    pin:Show()
    active[#active + 1] = pin
  end
  for _, provider in ipairs(providers) do
    local ok, err = pcall(provider, mapID, add)
    if not ok then
      geterrorhandler()(err)
    end
  end
end

-- Pins keep their size on screen: the canvas scales with the zoom, each pin by the inverse.
local function layout(canvas, scale, width, height)
  for _, pin in ipairs(active) do
    pin:SetScale(1 / scale)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", width * pin.x * scale, -height * pin.y * scale)
  end
end

local function updateHover()
  local found
  local container = WorldMapFrame.ScrollContainer
  if not container or container:IsMouseOver() then
    for _, pin in ipairs(active) do
      if not pin.data.click and pin:IsMouseOver() then
        found = pin
        break
      end
    end
  end
  if found == hovered then
    return
  end
  if hovered then
    hideTooltip(hovered)
  end
  hovered = found
  if found then
    showTooltip(found)
  end
end

local function step(delta)
  local canvas = WorldMapFrame:GetCanvas()
  local mapID = WorldMapFrame:GetMapID()
  local scale = WorldMapFrame:GetCanvasScale()
  local width, height = canvas:GetWidth(), canvas:GetHeight()
  if not ns.Usable(scale) or scale <= 0 then
    return
  end
  if dirty or mapID ~= shownMap then
    dirty = false
    shownMap = mapID
    rebuild(mapID)
    shownScale = nil
  end
  if scale ~= shownScale or width ~= shownWidth or height ~= shownHeight then
    shownScale, shownWidth, shownHeight = scale, width, height
    layout(canvas, scale, width, height)
  end
  sinceHover = sinceHover + delta
  if sinceHover >= HOVER_INTERVAL then
    sinceHover = 0
    updateHover()
  end
end

local function frameLevel(canvas)
  local manager = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
  if manager and manager.GetValidFrameLevel then
    for _, name in ipairs({ "PIN_FRAME_LEVEL_WAYPOINT_LOCATION", "PIN_FRAME_LEVEL_MAP_HIGHLIGHT" }) do
      local ok, level = pcall(manager.GetValidFrameLevel, manager, name)
      if ok and ns.Usable(level) then
        return level
      end
    end
  end
  return math.min(9000, canvas:GetFrameLevel() + 2000)
end

local function build()
  if not (WorldMapFrame.GetCanvas and WorldMapFrame.GetCanvasScale and WorldMapFrame.GetMapID) then
    return
  end
  local canvas = WorldMapFrame:GetCanvas()
  if not canvas then
    return
  end
  layer = CreateFrame("Frame", nil, canvas)
  layer:SetAllPoints(canvas)
  layer:SetFrameLevel(frameLevel(canvas))
  layer:SetScript("OnUpdate", function(self, delta)
    local ok, err = pcall(step, delta)
    if not ok then
      -- A client without the expected map API: the pins go, the map stays.
      self:SetScript("OnUpdate", nil)
      self:Hide()
      geterrorhandler()(err)
    end
  end)
  layer:SetScript("OnHide", function()
    if hovered then
      hideTooltip(hovered)
      hovered = nil
    end
  end)
end

-- fn runs once the world map exists.
function ns.WhenMapReady(fn)
  if WorldMapFrame then
    fn()
    return
  end
  local waiter = CreateFrame("Frame")
  waiter:RegisterEvent("ADDON_LOADED")
  waiter:SetScript("OnEvent", function(self)
    if WorldMapFrame then
      self:UnregisterEvent("ADDON_LOADED")
      fn()
    end
  end)
end

ns.OnLogin(function()
  ns.WhenMapReady(build)
end)
