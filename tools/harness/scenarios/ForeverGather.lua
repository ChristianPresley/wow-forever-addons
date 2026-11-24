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
expect(type(nodes[1].first) == "number" and nodes[1].last == nodes[1].first, "the herb has the time of its first and last gather")
expect(ns.DaysSince(time() - 3 * 86400 - 5) == 3 and ns.DaysSince(nil) == nil, "three days and five seconds ago is three days ago")

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

-- A thing opened with "Opening" is a chest or a quest object: its loot says which. The loot
-- window of the stand-in is H.world.loot: a list of { name, quest, questID }.
local function last()
  return ForeverGatherDB.history[#ForeverGatherDB.history]
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
local questTotal, questCounts = ns.CountNodes()
expect(questTotal == 4 and questCounts.quest == 1 and questCounts.treasure == nil, "a thing with a quest item as loot is a quest object and no treasure")
expect(last().result == "recorded as quest objects on map 37", "the last cast says that it was recorded as a quest object, got " .. tostring(last().result))
expect(ns.KIND.quest and ns.GetOption("quest") == true, "quest objects are a kind that shows from the start")
ns.SetOption("quest", false)
expect(#ns.VisibleNodes(37) == 3, "hidden quest objects do not show")
ns.SetOption("quest", true)
ns.Forget("quest")
expect(ns.CountNodes() == 3, "the quest object is forgotten again for the counts below")
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

-- No node inside an instance. On the map of a continent the zone under the player has the node.
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
-- The continent has Elwynn Forest on its left half: 0.42 on the continent is 0.84 in the zone.
local moved
for _, node in ipairs(ForeverGatherDB.nodes[37]) do
  if node.name == "Serpentbloom" then
    moved = node
  end
end
expect(ns.CountNodes() == before + 1 and ForeverGatherDB.nodes[13] == nil and moved, "a gather on the map of a continent is a node of the zone under the player")
expect(moved and math.abs(moved.x - 0.84) < 1e-6 and math.abs(moved.y - 0.65) < 1e-6, "the place on the continent is the place 0.84, 0.65 in the zone")
expect(last().result == "recorded as herbs on map 37", "the last cast names the zone, got " .. tostring(last().result))
-- /fgather forget here: the node nearest to the player goes, and no other.
T.slash("/fgather", "forget here")
expect(T.printed("Forgot Serpentbloom") and ns.CountNodes() == before, "/fgather forget here forgets the node at the player")
T.slash("/fgather", "forget here")
expect(T.printed("Nothing forgotten: no node is within 20 yards"), "with no node near, /fgather forget here forgets nothing")
expect(ns.CountNodes() == before, "the nodes 420 yards away stay")
-- The world map has no zone under the player: nothing is recorded.
C_Map.GetBestMapForUnit = function() return 947 end
T.fire("UNIT_SPELLCAST_SENT", "player", "Serpentbloom", "Cast-22", 2366)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-22", 2366)
expect(ns.CountNodes() == before and ForeverGatherDB.nodes[947] == nil, "a gather on a map with no zone under the player adds no node")
expect(last().result:find("continent %(map 947%)"), "the last cast names the map that is too large, got " .. tostring(last().result))
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-23", 3365)
T.fire("LOOT_READY", false)
expect(ns.CountNodes() == before, "a chest on such a map adds no node")
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

-- The history keeps the last 20 gathering casts.
expect(#ForeverGatherDB.history > 5 and #ForeverGatherDB.history <= 20, "the history has the casts from above")
for index = 1, 25 do
  T.fire("UNIT_SPELLCAST_SENT", "player", "Vein " .. index, "Cast-4" .. index, 2575)
  T.fire("UNIT_SPELLCAST_FAILED", "player", "Cast-4" .. index, 2575)
end
expect(#ForeverGatherDB.history == 20 and ForeverGatherDB.history[1].target == "Vein 6" and last().target == "Vein 25", "the history keeps the 20 newest casts")
T.slash("/fgather", "history")
expect(T.printed("The last 20 gathering casts") and T.printed("20%. .* at Vein 25.*not recorded: the cast failed"), "/fgather history lists the casts with what came of each")

-- A node of the next zone shows on the minimap near the border. Westfall lies east of Elwynn
-- Forest here: its left edge is the right edge of Elwynn Forest.
local worldPos = C_Map.GetWorldPosFromMapPos
C_Map.GetWorldPosFromMapPos = function(mapID, position)
  return 0, CreateVector2D(position.x * 1000 + (mapID == 52 and 1000 or 0), position.y * 1000)
end
ForeverGatherDB.nodes[52] = { { kind = "herb", name = "Briarthorn", x = 0.01, y = 0.65, count = 1 } }
local bx, by = ns.OnOtherMap(52, 0.01, 0.65, 37)
expect(bx and math.abs(bx - 1.01) < 1e-6 and math.abs(by - 0.65) < 1e-6, "0.01 in Westfall is 1.01 on the map of Elwynn Forest")
local across
for _, entry in ipairs(ns.NodesAround(37)) do
  if entry.node.name == "Briarthorn" then
    across = entry
  end
end
expect(across and #ns.NodesAround(37) == #ns.VisibleNodes(37) + 1, "the nodes around Elwynn Forest have the node of Westfall too")
local ox, oy = ns.MinimapOffset(across or { x = 0, y = 0 }, 0.99, 0.65, 1000, 1000, 100, 70)
expect(ox and math.abs(ox - 14) < 1e-6 and math.abs(oy) < 1e-6, "from 10 yards before the border the node is 20 yards east on the minimap")
ForeverGatherDB.nodes[52] = nil
C_Map.GetWorldPosFromMapPos = worldPos

-- A square minimap shows its corners; a round one does not.
local corner = { x = 0.5, y = 0.57 } -- 80 yards east and 80 yards north of 0.42, 0.65
expect(ns.MinimapOffset(corner, 0.42, 0.65, 1000, 1000, 100, 70) == nil, "a node in the corner is off a round minimap")
local sx, sy = ns.MinimapOffset(corner, 0.42, 0.65, 1000, 1000, 100, 70, nil, true)
expect(sx and math.abs(sx - 56) < 1e-6 and math.abs(sy - 56) < 1e-6, "a node in the corner shows on a square minimap")
corner.x = 0.53
expect(ns.MinimapOffset(corner, 0.42, 0.65, 1000, 1000, 100, 70, nil, true) == nil, "a node 110 yards east is off a square minimap too")

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
ns.SetOption("herb", false)
T.advance(1)
expect(ns.MinimapPinCount() == 3, "with herbs hidden the minimap has three pins, got " .. ns.MinimapPinCount())
ns.SetOption("herb", true)
ns.SetOption("minimap", false)
T.advance(1)
expect(ns.MinimapPinCount() == 0, "with the minimap off it has no pins")
ns.SetOption("minimap", true)
T.advance(1)
expect(ns.MinimapPinCount() == 4, "with the minimap on again the four pins are back, got " .. ns.MinimapPinCount())

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
