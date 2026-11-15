local _, ns = ...

ns.HISTORY_DAYS = 14

local DAY = 86400

function ns.Print(msg)
  print("|cffd8a657Forever Auctions|r: " .. tostring(msg))
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

-- Returns the entry and the average of the daily lows, or nil.
function ns.Lookup(itemID)
  local entry = ns.Prices()[itemID]
  if not entry or not entry.price then
    return nil
  end
  local sum, count = 0, 0
  for _, low in pairs(entry.days) do
    sum = sum + low
    count = count + 1
  end
  local average = count > 0 and math.floor(sum / count + 0.5) or entry.price
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
  local seconds = math.max(0, time() - timestamp)
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
  db.options = db.options or {}
  if db.options.tooltip == nil then
    db.options.tooltip = true
  end
end)
