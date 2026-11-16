local _, ns = ...

-- The Forever Atlas map: a map window of this addon, in the place of the world map of the game.
--
--   Mouse wheel   zooms toward the pointer, in small steps, as far in and out as wanted
--   Drag          moves the map
--   Click         opens the zone under the pointer
--   Right-click   goes out to the map above
--   Alt-click     adds a note at that place
--
-- The art of a map has layers: the whole map as one picture, and for many maps a finer picture
-- with more detail for a closer look. Each layer is a grid of images. The map shows the first
-- layer when the whole map is in the window and fades to the next one as the player zooms in,
-- the same way as the map of the game.
--
-- Why it does not wait: all images of all layers are put on one frame (the canvas) when the map
-- opens. A zoom or a move then changes the scale and the place of that one frame and the
-- opacity of its layers, and nothing else: no image is loaded and no frame is made while the
-- player zooms. The pins keep their size on the screen; they are moved only when the map moved.
--
-- The game's own map window is not changed. It has the quest log, so it stays one click away
-- (the button "Game map"), and it still opens for a click on a quest.
--
-- With the option mapKey, the key of the world map opens this map. The key gets a binding of
-- this addon over the game's own (an override binding), so no function of the game is replaced.
-- The game allows a change of bindings only out of a fight.

local ZOOM_STEP = 1.2 -- one notch of the wheel
local EASE_SECONDS = 0.06 -- the zoom reaches its goal in a few frames
local MAX_MAGNIFY = 3 -- how far past the pixels of the finest layer the map zooms in
local LAYER_STEP = 1.8 -- without zoom data of the game: each finer layer starts this much closer
local FADE_PART = 0.35 -- the last part of the way to a finer layer, over which it fades in
local DRAG_SLOP = 4 -- a press that moves less than this is a click
local INFO_INTERVAL = 0.05
local ARROW = "Interface\\Minimap\\MinimapArrow"

local QUEST_LOOK = { texture = "Interface\\GossipFrame\\AvailableQuestIcon" }
local TURN_IN_LOOK = { texture = "Interface\\GossipFrame\\ActiveQuestIcon" }

local window, viewport, canvas, overlay, arrow
local layerFrames = {} -- [index] = { frame = , tiles = {} }, one for each layer of the art
local exploredFrame
local overlays = {}
local pins, pinPool = {}, {}

-- The map on the screen. width and height are of the canvas, in the pixels of the art.
-- scale: screen units for one pixel of the art. x, y: where the top left corner of the canvas
-- is in the viewport, to the right and down.
-- layers: for each layer of the art, `start`: how many times closer than the whole map the
-- layer is fully shown (1 for the first), and `ratio`: its pixels for one pixel of the first.
local view = { mapID = nil, width = 1, height = 1, scale = 1, target = 1, x = 0, y = 0, minScale = 1, maxScale = 1, layers = {} }
local anchor -- the point of the map that stays under the pointer during a zoom
local drag
local dirty = true -- the canvas or the pins must be placed again
local sinceInfo = 0

---------------------------------------------------------------------------------------------------
-- Geometry

local function viewportSize()
  local width, height = viewport:GetWidth(), viewport:GetHeight()
  if not ns.Usable(width) or width <= 0 or not ns.Usable(height) or height <= 0 then
    return 1, 1
  end
  return width, height
end

-- The pointer in the viewport: to the right and down from its top left corner. Nil where the
-- game does not say.
local function pointer()
  local left, top = viewport:GetLeft(), viewport:GetTop()
  local scale = viewport:GetEffectiveScale()
  local x, y = GetCursorPosition()
  if not (ns.Usable(left) and ns.Usable(top) and ns.Usable(scale) and scale > 0 and ns.Usable(x) and ns.Usable(y)) then
    return nil
  end
  return x / scale - left, top - y / scale
end

-- A place of the viewport as a point of the map, both from 0 to 1 (outside the map: below 0 or above 1).
local function toMap(px, py)
  return (px - view.x) / (view.width * view.scale), (py - view.y) / (view.height * view.scale)
end

-- Keeps the map in the viewport: a map smaller than the viewport is in the middle, a larger
-- one never shows empty space beside it.
local function clampView()
  local width, height = viewportSize()
  local mapWidth, mapHeight = view.width * view.scale, view.height * view.scale
  if mapWidth <= width then
    view.x = (width - mapWidth) / 2
  else
    view.x = math.min(0, math.max(width - mapWidth, view.x))
  end
  if mapHeight <= height then
    view.y = (height - mapHeight) / 2
  else
    view.y = math.min(0, math.max(height - mapHeight, view.y))
  end
end

local function limits()
  local width, height = viewportSize()
  view.minScale = math.min(width / view.width, height / view.height)
  -- Far enough in to see the finest layer well: past its pixels, and past the place where it
  -- is fully shown.
  local finest = view.layers[#view.layers]
  local ratio, start = finest and finest.ratio or 1, finest and finest.start or 1
  view.maxScale = math.max(view.minScale * 2, MAX_MAGNIFY * ratio, view.minScale * start * 2)
end

-- The opacity of each layer for the zoom now. The first layer is always there; a finer one
-- fades in over the last part of the way to its start and stays.
local function layerAlpha(index)
  local layer = view.layers[index]
  if index == 1 or not layer then
    return layer and 1 or 0
  end
  local closer = view.scale / view.minScale
  local before = view.layers[index - 1].start
  local fade = (layer.start - before) * FADE_PART
  if fade <= 0 then
    return closer >= layer.start and 1 or 0
  end
  return math.min(1, math.max(0, (closer - (layer.start - fade)) / fade))
end

local function fit()
  limits()
  view.scale, view.target = view.minScale, view.minScale
  anchor = nil
  clampView()
  dirty = true
end

-- Zooms by a number of notches toward a place of the viewport (the middle if left out).
local function zoomAt(notches, px, py)
  local width, height = viewportSize()
  px, py = px or width / 2, py or height / 2
  limits()
  view.target = math.min(view.maxScale, math.max(view.minScale, view.target * ZOOM_STEP ^ notches))
  local mapX, mapY = toMap(px, py)
  anchor = { px = px, py = py, mapX = mapX, mapY = mapY }
end

-- One step of the zoom toward its goal. `elapsed` in seconds; nil goes to the goal at once.
local function stepZoom(elapsed)
  if view.scale == view.target then
    return
  end
  local part = elapsed and (1 - math.exp(-elapsed / EASE_SECONDS)) or 1
  local scale = view.scale + (view.target - view.scale) * part
  if math.abs(scale - view.target) < view.target * 0.002 then
    scale = view.target
  end
  view.scale = scale
  if anchor then
    view.x = anchor.px - anchor.mapX * view.width * scale
    view.y = anchor.py - anchor.mapY * view.height * scale
  end
  clampView()
  dirty = true
end

---------------------------------------------------------------------------------------------------
-- The art

local function textureAt(parent, list, index, layer, level)
  local texture = list[index]
  if not texture then
    texture = parent:CreateTexture(nil, layer, nil, level)
    list[index] = texture
  end
  return texture
end

-- The layers of the art of a map that can be drawn, in the order of the game.
local function artLayers(mapID)
  local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
  local usable = {}
  if ok and type(layers) == "table" then
    for index, info in ipairs(layers) do
      if type(info) == "table" and ns.Usable(info.layerWidth) and ns.Usable(info.layerHeight) and ns.Usable(info.tileWidth)
        and ns.Usable(info.tileHeight) and info.layerWidth > 0 and info.layerHeight > 0 and info.tileWidth > 0 and info.tileHeight > 0 then
        local okFiles, files = pcall(C_Map.GetMapArtLayerTextures, mapID, index)
        if okFiles and type(files) == "table" and #files > 0 then
          usable[#usable + 1] = { info = info, files = files }
        end
      end
    end
  end
  return usable
end

-- How many times closer than the whole map each layer starts. The game gives a least scale for
-- each layer. Where those numbers go up from layer to layer they are used, as parts of the
-- first; else each finer layer starts LAYER_STEP closer than the one before.
local function layerStarts(layers)
  local starts, fromGame = { 1 }, true
  local first = layers[1].info.minScale
  for index = 2, #layers do
    local least, before = layers[index].info.minScale, layers[index - 1].info.minScale
    if not (ns.Usable(first) and first > 0 and ns.Usable(least) and ns.Usable(before) and least > before) then
      fromGame = false
    end
  end
  for index = 2, #layers do
    starts[index] = fromGame and layers[index].info.minScale / first or LAYER_STEP ^ (index - 1)
  end
  return starts
end

-- Puts every image of every layer of the map on the canvas. Returns the number of images, or
-- nil if the game has no art for the map.
local function loadArt(mapID)
  local layers = artLayers(mapID)
  if #layers == 0 then
    return nil
  end
  local first = layers[1].info
  view.width, view.height = first.layerWidth, first.layerHeight
  canvas:SetSize(view.width, view.height)
  local starts = layerStarts(layers)
  view.layers = {}
  local images = 0
  for index, layer in ipairs(layers) do
    local info = layer.info
    local entry = layerFrames[index]
    if not entry then
      entry = { frame = CreateFrame("Frame", nil, canvas), tiles = {} }
      entry.frame:SetPoint("TOPLEFT")
      entry.frame:SetFrameLevel(canvas:GetFrameLevel() + index)
      layerFrames[index] = entry
    end
    -- A layer with more pixels than the first is made smaller, so it covers the same map.
    local ratio = info.layerWidth / first.layerWidth
    entry.frame:SetScale(1 / ratio)
    entry.frame:SetSize(info.layerWidth, info.layerHeight)
    entry.frame:Show()
    local columns = math.ceil(info.layerWidth / info.tileWidth)
    for tileIndex, file in ipairs(layer.files) do
      local tile = textureAt(entry.frame, entry.tiles, tileIndex, "BACKGROUND", 0)
      local column, row = (tileIndex - 1) % columns, math.floor((tileIndex - 1) / columns)
      tile:ClearAllPoints()
      tile:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", column * info.tileWidth, -row * info.tileHeight)
      tile:SetSize(info.tileWidth, info.tileHeight)
      tile:SetTexCoord(0, 1, 0, 1)
      -- TRILINEAR: the smoothest picture between the zoom steps.
      tile:SetTexture(file, nil, nil, "TRILINEAR")
      tile:Show()
    end
    for tileIndex = #layer.files + 1, #entry.tiles do
      entry.tiles[tileIndex]:Hide()
    end
    images = images + #layer.files
    view.layers[index] = { start = starts[index], ratio = ratio, frame = entry.frame, images = #layer.files }
  end
  for index = #layers + 1, #layerFrames do
    layerFrames[index].frame:Hide()
  end
  local tileWidth, tileHeight = first.tileWidth, first.tileHeight
  if not exploredFrame then
    exploredFrame = CreateFrame("Frame", nil, canvas)
    exploredFrame:SetAllPoints(canvas)
  end
  -- Over every layer of the art.
  exploredFrame:SetFrameLevel(canvas:GetFrameLevel() + #layers + 1)
  -- The parts of the map that the character has uncovered are images over the base picture.
  -- The sizes are those of Blizzard_SharedMapDataProviders/MapExplorationDataProvider.lua.
  local used = 0
  local okExplored, explored = pcall(C_MapExplorationInfo.GetExploredMapTextures, mapID)
  if okExplored and type(explored) == "table" then
    for _, part in ipairs(explored) do
      if type(part) == "table" and not part.isShownByMouseOver and type(part.fileDataIDs) == "table"
        and ns.Usable(part.textureWidth) and ns.Usable(part.textureHeight) and ns.Usable(part.offsetX) and ns.Usable(part.offsetY) then
        local wide, tall = math.ceil(part.textureWidth / tileWidth), math.ceil(part.textureHeight / tileHeight)
        for row = 1, tall do
          local pixelHeight, fileHeight = tileHeight, tileHeight
          if row == tall then
            pixelHeight = part.textureHeight % tileHeight
            if pixelHeight == 0 then
              pixelHeight = tileHeight
            end
            fileHeight = 16
            while fileHeight < pixelHeight do
              fileHeight = fileHeight * 2
            end
          end
          for column = 1, wide do
            local pixelWidth, fileWidth = tileWidth, tileWidth
            if column == wide then
              pixelWidth = part.textureWidth % tileWidth
              if pixelWidth == 0 then
                pixelWidth = tileWidth
              end
              fileWidth = 16
              while fileWidth < pixelWidth do
                fileWidth = fileWidth * 2
              end
            end
            local file = part.fileDataIDs[(row - 1) * wide + column]
            if file then
              used = used + 1
              local texture = textureAt(exploredFrame, overlays, used, "BORDER", part.isDrawOnTopLayer and 1 or 0)
              texture:ClearAllPoints()
              texture:SetPoint("TOPLEFT", canvas, "TOPLEFT", part.offsetX + tileWidth * (column - 1), -(part.offsetY + tileHeight * (row - 1)))
              texture:SetSize(pixelWidth, pixelHeight)
              texture:SetTexCoord(0, pixelWidth / fileWidth, 0, pixelHeight / fileHeight)
              texture:SetTexture(file, nil, nil, "TRILINEAR")
              texture:Show()
            end
          end
        end
      end
    end
  end
  for index = used + 1, #overlays do
    overlays[index]:Hide()
  end
  return images
end

---------------------------------------------------------------------------------------------------
-- Pins

local function pinTooltip(pin)
  if pin.data and pin.data.tooltip then
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    pin.data.tooltip(GameTooltip)
    GameTooltip:Show()
  end
end

local function acquirePin()
  local pin = table.remove(pinPool)
  if not pin then
    pin = CreateFrame("Frame", nil, overlay)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin:SetScript("OnEnter", pinTooltip)
    pin:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    pin:SetScript("OnMouseUp", function(self, button)
      if self.data and self.data.click then
        self.data.click(button)
      end
    end)
  end
  return pin
end

-- The quests of the quest log with a place on this map. A click opens the quest in the quest
-- log of the game.
local function questPins(mapID, add)
  if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then
    return
  end
  local ok, quests = pcall(C_QuestLog.GetQuestsOnMap, mapID)
  if not ok or type(quests) ~= "table" then
    return
  end
  for _, quest in ipairs(quests) do
    local questID = quest.questID
    if questID and ns.Usable(quest.x) and ns.Usable(quest.y) then
      local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
      local ready = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
      add(quest.x * 100, quest.y * 100, {
        look = ready and TURN_IN_LOOK or QUEST_LOOK,
        size = 20,
        quest = questID,
        tooltip = function(tooltip)
          tooltip:AddLine(type(title) == "string" and title or "Quest", 1, 0.82, 0)
          tooltip:AddLine(ready and "Ready to turn in" or "In progress", 1, 1, 1)
          tooltip:AddLine("Click to open the quest", 0.6, 0.6, 0.6)
        end,
        click = function()
          if type(QuestMapFrame_OpenToQuestDetails) == "function" then
            ns.HideMap()
            pcall(QuestMapFrame_OpenToQuestDetails, questID)
          end
        end,
      })
    end
  end
end

local function rebuildPins()
  GameTooltip:Hide()
  for index = #pins, 1, -1 do
    local pin = pins[index]
    pin:Hide()
    pin.data = nil
    pinPool[#pinPool + 1] = pin
    pins[index] = nil
  end
  local mapID = view.mapID
  if not mapID then
    return
  end
  local function add(x, y, data)
    if not ns.Usable(x) or not ns.Usable(y) or x < 0 or x > 100 or y < 0 or y > 100 then
      return
    end
    local pin = acquirePin()
    pin.x, pin.y, pin.data = x / 100, y / 100, data
    pin:SetSize(data.size or 16, data.size or 16)
    ns.SetIcon(pin.icon, data.look)
    -- A pin with a tooltip or a click takes the pointer; the others let it through to the map.
    pin:EnableMouse(data.click ~= nil or data.tooltip ~= nil)
    pin:Show()
    pins[#pins + 1] = pin
  end
  local providers = { questPins }
  for _, provider in ipairs(ns.PinProviders()) do
    providers[#providers + 1] = provider
  end
  for _, provider in ipairs(providers) do
    local ok, err = pcall(provider, mapID, add)
    if not ok then
      geterrorhandler()(err)
    end
  end
  dirty = true
end

-- Puts the canvas and the pins where the view says.
local function place()
  dirty = false
  canvas:SetScale(view.scale)
  canvas:ClearAllPoints()
  canvas:SetPoint("TOPLEFT", viewport, "TOPLEFT", view.x / view.scale, -view.y / view.scale)
  for index, layer in ipairs(view.layers) do
    layer.frame:SetAlpha(layerAlpha(index))
  end
  local mapWidth, mapHeight = view.width * view.scale, view.height * view.scale
  for _, pin in ipairs(pins) do
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", viewport, "TOPLEFT", view.x + pin.x * mapWidth, -(view.y + pin.y * mapHeight))
  end
end

local function placeArrow()
  local x, y = ns.PlayerPosition(view.mapID)
  if not x then
    arrow:Hide()
    return nil
  end
  local facing = GetPlayerFacing and GetPlayerFacing()
  arrow:ClearAllPoints()
  arrow:SetPoint("CENTER", viewport, "TOPLEFT", view.x + x / 100 * view.width * view.scale, -(view.y + y / 100 * view.height * view.scale))
  if ns.Usable(facing) then
    arrow:SetRotation(facing)
  end
  arrow:Show()
  return x, y
end

---------------------------------------------------------------------------------------------------
-- Maps

local function parentOf(mapID)
  local ok, info = pcall(C_Map.GetMapInfo, mapID)
  local parent = ok and info and info.parentMapID
  return ns.Usable(parent) and parent > 0 and parent or nil
end

-- Shows a map. Returns false if the game has no art for it: the map of before stays.
local function setMap(mapID)
  if not mapID then
    return false
  end
  if mapID ~= view.mapID then
    local images = loadArt(mapID)
    if not images then
      return false -- loadArt changes nothing for a map without art
    end
    view.mapID = mapID
    fit()
  end
  window.title:SetText(ns.MapName(mapID))
  window.up:SetEnabled(parentOf(mapID) ~= nil)
  rebuildPins()
  return true
end

-- The map of the place under a point of the shown map, if that is another map.
local function mapAt(mapX, mapY)
  if mapX < 0 or mapX > 1 or mapY < 0 or mapY > 1 or not C_Map.GetMapInfoAtPosition then
    return nil
  end
  local ok, info = pcall(C_Map.GetMapInfoAtPosition, view.mapID, mapX, mapY)
  if ok and type(info) == "table" and info.mapID and info.mapID ~= view.mapID then
    return info.mapID, info.name
  end
  return nil
end

-- A click on the map at a point of the viewport.
local function click(button, px, py)
  local mapX, mapY = toMap(px, py)
  if button == "RightButton" then
    local parent = parentOf(view.mapID)
    return parent ~= nil and setMap(parent)
  end
  if button ~= "LeftButton" then
    return false
  end
  if IsAltKeyDown and IsAltKeyDown() then
    if mapX >= 0 and mapX <= 1 and mapY >= 0 and mapY <= 1 and ns.EditNote then
      return ns.EditNote(view.mapID, mapX * 100, mapY * 100)
    end
    return false
  end
  local child = mapAt(mapX, mapY)
  return child ~= nil and setMap(child)
end

---------------------------------------------------------------------------------------------------
-- The window

local function updateInfo()
  local playerX, playerY = placeArrow()
  local text = playerX and string.format("You: %.1f, %.1f", playerX, playerY) or "You are not on this map"
  local px, py = pointer()
  local zone
  if px then
    local mapX, mapY = toMap(px, py)
    if mapX >= 0 and mapX <= 1 and mapY >= 0 and mapY <= 1 then
      text = text .. string.format("     Pointer: %.1f, %.1f", mapX * 100, mapY * 100)
      local _, name = mapAt(mapX, mapY)
      zone = name
    end
  end
  window.info:SetText(text)
  window.zone:SetText(type(zone) == "string" and zone or "")
end

local function onUpdate(_, elapsed)
  if drag then
    local px, py = pointer()
    if px then
      local dx, dy = px - drag.px, py - drag.py
      if not drag.moved and math.abs(dx) + math.abs(dy) > DRAG_SLOP then
        drag.moved = true
      end
      if drag.moved then
        view.x, view.y = drag.x + dx, drag.y + dy
        view.target, anchor = view.scale, nil -- a move ends a zoom that is on its way
        clampView()
        dirty = true
      end
    end
  end
  stepZoom(elapsed)
  if dirty then
    place()
    placeArrow()
  end
  sinceInfo = sinceInfo + elapsed
  if sinceInfo >= INFO_INTERVAL then
    sinceInfo = 0
    updateInfo()
  end
end

local function smallButton(text, width, tip, onClick)
  local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  button:SetSize(width, 22)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(text, 1, 1, 1)
    GameTooltip:AddLine(tip, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  return button
end

local function create()
  window = CreateFrame("Frame", "ForeverAtlasMap", UIParent)
  window:SetFrameStrata("HIGH")
  window:SetSize(math.max(640, UIParent:GetWidth() * 0.72), math.max(480, UIParent:GetHeight() * 0.8))
  window:SetPoint("CENTER")
  window:SetMovable(true)
  window:SetClampedToScreen(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  window:Hide()
  tinsert(UISpecialFrames, "ForeverAtlasMap") -- Escape closes the map

  local back = window:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  back:SetColorTexture(0.03, 0.03, 0.04, 0.96)

  window.title = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  window.title:SetPoint("TOP", 0, -9)
  local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    window:Hide()
  end)

  window.up = smallButton("Zoom out", 80, "Goes out to the map above this one. A right-click on the map does the same.", function()
    local parent = parentOf(view.mapID)
    if parent then
      setMap(parent)
    end
  end)
  window.up:SetPoint("TOPLEFT", 10, -6)
  local here = smallButton("My place", 80, "Shows the map of the place where you are.", function()
    ns.ShowMap()
  end)
  here:SetPoint("LEFT", window.up, "RIGHT", 4, 0)
  local game = smallButton("Game map", 90, "Opens the map of the game, which has the quest log.", function()
    local mapID = view.mapID
    window:Hide()
    if C_Map.OpenWorldMap then
      pcall(C_Map.OpenWorldMap, mapID)
    end
  end)
  game:SetPoint("LEFT", here, "RIGHT", 4, 0)

  viewport = CreateFrame("Frame", nil, window)
  viewport:SetPoint("TOPLEFT", 8, -34)
  viewport:SetPoint("BOTTOMRIGHT", -8, 26)
  viewport:SetClipsChildren(true)
  viewport:EnableMouse(true)
  viewport:EnableMouseWheel(true)
  canvas = CreateFrame("Frame", nil, viewport)
  canvas:SetSize(1, 1)
  canvas:SetPoint("TOPLEFT")
  -- The pins and the arrow are over the canvas and do not scale with it.
  overlay = CreateFrame("Frame", nil, viewport)
  overlay:SetAllPoints()
  overlay:SetFrameLevel(canvas:GetFrameLevel() + 20)
  arrow = overlay:CreateTexture(nil, "OVERLAY")
  arrow:SetSize(28, 28)
  arrow:SetTexture(ARROW)
  arrow:Hide()

  window.zone = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  window.zone:SetPoint("TOP", viewport, "TOP", 0, -8)
  window.info = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  window.info:SetPoint("BOTTOMLEFT", 10, 8)
  local hint = window:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMRIGHT", -10, 8)
  hint:SetText("Wheel: zoom    Drag: move    Click: open a zone    Right-click: zoom out    Alt-click: note")

  viewport:SetScript("OnMouseWheel", function(_, delta)
    local px, py = pointer()
    zoomAt(delta, px, py)
  end)
  viewport:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
      local px, py = pointer()
      if px then
        drag = { px = px, py = py, x = view.x, y = view.y, moved = false }
      end
    end
  end)
  viewport:SetScript("OnMouseUp", function(_, button)
    local held = drag
    drag = nil
    if button == "LeftButton" and held and held.moved then
      return -- the end of a move, not a click
    end
    local px, py = pointer()
    if px then
      click(button, px, py)
    end
  end)
  viewport:SetScript("OnSizeChanged", function()
    if view.mapID then
      limits()
      view.target = math.min(view.maxScale, math.max(view.minScale, view.target))
      view.scale = math.min(view.maxScale, math.max(view.minScale, view.scale))
      clampView()
      dirty = true
    end
  end)
  window:SetScript("OnUpdate", onUpdate)
  window:SetScript("OnShow", function()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN then
      PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)
    end
  end)
  window:SetScript("OnHide", function()
    drag = nil
  end)
end

---------------------------------------------------------------------------------------------------
-- For the rest of the addon

-- Shows the map of a place, or of the place of the player. Returns false if the window could
-- not be made or the game has no art for the map.
function ns.ShowMap(mapID)
  if not window then
    if not pcall(create) then
      window = nil
      return false
    end
  end
  mapID = mapID or C_Map.GetBestMapForUnit("player")
  -- A place without a map of its own (a cave) shows the map above it.
  local shown = false
  for _ = 1, 6 do
    if not mapID then
      break
    end
    if setMap(mapID) then
      shown = true
      break
    end
    mapID = parentOf(mapID)
  end
  if not shown and not view.mapID then
    return false
  end
  window:Show()
  place()
  updateInfo()
  return true
end

function ns.HideMap()
  if window and window:IsShown() then
    window:Hide()
    return true
  end
  return false
end

function ns.ToggleMap()
  if ns.HideMap() then
    return true
  end
  return ns.ShowMap()
end

-- The view of the map now: mapID, scale, the least and the greatest scale, and the place of the
-- map in the window. For the commands and the tests.
function ns.MapView()
  return view
end

-- Zooms by notches of the wheel toward a point of the map (0 to 1; the middle if left out), and
-- goes to the goal at once. Returns the new scale.
function ns.ZoomMap(notches, mapX, mapY)
  if not view.mapID then
    return nil
  end
  local px, py
  if mapX and mapY then
    px, py = view.x + mapX * view.width * view.scale, view.y + mapY * view.height * view.scale
  end
  zoomAt(notches, px, py)
  stepZoom(nil)
  place()
  return view.scale
end

-- A click on a point of the map (0 to 1). Returns true if the click did something.
function ns.ClickMap(button, mapX, mapY)
  if not view.mapID then
    return false
  end
  return click(button, view.x + mapX * view.width * view.scale, view.y + mapY * view.height * view.scale) and true or false
end

-- Prints the layers of the art that the game has for the map of the player: what the map can
-- show, and how fine. For /fatlas layers.
function ns.PrintMapLayers()
  local mapID = C_Map.GetBestMapForUnit("player")
  local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
  if not mapID or not ok or type(layers) ~= "table" or #layers == 0 then
    ns.Print("the game has no map art for this place.")
    return 0
  end
  ns.Print(string.format("%s (map %d) has %d %s of art:", ns.MapName(mapID), mapID, #layers, #layers == 1 and "layer" or "layers"))
  for index, info in ipairs(layers) do
    local okFiles, files = pcall(C_Map.GetMapArtLayerTextures, mapID, index)
    print(string.format("  %d: %s by %s pixels, tiles of %s, %d images, scale %s to %s, %s more zoom steps", index,
      tostring(info.layerWidth), tostring(info.layerHeight), tostring(info.tileWidth), okFiles and type(files) == "table" and #files or 0,
      tostring(info.minScale), tostring(info.maxScale), tostring(info.additionalZoomSteps)))
  end
  return #layers
end

-- How much of each layer of the art shows now: { opacity of layer 1, of layer 2, ... }.
function ns.MapLayers()
  local list = {}
  for index in ipairs(view.layers) do
    list[index] = layerAlpha(index)
  end
  return list
end

-- The pins of the map now: { { x, y, data }, ... } with x, y from 0 to 1.
function ns.MapPins()
  local list = {}
  for index, pin in ipairs(pins) do
    list[index] = { x = pin.x, y = pin.y, data = pin.data, frame = pin }
  end
  return list
end

-- The pins changed (a note, a waypoint, a visited area).
function ns.RefreshMapPins()
  if window and window:IsShown() then
    rebuildPins()
  end
end

---------------------------------------------------------------------------------------------------
-- The key of the world map

local keyButton = CreateFrame("Button", "ForeverAtlasMapKey", UIParent)
keyButton:SetScript("OnClick", function()
  ns.ToggleMap()
end)
local bound = {}
local wanted = false

-- Gives the keys of the game's world map to this map, or gives them back.
local function bindKeys()
  if InCombatLockdown and InCombatLockdown() then
    wanted = true -- the game refuses a change of bindings in a fight: after it
    return false
  end
  wanted = false
  ClearOverrideBindings(keyButton)
  bound = {}
  if ns.GetOption("mapKey") then
    for _, key in ipairs({ GetBindingKey("TOGGLEWORLDMAP") }) do
      if type(key) == "string" then
        SetOverrideBindingClick(keyButton, true, key, "ForeverAtlasMapKey")
        bound[#bound + 1] = key
      end
    end
  end
  return true
end

-- The keys that open this map now.
function ns.MapKeys()
  return bound
end

ns.OnOption(function(key)
  if key == "mapKey" then
    bindKeys()
  elseif key == "notes" or key == "pins" then
    ns.RefreshMapPins()
  end
end)

ns.OnLogin(function()
  bindKeys()
  local events = CreateFrame("Frame")
  for _, event in ipairs({ "UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED", "QUEST_LOG_UPDATE", "ZONE_CHANGED_NEW_AREA" }) do
    pcall(events.RegisterEvent, events, event)
  end
  events:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_BINDINGS" or (event == "PLAYER_REGEN_ENABLED" and wanted) then
      bindKeys()
    elseif event == "QUEST_LOG_UPDATE" then
      ns.RefreshMapPins()
    end
  end)
end)
