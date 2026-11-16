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
-- The arrow follows the waypoint.
T.advance(2)
-- A second waypoint, and a waypoint without a label.
T.slash("/way", "10 10")
expect(#waypoints == 2, "a second waypoint is added")
T.slash("/way", "")
T.slash("/way", "nonsense")
expect(#waypoints == 2, "a /way without coordinates adds nothing")
-- A waypoint at the place of the player: arriving removes it.
ns.SetOption("arrivalYards", 50)
ns.AddWaypoint(37, 42, 65, "Here")
T.advance(1)
ns.SetOption("arrivalYards", 5)
T.slash("/fatlas", "clear")

-- Visited areas and coordinates.
T.fire("ZONE_CHANGED")
T.fire("ZONE_CHANGED_NEW_AREA")
T.advance(2)
T.slash("/fatlas", "")
