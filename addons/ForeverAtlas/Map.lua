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

-- The terrain. The painted map of a zone is one picture of about a thousand pixels, so a close
-- look is blurred. The game also has the picture that the minimap shows: the terrain itself,
-- seen from above, as one image of 256 pixels for each square of 533 yards of the world. With
-- the option terrain, the map lays those images over the painted map when the player zooms in.
-- The game gives an addon no list of these images: their file names are made here, from the
-- place of the zone in the world. On a client that does not have the files under these names
-- the images do not show, so the option is off at first.
local TERRAIN_YARDS = 1600 / 3 -- the side of the square of one terrain image
local TERRAIN_IMAGE = 256 -- its pixels
local TERRAIN_PIXELS = 1.5 -- at the closest zoom, screen units for one pixel of a terrain image
local TERRAIN_START = 2 -- how many times closer than the whole map the terrain starts to show
local TERRAIN_FADE = 0.5 -- it is in full at TERRAIN_START * (1 + TERRAIN_FADE)
local TERRAIN_MOST = 1500 -- no terrain for a map that needs more images than this
-- The folder of the terrain images of each world, by the number of the world.
local TERRAIN_FOLDERS = { [0] = "Azeroth", [1] = "Kalimdor", [530] = "Expansion01", [571] = "Northrend" }

local REFRESH_SECONDS = 2 -- the pins are read again this often: group members move
local HOVER_REACH = 4 -- a pin shows its tooltip this far outside its picture

local window, viewport, canvas, overlay, arrow
local layerFrames = {} -- [index] = { frame = , tiles = {} }, one for each layer of the art
local exploredFrame
local terrainFrame
local terrainTiles = {}
local overlays = {}
local pins, pinPool = {}, {}
local hovered -- the pin whose tooltip shows
local labels, labelPool = {}, {} -- the names of the zones of a continent
local highlight, highlightKey -- the zone under the pointer, lit up
local sinceRefresh = 0

-- The map on the screen. width and height are of the canvas, in the pixels of the art.
-- scale: screen units for one pixel of the art. x, y: where the top left corner of the canvas
-- is in the viewport, to the right and down.
-- layers: for each layer of the art, `start`: how many times closer than the whole map the
-- layer is fully shown (1 for the first), and `ratio`: its pixels for one pixel of the first.
local view = { mapID = nil, width = 1, height = 1, scale = 1, target = 1, x = 0, y = 0, minScale = 1, maxScale = 1, layers = {} }
-- An error inside the map must not leave an empty window without a word. Each different error
-- is printed in the chat once, and goes to the error handler of the game.
local reported = {}
local function report(where, err)
  local text = where .. ": " .. tostring(err)
  if not reported[text] then
    reported[text] = true
    ns.Print("map error in " .. text)
  end
  geterrorhandler()(err)
end

local anchor -- the point of the map that stays under the pointer during a zoom
local drag
local dirty = true -- the canvas or the pins must be placed again
local sinceInfo = 0

---------------------------------------------------------------------------------------------------
-- Geometry

-- The part of the window for the map. The game works out the size of a frame that hangs on two
-- corners only when it draws it, so right after the window is made this size is not there yet.
-- Then the size comes from the window, which has a size of its own: a map fitted to a size of
-- nothing would be one point in a corner, with every pin on it.
local VIEWPORT_LESS_WIDE, VIEWPORT_LESS_HIGH = 16, 60 -- the edges of the window around the map

local function viewportSize()
  local width, height = viewport:GetWidth(), viewport:GetHeight()
  if ns.Usable(width) and width > 1 and ns.Usable(height) and height > 1 then
    return width, height
  end
  width, height = window:GetWidth(), window:GetHeight()
  if ns.Usable(width) and width > VIEWPORT_LESS_WIDE + 1 and ns.Usable(height) and height > VIEWPORT_LESS_HIGH + 1 then
    return width - VIEWPORT_LESS_WIDE, height - VIEWPORT_LESS_HIGH
  end
  return 1, 1
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
  -- With the terrain: far enough in for the pixels of a terrain image.
  if view.terrain then
    view.maxScale = math.max(view.maxScale, TERRAIN_PIXELS * TERRAIN_IMAGE / (view.terrain.tileWidth * view.width), view.minScale * TERRAIN_START * 3)
  end
end

-- The opacity of the terrain for the zoom now: it fades in from TERRAIN_START times closer than
-- the whole map.
local function terrainAlpha()
  if not view.terrain then
    return 0
  end
  local closer = view.scale / view.minScale
  return math.min(1, math.max(0, (closer - TERRAIN_START) / (TERRAIN_START * TERRAIN_FADE)))
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

-- The terrain images of a map: puts them on the canvas, under the name of each one, and
-- returns { tileWidth, columns, rows, folder, first } or nil. tileWidth is the width of one
-- image as a part of the map.
local function loadTerrain(mapID)
  if terrainFrame then
    terrainFrame:Hide()
  end
  if not (ns.GetOption("terrain") and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
    return nil
  end
  -- The world place of the top left and of the bottom right corner of the map. The game gives a
  -- place as north and west, in yards.
  local okA, world, cornerA = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
  local okB, _, cornerB = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
  local folder = okA and TERRAIN_FOLDERS[world]
  if not (folder and okB and type(cornerA) == "table" and type(cornerB) == "table") then
    return nil
  end
  local northA, westA = cornerA:GetXY()
  local northB, westB = cornerB:GetXY()
  if not (ns.Usable(northA) and ns.Usable(westA) and ns.Usable(northB) and ns.Usable(westB)) or northA == northB or westA == westB then
    return nil
  end
  -- The number of an image: 32 minus the place in squares. The first number of the file name
  -- is for west, the second for north.
  -- A map that ends exactly on the edge of a square does not need the square past that edge.
  local function squares(a, b)
    return math.floor(32 - math.max(a, b) / TERRAIN_YARDS), math.ceil(32 - math.min(a, b) / TERRAIN_YARDS) - 1
  end
  local columnFirst, columnLast = squares(westA, westB)
  local rowFirst, rowLast = squares(northA, northB)
  local columns, rows = columnLast - columnFirst + 1, rowLast - rowFirst + 1
  if columns < 1 or rows < 1 or columns * rows > TERRAIN_MOST then
    return nil
  end
  if not terrainFrame then
    terrainFrame = CreateFrame("Frame", nil, canvas)
    terrainFrame:SetAllPoints(canvas)
    terrainFrame:SetClipsChildren(true) -- an image at the edge reaches past the map
  end
  terrainFrame:SetFrameLevel(canvas:GetFrameLevel() + 12)
  -- Where a world place is on the map, from 0 to 1.
  local function across(west)
    return (west - westA) / (westB - westA)
  end
  local function down(north)
    return (north - northA) / (northB - northA)
  end
  local used = 0
  for row = rowFirst, rowLast do
    for column = columnFirst, columnLast do
      -- The image covers the square from (32 - number) down to (31 - number), in squares.
      local left, right = across((32 - column) * TERRAIN_YARDS), across((31 - column) * TERRAIN_YARDS)
      local top, bottom = down((32 - row) * TERRAIN_YARDS), down((31 - row) * TERRAIN_YARDS)
      used = used + 1
      local tile = textureAt(terrainFrame, terrainTiles, used, "ARTWORK", 0)
      tile:ClearAllPoints()
      tile:SetPoint("TOPLEFT", terrainFrame, "TOPLEFT", math.min(left, right) * view.width, -math.min(top, bottom) * view.height)
      tile:SetSize(math.abs(right - left) * view.width, math.abs(bottom - top) * view.height)
      tile:SetTexCoord(0, 1, 0, 1)
      tile.file = string.format("World\\Minimaps\\%s\\map%d_%d", folder, column, row)
      tile:SetTexture(tile.file, nil, nil, "TRILINEAR")
      tile:Show()
    end
  end
  for index = used + 1, #terrainTiles do
    terrainTiles[index]:Hide()
  end
  terrainFrame:Show()
  return {
    tileWidth = TERRAIN_YARDS / math.abs(westA - westB), columns = columns, rows = rows, folder = folder,
    first = terrainTiles[1].file, images = used,
  }
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
  -- The terrain is a trial: if it fails, the map still shows.
  local okTerrain, terrain = pcall(loadTerrain, mapID)
  view.terrain = okTerrain and terrain or nil
  if not okTerrain then
    report("the terrain", terrain)
    if terrainFrame then
      terrainFrame:Hide()
    end
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
    -- A pin with a click takes the pointer, so its tooltip comes from these scripts.
    pin:SetScript("OnEnter", function(self)
      hovered = self
      pinTooltip(self)
    end)
    pin:SetScript("OnLeave", function(self)
      if hovered == self then
        hovered = nil
      end
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

-- The names of the zones of a map of a continent, each in the middle of its zone.
local function rebuildLabels()
  for index = #labels, 1, -1 do
    labels[index]:Hide()
    labelPool[#labelPool + 1] = labels[index]
    labels[index] = nil
  end
  local mapID = view.mapID
  if not (mapID and ns.GetOption("zoneNames") and C_Map.GetMapChildrenInfo and C_Map.GetMapRectOnMap and Enum and Enum.UIMapType) then
    return
  end
  local ok, children = pcall(C_Map.GetMapChildrenInfo, mapID, Enum.UIMapType.Zone)
  if not ok or type(children) ~= "table" then
    return
  end
  for _, child in ipairs(children) do
    if type(child) == "table" and child.mapID and type(child.name) == "string" then
      local found, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, child.mapID, mapID)
      if found and ns.Usable(left) and ns.Usable(right) and ns.Usable(top) and ns.Usable(bottom) and right > left and bottom > top then
        local label = table.remove(labelPool)
        if not label then
          label = overlay:CreateFontString(nil, "ARTWORK", "GameFontNormal")
          label:SetTextColor(1, 0.95, 0.75)
        end
        label.x, label.y = (left + right) / 2, (top + bottom) / 2
        label:SetText(child.name)
        label:Show()
        labels[#labels + 1] = label
      end
    end
  end
end

local function rebuildPins()
  if hovered then
    GameTooltip:Hide()
    hovered = nil
  end
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
  local kind -- the kind of the provider that runs now
  local function add(x, y, data)
    if not ns.Usable(x) or not ns.Usable(y) or x < 0 or x > 100 or y < 0 or y > 100 then
      return
    end
    local pin = acquirePin()
    pin.x, pin.y, pin.data, pin.kind = x / 100, y / 100, data, kind
    pin:SetSize(data.size or 16, data.size or 16)
    ns.SetIcon(pin.icon, data.look)
    -- Only a pin with a click takes the pointer. The others let a click, a drag and the wheel
    -- through to the map; their tooltip comes from the place of the pointer (updateHover).
    pin:EnableMouse(data.click ~= nil)
    pin:Show()
    pins[#pins + 1] = pin
  end
  -- The kinds of the map that are on, then the pins of the addon (notes, waypoints, visited areas).
  for _, entry in ipairs(ns.MAP_KINDS) do
    if ns.GetOption(ns.MapKindOption(entry.key)) then
      kind = entry.key
      local ok, err = pcall(entry.find, mapID, add)
      if not ok then
        report("the pins of " .. entry.name, err)
      end
    end
  end
  kind = "atlas"
  for _, provider in ipairs(ns.PinProviders()) do
    local ok, err = pcall(provider, mapID, add)
    if not ok then
      report("the pins of the addon", err)
    end
  end
  rebuildLabels()
  dirty = true
end

-- The tooltip of the pin under a place of the viewport: the last one drawn there, which is the
-- one on top.
local function updateHover(px, py)
  local found
  if px then
    local mapWidth, mapHeight = view.width * view.scale, view.height * view.scale
    for index = #pins, 1, -1 do
      local pin = pins[index]
      if pin.data and pin.data.tooltip then
        local reach = (pin.data.size or 16) / 2 + HOVER_REACH
        if math.abs(view.x + pin.x * mapWidth - px) <= reach and math.abs(view.y + pin.y * mapHeight - py) <= reach then
          found = pin
          break
        end
      end
    end
  end
  if found == hovered then
    return
  end
  hovered = found
  if found then
    pinTooltip(found)
  else
    GameTooltip:Hide()
  end
end

-- Lights up the zone under a point of the map, as the map of the game does
-- (Blizzard_SharedMapDataProviders/MapHighlightDataProvider.lua).
local function updateHighlight(mapX, mapY)
  local file, atlas, partX, partY, sizeX, sizeY, atX, atY
  -- Only a zone that the player can open from here lights up: a map of another place under
  -- the pointer. On the map of a zone itself the game names the whole zone, which would put a
  -- bright colour over all of the map.
  local other = false
  if mapX and C_Map.GetMapInfoAtPosition then
    local okInfo, info = pcall(C_Map.GetMapInfoAtPosition, view.mapID, mapX, mapY)
    other = okInfo and type(info) == "table" and info.mapID ~= nil and info.mapID ~= view.mapID
  end
  if mapX and other and ns.GetOption("zoneHighlight") and C_Map.GetMapHighlightInfoAtPosition then
    local ok
    ok, file, atlas, partX, partY, sizeX, sizeY, atX, atY = pcall(C_Map.GetMapHighlightInfoAtPosition, view.mapID, mapX, mapY)
    if not ok or not (ns.Usable(partX) and ns.Usable(partY) and ns.Usable(sizeX) and ns.Usable(sizeY) and ns.Usable(atX) and ns.Usable(atY)) then
      file, atlas = nil, nil
    end
  end
  local hasAtlas = type(atlas) == "string" and atlas ~= ""
  local hasFile = ns.Usable(file) and file > 0
  if not (hasAtlas or hasFile) then
    if highlightKey then
      highlightKey = nil
      highlight:Hide()
    end
    return
  end
  local key = tostring(hasAtlas and atlas or file) .. ":" .. atX .. ":" .. atY
  if key == highlightKey then
    return
  end
  highlightKey = key
  highlight:ClearAllPoints()
  highlight:SetTexCoord(0, partX, 0, partY)
  if hasAtlas then
    highlight:SetAtlas(atlas, true)
    highlight:SetPoint("CENTER", canvas, "CENTER", ((atX + 0.5 * sizeX) - 0.5) * view.width, -((atY + 0.5 * sizeY) - 0.5) * view.height)
  else
    highlight:SetTexture(file, nil, nil, "TRILINEAR")
    highlight:SetSize(sizeX * view.width, sizeY * view.height)
    highlight:SetPoint("TOPLEFT", canvas, "TOPLEFT", atX * view.width, -atY * view.height)
  end
  highlight:Show()
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
  if terrainFrame and view.terrain then
    terrainFrame:SetAlpha(terrainAlpha())
  end
  local mapWidth, mapHeight = view.width * view.scale, view.height * view.scale
  for _, pin in ipairs(pins) do
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", viewport, "TOPLEFT", view.x + pin.x * mapWidth, -(view.y + pin.y * mapHeight))
  end
  for _, label in ipairs(labels) do
    label:ClearAllPoints()
    label:SetPoint("CENTER", viewport, "TOPLEFT", view.x + label.x * mapWidth, -(view.y + label.y * mapHeight))
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
  local zone, overX, overY
  if px then
    local mapX, mapY = toMap(px, py)
    if mapX >= 0 and mapX <= 1 and mapY >= 0 and mapY <= 1 then
      text = text .. string.format("     Pointer: %.1f, %.1f", mapX * 100, mapY * 100)
      local _, name = mapAt(mapX, mapY)
      zone = name
      overX, overY = mapX, mapY
    end
  end
  -- A pin with a click shows its own tooltip while the pointer is on it.
  if not (hovered and hovered.data and hovered.data.click) then
    updateHover(overX and px or nil, py)
  end
  updateHighlight(overX, overY)
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
  -- Not while the player moves or zooms the map: that must stay smooth.
  sinceRefresh = sinceRefresh + elapsed
  if sinceRefresh >= REFRESH_SECONDS and not drag and view.scale == view.target then
    sinceRefresh = 0
    rebuildPins()
  end
end

-- The menu of the button "Show": a checkbox for each kind of thing on the map.
local function showMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    ns.OpenSettings()
    return
  end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Show on the map")
    local function check(label, key)
      root:CreateCheckbox(label, function()
        return ns.GetOption(key)
      end, function()
        ns.SetOption(key, not ns.GetOption(key))
      end)
    end
    for _, kind in ipairs(ns.MAP_KINDS) do
      check(kind.name, ns.MapKindOption(kind.key))
    end
    check("Your notes", "notes")
    check("Visited areas", "pins")
    check("Names of the zones", "zoneNames")
    check("Light up the zone under the pointer", "zoneHighlight")
    check("Terrain when zoomed in (a trial)", "terrain")
  end)
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
  window.show = smallButton("Show", 70, "Chooses what the map shows: quests, flight masters, towns, rare enemies and more.", function(self)
    showMenu(self)
  end)
  window.show:SetPoint("LEFT", game, "RIGHT", 4, 0)

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
  -- The zone under the pointer, over the art and under the pins.
  local highlightFrame = CreateFrame("Frame", nil, canvas)
  highlightFrame:SetAllPoints(canvas)
  highlightFrame:SetFrameLevel(canvas:GetFrameLevel() + 15)
  highlight = highlightFrame:CreateTexture(nil, "ARTWORK")
  highlight:SetBlendMode("ADD")
  highlight:Hide()
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
      local whole = view.scale == view.minScale and view.target == view.minScale
      limits()
      -- A map that showed in whole still shows in whole in the new size.
      if whole then
        view.scale, view.target = view.minScale, view.minScale
      end
      view.target = math.min(view.maxScale, math.max(view.minScale, view.target))
      view.scale = math.min(view.maxScale, math.max(view.minScale, view.scale))
      clampView()
      dirty = true
    end
  end)
  window:SetScript("OnUpdate", function(self, elapsed)
    local ok, err = pcall(onUpdate, self, elapsed)
    if not ok then
      report("the update of the map", err)
    end
  end)
  window:SetScript("OnShow", function()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN then
      PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)
    end
  end)
  window:SetScript("OnHide", function()
    drag = nil
    if hovered then
      hovered = nil
      GameTooltip:Hide()
    end
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
    local ok, done = pcall(setMap, mapID)
    if not ok then
      report("showing map " .. tostring(mapID), done)
      break
    end
    if done then
      shown = true
      break
    end
    mapID = parentOf(mapID)
  end
  if not shown and not view.mapID then
    return false
  end
  window:Show()
  local ok, err = pcall(function()
    place()
    updateInfo()
  end)
  if not ok then
    report("placing the map", err)
  end
  return true
end

-- Prints what the map shows now, for /fatlas status: enough to see from outside why a map
-- looks wrong.
function ns.PrintMapStatus()
  if not window then
    ns.Print("the map has not been opened yet.")
    return false
  end
  local width, height = viewportSize()
  local shownTiles = 0
  for _, layer in ipairs(view.layers) do
    shownTiles = shownTiles + (layer.images or 0)
  end
  ns.Print(string.format("map %s (%s), window %s", tostring(view.mapID), view.mapID and ns.MapName(view.mapID) or "none", window:IsShown() and "open" or "closed"))
  print(string.format("  art: %d by %d pixels, %d layers, %d images", view.width, view.height, #view.layers, shownTiles))
  print(string.format("  window for the map: %.0f by %.0f; scale %.4f (from %.4f to %.4f); corner at %.0f, %.0f", width, height, view.scale, view.minScale, view.maxScale, view.x, view.y))
  local kinds = {}
  for _, pin in ipairs(pins) do
    kinds[pin.kind or "?"] = (kinds[pin.kind or "?"] or 0) + 1
  end
  local parts = {}
  for kind, count in pairs(kinds) do
    parts[#parts + 1] = kind .. " " .. count
  end
  table.sort(parts)
  print(string.format("  pins: %d (%s); zone names: %d", #pins, #parts > 0 and table.concat(parts, ", ") or "none", #labels))
  local terrain = view.terrain
  print("  terrain: " .. (terrain and string.format("%d images, %d by %d, first %s, opacity %.2f", terrain.images, terrain.columns, terrain.rows, terrain.first, terrainAlpha())
    or (ns.GetOption("terrain") and "on, but none for this map" or "off")))
  local errors = 0
  for text in pairs(reported) do
    errors = errors + 1
    print("  error: " .. text)
  end
  if errors == 0 then
    print("  no error inside the map so far.")
  end
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

-- The terrain of the map now: { images, columns, rows, folder, first (the name of the first
-- image), alpha (how much of it shows) }, or nil without terrain.
function ns.MapTerrain()
  if not view.terrain then
    return nil
  end
  local terrain = view.terrain
  return { images = terrain.images, columns = terrain.columns, rows = terrain.rows, folder = terrain.folder, first = terrain.first, alpha = terrainAlpha() }
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
    list[index] = { x = pin.x, y = pin.y, data = pin.data, frame = pin, kind = pin.kind }
  end
  return list
end

-- The names of the zones on the map now: { { x, y, text }, ... } with x, y from 0 to 1.
function ns.MapLabels()
  local list = {}
  for index, label in ipairs(labels) do
    list[index] = { x = label.x, y = label.y, text = label:GetText() }
  end
  return list
end

-- Moves the pointer to a point of the map (0 to 1), for the tests: the tooltip of the pin there
-- and the zone that lights up. Returns the pin whose tooltip shows, and true if a zone is lit.
function ns.HoverMap(mapX, mapY)
  updateHover(view.x + mapX * view.width * view.scale, view.y + mapY * view.height * view.scale)
  updateHighlight(mapX, mapY)
  return hovered, highlightKey ~= nil
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
  elseif key == "notes" or key == "pins" or key == "zoneNames" or key:find("^show_") then
    ns.RefreshMapPins()
  elseif key == "terrain" then
    if window and view.mapID then
      view.terrain = loadTerrain(view.mapID)
      limits()
      view.target = math.min(view.maxScale, view.target)
      view.scale = math.min(view.maxScale, view.scale)
      dirty = true
    end
  elseif key == "zoneHighlight" and highlight then
    highlightKey = nil
    highlight:Hide()
  end
end)

ns.OnLogin(function()
  bindKeys()
  local events = CreateFrame("Frame")
  for _, event in ipairs({
    "UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED", "QUEST_LOG_UPDATE", "ZONE_CHANGED_NEW_AREA", "VIGNETTES_UPDATED",
    "AREA_POIS_UPDATED", "GROUP_ROSTER_UPDATE", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "USER_WAYPOINT_UPDATED",
    "QUESTLINE_UPDATE",
  }) do
    pcall(events.RegisterEvent, events, event)
  end
  events:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_BINDINGS" or (event == "PLAYER_REGEN_ENABLED" and wanted) then
      bindKeys()
    elseif event ~= "UPDATE_BINDINGS" and event ~= "PLAYER_REGEN_ENABLED" then
      ns.RefreshMapPins()
    end
  end)
end)
