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

-- Ore and fish (no target name).
T.fire("UNIT_SPELLCAST_SENT", "player", "Copper Vein", "Cast-5", 2575)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", 2575)
T.fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-6", 7620)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-6", 7620)
expect(ns.CountNodes() == 3, "ore and a fishing spot are learned")

-- A thing opened with "Opening" is a chest only when its loot says so. The loot window of the
-- stand-in is H.world.loot: a list of { name, quest, questID }.
local function last()
  return ForeverGatherDB.last.gather
end
-- A tombstone of a quest: the cast succeeds and no loot window comes.
T.fire("UNIT_SPELLCAST_SENT", "player", "Yuriv's Tombstone", "Cast-7", 3365)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-7", 3365)
expect(ns.CountNodes() == 3, "a thing that is opened is no node before its loot shows")
expect(last().target == "Yuriv's Tombstone" and last().result:find("no loot window"), "the last cast says that no loot window came, got " .. tostring(last().result))
-- Loot much later is not the loot of that cast.
T.advance(10)
H.world.loot = { { name = "Linen Cloth", quest = false } }
T.fire("LOOT_READY", false)
expect(ns.CountNodes() == 3, "a loot window ten seconds after the cast records nothing")
-- A quest object: its loot is a quest item.
H.world.loot = { { name = "Deepmoss Egg", quest = true } }
T.fire("UNIT_SPELLCAST_SENT", "player", "Deepmoss Eggs", "Cast-8", 3365)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-8", 3365)
T.fire("LOOT_READY", false)
T.fire("LOOT_OPENED", false, false)
expect(ns.CountNodes() == 3, "a thing with a quest item as loot is no treasure")
expect(last().result:find("quest object"), "the last cast says that it was a quest object, got " .. tostring(last().result))
H.world.loot = { { name = "Linen Cloth", quest = false }, { name = "Stolen Silver", quest = false, questID = 1234 } }
expect(ns.LootKind() == "quest", "an item of a quest in the loot makes a quest object")
H.world.loot = {}
expect(ns.LootKind() == "empty", "a loot window without items is empty")
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 3365)
T.fire("LOOT_READY", false)
expect(ns.CountNodes() == 3 and last().result:find("empty"), "an empty loot window records nothing")
-- A chest: loot without a quest item. It has no target name here, so it has the name of its kind.
H.world.loot = { { name = "Linen Cloth", quest = false }, { name = "Minor Healing Potion", quest = false, questID = 0 } }
expect(ns.LootKind() == "chest", "loot without a quest item is a chest")
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-10", 3365)
T.fire("LOOT_READY", false)
T.fire("LOOT_OPENED", false, false)
expect(last().result == "recorded as treasure on map 37", "the last cast says where the chest was recorded, got " .. tostring(last().result))
local total, counts = ns.CountNodes()
expect(total == 4 and counts.ore == 1 and counts.fish == 1 and counts.treasure == 1, "ore, fish and a chest are learned, got " .. total)
local names = {}
for _, node in ipairs(ns.VisibleNodes(37)) do
  names[node.kind] = node.name
end
expect(names.fish == "Fishing spot" and names.treasure == "Treasure", "a node without a target name has the name of its kind")

-- No node inside an instance, and none on the map of a continent: the place would be wrong.
local before = ns.CountNodes()
local inInstance, bestMap = IsInInstance, C_Map.GetBestMapForUnit
IsInInstance = function() return true, "party" end
T.fire("UNIT_SPELLCAST_SENT", "player", "Serpentbloom", "Cast-20", 2366)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-20", 2366)
expect(ns.CountNodes() == before, "a gather inside an instance adds no node")
expect(last().target == "Serpentbloom" and last().result:find("inside an instance"), "the last cast says that it was inside an instance, got " .. tostring(last().result))
IsInInstance = inInstance
C_Map.GetBestMapForUnit = function() return 13 end
T.fire("UNIT_SPELLCAST_SENT", "player", "Serpentbloom", "Cast-21", 2366)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-21", 2366)
expect(ns.CountNodes() == before and ForeverGatherDB.nodes[13] == nil, "a gather on the map of a continent adds no node")
expect(last().result:find("continent %(map 13%)"), "the last cast names the continent map, got " .. tostring(last().result))
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-22", 3365)
T.fire("LOOT_READY", false)
expect(ns.CountNodes() == before, "a chest on the map of a continent adds no node")
C_Map.GetBestMapForUnit = bestMap
H.world.loot = {}
expect(ns.MapTooLarge(13) and ns.MapTooLarge(947) and not ns.MapTooLarge(37), "a continent and the world are too large for a node, a zone is not")

-- Nodes of the earlier version on the map of a continent go at login.
ForeverGatherDB.nodes[13] = {
  { kind = "herb", name = "Serpentbloom", x = 0.52, y = 0.55, count = 4 },
  { kind = "herb", name = "Serpentbloom", x = 0.53, y = 0.54, count = 1 },
}
expect(ns.DropMisplaced() == 2 and ForeverGatherDB.nodes[13] == nil and ns.CountNodes() == before, "the two nodes on the continent are dropped, the others stay")

-- The treasure of data version 1 goes: it had quest objects in it. Herbs stay.
local old = {
  version = 1,
  nodes = { [37] = {
    { kind = "treasure", name = "Deepmoss Eggs", x = 0.5, y = 0.7, count = 1 },
    { kind = "herb", name = "Peacebloom", x = 0.4, y = 0.6, count = 2 },
    { kind = "treasure", name = "Alliance Chest", x = 0.5, y = 0.8, count = 1 },
  } },
  names = { ["Deepmoss Eggs"] = { kind = "treasure" }, ["Peacebloom"] = { kind = "herb", skill = 1 }, ["Alliance Chest"] = { kind = "treasure" } },
}
expect(ns.DropOldTreasure(old) == 2 and #old.nodes[37] == 1 and old.nodes[37][1].name == "Peacebloom", "the old treasure nodes go, the herb stays")
expect(old.names["Deepmoss Eggs"] == nil and old.names["Peacebloom"].skill == 1, "the names of old treasure go, the herb keeps its skill")

-- /fgather status: the last gathering cast with what came of it, and the last other cast.
T.fire("UNIT_SPELLCAST_SENT", "player", "Kobold Vermin", "Cast-30", 133)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-30", 133)
expect(ForeverGatherDB.last.other.spell == 133 and ForeverGatherDB.last.other.target == "Kobold Vermin", "a cast of another spell at a target is kept as the last other cast")
T.fire("UNIT_SPELLCAST_SENT", "player", "Tin Vein", "Cast-31", 2575)
T.fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-31", 2575)
T.slash("/fgather", "status")
expect(T.printed("Last gathering cast: .*%(spell 2575%) at Tin Vein.*ore: not recorded: the cast failed or was interrupted"), "/fgather status has the interrupted cast and why it was not recorded")
expect(T.printed("Last other cast at a target: .*%(spell 133%) at Kobold Vermin"), "/fgather status has the last other cast")
expect(T.printed("Your skills: Herbalism"), "/fgather status has the skills")
T.fire("UNIT_SPELLCAST_SENT", "player", "Tin Vein", "Cast-32", 2575)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-32", 2575)
T.slash("/fgather", "status")
expect(T.printed("at Tin Vein.*ore: recorded as ore on map 37"), "/fgather status says where the last gather was recorded")
-- The Tin Vein goes again: the checks below count the four nodes from above.
for index, node in ipairs(ForeverGatherDB.nodes[37]) do
  if node.name == "Tin Vein" then
    table.remove(ForeverGatherDB.nodes[37], index)
    break
  end
end

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
