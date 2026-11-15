local _, ns = ...

-- Builder for the page of this addon in the Options window of the game (under AddOns).
-- Each addon in the repository has its own copy of this file: see docs/addon-development.md.
--
--   local page = ns.NewSettingsPage("Forever Quests", "One line under the title.")
--   page:Header("Alerts")
--   page:Check({ label = "", hint = "", get = function() end, set = function(value) end })
--   page:Slider({ label = "", hint = "", min = 0, max = 10, step = 1, get = , set = , format = function(value) end })
--   page:Choice({ label = "", hint = "", values = { { value, "text" }, ... }, get = , set = })
--   local sub = ns.NewSettingsPage("Compass 1", nil, page)   -- a page under another page in the list
--   page:Buttons({ { label = "", hint = "", confirm = "Question?", click = function() end }, ... })
--   page:Info(function() return "text" end)
--   page:Register()   -- adds the page to the Options window; false if this client cannot
--   page:Open()       -- opens the page; false if it cannot open now
--   page:Refresh()    -- shows the current values; call it after a value changes somewhere else

local LEFT = 16
local ROW = 24
local WIDTH = 560

local Page = {}
Page.__index = Page

function ns.NewSettingsPage(name, subtitle, parent)
  local self = setmetatable({ name = name, parent = parent, refreshers = {}, y = -16 }, Page)
  self.panel = CreateFrame("Frame")
  self.panel:Hide()
  self.panel:SetScript("OnShow", function()
    self:Refresh()
  end)

  local title = self.panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", LEFT, self.y)
  title:SetText(name)
  self.y = self.y - 22
  if subtitle then
    local text = self.panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", LEFT, self.y)
    text:SetText(subtitle)
    self.y = self.y - 14
  end

  -- One confirmation dialog for the buttons of this page.
  self.popup = "FOREVER_" .. ((parent and parent.name or "") .. name):upper():gsub("%W", "") .. "_CONFIRM"
  if StaticPopupDialogs then
    StaticPopupDialogs[self.popup] = {
      text = "%s",
      button1 = YES or "Yes",
      button2 = NO or "No",
      OnAccept = function()
        local action = self.pending
        self.pending = nil
        if action then
          action()
          self:Refresh()
        end
      end,
      OnCancel = function()
        self.pending = nil
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
    }
  end
  return self
end

local function attachTooltip(frame, title, hint)
  if not hint then
    return
  end
  frame:HookScript("OnEnter", function(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(hint, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end

function Page:Header(text)
  self.y = self.y - 10
  local header = self.panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  header:SetPoint("TOPLEFT", LEFT, self.y)
  header:SetText(text)
  self.y = self.y - 18
end

function Page:Check(spec)
  local check = CreateFrame("CheckButton", nil, self.panel, "UICheckButtonTemplate")
  check:SetSize(ROW, ROW)
  check:SetPoint("TOPLEFT", LEFT - 2, self.y)
  local label = self.panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("LEFT", check, "RIGHT", 4, 0)
  label:SetText(spec.label)
  -- A click on the label also works.
  check:SetHitRectInsets(0, -(label:GetStringWidth() + 6), 0, 0)
  check:SetScript("OnClick", function(button)
    spec.set(button:GetChecked() and true or false)
  end)
  attachTooltip(check, spec.label, spec.hint)
  self.refreshers[#self.refreshers + 1] = function()
    check:SetChecked(spec.get() and true or false)
  end
  self.y = self.y - ROW
  return check
end

function Page:Slider(spec)
  local label = self.panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("TOPLEFT", LEFT + 4, self.y - 4)
  label:SetText(spec.label)
  self.y = self.y - 22

  local slider = CreateFrame("Slider", nil, self.panel, "UISliderTemplate")
  slider:SetSize(220, 17)
  slider:SetPoint("TOPLEFT", LEFT + 6, self.y)
  slider:SetMinMaxValues(spec.min, spec.max)
  slider:SetValueStep(spec.step or 1)
  if slider.SetObeyStepOnDrag then
    slider:SetObeyStepOnDrag(true)
  end
  local value = self.panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  value:SetPoint("LEFT", slider, "RIGHT", 10, 0)
  local format = spec.format or tostring

  local refreshing = false
  slider:SetScript("OnValueChanged", function(_, raw)
    if refreshing then
      return
    end
    spec.set(raw)
    value:SetText(format(spec.get()))
  end)
  attachTooltip(slider, spec.label, spec.hint)
  self.refreshers[#self.refreshers + 1] = function()
    local current = spec.get()
    refreshing = true
    slider:SetValue(math.max(spec.min, math.min(spec.max, current)))
    refreshing = false
    value:SetText(format(current))
  end
  self.y = self.y - 24
  return slider
end

-- A choice of one value from a list: a button that shows the current one and opens a menu.
function Page:Choice(spec)
  local label = self.panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("TOPLEFT", LEFT + 4, self.y - 6)
  label:SetText(spec.label)

  local button = CreateFrame("Button", nil, self.panel, "UIPanelButtonTemplate")
  button:SetSize(230, 22)
  button:SetPoint("TOPLEFT", LEFT + 190, self.y - 1)
  local function textOf(value)
    for _, entry in ipairs(spec.values) do
      if entry[1] == value then
        return entry[2]
      end
    end
    return tostring(value)
  end
  local function choose(value)
    spec.set(value)
    button:SetText(textOf(spec.get()))
  end
  button:SetScript("OnClick", function(owner)
    if MenuUtil and MenuUtil.CreateContextMenu then
      MenuUtil.CreateContextMenu(owner, function(_, root)
        for _, entry in ipairs(spec.values) do
          root:CreateRadio(entry[2], function()
            return spec.get() == entry[1]
          end, function()
            choose(entry[1])
          end)
        end
      end)
      return
    end
    -- Without the menu of the game, a click goes to the next value.
    local current = spec.get()
    for index, entry in ipairs(spec.values) do
      if entry[1] == current then
        choose(spec.values[index % #spec.values + 1][1])
        return
      end
    end
    choose(spec.values[1][1])
  end)
  attachTooltip(button, spec.label, spec.hint)
  self.refreshers[#self.refreshers + 1] = function()
    button:SetText(textOf(spec.get()))
  end
  self.y = self.y - 28
  return button
end

function Page:Buttons(specs)
  self.y = self.y - 4
  local x = LEFT + 2
  for _, spec in ipairs(specs) do
    local button = CreateFrame("Button", nil, self.panel, "UIPanelButtonTemplate")
    button:SetText(spec.label)
    local text = button:GetFontString()
    button:SetSize(math.max(110, (text and text:GetStringWidth() or 90) + 28), 22)
    button:SetPoint("TOPLEFT", x, self.y)
    button:SetScript("OnClick", function()
      if spec.confirm and StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs[self.popup] then
        self.pending = spec.click
        StaticPopup_Show(self.popup, spec.confirm)
      else
        spec.click()
        self:Refresh()
      end
    end)
    attachTooltip(button, spec.label, spec.hint)
    x = x + button:GetWidth() + 8
  end
  self.y = self.y - 28
end

function Page:Info(getText)
  local text = self.panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  text:SetPoint("TOPLEFT", LEFT + 4, self.y - 2)
  text:SetWidth(WIDTH)
  text:SetJustifyH("LEFT")
  self.refreshers[#self.refreshers + 1] = function()
    text:SetText(getText())
  end
  self.y = self.y - 18
  return text
end

function Page:Refresh()
  if not self.panel:IsShown() then
    return
  end
  for _, refresher in ipairs(self.refreshers) do
    local ok, err = pcall(refresher)
    if not ok then
      geterrorhandler()(err)
    end
  end
end

function Page:Register()
  if self.category then
    return true
  end
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
    return false
  end
  local ok, category = pcall(function()
    if self.parent then
      -- A page under another page. The parent must be registered first.
      return Settings.RegisterCanvasLayoutSubcategory(self.parent.category, self.panel, self.name)
    end
    local registered = Settings.RegisterCanvasLayoutCategory(self.panel, self.name)
    Settings.RegisterAddOnCategory(registered)
    return registered
  end)
  self.category = ok and category or nil
  return self.category ~= nil
end

function Page:Open()
  local category = self.category
  local id = category and (category.GetID and category:GetID() or category.ID)
  if not (id and Settings and Settings.OpenToCategory) then
    return false
  end
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  return (pcall(Settings.OpenToCategory, id))
end
