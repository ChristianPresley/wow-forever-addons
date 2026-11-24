-- What Forever Atlas does, with checks. T is the test table of the driver (see driver.lua).
local T = ...
local H, ns, expect = T.H, T.ns, T.expect

-- A note at the place of the player.
T.slash("/fatlas", "note Good fishing")
local notes = ForeverAtlasDB.notes[37]
expect(notes and #notes == 1 and notes[1].text == "Good fishing", "/fatlas note adds a note on the map of the player")
expect(notes[1].x > 0 and notes[1].x <= 100 and notes[1].y > 0 and notes[1].y <= 100, "a note has map coordinates from 0 to 100")
expect(ns.GetOption("notes") == true, "adding a note turns the notes on")

-- Alt-click on the world map opens the editor; a plain click does nothing.
for _, handler in ipairs(H.canvasClickHandlers) do
  expect(handler(WorldMapFrame, "LeftButton", 0.4, 0.6) == false, "a plain click on the map stays with the map")
end
T.world.alt = true
local handled = false
for _, handler in ipairs(H.canvasClickHandlers) do
  handled = handler(WorldMapFrame, "LeftButton", 0.4, 0.6) or handled
end
T.world.alt = false
expect(handled == true and ForeverAtlasNoteEditor ~= nil and ForeverAtlasNoteEditor:IsShown(), "Alt-click on the map opens the note editor")
-- A note from code, and the notes of the map.
local added = ns.AddNote(37, 40, 60, "Cave", 3)
expect(#ForeverAtlasDB.notes[37] == 2 and added.icon == 3, "a note is added with its icon")

-- Waypoints: /way with coordinates on the map of the player.
T.slash("/way", "45.2 61.8 Farm")
local waypoints = ForeverAtlasCharDB.waypoints
expect(#waypoints == 1 and waypoints[1].label == "Farm" and waypoints[1].x == 45.2 and waypoints[1].y == 61.8, "/way adds a waypoint with its label")
expect(waypoints[1].mapID == 37, "the waypoint is on the map of the player")
-- The arrow follows the waypoint: from the player at 42, 65 it is 32 yards north and 32 west.
T.advance(2)
expect(ForeverAtlasArrow ~= nil and ForeverAtlasArrow:IsShown(), "the arrow is on the screen while a waypoint is set")
expect(ForeverAtlasArrow.distance:GetText() == "45 yd", "the arrow has the distance to the waypoint (45 yd), got " .. tostring(ForeverAtlasArrow.distance:GetText()))
expect(ForeverAtlasArrow.label:GetText() == "Farm", "the arrow has the label of the waypoint")
-- A second waypoint, and a waypoint without a label.
T.slash("/way", "10 10")
expect(#waypoints == 2, "a second waypoint is added")
T.slash("/way", "")
T.slash("/way", "nonsense")
expect(#waypoints == 2, "a /way without coordinates adds nothing")
-- A waypoint at the place of the player: arriving removes it.
ns.SetOption("arrivalYards", 50)
ns.AddWaypoint(37, 42, 65, "Here")
expect(#waypoints == 3, "the waypoint at the place of the player is added")
T.advance(1)
expect(#waypoints == 2 and T.printed("arrived at Here"), "arriving at a waypoint removes it and says so")
ns.SetOption("arrivalYards", 5)
T.slash("/fatlas", "clear")

-- Visited areas and coordinates.
T.fire("ZONE_CHANGED")
T.fire("ZONE_CHANGED_NEW_AREA")
T.advance(2)
T.slash("/fatlas", "")

-- The Forever Atlas map. The map key opens it: the key has a binding of the addon over the
-- game's own, and no function of the game is replaced.
expect(ns.GetOption("mapKey") == true and ns.MapKeys()[1] == "M", "the key of the world map (M) is bound to the Forever Atlas map")
expect(H.pressKey("M") == "override" and ForeverAtlasMap ~= nil and ForeverAtlasMap:IsShown(), "the map key opens the Forever Atlas map")
expect(H.count("game binding") == 0, "the map key does not reach the map of the game")
local view = ns.MapView()
expect(view.mapID == 37, "the map of the place of the player (37) shows, got " .. tostring(view.mapID))
-- The art of the zone has two layers of 1002 by 668 pixels: the whole map, and a finer picture.
-- All images of both (12 each) are on the canvas from the start.
expect(view.width == 1002 and view.height == 668 and #view.layers == 2, "the map has both layers of the art, got " .. #view.layers)
expect(view.layers[1].images == 12 and view.layers[2].images == 12, "every image of both layers is loaded when the map opens")
local shownLayers = ns.MapLayers()
expect(shownLayers[1] == 1 and shownLayers[2] == 0, "with the whole map in the window, only the first layer shows")
local framesBefore = #H.frames
-- At first the whole map fits in the window.
local whole = view.scale
expect(whole == view.minScale and view.maxScale >= 3, "the map opens with the whole map in the window, and zooms in to three times the art or more")
-- Zooming toward a point keeps that point where it is on the screen.
local function onScreen(mapX, mapY)
  return view.x + mapX * view.width * view.scale, view.y + mapY * view.height * view.scale
end
local beforeX, beforeY = onScreen(0.25, 0.75)
local scale = ns.ZoomMap(4, 0.25, 0.75)
local afterX, afterY = onScreen(0.25, 0.75)
expect(scale > whole * 2 and scale < whole * 2.1, "four notches of the wheel zoom in by 1.2 four times, got " .. tostring(scale / whole))
expect(math.abs(afterX - beforeX) < 0.01 and math.abs(afterY - beforeY) < 0.01, "the point under the pointer stays where it is during a zoom")
-- A zoom makes no frame and loads no image: the canvas only changes its scale.
ns.ZoomMap(6, 0.5, 0.5)
ns.ZoomMap(-3, 0.5, 0.5)
expect(#H.frames == framesBefore, "zooming makes no new frame")
-- The finer layer fades in on the way to 2.5 times closer (the zoom numbers of the game), and
-- is fully there from then on.
-- Zooming out past the whole of the zone goes out to its continent, with the zone kept in size.
ns.ZoomMap(-100)
expect(ns.MapView().mapID == 13 and ns.MapView().pan == nil, "zooming out past the whole zone goes out to its continent (13), got " .. tostring(ns.MapView().mapID))
expect(ns.MapView().scale >= ns.MapView().minScale and ns.MapView().scale <= ns.MapView().maxScale, "the continent opens at the size of the zone, got " .. tostring(ns.MapView().scale))
ns.ShowMap(37)
ns.ZoomMap(3, 0.5, 0.5) -- 1.73 times closer: before the fade starts at 1.975
expect(ns.MapLayers()[2] == 0, "at 1.7 times closer the finer layer does not show yet, got " .. tostring(ns.MapLayers()[2]))
ns.ZoomMap(1, 0.5, 0.5) -- 2.07 times closer
local part = ns.MapLayers()[2]
expect(part > 0 and part < 1, "at 2.07 times closer the finer layer is fading in, got " .. tostring(part))
ns.ZoomMap(2, 0.5, 0.5) -- 2.99 times closer
expect(ns.MapLayers()[2] == 1 and ns.MapLayers()[1] == 1, "past 2.5 times closer the finer layer shows in full, got " .. tostring(ns.MapLayers()[2]))
expect(#H.frames == framesBefore, "the change of the layer makes no new frame")
ns.ZoomMap(100)
expect(view.scale == view.maxScale, "the zoom stops at its greatest scale")
ns.ZoomMap(-100)
expect(ns.MapView().mapID == 13, "the zoom out from the zone goes to the continent, got " .. tostring(ns.MapView().mapID))
ns.ShowMap(37)
expect(ns.MapView().scale == ns.MapView().minScale, "the zone opens with the whole map in the window")
-- The pins: the quests of the log, the note and the waypoint of before.
local quests, others = 0, 0
for _, pin in ipairs(ns.MapPins()) do
  if pin.data.quest then
    quests = quests + 1
  else
    others = others + 1
  end
end
expect(quests == 2 and others >= 2, "the map has a pin for each quest of the log on it and the pins of the addon, got " .. quests .. " and " .. others)
-- A click on a quest pin opens the quest in the quest log of the game, and closes this map.
for _, pin in ipairs(ns.MapPins()) do
  if pin.data.quest == 176 then
    H.run(pin.frame, "OnMouseUp", "LeftButton")
  end
end
expect(H.count("open quest") == 1 and not ForeverAtlasMap:IsShown(), "a click on a quest pin opens the quest in the quest log of the game")
-- In a fight the game refuses an addon that opens a window: the map stays and says why.
H.pressKey("M")
T.world.secret = true
for _, pin in ipairs(ns.MapPins()) do
  if pin.data.quest == 176 then
    H.run(pin.frame, "OnMouseUp", "LeftButton")
  end
end
T.world.secret = false
expect(H.count("open quest") == 1 and ForeverAtlasMap:IsShown() and T.printed("cannot open in a fight"), "in a fight a click on a quest pin opens nothing and says why")
H.pressKey("M")
-- A right-click goes out to the map above; a click on a zone opens it.
H.pressKey("M")
expect(ns.ClickMap("RightButton", 0.5, 0.5) and view.mapID == 13, "a right-click goes out to the continent, got " .. tostring(view.mapID))
expect(#view.layers == 1, "the continent has one layer")
expect(ns.ClickMap("LeftButton", 0.8, 0.5) and view.mapID == 52, "a click on the right half of the continent opens Westfall, got " .. tostring(view.mapID))
-- Westfall: a finer layer with twice the pixels and no zoom numbers. It covers the same map,
-- starts 1.8 times closer, and the zoom goes far enough in for its pixels.
expect(#view.layers == 2 and view.layers[2].ratio == 2 and view.layers[2].images == 48, "the finer layer of Westfall has twice the pixels: 8 by 6 images")
expect(math.abs(view.layers[2].start - 1.8) < 0.001 and view.maxScale >= 6, "without zoom numbers the finer layer starts 1.8 times closer, and the zoom goes in to three times its pixels")
ns.ZoomMap(100)
expect(ns.MapLayers()[2] == 1, "zoomed all the way in, the finer layer shows")
ns.ShowMap(13)
ns.ShowMap(52)
expect(ns.ClickMap("LeftButton", 0.5, 0.5) == false and view.mapID == 52, "a click on a zone with no map under it changes nothing")
-- Alt-click adds a note there.
T.world.alt = true
ForeverAtlasNoteEditor:Hide()
expect(ns.ClickMap("LeftButton", 0.3, 0.4) and ForeverAtlasNoteEditor:IsShown(), "Alt-click on the map opens the note editor")
T.world.alt = false
ForeverAtlasNoteEditor:Hide()
-- A map without art: the map of before stays.
expect(ns.ShowMap(9999) == true and view.mapID == 52, "a map without art leaves the map of before")
-- The button to the map of the game.
T.slash("/fatlas", "map")
expect(not ForeverAtlasMap:IsShown(), "/fatlas map closes the map")
T.slash("/fatlas", "map")
expect(ForeverAtlasMap:IsShown(), "/fatlas map opens it again")
ForeverAtlasMap:Hide()
-- With the option off, the key is the game's again.
ns.SetOption("mapKey", false)
expect(#ns.MapKeys() == 0 and H.pressKey("M") == "TOGGLEWORLDMAP" and not ForeverAtlasMap:IsShown(), "with the option off the map key opens the map of the game")
-- In a fight the game refuses a change of bindings: the addon waits for the end of the fight.
T.world.secret = true
ns.SetOption("mapKey", true)
expect(#ns.MapKeys() == 0, "in a fight the key is not changed")
T.world.secret = false
T.fire("PLAYER_REGEN_ENABLED")
expect(ns.MapKeys()[1] == "M", "after the fight the map key is bound to the Forever Atlas map")

-- /fatlas layers prints the art of the map of the player.
T.slash("/fatlas", "layers")
expect(T.printed("has 2 layers of art") and T.printed("1002 by 668 pixels"), "/fatlas layers prints the layers of the map")

-- What the map shows: one kind for each sort of thing that the game tells an addon about.
ns.ShowMap(37)
local function count(kind)
  local found = 0
  for _, pin in ipairs(ns.MapPins()) do
    if pin.kind == kind then
      found = found + 1
    end
  end
  return found
end
local function pinNamed(kind, at)
  for _, pin in ipairs(ns.MapPins()) do
    if pin.kind == kind and (at == nil or math.abs(pin.x - at) < 0.001) then
      return pin
    end
  end
end
expect(count("questTurnIns") == 1 and count("questObjectives") == 1, "the quest that is ready has a turn-in pin, the other one an objective pin")
expect(count("questGivers") == 1, "one quest giver: not the hidden quest and not the one on another floor, got " .. count("questGivers"))
expect(count("flight") == 1, "one flight master: the one of the player's faction, got " .. count("flight"))
expect(count("areaPOIs") == 2 and count("graveyards") == 1 and count("links") == 1 and count("dungeons") == 0, "the town, the abbey, the graveyard and the way to Westfall")
expect(count("rares") == 2 and count("mapPin") == 1, "two rare markers and the map pin of the player")
expect(count("group") == 0 and count("corpse") == 0, "no group member and no corpse when alone and alive")
expect(count("atlas") >= 2, "the note and the waypoint of the addon are on the map too")
-- Another addon adds pins through the public table ForeverAtlasAPI; they show on this map at once.
expect(type(ForeverAtlasAPI) == "table" and ForeverAtlasAPI.version == 1, "the public table ForeverAtlasAPI is there")
local before = count("atlas")
local herbOn = true
ForeverAtlasAPI.AddPinProvider(function(mapID, add)
  if mapID == 37 and herbOn then
    add(33, 44, { look = { texture = "Interface\\Icons\\INV_Misc_Herb_07" }, size = 14, tooltip = function(tooltip) tooltip:AddLine("Peacebloom") end })
  end
end)
expect(count("atlas") == before + 1 and pinNamed("atlas", 0.33), "a pin of another addon is on the map, got " .. count("atlas") - before)
herbOn = false
ForeverAtlasAPI.RefreshPins()
expect(count("atlas") == before, "and is gone after RefreshPins when the addon drops it")
expect(not pcall(ForeverAtlasAPI.AddPinProvider, "not a function"), "AddPinProvider refuses what is not a function")
-- The icon is the game's: an atlas where the game names one, else a part of the sheet of map icons.
expect(pinNamed("questTurnIns").data.look.atlas == "UI-QuestPoi-QuestBangTurnIn" and pinNamed("questGivers").data.look.atlas == "QuestNormal", "quest pins have the icons of the game's map")
expect(pinNamed("flight").data.look.atlas == "TaxiNode_Alliance", "a flight master has the icon that the game names for it")
local town = pinNamed("areaPOIs", 0.42)
expect(town.data.look.texture == "Interface/Minimap/POIIcons" and town.data.look.coords[1] == 0.5 and town.data.look.coords[2] == 0.6, "a point of interest without an atlas has its part of the sheet of map icons")
expect(pinNamed("areaPOIs", 0.5).data.look.atlas == "poi-town", "a point of interest with an atlas has the atlas")
-- The pointer over a pin shows its tooltip. A pin without a click lets the mouse through to the map.
-- (Zoomed in: the window of the stand-in is one unit wide, so at first all pins are at one place.)
ns.ZoomMap(100, 0.42, 0.64)
local over = ns.HoverMap(0.42, 0.64)
expect(over ~= nil and over.kind == "areaPOIs" and not over:IsMouseEnabled(), "the tooltip of the town shows under the pointer, and the pin does not take the mouse")
expect(ns.HoverMap(0.9, 0.9) == nil, "away from every pin there is no tooltip")
expect(pinNamed("links").frame:IsMouseEnabled(), "a pin with a click takes the mouse")
-- Back to the whole zone: zooming out past it would go to the continent.
ns.ShowMap(13)
ns.ShowMap(37)
-- Each kind can be turned off.
ns.SetOption("show_flight", false)
expect(count("flight") == 0 and count("areaPOIs") == 2, "with flight masters off they are gone, and the rest stays")
ns.SetOption("show_flight", true)
expect(count("flight") == 1, "and back with the option on")
-- The menu of the button "Show" has a checkbox for each kind.
H.menus = {}
H.click(ForeverAtlasMap.show, "LeftButton", false)
-- The title and seven more checkboxes, and the choices of the two lists of percents (opacity: 5, size: 7).
expect(#H.menus == 1 and #H.menus[1] == #ns.MAP_KINDS + 8 + 12, "the menu has a checkbox for each kind, eight more and the two lists of percents, got " .. tostring(H.menus[1] and #H.menus[1]))
H.menus = {}
-- In a party: the member. As a ghost: the corpse.
T.world.group = "party"
T.world.dead = true
ns.RefreshMapPins()
expect(count("group") == 1 and count("corpse") == 1, "the party member and the corpse are on the map")
T.world.group = nil
T.world.dead = false
ns.RefreshMapPins()
-- The way to Westfall opens that map, which has a dungeon entrance.
H.run(pinNamed("links").frame, "OnMouseUp", "LeftButton")
expect(ns.MapView().mapID == 52 and count("dungeons") == 1 and pinNamed("dungeons").data.look.atlas == "Dungeon", "the way to Westfall opens its map, with the entrance of the dungeon")
-- The continent: the names of its zones, and the zone under the pointer lights up.
ns.ShowMap(13)
local zoneNames = ns.MapLabels()
expect(#zoneNames == 2 and zoneNames[1].text == "Elwynn Forest" and zoneNames[1].x == 0.25 and zoneNames[2].text == "Westfall" and zoneNames[2].x == 0.75, "the continent has the name of each zone in its middle")
expect(select(2, ns.HoverMap(0.2, 0.5)) == true, "the zone under the pointer lights up")
ns.SetOption("zoneHighlight", false)
expect(select(2, ns.HoverMap(0.2, 0.5)) == false, "with the option off no zone lights up")
ns.SetOption("zoneHighlight", true)
ns.SetOption("zoneNames", false)
expect(#ns.MapLabels() == 0, "with the option off the zones have no names")
ns.SetOption("zoneNames", true)
ns.ShowMap(37)
expect(#ns.MapLabels() == 0 and select(2, ns.HoverMap(0.2, 0.5)) == false, "a zone has no zone names and nothing to light up")
ForeverAtlasMap:Hide()

-- On the map of a zone the game names the whole zone as the picture to light up. The map does
-- not use it: it would put a bright colour over all of the map.
ns.ShowMap(37)
expect(select(2, ns.HoverMap(0.5, 0.5)) == false, "on the map of a zone, the zone itself does not light up")
-- The terrain: the images of the minimap over the map, zoomed in. The option is on at first.
expect(ns.GetOption("terrainDetail") == true and ns.MapTerrain() ~= nil, "the terrain is on at first")
ns.SetOption("terrainDetail", false)
expect(ns.MapTerrain() == nil, "no terrain while the option is off")
local maxBefore = ns.MapView().maxScale
ns.SetOption("terrainDetail", true)
local terrain = ns.MapTerrain()
-- The zone of the stand-in is 1000 yards wide, from 0 to 1000: the squares 30 and 31 each way.
-- The terrain goes on half a map past each edge, for the way to the next zone: the squares
-- 29 to 32 each way, as far as the table has an image for them.
local function terrainCount()
  local count = 0
  for column = 29, 32 do
    for row = 29, 32 do
      if ns.TERRAIN_IMAGES[0][column * 64 + row] then
        count = count + 1
      end
    end
  end
  return count
end
local allImages = terrainCount()
expect(allImages > 4, "the table has images past the edges of the zone of the stand-in")
expect(terrain ~= nil and terrain.columns == 2 and terrain.rows == 2 and terrain.images == allImages, "the zone of 1000 yards has two terrain images each way and more past its edges, got " .. tostring(terrain and terrain.images))
expect(terrain.world == 0 and terrain.first == ns.TERRAIN_IMAGES[0][30 * 64 + 30] and type(terrain.first) == "number", "an image has the number of the file of its square of the world, got " .. tostring(terrain.first))
-- A square of the world without an image is left out, and a world without images has no terrain.
local kept = ns.TERRAIN_IMAGES[0][31 * 64 + 31]
ns.TERRAIN_IMAGES[0][31 * 64 + 31] = nil
ns.SetOption("terrainDetail", false)
ns.SetOption("terrainDetail", true)
expect(ns.MapTerrain().images == allImages - 1, "a square without an image is left out, got " .. tostring(ns.MapTerrain().images))
ns.TERRAIN_IMAGES[0][31 * 64 + 31] = kept
local world = ns.TERRAIN_IMAGES[0]
ns.TERRAIN_IMAGES[0] = nil
ns.SetOption("terrainDetail", false)
ns.SetOption("terrainDetail", true)
expect(ns.MapTerrain() == nil, "a world without images has no terrain")
ns.TERRAIN_IMAGES[0] = world
ns.SetOption("terrainDetail", false)
ns.SetOption("terrainDetail", true)
-- Far enough in for one and a half screen units for each pixel of a terrain image.
expect(ns.MapView().maxScale >= maxBefore and ns.MapView().maxScale >= 1.5 * 256 / (1000 / 1.875 / 1000 * 1002) - 0.001, "with the terrain the map zooms in far enough for the pixels of the terrain, got " .. ns.MapView().maxScale)
expect(terrain.alpha == 0, "with the whole map in the window the terrain does not show")
ns.ZoomMap(100)
expect(ns.MapTerrain().alpha == 1, "zoomed all the way in, the terrain shows in full")
ns.ZoomMap(-100)
ns.ShowMap(13)
expect(ns.MapTerrain() ~= nil and ns.MapTerrain().images == allImages, "the continent of the stand-in has the same images")
-- From zone to zone. Close enough for the terrain in full, the map moves past the edge of the
-- zone, and the zone that is there shows, with the same place in the middle.
ns.ShowMap(37)
-- The place search: the names that start with the text come first, then the shorter names; an
-- empty text finds nothing; Enter in the search box goes to the best place.
do
  expect(#ns.FindPlaces("") == 0, "an empty search finds nothing")
  expect(#ns.FindPlaces("zzz") == 0, "a text that is in no name finds nothing")
  local west = ns.FindPlaces("west")
  expect(#west == 1 and west[1].mapID == 52 and west[1].name == "Westfall", "the search finds Westfall, got " .. #west)
  local e = ns.FindPlaces("e")
  expect(e[1].mapID == 37 and e[2].mapID == 13 and e[3].mapID == 52, "the names that start with the text come first, then the shorter ones: " .. tostring(e[1] and e[1].name))
  ns.ShowMap(37)
  local search = ForeverAtlasMap.search
  search:SetText("westf")
  search:GetScript("OnTextChanged")(search, true)
  expect(ForeverAtlasSearch:IsShown() and ForeverAtlasMap.search == search, "the search box is in the map window")
  search:GetScript("OnEnterPressed")(search)
  expect(ns.MapView().mapID == 52 and search:GetText() == "", "Enter in the search box goes to the best place and clears the box")
  ns.ShowMap(37)
end
-- The zones beside the zone are drawn around it, where they lie on the continent: Westfall
-- is the east half, so it starts at the east edge of Elwynn Forest and is as wide.
do
  local around, under = ns.MapNeighbours()
  expect(under == 13, "the painting of the continent lies under the zone, for the land around it")
  expect(#around == 1 and around[1].mapID == 52, "the zone beside Elwynn Forest is drawn around it, got " .. #around)
  expect(math.abs(around[1].x0 - 1) < 0.0001 and math.abs(around[1].x1 - 2) < 0.0001 and math.abs(around[1].y0) < 0.0001 and math.abs(around[1].y1 - 1) < 0.0001,
    "Westfall lies east of Elwynn Forest, as wide and as high")
  T.slash("/fatlas", "status")
  expect(T.printed("the continent under it, 1 zones drawn around it"),"/fatlas status says how many zones are drawn around the map")
end
-- Where the pictures of all the land of a zone are known (RevealData.lua, by the art of the
-- map), the zone is drawn as its land on the painting of the continent, without its sheet.
do
  local _, _, stitched = ns.MapNeighbours()
  expect(stitched == false, "a zone whose land is not known keeps its own sheet")
  local artID, revealBefore = C_Map.GetMapArtID, ns.MAP_REVEAL
  expect(type(revealBefore) == "table" and next(revealBefore) ~= nil, "the pictures of the land of the zones are loaded")
  C_Map.GetMapArtID = function(mapID) return mapID == 37 and 9101 or mapID == 52 and 9102 or 0 end
  ns.MAP_REVEAL = { [9101] = { ["300:200:10:20"] = "771, 772" }, [9102] = { ["256:256:0:0"] = "773" } }
  ns.ShowMap(13)
  ns.ShowMap(37)
  _, _, stitched = ns.MapNeighbours()
  expect(stitched == true, "a zone whose land is known is drawn as its land, without its sheet")
  T.slash("/fatlas", "status")
  expect(T.printed("all its land drawn without its sheet"), "/fatlas status says that the zone is drawn without its sheet")
  expect(ns.PanMapTo(1.03, 0.5) == true and ns.MapView().mapID == 52 and select(3, ns.MapNeighbours()) == true, "and so is the next zone after the map went to it")
  expect(ns.PanMapTo(-0.03, 0.5) == true and ns.MapView().mapID == 37, "and back")
  C_Map.GetMapArtID, ns.MAP_REVEAL = artID, revealBefore
  ns.ShowMap(13)
  ns.ShowMap(37)
end
-- The map goes past the edge at any zoom, also with the whole zone in the window: the map
-- changes to the zone that was drawn there, at the same place and the same size.
do
  local view = ns.MapView()
  local scaleBefore = view.scale
  expect(ns.PanMapTo(0.8, 0.5) == false and view.mapID == 37, "a move inside the whole zone keeps its map")
  local middle = view.x + 0.8 * view.width * view.scale -- the middle of the window
  expect(ns.PanMapTo(1.03, 0.5) == true and view.mapID == 52, "a move past the edge of the whole zone shows the next zone, got map " .. tostring(view.mapID))
  expect(view.scale == scaleBefore and ns.MapTerrain().alpha == 0, "and the next zone has the same size")
  expect(math.abs((middle - view.x) / (view.width * view.scale) - 0.03) < 0.0001, "and the place that was in the middle is still there")
  expect(#ns.MapNeighbours() == 1 and ns.MapNeighbours()[1].mapID == 37 and math.abs(ns.MapNeighbours()[1].x1) < 0.0001, "now Elwynn Forest is drawn beside Westfall, to the west")
  expect(ns.PanMapTo(-0.03, 0.5) == true and view.mapID == 37, "and back")
  ns.ShowMap(13)
  expect(#ns.MapNeighbours() == 0, "a continent has no zones drawn around it")
  ns.ShowMap(37)
end
while ns.MapView().scale / ns.MapView().minScale < 3.2 do
  ns.ZoomMap(1)
end
expect(ns.MapTerrain().alpha == 1, "close enough, the terrain shows in full")
local scaleBefore = ns.MapView().scale
expect(ns.PanMapTo(0.5, 0.5) == false and ns.MapView().mapID == 37, "a move inside the zone keeps its map")
expect(ns.PanMapTo(1.03, 0.5) == true and ns.MapView().mapID == 52, "past the east edge of Elwynn Forest the map shows Westfall, got map " .. tostring(ns.MapView().mapID))
local crossed = ns.MapView()
expect(math.abs(crossed.scale - scaleBefore) < 0.0001, "the land keeps its size from zone to zone")
expect(ForeverAtlasMap.title:GetText() == "Westfall", "the window has the name of the new zone")
expect(ns.PanMapTo(-0.03, 0.5) == true and ns.MapView().mapID == 37, "and back past the west edge of Westfall the map shows Elwynn Forest again")
-- North of the zones the continent has nothing: the map stays, with its edge in the middle.
expect(ns.PanMapTo(0.5, -0.2) == false and ns.MapView().mapID == 37, "where the continent has no zone the map stays")
T.slash("/fatlas", "status")
expect(T.printed("from zone to zone: on map 13") and T.printed("the last try: "), "/fatlas status says where the zone is on its continent and how the last move past the edge went")
-- Zoomed all the way in, the two maps have the same closest zoom: the map still goes across.
ns.ZoomMap(100)
expect(ns.PanMapTo(1.03, 0.5) == true and ns.MapView().mapID == 52, "at the closest zoom the map goes to the next zone too")
expect(ns.PanMapTo(-0.03, 0.5) == true and ns.MapView().mapID == 37, "and back")
-- A next zone that is smaller on the continent keeps the size of the land: its map is half
-- as far in.
do
  local rectOnMap = C_Map.GetMapRectOnMap
  C_Map.GetMapRectOnMap = function(mapID, onMapID)
    if onMapID == 13 and mapID == 52 then
      return 0.5, 0.75, 0.25, 0.75
    end
    return rectOnMap(mapID, onMapID)
  end
  ns.ShowMap(37)
  while ns.MapView().scale / ns.MapView().minScale < 3.2 do
    ns.ZoomMap(1)
  end
  local scaleBefore = ns.MapView().scale
  expect(ns.PanMapTo(1.03, 0.5) == true and ns.MapView().mapID == 52, "the map goes to a smaller next zone too, got map " .. tostring(ns.MapView().mapID))
  expect(math.abs(ns.MapView().scale - scaleBefore / 2) < 0.0001, "and the land keeps its size there, got " .. ns.MapView().scale .. " after " .. scaleBefore)
  expect(ns.PanMapTo(-0.03, 0.5) == true and ns.MapView().mapID == 37, "and back from the smaller zone")
  C_Map.GetMapRectOnMap = rectOnMap
end
-- Zones with their own world places, as in the game (north and west, in yards, falling to the
-- south and east): Elwynn Forest the west half, Westfall the east half. The new zone is placed
-- by the world, so the terrain stays where it is under the window.
do
  local worldPos = C_Map.GetWorldPosFromMapPos
  C_Map.GetWorldPosFromMapPos = function(mapID, position)
    local left = mapID == 52 and 0.5 or 0
    local wide = (mapID == 37 or mapID == 52) and 0.5 or 1
    return 0, CreateVector2D(1000 - position.y * 1000, 1000 - (left + position.x * wide) * 1000)
  end
  ns.ShowMap(13)
  ns.ShowMap(37)
  while ns.MapView().scale / ns.MapView().minScale < 3.2 do
    ns.ZoomMap(1)
  end
  ns.PanMapTo(0.5, 0.5)
  local view = ns.MapView()
  local half = view.x + 0.5 * view.width * view.scale -- the middle of the window
  local perYard = view.scale * view.width / 500
  expect(ns.PanMapTo(1.03, 0.4) == true and view.mapID == 52, "with world places of their own the map goes to the next zone, got map " .. tostring(view.mapID))
  local middleX = (half - view.x) / (view.width * view.scale)
  expect(math.abs(middleX - 0.03) < 0.0005,"the same place of the world is in the middle of the window, got " .. middleX)
  expect(math.abs(view.scale * view.width / 500 - perYard) < 0.0001, "and a yard keeps its size")
  T.slash("/fatlas", "status")
  expect(T.printed("placed by the world"), "/fatlas status says that the world placed the new zone")
  expect(ns.PanMapTo(-0.03, 0.4) == true and view.mapID == 37, "and back by the world")
  C_Map.GetWorldPosFromMapPos = worldPos
  ns.ShowMap(13)
  ns.ShowMap(37)
end
ns.SetOption("terrainDetail", false)
ns.ShowMap(37)
ns.ZoomMap(100)
expect(ns.PanMapTo(1.03, 0.5) == true and ns.MapView().mapID == 52, "without the terrain the map goes past the edge of the zone too")
expect(ns.PanMapTo(-0.03, 0.5, true) == true and ns.MapView().mapID == 37, "and back, with the mouse button held")
ns.SetOption("terrainDetail", true)
ns.ZoomMap(-100)
ns.ShowMap(13)
ns.SetOption("terrainDetail", false)
expect(ns.MapTerrain() == nil, "with the option off again there is no terrain")
ns.SetOption("terrainDetail", true)
ns.ShowMap(37)
ForeverAtlasMap:Hide()

-- /fatlas status says what the map shows, and an error inside the map is printed, not lost.
ns.ShowMap(37)
T.slash("/fatlas", "status")
expect(T.printed("map 37 %(Elwynn Forest%), window open") and T.printed("art: 1002 by 668 pixels, 2 layers, 24 images") and T.printed("no error inside the map so far"), "/fatlas status prints the map, its art and that there is no error")
-- A kind of pin that fails does not take the map away: the other pins stay, and the error is printed.
local broken = ns.MAP_KINDS[1].find
ns.MAP_KINDS[1].find = function() error("broken on purpose") end
-- The error also goes to the error handler of the game, which the test would count: for this
-- step the handler only counts.
local handler, handled = H.onError, 0
H.onError = function() handled = handled + 1 end
ns.RefreshMapPins()
H.onError = handler
expect(handled == 1, "the error of the broken kind goes to the error handler of the game once, got " .. handled)
expect(count("flight") == 1 and count("areaPOIs") == 0, "with one kind broken, the other kinds still have their pins")
expect(T.printed("map error in the pins of Towns and landmarks: .*broken on purpose"), "the error of the broken kind is printed in the chat")
ns.MAP_KINDS[1].find = broken
ns.RefreshMapPins()
expect(count("areaPOIs") == 2, "and the kind is back when it works again")
ForeverAtlasMap:Hide()

-- /fatlas status also says what the game draws: each part with its place on the screen.
ns.ShowMap(37)
T.slash("/fatlas", "status")
expect(T.printed("what the game draws") and T.printed("layer 1 image 1: visible") and T.printed("pin 1 %("), "/fatlas status lists the drawn parts of the map")
ForeverAtlasMap:Hide()

---------------------------------------------------------------------------------------------------
-- PINS AND MARKERS. This block belongs to the session of the pins (MapKinds.lua): the kinds
-- that came after the first ones. It uses nothing of the blocks above but `count`.
do
  local function pinOf(kind, index)
    local found = 0
    for _, pin in ipairs(ns.MapPins()) do
      if pin.kind == kind then
        found = found + 1
        if found == (index or 1) then
          return pin
        end
      end
    end
  end
  -- The lines of the tooltip of a pin, joined with " | ".
  local function tooltipOf(pin)
    local seen = {}
    pin.data.tooltip({ AddLine = function(_, line) seen[#seen + 1] = line end })
    return table.concat(seen, " | ")
  end
  ns.ShowMap(37)
  -- An event of the map, with the time that is left.
  expect(count("events") == 1 and pinOf("events").data.look.atlas == "poi-event" and math.abs(pinOf("events").x - 0.7) < 0.001, "the event of the map has a pin with its own icon, got " .. count("events"))
  expect(tooltipOf(pinOf("events")) == "Harvest Festival | Event | A feast | 1 h 30 min left", "the event says how long it lasts, got " .. tooltipOf(pinOf("events")))
  T.world.eventSeconds = 600
  expect(tooltipOf(pinOf("events")):find("| 10 min left", 1, true), "and ten minutes before its end, got " .. tooltipOf(pinOf("events")))
  T.world.eventSeconds = nil
  expect(count("areaPOIs") == 2, "an event is not among the towns and landmarks")
  -- A bonus objective: the one of this map, not the one that the game lists for a map under it.
  expect(count("taskQuests") == 1 and tooltipOf(pinOf("taskQuests")):find("^Clear the Fields | ") and pinOf("taskQuests").data.task == 900, "the bonus objective of this map has a pin with its name, got " .. count("taskQuests"))
  -- The place that a guard pointed out comes with the event of the game, and has its picture of the sheet of map icons.
  -- Map.lua hears the event and reads the pins again at its next update, not in the event itself.
  expect(count("guide") == 0, "no guard has pointed out a place yet")
  T.world.guide = true
  T.fire("DYNAMIC_GOSSIP_POI_UPDATED")
  T.advance(1)
  local guide = pinOf("guide")
  expect(count("guide") == 1 and guide and guide.data.look.texture == "Interface/Minimap/POIIcons" and math.abs(guide.data.look.coords[1] - 0.6) < 0.001, "the place that a guard pointed out is on the map soon after the event, got " .. count("guide"))
  expect(guide and tooltipOf(guide) == "Goldshire Smithy | A guard showed you this place", "and says what it is, got " .. (guide and tooltipOf(guide) or "no pin"))
  T.world.guide = nil
  T.fire("DYNAMIC_GOSSIP_POI_UPDATED")
  T.advance(1)
  expect(count("guide") == 0, "and is gone when the game drops it")
  -- The way to the quest that the player follows, when its goal is on another map.
  expect(count("questWaypoint") == 0, "a quest with its goal on this map has no way to show")
  T.world.questWaypoint = true
  T.fire("SUPER_TRACKING_CHANGED")
  T.advance(1)
  local way = pinOf("questWaypoint")
  expect(count("questWaypoint") == 1 and math.abs(way.x - 0.85) < 0.001 and way.data.wayTo == 176, "the next step to the followed quest is on the map, got " .. count("questWaypoint"))
  local opened = H.count("open quest")
  H.run(way.frame, "OnMouseUp", "LeftButton")
  expect(H.count("open quest") == opened + 1, "a click on it opens the quest")
  T.world.questWaypoint = nil
  ns.ShowMap(37)
  expect(count("questWaypoint") == 0, "without a next step there is no pin")
  -- The bosses of a dungeon, the defeated one in grey.
  ns.ShowMap(52)
  expect(count("bosses") == 2, "both bosses of the map have a pin, got " .. count("bosses"))
  expect(tooltipOf(pinOf("bosses", 1)) == "Dungeon boss | Not defeated yet" and pinOf("bosses", 1).data.look.color == nil, "a boss that lives has the plain icon")
  expect(tooltipOf(pinOf("bosses", 2)) == "Dungeon boss | Defeated" and pinOf("bosses", 2).data.look.color[1] == 0.5, "a defeated boss is grey and says so")
  ns.ShowMap(37)
  expect(count("bosses") == 0, "a map without bosses has none")
  -- The other places that the game lists: the quest hub and the pet tamer. The abbey is a quest
  -- hub too, and stays with the landmarks.
  expect(count("otherPlaces") == 2 and count("areaPOIs") == 2, "the quest hub and the pet tamer have a pin, and a landmark is not there twice, got " .. count("otherPlaces"))
  expect(tooltipOf(pinOf("otherPlaces", 1)) == "Eastvale Logging Camp | Quest hub | Quests" and pinOf("otherPlaces", 1).data.look.atlas == "poi-hub", "the quest hub says what it is, got " .. tooltipOf(pinOf("otherPlaces", 1)))
  expect(tooltipOf(pinOf("otherPlaces", 2)) == "Julia Stevens | Pet tamer" and math.abs(pinOf("otherPlaces", 2).x - 0.3) < 0.001, "and so does the pet tamer, got " .. tooltipOf(pinOf("otherPlaces", 2)))
  ns.SetOption("show_otherPlaces", false)
  expect(count("otherPlaces") == 0, "with the option off they are gone")
  ns.SetOption("show_otherPlaces", true)
  -- A dead player: the corpse, and the spirit healer once the game names the place.
  T.world.dead = true
  ns.RefreshMapPins()
  expect(count("corpse") == 1 and not pinOf("corpse").data.release, "without a place to come back to life, only the corpse shows")
  T.world.release = true
  ns.RefreshMapPins()
  local healer = pinOf("corpse", 2)
  expect(count("corpse") == 2 and healer.data.release == true and math.abs(healer.x - 0.3) < 0.001 and tooltipOf(healer):find("^Spirit healer | "), "the spirit healer shows where the spirit comes back, got " .. count("corpse"))
  T.world.dead = false
  ns.RefreshMapPins()
  expect(count("corpse") == 0, "alive again, neither shows")
  T.world.release = nil
  -- The tooltip of a quest has its objectives as they are now, the finished ones marked.
  local objective = tooltipOf(pinOf("questObjectives"))
  expect(objective:find(" | Hogger slain: %d+/8 | Click to open the quest$") and not objective:find("In progress", 1, true), "a quest pin lists the objectives of the quest, got " .. objective)
  T.world.questItems = true
  objective = tooltipOf(pinOf("questObjectives"))
  expect(objective:find(" | Gnoll Paw: 3/8 | Done: 8/8 Linen Cloth | ", 1, true), "the same pin follows the quest, with the finished objective marked, got " .. objective)
  T.world.questItems = nil
  expect(tooltipOf(pinOf("questTurnIns")):find(" | Ready to turn in | Click to open the quest$"), "a quest that is ready says so, without its objectives, got " .. tooltipOf(pinOf("questTurnIns")))

  -- NPCs that the player has used: the game does not give their places, the addon remembers them.
  expect(count("npcs") == 0 and ns.CountNpcs() == 0, "no NPC is known at first")
  T.world.npc = "Brog Hamfist"
  T.fire("MERCHANT_SHOW")
  local known = ForeverAtlasDB.npcs[37]
  expect(known and #known == 1 and known[1].name == "Brog Hamfist" and known[1].roles.vendor and known[1].roles.repair, "a vendor that repairs is remembered with both roles")
  expect(math.abs(known[1].x - 42) < 0.01 and math.abs(known[1].y - 65) < 0.01, "at the place of the player, got " .. tostring(known[1].x) .. ", " .. tostring(known[1].y))
  expect(count("npcs") == 1 and tooltipOf(pinOf("npcs")):find("^Brog Hamfist | Repairer, Vendor | Last used: "), "the vendor is on the map at once, got " .. (pinOf("npcs") and tooltipOf(pinOf("npcs")) or "no pin"))
  T.fire("TRAINER_SHOW")
  expect(#known == 1 and count("npcs") == 1 and tooltipOf(pinOf("npcs")):find("| Trainer, Repairer, Vendor |", 1, true), "the same NPC with one more role stays one pin, got " .. tooltipOf(pinOf("npcs")))
  -- The icon: the one of the game for the role if the client has it, else a dot of the colour of the role.
  local red, green = pinOf("npcs").frame.icon:GetVertexColor()
  if C_Texture.GetAtlasInfo("Profession") then
    expect(red == 1 and green == 1, "an icon of the game keeps its own colours")
  else
    expect(math.abs(red - 0.5) < 0.01 and green == 1, "without the icon of the game the pin is a dot in the colour of the role, got " .. tostring(red))
  end
  -- A click sets a waypoint to the NPC.
  local before = #ForeverAtlasCharDB.waypoints
  H.run(pinOf("npcs").frame, "OnMouseUp", "LeftButton")
  local newest = ForeverAtlasCharDB.waypoints[before + 1]
  expect(newest ~= nil and newest.label == "Brog Hamfist" and newest.mapID == 37, "a click on the NPC sets a waypoint with its name")
  ns.ClearWaypoints()
  -- A mailbox has no NPC: one entry for each place.
  T.world.npc = nil
  T.fire("MAIL_SHOW")
  T.fire("MAIL_SHOW")
  expect(#known == 2 and known[2].name == "Mailbox" and known[2].roles.mailbox, "a mailbox is remembered once, got " .. #known)
  -- A quest from an item has no NPC, and in a fight the game hides the name: nothing is remembered.
  T.fire("QUEST_DETAIL")
  T.world.secret = true
  T.world.npc = "Hidden One"
  T.fire("GOSSIP_SHOW")
  T.world.secret = false
  expect(#known == 2, "without an NPC, or with a hidden name, nothing is remembered, got " .. #known)
  T.fire("GOSSIP_SHOW")
  expect(#known == 3 and known[3].roles.talk, "out of the fight the NPC is remembered")
  T.world.npc = nil
  -- The places of Forever Compass: the one that this addon remembers too is left out while its own kind is on.
  local compass = _G["ForeverCompassDB"]
  _G["ForeverCompassDB"] = { places = { vendor = { { mapID = 37, x = 0.42, y = 0.65, name = "Brog Hamfist" }, { mapID = 37, x = 0.1, y = 0.3, name = "Far Vendor" } } } }
  ns.RefreshMapPins()
  expect(count("learned") == 1 and tooltipOf(pinOf("learned")):find("^Far Vendor | Vendor | "), "a place that both addons know has one pin, got " .. count("learned"))
  ns.SetOption("show_npcs", false)
  expect(count("npcs") == 0 and count("learned") == 2, "with the NPCs off they are gone, and Forever Compass has both of its places")
  ns.SetOption("show_npcs", true)
  _G["ForeverCompassDB"] = compass
  -- The place of an NPC is the average of its visits: the old place 40 and the new one 42 give 41.
  known[1].x, known[1].n, known[1].t = 40, nil, (known[1].t or 0) - 3600
  T.world.npc = "Brog Hamfist"
  T.fire("MERCHANT_SHOW")
  expect(math.abs(known[1].x - 41) < 0.01 and known[1].n == 2, "the place is the average of two visits, got " .. tostring(known[1].x))
  -- An innkeeper that sells food is an inn as well; a talk-only NPC is remembered but not drawn.
  T.world.npc = "Innkeeper Test"
  T.fire("MERCHANT_SHOW")
  local inn = known[#known]
  expect(inn.name == "Innkeeper Test" and inn.roles.inn and inn.roles.vendor and count("npcs") == 3, "an innkeeper that sells is remembered as an inn too, got " .. count("npcs"))
  -- A quest giver that is only that is remembered, but not drawn: it would look like an open quest.
  T.world.npc = "Quest Giver Test"
  T.fire("QUEST_GREETING")
  local giver = known[#known]
  expect(giver.name == "Quest Giver Test" and giver.roles.quests and count("npcs") == 3 and not tooltipOf(pinOf("npcs")):find("Quest Giver Test", 1, true), "a quest giver that is only that is remembered and not drawn, got " .. count("npcs"))
  T.world.npc = nil
  -- Forgetting them: five are known, three are drawn (the talk-only and the quest-only one are not).
  expect(ns.CountNpcs() == 5 and count("npcs") == 3, "five are known, three drawn, got " .. ns.CountNpcs() .. " and " .. count("npcs"))
  ns.ForgetNpcs()
  expect(ns.CountNpcs() == 0 and count("npcs") == 0, "after forgetting them none is left")
  ForeverAtlasMap:Hide()
end

-- The map window: opacity, scale, a size and a place kept for the next time; the land that is
-- not explored; the areas of the quest objectives; the minimap.
do
  ns.ShowMap(37)
  local window = ForeverAtlasMap
  ns.SetOption("mapOpacity", 55)
  ns.SetOption("mapScale", 130)
  expect(math.abs(window:GetAlpha() - 0.55) < 0.001 and math.abs(window:GetScale() - 1.3) < 0.001, "the options set the opacity and the scale of the map window")
  ns.SetOption("mapOpacity", 10)
  expect(ns.GetOption("mapOpacity") == 30, "the opacity of the window has a least value, got " .. tostring(ns.GetOption("mapOpacity")))
  ns.SetOption("mapOpacity", 100)
  ns.SetOption("mapScale", 100)
  expect(window.grip ~= nil and window.grip:IsShown(), "the window can change its size from its corner")
  H.run(window.grip, "OnMouseDown", "LeftButton")
  window:SetSize(900, 600)
  H.run(window.grip, "OnMouseUp", "LeftButton")
  local saved = ForeverAtlasDB.frames.map
  expect(type(saved) == "table" and saved[5] == 900 and saved[6] == 600, "the size of the window is kept")
  ns.ResetMapWindow()
  expect(ForeverAtlasDB.frames.map == nil and window:GetWidth() ~= 900, "the window goes back to its first size")

  -- The land that is not explored: on, off, and as bright as the rest.
  ns.ShowMap(52)
  local _, _, stitched = ns.MapNeighbours()
  ns.SetOption("revealAll", false)
  local _, _, after = ns.MapNeighbours()
  expect(after == false, "without the land that is not explored a zone keeps its own sheet")
  ns.SetOption("revealAll", true)
  local _, _, again = ns.MapNeighbours()
  expect(again == stitched, "with it the zone is drawn as before")
  ns.SetOption("revealBright", true)
  ns.SetOption("revealBright", false)

  -- The areas of the quest objectives.
  ns.ShowMap(37)
  ns.RefreshMapPins()
  T.slash("/fatlas", "status")
  expect(T.printed("quest areas: "), "/fatlas status says how many quest areas are drawn")
  local drawn = ns.MapView().questAreas
  expect(type(drawn) == "number", "the quest areas are counted, got " .. tostring(drawn))
  ns.SetOption("questAreas", false)
  expect(ns.MapView().questAreas == 0, "with the option off no quest area is drawn")
  ns.SetOption("questAreas", true)
  ForeverAtlasMap:Hide()

  -- The minimap: nothing changes until an option is on, and everything goes back.
  local state = ns.MinimapState()
  expect(not state.square and not state.scale and state.coords == nil, "with the options off the minimap is not touched")
  ns.SetOption("minimapSquare", true)
  ns.SetOption("minimapScale", 140)
  ns.SetOption("minimapCoords", true)
  state = ns.MinimapState()
  if state.owner then
    expect(not state.square, "another addon that shapes the minimap keeps it")
  else
    expect(state.square and state.scale and GetMinimapShape and GetMinimapShape() == "SQUARE", "a square, larger minimap tells other addons its shape")
    expect(type(state.coords) == "string" and state.coords:find("^%d+%.%d, %d+%.%d$"), "the coordinates show under the minimap, got " .. tostring(state.coords))
  end
  ns.SetOption("minimapSquare", false)
  ns.SetOption("minimapScale", 100)
  ns.SetOption("minimapCoords", false)
  state = ns.MinimapState()
  expect(not state.square and not state.scale and state.coords == nil and GetMinimapShape == nil, "turned off, the minimap is given back")
end
