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
expect(last().kind == "quest" and last().target == "Deepmoss Eggs", "the cast in the history has the kind that the loot told")
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

-- One cast is one line of the history: its end is written into the line of its start.
local lines = #ForeverGatherDB.history
T.fire("UNIT_SPELLCAST_SENT", "player", "Copper Vein", "Cast-24", 2575)
expect(#ForeverGatherDB.history == lines + 1 and last().result:find("did not end yet"), "a cast that started is a line of the history")
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-24", 2575)
expect(#ForeverGatherDB.history == lines + 1 and last().result == "recorded as ore on map 37", "the end of the cast is the same line, got " .. tostring(last().result))
H.world.loot = { { name = "Troll Charm", quest = true } }
T.fire("UNIT_SPELLCAST_SENT", "player", "Troll Chest", "Cast-25", 3365)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-25", 3365)
T.fire("LOOT_READY", false)
expect(#ForeverGatherDB.history == lines + 2 and last().result == "recorded as quest objects on map 37", "a quest object that was opened is one line too")
ns.Forget("quest")
H.world.loot = {}

-- Where the maps of two zones overlap, a cave is a place of the zone that the player came from.
-- The rectangles are those of two zones whose maps share a strip of the continent.
local rectOnMap, infoAt = C_Map.GetMapRectOnMap, C_Map.GetMapInfoAtPosition
C_Map.GetMapRectOnMap = function(zone)
  if zone == 9001 then
    return 0.38, 0.56, 0.18, 0.36
  end
  return 0.42, 0.58, 0.33, 0.49
end
C_Map.GetMapInfoAtPosition = function() return { mapID = 9001 } end
local zone, zx, zy = ns.ZoneAt(13, 0.44, 0.346)
expect(zone == 9001 and math.abs(zy - 0.9222) < 1e-3, "with no zone that the player came from, the zone that the game names has the place")
zone, zx, zy = ns.ZoneAt(13, 0.44, 0.346, 9002)
expect(zone == 9002 and math.abs(zx - 0.125) < 1e-6 and math.abs(zy - 0.1) < 1e-6, "the zone that the player came from has the place when it is on its map")
zone = ns.ZoneAt(13, 0.40, 0.20, 9002)
expect(zone == 9001, "a place that is not on the map of the zone that the player came from is of the zone that the game names")
-- A node of a cave on the wrong one of two maps that overlap moves once, to the map of a newer
-- node of the same thing near it: that one was stored on the zone that the player came from.
-- A place that the game gave (a single float) stays, and so does a node with no newer one near.
-- The newer node itself stays: no node near it is newer.
C_Map.GetMapRectOnMap = function(zone)
  if zone == 37 then
    return 0.38, 0.56, 0.18, 0.36
  end
  return 0.42, 0.58, 0.33, 0.49
end
local own37, own52 = ForeverGatherDB.nodes[37], ForeverGatherDB.nodes[52]
ForeverGatherDB.nodes[37] = {
  { kind = "quest", name = "Sapphire", x = 0.3164023152017831, y = 0.9224205656863054, count = 1, first = 1, last = 1 },
  { kind = "quest", name = "At the edge", x = 0.5, y = 0.9375, count = 1, first = 1, last = 1 },
  { kind = "quest", name = "Sapphire", x = 0.3164023152017832, y = 0.5000000000000001, count = 1, first = 1, last = 1 },
  { kind = "quest", name = "Other thing", x = 0.3164023152017831, y = 0.9224205656863054, count = 1, first = 1, last = 1 },
}
ForeverGatherDB.nodes[52] = {
  { kind = "quest", name = "Sapphire", x = 0.1321655106099081, y = 0.1282111468634372, count = 1, first = 5, last = 5 },
}
ForeverGatherDB.nodes[9999] = {}
expect(ns.MoveCaveNodes() == 1 and #ForeverGatherDB.nodes[37] == 3, "the older node of the cave moves; the node that the game placed, the node far from the newer one and the other thing stay")
local cave = ForeverGatherDB.nodes[52][2]
expect(cave and cave.first == 1 and math.abs(cave.x - 0.1060) < 1e-3 and math.abs(cave.y - 0.1002) < 1e-3, "the node is at the same place on the map of the newer node")
expect(ns.MoveCaveNodes() == 0, "a second run moves nothing")
ns.DropEmptyMaps()
expect(ForeverGatherDB.nodes[9999] == nil and ForeverGatherDB.nodes[52], "a map with no node left is dropped")
ForeverGatherDB.nodes[37], ForeverGatherDB.nodes[52] = own37, own52
C_Map.GetMapRectOnMap, C_Map.GetMapInfoAtPosition = rectOnMap, infoAt
expect(ns.LastZone() == 37, "the zone of the last gather on a zone map is kept")

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

-- What a node gave: the loot window after a gather is counted on the node.
local peacebloom = ns.VisibleNodes(37)[1]
expect(peacebloom.name == "Peacebloom" and peacebloom.loot == nil, "the herb has no loot yet")
H.world.loot = { { name = "Peacebloom", quest = false }, { name = "Earthroot", quest = false } }
local gathersBefore = peacebloom.count
T.fire("UNIT_SPELLCAST_SENT", "player", "Peacebloom", "Cast-50", 2366)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-50", 2366)
T.fire("LOOT_READY", false)
T.fire("LOOT_OPENED", false, false)
expect(peacebloom.count == gathersBefore + 1 and peacebloom.loot and peacebloom.loot["Peacebloom"] == 1 and peacebloom.loot["Earthroot"] == 1 and peacebloom.looted == 1,
  "the loot of the gather is counted once on the node")
H.world.loot = { { name = "Peacebloom", quest = false } }
T.fire("UNIT_SPELLCAST_SENT", "player", "Peacebloom", "Cast-51", 2366)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-51", 2366)
T.fire("LOOT_READY", false)
local gave = ns.LootOf(peacebloom)
expect(peacebloom.looted == 2 and #gave == 2 and gave[1].item == "Peacebloom" and gave[1].count == 2 and gave[2].item == "Earthroot", "the node names what it gave, the most first")
T.fire("LOOT_READY", false)
expect(peacebloom.looted == 2 and peacebloom.loot["Peacebloom"] == 2, "a loot window without a gather before it counts nothing")
H.world.loot = {}

-- The gathers of the session, and /fgather session.
local session = ns.Session()
expect(session.total >= 6 and session.kinds.herb >= 4 and session.names["Peacebloom"] >= 4, "the session counts the gathers by kind and by name")
T.slash("/fgather", "session")
expect(T.printed("This session: " .. session.total .. " |4gather:gathers;, ") and T.printed("  Peacebloom: " .. session.names["Peacebloom"]), "/fgather session says the gathers of the session")
T.slash("/fgather", "session reset")
expect(ns.Session().total == 0, "/fgather session reset starts the count again")
T.slash("/fgather", "session")
expect(T.printed("No gather in this session yet"), "after the reset the session has no gather")

-- /fgather zone: what is known in the zone, by name.
local zoneList = ns.ZoneList(37)
local zoneHerb
for _, entry in ipairs(zoneList) do
  if entry.name == "Peacebloom" then
    zoneHerb = entry
  end
end
expect(#zoneList == 4 and zoneHerb and zoneHerb.nodes == 1 and zoneHerb.gathers == peacebloom.count, "the list of the zone has the four names, the herb with its gathers")
T.slash("/fgather", "zone")
expect(T.printed("Learned in Elwynn Forest") and T.printed("  Peacebloom %(herbs%): 1 |4place:places;, " .. peacebloom.count .. " |4gather"), "/fgather zone lists the zone")

-- The difficulty of a node for the player's skill, from the skill that it was learned at.
-- The player of the stand-in has no profession: for these checks the rank in Herbalism is 150.
local skillRank = ns.SkillRank
local herbalism = 150
ns.SkillRank = function(skill) return skill == "Herbalism" and herbalism or nil end
local learnedAt = ForeverGatherDB.names["Peacebloom"].skill
ForeverGatherDB.names["Peacebloom"].skill = herbalism
expect(ns.Difficulty(peacebloom) == "orange", "a node learned at the player's skill is orange")
ForeverGatherDB.names["Peacebloom"].skill = herbalism - 30
expect(ns.Difficulty(peacebloom) == "yellow", "30 points over the node is yellow")
ForeverGatherDB.names["Peacebloom"].skill = herbalism - 60
expect(ns.Difficulty(peacebloom) == "green", "60 points over the node is green")
ForeverGatherDB.names["Peacebloom"].skill = herbalism - 100
expect(ns.Difficulty(peacebloom) == "grey", "100 points over the node is grey")
ForeverGatherDB.names["Peacebloom"].skill = herbalism + 10
expect(ns.Difficulty(peacebloom) == "needs more skill", "a node learned by another character at a higher skill needs more skill")
ForeverGatherDB.names["Peacebloom"].skill = learnedAt
expect(ns.Difficulty({ kind = "treasure", name = "Treasure" }) == nil, "a chest has no difficulty")
ns.SkillRank = skillRank
expect(ns.Difficulty(peacebloom) == nil, "without a rank in the skill the difficulty is not known")

-- A node is dim for some minutes after its gather.
expect(ns.RecentlyGathered(peacebloom), "the herb that was gathered now is recent")
expect(not ns.RecentlyGathered({ last = time() - 600 }), "a gather ten minutes ago is not recent")
ns.SetOption("dimMinutes", 0)
expect(not ns.RecentlyGathered(peacebloom), "with 0 minutes no node is recent")
ns.SetOption("dimMinutes", 5)

-- The alert: a node that comes near is said once for a visit. The nodes at the player were
-- gathered now and are not said.
expect(ns.DirectionWord(0, 10) == "north" and ns.DirectionWord(10, -10) == "south-east" and ns.DirectionWord(-10, 0) == "west", "the direction has its word")
local silver = { kind = "ore", name = "Silver Vein", x = 0.45, y = 0.65, count = 1, first = time() - 3600, last = time() - 3600 }
table.insert(ForeverGatherDB.nodes[37], silver)
ns.Changed()
local alertsBefore = ns.AlertCount()
expect(ns.CheckNearby() == 1 and ns.AlertCount() == alertsBefore + 1, "the node 30 yards away is said, the nodes gathered now are not")
expect(T.printed("Silver Vein is 30 yards to the east"), "the alert says the name, the distance and the direction")
expect(ns.CheckNearby() == 0, "the node is not said again in the same visit")
local mapPosition = C_Map.GetPlayerMapPosition
C_Map.GetPlayerMapPosition = function() return CreateVector2D(0.9, 0.65) end
expect(ns.CheckNearby() == 0, "450 yards away nothing is near")
C_Map.GetPlayerMapPosition = mapPosition
expect(ns.CheckNearby() == 1, "back at the node it is said again: a new visit")
C_Map.GetPlayerMapPosition = function() return CreateVector2D(0.9, 0.65) end
ns.CheckNearby()
C_Map.GetPlayerMapPosition = mapPosition
ns.SetOption("alert", false)
expect(ns.CheckNearby() == 0, "with the alert off nothing is said")
T.slash("/fgather", "alert")
expect(ns.GetOption("alert") == true, "/fgather alert turns the alert on again")
ns.SetOption("alertYards", 20)
expect(ns.CheckNearby() == 0, "with 20 yards the node 30 yards away is not near")
ns.SetOption("alertYards", 60)

-- The map pin of the game on a node, and forget one node: the two entries of the menu of a pin.
local canPin, setPin = C_Map.CanSetUserWaypointOnMap, C_Map.SetUserWaypoint
C_Map.CanSetUserWaypointOnMap = function() return false end
expect(ns.SetWaypoint(37, silver):find("takes no map pin"), "where the game takes no map pin, the player is told")
C_Map.CanSetUserWaypointOnMap = function() return true end
C_Map.SetUserWaypoint = function(point) H.gatherPin = point return true end
expect(ns.SetWaypoint(37, silver) == "the map pin is on Silver Vein.", "the map pin goes on the node")
expect(H.gatherPin and H.gatherPin.uiMapID == 37 and math.abs(H.gatherPin.position.x - 0.45) < 1e-6, "the map pin is at the place of the node")
C_Map.CanSetUserWaypointOnMap, C_Map.SetUserWaypoint = canPin, setPin
local withSilver = ns.CountNodes()
expect(ns.ForgetNode(37, silver) and ns.CountNodes() == withSilver - 1, "one node is forgotten, the others stay")
expect(not ns.ForgetNode(37, silver), "a node that is not there is not forgotten twice")

-- Export and import as text.
local exported, exportCount = ns.ExportNodes()
expect(exportCount == ns.CountNodes() and exported:find("^FG1\n") and exported:find("\n37;herb;4200;6500;Peacebloom"), "the export has a line for each node, got " .. exported)
local read, added = ns.ImportNodes(exported)
expect(read == exportCount and added == 0, "an import of the own export adds nothing")
read, added = ns.ImportNodes("FG1\r\n52;ore;1234;5678;Jacob's Vein; the big one\n37;herb;4200;6500;Peacebloom\n\n")
local importedNode = ForeverGatherDB.nodes[52] and ForeverGatherDB.nodes[52][1]
expect(read == 2 and added == 1 and importedNode and importedNode.name == "Jacob's Vein; the big one", "an import adds the node that is not known, with its whole name")
expect(importedNode and importedNode.count == 0 and importedNode.imported == true and math.abs(importedNode.x - 0.1234) < 1e-9 and math.abs(importedNode.y - 0.5678) < 1e-9, "the imported node has its place and no gather")
expect(ns.CountNodes() == exportCount + 1, "the import added one node")
local nothing, why = ns.ImportNodes("hello")
expect(nothing == nil and why:find("not an export"), "a text that is no export is refused")
nothing, why = ns.ImportNodes("FG1\n52;ore;1;1;Good Vein\n37;gems;1;1;Ruby")
expect(nothing == nil and why:find("line 3") and #ForeverGatherDB.nodes[52] == 1, "a text with a wrong line is refused whole")
read, added = ns.ImportNodes("FG1\n13;herb;5000;5000;Serpentbloom")
expect(read == 0 and added == 0 and ForeverGatherDB.nodes[13] == nil, "a node on the map of a continent is not imported")
ForeverGatherDB.nodes[52] = nil
ForeverGatherDB.names["Jacob's Vein; the big one"] = nil
ns.Changed()
-- The window.
T.slash("/fgather", "export")
expect(ForeverGatherShare:IsShown() and ForeverGatherShare.box:GetText() == exported, "/fgather export shows the export in its window")
T.slash("/fgather", "import")
expect(ForeverGatherShare.mode == "import" and ForeverGatherShare.box:GetText() == "", "/fgather import shows an empty box")
ForeverGatherShare.box:SetText("FG1\n52;herb;100;200;Briarthorn")
ForeverGatherShare.action:GetScript("OnClick")(ForeverGatherShare.action)
expect(T.printed("1 |4node:nodes; read, 1 of them new") and not ForeverGatherShare:IsShown() and #ForeverGatherDB.nodes[52] == 1, "the button Import adds the node and closes the window")
ForeverGatherDB.nodes[52] = nil
ForeverGatherDB.names["Briarthorn"] = nil
ns.Changed()

-- Two nodes of one name are one node within 15 yards (fish: 45), in every zone. The map of
-- the stand-in is 1000 yards wide.
local reachX, reachY = ns.SameReach("herb", 37)
expect(math.abs(reachX - 0.015) < 1e-9 and math.abs(reachY - 0.015) < 1e-9 and math.abs(ns.SameReach("fish", 37) - 0.045) < 1e-9, "15 yards are 0.015 of the map, 45 yards 0.045")
local here = ForeverGatherDB.nodes[37]
local royalA = { kind = "herb", name = "Mageroyal", x = 0.2, y = 0.2, count = 2, first = 100, last = 200, loot = { Mageroyal = 2 }, looted = 2 }
local royalB = { kind = "herb", name = "Mageroyal", x = 0.21, y = 0.2, count = 1, first = 50, last = 300, loot = { Mageroyal = 1, Swiftthistle = 1 }, looted = 1 }
local royalC = { kind = "herb", name = "Mageroyal", x = 0.3, y = 0.2, count = 1 }
local royalD = { kind = "ore", name = "Mageroyal", x = 0.2, y = 0.2, count = 1 }
table.insert(here, royalA)
table.insert(here, royalB)
table.insert(here, royalC)
table.insert(here, royalD)
local beforeClean = ns.CountNodes()
expect(ns.FindNode(here, "herb", "Mageroyal", 0.205, 0.2, 37, royalA) == royalB, "the node 5 yards away is the same node; the node to pass over is passed over")
expect(ns.CleanNodes() == 1 and ns.CountNodes() == beforeClean - 1, "the two herbs 10 yards apart become one; the one 90 yards away and the ore stay")
local kept = ns.FindNode(here, "herb", "Mageroyal", 0.2, 0.2, 37)
expect(kept and kept.count == 3 and math.abs(kept.x - (0.2 * 2 + 0.21) / 3) < 1e-9, "the merged node has the gathers of both, at the average place by gathers")
expect(kept and kept.first == 50 and kept.last == 300 and kept.loot.Mageroyal == 3 and kept.loot.Swiftthistle == 1 and kept.looted == 3, "the merged node has the first and the last time and the loot of both")
T.slash("/fgather", "clean")
expect(T.printed("0 |4node:nodes; merged") and ns.CountNodes() == beforeClean - 1, "/fgather clean merges nothing more")
for index = #here, 1, -1 do
  if here[index].name == "Mageroyal" then
    table.remove(here, index)
  end
end
ns.Changed()

-- A node that needs more skill: the game says so in red, and the thing under the pointer has
-- the name. It is stored as seen, with no gather.
local worldCursor = C_TooltipInfo.GetWorldCursor
local underPointer = { lines = { { leftText = "Mageroyal" }, { leftText = "Requires Herbalism" } } }
C_TooltipInfo.GetWorldCursor = function() return underPointer end
local beforeSeen = ns.CountNodes()
T.fire("UI_ERROR_MESSAGE", 50, "Out of range.")
expect(ns.CountNodes() == beforeSeen and ForeverGatherDB.last.error.message == "Out of range." and ForeverGatherDB.last.error.name == "Mageroyal", "another red message stores no node, and is kept for a report")
T.fire("UI_ERROR_MESSAGE", 50, "Requires Herbalism 150")
local seen = ns.FindNode(here, "herb", "Mageroyal", 0.42, 0.65, 37)
expect(ns.CountNodes() == beforeSeen + 1 and seen and seen.count == 0 and seen.seen == true, "the herb that needs more skill is stored as seen, at the player")
expect(ns.NeededSkill("Mageroyal") == 150 and last().result:find("seen, not gathered"), "the skill that the game asked for is kept, and the history has the node")
T.fire("UI_ERROR_MESSAGE", 50, "Requires Herbalism 150")
expect(ns.CountNodes() == beforeSeen + 1, "the same node is not stored twice")
ns.SkillRank = function() return 100 end
expect(ns.Difficulty(seen) == "needs more skill", "at skill 100 the node that needs 150 needs more skill")
ns.SkillRank = function() return 160 end
expect(ns.Difficulty(seen) == "orange", "at skill 160 the node that needs 150 is orange")
ns.SkillRank = skillRank
underPointer = { lines = { { leftText = "Kobold Vermin" }, { leftText = "Level 2 Humanoid" } } }
T.fire("UI_ERROR_MESSAGE", 50, "Requires Herbalism 150")
expect(ns.CountNodes() == beforeSeen + 1, "a thing whose tooltip names no skill is no node")
underPointer = {}
T.fire("UI_ERROR_MESSAGE", 50, "Requires Mining 75")
expect(ForeverGatherDB.last.error.name == "Kobold Vermin", "with nothing under the pointer a red message is not kept")
C_TooltipInfo.GetWorldCursor = worldCursor
T.slash("/fgather", "status")
expect(T.printed("Last red message with a thing under the pointer.*Requires Herbalism 150.*Kobold Vermin"), "/fgather status has the last red message")
-- The first gather of a seen node makes it a gathered node.
T.fire("UNIT_SPELLCAST_SENT", "player", "Mageroyal", "Cast-60", 2366)
T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-60", 2366)
expect(ns.CountNodes() == beforeSeen + 1 and seen.count == 1 and seen.seen == nil, "a gather of the seen node counts on it, and it is no longer only seen")
expect(ns.ForgetNode(37, seen), "the herb is forgotten again for the counts below")
ForeverGatherDB.names["Mageroyal"] = nil

-- The route of a zone: each node once, in a short order. Four corners of a square of 800 yards.
ForeverGatherDB.nodes[52] = {
  { kind = "herb", name = "Briarthorn", x = 0.1, y = 0.1, count = 1 },
  { kind = "herb", name = "Briarthorn", x = 0.9, y = 0.9, count = 1 },
  { kind = "herb", name = "Briarthorn", x = 0.9, y = 0.1, count = 1 },
  { kind = "herb", name = "Briarthorn", x = 0.1, y = 0.9, count = 1 },
}
ns.Changed()
local route, routeYards = ns.Route(52)
expect(#route == 4 and math.abs(routeYards - 3200) < 1e-6, "the route around the four corners is 3200 yards, got " .. routeYards)
-- Twelve nodes in two rows, given in a mixed order: the shortest way round is 1200 yards.
ForeverGatherDB.nodes[52] = {}
for _, index in ipairs({ 3, 9, 0, 6, 11, 2, 8, 5, 1, 10, 4, 7 }) do
  table.insert(ForeverGatherDB.nodes[52], { kind = "ore", name = "Tin Vein", x = 0.1 + (index % 6) * 0.1, y = index < 6 and 0.4 or 0.5, count = 1 })
end
ns.Changed()
route, routeYards = ns.Route(52)
local onRoute, different = {}, 0
for _, node in ipairs(route) do
  if not onRoute[node] then
    onRoute[node] = true
    different = different + 1
  end
end
expect(#route == 12 and different == 12, "the route has each of the twelve nodes once")
expect(math.abs(routeYards - 1200) < 1e-6, "the route round the two rows is 1200 yards, got " .. routeYards)
expect(#ns.Route(nil) == 0 and select(2, ns.Route(1)) == 0, "no map and a map without nodes have no route")
ForeverGatherDB.nodes[52] = nil
ForeverGatherDB.names["Briarthorn"] = nil
ns.Changed()

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
-- The line of the route on the world map: a leg from each node to the next, and back to the first.
ns.RefreshWorldPins()
expect(ns.RouteLineCount() == 0, "with the route off the map has no line")
T.slash("/fgather", "route")
ns.RefreshWorldPins()
expect(ns.GetOption("route") == true and ns.RouteLineCount() == 4, "/fgather route draws a line with four legs through the four nodes, got " .. ns.RouteLineCount())
expect(T.printed("The route of this zone: 4 nodes"), "/fgather route says the route of the zone")
ns.SetOption("herb", false)
ns.RefreshWorldPins()
expect(ns.RouteLineCount() == 3, "the route goes through the nodes that show only, got " .. ns.RouteLineCount())
ns.SetOption("herb", true)
T.slash("/fgather", "route")
ns.RefreshWorldPins()
expect(ns.GetOption("route") == false and ns.RouteLineCount() == 0, "with the route off again the line is gone")

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
