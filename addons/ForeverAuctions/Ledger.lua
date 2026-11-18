local _, ns = ...

-- Ledger: the sales and the purchases of the player at the auction house, with a window for them.
--
-- The game sends a mail with an invoice for each sale and each purchase. This file reads the
-- invoices of the mails in the inbox when the player is at a mailbox. It takes no mail and no money.
--
-- A mail stays in the inbox until the player takes it, so the same invoice is read many times.
-- realm.ledgerSeen has one record for each mail that is in the ledger already: the text of the
-- invoice and the time at which the mail expires, which does not change. A mail with the same text
-- and (almost) the same expiry time is the same mail.

local DAY = 86400
local MAIL_DAYS = 30 -- an auction house mail expires after 30 days, so this gives its arrival time
local SAME_MAIL_SECONDS = 300
local ROWS = 16
local ROW_HEIGHT = 18
local WIDTH, HEIGHT = 640, 478
local FRAME_NAME = "ForeverAuctionsLedgerFrame"

local frame
local filter = "all" -- "all", "sale" or "buy"
local filterDays -- nil: all the ledger has; else the last number of days
local filterName = "" -- lower case part of the item name, "" for any
local shown = {}
local offset = 0

function ns.Ledger()
  return ns.Realm().ledger
end

local function prune(now)
  local realm = ns.Realm()
  local oldest = now - ns.GetOption("ledgerDays") * DAY
  local ledger = realm.ledger
  local kept = {}
  for _, entry in ipairs(ledger) do
    if type(entry) == "table" and type(entry.t) == "number" and entry.t >= oldest then
      kept[#kept + 1] = entry
    end
  end
  if #kept ~= #ledger then
    realm.ledger = kept
  end
  -- A record of a mail is needed for as long as the mail can be in the inbox.
  local seen = {}
  for _, record in ipairs(realm.ledgerSeen) do
    if type(record) == "table" and type(record.exp) == "number" and record.exp > now - 3600 then
      seen[#seen + 1] = record
    end
  end
  realm.ledgerSeen = seen
end

-- Reads the invoices of the inbox. Returns the number of new sales and purchases.
local function readInbox()
  if not (GetInboxNumItems and GetInboxInvoiceInfo and GetInboxHeaderInfo) then
    return 0
  end
  local now = time()
  prune(now)
  local realm = ns.Realm()
  local ledger, seen = realm.ledger, realm.ledgerSeen
  local character = UnitName("player") or "?"
  local used = {}
  local added = 0
  for i = 1, GetInboxNumItems() or 0 do
    local invoiceType, itemName, playerName, bid, _, deposit, consignment, _, _, _, count = GetInboxInvoiceInfo(i)
    -- "seller_temp_invoice" is the notice of a sale whose money comes later, with a "seller" mail.
    if (invoiceType == "seller" or invoiceType == "buyer") and type(itemName) == "string" and type(bid) == "number" then
      local daysLeft = select(7, GetInboxHeaderInfo(i))
      if type(daysLeft) == "number" then
        deposit = type(deposit) == "number" and deposit or 0
        consignment = type(consignment) == "number" and consignment or 0
        count = type(count) == "number" and count > 0 and count or 1
        local expires = now + math.floor(daysLeft * DAY)
        local key = table.concat({ character, invoiceType, itemName, playerName or "", bid, deposit, consignment, count }, "|")
        local match
        for j, record in ipairs(seen) do
          if not used[j] and record.key == key and math.abs(record.exp - expires) <= SAME_MAIL_SECONDS then
            match = j
            break
          end
        end
        if match then
          used[match] = true
        else
          seen[#seen + 1] = { key = key, exp = expires }
          used[#seen] = true
          local sale = invoiceType == "seller"
          ledger[#ledger + 1] = {
            t = math.min(now, expires - MAIL_DAYS * DAY),
            kind = sale and "sale" or "buy",
            name = itemName,
            count = count,
            -- A sale: the price minus the cut of the auction house. A purchase: the price paid.
            amount = sale and math.max(0, bid - consignment) or bid,
            cut = sale and consignment or 0,
            who = playerName,
            char = character,
          }
          added = added + 1
        end
      end
    end
  end
  if added > 0 then
    table.sort(ledger, function(a, b)
      return a.t < b.t
    end)
  end
  return added
end

-- Sales and purchases of the last number of days (nil: all that the ledger has).
-- Returns the number of sales, their total, the number of purchases, their total.
function ns.LedgerSummary(days)
  local since = days and (time() - days * DAY) or 0
  local sales, earned, buys, spent = 0, 0, 0, 0
  for _, entry in ipairs(ns.Ledger()) do
    if entry.t >= since then
      if entry.kind == "sale" then
        sales, earned = sales + 1, earned + entry.amount
      else
        buys, spent = buys + 1, spent + entry.amount
      end
    end
  end
  return sales, earned, buys, spent
end

local function summaryLine(label, days)
  local sales, earned, buys, spent = ns.LedgerSummary(days)
  local net = earned - spent
  return string.format("%s: %d sold for %s, %d bought for %s, net %s%s", label, sales, ns.Money(earned), buys, ns.Money(spent),
    net < 0 and "-" or "", ns.Money(math.abs(net)))
end

function ns.ClearLedger()
  local realm = ns.Realm()
  -- The records of the mails stay, so a mail that is still in the inbox does not come back.
  realm.ledger = {}
  if ns.RefreshLedger then
    ns.RefreshLedger()
  end
end

---------------------------------------------------------------------------------------------------
-- Window

local FILTER_TEXT = { all = "Sales and purchases", sale = "Sales only", buy = "Purchases only" }
local NEXT_FILTER = { all = "sale", sale = "buy", buy = "all" }
local DAY_CHOICES = { 1, 7, 30 } -- the date button goes through these, then back to all

local function daysText()
  if not filterDays then
    return "All dates"
  end
  return filterDays == 1 and "Last 24 hours" or ("Last " .. filterDays .. " days")
end

local function render()
  if not frame then
    return
  end
  offset = math.max(0, math.min(offset, #shown - ROWS))
  for i, row in ipairs(frame.rows) do
    local entry = shown[offset + i]
    row:SetShown(entry ~= nil)
    if entry then
      local sale = entry.kind == "sale"
      row.when:SetText(ns.Age(entry.t))
      row.kind:SetText(sale and "Sold" or "Bought")
      row.kind:SetTextColor(sale and 0.3 or 0.95, sale and 0.9 or 0.6, 0.3)
      row.item:SetText(entry.count > 1 and (entry.name .. " x" .. entry.count) or entry.name)
      row.amount:SetText((sale and "+" or "-") .. ns.Money(entry.amount))
      row.who:SetText(entry.who or "")
      row.entry = entry
    end
  end
  frame.empty:SetShown(#shown == 0)
end

-- The lines that pass the filters, the newest first.
function ns.LedgerShown()
  local result = {}
  local ledger = ns.Ledger()
  local since = filterDays and (time() - filterDays * DAY) or nil
  for i = #ledger, 1, -1 do
    local entry = ledger[i]
    if (filter == "all" or entry.kind == filter) and (not since or entry.t >= since)
      and (filterName == "" or entry.name:lower():find(filterName, 1, true)) then
      result[#result + 1] = entry
    end
  end
  return result
end

-- kind: "all", "sale" or "buy". days: nil or a number of days. name: part of the item name.
function ns.SetLedgerFilter(kind, days, name)
  if kind and NEXT_FILTER[kind] then
    filter = kind
  end
  filterDays = type(days) == "number" and days > 0 and days or nil
  filterName = ((name or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
  if frame then
    if frame.nameBox and (frame.nameBox:GetText() or ""):lower() ~= filterName then
      frame.nameBox:SetText(name or "")
    end
    offset = 0
  end
  ns.RefreshLedger()
end

local function rebuild()
  if not (frame and ForeverAuctionsDB) then
    return
  end
  prune(time())
  shown = ns.LedgerShown()
  frame.summary:SetText(table.concat({
    summaryLine("Last 24 hours", 1),
    summaryLine("Last 7 days", 7),
    summaryLine("Last " .. ns.GetOption("ledgerDays") .. " days", nil),
  }, "\n"))
  frame.filterButton:SetText(FILTER_TEXT[filter])
  frame.daysButton:SetText(daysText())
  frame.count:SetText(#shown .. " of " .. #ns.Ledger() .. " lines. A sale shows the price minus the cut of the auction house.")
  render()
end

local COLUMNS = {
  { key = "when", label = "When", width = 70, justify = "LEFT" },
  { key = "kind", label = "", width = 54, justify = "LEFT" },
  { key = "item", label = "Item", width = 250, justify = "LEFT" },
  { key = "amount", label = "Gold", width = 120, justify = "RIGHT" },
  { key = "who", label = "Other player", width = 104, justify = "LEFT", gap = 10 },
}

local function addColumns(parent, font, texts)
  local x = 4
  for _, column in ipairs(COLUMNS) do
    x = x + (column.gap or 0)
    local text = parent:CreateFontString(nil, "ARTWORK", font)
    text:SetPoint("LEFT", x, 0)
    text:SetWidth(column.width - 6)
    text:SetJustifyH(column.justify)
    text:SetWordWrap(false)
    if texts then
      text:SetText(column.label)
    end
    parent[column.key] = text
    x = x + column.width
  end
end

local function savePosition()
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  if point and ForeverAuctionsDB then
    ForeverAuctionsDB.options.ledgerWindow = { point = point, relativePoint = relativePoint, x = x, y = y }
  end
end

local function restorePosition()
  local saved = ForeverAuctionsDB and ForeverAuctionsDB.options.ledgerWindow
  frame:ClearAllPoints()
  if type(saved) == "table" and type(saved.point) == "string" and type(saved.x) == "number" and type(saved.y) == "number" then
    local ok = pcall(frame.SetPoint, frame, saved.point, UIParent, saved.relativePoint or saved.point, saved.x, saved.y)
    if ok then
      return
    end
    frame:ClearAllPoints()
  end
  frame:SetPoint("CENTER")
end

-- Puts the window back in the middle of the screen.
function ns.ResetLedgerPosition()
  ForeverAuctionsDB.options.ledgerWindow = nil
  if frame then
    restorePosition()
  end
end

local function createWindow()
  local ok, window = pcall(CreateFrame, "Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
  if not ok then
    window = CreateFrame("Frame", FRAME_NAME, UIParent)
    local background = window:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.05, 0.05, 0.92)
    local okClose, close = pcall(CreateFrame, "Button", nil, window, "UIPanelCloseButton")
    if okClose then
      close:SetPoint("TOPRIGHT", 2, 2)
      close:SetScript("OnClick", function()
        window:Hide()
      end)
    end
    window.TitleText = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    window.TitleText:SetPoint("TOP", 0, -6)
  end
  frame = window
  frame:Hide()
  frame:SetSize(WIDTH, HEIGHT)
  restorePosition()
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition()
  end)
  -- Both forms of the window have the title text: the template, and the plain window above.
  frame.TitleText:SetText("Forever Auctions: sales and purchases")
  tinsert(UISpecialFrames, FRAME_NAME) -- Escape closes the window

  -- The template has an inset frame over its inside. Everything of ours goes on a frame above that.
  local content = CreateFrame("Frame", nil, frame)
  content:SetAllPoints()
  content:SetFrameLevel(frame:GetFrameLevel() + 10)

  frame.summary = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  frame.summary:SetPoint("TOPLEFT", 18, -34)
  frame.summary:SetJustifyH("LEFT")
  frame.summary:SetSpacing(3)

  frame.filterButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  frame.filterButton:SetSize(160, 22)
  frame.filterButton:SetPoint("TOPRIGHT", -18, -34)
  frame.filterButton:SetScript("OnClick", function()
    filter = NEXT_FILTER[filter]
    offset = 0
    rebuild()
  end)

  -- Second line: the item name and the dates.
  local okSearch, nameBox = pcall(CreateFrame, "EditBox", nil, content, "SearchBoxTemplate")
  if not okSearch then
    nameBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
  end
  frame.nameBox = nameBox
  nameBox:SetSize(220, 20)
  nameBox:SetPoint("TOPLEFT", 22, -90)
  nameBox:SetAutoFocus(false)
  if nameBox.Instructions then
    nameBox.Instructions:SetText("Search by item name")
  end
  nameBox:HookScript("OnTextChanged", function(self)
    local text = ((self:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
    if text ~= filterName then
      filterName = text
      offset = 0
      rebuild()
    end
  end)
  nameBox:HookScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)

  frame.daysButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  frame.daysButton:SetSize(160, 22)
  frame.daysButton:SetPoint("TOPRIGHT", -18, -88)
  frame.daysButton:SetScript("OnClick", function()
    local nextDays
    if not filterDays then
      nextDays = DAY_CHOICES[1]
    else
      for i, days in ipairs(DAY_CHOICES) do
        if days == filterDays then
          nextDays = DAY_CHOICES[i + 1]
        end
      end
    end
    filterDays = nextDays
    offset = 0
    rebuild()
  end)

  local header = CreateFrame("Frame", nil, content)
  header:SetHeight(ROW_HEIGHT)
  header:SetPoint("TOPLEFT", 14, -114)
  header:SetPoint("RIGHT", content, "RIGHT", -14, 0)
  addColumns(header, "GameFontNormalSmall", true)

  frame.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -(i - 1) * ROW_HEIGHT - 2)
    row:SetPoint("RIGHT", header, "RIGHT")
    addColumns(row, "GameFontHighlightSmall", false)
    if i % 2 == 0 then
      local stripe = row:CreateTexture(nil, "BACKGROUND")
      stripe:SetAllPoints()
      stripe:SetColorTexture(1, 1, 1, 0.04)
    end
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
      local entry = self.entry
      if not entry then
        return
      end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(entry.name, 1, 1, 1)
      GameTooltip:AddLine(date("%Y-%m-%d %H:%M", entry.t) .. ", on " .. (entry.char or "?"), nil, nil, nil, true)
      if entry.kind == "sale" then
        GameTooltip:AddLine("Sold for " .. ns.Money(entry.amount + entry.cut) .. ". The auction house took " .. ns.Money(entry.cut) .. ".", nil, nil, nil, true)
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    frame.rows[i] = row
  end

  frame.empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  frame.empty:SetPoint("TOP", header, "BOTTOM", 0, -60)
  frame.empty:SetWidth(WIDTH - 80)
  frame.empty:SetText("Nothing here yet. The ledger reads the auction house mails in your inbox when you open a mailbox.")

  frame.count = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  frame.count:SetPoint("BOTTOMLEFT", 16, 10)

  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    offset = offset - delta * 3
    render()
  end)
  frame:SetScript("OnShow", function()
    offset = 0
    rebuild()
  end)
end

function ns.ShowLedger()
  if not ForeverAuctionsDB then
    return
  end
  if not frame then
    local ok, problem = pcall(createWindow)
    if not ok then
      frame = nil
      ns.Print("the ledger window could not be made: " .. tostring(problem))
      return
    end
  end
  frame:Show()
  if frame.Raise then
    frame:Raise()
  end
end

function ns.ToggleLedger()
  if frame and frame:IsShown() then
    frame:Hide()
  else
    ns.ShowLedger()
  end
end

function ns.RefreshLedger()
  if frame and frame:IsShown() then
    rebuild()
  end
end

-- /fah ledger text: the totals in chat.
function ns.PrintLedger()
  prune(time())
  ns.Print("sales and purchases at the auction house:")
  print("  " .. summaryLine("Last 24 hours", 1))
  print("  " .. summaryLine("Last 7 days", 7))
  print("  " .. summaryLine("Last " .. ns.GetOption("ledgerDays") .. " days", nil))
end

ns.OnOptionChanged(function(key)
  if key == "ledgerDays" then
    ns.RefreshLedger()
  end
end)

---------------------------------------------------------------------------------------------------
-- Mail

local pending = false

local function onMail()
  pending = false
  if not (ForeverAuctionsDB and ns.GetOption("ledger")) then
    return
  end
  local ok, added = pcall(readInbox)
  if ok and added > 0 then
    ns.Print(string.format("%d new %s in the ledger. Type /fah ledger to see them.", added, added == 1 and "line" or "lines"))
    ns.RefreshLedger()
  end
end

local events = CreateFrame("Frame")
ns.SafeRegister(events, "MAIL_SHOW")
ns.SafeRegister(events, "MAIL_INBOX_UPDATE")
events:SetScript("OnEvent", function()
  -- MAIL_INBOX_UPDATE comes in bursts. One read per burst is enough.
  if not pending then
    pending = true
    C_Timer.After(0.5, onMail)
  end
end)
