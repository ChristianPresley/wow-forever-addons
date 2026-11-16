local _, ns = ...

-- Item tooltips: how many of the item the account owns, and which character has them.

local function isSecret(value)
  return issecretvalue ~= nil and issecretvalue(value) or false
end

local function classColor(class)
  local color = type(class) == "string" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if color then
    return color.r, color.g, color.b
  end
  return 0.8, 0.8, 0.8
end

local function addLines(tooltip, itemID)
  if not ForeverBagsDB or type(itemID) ~= "number" or isSecret(itemID) then
    return
  end
  local showMine, showAlts = ns.GetOption("tooltipCounts"), ns.GetOption("tooltipAlts")
  if not (showMine or showAlts) then
    return
  end
  local lines, shared, total = ns.OwnerLines(itemID)
  local shown = 0
  for _, line in ipairs(lines) do
    if (line.isMe and showMine) or (not line.isMe and showAlts) then
      local r, g, b = classColor(line.class)
      tooltip:AddDoubleLine(line.name, line.text, r, g, b, 1, 1, 1)
      shown = shown + 1
    end
  end
  if showAlts and shared > 0 then
    tooltip:AddDoubleLine("Shared bank", shared, 0.6, 0.8, 1, 1, 1, 1)
    shown = shown + 1
  end
  -- A total says something only with more than one line above it.
  if shown > 1 then
    tooltip:AddDoubleLine("Owned in total", total, 0.6, 0.6, 0.6, 1, 1, 1)
  end
end

local function isItemTooltip(tooltip)
  return tooltip == GameTooltip or tooltip == ItemRefTooltip
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if isItemTooltip(tooltip) and data then
      pcall(addLines, tooltip, data.id)
    end
  end)
else
  local function onSetItem(tooltip)
    local _, link = tooltip:GetItem()
    if link then
      pcall(addLines, tooltip, tonumber(link:match("item:(%d+)")))
    end
  end
  GameTooltip:HookScript("OnTooltipSetItem", onSetItem)
  ItemRefTooltip:HookScript("OnTooltipSetItem", onSetItem)
end
