local _, ns = ...

-- The gear data of Forever Gear. Written for this addon from general knowledge of the game's
-- pre-raid gear; no list of another addon or site is copied.
--
-- Nothing here is checked against the game client yet: the IDs, the names, the slots, the sources,
-- the ranks and which class can use which weapon are all from memory. /fgear audit compares each
-- item with what the game client says about its ID (the name, on an English client, and the
-- slot) and prints the differences: run it in the game and correct this file from its lines.
--
-- Each item is listed once, with the slot it fits, where it comes from and the roles that want
-- it, ranked: 1 is the first choice of that role for that slot.

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

-- Weapon types that a class can use. A name with 2 is the two-hand kind. "held" (an off-hand item
-- that is not a weapon) is for every class and is not in the table. A class that is not in the
-- table gets every weapon.
local function set(...)
  local result = {}
  for index = 1, select("#", ...) do
    result[(select(index, ...))] = true
  end
  return result
end
ns.WEAPONS_OF_CLASS = {
  WARRIOR = set("sword", "sword2", "axe", "axe2", "mace", "mace2", "dagger", "fist", "polearm", "staff", "bow", "gun", "crossbow", "thrown", "shield"),
  PALADIN = set("sword", "sword2", "axe", "axe2", "mace", "mace2", "polearm", "shield"),
  HUNTER = set("sword", "sword2", "axe", "axe2", "dagger", "fist", "polearm", "staff", "bow", "gun", "crossbow", "thrown"),
  ROGUE = set("sword", "mace", "dagger", "fist", "bow", "gun", "crossbow", "thrown"),
  PRIEST = set("mace", "dagger", "staff", "wand"),
  SHAMAN = set("mace", "mace2", "axe", "axe2", "dagger", "fist", "staff", "shield"),
  MAGE = set("sword", "dagger", "staff", "wand"),
  WARLOCK = set("sword", "dagger", "staff", "wand"),
  DRUID = set("mace", "mace2", "dagger", "fist", "staff"),
}
-- Classes that hold a weapon in the off hand.
ns.DUAL_WIELD = set("WARRIOR", "ROGUE", "HUNTER")

-- Sources of the loot browser, in the order of the list.
ns.INSTANCES = {
  { key = "BRD", name = "Blackrock Depths" },
  { key = "LBRS", name = "Lower Blackrock Spire" },
  { key = "UBRS", name = "Upper Blackrock Spire" },
  { key = "STRAT", name = "Stratholme" },
  { key = "SCHOLO", name = "Scholomance" },
  { key = "DM", name = "Dire Maul" },
  { key = "CRAFT", name = "Crafted" },
  { key = "QUEST", name = "Quests" },
  { key = "OTHER", name = "Other sources" },
}
ns.INSTANCE_BY_KEY = {}
for index, instance in ipairs(ns.INSTANCES) do
  instance.order = index
  ns.INSTANCE_BY_KEY[instance.key] = instance
end

local WARRIOR, PALADIN, HUNTER, SHAMAN = set("WARRIOR"), set("PALADIN"), set("HUNTER"), set("SHAMAN")
local MAGE, WARLOCK, PRIEST, DRUID = set("MAGE"), set("WARLOCK"), set("PRIEST"), set("DRUID")

-- An item:
--   id      the item ID of the game
--   name    the English name, as the author remembers it (nil: not remembered). The window shows
--           the name that the game gives; this one is for /fgear audit
--   slot    a key of ns.SLOTS
--   armor   the armour type (nil: not armour)
--   weapon  the weapon type, a key of ns.WEAPONS_OF_CLASS, or "held" (nil: not for a hand)
--   from    a key of ns.INSTANCES
--   source  the boss, profession or other source (nil: not certain)
--   classes the classes that can use the item (nil: every class that can wear it)
--   roles   { role = rank } for the roles that list the item
ns.ITEMS = {
  -- Head
  { id = 12640, name = "Lionheart Helm", slot = "HEAD", armor = "plate", from = "CRAFT", source = "Blacksmithing", roles = { melee = 1, tank = 3 } },
  { id = 13404, name = "Mask of the Unforgiven", slot = "HEAD", armor = "leather", from = "STRAT", source = "The Unforgiven", roles = { melee = 2, ranged = 2, tank = 4 } },
  { id = 12587, name = "Eye of Rend", slot = "HEAD", armor = "leather", from = "UBRS", source = "Warchief Rend Blackhand", roles = { melee = 3 } },
  { id = 12952, name = "Gyth's Skull", slot = "HEAD", armor = "plate", from = "UBRS", source = "Gyth", roles = { tank = 1 } },
  { id = 16731, name = "Helm of Valor", slot = "HEAD", armor = "plate", from = "SCHOLO", source = "Darkmaster Gandling", classes = WARRIOR, roles = { tank = 2 } },
  { id = 16677, name = "Beaststalker's Cap", slot = "HEAD", armor = "mail", from = "SCHOLO", source = "Darkmaster Gandling", classes = HUNTER, roles = { ranged = 1 } },
  { id = 22267, name = "Spellweaver's Turban", slot = "HEAD", armor = "cloth", from = "UBRS", source = "General Drakkisath", roles = { caster = 1 } },
  { id = 16686, name = "Magister's Crown", slot = "HEAD", armor = "cloth", from = "SCHOLO", source = "Darkmaster Gandling", classes = MAGE, roles = { caster = 2 } },
  { id = 16698, name = "Dreadmist Mask", slot = "HEAD", armor = "cloth", from = "SCHOLO", source = "Darkmaster Gandling", classes = WARLOCK, roles = { caster = 2 } },
  { id = 10504, name = "Green Lens", slot = "HEAD", armor = "cloth", from = "CRAFT", source = "Engineering", roles = { caster = 3, healer = 3 } },
  { id = 16693, name = "Devout Crown", slot = "HEAD", armor = "cloth", from = "SCHOLO", source = "Darkmaster Gandling", classes = PRIEST, roles = { healer = 1 } },
  { id = 16727, name = "Lightforge Helm", slot = "HEAD", armor = "plate", from = "SCHOLO", source = "Darkmaster Gandling", classes = PALADIN, roles = { healer = 1 } },
  { id = 16667, name = "Coif of Elements", slot = "HEAD", armor = "mail", from = "SCHOLO", source = "Darkmaster Gandling", classes = SHAMAN, roles = { healer = 1 } },
  { id = 16720, name = "Wildheart Cowl", slot = "HEAD", armor = "leather", from = "SCHOLO", source = "Darkmaster Gandling", classes = DRUID, roles = { healer = 1 } },
  { id = 13102, name = "Cassandra's Grace", slot = "HEAD", armor = "cloth", from = "OTHER", source = "World drop", roles = { healer = 2 } },
  { id = 11735, name = "Ragefury Eyepatch", slot = "HEAD", armor = "leather", from = "BRD", roles = {} },

  -- Neck
  { id = 15411, name = "Mark of Fordring", slot = "NECK", from = "QUEST", source = "Western Plaguelands", roles = { melee = 1, ranged = 1, tank = 2 } },
  { id = 11933, name = "Imperial Jewel", slot = "NECK", from = "BRD", source = "Emperor Dagran Thaurissan", roles = { melee = 2, ranged = 2 } },
  { id = 13177, name = "Talisman of Evasion", slot = "NECK", from = "UBRS", source = "General Drakkisath", roles = { tank = 1 } },
  { id = 12929, name = "Emberfury Talisman", slot = "NECK", from = "UBRS", source = "Pyroguard Emberseer", roles = { tank = 3 } },
  { id = 12103, name = "Star of Mystaria", slot = "NECK", from = "OTHER", source = "World drop", roles = { caster = 1, healer = 2 } },
  { id = 13141, name = "Tooth of Gnarr", slot = "NECK", from = "LBRS", roles = { caster = 2 } },
  { id = 18723, name = "Animated Chain Necklace", slot = "NECK", from = "DM", roles = { healer = 1 } },

  -- Shoulders
  { id = 12927, name = "Truestrike Shoulders", slot = "SHOULDER", armor = "leather", from = "UBRS", source = "Pyroguard Emberseer", roles = { melee = 1, ranged = 1, tank = 3 } },
  { id = 13358, name = "Wyrmtongue Shoulders", slot = "SHOULDER", armor = "leather", from = "OTHER", roles = { melee = 2 } },
  { id = 14552, name = "Stockade Pauldrons", slot = "SHOULDER", armor = "plate", from = "OTHER", source = "World drop", roles = { tank = 1 } },
  { id = 13955, name = "Stoneform Shoulders", slot = "SHOULDER", armor = "plate", from = "STRAT", roles = { tank = 2 } },
  { id = 16679, name = "Beaststalker's Mantle", slot = "SHOULDER", armor = "mail", from = "LBRS", source = "Beaststalker set", classes = HUNTER, roles = { ranged = 2 } },
  { id = 11782, name = "Boreal Mantle", slot = "SHOULDER", armor = "cloth", from = "BRD", roles = { caster = 1 } },
  { id = 13013, name = "Elder Wizard's Mantle", slot = "SHOULDER", armor = "cloth", from = "OTHER", source = "World drop", roles = { caster = 2 } },
  { id = 18681, name = "Burial Shawl", slot = "SHOULDER", armor = "cloth", from = "SCHOLO", roles = { healer = 1 } },
  { id = 16695, name = "Devout Mantle", slot = "SHOULDER", armor = "cloth", from = "UBRS", source = "Devout set", classes = PRIEST, roles = { healer = 2 } },
  { id = 15061, name = "Living Shoulders", slot = "SHOULDER", armor = "leather", from = "CRAFT", source = "Leatherworking", roles = { healer = 3 } },

  -- Back
  { id = 13340, name = "Cape of the Black Baron", slot = "BACK", from = "STRAT", source = "Baron Rivendare", roles = { melee = 1, ranged = 1, tank = 2 } },
  { id = 13397, name = "Stoneskin Gargoyle Cape", slot = "BACK", from = "STRAT", roles = { tank = 1, melee = 2 } },
  { id = 13386, name = "Archivist Cape", slot = "BACK", from = "STRAT", roles = { caster = 1, healer = 3 } },
  { id = 18350, name = "Amplifying Cloak", slot = "BACK", from = "DM", roles = { caster = 2 } },
  { id = 18510, name = "Hide of the Wild", slot = "BACK", from = "CRAFT", source = "Leatherworking", roles = { healer = 1 } },
  { id = 18389, name = "Cloak of the Cosmos", slot = "BACK", from = "DM", roles = { healer = 2 } },
  { id = 12608, slot = "BACK", from = "LBRS", roles = {} },
  { id = 18734, slot = "BACK", from = "DM", roles = {} },

  -- Chest
  { id = 11726, name = "Savage Gladiator Chain", slot = "CHEST", armor = "mail", from = "BRD", source = "Ring of Law", roles = { melee = 1, ranged = 2 } },
  { id = 14637, name = "Cadaverous Armor", slot = "CHEST", armor = "leather", from = "SCHOLO", roles = { melee = 2, ranged = 1 } },
  { id = 16674, name = "Beaststalker's Tunic", slot = "CHEST", armor = "mail", from = "UBRS", source = "General Drakkisath", classes = HUNTER, roles = { ranged = 3 } },
  { id = 14624, name = "Deathbone Chestplate", slot = "CHEST", armor = "plate", from = "SCHOLO", roles = { tank = 1 } },
  { id = 16730, name = "Breastplate of Valor", slot = "CHEST", armor = "plate", from = "UBRS", source = "General Drakkisath", classes = WARRIOR, roles = { tank = 2 } },
  { id = 15064, name = "Warbear Harness", slot = "CHEST", armor = "leather", from = "CRAFT", source = "Leatherworking", roles = { tank = 3 } },
  { id = 14152, name = "Robe of the Archmage", slot = "CHEST", armor = "cloth", from = "CRAFT", source = "Tailoring", classes = MAGE, roles = { caster = 1 } },
  { id = 14153, name = "Robe of the Void", slot = "CHEST", armor = "cloth", from = "CRAFT", source = "Tailoring", classes = WARLOCK, roles = { caster = 1 } },
  { id = 14136, name = "Robe of Winter Night", slot = "CHEST", armor = "cloth", from = "CRAFT", source = "Tailoring", roles = { caster = 2 } },
  { id = 11924, name = "Robes of the Royal Crown", slot = "CHEST", armor = "cloth", from = "BRD", roles = { caster = 3 } },
  { id = 13346, name = "Robes of the Exalted", slot = "CHEST", armor = "cloth", from = "STRAT", source = "Baron Rivendare", roles = { healer = 1 } },
  { id = 16690, name = "Devout Robe", slot = "CHEST", armor = "cloth", from = "UBRS", source = "General Drakkisath", classes = PRIEST, roles = { healer = 2 } },
  { id = 11926, name = "Deathdealer Breastplate", slot = "CHEST", armor = "mail", from = "BRD", roles = {} },
  { id = 18530, slot = "CHEST", armor = "mail", from = "DM", roles = {} },

  -- Wrists
  { id = 13400, name = "Vambraces of the Sadist", slot = "WRIST", armor = "plate", from = "STRAT", roles = { melee = 1, tank = 1 } },
  { id = 12936, name = "Battleborn Armbraces", slot = "WRIST", armor = "plate", from = "UBRS", roles = { melee = 2 } },
  { id = 18375, name = "Bracers of the Eclipse", slot = "WRIST", armor = "leather", from = "DM", roles = { melee = 3 } },
  { id = 12966, name = "Blackmist Armguards", slot = "WRIST", armor = "leather", from = "UBRS", roles = { melee = 4, tank = 3 } },
  { id = 13211, name = "Slashclaw Bracers", slot = "WRIST", armor = "mail", from = "LBRS", roles = { ranged = 1, melee = 5 } },
  { id = 16681, name = "Beaststalker's Bindings", slot = "WRIST", armor = "mail", from = "OTHER", source = "Beaststalker set", classes = HUNTER, roles = { ranged = 2 } },
  { id = 12550, name = "Runed Golem Shackles", slot = "WRIST", armor = "plate", from = "BRD", roles = { tank = 2 } },
  { id = 11766, name = "Flameweave Cuffs", slot = "WRIST", armor = "cloth", from = "BRD", roles = { caster = 1 } },
  { id = 16683, name = "Magister's Bindings", slot = "WRIST", armor = "cloth", from = "OTHER", source = "Magister's set", classes = MAGE, roles = { caster = 2 } },
  { id = 16703, name = "Dreadmist Bracers", slot = "WRIST", armor = "cloth", from = "OTHER", source = "Dreadmist set", classes = WARLOCK, roles = { caster = 2 } },
  { id = 13409, name = "Tearfall Bracers", slot = "WRIST", armor = "cloth", from = "STRAT", roles = { healer = 1 } },
  { id = 16697, name = "Devout Bracers", slot = "WRIST", armor = "cloth", from = "OTHER", source = "Devout set", classes = PRIEST, roles = { healer = 2 } },
  { id = 13951, slot = "WRIST", armor = "plate", from = "SCHOLO", roles = {} },

  -- Hands
  { id = 15063, name = "Devilsaur Gauntlets", slot = "HANDS", armor = "leather", from = "CRAFT", source = "Leatherworking", roles = { melee = 1, ranged = 1, tank = 4 } },
  { id = 14551, name = "Edgemaster's Handguards", slot = "HANDS", armor = "mail", from = "OTHER", source = "World drop", roles = { melee = 2, tank = 1 } },
  { id = 13957, name = "Gargoyle Slashers", slot = "HANDS", armor = "mail", from = "STRAT", roles = { melee = 3, ranged = 3 } },
  { id = 16676, name = "Beaststalker's Gloves", slot = "HANDS", armor = "mail", from = "LBRS", source = "Beaststalker set", classes = HUNTER, roles = { ranged = 2 } },
  { id = 12639, name = "Stronghold Gauntlets", slot = "HANDS", armor = "plate", from = "CRAFT", source = "Blacksmithing", roles = { tank = 2 } },
  { id = 14622, name = "Deathbone Gauntlets", slot = "HANDS", armor = "plate", from = "SCHOLO", roles = { tank = 3 } },
  { id = 13253, name = "Hands of Power", slot = "HANDS", armor = "cloth", from = "LBRS", roles = { caster = 1 } },
  { id = 18407, name = "Felcloth Gloves", slot = "HANDS", armor = "cloth", from = "CRAFT", source = "Tailoring", roles = { caster = 2 } },
  { id = 12554, name = "Hands of the Exalted Herald", slot = "HANDS", armor = "cloth", from = "BRD", roles = { healer = 1 } },
  { id = 16692, name = "Devout Gloves", slot = "HANDS", armor = "cloth", from = "STRAT", source = "Devout set", classes = PRIEST, roles = { healer = 2 } },
  { id = 13963, name = "Voone's Vice Grips", slot = "HANDS", armor = "mail", from = "LBRS", source = "War Master Voone", roles = {} },
  { id = 13344, name = "Dracorian Gauntlets", slot = "HANDS", armor = "mail", from = "STRAT", roles = {} },

  -- Waist
  { id = 13142, name = "Brigam Girdle", slot = "WAIST", armor = "plate", from = "UBRS", source = "General Drakkisath", roles = { melee = 1, tank = 3 } },
  { id = 13252, name = "Cloudrunner Girdle", slot = "WAIST", armor = "leather", from = "LBRS", roles = { melee = 2, ranged = 2, tank = 4 } },
  { id = 14614, name = "Bloodmail Belt", slot = "WAIST", armor = "mail", from = "SCHOLO", roles = { melee = 3, ranged = 3 } },
  { id = 16680, name = "Beaststalker's Belt", slot = "WAIST", armor = "mail", from = "OTHER", source = "Beaststalker set", classes = HUNTER, roles = { ranged = 1 } },
  { id = 14620, name = "Deathbone Girdle", slot = "WAIST", armor = "plate", from = "SCHOLO", roles = { tank = 1 } },
  { id = 16736, name = "Belt of Valor", slot = "WAIST", armor = "plate", from = "OTHER", source = "Valor set", classes = WARRIOR, roles = { tank = 2 } },
  { id = 11662, name = "Ban'thok Sash", slot = "WAIST", armor = "cloth", from = "BRD", roles = { caster = 1 } },
  { id = 18405, name = "Belt of the Archmage", slot = "WAIST", armor = "cloth", from = "CRAFT", source = "Tailoring", roles = { caster = 2 } },
  { id = 18327, name = "Whipvine Cord", slot = "WAIST", armor = "cloth", from = "DM", roles = { healer = 1 } },
  { id = 16696, name = "Devout Belt", slot = "WAIST", armor = "cloth", from = "OTHER", source = "Devout set", classes = PRIEST, roles = { healer = 2 } },

  -- Legs
  { id = 15062, name = "Devilsaur Leggings", slot = "LEGS", armor = "leather", from = "CRAFT", source = "Leatherworking", roles = { melee = 1, ranged = 1 } },
  { id = 12963, name = "Blademaster Leggings", slot = "LEGS", armor = "leather", from = "UBRS", roles = { melee = 2, ranged = 2 } },
  { id = 14554, name = "Cloudkeeper Legplates", slot = "LEGS", armor = "plate", from = "OTHER", source = "World drop", roles = { melee = 3 } },
  { id = 16678, name = "Beaststalker's Pants", slot = "LEGS", armor = "mail", from = "STRAT", source = "Baron Rivendare", classes = HUNTER, roles = { ranged = 3 } },
  { id = 14623, name = "Deathbone Legguards", slot = "LEGS", armor = "plate", from = "SCHOLO", roles = { tank = 1 } },
  { id = 12935, name = "Warmaster Legguards", slot = "LEGS", armor = "plate", from = "UBRS", roles = { tank = 2 } },
  { id = 15065, name = "Warbear Woolies", slot = "LEGS", armor = "leather", from = "CRAFT", source = "Leatherworking", roles = { tank = 3 } },
  { id = 13170, name = "Skyshroud Leggings", slot = "LEGS", armor = "cloth", from = "UBRS", roles = { caster = 1 } },
  { id = 16687, name = "Magister's Leggings", slot = "LEGS", armor = "cloth", from = "STRAT", source = "Baron Rivendare", classes = MAGE, roles = { caster = 2 } },
  { id = 16699, name = "Dreadmist Leggings", slot = "LEGS", armor = "cloth", from = "STRAT", source = "Baron Rivendare", classes = WARLOCK, roles = { caster = 2 } },
  { id = 12965, name = "Spiritshroud Leggings", slot = "LEGS", armor = "cloth", from = "UBRS", source = "Warchief Rend Blackhand", roles = { healer = 1 } },
  { id = 18386, name = "Padre's Trousers", slot = "LEGS", armor = "cloth", from = "DM", roles = { healer = 2 } },
  { id = 16694, name = "Devout Skirt", slot = "LEGS", armor = "cloth", from = "STRAT", source = "Baron Rivendare", classes = PRIEST, roles = { healer = 3 } },

  -- Feet
  { id = 12555, name = "Battlechaser's Greaves", slot = "FEET", armor = "plate", from = "BRD", roles = { melee = 1, tank = 3 } },
  { id = 14616, name = "Bloodmail Boots", slot = "FEET", armor = "mail", from = "SCHOLO", roles = { melee = 2, ranged = 1 } },
  { id = 12553, name = "Swiftwalker Boots", slot = "FEET", armor = "leather", from = "BRD", roles = { melee = 3, ranged = 3, tank = 4 } },
  { id = 16675, name = "Beaststalker's Boots", slot = "FEET", armor = "mail", from = "STRAT", source = "Beaststalker set", classes = HUNTER, roles = { ranged = 2 } },
  { id = 14621, name = "Deathbone Sabatons", slot = "FEET", armor = "plate", from = "SCHOLO", roles = { tank = 1 } },
  { id = 16734, name = "Boots of Valor", slot = "FEET", armor = "plate", from = "SCHOLO", source = "Valor set", classes = WARRIOR, roles = { tank = 2 } },
  { id = 11822, name = "Omnicast Boots", slot = "FEET", armor = "cloth", from = "BRD", roles = { caster = 1, healer = 2 } },
  { id = 16682, name = "Magister's Boots", slot = "FEET", armor = "cloth", from = "STRAT", source = "Magister's set", classes = MAGE, roles = { caster = 2 } },
  { id = 16704, name = "Dreadmist Sandals", slot = "FEET", armor = "cloth", from = "STRAT", source = "Dreadmist set", classes = WARLOCK, roles = { caster = 2 } },
  { id = 22247, name = "Faith Healer's Boots", slot = "FEET", armor = "cloth", from = "BRD", roles = { healer = 1 } },
  { id = 16691, name = "Devout Sandals", slot = "FEET", armor = "cloth", from = "STRAT", source = "Devout set", classes = PRIEST, roles = { healer = 3 } },
  { id = 13398, name = "Boots of the Shrieker", slot = "FEET", armor = "leather", from = "STRAT", roles = {} },

  -- Rings
  { id = 17713, name = "Blackstone Ring", slot = "FINGER", from = "OTHER", source = "Another dungeon", roles = { melee = 1, ranged = 1 } },
  { id = 13098, name = "Painweaver Band", slot = "FINGER", from = "UBRS", source = "General Drakkisath", roles = { melee = 2, ranged = 2 } },
  { id = 18500, name = "Tarnished Elven Ring", slot = "FINGER", from = "DM", roles = { melee = 3, ranged = 3 } },
  { id = 11669, name = "Naglering", slot = "FINGER", from = "BRD", roles = { tank = 1 } },
  { id = 13373, name = "Band of Flesh", slot = "FINGER", from = "OTHER", roles = { tank = 2, melee = 4 } },
  { id = 12548, name = "Magni's Will", slot = "FINGER", from = "QUEST", source = "Blackrock Depths quest", roles = { tank = 3 } },
  { id = 12926, name = "Flaming Band", slot = "FINGER", from = "UBRS", roles = { caster = 1 } },
  { id = 13001, name = "Maiden's Circle", slot = "FINGER", from = "OTHER", source = "World drop", roles = { caster = 2 } },
  { id = 942, name = "Freezing Band", slot = "FINGER", from = "OTHER", source = "World drop", roles = { caster = 3 } },
  { id = 13178, name = "Rosewine Circle", slot = "FINGER", from = "UBRS", roles = { healer = 1 } },
  { id = 16058, name = "Fordring's Seal", slot = "FINGER", from = "QUEST", source = "Western Plaguelands", roles = { healer = 2 } },
  { id = 12543, name = "Songstone of Ironforge", slot = "FINGER", from = "QUEST", source = "Blackrock Depths quest", roles = { healer = 3, caster = 4 } },
  { id = 13392, name = "The Postmaster's Seal", slot = "FINGER", from = "STRAT", source = "Postmaster Malown", roles = {} },

  -- Trinkets
  { id = 11815, name = "Hand of Justice", slot = "TRINKET", from = "BRD", source = "Emperor Dagran Thaurissan", roles = { melee = 1, ranged = 2, tank = 4 } },
  { id = 13965, name = "Blackhand's Breadth", slot = "TRINKET", from = "UBRS", source = "General Drakkisath", roles = { melee = 2, ranged = 1 } },
  { id = 20130, name = "Diamond Flask", slot = "TRINKET", from = "QUEST", source = "Warrior quest", classes = WARRIOR, roles = { melee = 3, tank = 1 } },
  { id = 13966, name = "Mark of Tyranny", slot = "TRINKET", from = "UBRS", source = "General Drakkisath", roles = { tank = 2 } },
  { id = 11810, name = "Force of Will", slot = "TRINKET", from = "BRD", roles = { tank = 3 } },
  { id = 12930, name = "Briarwood Reed", slot = "TRINKET", from = "UBRS", roles = { caster = 1, healer = 3 } },
  { id = 13968, name = "Eye of the Beast", slot = "TRINKET", from = "UBRS", source = "The Beast", roles = { caster = 2 } },
  { id = 11832, name = "Burst of Knowledge", slot = "TRINKET", from = "BRD", roles = { caster = 3 } },
  { id = 11819, name = "Second Wind", slot = "TRINKET", from = "BRD", roles = { healer = 1 } },
  { id = 18371, name = "Mindtap Talisman", slot = "TRINKET", from = "DM", roles = { healer = 2 } },
  { id = 18537, slot = "TRINKET", from = "DM", roles = {} },

  -- Main hand
  { id = 11684, name = "Ironfoe", slot = "MAINHAND", weapon = "mace", from = "BRD", source = "Emperor Dagran Thaurissan", roles = { melee = 1, tank = 3 } },
  { id = 12940, name = "Dal'Rend's Sacred Charge", slot = "MAINHAND", weapon = "sword", from = "UBRS", source = "Warchief Rend Blackhand", roles = { melee = 2, ranged = 1 } },
  { id = 12784, name = "Arcanite Reaper", slot = "MAINHAND", weapon = "axe2", from = "CRAFT", source = "Blacksmithing", roles = { melee = 3 } },
  { id = 18420, name = "Bonecrusher", slot = "MAINHAND", weapon = "mace2", from = "DM", roles = { melee = 4 } },
  { id = 9449, name = "Manual Crowd Pummeler", slot = "MAINHAND", weapon = "mace2", from = "OTHER", source = "Another dungeon", classes = DRUID, roles = { melee = 1 } },
  { id = 18520, name = "Barbarous Blade", slot = "MAINHAND", weapon = "sword2", from = "DM", roles = { ranged = 2 } },
  { id = 18348, name = "Quel'Serrar", slot = "MAINHAND", weapon = "sword", from = "QUEST", source = "Onyxia quest chain", roles = { tank = 1 } },
  { id = 943, name = "Warden Staff", slot = "MAINHAND", weapon = "staff", from = "OTHER", source = "World drop", classes = DRUID, roles = { tank = 1 } },
  { id = 13964, name = "Witchblade", slot = "MAINHAND", weapon = "dagger", from = "SCHOLO", roles = { caster = 1 } },
  { id = 873, name = "Staff of Jordan", slot = "MAINHAND", weapon = "staff", from = "OTHER", source = "World drop", roles = { caster = 2 } },
  { id = 18534, name = "Rod of the Ogre Magi", slot = "MAINHAND", weapon = "staff", from = "DM", roles = { caster = 3 } },
  { id = 11923, name = "The Hammer of Grace", slot = "MAINHAND", weapon = "mace", from = "BRD", roles = { healer = 1 } },
  { id = 11932, name = "Guiding Stave of Wisdom", slot = "MAINHAND", weapon = "staff", from = "BRD", roles = { healer = 2 } },
  { id = 22315, name = "Hammer of Revitalization", slot = "MAINHAND", weapon = "mace", from = "SCHOLO", roles = { healer = 3 } },
  { id = 13361, name = "Skullforge Reaver", slot = "MAINHAND", weapon = "sword", from = "STRAT", source = "Baron Rivendare", roles = {} },
  { id = 12783, name = "Heartseeker", slot = "MAINHAND", weapon = "dagger", from = "CRAFT", source = "Blacksmithing", roles = {} },
  { id = 18737, name = "Bone Slicing Hatchet", slot = "MAINHAND", weapon = "axe", from = "DM", roles = {} },

  -- Off hand
  { id = 12939, name = "Dal'Rend's Tribal Guardian", slot = "OFFHAND", weapon = "sword", from = "UBRS", source = "Warchief Rend Blackhand", roles = { melee = 1, ranged = 1 } },
  { id = 12602, name = "Draconian Deflector", slot = "OFFHAND", weapon = "shield", from = "UBRS", source = "General Drakkisath", roles = { tank = 1 } },
  { id = 22253, name = "Tome of the Lost", slot = "OFFHAND", weapon = "held", from = "DM", roles = { caster = 1 } },
  { id = 11928, name = "Thaurissan's Royal Scepter", slot = "OFFHAND", weapon = "held", from = "BRD", source = "Emperor Dagran Thaurissan", roles = { healer = 1 } },
  { id = 18523, name = "Brightly Glowing Stone", slot = "OFFHAND", weapon = "held", from = "DM", roles = { healer = 2 } },
  { id = 13385, name = "Tome of Knowledge", slot = "OFFHAND", weapon = "held", from = "OTHER", roles = {} },
  { id = 13353, name = "Book of the Dead", slot = "OFFHAND", weapon = "held", from = "SCHOLO", source = "Darkmaster Gandling", roles = {} },

  -- Ranged
  { id = 18323, name = "Satyr's Bow", slot = "RANGED", weapon = "bow", from = "DM", roles = { ranged = 1, melee = 1 } },
  { id = 12651, name = "Blackcrow", slot = "RANGED", weapon = "crossbow", from = "LBRS", roles = { ranged = 2, melee = 2 } },
  { id = 18738, name = "Carapace Spine Crossbow", slot = "RANGED", weapon = "crossbow", from = "STRAT", roles = { ranged = 3 } },
  { id = 13938, name = "Bonecreeper Stylus", slot = "RANGED", weapon = "wand", from = "SCHOLO", roles = { caster = 1, healer = 1 } },
  { id = 13396, name = "Skul's Ghastly Touch", slot = "RANGED", weapon = "wand", from = "STRAT", roles = { caster = 2, healer = 2 } },
}
