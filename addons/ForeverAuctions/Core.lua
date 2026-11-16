local _, ns = ...

local DAY = 86400

-- Options and their defaults. A saved option of the wrong type gets its default again.
ns.DEFAULTS = {
  tooltip = true, -- auction price and average
  tooltipVendor = true, -- vendor sell price
  tooltipStack = true, -- auction value of the stack
  tooltipStackVendor = true, -- vendor value of the stack
  undercut = 1, -- copper below the lowest price, for the posting helper
  sellHelper = true, -- the price helper on the sell tab of the auction house
  scanButton = true, -- the full scan button on the auction house window
  historyDays = 14, -- days of daily lows kept for each item
  shoppingPanel = true, -- the shopping list beside the auction house window
  undercutCheck = true, -- a message when your auctions are no longer the lowest
  priceAlerts = true, -- a message when a watched item is seen at or below its target price
  dealPercent = 70, -- an item is a deal at this percentage of its average price, or lower
  ledger = true, -- record sales and purchases from the auction house mail
  ledgerDays = 60, -- days that the ledger keeps a sale or a purchase
}

-- Lowest and highest value of the number options that have a range.
ns.LIMITS = {
  historyDays = { 3, 30 },
  dealPercent = { 10, 95 },
  ledgerDays = { 7, 365 },
}

local optionListeners = {}
local readyCallbacks = {}
local recordListeners = {}

-- The function is called with the item ID and the price each time a price is stored.
function ns.OnRecord(listener)
  recordListeners[#recordListeners + 1] = listener
end

local MONEY_UNITS = { g = 10000, s = 100, c = 1 }

-- "5g", "1g 50s", "20s5c" or a number of copper. Nil for other text.
function ns.ParseMoney(text)
  text = ((text or ""):lower():gsub("%s+", ""))
  if text:match("^%d+$") then
    return tonumber(text)
  end
  if text == "" or (text:gsub("%d+[gsc]", "")) ~= "" then
    return nil
  end
  local total = 0
  for amount, unit in text:gmatch("(%d+)([gsc])") do
    total = total + tonumber(amount) * MONEY_UNITS[unit]
  end
  return total
end

-- The link of an item for chat, or "item 1234" while the client does not know the item yet.
function ns.ItemLabel(itemID)
  local get = C_Item and C_Item.GetItemInfo or GetItemInfo
  local link = get and select(2, get(itemID))
  return type(link) == "string" and link or ("item " .. tostring(itemID))
end

function ns.Print(msg)
  print("|cffd8a657Forever Auctions|r: " .. tostring(msg))
end

function ns.GetOption(key)
  local options = ForeverAuctionsDB and ForeverAuctionsDB.options
  local value = options and options[key]
  if value == nil then
    return ns.DEFAULTS[key]
  end
  return value
end

-- Every change of an option goes through here, so the settings page and the slash commands stay in sync.
function ns.SetOption(key, value)
  if not ForeverAuctionsDB then
    return
  end
  local default = ns.DEFAULTS[key]
  if type(default) == "number" then
    local limit = ns.LIMITS[key]
    value = math.max(0, math.floor((tonumber(value) or default) + 0.5))
    if limit then
      value = math.max(limit[1], math.min(limit[2], value))
    end
  elseif type(default) == "boolean" then
    value = value and true or false
  end
  ForeverAuctionsDB.options[key] = value
  for _, listener in ipairs(optionListeners) do
    listener(key, value)
  end
end

function ns.OnOptionChanged(listener)
  optionListeners[#optionListeners + 1] = listener
end

-- Runs callback once the saved variables are loaded.
function ns.OnReady(callback)
  readyCallbacks[#readyCallbacks + 1] = callback
end

local function realmKey()
  local faction = UnitFactionGroup("player") or "Neutral"
  return (GetRealmName() or "Unknown") .. "-" .. faction
end

-- The data of the current realm and faction: prices and price alerts.
function ns.Realm()
  local key = realmKey()
  local realm = ForeverAuctionsDB.realms[key]
  if type(realm) ~= "table" then
    realm = {}
    ForeverAuctionsDB.realms[key] = realm
  end
  if type(realm.prices) ~= "table" then
    realm.prices = {}
  end
  if type(realm.watch) ~= "table" then
    realm.watch = {} -- [itemID] = target price in copper
  end
  if type(realm.ledger) ~= "table" then
    realm.ledger = {} -- sales and purchases, the oldest first (Ledger.lua)
  end
  if type(realm.ledgerSeen) ~= "table" then
    realm.ledgerSeen = {} -- the mails that are in the ledger already
  end
  return realm
end

-- Price table of the current realm and faction: [itemID] = entry.
function ns.Prices()
  return ns.Realm().prices
end

-- Stores the lowest unit price seen for an item.
-- entry = { price = latest lowest price, seen = time(), days = { [dayNumber] = lowest price that day } }
function ns.Record(itemID, price)
  if type(itemID) ~= "number" or type(price) ~= "number" or price <= 0 then
    return
  end
  local now = time()
  local day = math.floor(now / DAY)
  local prices = ns.Prices()
  local entry = prices[itemID]
  if not entry then
    entry = { days = {} }
    prices[itemID] = entry
  end
  if type(entry.days) ~= "table" then
    entry.days = {}
  end
  entry.price = price
  entry.seen = now
  local low = entry.days[day]
  if not low or price < low then
    entry.days[day] = price
  end
  for d in pairs(entry.days) do
    if d < day - ns.GetOption("historyDays") then
      entry.days[d] = nil
    end
  end
  for _, listener in ipairs(recordListeners) do
    listener(itemID, price)
  end
end

-- Low, high, average and number of the stored daily lows of an entry. Without daily lows all three are the latest price.
function ns.DayStats(entry)
  local low, high, sum, count = nil, nil, 0, 0
  if type(entry.days) == "table" then
    for _, price in pairs(entry.days) do
      if type(price) == "number" then
        low = (not low or price < low) and price or low
        high = (not high or price > high) and price or high
        sum = sum + price
        count = count + 1
      end
    end
  end
  if count == 0 then
    return entry.price, entry.price, entry.price, 0
  end
  return low, high, math.floor(sum / count + 0.5), count
end

-- Returns the entry and the average of the daily lows, or nil.
function ns.Lookup(itemID)
  local entry = ns.Prices()[itemID]
  if not entry or not entry.price then
    return nil
  end
  local _, _, average, count = ns.DayStats(entry)
  return entry, average, count
end

function ns.Money(copper)
  if GetMoneyString then
    return GetMoneyString(copper, true)
  end
  return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

function ns.Age(timestamp)
  local seconds = math.max(0, time() - (timestamp or 0))
  if seconds < 3600 then
    return string.format("%dm ago", math.floor(seconds / 60))
  elseif seconds < DAY then
    return string.format("%dh ago", math.floor(seconds / 3600))
  end
  return string.format("%dd ago", math.floor(seconds / DAY))
end

-- Registers an event only if this client knows it.
function ns.SafeRegister(frame, event)
  return pcall(frame.RegisterEvent, frame, event)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name ~= "ForeverAuctions" then
    return
  end
  self:UnregisterEvent("ADDON_LOADED")
  ForeverAuctionsDB = ForeverAuctionsDB or {}
  local db = ForeverAuctionsDB
  db.version = 1
  db.realms = db.realms or {}
  if type(db.options) ~= "table" then
    db.options = {}
  end
  for key, default in pairs(ns.DEFAULTS) do
    if type(db.options[key]) ~= type(default) then
      db.options[key] = default
    end
  end
  db.options.undercut = math.max(0, math.floor(db.options.undercut + 0.5))
  local days = ns.LIMITS.historyDays
  db.options.historyDays = math.max(days[1], math.min(days[2], math.floor(db.options.historyDays + 0.5)))
  for key, limit in pairs(ns.LIMITS) do
    db.options[key] = math.max(limit[1], math.min(limit[2], math.floor(db.options[key] + 0.5)))
  end
  -- The shopping list: saved search texts, for all characters.
  if type(db.shopping) ~= "table" then
    db.shopping = {}
  end
  -- Time of the last full scan request. The server's limit is per account, so this is not per realm.
  if type(db.scan) ~= "table" then
    db.scan = {}
  end
  for _, callback in ipairs(readyCallbacks) do
    callback()
  end
end)
