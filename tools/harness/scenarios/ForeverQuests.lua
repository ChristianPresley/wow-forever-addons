-- What Forever Quests does, with checks. T is the test table of the driver (see driver.lua).
local T = ...
local H, ns, expect = T.H, T.ns, T.expect

-- Automation: off at first, so a quest giver changes nothing.
T.fire("GOSSIP_SHOW")
T.fire("QUEST_DETAIL")
expect(H.count("gossip turn in") == 0 and H.count("accept") == 0, "automation is off by default")

ns.SetOption("autoAccept", true)
ns.SetOption("autoTurnIn", true)
T.fire("GOSSIP_SHOW")
expect(H.count("gossip turn in") == 1 and H.did[#H.did][2] == 40, "the quest that is ready (40) is turned in at a gossip window")
ns.SetOption("autoTurnIn", false)
T.fire("GOSSIP_SHOW")
expect(H.count("gossip accept") == 1 and H.did[#H.did][2] == 61, "the quest that is not repeatable (61) is accepted, the repeatable one (62) is not")
ns.SetOption("autoTurnIn", true)
T.fire("QUEST_GREETING")
expect(H.count("greeting turn in") == 1 and H.did[#H.did][2] == 2, "at a greeting window the complete quest (the second) is turned in")
T.fire("QUEST_DETAIL")
expect(H.count("accept") == 1, "a quest is accepted at its detail window")
T.world.autoAcceptQuest = true
T.fire("QUEST_DETAIL")
expect(H.count("acknowledge") == 1 and H.count("accept") == 1, "a quest that the game accepted is acknowledged, not accepted again")
T.world.autoAcceptQuest = false
T.fire("QUEST_PROGRESS")
expect(H.count("complete") == 1, "a completable quest is completed")
T.fire("QUEST_COMPLETE")
expect(H.count("reward") == 0, "with three rewards to choose from, the choice stays with the player")
T.world.choices = { 117 }
T.fire("QUEST_COMPLETE")
expect(H.count("reward") == 1, "with one reward the quest is turned in")
T.world.choices = { 2211, 117, 2589 }
-- Shift held: nothing is done for the player.
T.world.shift = true
T.fire("QUEST_DETAIL")
T.fire("QUEST_PROGRESS")
expect(H.count("accept") == 1 and H.count("complete") == 1, "Shift skips the automation once")
T.world.shift = false
ns.SetOption("autoAccept", false)
ns.SetOption("autoTurnIn", false)

-- Reward prices: the quest window shows three choices.
T.fire("QUEST_COMPLETE")
T.advance(1)
T.fire("QUEST_FINISHED")
T.advance(1)

-- Party progress: joining a party sends a hello and the full list.
T.world.group = "party"
T.fire("GROUP_ROSTER_UPDATE")
T.advance(30)
local sentFull = false
for _, entry in ipairs(H.did) do
  if entry[1] == "addon message" and entry[2] == "ForeverQuests" and entry[3]:sub(1, 2) == "1S" then
    sentFull = true
    expect(entry[3]:find("176:0:", 1, true) and entry[3]:find("40:1", 1, true), "the full list has both quests with their state: " .. entry[3])
    expect(entry[4] == "PARTY", "the list goes to the party")
  end
end
expect(sentFull, "a full list of quests is sent after joining a party")

-- A list from a party member.
T.fire("CHAT_MSG_ADDON", "ForeverQuests", "1S176:0:2.8;40:1", "PARTY", "Friend")
expect(ns.party.Friend and ns.party.Friend[176] and ns.party.Friend[176].objectives[1][1] == 2, "the progress of the party member on quest 176 is 2 of 8")
expect(ns.party.Friend[40].complete == true, "the party member has quest 40 ready")
-- A change, and a quest that the member no longer has.
T.fire("CHAT_MSG_ADDON", "ForeverQuests", "1U176:0:5.8;40:x", "PARTY", "Friend")
expect(ns.party.Friend[176].objectives[1][1] == 5 and ns.party.Friend[40] == nil, "a change message updates one quest and removes another")
-- Bad messages change nothing: a broken entry, another prefix, another channel, the player itself.
for _, message in ipairs({ "1U176:0:9.8;40:y", "1U176:0:9,8", "1U0:0", "1Z176:0:9.8", "2U176:0:9.8", "1U176:0:999999.8" }) do
  T.fire("CHAT_MSG_ADDON", "ForeverQuests", message, "PARTY", "Friend")
end
T.fire("CHAT_MSG_ADDON", "OtherAddon", "1U176:0:9.8", "PARTY", "Friend")
T.fire("CHAT_MSG_ADDON", "ForeverQuests", "1U176:0:9.8", "WHISPER", "Friend")
T.fire("CHAT_MSG_ADDON", "ForeverQuests", "1U176:0:9.8", "PARTY", "Tester")
expect(ns.party.Friend[176].objectives[1][1] == 5 and ns.party.Tester == nil, "a broken or foreign message is dropped whole")
-- A hello from the member asks for the list again.
T.fire("CHAT_MSG_ADDON", "ForeverQuests", "1H", "PARTY", "Friend")
T.advance(30)
T.slash("/fq", "party")
expect(T.printed("Friend: 1 shared"), "/fq party lists the member with the quest that both have")
-- The game refuses addon messages (in an instance): the addon goes quiet without an error.
T.world.addonMessageResult = 9
H.questProgress = H.questProgress + 1
T.fire("QUEST_LOG_UPDATE")
T.advance(30)
T.world.addonMessageResult = nil
-- Leaving the party forgets the members.
T.world.group = nil
T.fire("GROUP_ROSTER_UPDATE")
expect(next(ns.party) == nil, "leaving the party forgets the progress of its members")

-- The order of the quest log. By name: "A Fishy Peril" comes before "Wanted: Hogger".
local function place(questID)
  for button in QuestScrollFrame.titleFramePool:EnumerateActive() do
    if button.questID == questID then
      return button.layoutIndex
    end
  end
end
ns.SetOption("popProgress", false)
ns.SetOption("sortAlpha", true)
QuestLogQuests_Update()
expect(place(40) == 2 and place(176) == 3, "sorted by name, quest 40 is first under the zone header")
-- A quest that makes progress goes to the top of its zone.
ns.SetOption("popProgress", true)
T.advance(2)
H.questProgress = H.questProgress + 1
T.fire("QUEST_LOG_UPDATE")
T.advance(2)
QuestLogQuests_Update()
expect(place(176) == 2 and place(40) == 3, "the quest that made progress (176) is first, the rest by name")
ns.SetOption("sortAlpha", false)

-- Current zone only: both quests are of this zone, so none is hidden. A search turns the filter off.
ns.SetOption("zoneLog", true)
QuestLogQuests_Update()
local shownQuests = 0
for button in QuestScrollFrame.titleFramePool:EnumerateActive() do
  if button:IsShown() then
    shownQuests = shownQuests + 1
  end
end
expect(shownQuests == 2, "both quests are in the current zone and stay in the log")
QuestScrollFrame.SearchBox:SetText("hogger")
QuestLogQuests_Update()
QuestScrollFrame.SearchBox:SetText("")
ns.SetOption("zoneLog", false)

-- Current zone only on the tracker: the quest of the zone that is not tracked (40) gets tracked.
ns.SetOption("zoneTracker", true)
T.advance(2)
expect(H.watched[40] == true and H.watched[176] == true, "the quests of the zone are tracked")
ns.SetOption("zoneTracker", false)
expect(H.watched[40] == nil and H.watched[176] == true, "the tracking of before comes back")
