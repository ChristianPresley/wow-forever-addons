local _, ns = ...

-- The meter window: a header and one bar for each player (or enemy) of the fight.
--
-- The window works the same without a group, in a party and in a raid. Only the number of bars
-- differs, and each kind of group has its own setting for it. The mouse wheel moves through a
-- longer list, and the bar of the player stays in view.

local HEADER = 20
local MAX_ROWS = 25
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local window
local rows = {}
local offset = 0
local lastCount = 0

local ROWS_OPTION = { solo = "rowsSolo", party = "rowsParty", raid = "rowsRaid" }
local SHOW_OPTION = { solo = "showSolo", party = "showParty", raid = "showRaid" }
local GROUP_NAME = { solo = "Solo", party = "Party", raid = "Raid" }

---------------------------------------------------------------------------------------------------
-- Menu

local REPORT_CHANNELS = {
  { "SELF", "Only to me" },
  { "SAY", "Say" },
  { "PARTY", "Party" },
  { "RAID", "Raid" },
  { "GUILD", "Guild" },
}

local function showMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    ns.Print("type /fmeter help for the commands.")
    return
  end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Forever Meter")

    local show = root:CreateButton("Show")
    for _, mode in ipairs(ns.MODES) do
      show:CreateRadio(mode.label, function()
        return ns.GetOption("mode") == mode.key
      end, function()
        ns.SetOption("mode", mode.key)
      end)
    end

    local fight = root:CreateButton("Fight")
    fight:CreateRadio("Current fight", function()
      return ns.segment.type == 1
    end, function()
      ns.SetSegment({ type = 1 })
    end)
    fight:CreateRadio("Whole session", function()
      return ns.segment.type == 0
    end, function()
      ns.SetSegment({ type = 0 })
    end)
    -- The earlier fights, the newest first.
    local sessions = ns.Sessions()
    for i = #sessions, math.max(1, #sessions - 9), -1 do
      local session = sessions[i]
      local label = type(session.name) == "string" and not ns.IsSecret(session.name) and session.name or ("Fight " .. i)
      if ns.Usable(session.durationSeconds) then
        label = label .. " (" .. ns.Clock(session.durationSeconds) .. ")"
      end
      fight:CreateRadio(label, function()
        return ns.segment.id == session.sessionID
      end, function()
        ns.SetSegment({ id = session.sessionID, name = label })
      end)
    end

    local report = root:CreateButton("Report to")
    for _, channel in ipairs(REPORT_CHANNELS) do
      report:CreateButton(channel[2], function()
        ns.Report(channel[1])
      end)
    end

    root:CreateButton("Delete all fights", function()
      ns.ConfirmReset()
    end)
    root:CreateCheckbox("Lock the window", function()
      return ns.GetOption("lock")
    end, function()
      ns.SetOption("lock", not ns.GetOption("lock"))
    end)
    root:CreateButton("Options", function()
      ns.OpenOptions()
    end)
    root:CreateButton("Hide the window", function()
      ns.SetOption("show", false)
      ns.Print("the window is hidden. Type /fmeter to show it.")
    end)
  end)
end

-- Asks before the data of all fights is deleted.
function ns.ConfirmReset()
  if StaticPopup_Show and StaticPopupDialogs then
    StaticPopupDialogs.FOREVER_METER_RESET = StaticPopupDialogs.FOREVER_METER_RESET or {
      text = "Delete the damage data of all fights?",
      button1 = YES or "Yes",
      button2 = NO or "No",
      OnAccept = function()
        ns.ResetData()
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
    }
    StaticPopup_Show("FOREVER_METER_RESET")
  else
    ns.ResetData()
  end
end

---------------------------------------------------------------------------------------------------
-- Rows

local function createRow(index)
  local row = CreateFrame("Button", nil, window)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  row.bar = CreateFrame("StatusBar", nil, row)
  row.bar:SetAllPoints()
  row.bar:SetStatusBarTexture(BAR_TEXTURE)
  row.bar:SetMinMaxValues(0, 1)
  row.bar:SetValue(0)

  row.back = row:CreateTexture(nil, "BACKGROUND")
  row.back:SetAllPoints()
  row.back:SetColorTexture(0, 0, 0, 0.35)

  -- A line on the left of the bar of the player.
  row.own = row.bar:CreateTexture(nil, "OVERLAY")
  row.own:SetColorTexture(1, 1, 1, 0.9)
  row.own:SetPoint("TOPLEFT")
  row.own:SetPoint("BOTTOMLEFT")
  row.own:SetWidth(2)

  row.value = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.value:SetPoint("RIGHT", -4, 0)
  row.value:SetJustifyH("RIGHT")

  row.name = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", 5, 0)
  row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  row:SetScript("OnClick", function(self, mouseButton)
    if mouseButton == "RightButton" then
      showMenu(self)
    elseif self.source then
      ns.ShowDetails(self.source)
    end
  end)
  row:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Forever Meter", 1, 1, 1)
    GameTooltip:AddLine("Click for the spells. Right-click for the menu. The mouse wheel moves the list.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  rows[index] = row
  return row
end

-- The text on the right of a bar.
local function setValue(row, source, mode, session)
  if mode.deaths then
    -- The time of the death in the fight. -1 means that the whole session has no such time.
    local seconds = source.deathTimeSeconds
    row.value:SetText(ns.Usable(seconds) and seconds >= 0 and ns.Clock(seconds) or "")
    return
  end
  local total, rate = source.totalAmount, source.amountPerSecond
  -- The share of the group total needs a calculation, so it comes when the numbers are readable.
  local suffix
  if ns.GetOption("showPercent") and ns.Usable(total) and ns.Usable(session.totalAmount) and session.totalAmount > 0 then
    suffix = string.format("  %d%%", math.floor(total / session.totalAmount * 100 + 0.5))
  end
  if mode.noRate then
    ns.SetNumber(row.value, total, false, nil, suffix)
  elseif mode.rate then
    ns.SetNumber(row.value, rate, true, total, suffix)
  else
    ns.SetNumber(row.value, total, true, rate, suffix)
  end
end

local function fillRow(row, source, rank, mode, session)
  row.source = source
  ns.SetName(row.name, source.name, ns.GetOption("showRank") and rank or nil)
  local r, g, b = ns.SourceColor(source.classFilename)
  row.bar:SetStatusBarColor(r, g, b, 0.85)
  if mode.deaths then
    ns.SetBar(row.bar, 1, 1)
  else
    ns.SetBar(row.bar, source.totalAmount, session.maxAmount)
  end
  setValue(row, source, mode, session)
  row.own:SetShown(source.isLocalPlayer == true)
  row:Show()
end

---------------------------------------------------------------------------------------------------
-- Window

local function shouldShow()
  if not ns.GetOption("show") or not ns.GetOption(SHOW_OPTION[ns.GroupType()]) then
    return false
  end
  if ns.GetOption("hideOutOfCombat") and not ns.InCombat() then
    return false
  end
  return true
end

local function layout()
  local rowHeight = ns.GetOption("rowHeight")
  local visible = ns.GetOption(ROWS_OPTION[ns.GroupType()])
  window:SetWidth(ns.GetOption("width"))
  window:SetHeight(HEADER + visible * rowHeight + 2)
  window.background:SetColorTexture(0.03, 0.03, 0.04, ns.GetOption("alpha") / 100)
  for index = 1, MAX_ROWS do
    local row = rows[index]
    if index <= visible then
      row = row or createRow(index)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 1, -HEADER - (index - 1) * rowHeight)
      row:SetPoint("RIGHT", window, "RIGHT", -1, 0)
      row:SetHeight(rowHeight - 1)
    elseif row then
      row:Hide()
      row.source = nil
    end
  end
  window:SetMovable(not ns.GetOption("lock"))
  return visible
end

local function update()
  if not window then
    return
  end
  if not shouldShow() then
    window:Hide()
    return
  end
  window:Show()
  local visible = layout()
  local mode, segment = ns.Mode(), ns.segment
  local group = ns.GroupType()

  window.title:SetText(mode.short .. " - " .. ns.SegmentName(segment))

  local available, reason = ns.Available()
  local session = available and ns.GetSession(mode, segment) or nil
  local sources = session and session.combatSources or {}
  local count = #sources
  lastCount = count
  offset = math.max(0, math.min(offset, count - visible))

  -- Right side of the header: the group total and the time of the fight.
  local duration = ns.Duration(segment)
  window.time:SetText(duration and ns.Clock(duration) or "")
  if session and count > 0 and not mode.deaths then
    ns.SetNumber(window.total, session.totalAmount)
  else
    window.total:SetText("")
  end

  local own, ownIndex
  if session then
    own, ownIndex = ns.OwnSource(session)
  end
  for index = 1, visible do
    local row = rows[index]
    local rank = offset + index
    local source = sources[rank]
    -- The last bar is the bar of the player when the player is farther down the list.
    if index == visible and own and ownIndex > offset + visible and ns.GetOption("pinSelf") then
      source, rank = own, ownIndex
    end
    if source then
      local ok = pcall(fillRow, row, source, rank, mode, session)
      if not ok then
        row:Hide()
      end
    else
      row:Hide()
      row.source = nil
    end
  end

  if count == 0 then
    if not available then
      window.note:SetText(reason)
    elseif ns.GameMeterEnabled() == false then
      window.note:SetText("No data. The damage meter of the game is off.\nType /fmeter enable to turn it on.")
    else
      window.note:SetText("No data for this fight yet.\n" .. GROUP_NAME[group] .. ": up to " .. visible .. " bars.")
    end
    window.note:Show()
  else
    window.note:Hide()
  end
end

ns.UpdateWindow = update

local function createWindow()
  window = CreateFrame("Frame", "ForeverMeterWindow", UIParent)
  window:SetFrameStrata("LOW")
  window:SetClampedToScreen(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", function(self)
    if not ns.GetOption("lock") then
      self:StartMoving()
    end
  end)
  window:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.SavePosition("window", self)
  end)

  window.background = window:CreateTexture(nil, "BACKGROUND")
  window.background:SetAllPoints()

  local header = CreateFrame("Button", nil, window)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetHeight(HEADER)
  header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function()
    if not ns.GetOption("lock") then
      window:StartMoving()
    end
  end)
  header:SetScript("OnDragStop", function()
    window:StopMovingOrSizing()
    ns.SavePosition("window", window)
  end)
  header:SetScript("OnClick", function(self)
    showMenu(self)
  end)
  header:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Forever Meter", 1, 1, 1)
    GameTooltip:AddLine("Click for the menu: what to show, which fight, report and options. Drag to move.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  header:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  local headerBack = header:CreateTexture(nil, "BACKGROUND")
  headerBack:SetAllPoints()
  headerBack:SetColorTexture(0.45, 0.12, 0.1, 0.85)

  window.time = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  window.time:SetPoint("RIGHT", -5, 0)
  window.total = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  window.total:SetPoint("RIGHT", window.time, "LEFT", -8, 0)
  window.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  window.title:SetPoint("LEFT", 5, 0)
  window.title:SetPoint("RIGHT", window.total, "LEFT", -6, 0)
  window.title:SetJustifyH("LEFT")
  window.title:SetWordWrap(false)

  window.note = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  window.note:SetPoint("TOPLEFT", 6, -HEADER - 4)
  window.note:SetPoint("RIGHT", -6, 0)
  window.note:SetJustifyH("LEFT")

  window:EnableMouseWheel(true)
  window:SetScript("OnMouseWheel", function(_, delta)
    local visible = ns.GetOption(ROWS_OPTION[ns.GroupType()])
    offset = math.max(0, math.min(offset - delta, lastCount - visible))
    update()
  end)

  ns.RestorePosition("window", window, "RIGHT", -40, -120)
end

ns.OnResetPositions(function()
  if window then
    ns.RestorePosition("window", window, "RIGHT", -40, -120)
  end
end)

ns.OnChange(function(key)
  if key == "mode" or key == nil then
    offset = 0
  end
  update()
end)

ns.OnLogin(function()
  createWindow()
  update()

  -- The numbers change all through a fight: the window reads them at a fixed interval while it
  -- is in view. The events below cover what changes the window when nothing is fought.
  local elapsed = 0
  local ticker = CreateFrame("Frame")
  ticker:SetScript("OnUpdate", function(_, seconds)
    elapsed = elapsed + seconds
    if elapsed >= ns.GetOption("updateTenths") / 10 then
      elapsed = 0
      if window:IsShown() then
        update()
      end
    end
  end)

  local events = CreateFrame("Frame")
  local wasInInstance
  for _, event in ipairs({
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
    "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET",
  }) do
    pcall(events.RegisterEvent, events, event)
  end
  events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
      local inInstance = IsInInstance and IsInInstance() and true or false
      if inInstance and wasInInstance == false and ns.GetOption("autoReset") then
        ns.ResetData()
        ns.Print("the data of earlier fights is deleted, because you entered an instance.")
      end
      wasInInstance = inInstance
    elseif event == "DAMAGE_METER_RESET" then
      offset = 0
    end
    update()
  end)
end)
