local _, ns = ...

local SELL_PRICE_INDEX = 11 -- position of the vendor sell price in the results of GetItemInfo

local function isSecret(value)
  return issecretvalue and issecretvalue(value) or false
end

-- What a vendor pays for one item, nil if nothing or not known yet.
local function vendorPrice(itemID)
  local getInfo = C_Item.GetItemInfo
  if not getInfo then
    return nil
  end
  local price = select(SELL_PRICE_INDEX, getInfo(itemID))
  if type(price) ~= "number" or isSecret(price) or price <= 0 then
    return nil
  end
  return price
end

-- Size of the stack the tooltip is for. Only known for bag and bank slots, whose buttons have GetBagID. Else 1.
local function readStack(tooltip, itemID)
  local owner = tooltip:GetOwner()
  local bag = owner and owner.GetBagID and owner:GetBagID()
  if not bag or not ItemLocation or not C_Item or not C_Item.GetStackCount then
    return 1
  end
  local location = ItemLocation:CreateFromBagAndSlot(bag, owner:GetID())
  if not C_Item.DoesItemExist(location) or C_Item.GetItemID(location) ~= itemID then
    return 1
  end
  return C_Item.GetStackCount(location)
end

local function stackCount(tooltip, itemID)
  local ok, count = pcall(readStack, tooltip, itemID)
  if not ok or type(count) ~= "number" or isSecret(count) or count < 1 then
    return 1
  end
  return count
end

local function addLines(tooltip, itemID)
  if not ForeverAuctionsDB then
    return
  end
  if type(itemID) ~= "number" or isSecret(itemID) then
    return
  end
  local showAuction = ns.GetOption("tooltip")
  local showVendor = ns.GetOption("tooltipVendor")
  local showStack = ns.GetOption("tooltipStack")
  local showStackVendor = ns.GetOption("tooltipStackVendor")
  if not (showAuction or showVendor or showStack or showStackVendor) then
    return
  end

  local entry, average, days = ns.Lookup(itemID)
  local vendor = (showVendor or showStackVendor) and vendorPrice(itemID) or nil
  local stack = (showStack or showStackVendor) and stackCount(tooltip, itemID) or 1
  local vendorPaysMore = entry and vendor and vendor > entry.price
  local added = false

  if entry and showAuction then
    tooltip:AddDoubleLine("Auction (" .. ns.Age(entry.seen) .. ")", ns.Money(entry.price), 0.85, 0.65, 0.34, 1, 1, 1)
    if days > 1 then
      tooltip:AddDoubleLine(days .. "-day average", ns.Money(average), 0.6, 0.6, 0.6, 0.8, 0.8, 0.8)
    end
    added = true
  end
  local cost, complete = showAuction and ns.GetOption("craftCost") and ns.CraftCost(itemID)
  if cost then
    local profit = ns.CraftProfit(itemID)
    if profit then
      tooltip:AddDoubleLine("Crafting cost", ns.Money(cost), 0.6, 0.6, 0.6, 1, 1, 1)
      tooltip:AddDoubleLine(profit >= 0 and "Crafting profit" or "Crafting loss", ns.Money(math.abs(profit)),
        0.6, 0.6, 0.6, profit >= 0 and 0.3 or 1, profit >= 0 and 0.9 or 0.4, 0.3)
    else
      tooltip:AddDoubleLine(complete and "Crafting cost" or "Crafting cost (some reagents have no price)", ns.Money(cost), 0.6, 0.6, 0.6, 1, 1, 1)
    end
    added = true
  end
  local target = showAuction and ns.GetOption("priceAlerts") and ns.WatchTarget(itemID)
  if target then
    tooltip:AddDoubleLine("Price alert at", ns.Money(target), 0.4, 0.8, 1, 1, 1, 1)
    added = true
  end
  if vendor and showVendor then
    if vendorPaysMore then
      tooltip:AddDoubleLine("Vendor (pays more than auction)", ns.Money(vendor), 1, 0.4, 0.3, 1, 1, 1)
    else
      tooltip:AddDoubleLine("Vendor", ns.Money(vendor), 0.6, 0.6, 0.6, 1, 1, 1)
    end
    added = true
  end
  if stack > 1 then
    if entry and showStack then
      tooltip:AddDoubleLine("Auction, stack of " .. stack, ns.Money(entry.price * stack), 0.85, 0.65, 0.34, 1, 1, 1)
      added = true
    end
    if vendor and showStackVendor then
      if vendorPaysMore then
        tooltip:AddDoubleLine("Vendor, stack of " .. stack .. " (pays more)", ns.Money(vendor * stack), 1, 0.4, 0.3, 1, 1, 1)
      else
        tooltip:AddDoubleLine("Vendor, stack of " .. stack, ns.Money(vendor * stack), 0.6, 0.6, 0.6, 1, 1, 1)
      end
      added = true
    end
  end
  return added
end

local function isItemTooltip(tooltip)
  return tooltip == GameTooltip or tooltip == ItemRefTooltip
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if isItemTooltip(tooltip) and data then
      addLines(tooltip, data.id)
    end
  end)
end
