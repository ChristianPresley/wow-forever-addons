-- What Forever Auctions does, with checks. T is the test table of the driver (see driver.lua).
local T = ...
local H, ns, expect = T.H, T.ns, T.expect
local linen = H.itemLink(2589)

-- Browsing records the lowest price of each row.
T.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
local entry = ns.Lookup(2589)
expect(entry and entry.price == 150, "browsing stores 150 for Linen Cloth")
expect(ns.Lookup(769) and ns.Lookup(769).price == 40, "browsing stores 40 for Chunk of Boar Meat")
-- A commodity search: the lowest of three sellers.
T.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
expect(ns.Lookup(2589).price == 145, "a commodity search stores the lowest unit price of the three sellers (145), got " .. tostring(ns.Lookup(2589).price))

-- The undercut price.
ns.SetOption("undercut", 1)
expect(ns.UndercutPrice(150) == 149, "the undercut of 150 by 1 copper is 149")
ns.SetOption("undercut", 0)
expect(ns.UndercutPrice(150) == 150, "an undercut of 0 matches the price")
ns.SetOption("undercut", 1)

-- Full scan: needs the auction house, then reads every listing.
T.slash("/fah", "scan")
expect(H.count("full scan") == 0, "no full scan without the auction house")
H.openAuctionHouse()
T.fire("AUCTION_HOUSE_SHOW")
T.advance(1)
T.slash("/fah", "scan")
T.advance(2)
expect(H.count("full scan") == 1, "the full scan asks the game once")
T.slash("/fah", "scan")
T.advance(1)
expect(H.count("full scan") == 1, "a second scan within 15 minutes is not sent")
T.fire("REPLICATE_ITEM_LIST_UPDATE")
T.advance(5)
-- 20 for 3000 is 150 each, 10 for 1400 is 140 each: the lower one is stored.
expect(ns.Lookup(2589).price == 140, "the full scan stores the lowest unit price of Linen Cloth (140), got " .. tostring(ns.Lookup(2589).price))
-- 8 for 280 is 35 each: lower than the 40 that browsing stored.
expect(ns.Lookup(769).price == 35, "the full scan stores 35 for Chunk of Boar Meat, got " .. tostring(ns.Lookup(769).price))
expect(ns.ScanCooldown() > 0 and not ns.ScanRunning(), "after the scan the 15 minutes run")

-- The player's own auction (160) is above the stored lowest price (140).
T.fire("OWNED_AUCTIONS_UPDATED")
local undercut, active = ns.UndercutAuctions()
expect(active == 1 and #undercut == 1 and undercut[1].low == 140 and undercut[1].mine == 160, "the own auction at 160 is above the lowest price of 140")
T.slash("/fah", "mine")

-- A price alert: the stored price is at the target already.
T.slash("/fah", "watch " .. linen .. " 2s")
T.advance(2)
expect(ns.WatchTarget(2589) == 200, "the target price of the alert is 2 silver")
expect(T.printed("price alert: .* is at"), "the alert says that the item is at its target price")
T.slash("/fah", "watch")
T.slash("/fah", "unwatch " .. linen)
expect(ns.WatchTarget(2589) == nil, "the alert is removed")

-- The shopping list.
expect(ns.AddSearch("  Linen Cloth ") == true and #ns.ShoppingList() == 1, "a search is added, without the spaces around it")
expect(ns.AddSearch("linen cloth") == false, "the same search again is refused")
expect(ns.AddSearch(linen) == false, "an item link becomes the name of the item, which is on the list")
T.slash("/fah", "list add Copper Ore")
T.slash("/fah", "list")
expect(ns.RunSearch("Linen Cloth") == true and H.auctionSearches[#H.auctionSearches] == "Linen Cloth", "a click starts the search in the search box of the game")
-- The house is on the buy tab now: a second search does not set the tab again.
local modeSets = H.count("auction display mode")
expect(ns.RunSearch("Linen Cloth") == true and H.count("auction display mode") == modeSets, "a search on the buy tab leaves the tab of the game's window alone")
expect(ns.RemoveSearch("COPPER ORE") == true and #ns.ShoppingList() == 1, "a search is removed by its text")
-- A link whose colour is the name of a quality colour, as newer clients write it.
expect(ns.AddSearch("|cnIQ1:|Hitem:2770::::::::20:::::|h[Copper Ore]|h|r") == true and ns.ShoppingList()[1] == "Copper Ore",
  "a link with a quality colour name becomes the name of the item, got " .. tostring(ns.ShoppingList()[1]))
expect(ns.RemoveSearch("Copper Ore") == true and #ns.ShoppingList() == 1, "the search from the link is removed again")
-- A link that is longer than a saved search can be: the name is what counts against the limit.
local longLink = "|cffffffff|Hitem:6660::::::::20:::::|h[Julie's Dagger of the Whale]|h|r"
expect(#longLink > 60 and ns.AddSearch(longLink) == true and ns.ShoppingList()[1] == "Julie's Dagger of the Whale",
  "a link of more than 60 characters becomes the name of the item, got " .. tostring(ns.ShoppingList()[1]))
expect(ns.RemoveSearch("Julie's Dagger of the Whale") == true and #ns.ShoppingList() == 1, "the search from the long link is removed again")

-- The value of the bags: 32 Linen Cloth at 140 and 8 Chunk of Boar Meat at 35.
local auction, vendor, items = ns.BagValue()
expect(auction == 32 * 140 + 8 * 35, "the bags are worth 4760 at the auction house, got " .. tostring(auction))
expect(vendor == 32 * 13 + 8 * 4 + 5 * 1 + 7, "the bags are worth 460 at a vendor, got " .. tostring(vendor))
expect(#items == 2 and items[1].itemID == 2589, "the most valuable item of the bags is Linen Cloth")
T.slash("/fah", "bags")

-- The ledger: one sale in the mail, read once however often the mailbox opens.
T.fire("MAIL_SHOW")
T.advance(2)
local ledger = ns.Ledger()
expect(#ledger == 1 and ledger[1].kind == "sale" and ledger[1].amount == 950 and ledger[1].cut == 50, "the sale of 1000 with a cut of 50 is in the ledger as 950")
expect(ledger[1].name == "Linen Cloth" and ledger[1].count == 20 and ledger[1].who == "Buyer", "the ledger has the item, the count and the buyer")
T.fire("MAIL_INBOX_UPDATE")
T.advance(2)
T.fire("MAIL_SHOW")
T.advance(2)
expect(#ns.Ledger() == 1, "the same mail is in the ledger once")
local sales, earned, buys, spent = ns.LedgerSummary(7)
expect(sales == 1 and earned == 950 and buys == 0 and spent == 0, "the totals of the week are one sale of 950")
T.slash("/fah", "ledger")
T.slash("/fah", "ledger text")
-- The ledger filters: by date and by item name.
ns.SetLedgerFilter("all", 1, "linen")
expect(#ns.LedgerShown() == 1, "the sale of Linen Cloth is in the last 24 hours and matches \"linen\"")
ns.SetLedgerFilter("all", nil, "copper")
expect(#ns.LedgerShown() == 0, "no line matches \"copper\"")
ns.SetLedgerFilter("buy", nil, "")
expect(#ns.LedgerShown() == 0, "there are no purchases")
ns.SetLedgerFilter("all", nil, "")
expect(#ns.LedgerShown() == 1, "without filters the ledger shows its one line")
-- The ledger window remembers where the player dragged it.
local ledgerFrame = ForeverAuctionsLedgerFrame
expect(ledgerFrame ~= nil and ledgerFrame:IsShown() and ForeverAuctionsDB.options.ledgerWindow == nil, "the ledger window is open and has no saved position yet")
if ledgerFrame then
  ledgerFrame:GetScript("OnDragStop")(ledgerFrame)
  expect(type(ForeverAuctionsDB.options.ledgerWindow) == "table" and ForeverAuctionsDB.options.ledgerWindow.point ~= nil, "the end of a drag saves the position of the ledger window")
  ns.ResetLedgerPosition()
  expect(ForeverAuctionsDB.options.ledgerWindow == nil, "the reset forgets the position of the ledger window")
end

-- The price window and its deals view.
T.slash("/fah", "")
T.advance(2)
-- The filters of the price window: Linen Cloth at 140 and Chunk of Boar Meat at 35, both common trade goods.
local function shownIDs()
  local ids = ns.HistoryShown()
  table.sort(ids)
  return table.concat(ids, ",")
end
expect(shownIDs() == "769,2589", "without filters the window shows both items, got " .. shownIDs())
ns.SetHistoryFilter("minPrice", 100)
expect(shownIDs() == "2589", "a lowest price of 100 leaves Linen Cloth, got " .. shownIDs())
ns.SetHistoryFilter("maxPrice", 120)
expect(shownIDs() == "", "a price range of 100 to 120 leaves nothing, got " .. shownIDs())
ns.ClearHistoryFilters()
ns.SetHistoryFilter("class", 7)
expect(shownIDs() == "769,2589", "both items are of item class 7, got " .. shownIDs())
ns.SetHistoryFilter("class", 2)
expect(shownIDs() == "", "neither item is a weapon (class 2), got " .. shownIDs())
ns.ClearHistoryFilters()
ns.SetHistoryFilter("quality", 2)
expect(shownIDs() == "", "neither item is uncommon or better, got " .. shownIDs())
ns.SetHistoryFilter("quality", 1)
expect(shownIDs() == "769,2589", "both items are common or better, got " .. shownIDs())
ns.ClearHistoryFilters()
ns.SetHistoryFilter("seenWithin", 3600)
expect(shownIDs() == "769,2589", "both items were seen in the last hour, got " .. shownIDs())
ns.SetHistoryFilter("watched", true)
expect(shownIDs() == "" and ns.HistoryFilterSummary():find("price alert"), "no item has a price alert now, got " .. shownIDs())
ns.SetWatch(769, 20)
ns.SetHistoryFilter("watched", true)
expect(shownIDs() == "769", "only the item with a price alert is shown, got " .. shownIDs())
ns.SetWatch(769, nil)
ns.ClearHistoryFilters()
expect(shownIDs() == "769,2589" and ns.HistoryFilterSummary() == "", "clearing the filters shows both items again")
T.slash("/fah", "deals")
T.advance(2)
T.slash("/fah", "price " .. linen)
expect(T.printed("%-day average"), "/fah price prints the stored price and the average")

-- The sell helper: the price field gets the undercut of the lowest other seller (150).
T.advance(1)
-- A commodity is in the sell form: the other sellers have 145 and 175, the own auction 160.
local fillButton
for _, frame in ipairs(H.frames) do
  local panel = H.state(frame).parent
  if panel and panel.sellFrame == AuctionHouseFrame.CommoditiesSellFrame and panel.button == frame then
    fillButton = frame
  end
end
expect(fillButton ~= nil and fillButton:IsShown(), "the sell form of a commodity has the button that fills the price")
if fillButton then
  expect(fillButton:GetText() == "Undercut: " .. ns.Money(144), "the button offers the undercut of the lowest other seller, got " .. tostring(fillButton:GetText()))
  local before = H.count("price filled")
  H.click(fillButton, "LeftButton", false)
  expect(H.count("price filled") == before + 1 and H.did[#H.did][2] == 144, "a click writes 144 into the price field, got " .. tostring(H.did[#H.did][2]))
end
-- The functions that need a click of the player (buy, post, cancel) and the mail and profession
-- functions are not in the stand-in: this scenario stands in for them and notes each call.
local calls = {}
local function note(name)
  return function(...)
    calls[#calls + 1] = { name, ... }
  end
end
local function called(name)
  local n, last = 0, nil
  for _, call in ipairs(calls) do
    if call[1] == name then
      n, last = n + 1, call
    end
  end
  return n, last
end

-- Cancel undercut: the own auction at 160 is above the stored 140.
C_AuctionHouse.CanCancelAuction = function() return true end
C_AuctionHouse.CancelAuction = note("cancel")
expect(ns.CancelNextUndercut() == true and select(2, called("cancel"))[2] == 1, "the undercut auction (ID 1) is cancelled")

-- Quick buy: a price alert at 150 takes the 20 Linen Cloth at 145 of the other seller, not the own 5 at 160.
C_AuctionHouse.StartCommoditiesPurchase = note("start purchase")
C_AuctionHouse.ConfirmCommoditiesPurchase = note("confirm purchase")
C_AuctionHouse.CancelCommoditiesPurchase = note("cancel purchase")
ns.SetWatch(2589, 150)
T.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
local quantity, total = ns.QuickBuyOffer(2589)
expect(quantity == 20 and total == 2900, "quick buy offers 20 for 2900, got " .. tostring(quantity) .. " for " .. tostring(total))
ns.QuickBuyClick()
expect(called("start purchase") == 1 and ns.QuickBuyState() == "waiting", "the first click asks the game for the final price")
T.fire("COMMODITY_PRICE_UPDATED", 145, 2900)
expect(ns.QuickBuyState() == "confirm", "the final price at the target waits for a second click")
expect(called("confirm purchase") == 0, "nothing is bought before the second click")
ns.QuickBuyClick()
expect(called("confirm purchase") == 1 and select(2, called("confirm purchase"))[3] == 20, "the second click buys the 20")
T.fire("COMMODITY_PURCHASE_SUCCEEDED")
expect(ns.QuickBuyState() == "idle" and T.printed("bought 20"), "the purchase is reported")
ns.QuickBuyClick()
T.fire("COMMODITY_PRICE_UPDATED", 180, 3600)
expect(ns.QuickBuyState() == "idle" and called("cancel purchase") == 1 and called("confirm purchase") == 1,
  "a final price above the target cancels the purchase")
ns.SetWatch(2589, nil)

-- Crafting cost: a Bolt of Linen Cloth (2996) from 2 Linen Cloth.
C_TradeSkillUI = C_TradeSkillUI or {}
C_TradeSkillUI.GetRecipeInfo = function(recipeID) return { recipeID = recipeID, learned = recipeID == 2963 } end
C_TradeSkillUI.GetRecipeSchematic = function(recipeID)
  return { recipeID = recipeID, outputItemID = 2996, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
    { reagentType = 1, required = true, quantityRequired = 2, reagents = { { itemID = 2589 } } },
    { reagentType = 0, required = false, quantityRequired = 1, reagents = { { itemID = 769 } } },
  } }
end
-- The profession window says which recipe the player selects; a recipe not learned is left out.
EventRegistry:TriggerEvent("ProfessionsRecipeListMixin.Event.OnRecipeSelected", { recipeID = 9999 })
expect(ns.CraftCost(2996) == nil, "a recipe that is not learned is not stored")
EventRegistry:TriggerEvent("ProfessionsRecipeListMixin.Event.OnRecipeSelected", { recipeID = 2963 })
ns.Record(2996, 400)
local lowLinen = ns.Lookup(2589).price
local cost, complete = ns.CraftCost(2996)
expect(cost == 2 * lowLinen and complete, "the bolt costs two Linen Cloth, the optional reagent is left out, got " .. tostring(cost))
expect(ns.CraftProfit(2996) == 380 - 2 * lowLinen, "the profit is 95% of 400 minus the reagents, got " .. tostring(ns.CraftProfit(2996)))
expect(ns.CraftCost(769) == nil, "an item without a known recipe has no crafting cost")

-- Post queue: the Linen Cloth of two stacks is one post of 32; the Boar Meat is the second.
C_AuctionHouse.GetItemCommodityStatus = function() return 2 end
C_AuctionHouse.IsSellItemValid = function() return true end
C_AuctionHouse.MakeItemKey = function(itemID) return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end
C_AuctionHouse.SendSearchQuery = note("search")
C_AuctionHouse.PostCommodity = function(...)
  note("post")(...)
  return false
end
C_AuctionHouse.PostItem = note("post item")
expect(ns.BuildPostQueue() == 2, "two items of the bags have a price and can be posted, got " .. tostring(#ns.PostQueue()))
local queue = ns.PostQueue()
expect(queue[1].itemID == 2589 and queue[1].quantity == 32, "Linen Cloth is one entry of 32")
ns.PostClick()
expect(called("search") == 1 and called("post") == 0, "the first click searches, it does not post")
T.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
local _, _, postState, postPrice = ns.PostQueue()
expect(postState == "ready" and postPrice == 144, "the post price is the undercut of the lowest other seller (144), got " .. tostring(postPrice))
ns.PostClick()
local _, postCall = called("post")
expect(postCall and postCall[3] == 2 and postCall[4] == 32 and postCall[5] == 144, "the second click posts 32 at 144 for 24 hours")
T.fire("AUCTION_HOUSE_AUCTION_CREATED", 7)
expect(select(2, ns.PostQueue()) == 2, "after the post the queue goes to the next item")
ns.PostSkip()
expect(select(2, ns.PostQueue()) == 3, "Skip leaves an item")

-- Open auction mail: the ledger reads the invoice, then the gold is taken.
MailFrame:Show()
T.fire("MAIL_SHOW")
T.advance(1)
ns.OpenAuctionMail()
T.advance(2)
expect(H.count("take inbox money") == 1 and H.count("loot mail") == 0, "the gold of the auction mail is taken")
expect(#ns.Ledger() == 1 and not ns.MailRunning(), "the sale is in the ledger once, and the opening is done")
T.slash("/fah", "mail")
T.advance(2)

-- Export and import of the prices.
local text, exported = ns.ExportPrices()
expect(text:sub(1, 5) == "FAH1:" and exported >= 3 and text:find("2996,400,"), "the export holds every stored price")
expect(ns.ImportPrices("hello") == nil, "a text that is not an export is refused")
expect(ns.ImportPrices("FAH1:1,2,x") == nil, "a damaged export is refused")
wipe(ns.Prices())
local read, changed = ns.ImportPrices(text)
expect(read == exported and changed == exported and ns.Lookup(2996).price == 400, "the import brings every price back")
local _, changedAgain = ns.ImportPrices(text)
expect(changedAgain == 0, "an import of the same prices changes nothing")
T.slash("/fah", "export")
T.slash("/fah", "import")

-- /fah clear deletes the stored prices only with "yes".
T.slash("/fah", "clear")
expect(ns.Lookup(2589) ~= nil and T.printed("Type /fah clear yes"), "/fah clear alone deletes nothing and says how to delete")
T.slash("/fah", "clear yes")
expect(ns.Lookup(2589) == nil and ns.Lookup(769) == nil, "/fah clear yes deletes the stored prices")

-- An empty realm name from the game must find the same record, not make a new one.
local faction = UnitFactionGroup("player") or "Neutral"
local realmRecord = ns.Realm()
expect(ns.RealmName() == "TestRealm" and ns.RealmKey() == "TestRealm-" .. faction, "the realm name comes from the game while the game gives one")
local realGetRealmName = GetRealmName
GetRealmName = function() return "" end
expect(ns.RealmName() == "TestRealm" and ns.Realm() == realmRecord, "with an empty realm name the saved name is used, and the same record is found")
expect(ForeverAuctionsDB.realms["-" .. faction] == nil, "an empty realm name does not make a record of its own")
ForeverAuctionsDB.realmOf = nil
expect(ns.Realm() == realmRecord, "without a saved name, the one realm of this faction in the records is found")
GetRealmName = realGetRealmName
expect(ns.Realm() == realmRecord, "the realm of the game is found again when the game gives its name")
