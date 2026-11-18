local _, ns = ...

-- The chain of a quest, beside its details in the quest log: the name of the chain and its steps,
-- each one done, this quest, in the quest log, or still to come.
--
-- The game knows the chains (quest lines) itself: C_QuestLine.GetQuestLineInfo gives the chain of a
-- quest and C_QuestLine.GetQuestLineQuests its quests in order. A quest that is in no chain of the
-- game gets no panel. The panel hangs under the item panel of Items.lua when that one is shown.

local WIDTH, PAD, ROW = 230, 8, 16
local MAX_ROWS = 12

local panel, shownQuest
local rows = {}

local function usable(value)
  return value ~= nil and not ns.IsSecret(value)
end

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, result = pcall(fn, ...)
  if ok and usable(result) then
    return result
  end
  return nil
end

local function titleOf(questID)
  local title = C_QuestLog.GetTitleForQuestID and call(C_QuestLog.GetTitleForQuestID, questID)
  if type(title) == "string" and title ~= "" then
    return title
  end
  return nil
end

-- The chain of a quest: { name, index, steps = { { questID, title, state } } }, or nil.
-- state is "done", "this", "log" (in the quest log) or "later".
function ns.QuestChain(questID)
  if type(questID) ~= "number" or not C_QuestLine then
    return nil
  end
  local info = call(C_QuestLine.GetQuestLineInfo, questID)
  local lineID = type(info) == "table" and usable(info.questLineID) and info.questLineID
  if type(lineID) ~= "number" then
    return nil
  end
  local ids = call(C_QuestLine.GetQuestLineQuests, lineID)
  if type(ids) ~= "table" or #ids < 2 then
    return nil -- a chain of one quest says nothing
  end
  local chain = { name = usable(info.questLineName) and info.questLineName or "Quest chain", steps = {} }
  for index, id in ipairs(ids) do
    local state
    if id == questID then
      state, chain.index = "this", index
    elseif C_QuestLog.IsQuestFlaggedCompleted and call(C_QuestLog.IsQuestFlaggedCompleted, id) then
      state = "done"
    elseif C_QuestLog.GetLogIndexForQuestID and call(C_QuestLog.GetLogIndexForQuestID, id) then
      state = "log"
    else
      state = "later"
    end
    chain.steps[index] = { questID = id, title = titleOf(id), state = state }
  end
  if not chain.index then
    return nil
  end
  return chain
end

local MARKS = {
  done = { "|cff4dff4d+|r", 0.6, 0.6, 0.6 },
  this = { "|cffffd100>|r", 1, 0.82, 0 },
  log = { "|cffffffff-|r", 1, 1, 1 },
  later = { "|cff808080-|r", 0.6, 0.6, 0.6 },
}

-- The rows of the panel as texts, for the tests: "+ Step one", "> This quest", "- Step three".
function ns.QuestChainLines(questID)
  local chain = ns.QuestChain(questID)
  if not chain then
    return nil
  end
  local lines = { string.format("%s: step %d of %d", chain.name, chain.index, #chain.steps) }
  for _, step in ipairs(chain.steps) do
    local mark = ({ done = "+", this = ">", log = "-", later = "-" })[step.state]
    lines[#lines + 1] = mark .. " " .. (step.title or "a quest you have not seen")
  end
  return lines
end

local function rowAt(index)
  if rows[index] then
    return rows[index]
  end
  local row = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row:SetPoint("TOPLEFT", PAD, -26 - (index - 1) * ROW)
  row:SetPoint("RIGHT", -PAD, 0)
  row:SetJustifyH("LEFT")
  row:SetWordWrap(false)
  rows[index] = row
  return row
end

local function create()
  local details = QuestMapFrame and QuestMapFrame.DetailsFrame
  if not details then
    return false
  end
  panel = CreateFrame("Frame", "ForeverQuestsChain", details)
  panel:SetFrameStrata("HIGH")
  panel:SetWidth(WIDTH)
  local background = panel:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.04, 0.04, 0.05, 0.9)
  panel.title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  panel.title:SetPoint("TOPLEFT", PAD, -7)
  panel.title:SetPoint("RIGHT", -PAD, 0)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetWordWrap(false)
  panel:Hide()
  return true
end

local function place()
  local items = _G["ForeverQuestsItems"]
  local portrait = _G["QuestModelScene"]
  panel:ClearAllPoints()
  if type(items) == "table" and type(items.IsShown) == "function" and items:IsShown() then
    panel:SetPoint("TOPLEFT", items, "BOTTOMLEFT", 0, -6)
  elseif type(portrait) == "table" and type(portrait.IsShown) == "function" and portrait:IsShown() then
    panel:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 6, 0)
  else
    panel:SetPoint("TOPLEFT", QuestMapFrame, "TOPRIGHT", 6, -24)
  end
end

local function show(questID)
  shownQuest = questID
  local chain = ns.GetOption("questChain") and ns.QuestChain(questID)
  if not chain then
    if panel then
      panel:Hide()
    end
    return
  end
  if not panel and not create() then
    return
  end
  panel.title:SetText(string.format("%s (%d/%d)", chain.name, chain.index, #chain.steps))
  -- A long chain shows the steps around this quest.
  local first = math.max(1, math.min(chain.index - math.floor(MAX_ROWS / 2), #chain.steps - MAX_ROWS + 1))
  local count = math.min(MAX_ROWS, #chain.steps)
  for index = 1, count do
    local step = chain.steps[first + index - 1]
    local mark = MARKS[step.state]
    local row = rowAt(index)
    row:SetText(mark[1] .. " " .. (step.title or "a quest you have not seen"))
    row:SetTextColor(mark[2], mark[3], mark[4])
    row:Show()
  end
  for index = count + 1, #rows do
    rows[index]:Hide()
  end
  panel:SetHeight(26 + count * ROW + PAD)
  place()
  panel:Show()
end

ns.OnOptionChanged(function(key)
  if key == "questChain" and shownQuest then
    pcall(show, shownQuest)
  end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    -- After Items.lua (later in the TOC), so the item panel is placed first.
    if type(QuestMapFrame_ShowQuestDetails) == "function" then
      hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
        pcall(show, questID)
      end)
    end
    for _, name in ipairs({ "QUEST_LOG_UPDATE", "QUESTLINE_UPDATE", "QUEST_TURNED_IN" }) do
      pcall(self.RegisterEvent, self, name)
    end
    return
  end
  if shownQuest and panel and panel:IsVisible() then
    pcall(show, shownQuest)
  end
end)
