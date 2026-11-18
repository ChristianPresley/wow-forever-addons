local _, ns = ...

-- The quest tracker at the right of the screen (QuestObjectiveTracker of the game), with the
-- option trackerLook: what this addon does in the quest log, it does there too.
--
--   a quest that is ready to turn in is a green row in white text (option completeFanfare)
--   a quest that made progress glows for a few seconds (option popProgress)
--   the order: a quest that made progress first, then the ready quests (popProgress), and the
--              quests by name (sortAlpha)
--   each quest has the compass symbol, if Forever Compass is loaded: a click makes a tracker of
--              the compass point to the quest, a second click takes it off the compass again
--
-- Which quests the tracker lists is the watch list of the game: the tracking symbol of the quest
-- log (LogOrder.lua) and "current zone only" (ZoneFilter.lua) change it.
--
-- The tracker is the game's own, and the game refuses its own actions after addon code wrote to
-- its tables (taint). So this file only reads the fields of the tracker, keeps what it knows in
-- its own tables, and adds textures and buttons of its own to the quests. It runs after the game
-- has laid the tracker out (hooksecurefunc). It does not move, hide or collapse the tracker:
-- that is the game's (its header button, and Edit Mode).
--
-- From Blizzard_ObjectiveTracker (Module.lua, Block.lua, QuestObjectiveTracker.lua):
--   the module has firstBlock, and each block has nextBlock: the quests from top to bottom
--   a block has id (the quest ID), HeaderText, HeaderButton, usedLines[key].Text and
--     rightEdgeOffset (the room that the item button of the quest takes at the right)
--   each block hangs under the one before it, the first under ContentsFrame, by its point TOP
--     (ObjectiveTrackerModuleMixin:AnchorBlock)
--   the game sets the colour of a text only when its colorStyle changes
--     (ObjectiveTrackerBlockMixin:SetStringText), and again when the pointer comes onto the
--     quest or leaves it (UpdateHighlight).

local SYMBOL_SIZE = 13
local SYMBOL_ROOM = 4 -- around the compass symbol, on each side: it takes the click too
local BLOCK_GAP = -10 -- between two quests, if the module does not say (fromBlockOffsetY)

local marks = setmetatable({}, { __mode = "k" }) -- marks[block] = { on, back, compass }
local whitened = setmetatable({}, { __mode = "k" }) -- the texts that this file made white
local hookedHeaders = setmetatable({}, { __mode = "k" })
local arranged = false -- true while the quests are in another order than the game's

local function isQuestBlock(block)
  return type(block.id) == "number" and type(block.HeaderText) == "table" and type(block.CreateTexture) == "function"
end

-- The blocks of the tracker from top to bottom.
local function chain(tracker)
  local list, block = {}, tracker.firstBlock
  while type(block) == "table" and #list < 100 do
    list[#list + 1] = block
    block = block.nextBlock
  end
  return list
end

---------------------------------------------------------------------------------------------------
-- The look of a ready quest

-- Gives each text that this file made white the colour of the game again. The game keeps the
-- colour of a text in its colorStyle, and uses a line again for another quest.
local function restoreColours()
  for text in pairs(whitened) do
    local style = text.colorStyle
    if type(style) == "table" and type(style.r) == "number" and type(style.g) == "number" and type(style.b) == "number" then
      text:SetTextColor(style.r, style.g, style.b)
    end
    whitened[text] = nil
  end
end

local function whitenText(text)
  if type(text) == "table" and type(text.SetTextColor) == "function" then
    text:SetTextColor(1, 1, 1)
    whitened[text] = true
  end
end

local function whiten(block)
  whitenText(block.HeaderText)
  if type(block.usedLines) == "table" then
    for _, line in pairs(block.usedLines) do
      if type(line) == "table" then
        whitenText(line.Text)
      end
    end
  end
end

local function createMark(block)
  local mark = { on = false }
  -- Under the texts of the quest, and under its icon at the left of the name.
  mark.back = block:CreateTexture(nil, "BACKGROUND")
  mark.back:SetPoint("TOPLEFT", -26, 3)
  mark.back:SetPoint("BOTTOMRIGHT", 2, -3)
  mark.back:SetColorTexture(0.1, 0.5, 0.15, 0.9)
  mark.back:Hide()

  -- The compass symbol (Media/Compass.tga), as in the quest log.
  local compass = CreateFrame("Button", nil, block)
  compass:SetSize(SYMBOL_SIZE + 2 * SYMBOL_ROOM, SYMBOL_SIZE + 2 * SYMBOL_ROOM)
  compass.symbol = compass:CreateTexture(nil, "OVERLAY")
  compass.symbol:SetTexture("Interface\\AddOns\\ForeverQuests\\Media\\Compass")
  compass.symbol:SetSize(SYMBOL_SIZE, SYMBOL_SIZE)
  compass.symbol:SetPoint("CENTER")
  compass:RegisterForClicks("LeftButtonUp")
  compass:SetScript("OnClick", function(self)
    if self.questID then
      ns.ToggleCompass(self.questID)
      ns.ShowOnCompass(self)
      if ns.RefreshQuestLog then
        ns.RefreshQuestLog() -- the same symbol in the quest log
      end
    end
  end)
  compass:SetScript("OnEnter", function(self)
    local index = ns.CompassTracker(self.questID)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Track in compass", 1, 1, 1)
    GameTooltip:AddLine(index and ("Tracker " .. index .. " of the compass points to this quest. Click to take it off the compass.")
      or "Click to make a tracker of the compass point to this quest.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  compass:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  compass:Hide()
  mark.compass = compass
  return mark
end

-- The game gives the texts of a quest their own colours again when the pointer comes onto its
-- name and when it leaves. After that, the texts of a ready quest are white again.
local function hookHeader(block)
  local header = block.HeaderButton
  if hookedHeaders[block] or type(header) ~= "table" or type(header.HookScript) ~= "function" then
    return
  end
  hookedHeaders[block] = true
  for _, script in ipairs({ "OnEnter", "OnLeave" }) do
    pcall(header.HookScript, header, script, function()
      local mark = marks[block]
      if mark and mark.on then
        whiten(block)
      end
    end)
  end
end

local function updateBlock(block, on, visible)
  local questID = block.id
  local mark = marks[block]
  ns.UpdateGlow(block, questID, on and ns.GetOption("popProgress"), visible, "trackerShine")
  if not on then
    if mark then
      mark.on = false
      mark.back:Hide()
      mark.compass:Hide()
    end
    return
  end
  if not mark then
    mark = createMark(block)
    marks[block] = mark
  end
  hookHeader(block)

  -- The compass symbol is in the lower right corner of the quest, beside its last line: the
  -- name of a quest can fill the first line. The item button of a quest is at the upper right
  -- (ObjectiveTrackerBlockMixin:AddRightEdgeFrame), and the lines end to the left of it.
  local compass = mark.compass
  compass.questID = questID
  local edge = type(block.rightEdgeOffset) == "number" and block.rightEdgeOffset or 0
  compass:ClearAllPoints()
  compass:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", edge + SYMBOL_ROOM, -SYMBOL_ROOM)
  compass:SetFrameLevel(block:GetFrameLevel() + 3)
  if ns.HasCompass() then
    ns.ShowOnCompass(compass)
    compass:Show()
  else
    compass:Hide()
  end

  mark.on = ns.GetOption("completeFanfare") and ns.IsReady(questID)
  if mark.on then
    mark.back:Show()
    whiten(block)
  else
    mark.back:Hide()
  end
end

---------------------------------------------------------------------------------------------------
-- Order

local function sortName(questID)
  local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
  if not ok or ns.IsSecret(title) or type(title) ~= "string" then
    return ""
  end
  return title:lower()
end

-- The blocks in the order of this addon, or nil if that is the order of the game. A block that
-- is not a quest (the game's note of a quest that it accepted or completed for the player) keeps
-- its place.
local function wantedOrder(blocks, on)
  local pop, alpha = on and ns.GetOption("popProgress"), on and ns.GetOption("sortAlpha")
  if not (pop or alpha) then
    return nil
  end
  local ready = ns.GetOption("completeFanfare")
  local places, items = {}, {}
  for i, block in ipairs(blocks) do
    if isQuestBlock(block) then
      places[#places + 1] = i
      -- As in the quest log: a quest that made progress is first, the newest at the top. Then
      -- the quests that are ready to turn in, then the rest.
      local at = pop and (ns.ProgressAt(block.id) or (ready and ns.IsReady(block.id) and 0.5)) or 0
      items[#items + 1] = { block = block, place = #places, at = at, name = alpha and sortName(block.id) or "" }
    end
  end
  if #items < 2 then
    return nil
  end
  table.sort(items, function(a, b)
    if a.at ~= b.at then
      return a.at > b.at
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.place < b.place
  end)
  local order, moved = {}, false
  for i, block in ipairs(blocks) do
    order[i] = block
  end
  for i, item in ipairs(items) do
    if item.place ~= i then
      moved = true
    end
    order[places[i]] = item.block
  end
  return moved and order or nil
end

-- Hangs the blocks under each other in the order of this addon. The game does not lay the
-- tracker out on each of its updates, so the order of the game is put back here too.
local function arrange(tracker, blocks, on)
  local order = wantedOrder(blocks, on)
  if not order then
    if not arranged then
      return
    end
    order = blocks
  end
  arranged = order ~= blocks
  local contents = tracker.ContentsFrame
  if type(contents) ~= "table" then
    return
  end
  local first = type(tracker.fromHeaderOffsetY) == "number" and tracker.fromHeaderOffsetY or BLOCK_GAP
  local between = type(tracker.fromBlockOffsetY) == "number" and tracker.fromBlockOffsetY or BLOCK_GAP
  -- First each block under the top, so that no block hangs under one that hangs under it.
  for _, block in ipairs(order) do
    block:SetPoint("TOP", contents, "TOP", 0, first)
  end
  for i = 2, #order do
    order[i]:SetPoint("TOP", order[i - 1], "BOTTOM", 0, between)
  end
end

---------------------------------------------------------------------------------------------------
-- Wiring

-- The quest part of the game's tracker (Blizzard_QuestObjectiveTracker.xml), or nil.
local function questTracker()
  local tracker = QuestObjectiveTracker
  return type(tracker) == "table" and tracker or nil
end

local function apply()
  local tracker = questTracker()
  if not tracker then
    return
  end
  local on = ns.GetOption("trackerLook")
  local blocks = chain(tracker)
  local visible = type(tracker.IsVisible) == "function" and tracker:IsVisible() and true or false
  restoreColours()
  for _, block in ipairs(blocks) do
    if isQuestBlock(block) then
      updateBlock(block, on, visible)
    end
  end
  arrange(tracker, blocks, on)
end

local hooked = false

local function hook()
  if hooked then
    return true
  end
  local tracker = questTracker()
  if not tracker or type(tracker.Update) ~= "function" then
    return false
  end
  hooked = true
  -- After each layout of the quests by the game (ObjectiveTrackerModuleMixin:Update).
  hooksecurefunc(tracker, "Update", function()
    pcall(apply)
  end)
  return true
end

-- Sets the look and the order again, without a new layout by the game.
function ns.RefreshTracker()
  if hook() then
    pcall(apply)
  end
end

-- The parts of this addon on the block of a quest in the tracker: { on (the look of a ready
-- quest), back, compass }, or nil.
function ns.TrackerMark(block)
  return marks[block]
end

ns.OnOptionChanged(function(option)
  if option == "trackerLook" or option == "popProgress" or option == "sortAlpha" or option == "completeFanfare" then
    ns.RefreshTracker()
  end
end)

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
local loggedIn = false
frame:SetScript("OnEvent", function(self, event)
  loggedIn = loggedIn or event == "PLAYER_LOGIN"
  -- The tracker of the game can load later than this addon.
  if loggedIn and hook() then
    self:UnregisterEvent("ADDON_LOADED")
    pcall(apply)
  end
end)
