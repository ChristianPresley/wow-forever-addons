local _, ns = ...

-- The compasses on screen. Each one is a dial with a needle that points to the nearest target of
-- its kind, with the name of the target and the distance under it.
--
-- Direction and distance come from world positions, so they are known only where the game gives
-- the player's position. In an instance the compasses hide.

local NEEDLE_INTERVAL = 0.05 -- seconds between turns of the needles
local TARGET_INTERVAL = 1 -- seconds between searches for targets
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- a filled circle
local NEEDLE = "Interface\\Minimap\\MinimapArrow"

local compasses = {}
local inCombat = false

-- Makes a texture round, where the client can.
local function makeRound(frame, texture)
  if not frame.CreateMaskTexture then
    return
  end
  local mask = frame:CreateMaskTexture()
  mask:SetAllPoints(texture)
  mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  texture:AddMaskTexture(mask)
end

local function savePosition(compass)
  local point, _, relativePoint, x, y = compass:GetPoint(1)
  if point then
    ForeverCompassDB.frames[compass.index] = { point, relativePoint, x, y }
  end
end

local function defaultPosition(compass)
  compass:ClearAllPoints()
  compass:SetPoint("TOP", UIParent, "TOP", (compass.index - 2.5) * 110, -190)
end

local function restorePosition(compass)
  local saved = ForeverCompassDB.frames[compass.index]
  if type(saved) == "table" and type(saved[1]) == "string" and ns.Usable(saved[3]) and ns.Usable(saved[4]) then
    compass:ClearAllPoints()
    if pcall(compass.SetPoint, compass, saved[1], UIParent, saved[2] or saved[1], saved[3], saved[4]) then
      return
    end
  end
  defaultPosition(compass)
end

function ns.ResetPositions()
  wipe(ForeverCompassDB.frames)
  for _, compass in ipairs(compasses) do
    defaultPosition(compass)
  end
end

local function showTooltip(compass)
  local kind = ns.KindByKey[ns.GetCompass(compass.index, "kind")]
  GameTooltip:SetOwner(compass, "ANCHOR_BOTTOM")
  GameTooltip:SetText("Compass " .. compass.index .. ": " .. (kind and kind.name or "?"), 1, 1, 1)
  if kind then
    GameTooltip:AddLine(kind.hint, nil, nil, nil, true)
  end
  GameTooltip:AddLine("Drag to move. Right-click for its settings.", 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

local function create(index)
  local compass = CreateFrame("Frame", "ForeverCompass" .. index, UIParent)
  compass.index = index
  compass:SetMovable(true)
  compass:SetClampedToScreen(true)
  compass:RegisterForDrag("LeftButton")
  compass:SetScript("OnDragStart", function(self)
    if not ns.GetOption("lock") then
      self:StartMoving()
    end
  end)
  compass:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition(self)
  end)
  compass:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
      ns.OpenSettings(self.index)
    end
  end)
  compass:SetScript("OnEnter", showTooltip)
  compass:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- The ring is a circle in the colour of the compass, with a smaller dark circle on it.
  compass.ring = compass:CreateTexture(nil, "BACKGROUND")
  compass.ring:SetAllPoints()
  makeRound(compass, compass.ring)
  compass.face = compass:CreateTexture(nil, "BORDER")
  compass.face:SetColorTexture(0.05, 0.05, 0.06, 0.85)
  makeRound(compass, compass.face)

  compass.needle = compass:CreateTexture(nil, "ARTWORK")
  compass.needle:SetTexture(NEEDLE)
  compass.needle:SetPoint("CENTER")

  compass.number = compass:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  compass.number:SetPoint("CENTER")

  compass.name = compass:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  compass.name:SetPoint("TOP", compass, "BOTTOM", 0, -2)
  compass.name:SetWidth(150)
  compass.name:SetWordWrap(false)
  compass.distance = compass:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

  compass.targets = {}
  compass.sinceSearch = TARGET_INTERVAL + index * 0.2 -- the compasses do not all search in the same frame
  restorePosition(compass)
  return compass
end

-- Sets the look of a compass from its settings.
local function style(compass)
  local index = compass.index
  local size = ns.GetCompass(index, "size")
  local r, g, b = ns.ColorOf(index)
  compass:SetSize(size, size)
  compass:SetAlpha(ns.GetCompass(index, "alpha") / 100)
  compass:EnableMouse(not ns.GetOption("lock"))
  compass.ring:SetColorTexture(r, g, b, 0.9)
  compass.face:ClearAllPoints()
  local edge = math.max(2, size * 0.06)
  compass.face:SetPoint("TOPLEFT", edge, -edge)
  compass.face:SetPoint("BOTTOMRIGHT", -edge, edge)
  compass.needle:SetSize(size * 0.72, size * 0.72)
  compass.needle:SetVertexColor(r, g, b)
  compass.number:SetText(index)
  compass.name:SetTextColor(r, g, b)

  local showName = ns.GetCompass(index, "showName")
  compass.name:SetShown(showName)
  compass.distance:SetShown(ns.GetCompass(index, "showDistance"))
  compass.distance:ClearAllPoints()
  if showName then
    compass.distance:SetPoint("TOP", compass.name, "BOTTOM", 0, -1)
  else
    compass.distance:SetPoint("TOP", compass, "BOTTOM", 0, -2)
  end
end

-- The nearest target on the player's continent, within the range of the compass.
local function nearest(compass, continent, north, west)
  local limit = ns.GetCompass(compass.index, "maxYards")
  local best, bestYards, bestNorth, bestWest
  for _, target in ipairs(compass.targets) do
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

local function update(compass, elapsed, continent, north, west, facing)
  local index = compass.index
  if not ns.GetCompass(index, "enabled") or (inCombat and ns.GetOption("hideInCombat")) or not north then
    compass:Hide()
    return
  end
  compass.sinceSearch = compass.sinceSearch + elapsed
  if compass.sinceSearch >= TARGET_INTERVAL then
    compass.sinceSearch = 0
    compass.targets = ns.FindTargets(ns.GetCompass(index, "kind"))
  end

  local target, yards, dNorth, dWest = nearest(compass, continent, north, west)
  if not target then
    if ns.GetCompass(index, "hideEmpty") then
      compass:Hide()
      return
    end
    local kind = ns.KindByKey[ns.GetCompass(index, "kind")]
    compass.needle:Hide()
    compass.number:Show()
    compass.name:SetText(kind and kind.name or "")
    compass.distance:SetText(kind and kind.learned and #ns.Places(kind.key) == 0 and "none learned yet" or "none near")
    compass:Show()
    return
  end

  compass.number:Hide()
  compass.name:SetText(target[4] or "")
  compass.distance:SetText(distanceText(yards))
  if ns.Usable(facing) then
    -- Facing and bearing both turn counterclockwise from north.
    compass.needle:SetRotation(math.atan2(dWest, dNorth) - facing)
    compass.needle:Show()
  else
    compass.needle:Hide()
  end
  compass:Show()
end

local function styleAll()
  for _, compass in ipairs(compasses) do
    style(compass)
    compass.sinceSearch = TARGET_INTERVAL -- a changed kind shows at once
  end
end

ns.OnLogin(function()
  for index = 1, ns.COUNT do
    compasses[index] = create(index)
  end
  styleAll()
  ns.OnChange(styleAll)

  local driver = CreateFrame("Frame")
  local elapsed = 0
  driver:SetScript("OnUpdate", function(self, delta)
    elapsed = elapsed + delta
    if elapsed < NEEDLE_INTERVAL then
      return
    end
    local continent, north, west = ns.UnitWorld("player")
    local facing = GetPlayerFacing and GetPlayerFacing()
    for _, compass in ipairs(compasses) do
      local ok, err = pcall(update, compass, elapsed, continent, north, west, facing)
      if not ok then
        -- An error stops the compasses, not the game.
        self:Hide()
        for _, other in ipairs(compasses) do
          other:Hide()
        end
        geterrorhandler()(err)
        break
      end
    end
    elapsed = 0
  end)

  driver:RegisterEvent("PLAYER_REGEN_DISABLED")
  driver:RegisterEvent("PLAYER_REGEN_ENABLED")
  driver:SetScript("OnEvent", function(_, event)
    inCombat = event == "PLAYER_REGEN_DISABLED"
  end)
end)
