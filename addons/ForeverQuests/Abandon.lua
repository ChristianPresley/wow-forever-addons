local _, ns = ...

-- When the player abandons a quest: a chat message with the progress that goes with it.
--
-- The game asks "Abandon <quest>?" from QuestMapQuestOptions_AbandonQuest(questID), which the quest
-- log and the menu of the tracker both call (Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua,
-- Blizzard_ObjectiveTracker/Blizzard_QuestObjectiveTracker.lua). The addon runs after it through
-- hooksecurefunc and only reads the quest, so the game's dialog is untouched.

local function usable(value)
  return value ~= nil and not ns.IsSecret(value)
end

-- The objectives the player has made progress on, as the game writes them ("Gnoll Paw: 6/10").
local function progressLines(questID)
  local lines = {}
  local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
  if not ok or type(objectives) ~= "table" then
    return lines
  end
  for _, objective in ipairs(objectives) do
    local text = objective.text
    local done = usable(objective.finished) and objective.finished
    local some = usable(objective.numFulfilled) and type(objective.numFulfilled) == "number" and objective.numFulfilled > 0
    if usable(text) and type(text) == "string" and text ~= "" and (done or some) then
      lines[#lines + 1] = text
    end
  end
  return lines
end

-- The message for a quest, or nil when nothing is lost.
function ns.AbandonWarning(questID)
  if type(questID) ~= "number" then
    return nil
  end
  local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
  if not (usable(title) and type(title) == "string" and title ~= "") then
    title = "this quest"
  end
  if ns.IsReady and ns.IsReady(questID) then
    return string.format("%s is ready to turn in. Abandon it and its rewards are lost.", title)
  end
  local lines = progressLines(questID)
  if #lines == 0 then
    return nil
  end
  return string.format("abandon %s and you lose: %s.", title, table.concat(lines, "; "))
end

local hooked = false

local function hook()
  if hooked or type(QuestMapQuestOptions_AbandonQuest) ~= "function" then
    return hooked
  end
  hooked = true
  hooksecurefunc("QuestMapQuestOptions_AbandonQuest", function(questID)
    if not ns.GetOption("abandonWarning") then
      return
    end
    local ok, message = pcall(ns.AbandonWarning, questID)
    if ok and message then
      ns.Print(message)
    end
  end)
  return true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
local loggedIn = false
frame:SetScript("OnEvent", function(self, event)
  loggedIn = loggedIn or event == "PLAYER_LOGIN"
  -- The quest log of the game can load later than this addon.
  if loggedIn and hook() then
    self:UnregisterAllEvents()
  end
end)
