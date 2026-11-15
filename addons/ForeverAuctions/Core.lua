local _, ns = ...

ns.HISTORY_DAYS = 14

local DAY = 86400

-- Options and their defaults. A saved option of the wrong type gets its default again.
ns.DEFAULTS = {
  tooltip = true, -- auction price and average
  tooltipVendor = true, -- vendor sell price
  tooltipStack = true, -- auction value of the stack
  tooltipStackVendor = true, -- vendor value of the stack
  undercut = 1, -- copper below the lowest price, for the posting helper
}

local optionListeners = {}
local readyCallbacks = {}

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
  if key == "undercut" then
    value = math.max(0, math.floor((tonumber(value) or ns.DEFAULTS.undercut) + 0.5))
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

-- Price table of the current realm and faction: [itemID] = entry.
function ns.Prices()
  local key = realmKey()
  local realm = ForeverAuctionsDB.realms[key]
  if not realm then
    realm = { prices = {} }
    ForeverAuctionsDB.realms[key] = realm
  end
  return realm.prices
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
    if d < day - ns.HISTORY_DAYS then
      entry.days[d] = nil
    end
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
  if GetCoinTextureString then
    return GetCoinTextureString(copper)
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
  -- Time of the last full scan request. The server's limit is per account, so this is not per realm.
  if type(db.scan) ~= "table" then
    db.scan = {}
  end
  for _, callback in ipairs(readyCallbacks) do
    callback()
  end
end)
