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

-- A list from a party member. The game gives the sender with the realm ("Friend-TestRealm"); the
-- addon must take the realm of its own realm off, or its own messages look like a member's.
T.fire("CHAT_MSG_ADDON", "ForeverQuests", "1S176:0:2.8;40:1", "PARTY", "Friend-TestRealm")
expect(ns.party.Friend and ns.party.Friend[176] and ns.party.Friend[176].objectives[1][1] == 2, "the progress of the party member on quest 176 is 2 of 8")
expect(ns.party.Friend[40].complete == true, "the party member has quest 40 ready")
-- A change, and a quest that the member no longer has.
T.fire("CHAT_MSG_ADDON", "ForeverQuests", "1U176:0:5.8;40:x", "PARTY", "Friend-TestRealm")
expect(ns.party.Friend[176].objectives[1][1] == 5 and ns.party.Friend[40] == nil, "a change message updates one quest and removes another")
-- Bad messages change nothing: a broken entry, another prefix, another channel, the player itself.
for _, message in ipairs({ "1U176:0:9.8;40:y", "1U176:0:9,8", "1U0:0", "1Z176:0:9.8", "2U176:0:9.8", "1U176:0:999999.8" }) do
  T.fire("CHAT_MSG_ADDON", "ForeverQuests", message, "PARTY", "Friend-TestRealm")
end
T.fire("CHAT_MSG_ADDON", "OtherAddon", "1U176:0:9.8", "PARTY", "Friend-TestRealm")
T.fire("CHAT_MSG_ADDON", "ForeverQuests", "1U176:0:9.8", "WHISPER", "Friend-TestRealm")
T.fire("CHAT_MSG_ADDON", "ForeverQuests", "1U176:0:9.8", "PARTY", "Tester-TestRealm")
expect(ns.party.Friend[176].objectives[1][1] == 5 and ns.party.Tester == nil, "a broken or foreign message is dropped whole")
-- A hello from the member asks for the list again.
T.fire("CHAT_MSG_ADDON", "ForeverQuests", "1H", "PARTY", "Friend-TestRealm")
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
-- In another zone, where only quest 176 has a place on the map: quest 40 is hidden.
local function shownInLog()
  local count = 0
  for button in QuestScrollFrame.titleFramePool:EnumerateActive() do
    if button:IsShown() then
      count = count + 1
    end
  end
  return count
end
T.world.zone = "Westfall"
T.fire("ZONE_CHANGED_NEW_AREA")
T.advance(2)
QuestLogQuests_Update()
expect(shownInLog() == 1, "in another zone the quest that is not of it is hidden, shown: " .. shownInLog())
-- With a text in the search box of the quest log the filter is off: the game's search decides.
QuestScrollFrame.SearchBox:SetText("hogger")
QuestLogQuests_Update()
expect(shownInLog() == 2, "a search in the quest log turns the zone filter off, shown: " .. shownInLog())
QuestScrollFrame.SearchBox:SetText("")
QuestLogQuests_Update()
expect(shownInLog() == 1, "without the search text the filter is back, shown: " .. shownInLog())
T.world.zone = nil
T.fire("ZONE_CHANGED_NEW_AREA")
T.advance(2)
QuestLogQuests_Update()
ns.SetOption("zoneLog", false)

-- Current zone only on the tracker: the quest of the zone that is not tracked (40) gets tracked.
ns.SetOption("zoneTracker", true)
T.advance(2)
expect(H.watched[40] == true and H.watched[176] == true, "the quests of the zone are tracked")
ns.SetOption("zoneTracker", false)
expect(H.watched[40] == nil and H.watched[176] == true, "the tracking of before comes back")

-- The items of a quest, beside its details in the quest log: in the bags or not.
T.world.questItems = true
QuestMapFrame_OpenToQuestDetails(176)
local lines = ns.QuestItemLines(176)
expect(#lines == 6, "quest 176 has six items: one to use, two to collect, one reward and two choices, got " .. #lines)
expect(lines[1] == "Use Stormwind Hunting Horn not in your bags", "the item to use is listed although it is not in the bags, got " .. tostring(lines[1]))
expect(lines[2] == "Collect Gnoll Paw 3/8" and lines[3] == "Collect Linen Cloth 8/8", "the items to collect, in both forms of the objective text, got " .. tostring(lines[2]) .. " | " .. tostring(lines[3]))
expect(lines[4] == "Reward Bent Large Shield" and lines[5] == "Choice Tough Jerky x5" and lines[6] == "Choice Linen Cloth x10", "the reward and the choices, got " .. tostring(lines[4]) .. " | " .. tostring(lines[5]) .. " | " .. tostring(lines[6]))
local collect = ns.QuestItems(176)[2]
expect(collect.itemID == 5001 and collect.icon == 133721, "the item of an objective is found by its name, with its icon")
expect(ForeverQuestsItems ~= nil and ForeverQuestsItems:IsVisible(), "the panel shows beside the details of the quest")
expect(ForeverQuestsItems:GetParent() == QuestMapFrame.DetailsFrame, "the panel is a child of the details, so it hides with them")
QuestMapFrame.DetailsFrame:Hide()
expect(not ForeverQuestsItems:IsVisible(), "closing the details hides the panel")
-- A quest without items has no panel.
QuestMapFrame_OpenToQuestDetails(40)
expect(not ForeverQuestsItems:IsShown(), "a quest without items shows no panel")
QuestMapFrame_OpenToQuestDetails(176)
ns.SetOption("questItems", false)
expect(not ForeverQuestsItems:IsShown(), "with the option off the panel is hidden")
ns.SetOption("questItems", true)
expect(ForeverQuestsItems:IsShown(), "with the option on again the panel is back")
QuestMapFrame.DetailsFrame:Hide()
T.world.questItems = nil

-- A quest that becomes ready to turn in: the banner, the COMPLETED mark, and its place in the log.
local function logButton(questID)
  for button in QuestScrollFrame.titleFramePool:EnumerateActive() do
    if button.questID == questID then
      return button
    end
  end
end
ns.SetOption("popProgress", true)
QuestLogQuests_Update()
expect(ns.HasCompletedMark(logButton(40)) and not ns.HasCompletedMark(logButton(176)), "the quest that is ready (40) has the COMPLETED mark, the other one not")
-- The mark covers the box of the game that tracks the quest, and the box is not drawn under it.
expect(logButton(40).Checkbox:GetAlpha() == 0 and logButton(176).Checkbox:GetAlpha() == 1, "the tracking box of a ready quest is not drawn under the mark; the box of the other quest is")
local mark
for _, frame in ipairs(H.frames) do
  if H.state(frame).parent == logButton(40) and frame.text and frame.text:GetText() == "COMPLETED" then
    mark = frame
  end
end
expect(mark ~= nil and select(2, mark:GetPoint(1)) == logButton(40).Checkbox and mark:GetHeight() >= 20 and mark:GetFrameLevel() > logButton(40).Checkbox:GetFrameLevel(), "the mark is on the box, taller than it and above it")
-- The mark is the tracking box of the quest: a click tracks it, and a second one stops.
-- Its tracking symbol is at the right end: grey while the quest is not tracked, bright while it is.
local function symbolLook()
  local red, green, blue, alpha = mark.symbol:GetVertexColor()
  return red == 1 and green == 0.9 and blue == 0.3 and alpha == 1 and "bright" or (red == 0.55 and green == 0.55 and blue == 0.55 and alpha == 0.7 and "grey" or "other")
end
expect(mark.symbol:IsShown() and mark.symbol:GetPoint(1) == "RIGHT", "the tracking symbol is at the right end of the mark, and always there")
expect(H.watched[40] == nil and mark.tracked == false and symbolLook() == "grey", "quest 40 is not tracked, and the symbol is grey, got " .. symbolLook())
H.click(mark, "LeftButton", false)
expect(H.watched[40] == true and mark.tracked == true and symbolLook() == "bright", "a click on the mark tracks the quest, and the symbol is bright, got " .. symbolLook())
H.click(mark, "LeftButton", false)
expect(H.watched[40] == nil and mark.tracked == false and symbolLook() == "grey", "a second click stops tracking, and the symbol is grey again, got " .. symbolLook())
-- A right-click shows where to turn the quest in.
local openedByMark = H.count("open quest")
H.click(mark, "RightButton", false)
expect(H.count("open quest") == openedByMark + 1 and H.did[#H.did][2] == 40, "a right-click on the mark shows where to turn the quest in")
expect(H.watched[40] == nil, "the right-click does not change the tracking")
expect(ns.FanfareQuest() == nil, "no banner before a quest becomes ready")
T.world.completed = { [176] = true }
T.fire("QUEST_LOG_UPDATE")
T.advance(1)
expect(ns.FanfareQuest() == 176 and ForeverQuestsFanfare:IsShown(), "a quest that becomes ready shows the QUEST COMPLETE banner")
expect(ForeverQuestsFanfare.title:GetText() == "Wanted: Hogger", "the banner has the name of the quest, got " .. tostring(ForeverQuestsFanfare.title:GetText()))
QuestLogQuests_Update()
expect(place(176) == 2 and ns.HasCompletedMark(logButton(176)), "the quest that became ready is at the top of its zone, with the mark")
-- A click on the banner shows where to turn the quest in.
local opened = H.count("open quest")
H.click(ForeverQuestsFanfare, "LeftButton", false)
expect(H.count("open quest") == opened + 1 and H.did[#H.did][2] == 176, "a click on the banner opens the quest on the map")
expect(ns.FanfareQuest() == nil, "the click takes the banner away")
-- The banner goes away by itself.
ns.ShowQuestComplete(40, "A Fishy Peril")
T.advance(2)
expect(ns.FanfareQuest() == 40, "the banner stays for a few seconds")
T.advance(4)
expect(ns.FanfareQuest() == nil, "the banner fades out by itself")
-- With the option off: no banner and no mark.
ns.SetOption("completeFanfare", false)
expect(ns.ShowQuestComplete(40, "A Fishy Peril") == false and ns.FanfareQuest() == nil, "with the option off there is no banner")
QuestLogQuests_Update()
expect(not ns.HasCompletedMark(logButton(40)), "with the option off there is no COMPLETED mark")
expect(logButton(40).Checkbox:GetAlpha() == 1, "with the option off the tracking box is back")
ns.SetOption("completeFanfare", true)
-- The glow starts when the quest log comes onto the screen, also without a new build by the game.
T.world.completed = nil
QuestMapFrame:Hide()
H.questProgress = H.questProgress + 1
T.fire("QUEST_LOG_UPDATE")
T.advance(1)
QuestLogQuests_Update()
expect(not ns.IsGlowing(logButton(176)), "a quest that made progress does not glow while the quest log is closed")
QuestMapFrame:Show()
expect(ns.IsGlowing(logButton(176)), "when the quest log opens, the quest that made progress glows, without a new build by the game")
T.advance(8)
expect(not ns.IsGlowing(logButton(176)), "the glow ends after a few seconds")
T.slash("/fq", "demo")
expect(ns.FanfareQuest() ~= nil and T.printed("demo: open the quest log"), "/fq demo shows the banner and says what to look at")
H.click(ForeverQuestsFanfare, "RightButton", false)
