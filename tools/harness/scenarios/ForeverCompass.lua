-- What Forever Compass does, with checks. T is the test table of the driver (see driver.lua).
local T = ...
local H, ns, expect = T.H, T.ns, T.expect

local function names(kind)
  local out = {}
  for _, target in ipairs(ns.FindTargets(kind)) do
    out[#out + 1] = target[4]
  end
  table.sort(out)
  return table.concat(out, ", ")
end

-- What each kind of tracker finds in the world of the stand-in.
expect(names("questObjectives") == "Wanted: Hogger", "quest objectives: the quest that is not complete, got " .. names("questObjectives"))
expect(names("questTurnIns") == "A Fishy Peril", "quest turn-ins: the quest that is complete, got " .. names("questTurnIns"))
expect(names("questGivers") == "Shipment to Stormwind", "quest givers: not the hidden one and not the one on another floor, got " .. names("questGivers"))
expect(names("trackedQuest") == "Wanted: Hogger", "the tracked quest, got " .. names("trackedQuest"))
expect(names("rares") == "Gruff Swiftbite, Rare", "rares: a marker without a name is \"Rare\", got " .. names("rares"))
expect(names("flight") == "Goldshire", "flight masters: of the player's faction only, got " .. names("flight"))
expect(names("mapPin") == "Map pin", "the map pin, got " .. names("mapPin"))
expect(names("party") == "" and names("corpse") == "", "no party member and no corpse when alone and alive")
T.world.group = "party"
expect(names("party") == "Friend", "the party member, got " .. names("party"))
T.world.group = nil
T.world.dead = true
expect(names("corpse") == "Your corpse", "the corpse of a ghost, got " .. names("corpse"))
T.world.dead = false
-- Each target is a world position: continent, north, west, name.
local target = ns.FindTargets("flight")[1]
expect(type(target[1]) == "number" and type(target[2]) == "number" and type(target[3]) == "number", "a target has a continent and two world coordinates")

-- Places are learned: a vendor that repairs is a vendor and a repairer.
expect(#ns.Places("vendor") == 0, "no vendor is known at first")
T.world.npc = "Brog Hamfist"
T.fire("MERCHANT_SHOW")
expect(#ns.Places("vendor") == 1 and ns.Places("vendor")[1].name == "Brog Hamfist", "the vendor is remembered with its name")
expect(#ns.Places("repair") == 1, "a vendor that repairs is also a repairer")
T.fire("MERCHANT_SHOW")
expect(#ns.Places("vendor") == 1, "the same vendor at the same place is one place")
expect(names("vendor") == "Brog Hamfist", "a tracker for vendors points to the learned vendor")
T.fire("MAIL_SHOW")
expect(#ns.Places("mailbox") == 1, "a mailbox is remembered")
T.world.npc = nil

-- The trackers: each one can be set to each kind.
for index = 1, ns.COUNT do
  expect(ns.SetCompass(index, "enabled", true) == true, "tracker " .. index .. " turns on")
end
for _, kind in ipairs(ns.KINDS) do
  expect(ns.SetCompass(1, "kind", kind.key) == true, "tracker 1 takes the kind " .. kind.key)
  T.advance(1)
  expect(type(ns.TrackerStatus(1)) == "string", "tracker 1 has a status text for " .. kind.key)
end
expect(ns.SetCompass(1, "kind", "noSuchKind") == false, "a kind that does not exist is refused")
expect(ns.SetCompass(1, "color", "noSuchColour") == false, "a colour that does not exist is refused")
ns.SetCompass(1, "kind", "questObjectives")
ns.SetCompass(2, "kind", "flight")
ns.SetCompass(3, "kind", "rares")
ns.SetCompass(4, "kind", "vendor")

-- The numbers stay in their ranges.
ns.SetOption("barAlpha", 500)
expect(ns.GetOption("barAlpha") == 100, "the opacity of the bar stays at 100 or lower")
ns.SetOption("barWidth", 1)
expect(ns.GetOption("barWidth") == 30, "the width of the bar stays at 30 or higher")
ns.SetOption("barAlpha", 75)
ns.SetOption("barWidth", 67)

-- The commands with a tracker number.
T.slash("/fcompass", "2 vendor")
expect(ns.GetCompass(2, "kind") == "vendor", "/fcompass 2 vendor sets the kind of tracker 2")
T.slash("/fcompass", "2 off")
expect(ns.GetCompass(2, "enabled") == false, "/fcompass 2 off turns tracker 2 off")
T.slash("/fcompass", "2 on")
T.slash("/fcompass", "2 opacity 40")
expect(ns.GetCompass(2, "alpha") == 40, "/fcompass 2 opacity 40 sets the opacity of the marker")
T.slash("/fcompass", "kinds")
T.slash("/fcompass", "")
T.advance(2)

-- A marker of a quest of the log takes a click, which opens the quest in the quest log.
ns.SetCompass(1, "kind", "questObjectives")
ns.SetCompass(2, "kind", "flight")
T.advance(2)
local questMarker, flightMarker
for _, frame in ipairs(H.frames) do
  if frame.dot and frame.index == 1 then
    questMarker = frame
  elseif frame.dot and frame.index == 2 then
    flightMarker = frame
  end
end
expect(ns.TrackerQuest(1) == 176, "the marker of the quest objectives points to quest 176 (Wanted: Hogger), got " .. tostring(ns.TrackerQuest(1)))
expect(questMarker ~= nil and questMarker:IsMouseEnabled(), "the marker of a quest takes the mouse")
H.run(questMarker, "OnMouseUp", "LeftButton")
expect(H.count("open quest") == 1 and H.did[#H.did][2] == 176, "a click on the marker opens quest 176 in the quest log")
-- In a fight the game refuses an addon that opens a window: the click says so and asks nothing of the game.
T.world.secret = true
H.run(questMarker, "OnMouseUp", "LeftButton")
T.world.secret = false
expect(H.count("open quest") == 1 and T.printed("cannot open in a fight"), "in a fight a click on the marker opens nothing and says why")
expect(ns.TrackerQuest(2) == nil and flightMarker ~= nil and not flightMarker:IsMouseEnabled(), "the marker of a flight master is not a quest and lets a click through")
H.run(flightMarker, "OnMouseUp", "LeftButton")
expect(H.count("open quest") == 1, "a click on a marker that is not a quest opens nothing")
ns.SetCompass(2, "kind", "vendor")

-- For other addons: ForeverCompass.TrackQuest makes a tracker point to one quest of the log.
-- Forever Quests calls it from the compass symbol of a quest.
local kept = { ns.GetCompass(3, "kind"), ns.GetCompass(4, "kind") }
ns.SetCompass(3, "enabled", false)
ns.SetCompass(4, "enabled", false)
expect(type(ForeverCompass) == "table" and ForeverCompass.QuestTracker(40) == nil, "no tracker points to quest 40 at first")
expect(ForeverCompass.TrackQuest(40) == 3, "the first tracker that is off takes the quest")
expect(ns.GetCompass(3, "enabled") == true and ns.GetCompass(3, "kind") == "quest" and ns.GetCompass(3, "questID") == 40, "that tracker is on, of the kind for one quest, with the quest")
expect(ForeverCompass.QuestTracker(40) == 3 and ForeverCompass.TrackQuest(40) == 3, "a quest that is on the compass keeps its tracker")
T.advance(2)
expect(ns.TrackerQuest(3) == 40, "the marker of that tracker points to quest 40, got " .. tostring(ns.TrackerQuest(3)) .. " (" .. ns.TrackerStatus(3) .. ")")
expect(ForeverCompass.TrackQuest(176) == 4, "a second quest takes the next tracker that is off")
local none, why = ForeverCompass.TrackQuest(12345)
expect(none == nil and type(why) == "string" and why:find("in use"), "with every tracker on, a third quest is refused with the reason, got " .. tostring(why))
expect(ForeverCompass.TrackQuest("40") == nil and ForeverCompass.TrackQuest(0) == nil, "what is not a quest is refused")
expect(ForeverCompass.UntrackQuest(40) == true and ForeverCompass.QuestTracker(40) == nil and ns.GetCompass(3, "enabled") == false, "taking the quest off turns its tracker off")
expect(ForeverCompass.UntrackQuest(40) == false, "a quest that is not on the compass has nothing to take off")
-- A tracker of the kind for one quest without a quest points to nothing.
ns.SetCompass(3, "enabled", true)
T.advance(2)
expect(ns.TrackerQuest(3) == nil, "a tracker for one quest with no quest set shows nothing")
ns.SetCompass(3, "enabled", false)
ForeverCompass.UntrackQuest(176)
ns.SetCompass(3, "kind", kept[1])
ns.SetCompass(4, "kind", kept[2])