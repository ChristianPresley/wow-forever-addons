local _, ns = ...

-- Price history window: every stored item of this realm and faction with its latest price, its age and the low,
-- high and average of the stored daily lows.

local FRAME_NAME = "ForeverAuctionsHistoryFrame"
local WIDTH, HEIGHT = 932, 526
local ROW_HEIGHT = 20
local LIST_TOP = 112 -- from the top of the window to the first row
local LIST_BOTTOM = 30
local LIST_HEIGHT = HEIGHT - LIST_TOP - LIST_BOTTOM
local SCROLL_GUTTER = 22
local MONEY_WIDTH = 112
local AGE_WIDTH = 70
local LOAD_BATCH = 40 -- item names asked for per step
local LOAD_PAUSE = 0.1
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Columns from left to right. The name column takes the width that is left.
local COLUMNS = {
  { key = "name", label = "Item", descending = false },
  { key = "price", label = "Price", width = MONEY_WIDTH, descending = true },
  { key = "seen", label = "Age", width = AGE_WIDTH, descending = true },
  { key = "low", label = "Low", width = MONEY_WIDTH, descending = true },
  { key = "high", label = "High", width = MONEY_WIDTH, descending = true },
  { key = "avg", label = "Average", width = MONEY_WIDTH, descending = true },
  { key = "pct", label = "Of avg", width = 60, descending = false },
  { key = "profit", label = "Craft profit", width = MONEY_WIDTH, descending = true },
}
local DEAL_MIN_DAYS = 2 -- an average of one day says nothing about a deal

local frame, list, searchBox, countText
local headers = {}
local allRows = {} -- one per stored item: { id, price, seen, low, high, avg }
local shown = {} -- the rows that pass the search, sorted
local info = {} -- [itemID] = { name, lower, quality }, filled as the client loads the items
local pending = {} -- [itemID] = true while the name is asked for
local queue, queuePosition = {}, 1
local loaderRunning = false
local sortKey, sortDescending = "seen", true
local filter = ""
local dirty = false -- names arrived since the last redraw
local dealsOnly = false
local dealsButton, filterText, minBox, maxBox
local showFilterMenu

-- The filters of the window, besides the name search and the deals. Nil is "any".
-- class, subclass: item class and subclass IDs. quality: the lowest quality shown.
-- minPrice, maxPrice: copper. seenWithin: seconds. watched: only items with a price alert.
local filters = {}
local FILTER_KEYS = { class = "number", subclass = "number", quality = "number", minPrice = "number", maxPrice = "number", seenWithin = "number", watched = "boolean" }
local types = {} -- [itemID] = { class, subclass, className, subclassName }, from the client's item data
local QUALITIES = { 0, 1, 2, 3, 4, 5 }
local QUALITY_NAMES = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local SEEN_CHOICES = { { 3600, "the last hour" }, { 86400, "the last day" }, { 7 * 86400, "the last 7 days" }, { 30 * 86400, "the last 30 days" } }

local function qualityName(quality)
  local text = _G["ITEM_QUALITY" .. quality .. "_DESC"]
  return type(text) == "string" and text or QUALITY_NAMES[quality] or tostring(quality)
end

-- Class and subclass of an item. The client has them for every item without loading it.
local function typeOf(itemID)
  local known = types[itemID]
  if known then
    return known
  end
  local get = C_Item and C_Item.GetItemInfoInstant
  if not get then
    return nil
  end
  local _, className, subclassName, _, _, class, subclass = get(itemID)
  if type(class) ~= "number" then
    return nil
  end
  known = {
    class = class, subclass = type(subclass) == "number" and subclass or 0,
    className = type(className) == "string" and className ~= "" and className or ("Class " .. class),
    subclassName = type(subclassName) == "string" and subclassName ~= "" and subclassName or nil,
  }
  types[itemID] = known
  return known
end

local function anyFilter()
  return next(filters) ~= nil
end

-- "1g 50s" as a player types it, which ns.ParseMoney reads back.
local function plainMoney(copper)
  local parts = {}
  local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if gold > 0 then
    parts[#parts + 1] = gold .. "g"
  end
  if silver > 0 then
    parts[#parts + 1] = silver .. "s"
  end
  if rest > 0 or #parts == 0 then
    parts[#parts + 1] = rest .. "c"
  end
  return table.concat(parts, " ")
end

-- A deal: the latest price is at most the "deal" percentage of the average of at least two days.
local function isDeal(row)
  return row.days >= DEAL_MIN_DAYS and row.pct <= ns.GetOption("dealPercent")
end

local function getItemInfo(itemID)
  local get = C_Item.GetItemInfo
  if get then
    return get(itemID)
  end
end

-- Name and quality of an item if the client has them. Asking for an item that is not loaded makes the client load it,
-- and GET_ITEM_INFO_RECEIVED tells when it is there.
local function loadInfo(itemID)
  local known = info[itemID]
  if known then
    return known
  end
  local name, _, quality = getItemInfo(itemID)
  if type(name) == "string" and name ~= "" then
    known = { name = name, lower = name:lower(), quality = quality }
    info[itemID] = known
    pending[itemID] = nil
    return known
  end
  return nil
end

local function iconOf(itemID)
  local icon
  if C_Item and C_Item.GetItemIconByID then
    icon = C_Item.GetItemIconByID(itemID)
  end
  return icon or UNKNOWN_ICON
end

local function compare(a, b)
  local x, y
  if sortKey == "name" then
    local ia, ib = info[a.id], info[b.id]
    -- Items without a name yet go to the end.
    if (ia == nil) ~= (ib == nil) then
      return ia ~= nil
    end
    x, y = ia and ia.lower or a.id, ib and ib.lower or b.id
  else
    x, y = a[sortKey] or 0, b[sortKey] or 0
  end
  if x == y then
    return a.id < b.id
  end
  if sortDescending then
    return x > y
  end
  return x < y
end

local function matches(row)
  if dealsOnly and not isDeal(row) then
    return false
  end
  if filters.minPrice and row.price < filters.minPrice then
    return false
  end
  if filters.maxPrice and row.price > filters.maxPrice then
    return false
  end
  if filters.seenWithin and row.seen < time() - filters.seenWithin then
    return false
  end
  if filters.watched and not ns.WatchTarget(row.id) then
    return false
  end
  if filters.class then
    local kind = typeOf(row.id)
    if not kind or kind.class ~= filters.class or (filters.subclass and kind.subclass ~= filters.subclass) then
      return false
    end
  end
  if filters.quality then
    -- The quality is known once the client has loaded the item; until then the row waits.
    local known = info[row.id]
    if not (known and type(known.quality) == "number" and known.quality >= filters.quality) then
      return false
    end
  end
  if filter == "" then
    return true
  end
  local known = info[row.id]
  if known then
    return known.lower:find(filter, 1, true) ~= nil
  end
  return tostring(row.id) == filter
end

-- Filters and sorts the rows and hands them to the list. keepPosition keeps the scroll position.
local function rebuild(keepPosition)
  if not frame then
    return
  end
  shown = {}
  for _, row in ipairs(allRows) do
    if matches(row) then
      shown[#shown + 1] = row
    end
  end
  table.sort(shown, compare)
  list.SetItems(shown, keepPosition)
  if dealsOnly then
    countText:SetText(string.format("%d deals (at most %d%% of the average) among %d items", #shown, ns.GetOption("dealPercent"), #allRows))
  else
    countText:SetText(string.format("%d of %d items", #shown, #allRows))
  end
  if dealsButton then
    dealsButton:SetText(dealsOnly and "Show all items" or "Show deals only")
  end
  if filterText then
    filterText:SetText(ns.HistoryFilterSummary())
  end
  dirty = false
end

-- The active filters in words, or "".
function ns.HistoryFilterSummary()
  local parts = {}
  if filters.class then
    local name
    for _, kind in pairs(types) do
      if kind.class == filters.class and (not filters.subclass or kind.subclass == filters.subclass) then
        name = filters.subclass and kind.subclassName or kind.className
        break
      end
    end
    parts[#parts + 1] = name or "one item type"
  end
  if filters.quality then
    parts[#parts + 1] = qualityName(filters.quality) .. " or better"
  end
  if filters.seenWithin then
    for _, choice in ipairs(SEEN_CHOICES) do
      if choice[1] == filters.seenWithin then
        parts[#parts + 1] = "seen in " .. choice[2]
      end
    end
  end
  if filters.watched then
    parts[#parts + 1] = "with a price alert"
  end
  if #parts == 0 then
    return ""
  end
  return "Only: " .. table.concat(parts, ", ")
end

-- Sets one filter of the price window. Nil (or false for "watched") removes it.
function ns.SetHistoryFilter(key, value)
  local kind = FILTER_KEYS[key]
  if not kind then
    return
  end
  if type(value) ~= kind or value == false then
    value = nil
  end
  filters[key] = value
  if key == "class" then
    filters.subclass = nil
  end
  if key == "minPrice" or key == "maxPrice" then
    local box = key == "minPrice" and minBox or maxBox
    if box and ns.ParseMoney(box:GetText()) ~= value then
      box:SetText(value and plainMoney(value) or "")
    end
  end
  rebuild(false)
end

function ns.ClearHistoryFilters()
  wipe(filters)
  if minBox then
    minBox:SetText("")
    maxBox:SetText("")
  end
  rebuild(false)
end

-- The item IDs that the window shows now, in their order.
function ns.HistoryShown()
  local ids = {}
  for i, row in ipairs(shown) do
    ids[i] = row.id
  end
  return ids
end

local function updateHeaders()
  for _, header in ipairs(headers) do
    local active = header.column.key == sortKey
    header.arrow:SetShown(active)
    if active then
      if sortDescending then
        header.arrow:SetTexCoord(0, 0.5625, 0, 1)
      else
        header.arrow:SetTexCoord(0, 0.5625, 1, 0)
      end
    end
  end
end

-- Asks for the names of the queued items, a few per step, while the window is open.
local function loadStep()
  if not frame or not frame:IsShown() then
    loaderRunning = false
    return
  end
  local stop = math.min(queuePosition + LOAD_BATCH - 1, #queue)
  for i = queuePosition, stop do
    local itemID = queue[i]
    if loadInfo(itemID) then
      dirty = true
    else
      pending[itemID] = true
    end
  end
  queuePosition = stop + 1
  if queuePosition > #queue then
    loaderRunning = false
    return
  end
  C_Timer.After(LOAD_PAUSE, loadStep)
end

-- Reads the stored prices again and shows them.
local function reload()
  if not frame or not ForeverAuctionsDB then
    return
  end
  allRows = {}
  queue, queuePosition = {}, 1
  for itemID, entry in pairs(ns.Prices()) do
    if type(itemID) == "number" and type(entry) == "table" and type(entry.price) == "number" then
      local low, high, average, days = ns.DayStats(entry)
      allRows[#allRows + 1] = {
        id = itemID, price = entry.price, seen = entry.seen or 0, low = low, high = high, avg = average,
        days = days,
        pct = average > 0 and math.floor(entry.price / average * 100 + 0.5) or 100,
        profit = ns.GetOption("craftCost") and ns.CraftProfit(itemID) or nil,
      }
      if not info[itemID] then
        queue[#queue + 1] = itemID
      end
    end
  end
  rebuild(false)
  if #queue > 0 and not loaderRunning and C_Timer and C_Timer.After then
    loaderRunning = true
    loadStep()
  end
end

-- Right-click on a row: search for the item, save it as a search, or set a price alert.
local function showRowMenu(owner, item)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    return
  end
  local known = info[item.id]
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(known and known.name or ("Item " .. item.id))
    if known then
      root:CreateButton("Search at the auction house", function()
        ns.RunSearch(known.name)
      end)
      root:CreateButton("Add to the shopping list", function()
        local ok, problem = ns.AddSearch(known.name)
        ns.Print(ok and ("\"" .. known.name .. "\" added to the shopping list.") or problem)
      end)
    end
    local target = ns.WatchTarget(item.id)
    if target then
      root:CreateButton("Remove the price alert (" .. ns.Money(target) .. ")", function()
        ns.SetWatch(item.id, nil)
        ns.Print("price alert removed.")
      end)
    else
      -- Below the price of now, so the alert does not fire at once.
      local below = math.max(1, math.floor(item.price * 0.9))
      root:CreateButton("Alert at " .. ns.Money(below) .. " or lower (10% below now)", function()
        ns.SetWatch(item.id, below)
        ns.Print("price alert set at " .. ns.Money(below) .. ". For a different price: /fah watch [item link] 5g.")
      end)
    end
  end)
end

-- The classes and subclasses of the stored items, sorted by name: { { class, name, subs = { { subclass, name } } } }.
local function storedTypes()
  local classes, byClass = {}, {}
  for _, row in ipairs(allRows) do
    local kind = typeOf(row.id)
    if kind then
      local entry = byClass[kind.class]
      if not entry then
        entry = { class = kind.class, name = kind.className, subs = {}, seen = {} }
        byClass[kind.class] = entry
        classes[#classes + 1] = entry
      end
      if kind.subclassName and not entry.seen[kind.subclass] then
        entry.seen[kind.subclass] = true
        entry.subs[#entry.subs + 1] = { subclass = kind.subclass, name = kind.subclassName }
      end
    end
  end
  local function byName(a, b)
    return a.name < b.name
  end
  table.sort(classes, byName)
  for _, entry in ipairs(classes) do
    table.sort(entry.subs, byName)
  end
  return classes
end

-- The Filters button: item type, quality, age and price alerts. The price range is in the boxes below.
function showFilterMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    ns.Print("this game client has no menus for addons. The price boxes still filter.")
    return
  end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Item type")
    root:CreateRadio("All types", function()
      return filters.class == nil
    end, function()
      ns.SetHistoryFilter("class", nil)
    end)
    for _, entry in ipairs(storedTypes()) do
      local classRadio = root:CreateRadio(entry.name, function()
        return filters.class == entry.class
      end, function()
        ns.SetHistoryFilter("class", entry.class)
      end)
      if #entry.subs > 1 then
        classRadio:CreateRadio("All " .. entry.name, function()
          return filters.class == entry.class and filters.subclass == nil
        end, function()
          ns.SetHistoryFilter("class", entry.class)
        end)
        for _, sub in ipairs(entry.subs) do
          classRadio:CreateRadio(sub.name, function()
            return filters.class == entry.class and filters.subclass == sub.subclass
          end, function()
            ns.SetHistoryFilter("class", entry.class)
            ns.SetHistoryFilter("subclass", sub.subclass)
          end)
        end
      end
    end
    root:CreateDivider()
    local quality = root:CreateButton("Quality")
    quality:CreateRadio("Any quality", function()
      return filters.quality == nil
    end, function()
      ns.SetHistoryFilter("quality", nil)
    end)
    for _, q in ipairs(QUALITIES) do
      quality:CreateRadio(qualityName(q) .. (q < 5 and " or better" or ""), function()
        return filters.quality == q
      end, function()
        ns.SetHistoryFilter("quality", q)
      end)
    end
    local seen = root:CreateButton("Last seen")
    seen:CreateRadio("Any time", function()
      return filters.seenWithin == nil
    end, function()
      ns.SetHistoryFilter("seenWithin", nil)
    end)
    for _, choice in ipairs(SEEN_CHOICES) do
      seen:CreateRadio("In " .. choice[2], function()
        return filters.seenWithin == choice[1]
      end, function()
        ns.SetHistoryFilter("seenWithin", choice[1])
      end)
    end
    root:CreateCheckbox("Only items with a price alert", function()
      return filters.watched == true
    end, function()
      ns.SetHistoryFilter("watched", not filters.watched)
    end)
    root:CreateDivider()
    root:CreateButton("Clear all filters", function()
      ns.ClearHistoryFilters()
    end)
  end)
end

local function createRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(ROW_HEIGHT)
  row:EnableMouse(true)

  row.highlight = row:CreateTexture(nil, "BACKGROUND")
  row.highlight:SetAllPoints()
  row.highlight:SetColorTexture(1, 1, 1, 0.08)
  row.highlight:Hide()

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
  row.icon:SetPoint("LEFT", 4, 0)

  -- The value columns are laid out from the right edge, the name takes the rest.
  local right = -4
  for i = #COLUMNS, 2, -1 do
    local column = COLUMNS[i]
    local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("RIGHT", row, "RIGHT", right, 0)
    text:SetWidth(column.width - 6)
    text:SetJustifyH("RIGHT")
    text:SetWordWrap(false)
    row[column.key] = text
    right = right - column.width
  end

  row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetPoint("RIGHT", row, "RIGHT", right - 4, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  row:SetScript("OnEnter", function(self)
    self.highlight:Show()
    if self.itemID then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink("item:" .. self.itemID)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.highlight:Hide()
    GameTooltip:Hide()
  end)
  row:SetScript("OnMouseUp", function(self, mouseButton)
    if mouseButton == "RightButton" and self.item then
      showRowMenu(self, self.item)
    end
  end)
  return row
end

local function setupRow(row, item)
  row.itemID = item.id
  row.item = item
  if item.days >= DEAL_MIN_DAYS then
    row.pct:SetText(item.pct .. "%")
    if isDeal(item) then
      row.pct:SetTextColor(0.3, 0.9, 0.3)
    elseif item.pct > 100 then
      row.pct:SetTextColor(0.9, 0.5, 0.4)
    else
      row.pct:SetTextColor(1, 1, 1)
    end
  else
    row.pct:SetText("-")
    row.pct:SetTextColor(0.6, 0.6, 0.6)
  end
  row.icon:SetTexture(iconOf(item.id))
  local known = info[item.id]
  if known then
    row.name:SetText(known.name)
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[known.quality or 1]
    if color and color.r then
      row.name:SetTextColor(color.r, color.g, color.b)
    else
      row.name:SetTextColor(1, 1, 1)
    end
  else
    row.name:SetText("Item " .. item.id)
    row.name:SetTextColor(0.6, 0.6, 0.6)
  end
  row.price:SetText(ns.Money(item.price))
  row.seen:SetText(ns.Age(item.seen))
  row.low:SetText(ns.Money(item.low))
  row.high:SetText(ns.Money(item.high))
  row.avg:SetText(ns.Money(item.avg))
  if item.profit then
    row.profit:SetText((item.profit < 0 and "-" or "") .. ns.Money(math.abs(item.profit)))
    row.profit:SetTextColor(item.profit >= 0 and 0.3 or 0.9, item.profit >= 0 and 0.9 or 0.4, 0.3)
  else
    row.profit:SetText("-")
    row.profit:SetTextColor(0.6, 0.6, 0.6)
  end
end

-- The game's scroll box draws only the rows in view and reuses their frames. Nil if this client lacks a part of it.
local function createScrollBoxList(parent)
  if not (ScrollUtil and ScrollUtil.InitScrollBoxListWithScrollBar and CreateScrollBoxListLinearView and CreateDataProvider) then
    return nil
  end
  local okBox, box = pcall(CreateFrame, "Frame", nil, parent, "WowScrollBoxList")
  if not okBox then
    return nil
  end
  local okBar, bar = pcall(CreateFrame, "EventFrame", nil, parent, "MinimalScrollBar")
  if not okBar then
    box:Hide()
    return nil
  end
  box:SetPoint("TOPLEFT")
  box:SetPoint("BOTTOMRIGHT", -SCROLL_GUTTER, 0)
  bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)

  local okView = pcall(function()
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtentCalculator(function()
      return ROW_HEIGHT
    end)
    view:SetElementFactory(function(factory)
      factory("Frame", function(holder, item)
        if not holder.row then
          holder.row = createRow(holder)
          holder.row:SetAllPoints()
        end
        setupRow(holder.row, item)
      end)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  end)
  if not okView then
    box:Hide()
    bar:Hide()
    return nil
  end

  local scrollList = {}
  function scrollList.SetItems(items, keepPosition)
    local retain = keepPosition and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or nil
    box:SetDataProvider(CreateDataProvider(items), retain)
  end
  function scrollList.Render()
    box:ForEachFrame(function(holder, item)
      if holder.row then
        setupRow(holder.row, item)
      end
    end)
  end
  return scrollList
end

-- Replacement without the scroll box: a fixed set of rows that show a part of the list, moved with the mouse wheel.
local function createPlainList(parent)
  local visible = math.floor(LIST_HEIGHT / ROW_HEIGHT)
  local rows, items, offset = {}, {}, 0
  local plainList = {}

  function plainList.Render()
    offset = math.max(0, math.min(offset, #items - visible))
    for i = 1, visible do
      local row = rows[i]
      if not row then
        row = createRow(parent)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", parent, "RIGHT", -SCROLL_GUTTER, 0)
        rows[i] = row
      end
      local item = items[offset + i]
      if item then
        setupRow(row, item)
        row:Show()
      else
        row:Hide()
      end
    end
  end
  function plainList.SetItems(newItems, keepPosition)
    items = newItems
    if not keepPosition then
      offset = 0
    end
    plainList.Render()
  end

  parent:EnableMouseWheel(true)
  parent:SetScript("OnMouseWheel", function(_, delta)
    offset = offset - delta * 3
    plainList.Render()
  end)
  return plainList
end

local function savePosition()
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  if point and ForeverAuctionsDB then
    ForeverAuctionsDB.options.window = { point = point, relativePoint = relativePoint, x = x, y = y }
  end
end

local function restorePosition()
  local saved = ForeverAuctionsDB and ForeverAuctionsDB.options.window
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
function ns.ResetHistoryPosition()
  ForeverAuctionsDB.options.window = nil
  if frame then
    restorePosition()
  end
end

local function createHeader(parent, column)
  local header = CreateFrame("Button", nil, parent)
  header.column = column
  header:SetHeight(20)
  header.text = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  header.text:SetText(column.label)
  header.arrow = header:CreateTexture(nil, "ARTWORK")
  header.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
  header.arrow:SetSize(9, 8)
  header.arrow:Hide()
  if column.key == "name" then
    header.text:SetPoint("LEFT", 4, 0)
    header.arrow:SetPoint("LEFT", header.text, "RIGHT", 3, 0)
  else
    header.text:SetPoint("RIGHT")
    header.arrow:SetPoint("RIGHT", header.text, "LEFT", -3, 0)
  end
  header:SetScript("OnClick", function()
    if sortKey == column.key then
      sortDescending = not sortDescending
    else
      sortKey, sortDescending = column.key, column.descending
    end
    updateHeaders()
    rebuild(false)
  end)
  return header
end

local function createWindow()
  local ok, window = pcall(CreateFrame, "Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
  if not ok then
    -- Plain window where the template is missing.
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
  frame.TitleText:SetText("Forever Auctions: price history")
  -- Escape closes the window.
  tinsert(UISpecialFrames, FRAME_NAME)

  -- The template has an inset frame over its inside. Everything of ours goes on a frame above that.
  local content = CreateFrame("Frame", nil, frame)
  content:SetAllPoints()
  content:SetFrameLevel(frame:GetFrameLevel() + 10)

  local okSearch, box = pcall(CreateFrame, "EditBox", nil, content, "SearchBoxTemplate")
  if not okSearch then
    box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
  end
  searchBox = box
  searchBox:SetSize(220, 20)
  searchBox:SetPoint("TOPLEFT", 18, -34)
  searchBox:SetAutoFocus(false)
  if searchBox.Instructions then
    searchBox.Instructions:SetText("Search by name")
  end
  searchBox:HookScript("OnTextChanged", function(self)
    local text = (self:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text ~= filter then
      filter = text
      rebuild(false)
    end
  end)
  searchBox:HookScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)

  dealsButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  dealsButton:SetSize(150, 22)
  dealsButton:SetPoint("LEFT", searchBox, "RIGHT", 12, 0)
  dealsButton:SetText("Show deals only")
  dealsButton:SetScript("OnClick", function()
    dealsOnly = not dealsOnly
    rebuild(false)
  end)
  dealsButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Deals", 1, 1, 1)
    GameTooltip:AddLine(string.format("Items whose latest price is at most %d%% of their average, with prices of at least %d days. Change the percentage in the settings. Right-click a row for more actions.",
      ns.GetOption("dealPercent"), DEAL_MIN_DAYS), nil, nil, nil, true)
    GameTooltip:Show()
  end)
  dealsButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  local filterButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  filterButton:SetSize(100, 22)
  filterButton:SetPoint("LEFT", dealsButton, "RIGHT", 8, 0)
  filterButton:SetText("Filters")
  filterButton:SetScript("OnClick", function(self)
    showFilterMenu(self)
  end)

  local clearButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  clearButton:SetSize(110, 22)
  clearButton:SetPoint("LEFT", filterButton, "RIGHT", 8, 0)
  clearButton:SetText("Clear filters")
  clearButton:SetScript("OnClick", function()
    ns.ClearHistoryFilters()
  end)

  -- Second line: the price range, and the other filters in words.
  local priceLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  priceLabel:SetPoint("TOPLEFT", 18, -66)
  priceLabel:SetText("Price from")
  local function priceBox(key)
    local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    box:SetSize(80, 20)
    box:SetAutoFocus(false)
    box:SetMaxLetters(20)
    box:HookScript("OnTextChanged", function(self)
      local text = self:GetText() or ""
      local value = ns.ParseMoney(text)
      if text:gsub("%s", "") ~= "" and not value then
        self:SetTextColor(1, 0.3, 0.3) -- not a price: the filter stays as it was
        return
      end
      self:SetTextColor(1, 1, 1)
      if value ~= filters[key] then
        ns.SetHistoryFilter(key, value)
      end
    end)
    box:HookScript("OnEscapePressed", function(self)
      self:ClearFocus()
    end)
    box:HookScript("OnEnterPressed", function(self)
      self:ClearFocus()
    end)
    box:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(key == "minPrice" and "Lowest price" or "Highest price", 1, 1, 1)
      GameTooltip:AddLine("For example 50s, 1g 20s or 5g. Empty: no limit.", nil, nil, nil, true)
      GameTooltip:Show()
    end)
    box:HookScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    return box
  end
  minBox = priceBox("minPrice")
  minBox:SetPoint("LEFT", priceLabel, "RIGHT", 12, 0)
  local toLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  toLabel:SetPoint("LEFT", minBox, "RIGHT", 6, 0)
  toLabel:SetText("to")
  maxBox = priceBox("maxPrice")
  maxBox:SetPoint("LEFT", toLabel, "RIGHT", 12, 0)

  filterText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  filterText:SetPoint("LEFT", maxBox, "RIGHT", 16, 0)
  filterText:SetPoint("RIGHT", content, "RIGHT", -18, 0)
  filterText:SetJustifyH("LEFT")
  filterText:SetWordWrap(false)

  countText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  countText:SetPoint("BOTTOMLEFT", 16, 10)

  local realm = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  realm:SetPoint("BOTTOMRIGHT", -16, 10)
  realm:SetText(ns.RealmName() .. ", " .. (UnitFactionGroup("player") or "Neutral"))

  local listArea = CreateFrame("Frame", nil, content)
  listArea:SetPoint("TOPLEFT", 12, -LIST_TOP)
  listArea:SetPoint("BOTTOMRIGHT", -10, LIST_BOTTOM)

  -- Headers above the columns, laid out like the rows.
  local right = -4 - SCROLL_GUTTER
  for i = #COLUMNS, 2, -1 do
    local column = COLUMNS[i]
    local header = createHeader(content, column)
    header:SetWidth(column.width)
    header:SetPoint("BOTTOMRIGHT", listArea, "TOPRIGHT", right, 2)
    headers[#headers + 1] = header
    right = right - column.width
  end
  local nameHeader = createHeader(content, COLUMNS[1])
  nameHeader:SetPoint("BOTTOMLEFT", listArea, "TOPLEFT", ROW_HEIGHT + 2, 2)
  nameHeader:SetPoint("BOTTOMRIGHT", listArea, "TOPRIGHT", right, 2)
  headers[#headers + 1] = nameHeader

  list = createScrollBoxList(listArea) or createPlainList(listArea)

  local events = CreateFrame("Frame", nil, frame)
  ns.SafeRegister(events, "GET_ITEM_INFO_RECEIVED")
  events:SetScript("OnEvent", function(_, _, itemID)
    if pending[itemID] and loadInfo(itemID) then
      dirty = true
    end
  end)

  -- Names arrive one by one: the list is redrawn at most twice a second.
  local elapsed = 0
  frame:SetScript("OnUpdate", function(_, seconds)
    elapsed = elapsed + seconds
    if elapsed < 0.5 then
      return
    end
    elapsed = 0
    if not dirty then
      return
    end
    if sortKey == "name" or filter ~= "" or filters.quality then
      rebuild(true)
    else
      dirty = false
      list.Render()
    end
  end)
  frame:SetScript("OnShow", reload)

  restorePosition()
  updateHeaders()
end

function ns.ShowHistory()
  if not ForeverAuctionsDB then
    return
  end
  if not frame then
    local ok, problem = pcall(createWindow)
    if not ok then
      frame = nil
      ns.Print("the price history window could not be made: " .. tostring(problem))
      return
    end
  end
  frame:Show()
  if frame.Raise then
    frame:Raise()
  end
end

-- Opens the window with only the deals, the lowest percentage of the average first.
function ns.ShowDeals()
  dealsOnly = true
  sortKey, sortDescending = "pct", false
  local wasShown = frame and frame:IsShown()
  ns.ShowHistory()
  if frame then
    updateHeaders()
    if wasShown then
      rebuild(false) -- a window that opens now reads the prices itself
    end
  end
end

ns.OnOptionChanged(function(key)
  if key == "dealPercent" and frame and frame:IsShown() then
    rebuild(true)
  end
end)

function ns.ToggleHistory()
  if frame and frame:IsShown() then
    frame:Hide()
  else
    ns.ShowHistory()
  end
end

-- Called when the stored prices changed a lot (full scan, clear).
function ns.RefreshHistory()
  if frame and frame:IsShown() then
    reload()
  end
end
