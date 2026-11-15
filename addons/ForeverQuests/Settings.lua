local _, ns = ...

-- The "Forever Quests" page in the Options window of the game: one checkbox for each option.

local category
local boxes = {}

local function refresh()
  for key, box in pairs(boxes) do
    box:SetChecked(ns.GetOption(key))
  end
end

local function createPanel()
  local panel = CreateFrame("Frame")
  panel:Hide()

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Forever Quests")

  local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  subtitle:SetText("These settings are for all your characters. You can also change them with /fq.")

  for i, option in ipairs(ns.OPTIONS) do
    local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    box:SetSize(26, 26)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -62 - (i - 1) * 44)
    box:SetScript("OnClick", function(self)
      ns.SetOption(option.key, self:GetChecked() and true or false)
    end)

    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, -3)
    label:SetText(option.text)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    hint:SetText(option.hint)

    boxes[option.key] = box
  end

  panel:SetScript("OnShow", refresh)
  return panel
end

local function register()
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
    return
  end
  category = Settings.RegisterCanvasLayoutCategory(createPanel(), "Forever Quests")
  Settings.RegisterAddOnCategory(category)
  ns.OnOptionChanged(refresh)
end

-- /fq options
function ns.OpenOptions()
  local id = category and (category.GetID and category:GetID() or category.ID)
  if not (id and Settings and Settings.OpenToCategory) then
    ns.Print("the options page is not available. Type /fq for the settings.")
    return
  end
  if InCombatLockdown and InCombatLockdown() then
    ns.Print("the options page cannot open in combat.")
    return
  end
  if not pcall(Settings.OpenToCategory, id) then
    ns.Print("the options page did not open. Type /fq for the settings.")
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  if not pcall(register) then
    category = nil
  end
end)
