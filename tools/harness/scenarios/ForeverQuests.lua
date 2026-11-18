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
-- The icon of a quest is not a child of its title: the icon of a hidden quest is hidden too.
local iconsShown, iconOfHidden = 0, false
for icon in QuestScrollFrame.Contents.buttonPool:EnumerateActive() do
  if icon:IsShown() then
    iconsShown = iconsShown + 1
    iconOfHidden = iconOfHidden or not icon.parent:IsShown()
  end
end
expect(iconsShown == 1 and not iconOfHidden, "the icon of the hidden quest is hidden with it, icons shown: " .. iconsShown)
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
expect(select(2, ForeverQuestsItems:GetPoint(1)) == QuestMapFrame, "without a picture of the quest giver the panel is beside the quest log")
-- A quest with a picture of its quest giver: the game shows it at that same place, over other
-- windows. The panel goes to the right of the picture.
T.world.questPortrait = true
QuestMapFrame_OpenToQuestDetails(176)
expect(QuestModelScene:IsShown() and select(2, ForeverQuestsItems:GetPoint(1)) == QuestModelScene, "with the picture of the quest giver the panel is at the right of the picture")
T.world.questPortrait = nil
QuestMapFrame_OpenToQuestDetails(176)
expect(select(2, ForeverQuestsItems:GetPoint(1)) == QuestMapFrame, "and beside the quest log again without it")
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
-- A ready quest in the quest log: the whole quest on green, in white, "COMPLETED" before its name.
local ready, other = logButton(40), logButton(176)
local mark = ns.CompletedMark(ready)
local function colour(region)
  local red, green, blue = region:GetTextColor()
  return red .. " " .. green .. " " .. blue
end
expect(mark ~= nil and mark.back:IsShown() and select(2, mark.back:GetPoint(1)) == ready, "the green background covers the button of the ready quest")
expect(ready.Text:GetText() == "COMPLETED  A Fishy Peril", "COMPLETED is in front of the name of the quest, got " .. tostring(ready.Text:GetText()))
expect(other.Text:GetText() == "Wanted: Hogger" and not ns.CompletedMark(other).back:IsShown(), "the quest that is not ready keeps its name and has no green")
expect(colour(ready.Text) == "1 1 1" and colour(H.questLogFrames.line3.Text) == "1 1 1", "the title of the ready quest and the line under it are white, got " .. colour(ready.Text))
expect(colour(other.Text) ~= "1 1 1", "the title of the other quest has the colour of the game")
-- The game gives the texts their own colours again when the pointer leaves the quest. After
-- that they are white again.
H.run(ready, "OnEnter")
H.run(ready, "OnLeave")
expect(colour(ready.Text) == "1 1 1" and colour(H.questLogFrames.line3.Text) == "1 1 1", "after the pointer leaves the quest its texts are white again")
expect(colour(ready.TagText) == "1 1 1", "the tag at the right of the name is white too, got " .. colour(ready.TagText))
H.run(other, "OnLeave")
expect(colour(other.Text) ~= "1 1 1", "and the other quest is not made white")
-- A second pass over the same build does not put COMPLETED there twice.
QuestMapFrame:Hide()
QuestMapFrame:Show()
expect(ready.Text:GetText() == "COMPLETED  A Fishy Peril", "COMPLETED is in front of the name once, got " .. tostring(ready.Text:GetText()))
-- The tracking symbol is small, at the right end of the title where the game has its tracking
-- box, and the box is not drawn there. It has room around it that takes the click too.
local tracker = mark.tracker
expect(tracker:IsShown() and tracker.symbol:GetWidth() <= 14 and select(2, tracker:GetPoint(1)) == ready.Checkbox, "the tracking symbol is small and at the place of the tracking box")
expect(tracker:GetWidth() >= tracker.symbol:GetWidth() + 6 and tracker:GetHeight() >= tracker.symbol:GetHeight() + 6, "the tracking symbol has room around it")
-- Every quest has the symbol in the place of the box, not only a ready one.
local otherMark = ns.CompletedMark(other)
expect(ready.Checkbox:GetAlpha() == 0 and other.Checkbox:GetAlpha() == 0, "the tracking box of the game is not drawn on any quest")
expect(otherMark.tracker:IsShown() and select(2, otherMark.tracker:GetPoint(1)) == other.Checkbox and otherMark.tracker.questID == 176, "a quest that is not ready has the tracking symbol too")
local wasTracked = H.watched[176] == true
expect(otherMark.tracker.tracked == wasTracked, "the symbol of a quest that is not ready shows whether the quest is tracked")
H.click(otherMark.tracker, "LeftButton", false)
expect((H.watched[176] == true) == not wasTracked and otherMark.tracker.tracked == not wasTracked, "a click on the symbol of a quest that is not ready changes its tracking")
H.click(otherMark.tracker, "LeftButton", false)
expect((H.watched[176] == true) == wasTracked and otherMark.tracker.tracked == wasTracked, "and a second click changes it back")
local openedByOther = H.count("open quest")
H.click(otherMark.tracker, "RightButton", false)
expect(H.count("open quest") == openedByOther, "a right-click on a quest that is not ready opens nothing: there is no turn-in yet")
-- The compass symbol is under the tracking symbol, only with Forever Compass.
expect(not mark.compass:IsShown() and ns.CompassTracker(40) == nil and ns.ToggleCompass(40) == false, "without Forever Compass there is no compass symbol")
local onCompass, compassFull = {}, false
ForeverCompass = {
  QuestTracker = function(questID) return onCompass[questID] end,
  TrackQuest = function(questID)
    if compassFull then
      return nil, "all 4 trackers of the compass are in use"
    end
    onCompass[questID] = 3
    return 3
  end,
  UntrackQuest = function(questID)
    local had = onCompass[questID] ~= nil
    onCompass[questID] = nil
    return had
  end,
}
QuestLogQuests_Update()
-- The game makes the button of a quest as high as its title and the lines under it, and so
-- does the stand-in: both quests have a line, so their buttons have room for two symbols.
expect(ready:GetHeight() >= 38 and other:GetHeight() >= 38, "a quest with a line under its title has a button high enough for both symbols, got " .. ready:GetHeight() .. " and " .. other:GetHeight())
local compass = mark.compass
local function compassLook()
  local red, green, blue, alpha = compass.symbol:GetVertexColor()
  return red == 0.4 and green == 0.8 and blue == 1 and alpha == 1 and "bright" or (red == 0.8 and alpha == 0.6 and "grey" or "other")
end
expect(compass:IsShown() and otherMark.compass:IsShown() and select(2, compass:GetPoint(1)) == tracker and select(3, compass:GetPoint(1)) == "BOTTOM", "with Forever Compass every quest has the compass symbol under the tracking symbol")
expect(compass.onCompass == false and compassLook() == "grey", "a quest that is not on the compass has a grey compass symbol, got " .. compassLook())
H.click(compass, "LeftButton", false)
expect(onCompass[40] == 3 and compass.onCompass == true and compassLook() == "bright" and T.printed("tracker 3 of the compass"), "a click puts the quest on the compass, and the symbol is bright, got " .. compassLook())
expect(H.watched[40] == nil, "the compass symbol does not change the tracking of the game")
H.run(compass, "OnEnter")
expect(GameTooltip:IsShown(), "the compass symbol has a tooltip")
H.run(compass, "OnLeave")
H.click(compass, "LeftButton", false)
expect(onCompass[40] == nil and compass.onCompass == false and compassLook() == "grey", "a second click takes the quest off the compass")
compassFull = true
H.click(compass, "LeftButton", false)
expect(onCompass[40] == nil and compassLook() == "grey" and T.printed("all 4 trackers of the compass are in use"), "with every tracker in use the quest is not added, and the addon says why")
compassFull = false
-- A quest without lines under its title has a low button: the compass symbol is beside the
-- tracking symbol there, not under it, where it would be over the next quest.
local tall = ready:GetHeight()
ready:SetHeight(26)
ns.ArrangeLog()
expect(compass.beside == true and select(1, compass:GetPoint(1)) == "RIGHT" and select(2, compass:GetPoint(1)) == tracker and select(3, compass:GetPoint(1)) == "LEFT", "on a low button the compass symbol is to the left of the tracking symbol")
ready:SetHeight(60)
ns.ArrangeLog()
expect(compass.beside == false and select(3, compass:GetPoint(1)) == "BOTTOM", "on a button with lines under the title it is under the tracking symbol")
ready:SetHeight(tall)
ns.ArrangeLog()
local function symbolLook()
  local red, green, blue, alpha = tracker.symbol:GetVertexColor()
  return red == 1 and green == 0.9 and blue == 0.3 and alpha == 1 and "bright" or (red == 0.8 and alpha == 0.6 and "grey" or "other")
end
expect(H.watched[40] == nil and tracker.tracked == false and symbolLook() == "grey", "quest 40 is not tracked, and the symbol is grey, got " .. symbolLook())
H.click(tracker, "LeftButton", false)
expect(H.watched[40] == true and tracker.tracked == true and symbolLook() == "bright", "a click on the symbol tracks the quest, and the symbol is bright, got " .. symbolLook())
H.click(tracker, "LeftButton", false)
expect(H.watched[40] == nil and tracker.tracked == false and symbolLook() == "grey", "a second click stops tracking, and the symbol is grey again, got " .. symbolLook())
-- The game tracks a limited number of quests. At the limit a click tracks nothing, the game
-- says so (its own function was asked), and the symbol stays grey.
T.world.watchLimit = H.watchCount()
H.click(tracker, "LeftButton", false)
expect(H.watched[40] == nil and tracker.tracked == false and symbolLook() == "grey" and H.count("too many watches") == 1, "at the limit of tracked quests a click tracks nothing and the game says why")
T.world.watchLimit = nil
-- A right-click shows where to turn the quest in.
local openedByMark = H.count("open quest")
H.click(tracker, "RightButton", false)
expect(H.count("open quest") == openedByMark + 1 and H.did[#H.did][2] == 40, "a right-click on the symbol shows where to turn the quest in")
expect(H.watched[40] == nil, "the right-click does not change the tracking")
-- In a fight the game refuses an addon that opens a window: nothing is asked of the game.
T.world.secret = true
expect(ns.ShowTurnIn(40) == false and H.count("open quest") == openedByMark + 1 and T.printed("cannot open in a fight"), "in a fight the quest log is not opened, and the addon says why")
T.world.secret = false
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
expect(logButton(40).Checkbox:GetAlpha() == 0 and ns.CompletedMark(logButton(40)).tracker:IsShown(), "with the option off the quest still has the tracking symbol")
expect(not ns.CompletedMark(logButton(40)).back:IsShown() and logButton(40).Text:GetText() == "A Fishy Peril", "with the option off the quest has no green and its own name")
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

-- The quest tracker at the right of the screen (QuestObjectiveTracker of the stand-in, 04-world.lua):
-- one block for each watched quest, in the order of the quest log: quest 176, then quest 40.
T.world.completed = nil
local tracker = QuestObjectiveTracker
-- What a block hangs under, by its point TOP.
local function under(block)
  for index = 1, block:GetNumPoints() do
    local point, relative, relativePoint, _, y = block:GetPoint(index)
    if point == "TOP" then
      return relative, relativePoint, y
    end
  end
end
local function textColour(region)
  local red, green, blue = region:GetTextColor()
  return string.format("%.2f %.2f %.2f", red, green, blue)
end
local WHITE, GAME_LINE = "1.00 1.00 1.00", "0.80 0.80 0.80"
expect(ns.GetOption("trackerLook") == true, "the look of the quest log on the tracker is on at first")
ns.SetOption("popProgress", false)
ns.SetOption("sortAlpha", false)
local watched40 = H.watched[40]
C_QuestLog.AddQuestWatch(40)
tracker:Update()
local block176, block40 = H.trackerBlocks[176], H.trackerBlocks[40]
expect(block176 ~= nil and block40 ~= nil and tracker.firstBlock == block176 and block176.nextBlock == block40, "the game has quest 176 above quest 40 on the tracker")
expect(ns.TrackerMark(block40) ~= nil and ns.TrackerMark(block176) ~= nil, "after a layout of the tracker by the game each quest has the parts of the addon")
-- A ready quest is a green row in white, another quest keeps the colours of the game.
local mark40, mark176 = ns.TrackerMark(block40), ns.TrackerMark(block176)
local key40, line40 = next(block40.usedLines)
local key176, line176 = next(block176.usedLines)
expect(mark40.on and mark40.back:IsShown() and select(2, mark40.back:GetPoint(1)) == block40, "the ready quest (40) has the green background on its block of the tracker")
expect(textColour(block40.HeaderText) == WHITE and textColour(line40.Text) == WHITE, "the name of the ready quest and its line are white on the tracker, got " .. textColour(block40.HeaderText))
expect(not mark176.on and not mark176.back:IsShown() and textColour(block176.HeaderText) ~= WHITE and textColour(line176.Text) == GAME_LINE, "the quest that is not ready has no green and the colours of the game")
-- The game gives the texts their colours again when the pointer comes onto the name of the quest
-- and when it leaves.
H.run(block40.HeaderButton, "OnEnter")
expect(textColour(block40.HeaderText) == WHITE and textColour(line40.Text) == WHITE, "with the pointer on the ready quest its texts are white")
H.run(block40.HeaderButton, "OnLeave")
expect(textColour(block40.HeaderText) == WHITE and textColour(line40.Text) == WHITE, "after the pointer leaves the ready quest its texts are white again")
H.run(block176.HeaderButton, "OnEnter")
H.run(block176.HeaderButton, "OnLeave")
expect(textColour(block176.HeaderText) ~= WHITE and textColour(line176.Text) == GAME_LINE, "and the texts of the other quest are not made white")
-- Without a new order the blocks stay where the game put them.
expect(under(block176) == tracker.ContentsFrame and under(block40) == block176, "with no order of the addon the quests are in the order of the game")
-- The game uses a line again for another quest, and sets the colour of a text only when its
-- style changes: a white line that goes to a quest that is not ready gets the game's colour back.
block40.usedLines[key40], block176.usedLines[key176] = line176, line40
tracker:Update()
expect(textColour(line40.Text) == GAME_LINE and textColour(line176.Text) == WHITE, "a white line that the game gives to a quest that is not ready has the game's colour again, got " .. textColour(line40.Text))
-- The compass symbol, in the lower right corner of the quest. Forever Compass is the one from above.
expect(mark40.compass:IsShown() and mark176.compass:IsShown() and select(1, mark40.compass:GetPoint(1)) == "BOTTOMRIGHT" and select(2, mark40.compass:GetPoint(1)) == block40, "with Forever Compass each quest of the tracker has the compass symbol in its lower right corner")
local function trackerCompassLook(compass)
  local red, green, blue, alpha = compass.symbol:GetVertexColor()
  return red == 0.4 and green == 0.8 and blue == 1 and alpha == 1 and "bright" or (red == 0.8 and alpha == 0.6 and "grey" or "other")
end
expect(onCompass[176] == nil and trackerCompassLook(mark176.compass) == "grey", "a quest that is not on the compass has a grey symbol on the tracker")
H.click(mark176.compass, "LeftButton", false)
expect(onCompass[176] == 3 and trackerCompassLook(mark176.compass) == "bright", "a click on the symbol of the tracker puts the quest on the compass, got " .. trackerCompassLook(mark176.compass))
expect(H.watched[176] == true, "the compass symbol of the tracker does not change the tracking of the game")
-- The symbol of the same quest in the quest log is bright too, and a click there shows on the tracker.
QuestMapFrame:Show()
QuestLogQuests_Update()
local logCompass = ns.CompletedMark(logButton(176)).compass
expect(logCompass.onCompass == true, "the quest that the tracker put on the compass has a bright symbol in the quest log too")
H.click(logCompass, "LeftButton", false)
expect(onCompass[176] == nil and trackerCompassLook(mark176.compass) == "grey", "a click in the quest log takes the quest off the compass, and the symbol of the tracker is grey again")
-- A quest with an item button at its right end: the symbol is to the left of the button.
T.world.trackerRightEdge = { [176] = -28 }
tracker:Update()
expect(select(4, mark176.compass:GetPoint(1)) == -24 and select(4, mark40.compass:GetPoint(1)) == 4, "the symbol leaves the room of the item button of the quest free, got " .. tostring(select(4, mark176.compass:GetPoint(1))))
T.world.trackerRightEdge = nil

-- The order, as in the quest log: the quest that made progress (176, earlier in this scenario)
-- first, then the ready quest (40), then the rest. The stand-in has two quests, so a third one
-- that did neither, and the game's note of a quest that it completed for the player (a block
-- with a text as its id), are put above them here, after a layout by the game.
local popUp = CreateFrame("Frame", nil, tracker.ContentsFrame)
popUp:SetHeight(40)
popUp.id = "40COMPLETE"
local block999 = CreateFrame("Frame", nil, tracker.ContentsFrame, "ObjectiveTrackerBlockTemplate")
block999:SetHeight(12)
block999.id, block999.usedLines, block999.rightEdgeOffset = 999, {}, 0
block999.HeaderText:SetText("A quest without progress")
block999.HeaderText.colorStyle = block176.HeaderText.colorStyle
H.gameFrameSet[popUp], H.gameFrameSet[block999], H.gameFrameSet[block999.HeaderButton] = true, true, true
tracker:Update()
local list = { popUp, block999, block176, block40 }
tracker.firstBlock = popUp
for index, block in ipairs(list) do
  block.nextBlock = list[index + 1]
  block:ClearAllPoints()
  if index == 1 then
    block:SetPoint("TOP", tracker.ContentsFrame, "TOP", 0, tracker.fromHeaderOffsetY)
  else
    block:SetPoint("TOP", list[index - 1], "BOTTOM", 0, tracker.fromBlockOffsetY)
  end
  block:SetPoint("LEFT", tracker.blockOffsetX, 0)
  block:SetPoint("RIGHT")
  block:Show()
end
ns.RefreshTracker()
expect(ns.TrackerMark(popUp) == nil and ns.TrackerMark(block999) ~= nil, "a block of the tracker that is not a quest gets nothing, a third quest gets the parts of the addon")
expect(under(block999) == popUp and under(block176) == block999 and under(block40) == block176, "with no order of the addon the four blocks are where the game put them")
expect(ns.ProgressAt(176) ~= nil and ns.ProgressAt(40) == nil and ns.ProgressAt(999) == nil, "of the three quests only quest 176 made progress")
local layoutsBefore = H.trackerLayouts
ns.SetOption("popProgress", true)
expect(H.trackerLayouts == layoutsBefore and under(popUp) == tracker.ContentsFrame and under(block176) == popUp and under(block40) == block176 and under(block999) == block40, "on the tracker the quest that made progress is first, then the ready quest, then the rest, without a new layout by the game")
expect(select(2, under(block176)) == "BOTTOM" and select(3, under(block176)) == tracker.fromBlockOffsetY and select(2, under(popUp)) == "TOP" and select(3, under(popUp)) == tracker.fromHeaderOffsetY, "the blocks keep the distances of the game")
popUp:Hide()
block999:Hide()
block999.nextBlock = nil
tracker:Update()
expect(under(block176) == tracker.ContentsFrame and under(block40) == block176, "after a layout by the game with its two quests, quest 176 is first")
-- A quest that makes progress glows on the tracker.
T.advance(2)
local progressBefore = ns.ProgressAt(176)
H.questProgress = H.questProgress + 1
T.fire("QUEST_LOG_UPDATE")
T.advance(1)
expect(ns.ProgressAt(176) ~= progressBefore, "quest 176 made progress again")
expect(ns.IsGlowing(block176) and not ns.IsGlowing(block40), "the quest that made progress glows on the tracker, the other quest does not")
T.advance(8)
expect(not ns.IsGlowing(block176), "the glow on the tracker ends after a few seconds")
-- By name: "A Fishy Peril" before "Wanted: Hogger". The order stays after a new layout by the
-- game, and the game's order comes back without one.
ns.SetOption("popProgress", false)
layoutsBefore = H.trackerLayouts
ns.SetOption("sortAlpha", true)
expect(H.trackerLayouts == layoutsBefore and under(block40) == tracker.ContentsFrame and under(block176) == block40, "sorted by name, quest 40 is first on the tracker")
tracker:Update()
expect(under(block40) == tracker.ContentsFrame and under(block176) == block40, "after a new layout by the game the order of the addon is set again")
layoutsBefore = H.trackerLayouts
ns.SetOption("sortAlpha", false)
expect(H.trackerLayouts == layoutsBefore and under(block176) == tracker.ContentsFrame and under(block40) == block176, "with both orders off the quests are in the order of the game again")
-- With the option off the tracker is the game's again.
ns.SetOption("sortAlpha", true)
ns.SetOption("trackerLook", false)
expect(not mark40.back:IsShown() and not mark40.compass:IsShown() and not mark176.compass:IsShown(), "with the option off the quests of the tracker have no green and no compass symbol")
-- The game gives the "Ready for turn-in" line of a ready quest its grey for a finished line.
local READY_LINE = "0.60 0.60 0.60"
expect(textColour(block40.HeaderText) ~= WHITE and textColour(select(2, next(block40.usedLines)).Text) == READY_LINE, "and the texts have the colours of the game, got " .. textColour(select(2, next(block40.usedLines)).Text))
expect(under(block176) == tracker.ContentsFrame and under(block40) == block176, "and the quests are in the order of the game")
T.slash("/fq", "tracker")
expect(ns.GetOption("trackerLook") == true and mark40.back:IsShown() and T.printed("on the tracker"), "/fq tracker turns it on again")
ns.SetOption("sortAlpha", false)
ns.SetOption("popProgress", true)
if not watched40 then
  C_QuestLog.RemoveQuestWatch(40)
end
tracker:Update()
QuestMapFrame:Hide()
