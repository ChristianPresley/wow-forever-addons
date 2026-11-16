local _, ns = ...

-- /fah bags: what the items in the bags are worth at the auction house and at a vendor.

local SELL_PRICE_INDEX = 11 -- position of the vendor sell price in the results of GetItemInfo
local TOP = 5

local function vendorPrice(itemID)
  local get = C_Item.GetItemInfo
  local price = get and select(SELL_PRICE_INDEX, get(itemID))
  if type(price) ~= "number" or (issecretvalue and issecretvalue(price)) or price <= 0 then
    return 0
  end
  return price
end

-- Returns the auction total, the vendor total, and a list of { itemID, count, value } for the
-- items with an auction price, the most valuable first. Nil if this client has no bag API.
function ns.BagValue()
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
    return nil
  end
  local lastBag = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
  local auction, vendor = 0, 0
  local byItem = {}
  for bag = 0, lastBag do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local itemID = info and info.itemID
      if type(itemID) == "number" then
        local count = type(info.stackCount) == "number" and info.stackCount or 1
        if not info.hasNoValue then
          vendor = vendor + vendorPrice(itemID) * count
        end
        -- A bound item cannot go to the auction house.
        local entry = not info.isBound and ns.Lookup(itemID)
        if entry then
          auction = auction + entry.price * count
          local item = byItem[itemID]
          if not item then
            item = { itemID = itemID, count = 0, value = 0 }
            byItem[itemID] = item
          end
          item.count = item.count + count
          item.value = item.value + entry.price * count
        end
      end
    end
  end
  local items = {}
  for _, item in pairs(byItem) do
    items[#items + 1] = item
  end
  table.sort(items, function(a, b)
    if a.value ~= b.value then
      return a.value > b.value
    end
    return a.itemID < b.itemID
  end)
  return auction, vendor, items
end

function ns.PrintBagValue()
  local ok, auction, vendor, items = pcall(ns.BagValue)
  if not ok or not auction then
    ns.Print("the bags cannot be read on this game client.")
    return
  end
  ns.Print(string.format("your bags: %s at the auction house (%d kinds of items with a stored price), %s at a vendor.",
    ns.Money(auction), #items, ns.Money(vendor)))
  for i = 1, math.min(TOP, #items) do
    local item = items[i]
    print(string.format("  %s x%d: %s", ns.ItemLabel(item.itemID), item.count, ns.Money(item.value)))
  end
  if #items == 0 then
    print("  No item in your bags has a stored auction price. Search for items or run a full scan first.")
  end
end
