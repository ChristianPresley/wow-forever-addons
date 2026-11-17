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
-- /fah clear deletes the stored prices only with "yes".
T.slash("/fah", "clear")
expect(ns.Lookup(2589) ~= nil and T.printed("Type /fah clear yes"), "/fah clear alone deletes nothing and says how to delete")
T.slash("/fah", "clear yes")
expect(ns.Lookup(2589) == nil and ns.Lookup(769) == nil, "/fah clear yes deletes the stored prices")
