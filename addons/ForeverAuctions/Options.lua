local _, ns = ...

-- Settings page in the game's Options window, under AddOns.

local CATEGORY_NAME = "Forever Auctions"
local SLIDER_MAX = 100

local CHECKS = {
  { key = "tooltip", label = "Tooltip: auction price and average" },
  { key = "tooltipVendor", label = "Tooltip: vendor sell price" },
  { key = "tooltipStack", label = "Tooltip: auction value of the whole stack" },
  { key = "tooltipStackVendor", label = "Tooltip: vendor value of the whole stack" },
}

local category, panel
local checks = {}
local slider, sliderValue

local function refresh()
  if not panel then
    return
  end
  for key, check in pairs(checks) do
    check:SetChecked(ns.GetOption(key) and true or false)
  end
  local undercut = ns.GetOption("undercut")
  slider:SetValue(math.min(undercut, SLIDER_MAX))
  sliderValue:SetText(undercut .. " copper")
end

local function createPanel()
  panel = CreateFrame("Frame")
  panel:Hide()

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(CATEGORY_NAME)

  local anchor = title
  for index, option in ipairs(CHECKS) do
    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", index == 1 and -2 or 0, index == 1 and -14 or -4)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetText(option.label)
    check:SetScript("OnClick", function(self)
      ns.SetOption(option.key, self:GetChecked() and true or false)
    end)
    checks[option.key] = check
    anchor = check
  end

  local sliderLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  sliderLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -22)
  sliderLabel:SetText("Posting helper: undercut the lowest price by")

  slider = CreateFrame("Slider", nil, panel, "UISliderTemplate")
  slider:SetSize(220, 17)
  slider:SetPoint("TOPLEFT", sliderLabel, "BOTTOMLEFT", 0, -10)
  slider:SetMinMaxValues(0, SLIDER_MAX)
  slider:SetValueStep(1)
  if slider.SetObeyStepOnDrag then
    slider:SetObeyStepOnDrag(true)
  end
  sliderValue = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  sliderValue:SetPoint("LEFT", slider, "RIGHT", 10, 0)
  slider:SetScript("OnValueChanged", function(_, value, isUserInput)
    if isUserInput then
      ns.SetOption("undercut", value)
    end
  end)

  local sliderHelp = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  sliderHelp:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -8)
  sliderHelp:SetWidth(520)
  sliderHelp:SetJustifyH("LEFT")
  sliderHelp:SetText("For a larger amount type /fah undercut and the amount, for example /fah undercut 5s. Where the auction house only takes whole silver, the price is rounded down to whole silver.")

  local history = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  history:SetSize(160, 22)
  history:SetPoint("TOPLEFT", sliderHelp, "BOTTOMLEFT", 0, -20)
  history:SetText("Open price history")
  history:SetScript("OnClick", function()
    ns.ShowHistory()
  end)

  panel:SetScript("OnShow", refresh)
  return panel
end

function ns.OpenOptions()
  if category and Settings and Settings.OpenToCategory then
    local ok = pcall(Settings.OpenToCategory, category:GetID())
    if ok then
      return
    end
  end
  ns.Print("the settings page cannot be opened now. Type /fah help for the commands.")
end

ns.OnOptionChanged(function()
  if panel and panel:IsShown() then
    refresh()
  end
end)

ns.OnReady(function()
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
    return
  end
  local ok, result = pcall(function()
    local registered = Settings.RegisterCanvasLayoutCategory(createPanel(), CATEGORY_NAME)
    Settings.RegisterAddOnCategory(registered)
    return registered
  end)
  if ok then
    category = result
  else
    panel = nil
  end
end)
