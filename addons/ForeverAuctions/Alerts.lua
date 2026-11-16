local _, ns = ...

-- Price alerts: the player gives an item a target price. When a search or a full scan sees the item
-- at that price or lower, the addon says so in chat, once per price and play session.
-- Alerts are per realm and faction, like the prices.

local alerted = {} -- [itemID] = the price of the last message
local queue = {}
local flushing = false

function ns.WatchList()
  return ns.Realm().watch
end

-- The target price of an item, or nil.
function ns.WatchTarget(itemID)
  local target = ForeverAuctionsDB and ns.WatchList()[itemID]
  return type(target) == "number" and target or nil
end

-- Sets the target price of an item. Nil or 0 removes the alert.
function ns.SetWatch(itemID, copper)
  if type(itemID) ~= "number" then
    return
  end
  if type(copper) ~= "number" or copper <= 0 then
    copper = nil
  end
  ns.WatchList()[itemID] = copper
  alerted[itemID] = nil
  if copper then
    -- A stored price can be low enough already.
    local entry = ns.Lookup(itemID)
    if entry then
      ns.CheckAlert(itemID, entry.price)
    end
  end
end

function ns.ClearWatchList()
  wipe(ns.WatchList())
  wipe(alerted)
end

function ns.CountWatches()
  local count = 0
  for _ in pairs(ns.WatchList()) do
    count = count + 1
  end
  return count
end

local function flush()
  flushing = false
  if #queue == 0 then
    return
  end
  for _, alert in ipairs(queue) do
    ns.Print(string.format("price alert: %s is at %s (your target: %s).",
      ns.ItemLabel(alert.itemID), ns.Money(alert.price), ns.Money(alert.target)))
  end
  queue = {}
  if PlaySound then
    PlaySound((SOUNDKIT and SOUNDKIT.AUCTION_WINDOW_OPEN) or 5274)
  end
end

function ns.CheckAlert(itemID, price)
  if not ns.GetOption("priceAlerts") then
    return
  end
  local target = ns.WatchTarget(itemID)
  if not target or price > target or alerted[itemID] == price then
    return
  end
  alerted[itemID] = price
  queue[#queue + 1] = { itemID = itemID, price = price, target = target }
  -- A full scan stores thousands of prices: the messages come together, after it.
  if not flushing then
    flushing = true
    C_Timer.After(1, flush)
  end
end

ns.OnRecord(ns.CheckAlert)

-- /fah watch: the list of alerts in chat.
function ns.PrintWatchList()
  local ids = {}
  for itemID in pairs(ns.WatchList()) do
    ids[#ids + 1] = itemID
  end
  if #ids == 0 then
    ns.Print("no price alerts. Add one with /fah watch [item link] 5g.")
    return
  end
  table.sort(ids)
  ns.Print("price alerts of this realm and faction:")
  for _, itemID in ipairs(ids) do
    local entry = ns.Lookup(itemID)
    print(string.format("  %s at %s or lower. %s", ns.ItemLabel(itemID), ns.Money(ns.WatchTarget(itemID)),
      entry and ("Last seen at " .. ns.Money(entry.price) .. ", " .. ns.Age(entry.seen) .. ".") or "No price stored yet."))
  end
end
