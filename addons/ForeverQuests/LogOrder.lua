local _, ns = ...

-- The order of the quests in the quest log, and the glow on a quest that made progress.
--
--   popProgress: a quest that made progress goes to the top of its zone, the most recent one first,
--                and glows for a few seconds the next time the quest log shows it.
--   sortAlpha:   the quests of each zone are in the order of their names.
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
local function arrangeZone(zone, pop, alpha)
  if #zone < 2 then
    return false
  end
  local places, items = {}, {}
  for i, button in ipairs(zone) do
    places[i] = { layoutIndex = button.layoutIndex, topPadding = button.topPadding }
    local entry = pop and progressed[button.questID]
    items[i] = { button = button, place = i, at = entry and entry.at or 0, name = alpha and sortName(button) or "" }
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
  local visible = scroll:IsVisible()
  local buttons = {}
  for button in scroll.titleFramePool:EnumerateActive() do
    if button.questID and type(button.layoutIndex) == "number" then
      buttons[#buttons + 1] = button
    end
    updateGlow(button, pop, visible)
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
      moved = arrangeZone(zone, pop, alpha) or moved
      zone = {}
    end
    zone[#zone + 1] = button
  end
  moved = arrangeZone(zone, pop, alpha) or moved
  return moved
end

ns.OnOptionChanged(function(option)
  if (option == "popProgress" or option == "sortAlpha") and ns.RefreshQuestLog then
    ns.RefreshQuestLog()
  end
end)
