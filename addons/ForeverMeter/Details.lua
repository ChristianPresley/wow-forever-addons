local _, ns = ...

-- The spells of one player: a small window that opens with a click on a bar of the meter.
--
-- During a fight the game hides who a source is, and then it refuses the request for its spells.
-- The window says so and fills in after the fight.

local ROWS = 12
local ROW_HEIGHT = 18
local WIDTH = 300
local HEADER = 22
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local frame
local shownSource -- what the window is for: { guid, creatureID, name, class }

local function spellName(spellID)
  if C_Spell and C_Spell.GetSpellName then
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if ok then
      return true, name
    end
  end
  return false
end

local function fillRow(row, spell, source, mode)
  local found, name = spellName(spell.spellID)
  if not found or not pcall(row.name.SetText, row.name, name) then
    row.name:SetText("Spell")
  end
  ns.SetBar(row.bar, spell.totalAmount, source.maxAmount)
  local suffix
  if ns.Usable(spell.totalAmount) and ns.Usable(source.totalAmount) and source.totalAmount > 0 then
    suffix = string.format("  %d%%", math.floor(spell.totalAmount / source.totalAmount * 100 + 0.5))
  end
  if mode.noRate then
    ns.SetNumber(row.value, spell.totalAmount, false, nil, suffix)
  else
    ns.SetNumber(row.value, spell.totalAmount, true, spell.amountPerSecond, suffix)
  end
  row.spellID = spell.spellID
  row:Show()
end

local function update()
  if not (frame and frame:IsShown() and shownSource) then
    return
  end
  local mode, segment = ns.Mode(), ns.segment
  frame.title:SetText(mode.short .. " - " .. ns.SegmentName(segment))
  -- A source that was clicked during a fight has a secret identity, and that value stays
  -- secret after the fight. So the source is read again from the fight: the player's own
  -- one, or the one at the same place in the list.
  if ns.IsSecret(shownSource.guid) or ns.IsSecret(shownSource.name) then
    local session = ns.GetSession(mode, segment)
    local again
    if session then
      if shownSource.isLocal then
        again = ns.OwnSource(session)
      else
        again = session.combatSources[shownSource.rank or 0]
      end
    end
    if again and not ns.IsSecret(again.sourceGUID) then
      shownSource.guid, shownSource.creatureID = again.sourceGUID, again.sourceCreatureID
      shownSource.name, shownSource.class = again.name, again.classFilename
    end
  end
  ns.SetName(frame.who, shownSource.name)
  local r, g, b = ns.SourceColor(shownSource.class)

  local source = ns.GetSource(mode, segment, shownSource.guid, shownSource.creatureID)
  local spells = source and source.combatSpells or {}
  for index, row in ipairs(frame.rows) do
    local spell = spells[index]
    if spell then
      row.bar:SetStatusBarColor(r, g, b, 0.8)
      if not pcall(fillRow, row, spell, source, mode) then
        row:Hide()
      end
    else
      row:Hide()
    end
  end
  if #spells == 0 then
    frame.note:SetText(ns.InCombat()
      and "The game gives the spells of a player after the fight.\nThis window fills in then."
      or "No spells for this player in this fight.")
    frame.note:Show()
  else
    frame.note:Hide()
  end
end

local function create()
  frame = CreateFrame("Frame", "ForeverMeterDetails", UIParent)
  frame:SetSize(WIDTH, HEADER * 2 + ROWS * ROW_HEIGHT + 6)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.SavePosition("details", self)
  end)
  frame:Hide()
  tinsert(UISpecialFrames, "ForeverMeterDetails") -- Escape closes the window

  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.03, 0.03, 0.04, 0.92)
  local headerBack = frame:CreateTexture(nil, "BORDER")
  headerBack:SetPoint("TOPLEFT")
  headerBack:SetPoint("TOPRIGHT")
  headerBack:SetHeight(HEADER)
  headerBack:SetColorTexture(0.45, 0.12, 0.1, 0.85)

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.title:SetPoint("TOPLEFT", 6, -5)

  local close = CreateFrame("Button", nil, frame)
  close:SetSize(HEADER, HEADER)
  close:SetPoint("TOPRIGHT")
  local cross = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  cross:SetPoint("CENTER")
  cross:SetText("x")
  close:SetScript("OnClick", function()
    frame:Hide()
  end)

  frame.who = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.who:SetPoint("TOPLEFT", 6, -HEADER - 4)

  frame.rows = {}
  for index = 1, ROWS do
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(ROW_HEIGHT - 1)
    row:SetPoint("TOPLEFT", 1, -HEADER * 2 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", frame, "RIGHT", -1, 0)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetAllPoints()
    row.bar:SetStatusBarTexture(BAR_TEXTURE)
    row.value = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("RIGHT", -4, 0)
    row.name = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 5, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
      if self.spellID and not ns.IsSecret(self.spellID) then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID) then
          GameTooltip:Show()
        end
      end
    end)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    row:Hide()
    frame.rows[index] = row
  end

  frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.note:SetPoint("TOPLEFT", 8, -HEADER * 2 - 6)
  frame.note:SetPoint("RIGHT", -8, 0)
  frame.note:SetJustifyH("LEFT")

  local elapsed = 0
  frame:SetScript("OnUpdate", function(_, seconds)
    elapsed = elapsed + seconds
    if elapsed >= 1 then
      elapsed = 0
      update()
    end
  end)

  ns.RestorePosition("details", frame, "CENTER", 0, 0)
end

-- Opens the window for a source of the meter (an entry of combatSources).
-- `rank` is the place of the source in the list of the meter.
function ns.ShowDetails(source, rank)
  if not frame then
    if not pcall(create) then
      frame = nil
      return
    end
  end
  shownSource = {
    guid = source.sourceGUID,
    creatureID = source.sourceCreatureID,
    name = source.name,
    class = source.classFilename,
    isLocal = source.isLocalPlayer == true,
    rank = rank,
  }
  frame:Show()
  update()
end

ns.OnChange(update)

ns.OnResetPositions(function()
  if frame then
    ns.RestorePosition("details", frame, "CENTER", 0, 0)
  end
end)
