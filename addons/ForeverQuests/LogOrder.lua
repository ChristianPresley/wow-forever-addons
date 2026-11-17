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

-- Every quest of the quest log:
--   the tracking symbol is at the right end of the title, where the game has the box that
--   tracks the quest (button.Checkbox). The box is not drawn there. A click on the symbol
--   tracks the quest or stops tracking it, as the box does. The symbol is grey while the quest
--   is not tracked and bright while it is. It has some room around it, which takes the click too.
--   under it is the compass symbol, if Forever Compass is loaded: a click makes a tracker of
--   the compass point to this quest, a second click takes it off the compass again.
-- A quest that is ready to turn in, with the option completeFanfare:
--   the whole quest (its title and the lines under it) is on a green background, in white text
--   "COMPLETED" is in front of the name of the quest
--   a right-click on the tracking symbol shows where to turn the quest in.
-- The game uses a button again for another quest and writes the title and its colours again
-- each time it builds the log, so this is set each time too.
local PREFIX = "COMPLETED  "
local SYMBOL_SIZE = 13
local SYMBOL_ROOM = 4 -- around the tracking symbol, on each side
local SYMBOL_LEFT = 3 -- the symbol is this far to the left of the middle of the game's box
local COMPASS_GAP = 2 -- between the tracking symbol and the compass symbol under it

-- The functions of Forever Compass for other addons, or nil if it is not loaded.
local function compassApi()
  -- A name of another addon, which may not be there: read from the table of all names.
  local api = rawget(_G, "ForeverCompass")
  if type(api) == "table" and type(api.TrackQuest) == "function" and type(api.UntrackQuest) == "function" and type(api.QuestTracker) == "function" then
    return api
  end
  return nil
end

-- The tracker of the compass that points to the quest, or nil.
function ns.CompassTracker(questID)
  local api = compassApi()
  if not api or not questID then
    return nil
  end
  local ok, index = pcall(api.QuestTracker, questID)
  return ok and index or nil
end

-- Puts the quest on the compass, or takes it off. Returns true if it is on the compass after.
function ns.ToggleCompass(questID)
  local api = compassApi()
  if not api or not questID then
    return false
  end
  if ns.CompassTracker(questID) then
    pcall(api.UntrackQuest, questID)
    return false
  end
  local ok, index, why = pcall(api.TrackQuest, questID)
  if ok and index then
    ns.Print("tracker " .. tostring(index) .. " of the compass points to this quest now.")
    return true
  end
  ns.Print("the compass cannot take this quest: " .. tostring(ok and why or index) .. ".")
  return false
end

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
  if type(QuestMapQuestOptions_TrackQuest) == "function" then
    -- The game's own function has the rules of the game: no more tracked quests than the
    -- game allows, with the game's message on the screen.
    pcall(QuestMapQuestOptions_TrackQuest, questID)
  elseif tracked then
    pcall(C_QuestLog.RemoveQuestWatch, questID)
  else
    pcall(C_QuestLog.AddQuestWatch, questID)
  end
  local after = isTracked(questID)
  -- The sound of a box, only if the click changed something.
  if after ~= tracked and PlaySound and SOUNDKIT then
    local sound = tracked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
    if sound then
      PlaySound(sound)
    end
  end
  return after
end

-- The tracking symbol: grey and dim while the quest is not tracked, bright while it is.
local function showTracked(tracker)
  local tracked = tracker.questID ~= nil and isTracked(tracker.questID)
  tracker.tracked = tracked
  if tracked then
    tracker.symbol:SetVertexColor(1, 0.9, 0.3, 1)
  else
    tracker.symbol:SetVertexColor(0.8, 0.8, 0.8, 0.6)
  end
end

-- The compass symbol: grey and dim while the quest is not on the compass, bright while it is.
local function showOnCompass(compass)
  local on = ns.CompassTracker(compass.questID) ~= nil
  compass.onCompass = on
  if on then
    compass.symbol:SetVertexColor(0.4, 0.8, 1, 1)
  else
    compass.symbol:SetVertexColor(0.8, 0.8, 0.8, 0.6)
  end
end

local function fontString(region)
  return type(region) == "table" and type(region.SetTextColor) == "function" and region or nil
end

-- White text for the title of the quest and the lines under it.
local function whiten(button)
  local title = fontString(button.Text)
  if title then
    title:SetTextColor(1, 1, 1)
  end
  -- The tag at the right of the name (the level or the kind of the quest): the game gives it
  -- the colour of the name (QuestMapFrame.lua, QuestMapLogTitleButton_OnLeave).
  local tag = fontString(button.TagText)
  if tag then
    tag:SetTextColor(1, 1, 1)
  end
  local pool = QuestScrollFrame and QuestScrollFrame.objectiveFramePool
  if pool and pool.EnumerateActive then
    for line in pool:EnumerateActive() do
      local text = line.questID == button.questID and fontString(line.Text)
      if text then
        text:SetTextColor(1, 1, 1)
      end
    end
  end
end

-- Puts "COMPLETED" in front of the name. If the longer text needs one more line than the game
-- gave the title, the name stays as it was: the lines under it would not fit.
local function prefixTitle(button)
  local title = fontString(button.Text)
  local text = title and title:GetText()
  if type(text) ~= "string" or ns.IsSecret(text) or text:sub(1, #PREFIX) == PREFIX then
    return
  end
  local before = title.GetStringHeight and title:GetStringHeight()
  title:SetText(PREFIX .. text)
  local after = title.GetStringHeight and title:GetStringHeight()
  if type(before) == "number" and type(after) == "number" and after > before + 1 then
    title:SetText(text)
  end
end

local function createMark(button)
  local mark = { on = false }
  -- A texture of the button, under its text.
  mark.back = button:CreateTexture(nil, "BACKGROUND")
  mark.back:SetPoint("TOPLEFT", 0, -1)
  mark.back:SetPoint("BOTTOMRIGHT", 0, 1)
  mark.back:SetColorTexture(0.1, 0.5, 0.15, 0.9)

  local tracker = CreateFrame("Button", nil, button)
  tracker:SetSize(SYMBOL_SIZE + 2 * SYMBOL_ROOM, SYMBOL_SIZE + 2 * SYMBOL_ROOM)
  -- The picture of this addon (Media/Track.tga, drawn by `cargo dev track-icon`). It is white,
  -- so its colour is the one set here.
  tracker.symbol = tracker:CreateTexture(nil, "OVERLAY")
  tracker.symbol:SetTexture("Interface\\AddOns\\ForeverQuests\\Media\\Track")
  tracker.symbol:SetSize(SYMBOL_SIZE, SYMBOL_SIZE)
  tracker.symbol:SetPoint("CENTER")
  tracker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  tracker:SetScript("OnClick", function(self, mouseButton)
    if not self.questID then
      return
    end
    if mouseButton == "RightButton" then
      if mark.on and ns.ShowTurnIn then
        ns.ShowTurnIn(self.questID)
      end
    else
      ns.ToggleTracking(self.questID)
      showTracked(self)
    end
  end)
  tracker:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(mark.on and "Ready to turn in" or "Track this quest", 1, 1, 1)
    GameTooltip:AddLine(self.questID and isTracked(self.questID) and "Click to stop tracking this quest." or "Click to track this quest.", 0.6, 0.6, 0.6, true)
    if mark.on then
      GameTooltip:AddLine("Right-click to see where to turn it in.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
  end)
  tracker:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  mark.tracker = tracker

  -- The compass symbol (Media/Compass.tga, drawn by `cargo dev track-icon`), under the
  -- tracking symbol.
  local compass = CreateFrame("Button", nil, button)
  compass:SetSize(SYMBOL_SIZE + 2 * SYMBOL_ROOM, SYMBOL_SIZE + COMPASS_GAP)
  compass:SetPoint("TOP", tracker, "BOTTOM", 0, SYMBOL_ROOM - COMPASS_GAP)
  compass.symbol = compass:CreateTexture(nil, "OVERLAY")
  compass.symbol:SetTexture("Interface\\AddOns\\ForeverQuests\\Media\\Compass")
  compass.symbol:SetSize(SYMBOL_SIZE, SYMBOL_SIZE)
  compass.symbol:SetPoint("BOTTOM")
  compass:RegisterForClicks("LeftButtonUp")
  compass:SetScript("OnClick", function(self)
    if self.questID then
      ns.ToggleCompass(self.questID)
      showOnCompass(self)
    end
  end)
  compass:SetScript("OnEnter", function(self)
    local index = ns.CompassTracker(self.questID)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Track in compass", 1, 1, 1)
    GameTooltip:AddLine(index and ("Tracker " .. index .. " of the compass points to this quest. Click to take it off the compass.")
      or "Click to make a tracker of the compass point to this quest.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  compass:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  mark.compass = compass

  -- The game gives the title and its lines their own colours again when the pointer comes onto
  -- the quest and when it leaves (QuestMapLogTitleButton_OnEnter and _OnLeave). After that, the
  -- text of a ready quest is white again.
  if type(button.HookScript) == "function" then
    for _, script in ipairs({ "OnEnter", "OnLeave" }) do
      pcall(button.HookScript, button, script, function(self)
        if mark.on then
          whiten(self)
        end
      end)
    end
  end
  return mark
end

local function updateBadge(button, enabled)
  local mark = badges[button]
  local box = trackBox(button)
  if not button.questID then
    if mark then
      mark.on = false
      mark.back:Hide()
      mark.tracker:Hide()
      mark.compass:Hide()
    end
    if box then
      box:SetAlpha(1)
    end
    return
  end
  if not mark then
    mark = createMark(button)
    badges[button] = mark
  end
  -- The symbols, on every quest.
  local tracker, compass = mark.tracker, mark.compass
  tracker.questID = button.questID
  tracker:ClearAllPoints()
  if box then
    tracker:SetPoint("CENTER", box, "CENTER", -SYMBOL_LEFT, 0)
    tracker:SetFrameLevel(box:GetFrameLevel() + 2)
    box:SetAlpha(0)
  else
    tracker:SetPoint("TOPRIGHT", button, "TOPRIGHT", -6 - SYMBOL_LEFT + SYMBOL_ROOM, -5 + SYMBOL_ROOM)
    tracker:SetFrameLevel(button:GetFrameLevel() + 3)
  end
  showTracked(tracker)
  tracker:Show()
  compass.questID = button.questID
  compass:SetFrameLevel(tracker:GetFrameLevel())
  if compassApi() then
    showOnCompass(compass)
    compass:Show()
  else
    compass:Hide()
  end
  -- The look of a ready quest.
  mark.on = enabled and isComplete(button.questID)
  if mark.on then
    mark.back:Show()
    prefixTitle(button)
    whiten(button)
  else
    mark.back:Hide()
  end
end

-- True if the button of the quest log has the look of a ready quest now.
function ns.HasCompletedMark(button)
  local mark = badges[button]
  return mark ~= nil and mark.on
end

-- What this addon puts on a button of the quest log: { on (the look of a ready quest), back,
-- tracker, compass }, or nil.
function ns.CompletedMark(button)
  return badges[button]
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
