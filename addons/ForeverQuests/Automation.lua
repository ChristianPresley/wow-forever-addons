local _, ns = ...

-- Optional automatic accept and turn-in. Hold Shift while talking to an NPC to skip it once.

local function enabled(option)
  return ForeverQuestsDB and ForeverQuestsDB.options[option] and not IsShiftKeyDown()
end

local function onGossip()
  if not C_GossipInfo then
    return
  end
  if enabled("autoTurnIn") then
    for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
      if quest.isComplete and quest.questID then
        C_GossipInfo.SelectActiveQuest(quest.questID)
        return
      end
    end
  end
  if enabled("autoAccept") then
    for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
      -- Repeatable quests are skipped: accepting them in a loop can spend items.
      if quest.questID and not quest.repeatable then
        C_GossipInfo.SelectAvailableQuest(quest.questID)
        return
      end
    end
  end
end

local function onGreeting()
  if enabled("autoTurnIn") then
    for i = 1, GetNumActiveQuests() do
      local _, isComplete = GetActiveTitle(i)
      if isComplete then
        SelectActiveQuest(i)
        return
      end
    end
  end
  if enabled("autoAccept") and GetNumAvailableQuests() > 0 then
    SelectAvailableQuest(1)
  end
end

local function onDetail()
  if not enabled("autoAccept") then
    return
  end
  if QuestGetAutoAccept and QuestGetAutoAccept() then
    if AcknowledgeAutoAcceptQuest then
      AcknowledgeAutoAcceptQuest()
    end
  else
    AcceptQuest()
  end
end

local function onProgress()
  if enabled("autoTurnIn") and IsQuestCompletable() then
    CompleteQuest()
  end
end

local function onComplete()
  -- With more than one reward to choose from, the choice stays with the player.
  if enabled("autoTurnIn") and GetNumQuestChoices() <= 1 then
    GetQuestReward(1)
  end
end

local handlers = {
  GOSSIP_SHOW = onGossip,
  QUEST_GREETING = onGreeting,
  QUEST_DETAIL = onDetail,
  QUEST_PROGRESS = onProgress,
  QUEST_COMPLETE = onComplete,
}

local frame = CreateFrame("Frame")
for event in pairs(handlers) do
  pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event)
  handlers[event]()
end)
