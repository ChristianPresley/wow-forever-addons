local _, ns = ...

-- Item tooltips: whether the item is on a gear list or the player's own list, and whether it is
-- an upgrade for the slot it fits.

local function isSecret(value)
  return issecretvalue ~= nil and issecretvalue(value) or false
end

local GOLD, GREEN, GREY, BLUE = { 1, 0.82, 0.3 }, { 0.3, 0.9, 0.3 }, { 0.6, 0.6, 0.6 }, { 0.5, 0.75, 1 }

-- The lines for an item, as { text, color }. The scenario reads these too.
function ns.TooltipLines(itemID)
  local lines = {}
  if not ForeverGearDB or type(itemID) ~= "number" or isSecret(itemID) then
    return lines
  end
  local class = ns.PlayerClass()
  local role = ns.GetRole(class)
  local judged = ns.Judge(itemID, role, class)
  local slot = judged.slot and ns.SLOT_BY_KEY[judged.slot]
  if ns.GetOption("tooltipList") then
    if judged.rank then
      lines[#lines + 1] = { string.format("Gear list, %s: #%d for %s", ns.ROLES[role], judged.rank, slot and slot.name or "?"), GOLD }
    end
    if ns.GetOption("tooltipOtherRoles") then
      local item = ns.Item(itemID)
      for _, other in ipairs(ns.RolesOf(class)) do
        if other ~= role and item and item.roles[other] and ns.CanWear(item, class) then
          lines[#lines + 1] = { string.format("Gear list, %s: #%d", ns.ROLES[other], item.roles[other]), GREY }
        end
      end
    end
    if ns.IsPersonal(itemID) then
      lines[#lines + 1] = { "On your own list", BLUE }
    end
  end
  if ns.GetOption("tooltipUpgrade") and slot then
    if judged.verdict == "upgrade" then
      lines[#lines + 1] = { "Upgrade for your " .. slot.name:lower(), GREEN }
    elseif judged.verdict == "equipped" then
      lines[#lines + 1] = { "You wear this", GREY }
    elseif judged.verdict == "worse" then
      lines[#lines + 1] = { "Your " .. slot.name:lower() .. " ranks higher on the list", GREY }
    end
  end
  return lines
end

local function addLines(tooltip, itemID)
  for _, line in ipairs(ns.TooltipLines(itemID)) do
    tooltip:AddLine(line[1], line[2][1], line[2][2], line[2][3])
  end
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if (tooltip == GameTooltip or tooltip == ItemRefTooltip) and data then
      pcall(addLines, tooltip, data.id)
    end
  end)
end
