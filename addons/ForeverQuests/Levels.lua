local _, ns = ...

-- The quest level in front of the quest name, coloured by difficulty, in the quest log of the map
-- (QuestScrollFrame) and in the objective tracker (QuestObjectiveTracker). This client has no
-- QuestLogFrame or QuestWatchFrame. The game writes "[12] " in front of the names itself; then only
-- the colour is added. All of it happens after the game has set the text, and only the text changes.

-- Font string -> { ours = the text we set, original = the text of the game }.
local changed = setmetatable({}, { __mode = "k" })

local function levelOf(questID)
  if not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetInfo) then
    return nil
  end
  local index = C_QuestLog.GetLogIndexForQuestID(questID)
  local info = index and C_QuestLog.GetInfo(index)
  if not info or info.isHeader then
    return nil
  end
  local level = info.difficultyLevel or info.level
  if ns.IsSecret(level) or type(level) ~= "number" or level < 1 then
    return nil
  end
  local elite = C_QuestLog.IsEliteQuest and C_QuestLog.IsEliteQuest(questID)
  return math.floor(level), elite and not ns.IsSecret(elite)
end

local function colorCode(questID, level)
  local color
  if C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer and GetDifficultyColor then
    color = GetDifficultyColor(C_PlayerInfo.GetContentDifficultyQuestForPlayer(questID))
  elseif GetQuestDifficultyColor then
    color = GetQuestDifficultyColor(level)
  end
  if type(color) ~= "table" or type(color.r) ~= "number" or type(color.g) ~= "number" or type(color.b) ~= "number" then
    return nil
  end
  local function byte(value)
    return math.floor(math.max(0, math.min(1, value)) * 255 + 0.5)
  end
  return string.format("|cff%02x%02x%02x", byte(color.r), byte(color.g), byte(color.b))
end

local function decorate(fontString, questID)
  if not (fontString and fontString.GetText and fontString.SetText and fontString.GetStringHeight) then
    return
  end
  local text = fontString:GetText()
  if ns.IsSecret(text) or type(text) ~= "string" or text == "" or ns.IsSecret(questID) or type(questID) ~= "number" then
    return
  end
  local level, elite = levelOf(questID)
  local color = level and colorCode(questID, level)
  if not color then
    return
  end
  local first, last = text:find("[" .. level .. "+]", 1, true)
  if not first then
    first, last = text:find("[" .. level .. "]", 1, true)
  end
  local new
  if first then
    -- The level is in the text already. A text with colour codes is left as it is.
    if text:find("|c", 1, true) then
      return
    end
    new = text:sub(1, first - 1) .. color .. text:sub(first, last) .. "|r" .. text:sub(last + 1)
    fontString:SetText(new)
  else
    local height = fontString:GetStringHeight()
    new = color .. "[" .. level .. (elite and "+" or "") .. "]|r " .. text
    fontString:SetText(new)
    -- The game has measured the line already. A name that needs one more line now stays as it was.
    if math.abs(fontString:GetStringHeight() - height) > 0.5 then
      fontString:SetText(text)
      return
    end
  end
  changed[fontString] = { ours = new, original = text }
end

local function updateLog()
  if not ns.GetOption("questLevels") then
    return
  end
  local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
  if not (pool and pool.EnumerateActive) then
    return
  end
  for button in pool:EnumerateActive() do
    if button.questID and button.Text then
      decorate(button.Text, button.questID)
    end
  end
end

local function updateBlock(block)
  if block and block.id and block.HeaderText then
    decorate(block.HeaderText, block.id)
  end
end

local trackers = {}

local function updateTrackers()
  if not ns.GetOption("questLevels") then
    return
  end
  for _, tracker in ipairs(trackers) do
    if tracker.EnumerateActiveBlocks then
      tracker:EnumerateActiveBlocks(updateBlock)
    end
  end
end

local function restore()
  for fontString, texts in pairs(changed) do
    if fontString:GetText() == texts.ours then
      fontString:SetText(texts.original)
    end
    changed[fontString] = nil
  end
end

local logHooked = false
local trackerHooked = {}

-- Returns true when there is nothing left to hook.
local function hook()
  if not logHooked and type(QuestLogQuests_Update) == "function" and QuestScrollFrame then
    logHooked = true
    hooksecurefunc("QuestLogQuests_Update", function()
      pcall(updateLog)
    end)
  end
  for _, name in ipairs({ "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }) do
    local tracker = _G[name]
    if not trackerHooked[name] and type(tracker) == "table" and type(tracker.UpdateSingle) == "function"
      and type(tracker.GetExistingBlock) == "function" then
      trackerHooked[name] = true
      trackers[#trackers + 1] = tracker
      hooksecurefunc(tracker, "UpdateSingle", function(self, quest)
        if not ns.GetOption("questLevels") then
          return
        end
        pcall(function()
          local questID = quest and quest.GetID and quest:GetID()
          if questID then
            updateBlock(self:GetExistingBlock(questID))
          end
        end)
      end)
    end
  end
  return logHooked and trackerHooked.QuestObjectiveTracker
end

ns.OnOptionChanged(function(key, value)
  if key ~= "questLevels" then
    return
  end
  if value then
    pcall(updateLog)
    pcall(updateTrackers)
  else
    pcall(restore)
  end
end)

local loggedIn = false
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    loggedIn = true
  end
  -- The frames of the game can load later than this addon.
  if loggedIn and hook() then
    self:UnregisterAllEvents()
  end
end)
