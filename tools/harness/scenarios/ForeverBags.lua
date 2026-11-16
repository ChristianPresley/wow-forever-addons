-- What Forever Bags does, with checks. T is the test table of the driver (see driver.lua).
local T = ...
local H, ns, expect = T.H, T.ns, T.expect

-- The store: the bags of the character after login.
T.advance(2)
local me = ForeverBagsDB.characters["Tester-TestRealm"]
expect(me ~= nil and me.name == "Tester" and me.class == "WARRIOR" and me.level == 20, "the character is stored under its name and realm")
expect(me.bags[2589] == 32 and me.bags[769] == 8 and me.bags[117] == 5, "the bags are counted: 32 Linen Cloth in two stacks")
expect(me.equipped[2211] == 1, "the equipped item is counted")
expect(me.money == 123456, "the gold is stored")
expect(me.bankSeen == nil and next(me.bank) == nil, "the bank is not stored before a visit to a banker")

local owners, shared, total = ns.Owners(2589)
expect(#owners == 1 and owners[1].isMe and owners[1].bags == 32 and total == 32 and shared == 0, "one owner of Linen Cloth: this character, 32 in the bags")
-- The shield is in the bags and on the body.
local _, _, shields = ns.Owners(2211)
expect(shields == 2, "the shield counts in the bags and equipped")

-- Another character, as after a login with it.
ForeverBagsDB.characters["Alt-TestRealm"] = { name = "Alt", realm = "TestRealm", class = "MAGE", level = 12, money = 500, bags = { [2589] = 8 }, bank = { [2589] = 40 }, equipped = {}, bankSeen = 1 }
local lines, _, all = ns.OwnerLines(2589)
expect(#lines == 2 and all == 80, "two characters own 80 Linen Cloth")
expect(lines[1].isMe and lines[2].name == "Alt" and lines[2].text == "48 (bags 8, bank 40)", "the line of the other character: " .. tostring(lines[2] and lines[2].text))
T.slash("/fbags", "count " .. H.itemLink(2589))
T.slash("/fbags", "characters")
expect(T.printed("Gold of all characters"), "/fbags characters prints the gold of all characters")

-- The bag key opens this window. The functions of the game stay the game's own and run too (the
-- driver fails an addon that puts its own function in their place): the addon follows them.
expect(ns.GetOption("replaceBags") == true, "the bag window is replaced by default")
local before = H.gameBags
ToggleAllBags()
expect(H.gameBags > before, "the bag key runs the function of the game")
expect(ForeverBagsWindow ~= nil and ForeverBagsWindow:IsShown(), "the bag key opens the Forever Bags window")
T.advance(0.1)
ToggleAllBags()
expect(not ForeverBagsWindow:IsShown(), "the bag key again closes the window")
T.advance(0.1)
-- A vendor opens the bags and closes them.
OpenAllBags()
expect(ForeverBagsWindow:IsShown(), "OpenAllBags opens the window")
T.advance(0.1)
CloseAllBags()
expect(not ForeverBagsWindow:IsShown(), "CloseAllBags closes the window")
T.advance(0.1)
-- Escape closes this window and not the hidden one of the game: the bag key still opens it.
ToggleAllBags()
T.advance(0.1)
ForeverBagsWindow:Hide()
expect(H.gameBagsOpen == true, "the bag window of the game is still open, out of sight")
ToggleAllBags()
expect(ForeverBagsWindow:IsShown(), "after Escape the bag key opens the window again")
T.advance(0.1)
ToggleAllBags()
T.advance(0.1)
-- A bag of the bank stays with the game.
ToggleBag(7)
expect(not ForeverBagsWindow:IsShown(), "a bank bag does not open the window")
T.advance(0.1)
-- With the option off, the bag key leaves the window alone.
ns.SetOption("replaceBags", false)
ToggleAllBags()
expect(not ForeverBagsWindow:IsShown(), "with the option off, the bag key does not open the window")
T.advance(0.1)
ns.SetOption("replaceBags", true)

-- Categories. A quest item has any of the signs of the game: the mark of the slot, the item
-- class Quest, the bind type, or a quest of the log that names it. A quest item whose tooltip
-- says "Soulbound" and not "Quest Item" (the book) is one too.
expect(ns.CategoryOf(1, 3) == "quest", "Gnoll Paw (\"Quest Item\" in the tooltip) is a quest item, got " .. tostring(ns.CategoryOf(1, 3)))
expect(ns.CategoryOf(1, 4) == "quest", "the soulbound book of the item class Quest is a quest item, got " .. tostring(ns.CategoryOf(1, 4)))
-- An item of another class that an objective of a quest names is a quest item while it does.
expect(ns.CategoryOf(0, 2) == "trade", "Linen Cloth is a trade good while no quest asks for it")
T.world.questItems = true
T.fire("QUEST_LOG_UPDATE")
expect(ns.CategoryOf(0, 2) == "quest", "Linen Cloth is a quest item while a quest of the log asks for it (\"8/8 Linen Cloth\"), got " .. tostring(ns.CategoryOf(0, 2)))
T.world.questItems = nil
T.fire("QUEST_LOG_UPDATE")
expect(ns.CategoryOf(0, 2) == "trade", "and a trade good again when the quest is gone")
expect(ns.CategoryOf(1, 1) == "trade" and ns.CategoryOf(0, 3) == "consumables", "meat is a trade good and jerky a consumable")
expect(ns.CategoryOf(0, 4) == nil, "an empty slot has no category")

-- The Hearthstone has its own button at the top of the window, in both views.
T.slash("/fbags", "")
T.advance(1)
local stone = ForeverBagsWindow.hearthstone
expect(stone ~= nil and stone:IsShown() and stone:GetID() == 1 and stone:GetParent():GetID() == 0, "the Hearthstone (bag 0, slot 1) has its own button")
expect(stone ~= nil and select(2, stone:GetPoint(1)) == ForeverBagsWindow, "the button of the Hearthstone is at the top of the window, not in the grid")
ns.SetOption("groupBy", "none")
T.advance(1)
expect(ForeverBagsWindow.hearthstone == stone, "in the order of the bags the Hearthstone keeps its button")
ns.SetOption("groupBy", "category")
-- The window: by category and in bag order, and the search.
T.slash("/fbags", "")
ns.SetOption("groupBy", "none")
ns.SetOption("groupBy", "category")
T.slash("/fbags", "find linen")
T.advance(1)
T.slash("/fbags", "sort")
expect(H.count("sort bags") == 1, "/fbags sort asks the game to sort the bags")

-- The list of all characters, and forgetting one.
T.slash("/fbags", "all")
T.advance(2)
expect(ns.Forget("Tester-TestRealm") == false, "the character that is logged in cannot be forgotten")
expect(ns.Forget("Alt-TestRealm") == true and ForeverBagsDB.characters["Alt-TestRealm"] == nil, "another character is forgotten")
