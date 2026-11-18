-- What Forever Gather does, with checks. T is the test table of the driver (see driver.lua).
local T = ...
local H, ns, expect = T.H, T.ns, T.expect

-- The player stands on map 37 at 0.42, 0.65 (04-world.lua); the map is 1000 by 1000 yards.
expect(ns.CountNodes() == 0, "no node is known at first")
expect(ns.KindOfSpell(2366) == "herb" and ns.KindOfSpell(2575) == "ore" and ns.KindOfSpell(7620) == "fish" and ns.KindOfSpell(3365) == "treasure", "the gathering spells have their kinds")
expect(ns.KindOfSpell(133) == nil, "another spell is no gather")

-- An herb: the sent cast names the node, its success records it.
T.fire("UNIT_SPELLCAST_SENT", "player", "Peacebloom", "Cast-1", 2366)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 2366)
local nodes = ns.VisibleNodes(37)
expect(#nodes == 1 and nodes[1].name == "Peacebloom" and nodes[1].kind == "herb", "the herb is remembered with its name")
expect(math.abs(nodes[1].x - 0.42) < 1e-6 and math.abs(nodes[1].y - 0.65) < 1e-6, "the herb is where the player stands")

-- The same herb again is the same node, gathered twice.
T.fire("UNIT_SPELLCAST_SENT", "player", "Peacebloom", "Cast-2", 2366)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 2366)
expect(#ns.VisibleNodes(37) == 1 and ns.VisibleNodes(37)[1].count == 2, "a second gather at the same place counts on the same node")

-- A failed cast records nothing; a cast of another unit records nothing.
T.fire("UNIT_SPELLCAST_SENT", "player", "Copper Vein", "Cast-3", 2575)
T.fire("UNIT_SPELLCAST_FAILED", "player", "Cast-3", 2575)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-4", 2575)
expect(ns.CountNodes() == 1, "a failed cast and a cast of another unit add no node")

-- Ore, fish (no target name) and a chest.
T.fire("UNIT_SPELLCAST_SENT", "player", "Copper Vein", "Cast-5", 2575)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", 2575)
T.fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-6", 7620)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-6", 7620)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-7", 3365)
local total, counts = ns.CountNodes()
expect(total == 4 and counts.ore == 1 and counts.fish == 1 and counts.treasure == 1, "ore, fish and a chest are learned, got " .. total)
local names = {}
for _, node in ipairs(ns.VisibleNodes(37)) do
  names[node.kind] = node.name
end
expect(names.fish == "Fishing spot" and names.treasure == "Treasure", "a node without a target name has the name of its kind")

-- Filters by kind.
ns.SetOption("herb", false)
expect(#ns.VisibleNodes(37) == 3, "hidden herbs do not show")
T.slash("/fgather", "herb")
expect(ns.GetOption("herb") == true and #ns.VisibleNodes(37) == 4, "/fgather herb shows herbs again")

-- Filters by skill: a node learned at skill 1 is trivial at skill 101.
ForeverGatherDB.names["Peacebloom"].skill = 1
ns.SetOption("minSkill", 50)
expect(#ns.VisibleNodes(37) == 3, "a node learned below the lowest skill does not show")
ns.SetOption("minSkill", 0)
expect(ns.SetOption("minSkill", 9999) and ns.GetOption("minSkill") == 300, "the lowest skill stays at 300 or lower")
ns.SetOption("minSkill", 0)
expect(ns.SetOption("noSuchOption", 1) == false, "an option that does not exist is refused")

-- The world map: its pins are the visible nodes of the shown map.
-- The canvas of the game has the size of the map art; the stand-in's has none until set.
WorldMapFrame:GetCanvas():SetSize(1002, 668)
WorldMapFrame:Show()
ns.RefreshWorldPins()
T.advance(1)
expect(ns.WorldPinCount() == 4, "the world map of Elwynn Forest has a pin for each node, got " .. ns.WorldPinCount())
ns.SetOption("worldMap", false)
ns.RefreshWorldPins()
expect(ns.WorldPinCount() == 0, "with the world map off it has no pins")
ns.SetOption("worldMap", true)

-- The minimap: a node at the player shows at the centre; one far away does not show.
local node = { kind = "herb", name = "Peacebloom", x = 0.42, y = 0.65, count = 1 }
local x, y = ns.MinimapOffset(node, 0.42, 0.65, 1000, 1000, 150, 70)
expect(x == 0 and y == 0, "a node at the player is at the centre of the minimap")
node.x = 0.47 -- 50 yards east
x, y = ns.MinimapOffset(node, 0.42, 0.65, 1000, 1000, 100, 70)
expect(math.abs(x - 35) < 1e-6 and math.abs(y) < 1e-6, "a node 50 yards east is half the radius to the right")
x, y = ns.MinimapOffset(node, 0.42, 0.65, 1000, 1000, 100, 70, math.pi / 2)
expect(math.abs(x) < 1e-6 and math.abs(y + 35) < 1e-6, "facing west, a node to the east is behind: below the centre")
node.x = 0.9
expect(ns.MinimapOffset(node, 0.42, 0.65, 1000, 1000, 100, 70) == nil, "a node beyond the radius is not on the minimap")
local width, height = ns.MapYards(37)
expect(width == 1000 and height == 1000, "the map is 1000 by 1000 yards in the stand-in")
T.advance(1)
expect(ns.MinimapPinCount() == 4, "the minimap has the four nodes at the player, got " .. ns.MinimapPinCount())

-- The commands.
T.slash("/fgather", "")
expect(T.printed("4 nodes learned"), "/fgather says how many nodes are known")
T.slash("/fgather", "size 20")
expect(ns.GetOption("size") == 20, "/fgather size 20 sets the size")
T.slash("/fgather", "size")
T.slash("/fgather", "trivial")
expect(ns.GetOption("hideTrivial") == true, "/fgather trivial hides trivial nodes")
T.slash("/fgather", "trivial")
T.slash("/fgather", "skill 10")
T.slash("/fgather", "skill 0")
T.slash("/fgather", "minimap")
T.slash("/fgather", "minimap")
T.slash("/fgather", "map")
T.slash("/fgather", "map")
T.slash("/fgather", "help")
T.slash("/fgather", "forget gems")
expect(T.printed("No kind gems"), "forgetting a kind that does not exist is refused")
T.slash("/fgather", "forget fish")
expect(select(2, ns.CountNodes()).fish == nil and ns.CountNodes() == 3, "/fgather forget fish forgets only the fish")
T.advance(1)
H.world.zone = nil
T.slash("/fgather", "options")
