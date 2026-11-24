local _, ns = ...

-- Export and import of the stored prices as a line of text, to copy to another character, another
-- account or another player. The text holds the latest lowest price of each item and when it was seen:
--   FAH1:itemID,price,seen;itemID,price,seen;...
-- An import keeps whichever price of an item was seen later, and adds the imported price to the daily
-- lows of its day. It never deletes a price.

local PREFIX = "FAH1:"
local MAX_TEXT = 2000000 -- characters an import reads at most
local MAX_ITEMS = 100000
local MAX_ITEM_ID = 10000000
local MAX_PRICE = 10 ^ 12 -- copper, far above any real price
local DAY = 86400
local FRAME_NAME = "ForeverAuctionsExportFrame"

-- The stored prices of this realm and faction as text, and the number of items in it.
function ns.ExportPrices()
  local ids = {}
  for itemID, entry in pairs(ns.Prices()) do
    if type(itemID) == "number" and type(entry) == "table" and type(entry.price) == "number" then
      ids[#ids + 1] = itemID
    end
  end
  table.sort(ids)
  local prices = ns.Prices()
  local parts = {}
  for i, itemID in ipairs(ids) do
    local entry = prices[itemID]
    parts[i] = string.format("%d,%d,%d", itemID, entry.price, type(entry.seen) == "number" and entry.seen or 0)
  end
  return PREFIX .. table.concat(parts, ";"), #ids
end

-- Reads an export text into the stored prices. Returns the number of items read and the number that
-- changed a stored price, or nil and the reason.
function ns.ImportPrices(text)
  if type(text) ~= "string" then
    return nil, "there is no text to import."
  end
  text = text:gsub("%s+", "")
  if #text > MAX_TEXT then
    return nil, "the text is too long to be an export of Forever Auctions."
  end
  if text:sub(1, #PREFIX) ~= PREFIX then
    return nil, "the text is not an export of Forever Auctions (it starts with " .. PREFIX .. ")."
  end
  local now = time()
  local rows = {}
  for part in text:sub(#PREFIX + 1):gmatch("[^;]+") do
    local itemID, price, seen = part:match("^(%d+),(%d+),(%d+)$")
    itemID, price, seen = tonumber(itemID), tonumber(price), tonumber(seen)
    if not (itemID and itemID > 0 and itemID < MAX_ITEM_ID and price > 0 and price < MAX_PRICE and seen <= now + DAY) then
      return nil, "the text is damaged near \"" .. part:sub(1, 30) .. "\". Nothing was imported."
    end
    rows[#rows + 1] = { itemID, price, seen }
    if #rows > MAX_ITEMS then
      return nil, "the text has more than " .. MAX_ITEMS .. " items. Nothing was imported."
    end
  end
  if #rows == 0 then
    return nil, "the text has no prices."
  end
  local prices = ns.Prices()
  local oldest = math.floor(now / DAY) - ns.GetOption("historyDays")
  local changed = 0
  for _, row in ipairs(rows) do
    local itemID, price, seen = row[1], row[2], math.min(row[3], now)
    local entry = prices[itemID]
    if type(entry) ~= "table" then
      entry = { days = {} }
      prices[itemID] = entry
    end
    if type(entry.days) ~= "table" then
      entry.days = {}
    end
    local day = math.floor(seen / DAY)
    if day > oldest and (not entry.days[day] or price < entry.days[day]) then
      entry.days[day] = price
    end
    if type(entry.seen) ~= "number" or type(entry.price) ~= "number" or seen > entry.seen then
      entry.price, entry.seen = price, seen
      changed = changed + 1
    end
  end
  if ns.RefreshHistory then
    ns.RefreshHistory()
  end
  return #rows, changed
end

---------------------------------------------------------------------------------------------------
-- Window: one text box, filled for an export, empty for an import.

local frame

local function createWindow()
  local ok, window = pcall(CreateFrame, "Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
  if not ok then
    window = CreateFrame("Frame", FRAME_NAME, UIParent)
    local background = window:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    window.TitleText = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    window.TitleText:SetPoint("TOP", 0, -6)
  end
  frame = window
  frame:Hide()
  frame:SetSize(520, 320)
  frame:SetPoint("CENTER")
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  tinsert(UISpecialFrames, FRAME_NAME)

  local content = CreateFrame("Frame", nil, frame)
  content:SetAllPoints()
  content:SetFrameLevel(frame:GetFrameLevel() + 10)

  frame.help = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  frame.help:SetPoint("TOPLEFT", 16, -32)
  frame.help:SetPoint("RIGHT", content, "RIGHT", -16, 0)
  frame.help:SetJustifyH("LEFT")

  local okScroll, scroll = pcall(CreateFrame, "ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
  if not okScroll then
    scroll = CreateFrame("ScrollFrame", nil, content)
  end
  scroll:SetPoint("TOPLEFT", 16, -64)
  scroll:SetPoint("BOTTOMRIGHT", -34, 44)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject("ChatFontSmall")
  box:SetWidth(460)
  box:SetMaxLetters(0)
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  scroll:SetScrollChild(box)
  frame.box = box

  frame.action = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  frame.action:SetSize(140, 22)
  frame.action:SetPoint("BOTTOMRIGHT", -16, 14)
  frame.action:SetScript("OnClick", function()
    if frame.mode == "import" then
      local read, changed = ns.ImportPrices(box:GetText())
      if read then
        ns.Print(string.format("%d prices imported, %d of them newer than the stored ones.", read, changed))
        box:SetText("")
        frame:Hide()
      else
        ns.Print(changed)
      end
    else
      box:SetFocus()
      box:HighlightText()
    end
  end)
end

local function open(mode)
  if not ForeverAuctionsDB then
    return
  end
  if not frame then
    local ok, problem = pcall(createWindow)
    if not ok then
      frame = nil
      ns.Print("the export window could not be made: " .. tostring(problem))
      return
    end
  end
  frame.mode = mode
  if mode == "import" then
    frame.TitleText:SetText("Forever Auctions: import prices")
    frame.help:SetText("Paste the text of an export below (Ctrl+V) and click Import. A newer price of an item replaces the stored one; nothing is deleted.")
    frame.box:SetText("")
    frame.action:SetText("Import")
  else
    local text, count = ns.ExportPrices()
    frame.TitleText:SetText("Forever Auctions: export prices")
    frame.help:SetText(string.format("%d prices of %s. Copy the text below (Ctrl+C) and import it with /fah import on another character.",
      count, ns.RealmName() .. ", " .. (UnitFactionGroup("player") or "Neutral")))
    frame.box:SetText(text)
    frame.action:SetText("Select all")
  end
  frame:Show()
  if mode == "export" then
    frame.box:SetFocus()
    frame.box:HighlightText()
  else
    frame.box:SetFocus()
  end
end

function ns.ShowExport()
  open("export")
end

function ns.ShowImport()
  open("import")
end
