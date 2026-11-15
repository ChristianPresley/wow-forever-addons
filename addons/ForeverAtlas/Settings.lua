local _, ns = ...

-- The "Forever Atlas" page in the game's Options window: one checkbox for each option.

local ROWS = {
  { "coords", "Coordinates on the world map", "Player and cursor coordinates in the corner of the world map." },
  { "hud", "Coordinates on screen", "A small read-out of your coordinates, shown without the map. Drag it to move it." },
  { "hudArea", "Area name in the read-out", "Shows the name of the area under the coordinates." },
  { "hudLock", "Lock the read-out and the waypoint arrow", "Locked frames do not move and let clicks through." },
  { "pins", "Visited-area pins", "A pin on the world map for each area this character has visited." },
  { "notes", "Map notes", "Shows your notes on the world map. Alt-click the map to add one." },
  { "announce", "First-visit messages", "A chat message when you enter an area for the first time." },
}

local category
local checks = {}

local function refresh()
  for key, check in pairs(checks) do
    check:SetChecked(ns.GetOption(key))
  end
end

local function build()
  local panel = CreateFrame("Frame")
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Forever Atlas")
  local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  hint:SetText("Type /fatlas for commands and /way 45.2 61.8 for a waypoint.")

  for i, row in ipairs(ROWS) do
    local key = row[1]
    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", 14, -52 - (i - 1) * 44)
    check:SetScript("OnClick", function(self)
      ns.SetOption(key, self:GetChecked())
    end)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", check, "TOPRIGHT", 4, -2)
    label:SetText(row[2])
    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    note:SetText(row[3])
    checks[key] = check
  end

  panel:SetScript("OnShow", refresh)
  return panel
end

function ns.OpenSettings()
  if category and Settings.OpenToCategory then
    local ok = pcall(Settings.OpenToCategory, category:GetID())
    if ok then
      return
    end
  end
  ns.Print("open the game's Options window and choose AddOns, Forever Atlas.")
end

ns.OnLogin(function()
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
    return
  end
  category = Settings.RegisterCanvasLayoutCategory(build(), "Forever Atlas")
  Settings.RegisterAddOnCategory(category)
  ns.OnOption(refresh)
end)
