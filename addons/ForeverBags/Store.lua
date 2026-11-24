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

-- The realm as the game names it, the text of the keys. The game gives an empty text now and then
-- (on some servers, for GetRealmName), so the normalized name is the second choice. nil if both are empty.
function ns.RealmName()
  local realm = GetRealmName and GetRealmName()
  if type(realm) == "string" and realm ~= "" then
    return realm
  end
  realm = GetNormalizedRealmName and GetNormalizedRealmName()
  if type(realm) == "string" and realm ~= "" then
    return realm
  end
  return nil
end

-- The realm that a stored record of this name has, for a time when the game gives none.
local function knownRealm(name)
  if not ForeverBagsDB or type(ForeverBagsDB.characters) ~= "table" then
    return nil
  end
  for _, record in pairs(ForeverBagsDB.characters) do
    if type(record) == "table" and record.name == name and type(record.realm) == "string" and record.realm ~= "" and record.realm ~= "?" then
      return record.realm
    end
  end
  return nil
end

function ns.CharacterKey()
  local name = UnitName("player") or "?"
  return name .. "-" .. (ns.RealmName() or knownRealm(name) or "?")
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
  me.realm = ns.RealmName() or knownRealm(me.name) or "?"
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

-- False while the game does not show the bank that all characters share: the player may not
-- see it, or it is locked (another character of the account has it open). The game then says
-- that its tabs are empty, and the counts that are known must stay.
local function sharedBankReadable()
  local bank = C_Bank
  local kind = Enum and Enum.BankType and Enum.BankType.Account
  if not (bank and kind) then
    return true
  end
  if bank.CanViewBank then
    local ok, can = pcall(bank.CanViewBank, kind)
    if ok and can == false then
      return false
    end
  end
  if bank.FetchBankLockedReason then
    local ok, reason = pcall(bank.FetchBankLockedReason, kind)
    if ok and reason ~= nil then
      return false
    end
  end
  return true
end
ns.SharedBankReadable = sharedBankReadable

-- False while the game does not show the bank of this character: the bank window can be open
-- for the shared bank alone. The game then says that the tabs of the character are empty, and
-- the counts that are known must stay.
local function ownBankReadable()
  local bank = C_Bank
  local kind = Enum and Enum.BankType and Enum.BankType.Character
  if bank and kind and bank.CanViewBank then
    local ok, can = pcall(bank.CanViewBank, kind)
    if ok and can == false then
      return false
    end
  end
  return true
end

-- Only while the bank window is open: at other times the game says that the bank is empty.
local function scanBank()
  if not bankOpen then
    return
  end
  if ownBankReadable() then
    local me = ns.Me()
    me.bank = countBags(BANK_FIRST, BANK_LAST)
    me.bankSeen = time()
  end
  if sharedBankReadable() then
    ForeverBagsDB.accountBank = countBags(ACCOUNT_FIRST, ACCOUNT_LAST)
  end
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
-- The name is taken in any letter case, as a player types it.
function ns.Forget(key)
  if type(key) ~= "string" then
    return false
  end
  local myKey, wanted = ns.CharacterKey(), key:lower()
  for stored in pairs(ForeverBagsDB.characters) do
    if stored ~= myKey and stored:lower() == wanted then
      ForeverBagsDB.characters[stored] = nil
      changed()
      return true
    end
  end
  return false
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

-- The record that an empty realm made: "Name-" with no realm. It is moved to the key with the
-- realm of this character, and merged with the record of that key if there is one. The newer
-- record decides each field; the bank is the one that was seen last.
local function merged(old, current)
  if not current then
    return old
  end
  local base, other = old, current
  if (current.updated or 0) >= (old.updated or 0) then
    base, other = current, old
  end
  local result = {}
  for field, value in pairs(base) do
    result[field] = value
  end
  for field, value in pairs(other) do
    if result[field] == nil then
      result[field] = value
    end
  end
  if (other.bankSeen or 0) > (base.bankSeen or 0) then
    result.bank, result.bankSeen = other.bank, other.bankSeen
  end
  return result
end

function ns.MigrateOwnRecord()
  local name, realm = UnitName("player"), ns.RealmName()
  if not (name and realm and ForeverBagsDB and type(ForeverBagsDB.characters) == "table") then
    return false
  end
  local characters = ForeverBagsDB.characters
  local bare = name .. "-"
  local old = characters[bare]
  if type(old) ~= "table" then
    return false
  end
  local key = name .. "-" .. realm
  local record = merged(old, characters[key])
  record.name, record.realm = name, realm
  characters[key] = record
  characters[bare] = nil
  changed()
  return true
end

ns.OnLogin(function()
  pcall(ns.MigrateOwnRecord)
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
