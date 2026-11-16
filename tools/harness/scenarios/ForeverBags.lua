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

-- The bag key opens this window, not the window of the game.
expect(ns.GetOption("replaceBags") == true, "the bag window is replaced by default")
local before = H.gameBags
ToggleAllBags()
expect(H.gameBags == before and ForeverBagsWindow ~= nil and ForeverBagsWindow:IsShown(), "the bag key opens the Forever Bags window")
CloseAllBags()
expect(not ForeverBagsWindow:IsShown() and H.gameBags == before, "closing the bags closes the window")
-- A bag of the bank stays with the game.
ToggleBag(7)
expect(H.gameBags == before + 1, "a bank bag opens in the game")
-- With the option off, the bag key reaches the game.
ns.SetOption("replaceBags", false)
before = H.gameBags
ToggleAllBags()
expect(H.gameBags == before + 1 and not ForeverBagsWindow:IsShown(), "with the option off, the bag key opens the window of the game")
ns.SetOption("replaceBags", true)

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
