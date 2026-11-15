local _, ns = ...

-- Price history window: every stored item of this realm and faction with its latest price, its age and the low,
-- high and average of the stored daily lows.

local FRAME_NAME = "ForeverAuctionsHistoryFrame"
local WIDTH, HEIGHT = 820, 500
local ROW_HEIGHT = 20
local LIST_TOP = 86 -- from the top of the window to the first row
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
}

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

local function getItemInfo(itemID)
  local get = C_Item and C_Item.GetItemInfo or GetItemInfo
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
  elseif GetItemIcon then
    icon = GetItemIcon(itemID)
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
  countText:SetText(string.format("%d of %d items", #shown, #allRows))
  dirty = false
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
      local low, high, average = ns.DayStats(entry)
      allRows[#allRows + 1] = {
        id = itemID, price = entry.price, seen = entry.seen or 0, low = low, high = high, avg = average,
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
  return row
end

local function setupRow(row, item)
  row.itemID = item.id
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
  if frame.TitleText then
    frame.TitleText:SetText("Forever Auctions: price history")
  elseif frame.SetTitle then
    frame:SetTitle("Forever Auctions: price history")
  end
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

  countText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  countText:SetPoint("BOTTOMLEFT", 16, 10)

  local realm = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  realm:SetPoint("BOTTOMRIGHT", -16, 10)
  realm:SetText((GetRealmName() or "") .. ", " .. (UnitFactionGroup("player") or "Neutral"))

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
    if sortKey == "name" or filter ~= "" then
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
