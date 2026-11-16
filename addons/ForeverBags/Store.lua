local _, ns = ...

-- The store: what each character has in its bags, its bank and on its body, and its gold.
--
-- The game gives an addon the bags of the character that is logged in, and its bank only while
-- the bank window is open. So the store keeps what it saw: the bags after each change, the bank
-- each time the player is at a banker. The other characters are read from the saved data.

-- Bag numbers (Enum.BagIndex). The backpack is 0, the bags are 1 to 4, the reagent bag is 5.
ns.BAGS = { 0, 1, 2, 3, 4, 5 }
local BANK_FIRST, BANK_LAST = 6, 14 -- the bank tabs of the character
local ACCOUNT_FIRST, ACCOUNT_LAST = 15, 23 -- the bank tabs that all characters share
local EQUIPMENT_SLOTS = 19

local bankOpen = false
local listeners = {}

-- fn runs after the stored items of this character changed.
function ns.OnStoreChanged(fn)
  listeners[#listeners + 1] = fn
end

local function changed()
  for _, fn in ipairs(listeners) do
    local ok, err = pcall(fn)
    if not ok then
      geterrorhandler()(err)
    end
  end
end

function ns.CharacterKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- The record of this character. Made at the first call.
function ns.Me()
  local key = ns.CharacterKey()
  local characters = ForeverBagsDB.characters
  local me = characters[key]
  if type(me) ~= "table" then
    me = {}
    characters[key] = me
  end
  me.name = UnitName("player") or "?"
  me.realm = GetRealmName() or "?"
  me.class = select(2, UnitClass("player"))
  me.level = UnitLevel("player")
  for _, part in ipairs({ "bags", "bank", "equipped" }) do
    if type(me[part]) ~= "table" then
      me[part] = {}
    end
  end
  return me
end

local function slotsOf(bag)
  local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
  return ok and type(slots) == "number" and slots or 0
end

-- Counts the items of a range of bags: { [itemID] = count }.
local function countBags(first, last)
  local counts = {}
  for bag = first, last do
    for slot = 1, slotsOf(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local itemID = info and info.itemID
      if type(itemID) == "number" then
        counts[itemID] = (counts[itemID] or 0) + (type(info.stackCount) == "number" and info.stackCount or 1)
      end
    end
  end
  return counts
end

local function scanBags()
  local me = ns.Me()
  me.bags = countBags(ns.BAGS[1], ns.BAGS[#ns.BAGS])
  me.money = GetMoney and GetMoney() or me.money
  me.updated = time()
end

local function scanEquipped()
  local me = ns.Me()
  local counts = {}
  for slot = 1, EQUIPMENT_SLOTS do
    local itemID = GetInventoryItemID and GetInventoryItemID("player", slot)
    if type(itemID) == "number" then
      counts[itemID] = (counts[itemID] or 0) + 1
    end
  end
  me.equipped = counts
end

-- Only while the bank window is open: at other times the game says that the bank is empty.
local function scanBank()
  if not bankOpen then
    return
  end
  local me = ns.Me()
  me.bank = countBags(BANK_FIRST, BANK_LAST)
  me.bankSeen = time()
  ForeverBagsDB.accountBank = countBags(ACCOUNT_FIRST, ACCOUNT_LAST)
end

function ns.BankIsOpen()
  return bankOpen
end

---------------------------------------------------------------------------------------------------
-- Questions about the store

-- The characters, this one first, then by name: { { key, record, isMe }, ... }
function ns.Characters()
  local myKey = ns.CharacterKey()
  local list = {}
  for key, record in pairs(ForeverBagsDB.characters) do
    if type(record) == "table" then
      list[#list + 1] = { key = key, record = record, isMe = key == myKey }
    end
  end
  table.sort(list, function(a, b)
    if a.isMe ~= b.isMe then
      return a.isMe
    end
    return a.key < b.key
  end)
  return list
end

local function part(record, name, itemID)
  local counts = record[name]
  local count = type(counts) == "table" and counts[itemID]
  return type(count) == "number" and count or 0
end

-- Who owns an item: { { key, record, isMe, bags, bank, equipped, total }, ... } for the characters
-- with at least one, then the count in the shared bank, then the total of all.
function ns.Owners(itemID)
  local owners, total = {}, 0
  for _, character in ipairs(ns.Characters()) do
    local bags = part(character.record, "bags", itemID)
    local bank = part(character.record, "bank", itemID)
    local equipped = part(character.record, "equipped", itemID)
    local sum = bags + bank + equipped
    if sum > 0 then
      character.bags, character.bank, character.equipped, character.total = bags, bank, equipped, sum
      owners[#owners + 1] = character
      total = total + sum
    end
  end
  local shared = ForeverBagsDB.accountBank[itemID]
  shared = type(shared) == "number" and shared or 0
  return owners, shared, total + shared
end

-- Removes the stored data of a character that is not logged in. Returns true if it was there.
function ns.Forget(key)
  if key == ns.CharacterKey() or not ForeverBagsDB.characters[key] then
    return false
  end
  ForeverBagsDB.characters[key] = nil
  changed()
  return true
end

function ns.ForgetOthers()
  local myKey = ns.CharacterKey()
  for key in pairs(ForeverBagsDB.characters) do
    if key ~= myKey then
      ForeverBagsDB.characters[key] = nil
    end
  end
  changed()
end

---------------------------------------------------------------------------------------------------
-- Events

local pending = false

local function scan()
  pending = false
  pcall(scanBags)
  pcall(scanEquipped)
  pcall(scanBank)
  changed()
end

local function schedule()
  -- The bag events come in bursts. One scan per burst is enough.
  if not pending then
    pending = true
    C_Timer.After(0.3, scan)
  end
end

ns.OnLogin(function()
  local events = CreateFrame("Frame")
  for _, event in ipairs({
    "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED",
  }) do
    pcall(events.RegisterEvent, events, event)
  end
  events:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
      bankOpen = true
    elseif event == "BANKFRAME_CLOSED" then
      -- A last look, then the bank is closed.
      pcall(scanBank)
      bankOpen = false
    end
    schedule()
  end)
  schedule()
end)
