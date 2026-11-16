local _, ns = ...

-- The order of the quests in the quest log, and the glow on a quest that made progress.
--
--   popProgress: a quest that made progress goes to the top of its zone, the most recent one first,
--                and glows for a few seconds the next time the quest log shows it.
--   sortAlpha:   the quests of each zone are in the order of their names.
--   completeFanfare: a quest that is ready to turn in has a COMPLETED mark, and with popProgress
--                it is above the quests that are not ready.
--
-- The glow starts when the player sees the quest. The game builds the log at times when it is
-- not on the screen, so this file also runs when the log comes onto the screen.
--
-- The game gives each button of the quest log a layoutIndex, and its layout puts the buttons in that
-- order. ns.ArrangeLog runs after the game has built the log and gives the buttons of one zone each
-- other's places. The objective lines and the map icon of a quest are anchored to its button, so
-- they move with it. The quests stay under their own zone header.

local SHINE_SECONDS = 6
local POP_SECONDS = 0.35 -- the glow starts larger than the quest and brighter, then settles

-- progressed[questID] = { at = time of the progress, shineStart = time of the first show, or nil }
local progressed = {}

-- Progress.lua calls this for a quest with a new objective count, a finished objective or all done.
function ns.OnQuestProgress(questID)
  progressed[questID] = { at = GetTime() }
  if ns.GetOption("popProgress") and ns.RefreshQuestLog then
    ns.RefreshQuestLog()
  end
end

---------------------------------------------------------------------------------------------------
-- Glow

local glows = setmetatable({}, { __mode = "k" }) -- glows[button]

local function onGlowUpdate(self)
  local now = GetTime()
  local left = self.startTime + SHINE_SECONDS - now
  if left <= 0 then
    self:Hide()
    return
  end
  local age = now - self.startTime
  local settle = math.max(0, 1 - age / POP_SECONDS) -- 1 at the start, 0 after the pop
  local grow = 7 * settle
  self:ClearAllPoints()
  self:SetPoint("TOPLEFT", self.button, "TOPLEFT", -grow, grow)
  self:SetPoint("BOTTOMRIGHT", self.button, "BOTTOMRIGHT", grow, -grow)
  local pulse = 0.22 + 0.2 * math.abs(math.sin(age * 3.5))
  local alpha = pulse + (0.8 - pulse) * settle
  self:SetAlpha(alpha * math.min(1, left)) -- fades out in the last second
end

local function createGlow(button)
  local glow = CreateFrame("Frame", nil, button)
  glow.button = button
  glow:SetFrameLevel(button:GetFrameLevel() + 2)
  local fill = glow:CreateTexture(nil, "OVERLAY")
  fill:SetAllPoints()
  fill:SetColorTexture(1, 0.78, 0.12, 0.55)
  fill:SetBlendMode("ADD")
  for _, point in ipairs({ "TOP", "BOTTOM" }) do
    local edge = glow:CreateTexture(nil, "OVERLAY")
    edge:SetColorTexture(1, 0.95, 0.6, 1)
    edge:SetBlendMode("ADD")
    edge:SetHeight(1.5)
    edge:SetPoint(point .. "LEFT")
    edge:SetPoint(point .. "RIGHT")
  end
  glow:SetScript("OnUpdate", onGlowUpdate)
  glow:Hide()
  return glow
end

-- Shows the glow on the button of a quest that made progress, and hides an old glow of the button
-- (the game uses a button again for a different quest).
local function updateGlow(button, enabled, visible)
  local entry = enabled and button.questID and progressed[button.questID]
  local now = GetTime()
  if entry and not entry.shineStart and visible then
    entry.shineStart = now -- the player sees the quest now for the first time since the progress
  end
  local glow = glows[button]
  if entry and entry.shineStart and now < entry.shineStart + SHINE_SECONDS then
    if not glow then
      glow = createGlow(button)
      glows[button] = glow
    end
    glow.startTime = entry.shineStart
    glow:Show()
    onGlowUpdate(glow)
  elseif glow then
    glow:Hide()
  end
end

-- True if the button of the quest log glows now.
function ns.IsGlowing(button)
  local glow = glows[button]
  return glow ~= nil and glow:IsShown()
end

---------------------------------------------------------------------------------------------------
-- The COMPLETED mark

local badges = setmetatable({}, { __mode = "k" }) -- badges[button]

local function isComplete(questID)
  if not questID then
    return false
  end
  local ok, complete = pcall(C_QuestLog.IsComplete, questID)
  return ok and complete and true or false
end

-- The mark is where the game has the box that tracks the quest (button.Checkbox, at the right
-- of the title). It covers the box in full, and the box is not drawn under it, so nothing
-- shows through. The mark is the tracking box of a ready quest: a click tracks the quest or
-- stops tracking it, the same as the box. The tracking symbol at the right end of the mark
-- is grey while the quest is not tracked and bright while it is. A
-- right-click shows where to turn the quest in. A quest that is not ready has its box back.
-- The game uses a button again for another quest, so the box is set each time.
local function trackBox(button)
  local box = button.Checkbox
  return type(box) == "table" and type(box.SetAlpha) == "function" and box or nil
end

local function isTracked(questID)
  local ok, kind = pcall(C_QuestLog.GetQuestWatchType, questID)
  return ok and kind ~= nil
end

-- Tracks a quest or stops tracking it, as the box of the game does
-- (QuestMapQuestOptions_TrackQuest in QuestMapFrame.lua). Returns true if the quest is tracked after.
function ns.ToggleTracking(questID)
  local tracked = isTracked(questID)
  if tracked then
    pcall(C_QuestLog.RemoveQuestWatch, questID)
  else
    pcall(C_QuestLog.AddQuestWatch, questID)
  end
  if PlaySound and SOUNDKIT then
    local sound = tracked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
    if sound then
      PlaySound(sound)
    end
  end
  return isTracked(questID)
end

-- The tracking symbol of the mark: grey and dim while the quest is not tracked, in full colour
-- and bright while it is.
local function showTracked(badge)
  local tracked = badge.questID ~= nil and isTracked(badge.questID)
  badge.tracked = tracked
  if tracked then
    badge.symbol:SetVertexColor(1, 0.9, 0.3, 1)
  else
    badge.symbol:SetVertexColor(0.55, 0.55, 0.55, 0.7)
  end
end

local function updateBadge(button, enabled)
  local badge = badges[button]
  local box = trackBox(button)
  if enabled and isComplete(button.questID) then
    if not badge then
      badge = CreateFrame("Button", nil, button)
      local back = badge:CreateTexture(nil, "BACKGROUND")
      back:SetAllPoints()
      back:SetColorTexture(0.1, 0.5, 0.15, 1)
      badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      -- The text is in the part of the mark to the left of the symbol.
      badge.text:SetPoint("CENTER", -8, 0)
      badge.text:SetText("COMPLETED")
      badge.text:SetTextColor(1, 0.95, 0.6)
      -- The tracking symbol at the right end: the picture of this addon (Media/Track.tga, drawn
      -- by `cargo dev track-icon`). It is white, so its colour is the one set here.
      badge.symbol = badge:CreateTexture(nil, "OVERLAY")
      badge.symbol:SetTexture("Interface\\AddOns\\ForeverQuests\\Media\\Track")
      badge.symbol:SetSize(16, 16)
      badge.symbol:SetPoint("RIGHT", -2, 0)
      badge:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      badge:SetScript("OnClick", function(self, mouseButton)
        if not self.questID then
          return
        end
        if mouseButton == "RightButton" then
          if ns.ShowTurnIn then
            ns.ShowTurnIn(self.questID)
          end
        else
          ns.ToggleTracking(self.questID)
          showTracked(self)
        end
      end)
      badge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Ready to turn in", 1, 1, 1)
        GameTooltip:AddLine(self.questID and isTracked(self.questID) and "Click to stop tracking this quest." or "Click to track this quest.", 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine("Right-click to see where to turn it in.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
      end)
      badge:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
      badges[button] = badge
    end
    badge.questID = button.questID
    badge:ClearAllPoints()
    local height = 16
    if box then
      -- The right edge and the height of the box, and a little more on each side.
      local boxHeight = box:GetHeight()
      if type(boxHeight) == "number" and boxHeight + 4 > height then
        height = boxHeight + 4
      end
      badge:SetPoint("RIGHT", box, "RIGHT", 2, 0)
      badge:SetFrameLevel(box:GetFrameLevel() + 2)
      box:SetAlpha(0)
    else
      badge:SetPoint("TOPRIGHT", button, "TOPRIGHT", -4, -4)
      badge:SetFrameLevel(button:GetFrameLevel() + 3)
    end
    badge:SetSize(94, height)
    showTracked(badge)
    badge:Show()
  else
    if badge then
      badge:Hide()
    end
    if box then
      box:SetAlpha(1)
    end
  end
end

-- True if the button of the quest log has the COMPLETED mark now.
function ns.HasCompletedMark(button)
  local badge = badges[button]
  return badge ~= nil and badge:IsShown()
end

-- Shows the banner and the glow once, for /fq demo: on the first quest of the log.
function ns.Demo()
  for i = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(i)
    if info and not info.isHeader and not info.isHidden and info.questID then
      local shown = ns.GetOption("completeFanfare")
      if not shown then
        ns.Print("the quest complete banner is off: /fq fanfare turns it on.")
      else
        ns.ShowQuestComplete(info.questID, info.title)
      end
      ns.OnQuestProgress(info.questID)
      ns.Print("demo: open the quest log to see \"" .. tostring(info.title) .. "\" at the top of its zone with a glow.")
      return true
    end
  end
  ns.Print("demo: the quest log has no quest.")
  return false
end

---------------------------------------------------------------------------------------------------
-- Order

local function sortName(button)
  local title = button.info and button.info.title
  if type(title) ~= "string" or ns.IsSecret(title) then
    return ""
  end
  return title:lower()
end

-- Gives the buttons of one zone (in the game's order) their new places. True if a button moved.
local function arrangeZone(zone, pop, alpha, ready)
  if #zone < 2 then
    return false
  end
  local places, items = {}, {}
  for i, button in ipairs(zone) do
    places[i] = { layoutIndex = button.layoutIndex, topPadding = button.topPadding }
    local entry = pop and progressed[button.questID]
    -- A quest that made progress is first, the newest at the top. Then the quests that are
    -- ready to turn in, then the rest.
    local at = entry and entry.at or (pop and ready and isComplete(button.questID) and 0.5) or 0
    items[i] = { button = button, place = i, at = at, name = alpha and sortName(button) or "" }
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
  local moved = false
  for i, item in ipairs(items) do
    if item.place ~= i then
      moved = true
    end
    -- The space above a button belongs to the place: it is larger under a header.
    item.button.layoutIndex = places[i].layoutIndex
    item.button.topPadding = places[i].topPadding
  end
  return moved
end

-- Runs after the game has built the quest log. Returns true if the log needs a new layout.
function ns.ArrangeLog()
  local scroll = QuestScrollFrame
  if not (scroll and scroll.titleFramePool and scroll.titleFramePool.EnumerateActive) then
    return false
  end
  local pop, alpha = ns.GetOption("popProgress"), ns.GetOption("sortAlpha")
  local ready = ns.GetOption("completeFanfare")
  local visible = scroll:IsVisible()
  local buttons = {}
  for button in scroll.titleFramePool:EnumerateActive() do
    if button.questID and type(button.layoutIndex) == "number" then
      buttons[#buttons + 1] = button
    end
    updateGlow(button, pop, visible)
    updateBadge(button, ready)
  end
  if not (pop or alpha) then
    return false
  end

  table.sort(buttons, function(a, b)
    return a.layoutIndex < b.layoutIndex
  end)
  -- A header has a layoutIndex of its own. So the quests of one zone are a run of buttons with
  -- layoutIndex values that follow each other.
  local moved = false
  local zone = {}
  for _, button in ipairs(buttons) do
    local last = zone[#zone]
    if last and button.layoutIndex ~= last.layoutIndex + 1 then
      moved = arrangeZone(zone, pop, alpha, ready) or moved
      zone = {}
    end
    zone[#zone + 1] = button
  end
  moved = arrangeZone(zone, pop, alpha, ready) or moved
  return moved
end

ns.OnOptionChanged(function(option)
  if (option == "popProgress" or option == "sortAlpha" or option == "completeFanfare") and ns.RefreshQuestLog then
    ns.RefreshQuestLog()
  end
end)
