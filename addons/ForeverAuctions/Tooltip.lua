local _, ns = ...

local function addPrice(tooltip, itemID)
  if not ForeverAuctionsDB or not ForeverAuctionsDB.options.tooltip then
    return
  end
  if type(itemID) ~= "number" or (issecretvalue and issecretvalue(itemID)) then
    return
  end
  local entry, average, days = ns.Lookup(itemID)
  if not entry then
    return
  end
  tooltip:AddDoubleLine("Auction (" .. ns.Age(entry.seen) .. ")", ns.Money(entry.price), 0.85, 0.65, 0.34, 1, 1, 1)
  if days > 1 then
    tooltip:AddDoubleLine(days .. "-day average", ns.Money(average), 0.6, 0.6, 0.6, 0.8, 0.8, 0.8)
  end
end

local function isItemTooltip(tooltip)
  return tooltip == GameTooltip or tooltip == ItemRefTooltip
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if isItemTooltip(tooltip) and data then
      addPrice(tooltip, data.id)
    end
  end)
else
  local function onSetItem(tooltip)
    local _, link = tooltip:GetItem()
    if link then
      addPrice(tooltip, tonumber(link:match("item:(%d+)")))
    end
  end
  GameTooltip:HookScript("OnTooltipSetItem", onSetItem)
  ItemRefTooltip:HookScript("OnTooltipSetItem", onSetItem)
end
