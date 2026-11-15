local _, ns = ...

-- Compares the quest log with its previous state and reports what changed.

local previous
local pending = false

local function snapshot()
  local quests = {}
  for i = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(i)
    if info and not info.isHeader and not info.isHidden and info.questID then
      local objectives = {}
      for j, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
        objectives[j] = { text = objective.text, finished = objective.finished and true or false }
      end
      quests[info.questID] = {
        title = info.title,
        complete = C_QuestLog.IsComplete(info.questID) and true or false,
        objectives = objectives,
      }
    end
  end
  return quests
end

local function report(old, new)
  local options = ForeverQuestsDB.options
  local ready = false
  for questID, quest in pairs(new) do
    local before = old[questID]
    if before then
      if quest.complete and not before.complete then
        ready = true
        if options.announce then
          ns.Print("ready to turn in: " .. (quest.title or questID))
        end
      elseif options.announce then
        for j, objective in ipairs(quest.objectives) do
          local was = before.objectives[j]
          if objective.finished and was and not was.finished and objective.text then
            ns.Print("done: " .. objective.text)
          end
        end
      end
    end
  end
  if ready and options.sound and PlaySound then
    PlaySound((SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE) or 878)
  end
end

local function update()
  pending = false
  if not ForeverQuestsDB then
    return
  end
  local current = snapshot()
  if previous then
    report(previous, current)
  end
  previous = current
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("QUEST_LOG_UPDATE")
pcall(frame.RegisterEvent, frame, "QUEST_TURNED_IN")
frame:SetScript("OnEvent", function(_, event, questID, xp, money)
  if event == "QUEST_TURNED_IN" then
    if not ForeverQuestsCharDB then
      return
    end
    xp = type(xp) == "number" and xp or 0
    money = type(money) == "number" and money or 0
    for _, totals in ipairs({ ns.session, ForeverQuestsCharDB }) do
      totals.quests = totals.quests + 1
      totals.xp = totals.xp + xp
      totals.money = totals.money + money
    end
    return
  end
  -- QUEST_LOG_UPDATE fires in bursts. One comparison per burst is enough.
  if not pending then
    pending = true
    C_Timer.After(0.3, update)
  end
end)
