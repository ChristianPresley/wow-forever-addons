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
-- The icon is the game's: an atlas where the game names one, else a part of the sheet of map icons.
expect(pinNamed("questTurnIns").data.look.atlas == "QuestTurnin" and pinNamed("questGivers").data.look.atlas == "QuestNormal", "quest pins have the icons of the game's map")
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
ns.ZoomMap(-100)
-- Each kind can be turned off.
ns.SetOption("show_flight", false)
expect(count("flight") == 0 and count("areaPOIs") == 2, "with flight masters off they are gone, and the rest stays")
ns.SetOption("show_flight", true)
expect(count("flight") == 1, "and back with the option on")
-- The menu of the button "Show" has a checkbox for each kind.
H.menus = {}
H.click(ForeverAtlasMap.show, "LeftButton", false)
expect(#H.menus == 1 and #H.menus[1] == #ns.MAP_KINDS + 5, "the menu has a checkbox for each kind and five more, got " .. tostring(H.menus[1] and #H.menus[1]))
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
-- The terrain (a trial, off at first): the images of the minimap over the map, zoomed in.
expect(ns.MapTerrain() == nil, "no terrain while the option is off")
local maxBefore = ns.MapView().maxScale
ns.SetOption("terrain", true)
local terrain = ns.MapTerrain()
-- The zone of the stand-in is 1000 yards wide, from 0 to 1000: the squares 30 and 31 each way.
expect(terrain ~= nil and terrain.columns == 2 and terrain.rows == 2 and terrain.images == 4, "the zone of 1000 yards needs two terrain images each way, got " .. tostring(terrain and terrain.images))
expect(terrain.folder == "Azeroth" and terrain.first == "World\\Minimaps\\Azeroth\\map30_30", "an image has the name of its square of the world, got " .. tostring(terrain.first))
-- Far enough in for one and a half screen units for each pixel of a terrain image.
expect(ns.MapView().maxScale >= maxBefore and ns.MapView().maxScale >= 1.5 * 256 / (1000 / 1.875 / 1000 * 1002) - 0.001, "with the terrain the map zooms in far enough for the pixels of the terrain, got " .. ns.MapView().maxScale)
expect(terrain.alpha == 0, "with the whole map in the window the terrain does not show")
ns.ZoomMap(100)
expect(ns.MapTerrain().alpha == 1, "zoomed all the way in, the terrain shows in full")
ns.ZoomMap(-100)
ns.ShowMap(13)
expect(ns.MapTerrain() ~= nil and ns.MapTerrain().images == 4, "the continent of the stand-in has the same four images")
ns.SetOption("terrain", false)
expect(ns.MapTerrain() == nil, "with the option off again there is no terrain")
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
  expect(count("guide") == 0, "no guard has pointed out a place yet")
  T.world.guide = true
  T.fire("DYNAMIC_GOSSIP_POI_UPDATED")
  local guide = pinOf("guide")
  expect(count("guide") == 1 and guide.data.look.texture == "Interface/Minimap/POIIcons" and math.abs(guide.data.look.coords[1] - 0.6) < 0.001, "the place that a guard pointed out is on the map at once, got " .. count("guide"))
  expect(tooltipOf(guide) == "Goldshire Smithy | A guard showed you this place", "and says what it is, got " .. tooltipOf(guide))
  T.world.guide = nil
  T.fire("DYNAMIC_GOSSIP_POI_UPDATED")
  expect(count("guide") == 0, "and is gone when the game drops it")
  -- The way to the quest that the player follows, when its goal is on another map.
  expect(count("questWaypoint") == 0, "a quest with its goal on this map has no way to show")
  T.world.questWaypoint = true
  T.fire("SUPER_TRACKING_CHANGED")
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
  -- Forgetting them.
  expect(ns.CountNpcs() == 3 and count("npcs") == 3, "three are known, got " .. ns.CountNpcs())
  ns.ForgetNpcs()
  expect(ns.CountNpcs() == 0 and count("npcs") == 0, "after forgetting them none is left")
  ForeverAtlasMap:Hide()
end
