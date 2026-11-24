local _, ns = ...

-- Two windows: the readout (the bar and the numbers) and the list of zones for your level.

local WIDTH = 260
local ROWS = 10

local readout, zones

local function savePosition(frame, key)
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  ForeverLevelingDB.frames[key] = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function placeFrame(frame, key, point, x, y)
  frame:ClearAllPoints()
  local saved = ForeverLevelingDB.frames[key]
  if type(saved) == "table" and type(saved.point) == "string" and ns.Usable(saved.x) and ns.Usable(saved.y) then
    frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x, saved.y)
  else
    frame:SetPoint(point, UIParent, point, x, y)
  end
end

local function movable(frame, key)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if not ns.GetOption("lock") then
      self:StartMoving()
    end
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition(self, key)
  end)
end

local function background(frame)
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.6)
end

---------------------------------------------------------------------------------------------------
-- The readout

local function line(parent, y)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
  text:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
  text:SetJustifyH("LEFT")
  -- One line each: a wrapped line would lie on the line below it.
  text:SetWordWrap(false)
  return text
end

local function buildReadout()
  readout = CreateFrame("Frame", "ForeverLevelingReadout", UIParent)
  readout:SetSize(WIDTH, 112)
  readout:SetClampedToScreen(true)
  background(readout)
  movable(readout, "readout")

  readout.title = line(readout, -6)
  readout.title:SetFontObject("GameFontNormal")

  readout.bar = CreateFrame("StatusBar", nil, readout)
  readout.bar:SetPoint("TOPLEFT", readout, "TOPLEFT", 8, -24)
  readout.bar:SetPoint("TOPRIGHT", readout, "TOPRIGHT", -8, -24)
  readout.bar:SetHeight(10)
  readout.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  readout.bar:SetStatusBarColor(0.58, 0.0, 0.55)
  readout.rested = readout.bar:CreateTexture(nil, "BACKGROUND")
  readout.rested:SetColorTexture(0.0, 0.39, 0.88, 0.6)
  readout.rested:SetPoint("TOPLEFT", readout.bar, "TOPLEFT", 0, 0)
  readout.rested:SetHeight(10)
  local barBg = readout.bar:CreateTexture(nil, "BACKGROUND", nil, -1)
  barBg:SetAllPoints()
  barBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)

  readout.rate = line(readout, -40)
  readout.kills = line(readout, -56)
  readout.quests = line(readout, -72)
  readout.restedText = line(readout, -88)
  readout.lines = { readout.title, readout.rate, readout.kills, readout.quests, readout.restedText }

  readout:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
      ns.SetOption("showZones", not ns.GetOption("showZones"))
    end
  end)
  readout:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Forever Leveling")
    GameTooltip:AddLine("Drag to move. Right-click: the zones for your level.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  readout:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  -- The rate falls while nothing happens: the text is new each few seconds.
  local elapsed = 0
  readout:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed >= 5 then
      elapsed = 0
      ns.RefreshReadout()
    end
  end)
end

-- The readout is as wide as its longest line, and no narrower than WIDTH.
local function fitWidth()
  local width = WIDTH
  for _, text in ipairs(readout.lines) do
    local needed = text:GetStringWidth()
    if ns.Usable(needed) and needed + 16 > width then
      width = math.ceil(needed + 16)
    end
  end
  readout:SetWidth(width)
end

local function refreshReadout()
  readout:SetShown(ns.GetOption("show"))
  readout:SetScale(ns.GetOption("scale") / 100)
  readout:EnableMouse(not ns.GetOption("lock"))
  readout.bar:SetShown(ns.GetOption("showBar"))
  local state = ns.State()
  if not state then
    readout.title:SetText("Experience: hidden by the game")
    readout.rested:Hide()
    readout.rate:SetText("")
    readout.kills:SetText("")
    readout.quests:SetText("")
    readout.restedText:SetText("")
    return
  end
  if state.maxLevel then
    readout.title:SetText(string.format("Level %d: the highest level", state.level))
    readout.bar:SetMinMaxValues(0, 1)
    readout.bar:SetValue(1)
    readout.rested:Hide()
    readout.rate:SetText("")
    readout.kills:SetText("")
    readout.quests:SetText("")
    readout.restedText:SetText("")
    return
  end
  local percent = state.max > 0 and state.xp * 100 / state.max or 0
  readout.title:SetText(string.format("Level %d: %s / %s (%.1f%%)", state.level, ns.Thousands(state.xp), ns.Thousands(state.max), percent))
  readout.bar:SetMinMaxValues(0, math.max(1, state.max))
  readout.bar:SetValue(state.xp)
  local barWidth = readout.bar:GetWidth()
  if state.rested > 0 and state.max > 0 and ns.Usable(barWidth) and barWidth > 0 then
    local from = state.xp / state.max
    local to = math.min(1, (state.xp + state.rested) / state.max)
    readout.rested:ClearAllPoints()
    readout.rested:SetPoint("TOPLEFT", readout.bar, "TOPLEFT", from * barWidth, 0)
    readout.rested:SetSize(math.max(1, (to - from) * barWidth), 10)
    readout.rested:Show()
  else
    readout.rested:Hide()
  end
  if state.perHour then
    readout.rate:SetText(string.format("%s XP an hour, level in %s", ns.Thousands(state.perHour), ns.Duration(state.timeToLevel)))
  else
    readout.rate:SetText("XP an hour: after the first minute with experience")
  end
  readout.kills:SetText(state.killsToLevel and string.format("Kills to level: %d (%s XP each)", state.killsToLevel, ns.Thousands(state.killXP)) or "Kills to level: none counted yet")
  readout.quests:SetText(state.questsToLevel and string.format("Quests to level: %d (%s XP each)", state.questsToLevel, ns.Thousands(state.questXP)) or "Quests to level: none counted yet")
  if state.rested > 0 then
    readout.restedText:SetText(string.format("Rested: %s XP (%.0f%% of the level)", ns.Thousands(state.rested), state.max > 0 and state.rested * 100 / state.max or 0))
  else
    readout.restedText:SetText("Rested: none")
  end
end

function ns.RefreshReadout()
  if not readout then
    return
  end
  refreshReadout()
  fitWidth()
end

---------------------------------------------------------------------------------------------------
-- The zones

local FIT_COLOR = { low = "|cff40c040", even = "|cffffd100", high = "|cffff8040" }

local function buildZones()
  zones = CreateFrame("Frame", "ForeverLevelingZones", UIParent)
  zones:SetSize(WIDTH, 30 + ROWS * 18)
  zones:SetClampedToScreen(true)
  zones:SetFrameStrata("MEDIUM")
  background(zones)
  movable(zones, "zones")
  zones.title = line(zones, -6)
  zones.title:SetFontObject("GameFontNormal")
  local close = CreateFrame("Button", nil, zones, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", zones, "TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    ns.SetOption("showZones", false)
  end)
  zones.rows = {}
  for index = 1, ROWS do
    local row = CreateFrame("Button", nil, zones)
    row:SetPoint("TOPLEFT", zones, "TOPLEFT", 6, -26 - (index - 1) * 18)
    row:SetPoint("RIGHT", zones, "RIGHT", -6, 0)
    row:SetHeight(18)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.text:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(self)
      if self.zone then
        ns.Print(ns.PointAt(self.zone))
      end
    end)
    row:SetScript("OnEnter", function(self)
      if self.zone then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.zone.name)
        GameTooltip:AddLine("Click: a map pin in the middle of the zone, and a tracker of Forever Compass that points to it.", 1, 1, 1, true)
        GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    zones.rows[index] = row
  end
end

-- The zones that the window lists now.
function ns.ListedZones()
  local level = UnitLevel("player")
  return ns.ZonesFor(level, ns.GetOption("zoneSpread"), UnitFactionGroup("player")), level
end

function ns.RefreshZones()
  if not zones then
    return
  end
  zones:SetShown(ns.GetOption("showZones"))
  zones:SetScale(ns.GetOption("scale") / 100)
  if not zones:IsShown() then
    return
  end
  local list, level = ns.ListedZones()
  zones.title:SetText(string.format("Zones for level %s", ns.Usable(level) and level or "?"))
  for index, row in ipairs(zones.rows) do
    local zone = list[index]
    row.zone = zone
    if zone then
      row.text:SetText(string.format("%s%d-%d|r  %s", FIT_COLOR[ns.Fit(zone, level)], zone.min, zone.max, zone.name))
      row:Show()
    else
      row:Hide()
    end
  end
end

function ns.ResetPositions()
  ForeverLevelingDB.frames = {}
  placeFrame(readout, "readout", "TOP", 0, -120)
  placeFrame(zones, "zones", "TOP", 0, -246)
end

ns.OnLogin(function()
  buildReadout()
  buildZones()
  placeFrame(readout, "readout", "TOP", 0, -120)
  placeFrame(zones, "zones", "TOP", 0, -246)
  ns.OnChange(function()
    ns.RefreshReadout()
    ns.RefreshZones()
  end)
  ns.RefreshReadout()
  ns.RefreshZones()
end)
