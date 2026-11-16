local _, ns = ...

-- The read-out of the player's own DPS (or HPS): one small line on the screen, for the current
-- fight. It does not need the meter window, and it works alone and in any group.

local frame

local function ownMode()
  return ns.ModeByKey[ns.GetOption("personalHealing") and "hps" or "dps"]
end

local function update()
  if not frame then
    return
  end
  if not ns.GetOption("personal") then
    frame:Hide()
    return
  end
  frame:Show()
  frame:SetMovable(not ns.GetOption("personalLock"))
  local mode = ownMode()
  frame.label:SetText(mode.short)
  local session = ns.GetSession(mode, { type = 1 })
  local own, rank
  if session then
    own, rank = ns.OwnSource(session)
  end
  if own then
    ns.SetNumber(frame.value, own.amountPerSecond)
    -- The place in the group, when there is a group.
    local count = #session.combatSources
    frame.rank:SetText(ns.GroupType() ~= "solo" and count > 1 and ("#" .. rank .. " of " .. count) or "")
  else
    frame.value:SetText("0")
    frame.rank:SetText("")
  end
end

local function create()
  frame = CreateFrame("Frame", "ForeverMeterPersonal", UIParent)
  frame:SetSize(150, 26)
  frame:SetFrameStrata("LOW")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if not ns.GetOption("personalLock") then
      self:StartMoving()
    end
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.SavePosition("personal", self)
  end)

  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0, 0, 0, 0.35)

  frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.label:SetPoint("LEFT", 6, 0)
  frame.value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  frame.value:SetPoint("LEFT", frame.label, "RIGHT", 6, 0)
  frame.rank = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.rank:SetPoint("RIGHT", -6, 0)

  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Forever Meter", 1, 1, 1)
    GameTooltip:AddLine("Your own " .. ownMode().label:lower() .. " in the current fight. Drag to move. Turn it off in the options (/fmeter options).", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  local elapsed = 0
  frame:SetScript("OnUpdate", function(_, seconds)
    elapsed = elapsed + seconds
    if elapsed >= ns.GetOption("updateTenths") / 10 then
      elapsed = 0
      update()
    end
  end)

  ns.RestorePosition("personal", frame, "CENTER", 0, -220)
end

ns.OnChange(update)

ns.OnResetPositions(function()
  if frame then
    ns.RestorePosition("personal", frame, "CENTER", 0, -220)
  end
end)

ns.OnLogin(function()
  create()
  update()
end)
