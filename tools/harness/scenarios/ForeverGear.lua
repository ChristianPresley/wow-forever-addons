-- What Forever Gear does, with checks. T is the test table of the driver (see driver.lua).
local T = ...
local H, ns, expect = T.H, T.ns, T.expect

local function lines(itemID)
  local texts = {}
  for _, line in ipairs(ns.TooltipLines(itemID)) do
    texts[#texts + 1] = line[1]
  end
  return table.concat(texts, " | ")
end

-- The data: every item has a known slot and instance, and every role of every class has a list.
for _, item in ipairs(ns.ITEMS) do
  expect(ns.SLOT_BY_KEY[item.slot] ~= nil and ns.INSTANCE_BY_KEY[item.from] ~= nil, "item " .. item.id .. " has a known slot and source")
end
for class, roles in pairs(ns.CLASS_ROLES) do
  for _, role in ipairs(roles) do
    expect(#ns.ListOf(role, class) > 0, class .. " " .. role .. " has a gear list")
  end
end

-- Armour: a warrior lists plate and lighter, a mage cloth only.
expect(ns.CanWear(ns.Item(12640), "WARRIOR") and not ns.CanWear(ns.Item(12640), "ROGUE"), "plate is for a warrior, not a rogue")
for _, entry in ipairs(ns.ListOf("melee", "ROGUE")) do
  expect(entry.item.armor ~= "plate" and entry.item.armor ~= "mail", "the rogue list has no " .. tostring(entry.item.armor) .. ": " .. entry.item.id)
end
expect(#ns.ListOf("melee", "ROGUE") < #ns.ListOf("melee", "WARRIOR"), "the rogue list is shorter than the warrior list")

-- Class items: a set piece of the priest is on the healer list of the priest only.
expect(ns.CanWear(ns.Item(16693), "PRIEST") and not ns.CanWear(ns.Item(16693), "DRUID"), "the priest's set helm is for a priest, not a druid")
for _, class in ipairs({ "PALADIN", "SHAMAN", "DRUID" }) do
  for _, entry in ipairs(ns.ListOf("healer", class)) do
    expect(not entry.item.classes or entry.item.classes[class], "the healer list of " .. class .. " has no item of another class: " .. entry.item.id)
  end
end

-- Every role of every class has an item for every slot that every class fills.
local ids = {}
for _, item in ipairs(ns.ITEMS) do
  expect(not ids[item.id], "item " .. item.id .. " is in the data once")
  ids[item.id] = true
  expect(not item.weapon or item.weapon == "held" or ns.WEAPONS_OF_CLASS.WARRIOR[item.weapon] or item.weapon == "wand", "item " .. item.id .. " has a known weapon type")
  expect((item.slot == "MAINHAND" or item.slot == "OFFHAND" or item.slot == "RANGED") == (item.weapon ~= nil), "item " .. item.id .. " has a weapon type when it is for a hand, and only then")
end
for class, roles in pairs(ns.CLASS_ROLES) do
  for _, role in ipairs(roles) do
    local filled = {}
    for _, entry in ipairs(ns.ListOf(role, class)) do
      filled[entry.item.slot] = true
    end
    for _, slot in ipairs(ns.SLOTS) do
      if slot.key ~= "OFFHAND" and slot.key ~= "RANGED" then
        expect(filled[slot.key], class .. " " .. role .. " has an item for " .. slot.name)
      end
    end
  end
end

-- Weapons: a class sees the types it can use, and a weapon in the off hand only when it can hold one there.
expect(ns.CanWear(ns.Item(18348), "WARRIOR") and not ns.CanWear(ns.Item(18348), "DRUID"), "a sword is for a warrior, not a druid")
for _, entry in ipairs(ns.ListOf("tank", "DRUID")) do
  expect(entry.item.weapon ~= "sword" and entry.item.weapon ~= "shield", "the druid tank list has no " .. tostring(entry.item.weapon) .. ": " .. entry.item.id)
end
expect(ns.CanWear(ns.Item(12939), "ROGUE") and not ns.CanWear(ns.Item(12939), "PALADIN"), "a sword in the off hand is for a rogue, not a paladin")
expect(ns.CanWear(ns.Item(12602), "PALADIN") and not ns.CanWear(ns.Item(12602), "ROGUE"), "a shield is for a paladin, not a rogue")
expect(ns.CanWear(ns.Item(22253), "PRIEST") and ns.CanWear(ns.Item(22253), "DRUID"), "an off-hand item that is no weapon is for every class")
expect(ns.CanWear(ns.Item(13938), "MAGE") and not ns.CanWear(ns.Item(13938), "SHAMAN"), "a wand is for a mage, not a shaman")

-- Other sources: the loot browser has the group, with the world drops.
local other = ns.LootOf("OTHER")
local hasEdgemasters
for _, item in ipairs(other) do
  hasEdgemasters = hasEdgemasters or item.id == 14551
end
expect(hasEdgemasters, "the other sources have the world-drop gloves")

-- The audit. The world has item 2211, a shield by name that the stand-in gives no equip location.
local missing = ns.AuditItem({ id = 999999, name = "No such thing", slot = "HEAD" })
expect(missing and missing:find("no item with this ID", 1, true), "the audit names an ID that the game does not have, got " .. tostring(missing))
local wrongName = ns.AuditItem({ id = 2211, name = "Round Shield", slot = "OFFHAND" })
expect(wrongName and wrongName:find("is named Bent Large Shield in the game", 1, true), "the audit names another name, got " .. tostring(wrongName))
expect(wrongName and wrongName:find("is not equipment in the game, off hand here", 1, true), "the audit names another slot, got " .. tostring(wrongName))
local problems, _, total = ns.Audit()
expect(total == #ns.ITEMS and #problems == total, "the stand-in has none of the items, so the audit lists each one")
T.slash("/fgear", "audit")
expect(T.printed("audit: " .. total .. " of " .. total .. " items differ"), "/fgear audit prints the count")
expect(ns.Judge(14152, "caster", "WARLOCK").rank == nil and ns.Judge(14152, "caster", "MAGE").rank == 1, "the mage's robe has a rank for a mage only")
-- The role: the first role of the class by default. The character of the world is a warrior.
expect(ns.GetRole() == "melee", "a warrior starts with the melee list, got " .. tostring(ns.GetRole()))
local melee = ns.ListOf("melee")
expect(melee[1].item.slot == "HEAD" and melee[1].rank == 1, "the list starts with the first choice for the head")
expect(ns.SetRole("healer") == false and ns.GetRole() == "melee", "a warrior has no healer list")

-- The tooltip: the main hand of the world is an item that no list names, so a list weapon is an upgrade.
expect(lines(11684) == "Gear list, Melee damage: #1 for Main hand | Upgrade for your main hand", "a list weapon is an upgrade, got " .. lines(11684))
expect(lines(18348) == "", "a tank weapon says nothing to a melee warrior, got " .. lines(18348))
ns.SetOption("tooltipOtherRoles", true)
expect(lines(18348) == "Gear list, Tank: #1", "with other roles on, the tank rank shows and no upgrade line for another role, got " .. lines(18348))
ns.SetOption("tooltipOtherRoles", false)
ns.SetOption("tooltipUpgrade", false)
expect(lines(11684) == "Gear list, Melee damage: #1 for Main hand", "without the upgrade line only the rank shows, got " .. lines(11684))
ns.SetOption("tooltipUpgrade", true)

T.slash("/fgear", "role tank")
expect(ns.GetRole() == "tank" and ForeverGearDB.roles.WARRIOR == "tank", "/fgear role tank stores the role for the class")
expect(lines(18348) == "Gear list, Tank: #1 for Main hand | Upgrade for your main hand", "the tank list is used now, got " .. lines(18348))
T.slash("/fgear", "role melee")

-- Two trinkets with no list trinket worn: each is an upgrade; the rank of the second is shown.
expect(lines(13965) == "Gear list, Melee damage: #2 for Trinkets | Upgrade for your trinkets", "the second trinket, got " .. lines(13965))

-- The own list. The worn shield of the world goes on it, in the main hand.
T.slash("/fgear", "add " .. H.itemLink(2211) .. " mainhand")
expect(ForeverGearDB.personal[2211] == "MAINHAND", "/fgear add stores the item with its slot")
expect(lines(2211) == "On your own list | You wear this", "a worn item of the own list, got " .. lines(2211))
T.slash("/fgear", "add " .. H.itemLink(2211))
expect(ForeverGearDB.personal[2211] == nil, "/fgear add again takes it off")
T.slash("/fgear", "check 11684")
expect(T.printed("Upgrade for your main hand"), "/fgear check prints the tooltip lines")

-- The window: the loot of Blackrock Depths, and a click on an item puts it on the own list.
T.slash("/fgear", "loot brd")
expect(ForeverGearWindow ~= nil and ForeverGearWindow:IsShown(), "/fgear loot opens the window")
local entries = ns.WindowEntries()
local found
for _, entry in ipairs(entries) do
  found = found or entry.id == 11684
end
expect(found, "the loot of Blackrock Depths has Ironfoe")
local row
for _, candidate in ipairs(ForeverGearWindow.rows) do
  if candidate.entry and candidate.entry.id then
    row = row or candidate
  end
end
expect(row ~= nil, "the window shows an item row")
local clicked = row.entry.id
H.click(row)
expect(ns.IsPersonal(clicked), "a click on an item puts it on the own list")
T.slash("/fgear", "mine")
local mine = ns.WindowEntries()
expect(mine[2] and mine[2].id == clicked, "the own list shows the clicked item")
expect(#ns.PersonalList() == 1, "one item on the own list")
ns.ClearPersonal()
expect(#ns.PersonalList() == 0, "the own list is cleared")
T.slash("/fgear", "loot nowhere")
expect(T.printed("no dungeon by that name"), "an unknown dungeon is named in chat")
ForeverGearWindow:Hide()
