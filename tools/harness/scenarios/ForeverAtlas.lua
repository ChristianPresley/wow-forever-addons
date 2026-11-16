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
ns.ZoomMap(-100)
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
expect(view.scale == view.minScale, "the zoom stops with the whole map in the window")
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
ns.ZoomMap(-100)
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
