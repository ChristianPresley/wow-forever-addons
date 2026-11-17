local _, ns = ...

-- Shopping list: search texts that the player saved, in a panel beside the auction house window.
-- A click on one starts that search on the buy tab. The list is the same for all characters.

local MAX_ENTRIES = 100
local MAX_LENGTH = 60
local ROWS = 11
local ROW_HEIGHT = 20
local WIDTH, HEIGHT = 214, 344

local listeners = {}
local panel

local function changed()
  for _, listener in ipairs(listeners) do
    listener()
  end
end

function ns.ShoppingList()
  return ForeverAuctionsDB.shopping
end

-- Adds a search text. Returns true, or false and the reason.
function ns.AddSearch(text)
  text = ((text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
  -- An item link put into the text becomes the name of the item.
  text = text:gsub("|c%x+|Hitem:.-|h%[(.-)%]|h|r", "%1")
  if text == "" then
    return false, "type the text to search for."
  end
  text = text:sub(1, MAX_LENGTH)
  local list = ns.ShoppingList()
  for _, entry in ipairs(list) do
    if entry:lower() == text:lower() then
      return false, "\"" .. entry .. "\" is on the shopping list already."
    end
  end
  if #list >= MAX_ENTRIES then
    return false, "the shopping list is full (" .. MAX_ENTRIES .. " searches)."
  end
  list[#list + 1] = text
  table.sort(list, function(a, b)
    return a:lower() < b:lower()
  end)
  changed()
  return true
end

-- Removes a search by its text. Returns true if it was on the list.
function ns.RemoveSearch(text)
  local list = ns.ShoppingList()
  text = (text or ""):lower()
  for i, entry in ipairs(list) do
    if entry:lower() == text then
      table.remove(list, i)
      changed()
      return true
    end
  end
  return false
end

function ns.ClearShoppingList()
  wipe(ns.ShoppingList())
  changed()
end

-- Starts a search on the buy tab of the auction house, the same way as the search box of the game.
function ns.RunSearch(text)
  local house = AuctionHouseFrame
  if not (house and house:IsShown()) then
    ns.Print("open the auction house first.")
    return false
  end
  local bar = house.SearchBar
  if not (bar and bar.SetSearchText and bar.StartSearch) then
    ns.Print("this game client has no search bar that an addon can use.")
    return false
  end
  -- The buy tab, only if the house shows another one: the addon changes as little of the
  -- game's window as it can.
  local buy = AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy
  local now = house.GetDisplayMode and house:GetDisplayMode()
  if buy and house.SetDisplayMode and now ~= buy then
    pcall(house.SetDisplayMode, house, buy)
  end
  bar:SetSearchText(text)
  local ok = pcall(bar.StartSearch, bar)
  if not ok then
    ns.Print("the search could not start. Press Enter in the search box.")
  end
  return ok
end

-- The text in the search box of the auction house, or nil.
local function currentSearch()
  local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
  local box = bar and bar.SearchBox
  local text = box and box.GetText and box:GetText()
  if type(text) == "string" and text:gsub("%s", "") ~= "" then
    return text
  end
  return nil
end

---------------------------------------------------------------------------------------------------
-- Panel

local function tooltip(frame, title, text)
  frame:SetScript("OnEnter", function(self)
    if self.highlight then
      self.highlight:Show()
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if text then
      GameTooltip:AddLine(text, nil, nil, nil, true)
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function(self)
    if self.highlight then
      self.highlight:Hide()
    end
    GameTooltip:Hide()
  end)
end

local function button(parent, text, width)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  return b
end

local function render()
  if not panel then
    return
  end
  local list = ns.ShoppingList()
  panel.offset = math.max(0, math.min(panel.offset, #list - ROWS))
  for i, row in ipairs(panel.rows) do
    local entry = list[panel.offset + i]
    row.entry = entry
    row:SetShown(entry ~= nil)
    if entry then
      row.text:SetText(entry)
    end
  end
  panel.empty:SetShown(#list == 0)
  panel.count:SetText(#list > ROWS and string.format("%d searches (scroll)", #list) or "")
end

local function createRow(parent, index)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 8, -86 - (index - 1) * ROW_HEIGHT)
  row:SetPoint("RIGHT", parent, "RIGHT", -8, 0)

  row.highlight = row:CreateTexture(nil, "BACKGROUND")
  row.highlight:SetAllPoints()
  row.highlight:SetColorTexture(1, 1, 1, 0.1)
  row.highlight:Hide()

  row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.text:SetPoint("LEFT", 4, 0)
  row.text:SetPoint("RIGHT", -22, 0)
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)

  row:SetScript("OnClick", function(self)
    if self.entry then
      ns.RunSearch(self.entry)
    end
  end)
  tooltip(row, "Search", "Click to search the auction house for this text.")

  local remove = CreateFrame("Button", nil, row)
  remove:SetSize(18, ROW_HEIGHT)
  remove:SetPoint("RIGHT")
  local cross = remove:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  cross:SetPoint("CENTER")
  cross:SetText("x")
  cross:SetTextColor(0.9, 0.3, 0.3)
  remove:SetScript("OnClick", function()
    if row.entry then
      ns.RemoveSearch(row.entry)
    end
  end)
  tooltip(remove, "Remove", "Takes this search off the shopping list.")
  return row
end

local function addFromBox()
  local ok, problem = ns.AddSearch(panel.box:GetText())
  if ok then
    panel.box:SetText("")
  else
    ns.Print(problem)
  end
  panel.box:ClearFocus()
end

local function createPanel()
  local house = AuctionHouseFrame
  panel = CreateFrame("Frame", nil, house)
  panel:SetSize(WIDTH, HEIGHT)
  panel:SetPoint("TOPLEFT", house, "TOPRIGHT", 2, -20)
  panel:EnableMouse(true)
  panel.offset = 0

  local background = panel:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.04, 0.04, 0.04, 0.92)
  for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
    local line = panel:CreateTexture(nil, "BORDER")
    line:SetColorTexture(0.55, 0.45, 0.25, 0.9)
    line:SetPoint(edge[1])
    line:SetPoint(edge[2])
    if edge[3] then
      line:SetHeight(1)
    else
      line:SetWidth(1)
    end
  end

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOP", 0, -8)
  title:SetText("Shopping list")

  panel.box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  panel.box:SetSize(134, 20)
  panel.box:SetPoint("TOPLEFT", 14, -30)
  panel.box:SetAutoFocus(false)
  panel.box:SetMaxLetters(MAX_LENGTH)
  panel.box:SetScript("OnEnterPressed", addFromBox)
  panel.box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)

  local add = button(panel, "Add", 52)
  add:SetPoint("LEFT", panel.box, "RIGHT", 4, 0)
  add:SetScript("OnClick", addFromBox)
  tooltip(add, "Add a search", "Saves the text in the box to the left as a search.")

  local addCurrent = button(panel, "Add the current search", WIDTH - 16)
  addCurrent:SetPoint("TOPLEFT", 8, -56)
  addCurrent:SetScript("OnClick", function()
    local text = currentSearch()
    if not text then
      ns.Print("the search box of the auction house is empty.")
      return
    end
    local ok, problem = ns.AddSearch(text)
    if not ok then
      ns.Print(problem)
    end
  end)
  tooltip(addCurrent, "Add the current search", "Saves the text that is in the search box of the auction house.")

  panel.rows = {}
  for i = 1, ROWS do
    panel.rows[i] = createRow(panel, i)
  end

  panel.empty = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  panel.empty:SetPoint("TOP", 0, -110)
  panel.empty:SetWidth(WIDTH - 30)
  panel.empty:SetText("No saved searches yet.\nType a name above and click Add.")

  panel.count = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  panel.count:SetPoint("BOTTOM", 0, 34)

  local deals = button(panel, "Deals", (WIDTH - 20) / 2)
  deals:SetPoint("BOTTOMLEFT", 8, 8)
  deals:SetScript("OnClick", function()
    ns.ShowDeals()
  end)
  tooltip(deals, "Deals", "Opens the price window with the items that are now far below their average price.")

  local history = button(panel, "Prices", (WIDTH - 20) / 2)
  history:SetPoint("BOTTOMRIGHT", -8, 8)
  history:SetScript("OnClick", function()
    ns.ShowHistory()
  end)
  tooltip(history, "Prices", "Opens the price history window.")

  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta)
    panel.offset = panel.offset - delta * 2
    render()
  end)
end

listeners[#listeners + 1] = render

ns.OnOptionChanged(function(key, value)
  if key == "shoppingPanel" and panel then
    panel:SetShown(value)
  end
end)

local events = CreateFrame("Frame")
ns.SafeRegister(events, "AUCTION_HOUSE_SHOW")
events:SetScript("OnEvent", function()
  if not ForeverAuctionsDB then
    return
  end
  if not panel and AuctionHouseFrame then
    if not pcall(createPanel) then
      if panel then
        panel:Hide()
      end
      panel = nil
      events:UnregisterAllEvents()
      return
    end
  end
  if panel then
    panel:SetShown(ns.GetOption("shoppingPanel"))
    render()
  end
end)
