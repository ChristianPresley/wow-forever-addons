local _, ns = ...

-- The gear data of Forever Gear. Written for this addon from general knowledge of the game's
-- pre-raid gear; no list of another addon or site is copied. Nothing here is checked against the
-- game client yet: the IDs, the slots, the sources and the ranks are all from memory. Each item is
-- listed once, with the
-- slot it fits, where it comes from and the roles that want it, ranked: 1 is the first choice of
-- that role for that slot.
--
-- The game client gives each item's name, icon and quality from its ID, so only the ID, the
-- slot and the source are stored here. Lists are a starting point for version 0.1: check each
-- one in the game (/fgear) and correct an item whose name does not fit its slot.

-- Slots of a list, with the inventory slots of the character that they compare with.
ns.SLOTS = {
  { key = "HEAD", name = "Head", inventory = { 1 } },
  { key = "NECK", name = "Neck", inventory = { 2 } },
  { key = "SHOULDER", name = "Shoulders", inventory = { 3 } },
  { key = "BACK", name = "Back", inventory = { 15 } },
  { key = "CHEST", name = "Chest", inventory = { 5 } },
  { key = "WRIST", name = "Wrists", inventory = { 9 } },
  { key = "HANDS", name = "Hands", inventory = { 10 } },
  { key = "WAIST", name = "Waist", inventory = { 6 } },
  { key = "LEGS", name = "Legs", inventory = { 7 } },
  { key = "FEET", name = "Feet", inventory = { 8 } },
  { key = "FINGER", name = "Rings", inventory = { 11, 12 } },
  { key = "TRINKET", name = "Trinkets", inventory = { 13, 14 } },
  { key = "MAINHAND", name = "Main hand", inventory = { 16 } },
  { key = "OFFHAND", name = "Off hand", inventory = { 17 } },
  { key = "RANGED", name = "Ranged", inventory = { 18 } },
}
ns.SLOT_BY_KEY = {}
for index, slot in ipairs(ns.SLOTS) do
  slot.order = index
  ns.SLOT_BY_KEY[slot.key] = slot
end

-- The equip location that the game gives an item (C_Item.GetItemInfoInstant), as a slot key.
ns.EQUIP_LOCATIONS = {
  INVTYPE_HEAD = "HEAD", INVTYPE_NECK = "NECK", INVTYPE_SHOULDER = "SHOULDER", INVTYPE_CLOAK = "BACK",
  INVTYPE_CHEST = "CHEST", INVTYPE_ROBE = "CHEST", INVTYPE_WRIST = "WRIST", INVTYPE_HAND = "HANDS",
  INVTYPE_WAIST = "WAIST", INVTYPE_LEGS = "LEGS", INVTYPE_FEET = "FEET", INVTYPE_FINGER = "FINGER",
  INVTYPE_TRINKET = "TRINKET", INVTYPE_WEAPON = "MAINHAND", INVTYPE_2HWEAPON = "MAINHAND",
  INVTYPE_WEAPONMAINHAND = "MAINHAND", INVTYPE_WEAPONOFFHAND = "OFFHAND", INVTYPE_SHIELD = "OFFHAND",
  INVTYPE_HOLDABLE = "OFFHAND", INVTYPE_RANGED = "RANGED", INVTYPE_RANGEDRIGHT = "RANGED",
  INVTYPE_THROWN = "RANGED", INVTYPE_RELIC = "RANGED",
}

-- Roles. A class lists its roles; the first is the default.
ns.ROLES = {
  melee = "Melee damage",
  ranged = "Ranged damage",
  caster = "Spell damage",
  healer = "Healer",
  tank = "Tank",
}
ns.CLASS_ROLES = {
  WARRIOR = { "melee", "tank" },
  ROGUE = { "melee" },
  HUNTER = { "ranged" },
  MAGE = { "caster" },
  WARLOCK = { "caster" },
  PRIEST = { "healer", "caster" },
  PALADIN = { "healer", "tank", "melee" },
  SHAMAN = { "healer", "caster", "melee" },
  DRUID = { "healer", "caster", "tank", "melee" },
}

-- Armour types. A class wears its own type and the lighter ones.
ns.ARMOR_WEIGHT = { cloth = 1, leather = 2, mail = 3, plate = 4 }
ns.ARMOR_OF_CLASS = {
  WARRIOR = "plate", PALADIN = "plate", HUNTER = "mail", SHAMAN = "mail",
  ROGUE = "leather", DRUID = "leather", MAGE = "cloth", WARLOCK = "cloth", PRIEST = "cloth",
}

-- Instances of the loot browser, in the order of the list.
ns.INSTANCES = {
  { key = "BRD", name = "Blackrock Depths" },
  { key = "LBRS", name = "Lower Blackrock Spire" },
  { key = "UBRS", name = "Upper Blackrock Spire" },
  { key = "STRAT", name = "Stratholme" },
  { key = "SCHOLO", name = "Scholomance" },
  { key = "DM", name = "Dire Maul" },
  { key = "CRAFT", name = "Crafted" },
  { key = "QUEST", name = "Quests" },
}
ns.INSTANCE_BY_KEY = {}
for index, instance in ipairs(ns.INSTANCES) do
  instance.order = index
  ns.INSTANCE_BY_KEY[instance.key] = instance
end

-- id, slot, armour type (nil: not armour), instance key, boss or other source (nil: the boss is
-- not certain), classes (nil: every class; else the set of classes that can use the item), and
-- { role = rank } for the roles that list the item.
ns.ITEMS = {
  -- Melee damage, and the hunter where the item has agility
  { id = 12640, slot = "HEAD", armor = "plate", from = "CRAFT", source = "Blacksmithing", roles = { melee = 1, tank = 2 } },
  { id = 13404, slot = "HEAD", armor = "leather", from = "STRAT", source = "The Unforgiven", roles = { melee = 2, ranged = 1 } },
  { id = 15411, slot = "NECK", from = "QUEST", source = "Western Plaguelands", roles = { melee = 1, ranged = 1 } },
  { id = 12927, slot = "SHOULDER", armor = "leather", from = "UBRS", roles = { melee = 1, ranged = 1 } },
  { id = 13340, slot = "BACK", from = "STRAT", source = "Baron Rivendare", roles = { melee = 1, ranged = 1, tank = 2 } },
  { id = 11726, slot = "CHEST", armor = "mail", from = "BRD", source = "Ring of Law", roles = { melee = 1, ranged = 2 } },
  { id = 14637, slot = "CHEST", armor = "leather", from = "SCHOLO", roles = { melee = 2, ranged = 1 } },
  { id = 13400, slot = "WRIST", armor = "plate", from = "STRAT", roles = { melee = 1, tank = 1 } },
  { id = 15063, slot = "HANDS", armor = "leather", from = "CRAFT", source = "Leatherworking", roles = { melee = 1, ranged = 1 } },
  { id = 14551, slot = "HANDS", armor = "mail", from = "LBRS", roles = { melee = 2, tank = 1 } },
  { id = 15062, slot = "LEGS", armor = "leather", from = "CRAFT", source = "Leatherworking", roles = { melee = 1, ranged = 1 } },
  { id = 17713, slot = "FINGER", from = "QUEST", source = "Blackrock Depths quest", roles = { melee = 1, ranged = 1 } },
  { id = 11815, slot = "TRINKET", from = "BRD", roles = { melee = 1, ranged = 2, tank = 2 } },
  { id = 13965, slot = "TRINKET", from = "UBRS", source = "General Drakkisath", roles = { melee = 2, ranged = 1 } },
  { id = 20130, slot = "TRINKET", from = "QUEST", source = "Warrior quest", classes = { WARRIOR = true }, roles = { melee = 3, tank = 1 } },
  { id = 11684, slot = "MAINHAND", from = "BRD", source = "Emperor Dagran Thaurissan", roles = { melee = 1 } },
  { id = 12940, slot = "MAINHAND", from = "UBRS", source = "Warchief Rend Blackhand", roles = { melee = 2 } },
  { id = 12939, slot = "OFFHAND", from = "UBRS", source = "Warchief Rend Blackhand", roles = { melee = 1 } },
  { id = 18348, slot = "MAINHAND", from = "QUEST", source = "Onyxia quest chain", roles = { tank = 1 } },
  { id = 12602, slot = "OFFHAND", from = "UBRS", roles = { tank = 1 } },
  { id = 18323, slot = "RANGED", from = "DM", roles = { ranged = 1, melee = 1 } },
  -- Spell damage
  { id = 16686, slot = "HEAD", armor = "cloth", from = "SCHOLO", source = "Magister's set", classes = { MAGE = true }, roles = { caster = 1 } },
  { id = 14152, slot = "CHEST", armor = "cloth", from = "CRAFT", source = "Tailoring", classes = { MAGE = true }, roles = { caster = 1 } },
  { id = 14153, slot = "CHEST", armor = "cloth", from = "CRAFT", source = "Tailoring", classes = { WARLOCK = true }, roles = { caster = 2 } },
  { id = 12930, slot = "TRINKET", from = "UBRS", roles = { caster = 1 } },
  { id = 13968, slot = "TRINKET", from = "UBRS", source = "The Beast", roles = { caster = 2 } },
  -- Healing
  { id = 16693, slot = "HEAD", armor = "cloth", from = "SCHOLO", source = "Devout set", classes = { PRIEST = true }, roles = { healer = 1 } },
  { id = 16690, slot = "CHEST", armor = "cloth", from = "UBRS", source = "Devout set", classes = { PRIEST = true }, roles = { healer = 1 } },
  { id = 11923, slot = "MAINHAND", from = "BRD", roles = { healer = 1 } },
  { id = 18510, slot = "BACK", from = "CRAFT", source = "Leatherworking", roles = { healer = 1 } },
  -- More loot of the dungeons, on no list yet
  { id = 11735, slot = "HEAD", armor = "leather", from = "BRD", roles = {} },
  { id = 11926, slot = "CHEST", armor = "mail", from = "BRD", roles = {} },
  { id = 11933, slot = "NECK", from = "BRD", source = "Emperor Dagran Thaurissan", roles = {} },
  { id = 12553, slot = "FEET", armor = "leather", from = "BRD", roles = {} },
  { id = 13252, slot = "WAIST", armor = "leather", from = "LBRS", roles = {} },
  { id = 13361, slot = "MAINHAND", from = "STRAT", source = "Baron Rivendare", roles = {} },
  { id = 13963, slot = "HANDS", armor = "mail", from = "LBRS", source = "War Master Voone", roles = {} },
  { id = 12608, slot = "BACK", from = "LBRS", roles = {} },
  { id = 12587, slot = "HEAD", armor = "leather", from = "UBRS", source = "Warchief Rend Blackhand", roles = {} },
  { id = 12935, slot = "LEGS", armor = "plate", from = "UBRS", roles = {} },
  { id = 12936, slot = "WRIST", armor = "plate", from = "UBRS", roles = {} },
  { id = 12963, slot = "LEGS", armor = "leather", from = "UBRS", roles = {} },
  { id = 13358, slot = "SHOULDER", armor = "leather", from = "UBRS", roles = {} },
  { id = 12929, slot = "NECK", from = "UBRS", source = "Pyroguard Emberseer", roles = {} },
  { id = 13344, slot = "HANDS", armor = "mail", from = "STRAT", roles = {} },
  { id = 12783, slot = "MAINHAND", from = "CRAFT", source = "Blacksmithing", roles = {} },
  { id = 13392, slot = "FINGER", from = "STRAT", source = "Postmaster Malown", roles = {} },
  { id = 13398, slot = "FEET", armor = "leather", from = "STRAT", roles = {} },
  { id = 13955, slot = "SHOULDER", armor = "plate", from = "STRAT", roles = {} },
  { id = 13373, slot = "FINGER", from = "SCHOLO", roles = {} },
  { id = 13385, slot = "OFFHAND", from = "SCHOLO", roles = {} },
  { id = 13353, slot = "OFFHAND", from = "SCHOLO", source = "Darkmaster Gandling", roles = {} },
  { id = 14614, slot = "WAIST", armor = "mail", from = "SCHOLO", roles = {} },
  { id = 13951, slot = "WRIST", armor = "plate", from = "SCHOLO", roles = {} },
  { id = 18734, slot = "BACK", from = "DM", roles = {} },
  { id = 18723, slot = "NECK", from = "DM", roles = {} },
  { id = 18737, slot = "MAINHAND", from = "DM", roles = {} },
  { id = 18530, slot = "CHEST", armor = "mail", from = "DM", roles = {} },
  { id = 18537, slot = "TRINKET", from = "DM", roles = {} },
  { id = 18405, slot = "WAIST", armor = "cloth", from = "CRAFT", source = "Tailoring", roles = {} },
}
