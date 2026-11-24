local _, ns = ...

-- The lists: which items a role wants, which items an instance gives, the player's own list,
-- and how an item compares with what the character wears.

local byID = {}
for _, item in ipairs(ns.ITEMS) do
  byID[item.id] = item
end

function ns.Item(itemID)
  return byID[itemID]
end

-- Whether a class can wear an item: its armour type is at most the class's heaviest.
function ns.CanWear(item, class)
  if item.classes and not item.classes[class] then
    return false
  end
  if not item.armor then
    return true
  end
  local most = ns.ARMOR_OF_CLASS[class] or "plate"
  return ns.ARMOR_WEIGHT[item.armor] <= ns.ARMOR_WEIGHT[most]
end

-- The items of a role, ordered by slot and then by rank. With a class: only what it can wear.
function ns.ListOf(role, class)
  local list = {}
  for _, item in ipairs(ns.ITEMS) do
    local rank = item.roles[role]
    if rank and (not class or ns.CanWear(item, class)) then
      list[#list + 1] = { item = item, rank = rank }
    end
  end
  table.sort(list, function(a, b)
    local sa, sb = ns.SLOT_BY_KEY[a.item.slot].order, ns.SLOT_BY_KEY[b.item.slot].order
    if sa ~= sb then
      return sa < sb
    end
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return a.item.id < b.item.id
  end)
  return list
end

-- The items of an instance, ordered by source and then by slot.
function ns.LootOf(instanceKey)
  local list = {}
  for _, item in ipairs(ns.ITEMS) do
    if item.from == instanceKey then
      list[#list + 1] = item
    end
  end
  table.sort(list, function(a, b)
    local sa, sb = a.source or "~", b.source or "~"
    if sa ~= sb then
      return sa < sb
    end
    local oa, ob = ns.SLOT_BY_KEY[a.slot].order, ns.SLOT_BY_KEY[b.slot].order
    if oa ~= ob then
      return oa < ob
    end
    return a.id < b.id
  end)
  return list
end

---------------------------------------------------------------------------------------------------
-- The player's own list

-- The slot key of an item: from the data, or from the game.
function ns.SlotOf(itemID)
  local item = byID[itemID]
  if item then
    return item.slot
  end
  local saved = ForeverGearDB and ForeverGearDB.personal[itemID]
  if saved and saved ~= "" then
    return saved
  end
  local ok, _, _, _, equipLoc = pcall(C_Item.GetItemInfoInstant, itemID)
  if ok and type(equipLoc) == "string" then
    return ns.EQUIP_LOCATIONS[equipLoc]
  end
end

function ns.IsPersonal(itemID)
  return ForeverGearDB ~= nil and ForeverGearDB.personal[itemID] ~= nil
end

-- Puts an item on the player's list, or takes it off. Returns true when it is on the list now.
function ns.TogglePersonal(itemID, slotKey)
  if not ForeverGearDB or type(itemID) ~= "number" then
    return false
  end
  local personal = ForeverGearDB.personal
  if personal[itemID] ~= nil and not slotKey then
    personal[itemID] = nil
    ns.Changed("personal")
    return false
  end
  if slotKey and not ns.SLOT_BY_KEY[slotKey] then
    slotKey = nil
  end
  personal[itemID] = slotKey or ns.SlotOf(itemID) or ""
  ns.Changed("personal")
  return true
end

function ns.ClearPersonal()
  ForeverGearDB.personal = {}
  ns.Changed("personal")
end

-- The items of the player's list, ordered by slot.
function ns.PersonalList()
  local list = {}
  for itemID, slot in pairs(ForeverGearDB and ForeverGearDB.personal or {}) do
    list[#list + 1] = { id = itemID, slot = slot ~= "" and slot or nil }
  end
  table.sort(list, function(a, b)
    local oa = a.slot and ns.SLOT_BY_KEY[a.slot].order or 99
    local ob = b.slot and ns.SLOT_BY_KEY[b.slot].order or 99
    if oa ~= ob then
      return oa < ob
    end
    return a.id < b.id
  end)
  return list
end

---------------------------------------------------------------------------------------------------
-- Comparison with the equipped items

function ns.EquippedIn(slotKey)
  local slot = ns.SLOT_BY_KEY[slotKey]
  local ids = {}
  if slot then
    for _, inventory in ipairs(slot.inventory) do
      local itemID = GetInventoryItemID("player", inventory)
      if type(itemID) == "number" then
        ids[#ids + 1] = itemID
      end
    end
  end
  return ids
end

-- In any slot: a one-hand weapon of the main hand list can sit in the off hand.
function ns.IsEquipped(itemID)
  for inventory = 1, 18 do
    if GetInventoryItemID("player", inventory) == itemID then
      return true
    end
  end
  return false
end

-- What the tooltip says about an item for a role. Returns a table:
--   rank    = rank of the item on the role's list, or nil
--   slot    = the slot key
--   verdict = "equipped", "upgrade", "worse" or nil (no list item, or the same rank as the worn one)
function ns.Judge(itemID, role, class)
  local item = byID[itemID]
  local result = { slot = ns.SlotOf(itemID) }
  result.rank = item and (not class or ns.CanWear(item, class)) and item.roles[role] or nil
  if not result.slot then
    return result
  end
  if ns.IsEquipped(itemID) then
    result.verdict = "equipped"
    return result
  end
  local equipped = ns.EquippedIn(result.slot)
  if not result.rank then
    return result
  end
  local slot = ns.SLOT_BY_KEY[result.slot]
  -- An empty slot, or a slot whose item the list does not name, gains from a list item. A slot
  -- with two places (rings, trinkets) gains when the weaker of the two ranks lower.
  local worst = 0
  for index = 1, #slot.inventory do
    local id = equipped[index]
    local other = id and byID[id]
    local rank = other and other.slot == result.slot and other.roles[role] or math.huge
    worst = math.max(worst, rank)
  end
  -- The same rank as the worn item: neither is better, so no line.
  if result.rank < worst then
    result.verdict = "upgrade"
  elseif result.rank > worst then
    result.verdict = "worse"
  end
  return result
end
