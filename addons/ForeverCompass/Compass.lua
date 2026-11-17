local _, ns = ...

-- The compass bar: a strip at the top of the screen that shows the heading. The whole circle of
-- 360 degrees is on the strip, with N, NE, E, SE, S, SW, W and NW, and the strip scrolls as the
-- player turns. The bar shows a part of the circle at one time (the option fov).
--
-- Each tracker that is on puts a marker on the bar, at the bearing of its nearest target, with
-- the name of the target and the distance under it. A target outside the shown part of the
-- circle has its marker at the end of the bar on that side, dimmed.
--
-- A marker of a quest of the quest log takes a click: it opens the quest in the quest log, the
-- same as a click on the quest there.
--
-- Bearings are in degrees, clockwise from north: 0 is north and 90 is east.

local BAR_INTERVAL = 0.02 -- seconds between moves of the bar
local TARGET_INTERVAL = 1 -- seconds between searches for targets
local HEIGHT = 30
local STEP = 15 -- degrees between the marks on the strip
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- a filled circle
local POINTS = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" }

local root, strip, headingText
local marks, markers = {}, {}
local barWidth = 600
local inCombat = false

-- How far a bearing is to the right of the heading, from -180 to 180 degrees.
local function offsetOf(bearing, heading)
  return (bearing - heading + 540) % 360 - 180
end

local function savePosition()
  local point, _, relativePoint, x, y = root:GetPoint(1)
  if point then
    ForeverCompassDB.frames.bar = { point, relativePoint, x, y }
  end
end

local function defaultPosition()
  root:ClearAllPoints()
  root:SetPoint("TOP", UIParent, "TOP", 0, -20)
end

local function restorePosition()
  local saved = ForeverCompassDB.frames.bar
  if type(saved) == "table" and type(saved[1]) == "string" and ns.Usable(saved[3]) and ns.Usable(saved[4]) then
    root:ClearAllPoints()
    if pcall(root.SetPoint, root, saved[1], UIParent, saved[2] or saved[1], saved[3], saved[4]) then
      return
    end
  end
  defaultPosition()
end

function ns.ResetPositions()
  wipe(ForeverCompassDB.frames)
  if root then
    defaultPosition()
  end
end

local function line(parent, r, g, b, a)
  local texture = parent:CreateTexture(nil, "BORDER")
  texture:SetColorTexture(r, g, b, a)
  return texture
end

local function createBar()
  root = CreateFrame("Frame", "ForeverCompassBar", UIParent)
  root:SetMovable(true)
  root:SetClampedToScreen(true)
  root:RegisterForDrag("LeftButton")
  root:SetScript("OnDragStart", function(self)
    if not ns.GetOption("lock") then
      self:StartMoving()
    end
  end)
  root:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition()
  end)
  root:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
      ns.OpenSettings()
    end
  end)
  root:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Forever Compass", 1, 1, 1)
    GameTooltip:AddLine("Drag to move. Right-click for the settings.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  root:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- The strip has its own opacity. The markers are not on it, so each one keeps its own.
  strip = CreateFrame("Frame", nil, root)
  strip:SetAllPoints()
  local background = strip:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0, 0, 0, 0.6)
  for _, edge in ipairs({ "TOP", "BOTTOM" }) do
    local border = line(strip, 0.85, 0.72, 0.38, 0.9)
    border:SetHeight(1)
    border:SetPoint(edge .. "LEFT")
    border:SetPoint(edge .. "RIGHT")
  end
  -- The pointer in the middle shows where the player looks.
  local pointer = line(strip, 1, 1, 1, 0.95)
  pointer:SetDrawLayer("OVERLAY")
  pointer:SetSize(2, 9)
  pointer:SetPoint("TOP", 0, 0)

  headingText = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  headingText:SetPoint("BOTTOM", root, "TOP", 0, 2)

  for bearing = 0, 360 - STEP, STEP do
    local label = POINTS[bearing]
    local region
    if label then
      local main = #label == 1 -- N, E, S, W
      region = strip:CreateFontString(nil, "ARTWORK", main and "GameFontNormalLarge" or "GameFontHighlightSmall")
      region:SetText(label)
      if label == "N" then
        region:SetTextColor(1, 0.35, 0.3)
      end
    else
      region = line(strip, 1, 1, 1, 0.55)
      region:SetSize(1, 8)
    end
    marks[#marks + 1] = { bearing = bearing, region = region }
  end
end

local function createMarker(index)
  local marker = CreateFrame("Frame", nil, root)
  marker.index = index
  marker:SetFrameLevel(strip:GetFrameLevel() + 2)

  marker.dot = marker:CreateTexture(nil, "ARTWORK")
  marker.dot:SetAllPoints()
  -- Makes the dot round, where the client can.
  if marker.CreateMaskTexture then
    local mask = marker:CreateMaskTexture()
    mask:SetAllPoints(marker.dot)
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    marker.dot:AddMaskTexture(mask)
  end
  marker.number = marker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  marker.number:SetPoint("CENTER")
  marker.number:SetTextColor(0, 0, 0)
  marker.number:SetText(index)

  marker.distance = marker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  marker.name = marker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  marker.name:SetWidth(130)
  marker.name:SetWordWrap(false)

  -- The dot is small: the name and the distance under it take the click too.
  marker:SetHitRectInsets(-45, -45, 0, -30)
  marker:EnableMouse(false)
  marker:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and self.questID then
      ns.OpenQuest(self.questID)
    elseif button == "RightButton" then
      ns.OpenSettings()
    end
  end)
  marker:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(self.targetName or "Forever Compass", 1, 1, 1)
    if self.questID then
      GameTooltip:AddLine("Click to open this quest in the quest log.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
  end)
  marker:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  marker.targets = {}
  marker.sinceSearch = TARGET_INTERVAL + index * 0.2 -- the trackers do not all search in the same frame
  marker.status = "off"
  marker:Hide()
  return marker
end

-- Sets the look of the bar and of the markers from the settings.
local function style()
  barWidth = math.max(200, UIParent:GetWidth() * ns.GetOption("barWidth") / 100)
  root:SetSize(barWidth, HEIGHT)
  root:EnableMouse(not ns.GetOption("lock"))
  strip:SetAlpha(ns.GetOption("barAlpha") / 100)
  headingText:SetShown(ns.GetOption("showDegrees"))

  for index, marker in ipairs(markers) do
    local size = ns.GetCompass(index, "size")
    local r, g, b = ns.ColorOf(index)
    marker:SetSize(size, size)
    marker.dot:SetColorTexture(r, g, b, 1)
    marker.name:SetTextColor(r, g, b)
    local showDistance = ns.GetCompass(index, "showDistance")
    marker.distance:SetShown(showDistance)
    marker.name:SetShown(ns.GetCompass(index, "showName"))
    marker.distance:ClearAllPoints()
    marker.distance:SetPoint("TOP", marker, "BOTTOM", 0, -1)
    marker.name:ClearAllPoints()
    if showDistance then
      marker.name:SetPoint("TOP", marker.distance, "BOTTOM", 0, -1)
    else
      marker.name:SetPoint("TOP", marker, "BOTTOM", 0, -1)
    end
    marker.sinceSearch = TARGET_INTERVAL -- a changed kind shows at once
  end
end

-- The nearest target on the player's continent, within the range of the tracker.
local function nearest(marker, continent, north, west)
  local limit = ns.GetCompass(marker.index, "maxYards")
  local best, bestYards, bestNorth, bestWest
  for _, target in ipairs(marker.targets) do
    if not ns.Usable(continent) or not ns.Usable(target[1]) or target[1] == continent then
      local dNorth, dWest = target[2] - north, target[3] - west
      local yards = math.sqrt(dNorth * dNorth + dWest * dWest)
      if (limit == 0 or yards <= limit) and (not bestYards or yards < bestYards) then
        best, bestYards, bestNorth, bestWest = target, yards, dNorth, dWest
      end
    end
  end
  return best, bestYards, bestNorth, bestWest
end

local function distanceText(yards)
  if yards >= 1000 then
    return string.format("%.1fk yd", yards / 1000)
  end
  return string.format("%d yd", yards)
end

local function updateMarker(marker, elapsed, heading, half, scale, continent, north, west)
  local index = marker.index
  if not ns.GetCompass(index, "enabled") then
    marker.status = "off"
    marker:Hide()
    return
  end
  if not north then
    marker.status = "the game hides your position here"
    marker:Hide()
    return
  end
  marker.sinceSearch = marker.sinceSearch + elapsed
  if marker.sinceSearch >= TARGET_INTERVAL then
    marker.sinceSearch = 0
    marker.targets = ns.FindTargets(ns.GetCompass(index, "kind"))
  end

  local target, yards, dNorth, dWest = nearest(marker, continent, north, west)
  if not target then
    local kind = ns.KindByKey[ns.GetCompass(index, "kind")]
    marker.status = kind and kind.learned and #ns.Places(kind.key) == 0 and "none learned yet" or "none near"
    marker:Hide()
    return
  end

  -- atan2 gives the angle counterclockwise from north. A bearing is clockwise.
  local bearing = (-math.deg(math.atan2(dWest, dNorth))) % 360
  local offset = offsetOf(bearing, heading)
  local outside = math.abs(offset) > half
  if outside then
    offset = offset > 0 and half or -half
  end
  marker:ClearAllPoints()
  marker:SetPoint("CENTER", root, "BOTTOM", offset * scale, 0)
  marker:SetAlpha(ns.GetCompass(index, "alpha") / 100 * (outside and 0.5 or 1))
  marker.distance:SetText(distanceText(yards))
  marker.name:SetText(target[4] or "")
  marker.targetName = target[4]
  -- Only a marker of a quest takes the mouse: the others let a click through to the bar.
  if marker.questID ~= target[5] then
    marker.questID = target[5]
    marker:EnableMouse(target[5] ~= nil)
  end
  marker.status = (target[4] or "?") .. ", " .. distanceText(yards)
  marker:Show()
end

local function update(elapsed)
  local facing = GetPlayerFacing and GetPlayerFacing()
  if not ns.GetOption("show") or (inCombat and ns.GetOption("hideInCombat")) or not ns.Usable(facing) then
    root:Hide()
    return
  end
  -- The game gives the facing counterclockwise from north, in radians.
  local heading = (360 - math.deg(facing)) % 360
  local fov = ns.GetOption("fov")
  local half = fov / 2
  local scale = barWidth / fov
  local fade = math.max(1, fov * 0.06) -- marks fade out over this many degrees at the ends

  for _, mark in ipairs(marks) do
    local offset = offsetOf(mark.bearing, heading)
    local inside = half - math.abs(offset)
    if inside < 0 then
      mark.region:Hide()
    else
      mark.region:ClearAllPoints()
      mark.region:SetPoint("CENTER", strip, "CENTER", offset * scale, 0)
      mark.region:SetAlpha(math.min(1, inside / fade))
      mark.region:Show()
    end
  end
  headingText:SetText(string.format("%d°", math.floor(heading + 0.5) % 360))

  local continent, north, west = ns.UnitWorld("player")
  for _, marker in ipairs(markers) do
    updateMarker(marker, elapsed, heading, half, scale, continent, north, west)
  end
  root:Show()
end

-- Opens a quest of the quest log, the same as a click on it there: the log opens with the
-- details of the quest. Returns false if the game does not have the function or refuses.
function ns.OpenQuest(questID)
  if type(QuestMapFrame_OpenToQuestDetails) ~= "function" then
    return false
  end
  -- The game does not let an addon open a window in a fight: it would show an error and still
  -- change the chosen quest of the log.
  if InCombatLockdown and InCombatLockdown() then
    ns.Print("the quest log cannot open in a fight. Click again after it.")
    return false
  end
  return (pcall(QuestMapFrame_OpenToQuestDetails, questID))
end

-- The quest that the marker of a tracker points to now, or nil.
function ns.TrackerQuest(index)
  local marker = markers[index]
  return marker and marker:IsShown() and marker.questID or nil
end

-- What a tracker shows now, for /fcompass.
function ns.TrackerStatus(index)
  local marker = markers[index]
  return marker and marker.status or "?"
end

ns.OnLogin(function()
  createBar()
  for index = 1, ns.COUNT do
    markers[index] = createMarker(index)
  end
  restorePosition()
  style()
  ns.OnChange(style)

  local driver = CreateFrame("Frame")
  local elapsed = 0
  driver:SetScript("OnUpdate", function(self, delta)
    elapsed = elapsed + delta
    if elapsed < BAR_INTERVAL then
      return
    end
    local ok, err = pcall(update, elapsed)
    elapsed = 0
    if not ok then
      -- An error stops the compass, not the game.
      self:Hide()
      root:Hide()
      geterrorhandler()(err)
    end
  end)

  driver:RegisterEvent("PLAYER_REGEN_DISABLED")
  driver:RegisterEvent("PLAYER_REGEN_ENABLED")
  -- The width of the bar is a part of the width of the screen.
  pcall(driver.RegisterEvent, driver, "DISPLAY_SIZE_CHANGED")
  pcall(driver.RegisterEvent, driver, "UI_SCALE_CHANGED")
  driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
      inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
      inCombat = false
    else
      style()
    end
  end)
end)
