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
-- The game gives an addon no list of these images and does not have them under their old file
-- names. TerrainData.lua has the number of the file of each square of the world (from the
-- addon OpenMap); a square without a number there is left out.
local TERRAIN_YARDS = 1600 / 3 -- the side of the square of one terrain image
local TERRAIN_IMAGE = 256 -- its pixels
local TERRAIN_PIXELS = 1.5 -- at the closest zoom, screen units for one pixel of a terrain image
local TERRAIN_START = 2 -- how many times closer than the whole map the terrain can show in full
local TERRAIN_GUARD = 1.5 -- and from where it can start to show
local TERRAIN_SHOW, TERRAIN_FULL = 280, 360 -- screen units for the square of one image: it starts to show, it shows in full
local UNEXPLORED_SHADE = 0.72 -- how bright the land is where the character has not been
local NEIGHBOURS_MOST = 12 -- zones drawn around the zone shown
local NEIGHBOURS_REACH = 1.25 -- as far as this part of the map past each edge
local TERRAIN_MOST = 1500 -- no terrain for a map that needs more images than this
local TERRAIN_PAST = 0.5 -- the terrain goes on this far past each edge of the map, as a part of the map
local CROSS_SLACK = 0.05 -- the middle of the window goes this far past the edge before the next zone is looked for
local PAINT_SHARP = 1.2 -- the painting of the continent is clear while one of its pixels is this many screen units or fewer
local PAINT_BLUR = 2.5 -- and it is gone from this many: past that it is only blocks of colour

-- The options of the map window. Opacity and scale are in percent.
ns.defaults.mapOpacity = 100
ns.defaults.mapScale = 100
ns.limits.mapOpacity = { 30, 100 }
ns.limits.mapScale = { 50, 150 }
ns.defaults.revealAll = true -- the land where the character has not been is drawn too
ns.defaults.revealBright = false -- and as bright as the land where the character has been
ns.defaults.questAreas = true -- the area of each quest objective, under the pins
local WINDOW_LEAST_WIDE, WINDOW_LEAST_HIGH = 480, 360
local QUEST_FILL, QUEST_BORDER = "Interface\\WorldMap\\UI-QuestBlob-Inside", "Interface\\WorldMap\\UI-QuestBlob-Outside"

local REFRESH_SECONDS = 2 -- the pins are read again this often: group members move
local HOVER_REACH = 4 -- a pin shows its tooltip this far outside its picture

local window, viewport, canvas, overlay, arrow
local layerFrames = {} -- [index] = { frame = , tiles = {} }, one for each layer of the art
local exploredFrame
local terrainFrame
local terrainTiles = {}
local neighbourFrame -- the zones beside the zone shown, drawn around it
local neighbourTiles, neighbourOverlays = {}, {}
local loadNeighbours
local overlays = {}
local pins, pinPool = {}, {}
local hovered -- the pin whose tooltip shows
local labels, labelPool = {}, {} -- the names of the zones of a continent
local highlight, highlightKey -- the zone under the pointer, lit up
local sinceRefresh = 0
local stale = false -- the game said that something on the map changed: the pins are read again soon
local STALE_SECONDS = 0.25 -- many events in a row make one new reading

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

local terrainAlpha

-- True where the player can move the map past the edge of the zone: the zone has a place on
-- a continent. The zones beside it are drawn around it, so there is something to see there.
local function canCross()
  return view.pan ~= nil
end

-- Keeps the map in the viewport: a map smaller than the viewport is in the middle, a larger
-- one never shows empty space beside it. Where the player can cross to the next zone, the
-- middle of the viewport stays on the map instead, or `slack` (a part of the map) past it.
local function clampView(slack)
  local width, height = viewportSize()
  local mapWidth, mapHeight = view.width * view.scale, view.height * view.scale
  if canCross() then
    slack = slack or 0
    view.x = math.min(width / 2 + slack * mapWidth, math.max(width / 2 - (1 + slack) * mapWidth, view.x))
    view.y = math.min(height / 2 + slack * mapHeight, math.max(height / 2 - (1 + slack) * mapHeight, view.y))
    return
  end
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
function terrainAlpha()
  if not view.terrain then
    return 0
  end
  -- By the size of the land on the screen, so that the terrain stays as it is from zone to
  -- zone: from TERRAIN_SHOW to TERRAIN_FULL screen units for the square of one image. Not
  -- before the map is TERRAIN_GUARD times closer than whole: a small map keeps its painting.
  local closer = view.scale / view.minScale
  local guard = (closer - TERRAIN_GUARD) / (TERRAIN_START - TERRAIN_GUARD)
  local byLand = (view.terrain.tileWidth * view.width * view.scale - TERRAIN_SHOW) / (TERRAIN_FULL - TERRAIN_SHOW)
  return math.min(1, math.max(0, math.min(guard, byLand)))
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
local goUpAt -- set below: zooms out from a zone to its continent

local function zoomAt(notches, px, py)
  local width, height = viewportSize()
  px, py = px or width / 2, py or height / 2
  limits()
  local wanted = view.target * ZOOM_STEP ^ notches
  -- Past the whole of the zone, the map goes out to the continent with the zone where it was.
  if notches < 0 and wanted < view.minScale and goUpAt and goUpAt(px, py) then
    return
  end
  view.target = math.min(view.maxScale, math.max(view.minScale, wanted))
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

-- The terrain images of a map: puts them on the canvas, by the number of each one, and
-- returns { tileWidth, columns, rows, world, first } or nil. tileWidth is the width of one
-- image as a part of the map.
local function loadTerrain(mapID)
  if terrainFrame then
    terrainFrame:Hide()
  end
  if not (ns.GetOption("terrainDetail") and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
    return nil
  end
  -- The world place of the top left and of the bottom right corner of the map. The game gives a
  -- place as north and west, in yards.
  local okA, world, cornerA = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
  local okB, _, cornerB = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
  local images = okA and ns.TERRAIN_IMAGES and ns.TERRAIN_IMAGES[world]
  if not (images and okB and type(cornerA) == "table" and type(cornerB) == "table") then
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
  local firstFile = images[columnFirst * 64 + rowFirst]
  -- The terrain goes on past the edge of the map by a part of its size, for the way to the
  -- next zone. Not for a map that would need too many images then.
  local pastWest, pastNorth = math.abs(westA - westB) * TERRAIN_PAST, math.abs(northA - northB) * TERRAIN_PAST
  local wideFirst, wideLast = squares(math.max(westA, westB) + pastWest, math.min(westA, westB) - pastWest)
  local tallFirst, tallLast = squares(math.max(northA, northB) + pastNorth, math.min(northA, northB) - pastNorth)
  if (wideLast - wideFirst + 1) * (tallLast - tallFirst + 1) <= TERRAIN_MOST then
    columnFirst, columnLast, rowFirst, rowLast = wideFirst, wideLast, tallFirst, tallLast
  end
  if not terrainFrame then
    terrainFrame = CreateFrame("Frame", nil, canvas)
    terrainFrame:SetAllPoints(canvas)
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
      -- A square without an image (open sea, land the game never drew) keeps the painted map.
      local file = images[column * 64 + row]
      if file then
        used = used + 1
        local tile = textureAt(terrainFrame, terrainTiles, used, "ARTWORK", 0)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", terrainFrame, "TOPLEFT", math.min(left, right) * view.width, -math.min(top, bottom) * view.height)
        tile:SetSize(math.abs(right - left) * view.width, math.abs(bottom - top) * view.height)
        tile:SetTexCoord(0, 1, 0, 1)
        tile.file = file
        tile:SetTexture(file, nil, nil, "TRILINEAR")
        tile:Show()
      end
    end
  end
  for index = used + 1, #terrainTiles do
    terrainTiles[index]:Hide()
  end
  if used == 0 then
    return nil
  end
  terrainFrame:Show()
  return {
    tileWidth = TERRAIN_YARDS / math.abs(westA - westB), columns = columns, rows = rows, world = world,
    -- The world places of the corners, for the way from zone to zone.
    westA = westA, westB = westB, northA = northA, northB = northB,
    first = firstFile or terrainTiles[1].file, images = used,
  }
end

-- The pictures of all the land of a map, also where the character has not been (from
-- RevealData.lua, by the art of the map): { ["width:height:x:y"] = part }, each part as the
-- game gives an uncovered one, with `unexplored`. Nil for a map without them.
local revealed = {}
local function revealFor(mapID)
  if not (ns.MAP_REVEAL and C_Map.GetMapArtID) then
    return nil
  end
  local ok, art = pcall(C_Map.GetMapArtID, mapID)
  local data = ok and ns.Usable(art) and ns.MAP_REVEAL[art]
  if not data then
    return nil
  end
  if not revealed[art] then
    local parts = {}
    for key, files in pairs(data) do
      local width, height, x, y = string.match(key, "^(%d+):(%d+):(%d+):(%d+)$")
      if width then
        local ids = {}
        for id in string.gmatch(files, "%d+") do
          ids[#ids + 1] = tonumber(id)
        end
        parts[key] = {
          textureWidth = tonumber(width), textureHeight = tonumber(height), offsetX = tonumber(x), offsetY = tonumber(y),
          fileDataIDs = ids, unexplored = true,
        }
      end
    end
    revealed[art] = parts
  end
  return revealed[art]
end

-- The parts of a map that the character has uncovered: images over the base picture, on
-- `frame`, from the texture after `used` of `list` on. The sizes are those of
-- Blizzard_SharedMapDataProviders/MapExplorationDataProvider.lua. originX, originY: where the
-- top left corner of that map is on the canvas; scaleX, scaleY: canvas units for one of its
-- pixels (0, 0, 1, 1 for the map shown). Returns the last texture used.
-- With `all`, the land where the character has not been is drawn too, a little darker, from
-- the pictures of revealFor.
local function drawExplored(mapID, frame, list, used, tileWidth, tileHeight, originX, originY, scaleX, scaleY, all)
  local parts, seen = {}, {}
  local okExplored, explored = pcall(C_MapExplorationInfo.GetExploredMapTextures, mapID)
  if okExplored and type(explored) == "table" then
    for _, part in ipairs(explored) do
      if type(part) == "table" and type(part.fileDataIDs) == "table"
        and ns.Usable(part.textureWidth) and ns.Usable(part.textureHeight) and ns.Usable(part.offsetX) and ns.Usable(part.offsetY) then
        seen[part.textureWidth .. ":" .. part.textureHeight .. ":" .. part.offsetX .. ":" .. part.offsetY] = true
        if not part.isShownByMouseOver then
          parts[#parts + 1] = part
        end
      end
    end
  end
  for key, part in pairs(all and revealFor(mapID) or {}) do
    if not seen[key] then
      parts[#parts + 1] = part
    end
  end
  for _, part in ipairs(parts) do
    do
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
            local texture = textureAt(frame, list, used, "BORDER", 0)
            -- Land where the character has not been: under the land that is uncovered, and darker.
            texture:SetDrawLayer("BORDER", part.unexplored and -1 or (part.isDrawOnTopLayer and 1 or 0))
            local shade = part.unexplored and not ns.GetOption("revealBright") and UNEXPLORED_SHADE or 1
            texture:SetVertexColor(shade, shade, shade)
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", canvas, "TOPLEFT", originX + (part.offsetX + tileWidth * (column - 1)) * scaleX,
              -(originY + (part.offsetY + tileHeight * (row - 1)) * scaleY))
            texture:SetSize(pixelWidth * scaleX, pixelHeight * scaleY)
            texture:SetTexCoord(0, pixelWidth / fileWidth, 0, pixelHeight / fileHeight)
            texture:SetTexture(file, nil, nil, "TRILINEAR")
            texture:Show()
          end
        end
      end
    end
  end
  return used
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
  view.tileWidth, view.tileHeight = tileWidth, tileHeight
  local used = drawExplored(mapID, exploredFrame, overlays, 0, tileWidth, tileHeight, 0, 0, 1, 1)
  for index = used + 1, #overlays do
    overlays[index]:Hide()
  end
  -- If the terrain fails, the map still shows.
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

-- The areas of the objectives of the quests in the log, under the pins: the shapes that the
-- game's own map draws (Blizzard_SharedMapDataProviders/QuestBlobDataProvider.lua), from a frame
-- of the game that draws them for a map. False where this client cannot make that frame.
local questBlob
local function drawQuestAreas()
  view.questAreas = 0
  if questBlob == nil then
    local ok, frame = pcall(CreateFrame, "QuestPOIFrame", nil, canvas)
    if not (ok and frame and frame.DrawBlob and frame.SetMapID and frame.DrawNone) then
      questBlob = false
      return
    end
    questBlob = frame
    frame:SetAllPoints(canvas)
    -- Over the art and the terrain, under the zone that lights up and the pins.
    frame:SetFrameLevel(canvas:GetFrameLevel() + 14)
    -- The values of the game's own quest areas; an alpha here goes from 0 to 255.
    for method, value in pairs({ SetFillTexture = QUEST_FILL, SetBorderTexture = QUEST_BORDER, SetFillAlpha = 128, SetBorderAlpha = 192, SetBorderScalar = 1 }) do
      if frame[method] then
        pcall(frame[method], frame, value)
      end
    end
    frame:EnableMouse(false)
  end
  if not questBlob then
    return
  end
  questBlob:DrawNone()
  if not (view.mapID and ns.GetOption("questAreas")) then
    questBlob:Hide()
    return
  end
  questBlob:SetMapID(view.mapID)
  questBlob:Show()
  local ok, quests = pcall(C_QuestLog.GetQuestsOnMap, view.mapID)
  for _, quest in ipairs(ok and type(quests) == "table" and quests or {}) do
    local questID = type(quest) == "table" and quest.questID
    -- A quest that is ready to turn in has no area left: its pin is where to go.
    if ns.Usable(questID) and not C_QuestLog.IsComplete(questID) then
      local drawn = pcall(questBlob.DrawBlob, questBlob, questID, true)
      if drawn then
        view.questAreas = view.questAreas + 1
      end
    end
  end
end

local function rebuildPins()
  local okAreas, errAreas = pcall(drawQuestAreas)
  if not okAreas then
    report("the quest areas", errAreas)
  end
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
  -- And only on a map of many zones (a continent, the world). The picture of a lit zone is
  -- added to the map: over a small part that is a glow, over most of a zone map it leaves
  -- nothing but a bright colour.
  local other, wide = false, false
  if mapX then
    local okOwn, own = pcall(C_Map.GetMapInfo, view.mapID)
    local kind = okOwn and type(own) == "table" and own.mapType
    wide = ns.Usable(kind) and Enum and Enum.UIMapType and kind <= Enum.UIMapType.Continent
  end
  if mapX and wide and C_Map.GetMapInfoAtPosition then
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
    -- Not the sheet of the zone where its land lies on the painting of the continent.
    layer.frame:SetAlpha(view.stitched and 0 or layerAlpha(index))
  end
  if terrainFrame and view.terrain then
    terrainFrame:SetAlpha(terrainAlpha())
  end
  -- The painting of the continent goes soft as the map zooms in: one of its pixels grows past
  -- the sharp size, and past the blur size it is not drawn, so that no block of colour shows.
  local paint = 1
  if view.paintPixel then
    paint = math.min(1, math.max(0, (PAINT_BLUR - view.paintPixel * view.scale) / (PAINT_BLUR - PAINT_SHARP)))
  end
  for _, tile in ipairs(neighbourTiles) do
    tile:SetAlpha(paint)
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

-- Where a zone is on the map of its continent: { parent, left, right, top, bottom }, the edges
-- from 0 to 1. Nil for a map that is not a zone of a continent.
local function panFor(mapID)
  if not (C_Map.GetMapRectOnMap and Enum and Enum.UIMapType) then
    return nil
  end
  local ok, info = pcall(C_Map.GetMapInfo, mapID)
  if not (ok and type(info) == "table" and info.mapType == Enum.UIMapType.Zone) then
    return nil
  end
  local parent = mapID
  for _ = 1, 4 do
    parent = parentOf(parent)
    if not parent then
      return nil
    end
    local okParent, parentInfo = pcall(C_Map.GetMapInfo, parent)
    if okParent and type(parentInfo) == "table" and parentInfo.mapType == Enum.UIMapType.Continent then
      local found, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, mapID, parent)
      if found and ns.Usable(left) and ns.Usable(right) and ns.Usable(top) and ns.Usable(bottom) and right > left and bottom > top then
        return { parent = parent, left = left, right = right, top = top, bottom = bottom }
      end
      return nil
    end
  end
  return nil
end

-- The world places of the corners of a map (north and west, in yards), or nil.
local function cornersOf(mapID)
  if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then
    return nil
  end
  local okA, world, cornerA = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
  local okB, _, cornerB = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
  if not (okA and okB and type(cornerA) == "table" and type(cornerB) == "table") then
    return nil
  end
  local northA, westA = cornerA:GetXY()
  local northB, westB = cornerB:GetXY()
  if not (ns.Usable(northA) and ns.Usable(westA) and ns.Usable(northB) and ns.Usable(westB)) or northA == northB or westA == westB then
    return nil
  end
  return { world = world, northA = northA, westA = westA, northB = northB, westB = westB }
end

-- Where another zone of the same continent lies on a zone, with that zone from 0 to 1:
-- { x0, x1, y0, y1, by }. `from` and `to` are the places of the two on the continent. By the
-- world places of the two maps where they agree with the continent (the terrain is laid by
-- them), else by the rectangles on the continent.
local function rectIn(fromID, from, toID, to)
  local wide, tall = from.right - from.left, from.bottom - from.top
  local rect = {
    x0 = (to.left - from.left) / wide, x1 = (to.right - from.left) / wide,
    y0 = (to.top - from.top) / tall, y1 = (to.bottom - from.top) / tall, by = "the continent",
  }
  local a, b = cornersOf(fromID), cornersOf(toID)
  if a and b and a.world == b.world then
    local x0, x1 = (b.westA - a.westA) / (a.westB - a.westA), (b.westB - a.westA) / (a.westB - a.westA)
    local y0, y1 = (b.northA - a.northA) / (a.northB - a.northA), (b.northB - a.northA) / (a.northB - a.northA)
    if x1 > x0 and y1 > y0 and math.abs(x0 + x1 - rect.x0 - rect.x1) < 0.5 and math.abs(y0 + y1 - rect.y0 - rect.y1) < 0.5 then
      rect = { x0 = x0, x1 = x1, y0 = y0, y1 = y1, by = "the world" }
    end
  end
  return rect
end

-- Draws the land around the zone shown, under its own art: the painting of the continent,
-- and what the character has uncovered of the zones beside it. With them the map goes from
-- zone to zone without a break: the land of the next zone is there before the map changes.
local function drawNeighbours()
  view.neighbours, view.surround, view.stitched, view.paintPixel = {}, nil, false, nil
  local pan = view.pan
  local usedTiles, usedOverlays = 0, 0
  if pan then
    if not neighbourFrame then
      neighbourFrame = CreateFrame("Frame", nil, canvas)
      neighbourFrame:SetAllPoints(canvas)
    end
    neighbourFrame:SetFrameLevel(canvas:GetFrameLevel())
    local found = {}
    local ok, children = pcall(C_Map.GetMapChildrenInfo, pan.parent, Enum.UIMapType.Zone)
    if ok and type(children) == "table" then
      for _, child in ipairs(children) do
        local mapID = type(child) == "table" and child.mapID
        local to = ns.Usable(mapID) and mapID ~= view.mapID and panFor(mapID)
        if to and to.parent == pan.parent then
          local rect = rectIn(view.mapID, pan, mapID, to)
          if rect.x1 > -NEIGHBOURS_REACH and rect.x0 < 1 + NEIGHBOURS_REACH and rect.y1 > -NEIGHBOURS_REACH and rect.y0 < 1 + NEIGHBOURS_REACH then
            rect.mapID = mapID
            rect.far = math.max(math.abs((rect.x0 + rect.x1) / 2 - 0.5), math.abs((rect.y0 + rect.y1) / 2 - 0.5))
            found[#found + 1] = rect
          end
        end
      end
    end
    table.sort(found, function(a, b)
      if a.far ~= b.far then
        return a.far < b.far
      end
      return a.mapID < b.mapID
    end)
    -- Under everything, the painting of the continent: one picture for all the land around,
    -- where the map of each zone would be a sheet of paper with its own frame.
    local whole = artLayers(pan.parent)
    if #whole > 0 then
      local info, files = whole[1].info, whole[1].files
      local wide, tall = pan.right - pan.left, pan.bottom - pan.top
      local originX, originY = -pan.left / wide * view.width, -pan.top / tall * view.height
      local scaleX, scaleY = view.width / wide / info.layerWidth, view.height / tall / info.layerHeight
      view.paintPixel = scaleX -- how wide one of its pixels is on the canvas: see place
      local columns = math.ceil(info.layerWidth / info.tileWidth)
      for tileIndex, file in ipairs(files) do
        local column, row = (tileIndex - 1) % columns, math.floor((tileIndex - 1) / columns)
        -- The last image of a row or a column goes on past the map: only its part on the map.
        local pixelWidth = math.min(info.tileWidth, info.layerWidth - column * info.tileWidth)
        local pixelHeight = math.min(info.tileHeight, info.layerHeight - row * info.tileHeight)
        if pixelWidth > 0 and pixelHeight > 0 then
          usedTiles = usedTiles + 1
          local tile = textureAt(neighbourFrame, neighbourTiles, usedTiles, "BACKGROUND", -8)
          tile:ClearAllPoints()
          tile:SetPoint("TOPLEFT", canvas, "TOPLEFT", originX + column * info.tileWidth * scaleX, -(originY + row * info.tileHeight * scaleY))
          tile:SetSize(pixelWidth * scaleX, pixelHeight * scaleY)
          tile:SetTexCoord(0, pixelWidth / info.tileWidth, 0, pixelHeight / info.tileHeight)
          tile:SetTexture(file, nil, nil, "TRILINEAR")
          tile:Show()
        end
      end
      view.surround = pan.parent
    end
    -- Over it, what the character has uncovered of the zones around: those pictures have the
    -- shape of the land, not of a sheet.
    for index = 1, math.min(#found, NEIGHBOURS_MOST) do
      local rect = found[index]
      local layers = artLayers(rect.mapID)
      if #layers > 0 then
        local info = layers[1].info
        local originX, originY = rect.x0 * view.width, rect.y0 * view.height
        local scaleX = (rect.x1 - rect.x0) * view.width / info.layerWidth
        local scaleY = (rect.y1 - rect.y0) * view.height / info.layerHeight
        usedOverlays = drawExplored(rect.mapID, neighbourFrame, neighbourOverlays, usedOverlays, info.tileWidth, info.tileHeight, originX, originY, scaleX, scaleY,
          ns.GetOption("revealAll"))
        view.neighbours[#view.neighbours + 1] = rect
      end
    end
    -- The zone shown is drawn the same way where the land of it is known: all its land over
    -- the painting of the continent, without its own sheet of paper and the frame of that.
    -- So nothing changes on the screen when the map goes to the next zone. Without the option
    -- revealAll the land is not all known, so the zone keeps its sheet.
    if view.surround and ns.GetOption("revealAll") and revealFor(view.mapID) then
      view.stitched = true
      local used = drawExplored(view.mapID, exploredFrame, overlays, 0, view.tileWidth, view.tileHeight, 0, 0, 1, 1, true)
      for index = used + 1, #overlays do
        overlays[index]:Hide()
      end
    end
    neighbourFrame:Show()
  elseif neighbourFrame then
    neighbourFrame:Hide()
  end
  for index = usedTiles + 1, #neighbourTiles do
    neighbourTiles[index]:Hide()
  end
  for index = usedOverlays + 1, #neighbourOverlays do
    neighbourOverlays[index]:Hide()
  end
end

-- If the zones around fail, the map still shows.
function loadNeighbours()
  local ok, err = pcall(drawNeighbours)
  if not ok then
    view.neighbours = {}
    report("the zones around the map", err)
    if neighbourFrame then
      neighbourFrame:Hide()
    end
  end
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
    view.pan = panFor(mapID)
    fit()
    loadNeighbours()
  end
  window.title:SetText(ns.MapName(mapID))
  window.up:SetEnabled(parentOf(mapID) ~= nil)
  rebuildPins()
  -- At once: a pin from the store still has the place of the pin it was before.
  if window:IsShown() then
    place()
  end
  return true
end

-- Zooming out past the whole of a zone goes out to its continent, with the zone at the same size
-- and under the same point of the window, so that the map does not jump. Returns true if the
-- map changed; a zone with no continent, or a map that is already a continent, does not.
goUpAt = function(px, py)
  local from = view.pan
  local parent = parentOf(view.mapID)
  if not (from and parent) then
    return false
  end
  local oldScale, oldWidth = view.scale, view.width
  local mapX, mapY = toMap(px, py)
  local before = view.mapID
  if not setMap(parent) then
    return false
  end
  local wide, tall = from.right - from.left, from.bottom - from.top
  -- The zone keeps its size on the screen: its width on the continent is `wide` of the width.
  local scale = math.min(view.maxScale, math.max(view.minScale, oldScale * oldWidth / (wide * view.width)))
  local onX, onY = from.left + mapX * wide, from.top + mapY * tall
  view.scale, view.target, anchor = scale, scale, nil
  view.x = px - onX * view.width * scale
  view.y = py - onY * view.height * scale
  clampView()
  view.crossNote = string.format("zoomed out from map %s to map %s (%s)", tostring(before), tostring(parent), ns.MapName(parent))
  dirty = true
  return true
end

-- The zone at a point of the map of a continent (0 to 1) that is not the zone shown: its map
-- and where it is on the continent. The game names the zone under a point; where it names
-- none, or the zone shown (the rectangles of zones lie over each other), the zone is found
-- from the rectangles: the one that has the point deepest inside.
local function nextZone(parent, onX, onY)
  local function fits(mapID)
    if not ns.Usable(mapID) or mapID == view.mapID then
      return nil
    end
    local rect = panFor(mapID)
    if rect and rect.parent == parent and onX >= rect.left and onX <= rect.right and onY >= rect.top and onY <= rect.bottom then
      return rect
    end
    return nil
  end
  if C_Map.GetMapInfoAtPosition then
    local ok, info = pcall(C_Map.GetMapInfoAtPosition, parent, onX, onY)
    local rect = ok and type(info) == "table" and fits(info.mapID)
    if rect then
      return info.mapID, rect
    end
  end
  local best, bestRect, bestDepth
  local ok, children = pcall(C_Map.GetMapChildrenInfo, parent, Enum.UIMapType.Zone)
  if ok and type(children) == "table" then
    for _, child in ipairs(children) do
      local rect = type(child) == "table" and fits(child.mapID)
      if rect then
        local depth = math.min((onX - rect.left) / (rect.right - rect.left), (rect.right - onX) / (rect.right - rect.left),
          (onY - rect.top) / (rect.bottom - rect.top), (rect.bottom - onY) / (rect.bottom - rect.top))
        if not bestDepth or depth > bestDepth then
          best, bestRect, bestDepth = child.mapID, rect, depth
        end
      end
    end
  end
  return best, bestRect
end
-- The middle of the viewport has left the map of the zone: shows the zone that is there
-- instead, with the same place in the middle and the same size of the land. Returns true if
-- the map changed. The zones are found on the map of the continent, where each one has a
-- rectangle.
local function crossZone()
  if not canCross() then
    return false
  end
  local width, height = viewportSize()
  local mapX, mapY = toMap(width / 2, height / 2)
  if mapX >= 0 and mapX <= 1 and mapY >= 0 and mapY <= 1 then
    return false
  end
  local from = view.pan
  local onX, onY = from.left + mapX * (from.right - from.left), from.top + mapY * (from.bottom - from.top)
  if onX < 0 or onX > 1 or onY < 0 or onY > 1 then
    view.crossNote = "past the edge of the continent"
    return false
  end
  local nextID, to = nextZone(from.parent, onX, onY)
  if not nextID then
    view.crossNote = string.format("the continent has no zone at %.3f, %.3f", onX, onY)
    return false
  end
  -- Where the next zone lies on the map shown: the same rectangle it was drawn in beside this
  -- map, so the new map comes exactly where its picture was.
  local rect = rectIn(view.mapID, from, nextID, to)
  local before, oldScale, oldWidth = view.mapID, view.scale, view.width
  if not loadArt(nextID) then
    view.crossNote = "the game has no art for map " .. tostring(nextID)
    return false
  end
  view.mapID, view.pan = nextID, to
  limits()
  -- The place of the middle on the new map; inside it, so that the next look does not send
  -- the map back.
  local newX = math.min(1, math.max(0, (mapX - rect.x0) / (rect.x1 - rect.x0)))
  local newY = math.min(1, math.max(0, (mapY - rect.y0) / (rect.y1 - rect.y0)))
  -- The same size of the land. That can be farther out than the whole of a small zone: the
  -- zones around it fill the window. Not closer than the new map can zoom: at the closest
  -- zoom the two maps have the same limit but for the last digits of the number.
  local scale = math.min(view.maxScale, oldScale * oldWidth * (rect.x1 - rect.x0) / view.width)
  view.scale, view.target, anchor = scale, scale, nil
  view.x = width / 2 - newX * view.width * scale
  view.y = height / 2 - newY * view.height * scale
  view.crossNote = string.format("went from map %s to map %s (%s), placed by %s", tostring(before), tostring(nextID), ns.MapName(nextID), rect.by)
  window.title:SetText(ns.MapName(view.mapID))
  window.up:SetEnabled(parentOf(view.mapID) ~= nil)
  loadNeighbours()
  rebuildPins()
  dirty = true
  return true
end
-- After the player moved the map: the next zone if the middle left this one, else the map
-- stays where the middle is on it.
local function settle()
  clampView(CROSS_SLACK)
  local crossed = crossZone()
  clampView()
  dirty = true
  return crossed
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
        if settle() then
          -- The next zone: the move goes on from here.
          drag = { px = px, py = py, x = view.x, y = view.y, moved = true }
        end
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
  -- The pins are read again every few seconds (group members move), and soon after the game
  -- said that something changed. Not while the player moves or zooms the map: that must stay
  -- smooth. Not while a tooltip of a pin shows: the new pins would take it away under the pointer.
  sinceRefresh = sinceRefresh + elapsed
  local due = sinceRefresh >= REFRESH_SECONDS or (stale and sinceRefresh >= STALE_SECONDS)
  if due and not drag and view.scale == view.target and not hovered then
    sinceRefresh = 0
    stale = false
    rebuildPins()
    -- At once: a pin from the store still has the place of the pin it was before.
    place()
    placeArrow()
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
    check("Terrain when zoomed in", "terrainDetail")
    check("Quest areas", "questAreas")
    check("Land you have not explored", "revealAll")
    check("That land as bright as the rest", "revealBright")
    local function percent(label, key, values)
      local sub = root:CreateButton(label)
      for _, value in ipairs(values) do
        sub:CreateRadio(value .. "%", function()
          return ns.GetOption(key) == value
        end, function()
          ns.SetOption(key, value)
        end)
      end
    end
    percent("Opacity of the window", "mapOpacity", { 100, 85, 70, 55, 40 })
    percent("Size of the window", "mapScale", { 60, 75, 90, 100, 115, 130, 150 })
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

-- The opacity and the scale of the window, from the options.
local function applyWindowLook()
  if not window then
    return
  end
  local opacity, scale = ns.GetOption("mapOpacity"), ns.GetOption("mapScale")
  window:SetAlpha((ns.Usable(opacity) and opacity or 100) / 100)
  window:SetScale((ns.Usable(scale) and scale or 100) / 100)
end

-- The place and the size of the window, kept in ForeverAtlasDB.frames.map for the next time.
local function saveWindow()
  local point, _, relative, x, y = window:GetPoint(1)
  local width, height = window:GetWidth(), window:GetHeight()
  if type(ForeverAtlasDB) == "table" and type(ForeverAtlasDB.frames) == "table" and point and ns.Usable(x) and ns.Usable(y)
    and ns.Usable(width) and ns.Usable(height) then
    ForeverAtlasDB.frames.map = { point, relative, x, y, width, height }
  end
end

local function restoreWindow()
  local saved = type(ForeverAtlasDB) == "table" and type(ForeverAtlasDB.frames) == "table" and ForeverAtlasDB.frames.map
  window:ClearAllPoints()
  if type(saved) == "table" and type(saved[1]) == "string" and ns.Usable(saved[3]) and ns.Usable(saved[4])
    and ns.Usable(saved[5]) and ns.Usable(saved[6]) then
    window:SetSize(math.max(WINDOW_LEAST_WIDE, saved[5]), math.max(WINDOW_LEAST_HIGH, saved[6]))
    window:SetPoint(saved[1], UIParent, type(saved[2]) == "string" and saved[2] or saved[1], saved[3], saved[4])
  else
    window:SetSize(math.max(640, UIParent:GetWidth() * 0.72), math.max(480, UIParent:GetHeight() * 0.8))
    window:SetPoint("CENTER")
  end
end

-- Back to the first place and size (the button "Reset frame positions" of the settings).
function ns.ResetMapWindow()
  if type(ForeverAtlasDB) == "table" and type(ForeverAtlasDB.frames) == "table" then
    ForeverAtlasDB.frames.map = nil
  end
  if window then
    restoreWindow()
  end
end

-- The zones and continents of the world, by name, for the search: from the world map and the
-- zones of each continent (the game's list of the zones of a continent is the one that is sure).
local SEARCH_WORLD = 947
local SEARCH_MOST = 8

local function searchMaps()
  local list, seen = {}, {}
  local function add(info)
    if type(info) == "table" and ns.Usable(info.mapID) and type(info.name) == "string" and info.name ~= "" and not seen[info.mapID] then
      seen[info.mapID] = true
      list[#list + 1] = info
    end
  end
  local ok, top = pcall(C_Map.GetMapChildrenInfo, SEARCH_WORLD, nil, true)
  if ok and type(top) == "table" then
    for _, info in ipairs(top) do
      add(info)
      if type(info) == "table" and info.mapType == Enum.UIMapType.Continent then
        local okZones, zones = pcall(C_Map.GetMapChildrenInfo, info.mapID, Enum.UIMapType.Zone)
        for _, zone in ipairs(okZones and type(zones) == "table" and zones or {}) do
          add(zone)
        end
      end
    end
  end
  return list
end

-- The places that match a text, the best first: the names that start with it, then the
-- shorter names. Returns up to SEARCH_MOST of { mapID, name }.
function ns.FindPlaces(text)
  local wanted = string.lower(text or "")
  if wanted == "" then
    return {}
  end
  local found = {}
  for _, info in ipairs(searchMaps()) do
    local at = string.lower(info.name):find(wanted, 1, true)
    if at then
      found[#found + 1] = { mapID = info.mapID, name = info.name, at = at }
    end
  end
  table.sort(found, function(a, b)
    if (a.at == 1) ~= (b.at == 1) then
      return a.at == 1
    end
    if #a.name ~= #b.name then
      return #a.name < #b.name
    end
    return a.name < b.name
  end)
  local list = {}
  for index = 1, math.min(#found, SEARCH_MOST) do
    list[index] = { mapID = found[index].mapID, name = found[index].name }
  end
  return list
end

local function create()
  window = CreateFrame("Frame", "ForeverAtlasMap", UIParent)
  window:SetFrameStrata("HIGH")
  restoreWindow()
  window:SetMovable(true)
  window:SetResizable(true)
  if window.SetResizeBounds then
    window:SetResizeBounds(WINDOW_LEAST_WIDE, WINDOW_LEAST_HIGH)
  end
  window:SetClampedToScreen(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    saveWindow()
  end)
  window:Hide()
  applyWindowLook()
  -- The corner to change the size of the window.
  local grip = CreateFrame("Button", nil, window)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetFrameLevel(window:GetFrameLevel() + 30)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function()
    window:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    window:StopMovingOrSizing()
    saveWindow()
  end)
  window.grip = grip
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

  -- The search: type a name of a zone, and the list of the places it matches shows under it.
  -- Enter goes to the best one; a click on a line goes to that one.
  local search = CreateFrame("EditBox", "ForeverAtlasSearch", window, "InputBoxTemplate")
  search:SetSize(150, 20)
  search:SetPoint("LEFT", window.show, "RIGHT", 14, 0)
  search:SetAutoFocus(false)
  search:SetMaxLetters(40)
  local results = CreateFrame("Frame", nil, window)
  results:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -2)
  results:SetSize(170, 20)
  results:SetFrameLevel(window:GetFrameLevel() + 40)
  results:Hide()
  local resultsBack = results:CreateTexture(nil, "BACKGROUND")
  resultsBack:SetAllPoints()
  resultsBack:SetColorTexture(0.03, 0.03, 0.04, 0.98)
  results.rows = {}
  local function closeSearch()
    search:SetText("")
    search:ClearFocus()
    results:Hide()
  end
  local function goTo(mapID)
    closeSearch()
    ns.ShowMap(mapID)
  end
  local function showResults(text)
    local list = ns.FindPlaces(text)
    if #list == 0 then
      results:Hide()
      return
    end
    for index, place in ipairs(list) do
      local row = results.rows[index]
      if not row then
        row = CreateFrame("Button", nil, results)
        row:SetSize(166, 16)
        row:SetPoint("TOPLEFT", 2, -2 - (index - 1) * 16)
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 4, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnClick", function(self)
          goTo(self.mapID)
        end)
        results.rows[index] = row
      end
      row.mapID = place.mapID
      row.text:SetText(place.name)
      row:Show()
    end
    for index = #list + 1, #results.rows do
      results.rows[index]:Hide()
    end
    results:SetHeight(4 + #list * 16)
    results:Show()
  end
  search:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
      showResults(self:GetText())
    end
  end)
  search:SetScript("OnEnterPressed", function(self)
    local list = ns.FindPlaces(self:GetText())
    if list[1] then
      goTo(list[1].mapID)
    else
      closeSearch()
    end
  end)
  search:SetScript("OnEscapePressed", closeSearch)
  window.search = search

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
  highlight:SetAlpha(0.5) -- a glow: the map under it stays readable
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
  hint:SetPoint("BOTTOMRIGHT", -22, 8)
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
      -- The end of a move, not a click. A map that was moved past its edge from farther out
      -- goes back to its place.
      clampView()
      dirty = true
      return
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
    if drag and drag.moved and view.mapID then
      drag = nil
      clampView()
      dirty = true
    end
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
  print(string.format("  quest areas: %s; window opacity %s%%, size %s%%", questBlob == false and "this client cannot draw them"
    or not ns.GetOption("questAreas") and "off" or tostring(view.questAreas or 0), tostring(ns.GetOption("mapOpacity")), tostring(ns.GetOption("mapScale"))))
  -- Each kind of pin: what the icon of its first pin asked for, what the game shows for it, and
  -- how many of its pins are outside the window. A missing atlas falls back to a picture file;
  -- a file the game does not have shows nothing or a green square.
  local firstOf, outside, order = {}, {}, {}
  local mapWidth, mapHeight = view.width * view.scale, view.height * view.scale
  for _, pin in ipairs(pins) do
    local kind = pin.kind or "?"
    if not firstOf[kind] then
      firstOf[kind], outside[kind] = pin, 0
      order[#order + 1] = kind
    end
    local px, py = view.x + pin.x * mapWidth, view.y + pin.y * mapHeight
    if px < 0 or px > width or py < 0 or py > height then
      outside[kind] = outside[kind] + 1
    end
  end
  table.sort(order)
  local hasAtlas = C_Texture and C_Texture.GetAtlasInfo
  for _, kind in ipairs(order) do
    local pin = firstOf[kind]
    local look = pin.data and pin.data.look or {}
    local function state(atlas)
      if not atlas then
        return "none"
      end
      local ok, info = pcall(hasAtlas or error, atlas)
      return atlas .. (ok and info and " (the game has it)" or " (missing)")
    end
    local okAtlas, shownAtlas = pcall(pin.icon.GetAtlas, pin.icon)
    local okFile, shownFile = pcall(pin.icon.GetTexture, pin.icon)
    print(string.format("    %s: %d of %d outside the window; atlas %s, second atlas %s, file %s; shows %s, size %s",
      kind, outside[kind], kinds[kind], state(look.atlas), state(look.fallbackAtlas), tostring(look.texture),
      okAtlas and shownAtlas and ("atlas " .. tostring(shownAtlas)) or ("file " .. tostring(okFile and shownFile or "?")),
      tostring(pin.data and pin.data.size or 16)))
  end
  local terrain = view.terrain
  print("  terrain: " .. (terrain and string.format("%d images, %d by %d, first %s, opacity %.2f", terrain.images, terrain.columns, terrain.rows, tostring(terrain.first), terrainAlpha())
    or (ns.GetOption("terrainDetail") and "on, but none for this map" or "off")))
  local pan = view.pan
  print("  from zone to zone: " .. (pan and string.format("on map %s at %.3f to %.3f, %.3f to %.3f; %s", tostring(pan.parent), pan.left, pan.right, pan.top, pan.bottom,
    string.format("%s, %d zones drawn around it, %s", view.surround and "the continent under it" or "no painting of the continent", #(view.neighbours or {}),
      view.stitched and "all its land drawn without its sheet" or "its own sheet shown")) or "this map is not a zone of a continent"))
  if view.crossNote then
    print("    the last try: " .. view.crossNote)
  end
  local errors = 0
  for text in pairs(reported) do
    errors = errors + 1
    print("  error: " .. text)
  end
  if errors == 0 then
    print("  no error inside the map so far.")
  end
  -- What the game draws: each part of the map with its place on the screen. A part that is
  -- there and does not show is hidden, clear, of no size, or outside the window.
  local function call(object, method)
    local fn = object[method]
    if type(fn) ~= "function" then
      return "?"
    end
    local ok, value = pcall(fn, object)
    if not ok or value == nil then
      return "-"
    end
    if type(value) == "number" then
      return string.format("%.2f", value)
    end
    return tostring(value)
  end
  local function drawn(name, object)
    print(string.format("  %s: visible %s, opacity %s, level %s, scale %s, left %s, top %s, %s by %s", name,
      call(object, "IsVisible"), call(object, "GetEffectiveAlpha"), call(object, "GetFrameLevel"), call(object, "GetEffectiveScale"),
      call(object, "GetLeft"), call(object, "GetTop"), call(object, "GetWidth"), call(object, "GetHeight")))
  end
  print("  what the game draws:")
  drawn("window", window)
  drawn("map area", viewport)
  drawn("canvas", canvas)
  for index, layer in ipairs(view.layers) do
    drawn("layer " .. index, layer.frame)
    local entry = layerFrames[index]
    local tile = entry and entry.tiles[1]
    if tile then
      drawn("layer " .. index .. " image 1", tile)
      print(string.format("    its picture: %s, draw layer %s", call(tile, "GetTexture"), call(tile, "GetDrawLayer")))
    end
  end
  if exploredFrame then
    drawn("uncovered parts", exploredFrame)
    local shown = 0
    for _, texture in ipairs(overlays) do
      if texture:IsShown() then
        shown = shown + 1
      end
    end
    print("    images of uncovered parts: " .. shown)
  end
  drawn("pin layer", overlay)
  if pins[1] then
    drawn("pin 1 (" .. tostring(pins[1].kind) .. ")", pins[1])
    print(string.format("    its picture: %s", call(pins[1].icon, "GetTexture")))
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

-- Moves the map so that a point of it (0 to 1, or a little past the edge) is in the middle of
-- the window, as a drag does. Returns true if that showed the next zone.
-- With `held` the mouse button is down for the move and let go after it.
function ns.PanMapTo(mapX, mapY, held)
  if not view.mapID then
    return false
  end
  local width, height = viewportSize()
  local dragBefore = drag
  if held then
    drag = { moved = true }
  end
  view.x = width / 2 - mapX * view.width * view.scale
  view.y = height / 2 - mapY * view.height * view.scale
  view.target, anchor = view.scale, nil
  local crossed = settle()
  if held then
    drag = dragBefore
    clampView()
  end
  place()
  return crossed
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

-- The terrain of the map now: { images, columns, rows, world, first (the number of the first
-- image), alpha (how much of it shows) }, or nil without terrain.
-- The zones drawn around the zone shown: a list of { mapID, x0, x1, y0, y1, by }, the places
-- on the map shown (0 to 1 is the map itself).
-- The second result: the map whose painting lies under them all (the continent), or nil.
function ns.MapNeighbours()
  return view.neighbours or {}, view.surround, view.stitched == true
end

function ns.MapTerrain()
  if not view.terrain then
    return nil
  end
  local terrain = view.terrain
  return { images = terrain.images, columns = terrain.columns, rows = terrain.rows, world = terrain.world, first = terrain.first, alpha = terrainAlpha() }
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
    place()
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
  elseif key == "notes" or key == "pins" or key == "zoneNames" or key == "questAreas" or key:find("^show_") then
    ns.RefreshMapPins()
  elseif key == "mapOpacity" or key == "mapScale" then
    applyWindowLook()
  elseif key == "revealAll" or key == "revealBright" then
    -- The land of the zone shown and of the zones around it, drawn again.
    if window and view.mapID and exploredFrame then
      local used = drawExplored(view.mapID, exploredFrame, overlays, 0, view.tileWidth, view.tileHeight, 0, 0, 1, 1)
      for index = used + 1, #overlays do
        overlays[index]:Hide()
      end
      loadNeighbours()
      dirty = true
    end
  elseif key == "terrainDetail" then
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
    "QUESTLINE_UPDATE", "DYNAMIC_GOSSIP_POI_UPDATED", "SUPER_TRACKING_CHANGED",
  }) do
    pcall(events.RegisterEvent, events, event)
  end
  events:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_BINDINGS" or (event == "PLAYER_REGEN_ENABLED" and wanted) then
      bindKeys()
    elseif event ~= "UPDATE_BINDINGS" and event ~= "PLAYER_REGEN_ENABLED" then
      -- The game sends these in bursts (the quest log most of all): the map reads its pins
      -- again once, at its next update.
      stale = true
    end
  end)
end)
