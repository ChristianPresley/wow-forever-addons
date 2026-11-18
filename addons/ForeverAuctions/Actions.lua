local _, ns = ...

-- The actions panel below the shopping list: quick buy, the post queue and cancelling undercut auctions.
--
-- The game lets an addon buy, post and cancel only from a click of the player, one action per click.
-- So nothing here runs on its own: every button does one step, and a purchase takes two clicks, the
-- second one after the game has said the final price.

local DURATION = 2 -- 24 hours (1: 12 hours, 3: 48 hours)
local PURCHASE_TIMEOUT = 15
local POST_FLOOR = 0.5 -- the post queue refuses a price below half of the stored average
local WIDTH, HEIGHT = 214, 246

local panel
local refresh -- redraws the panel

local function supported(...)
  if not C_AuctionHouse then
    return false
  end
  for i = 1, select("#", ...) do
    if not C_AuctionHouse[select(i, ...)] then
      return false
    end
  end
  return true
end

local function itemName(itemID)
  local name = C_Item.GetItemInfo and C_Item.GetItemInfo(itemID)
  return type(name) == "string" and name or ("item " .. itemID)
end

---------------------------------------------------------------------------------------------------
-- Quick buy: the commodity of the last search, up to the target price. The target is the price
-- alert of the item, or else the deal price (the deal percentage of its average).

local buy = { state = "idle" } -- idle, waiting (for the final price), confirm, buying
local buyToken = 0

function ns.QuickBuyTarget(itemID)
  local target = ns.WatchTarget(itemID)
  if target then
    return target, "your price alert"
  end
  local entry, average, days = ns.Lookup(itemID)
  if entry and days and days >= 2 and average > 0 then
    return math.floor(average * ns.GetOption("dealPercent") / 100), "the deal price"
  end
  return nil
end

-- How many of the searched commodity other sellers offer at or below the target, and what they cost.
function ns.QuickBuyOffer(itemID)
  local target, source = ns.QuickBuyTarget(itemID)
  if not target or not supported("GetNumCommoditySearchResults", "GetCommoditySearchResultInfo") then
    return nil
  end
  local quantity, total, highest = 0, 0, 0
  for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0 do
    local row = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    local price, count = row and row.unitPrice, row and row.quantity
    if type(price) == "number" and type(count) == "number" and price > 0 and price <= target then
      local own = row.containsOwnerItem and type(row.numOwnerItems) == "number" and row.numOwnerItems or 0
      local others = count - own
      if others > 0 then
        quantity, total, highest = quantity + others, total + others * price, math.max(highest, price)
      end
    end
  end
  return quantity, total, target, source, highest
end

local function resetBuy(text)
  buy = { state = "idle", itemID = buy.itemID }
  buyToken = buyToken + 1
  if text then
    ns.Print(text)
  end
  if refresh then
    refresh()
  end
end

-- One click: the first one asks the game for the final price, the second one buys.
function ns.QuickBuyClick()
  if buy.state == "confirm" then
    buy.state = "buying"
    C_AuctionHouse.ConfirmCommoditiesPurchase(buy.itemID, buy.quantity)
    refresh()
    return
  end
  if buy.state ~= "idle" then
    return
  end
  local itemID = buy.itemID
  if not itemID or not supported("StartCommoditiesPurchase", "ConfirmCommoditiesPurchase", "CancelCommoditiesPurchase") then
    return
  end
  local quantity, total, target = ns.QuickBuyOffer(itemID)
  if not quantity or quantity == 0 then
    ns.Print("nothing is listed at or below the target price now.")
    return
  end
  buy = { state = "waiting", itemID = itemID, quantity = quantity, expected = total, target = target }
  buyToken = buyToken + 1
  local token = buyToken
  C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)
  C_Timer.After(PURCHASE_TIMEOUT, function()
    if token == buyToken and buy.state ~= "idle" then
      pcall(C_AuctionHouse.CancelCommoditiesPurchase)
      resetBuy("the auction house did not answer the purchase. Nothing was bought.")
    end
  end)
  refresh()
end

function ns.QuickBuyCancel()
  if buy.state == "waiting" or buy.state == "confirm" then
    pcall(C_AuctionHouse.CancelCommoditiesPurchase)
    resetBuy("purchase cancelled.")
  end
end

function ns.QuickBuyState()
  return buy.state, buy.quantity, buy.total
end

local function onPriceUpdated(unitPrice, totalPrice)
  if buy.state ~= "waiting" then
    return
  end
  -- The listings can be gone by now: the game then offers the next ones, at a higher price.
  if type(totalPrice) ~= "number" or totalPrice > buy.target * buy.quantity then
    pcall(C_AuctionHouse.CancelCommoditiesPurchase)
    resetBuy(string.format("the price rose to %s each, above the target of %s. Nothing was bought.",
      ns.Money(type(unitPrice) == "number" and unitPrice or 0), ns.Money(buy.target)))
    return
  end
  buy.state, buy.total = "confirm", totalPrice
  refresh()
end

---------------------------------------------------------------------------------------------------
-- Post queue: the items of the bags that have a stored price and can be sold. Each item takes two
-- clicks: a search for the price of now, then the post at the undercut of the lowest other seller.

local queue, queueIndex = {}, 1
local post = { state = "idle" } -- idle, searching, ready, confirm

local function locationOf(bag, slot)
  return ItemLocation and ItemLocation:CreateFromBagAndSlot(bag, slot)
end

-- Builds the queue from the bags. Commodities of one item are one entry for all their stacks.
function ns.BuildPostQueue()
  queue, queueIndex, post = {}, 1, { state = "idle" }
  local getInfo = C_Container and C_Container.GetContainerItemInfo
  if not (getInfo and ItemLocation and supported("GetItemCommodityStatus", "PostCommodity", "PostItem")) then
    return 0
  end
  local commodities = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = getInfo(bag, slot)
      if type(info) == "table" and type(info.itemID) == "number" and not info.isBound and ns.Lookup(info.itemID) then
        local location = locationOf(bag, slot)
        local valid = not C_AuctionHouse.IsSellItemValid or C_AuctionHouse.IsSellItemValid(location, false)
        if valid then
          local commodity = C_AuctionHouse.GetItemCommodityStatus(location) == 2
          if commodity and commodities[info.itemID] then
            local entry = commodities[info.itemID]
            entry.quantity = entry.quantity + (info.stackCount or 1)
          else
            local entry = { itemID = info.itemID, bag = bag, slot = slot, quantity = info.stackCount or 1, commodity = commodity }
            queue[#queue + 1] = entry
            if commodity then
              commodities[info.itemID] = entry
            end
          end
        end
      end
    end
  end
  if refresh then
    refresh()
  end
  return #queue
end

function ns.PostQueue()
  return queue, queueIndex, post.state, post.price
end

local function current()
  return queue[queueIndex]
end

local function nextInQueue()
  queueIndex = queueIndex + 1
  post = { state = "idle" }
  refresh()
end

-- The lowest unit price of other sellers in the search results of an entry, nil if none.
local function lowestOther(entry)
  local low
  if entry.commodity then
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(entry.itemID) or 0 do
      local row = C_AuctionHouse.GetCommoditySearchResultInfo(entry.itemID, i)
      local mine = row and row.containsOwnerItem and row.numOwnerItems and row.quantity and row.numOwnerItems >= row.quantity
      if row and not mine and type(row.unitPrice) == "number" and row.unitPrice > 0 then
        low = (not low or row.unitPrice < low) and row.unitPrice or low
      end
    end
  elseif post.itemKey then
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(post.itemKey) or 0 do
      local row = C_AuctionHouse.GetItemSearchResultInfo(post.itemKey, i)
      if row and not row.containsOwnerItem and type(row.buyoutAmount) == "number" and row.buyoutAmount > 0 then
        low = (not low or row.buyoutAmount < low) and row.buyoutAmount or low
      end
    end
  end
  return low
end

local function priceFound()
  local entry = current()
  if not entry or post.state ~= "searching" then
    return
  end
  local low = lowestOther(entry)
  local stored, average = ns.Lookup(entry.itemID)
  local price = low and ns.UndercutPrice(low) or (stored and stored.price)
  if not price then
    ns.Print(itemName(entry.itemID) .. ": no price known. Skipped.")
    nextInQueue()
    return
  end
  if average and average > 0 and price < average * POST_FLOOR then
    ns.Print(string.format("%s: %s is below half of the average (%s). Skipped; post it yourself if you want it.",
      itemName(entry.itemID), ns.Money(price), ns.Money(average)))
    nextInQueue()
    return
  end
  post.state, post.price, post.low = "ready", price, low
  refresh()
end

function ns.PostClick()
  local entry = current()
  if not entry then
    return
  end
  local location = locationOf(entry.bag, entry.slot)
  if not (C_Item.DoesItemExist(location) and C_Item.GetItemID(location) == entry.itemID) then
    ns.Print(itemName(entry.itemID) .. " is no longer in that bag slot. Skipped.")
    nextInQueue()
    return
  end
  if post.state == "idle" then
    post.state = "searching"
    if entry.commodity then
      C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(entry.itemID), {}, true)
    else
      post.itemKey = C_AuctionHouse.GetItemKeyFromItem(location)
      C_AuctionHouse.SendSearchQuery(post.itemKey, {}, true)
    end
    refresh()
  elseif post.state == "ready" then
    local needsConfirm
    if entry.commodity then
      needsConfirm = C_AuctionHouse.PostCommodity(location, DURATION, entry.quantity, post.price)
    else
      needsConfirm = C_AuctionHouse.PostItem(location, DURATION, entry.quantity, nil, post.price * entry.quantity)
    end
    if needsConfirm then
      post.state = "confirm" -- the game warns about the price; a second click posts anyway
    else
      post.state = "posting"
      local posted = entry
      C_Timer.After(10, function()
        if post.state == "posting" and current() == posted then
          post.state = "ready" -- no answer: the player can try again or skip
          ns.Print(itemName(posted.itemID) .. ": the auction house did not confirm the post.")
          refresh()
        end
      end)
    end
    refresh()
  elseif post.state == "confirm" then
    if entry.commodity then
      C_AuctionHouse.ConfirmPostCommodity(location, DURATION, entry.quantity, post.price)
    else
      C_AuctionHouse.ConfirmPostItem(location, DURATION, entry.quantity, nil, post.price * entry.quantity)
    end
    post.state = "posting"
    refresh()
  end
end

function ns.PostSkip()
  if current() then
    nextInQueue()
  end
end

---------------------------------------------------------------------------------------------------
-- Cancel undercut: one auction per click, from the list of /fah mine.

function ns.CancelNextUndercut()
  if not supported("CancelAuction") then
    return false
  end
  local undercut = ns.UndercutAuctions()
  for _, auction in ipairs(undercut) do
    local id = auction.auctionID
    if type(id) == "number" and (not C_AuctionHouse.CanCancelAuction or C_AuctionHouse.CanCancelAuction(id)) then
      C_AuctionHouse.CancelAuction(id)
      ns.Print(string.format("cancelled %s at %s (lowest %s). The deposit is not returned.",
        auction.link or ns.ItemLabel(auction.itemID), ns.Money(auction.mine), ns.Money(auction.low)))
      return true
    end
  end
  ns.Print("no undercut auction can be cancelled now. Open the Auctions tab first.")
  return false
end

---------------------------------------------------------------------------------------------------
-- Panel

local function sectionTitle(text, y)
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, y)
  title:SetText(text)
  return title
end

local function line(y)
  local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT", 10, y)
  text:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
  text:SetJustifyH("LEFT")
  return text
end

local function button(text, width, tip)
  local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  if b.SetMotionScriptsWhileDisabled then
    b:SetMotionScriptsWhileDisabled(true)
  end
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self:GetText() or text, 1, 1, 1)
    GameTooltip:AddLine(tip, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  return b
end

local function draw()
  if not panel then
    return
  end
  -- Quick buy
  local itemID = buy.itemID
  if buy.state == "confirm" then
    panel.buyText:SetText(string.format("%d %s for %s in all.", buy.quantity, itemName(itemID), ns.Money(buy.total)))
    panel.buyButton:SetText("Confirm: pay " .. ns.Money(buy.total))
    panel.buyButton:SetEnabled(true)
  elseif buy.state == "waiting" or buy.state == "buying" then
    panel.buyText:SetText(buy.state == "waiting" and "Asking for the final price..." or "Buying...")
    panel.buyButton:SetEnabled(false)
  elseif itemID then
    local quantity, total, target, source = ns.QuickBuyOffer(itemID)
    if not target then
      panel.buyText:SetText(itemName(itemID) .. ": no target price. Set a price alert with /fah watch.")
      panel.buyButton:SetText("Quick buy")
      panel.buyButton:SetEnabled(false)
    else
      panel.buyText:SetText(string.format("%s at %s or less (%s).", itemName(itemID), ns.Money(target), source))
      panel.buyButton:SetText(quantity > 0 and string.format("Buy %d for %s", quantity, ns.Money(total)) or "None at that price")
      panel.buyButton:SetEnabled(quantity > 0)
    end
  else
    panel.buyText:SetText("Search for a commodity to buy it quickly.")
    panel.buyButton:SetText("Quick buy")
    panel.buyButton:SetEnabled(false)
  end
  panel.buyCancel:SetShown(buy.state == "confirm" or buy.state == "waiting")

  -- Post queue
  local entry = current()
  if #queue == 0 then
    panel.postText:SetText("Fill the queue with the items of your bags that have a price.")
    panel.postButton:SetText("Fill the queue")
  elseif not entry then
    panel.postText:SetText("The queue is done.")
    panel.postButton:SetText("Fill the queue")
  else
    local count = entry.quantity > 1 and (entry.quantity .. " ") or ""
    panel.postText:SetText(string.format("%d of %d: %s%s", queueIndex, #queue, count, itemName(entry.itemID)))
    if post.state == "idle" then
      panel.postButton:SetText("Search the price")
    elseif post.state == "searching" then
      panel.postButton:SetText("Searching...")
    elseif post.state == "ready" then
      panel.postButton:SetText("Post at " .. ns.Money(post.price))
    elseif post.state == "confirm" then
      panel.postButton:SetText("Confirm the post")
    else
      panel.postButton:SetText("Posting...")
    end
  end
  panel.postButton:SetEnabled(post.state ~= "searching" and post.state ~= "posting")
  panel.postSkip:SetEnabled(entry ~= nil)

  -- Cancel
  local undercut, active = ns.UndercutAuctions()
  panel.cancelText:SetText(active > 0 and string.format("%d of %d auctions above the lowest stored price.", #undercut, active)
    or "Open the Auctions tab to check your auctions.")
  panel.cancelButton:SetEnabled(#undercut > 0)
end

refresh = function()
  if panel and panel:IsShown() then
    draw()
  end
end

local function createPanel()
  local house = AuctionHouseFrame
  panel = CreateFrame("Frame", nil, house)
  panel:SetSize(WIDTH, HEIGHT)
  panel:SetPoint("TOPLEFT", house, "TOPRIGHT", 2, -370)
  panel:EnableMouse(true)

  local background = panel:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.04, 0.04, 0.04, 0.92)

  sectionTitle("Quick buy", -8)
  panel.buyText = line(-26)
  panel.buyButton = button("Quick buy", WIDTH - 20, "First click: the game says the final price. Second click: buy. Nothing is bought above the target price.")
  panel.buyButton:SetPoint("TOPLEFT", 10, -54)
  panel.buyButton:SetScript("OnClick", ns.QuickBuyClick)
  panel.buyCancel = button("x", 22, "Cancel this purchase.")
  panel.buyCancel:SetPoint("LEFT", panel.buyButton, "RIGHT", -22, 0)
  panel.buyCancel:SetScript("OnClick", ns.QuickBuyCancel)

  sectionTitle("Post queue", -86)
  panel.postText = line(-104)
  panel.postButton = button("Fill the queue", 140, "Each item takes two clicks: a search for the price of now, then the post at the undercut of the lowest other seller, for 24 hours.")
  panel.postButton:SetPoint("TOPLEFT", 10, -132)
  panel.postButton:SetScript("OnClick", function()
    if not current() then
      local count = ns.BuildPostQueue()
      if count == 0 then
        ns.Print("no item in your bags has a stored price and can be sold.")
      end
    else
      ns.PostClick()
    end
    draw()
  end)
  panel.postSkip = button("Skip", WIDTH - 154, "Leave this item and go to the next one.")
  panel.postSkip:SetPoint("LEFT", panel.postButton, "RIGHT", 4, 0)
  panel.postSkip:SetScript("OnClick", ns.PostSkip)

  sectionTitle("Undercut auctions", -166)
  panel.cancelText = line(-184)
  panel.cancelButton = button("Cancel the next one", WIDTH - 20, "Cancels one of your auctions that are above the lowest stored price, per click. The deposit is not returned.")
  panel.cancelButton:SetPoint("TOPLEFT", 10, -214)
  panel.cancelButton:SetScript("OnClick", function()
    ns.CancelNextUndercut()
    draw()
  end)

  local elapsed = 0
  panel:SetScript("OnUpdate", function(_, seconds)
    elapsed = elapsed + seconds
    if elapsed >= 0.5 then
      elapsed = 0
      draw()
    end
  end)
end

ns.OnOptionChanged(function(key, value)
  if key == "actionsPanel" and panel then
    panel:SetShown(value)
  end
end)

local events = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
  "COMMODITY_PRICE_UPDATED", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_AUCTION_CREATED",
  "AUCTION_CANCELED" }) do
  ns.SafeRegister(events, event)
end
events:SetScript("OnEvent", function(_, event, arg1, arg2)
  if not ForeverAuctionsDB then
    return
  end
  if event == "AUCTION_HOUSE_SHOW" then
    if not panel and AuctionHouseFrame then
      if not pcall(createPanel) then
        if panel then
          panel:Hide()
        end
        panel = nil
      end
    end
    if panel then
      panel:SetShown(ns.GetOption("actionsPanel"))
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if buy.state ~= "idle" then
      resetBuy()
    end
    post = { state = "idle" }
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    if buy.state == "idle" then
      buy.itemID = arg1
    end
    local entry = current()
    if entry and entry.commodity and entry.itemID == arg1 then
      priceFound()
    end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    local entry = current()
    if entry and not entry.commodity and type(arg1) == "table" and arg1.itemID == entry.itemID then
      priceFound()
    end
  elseif event == "COMMODITY_PRICE_UPDATED" then
    onPriceUpdated(arg1, arg2)
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if buy.state == "buying" then
      resetBuy(string.format("bought %d %s for %s.", buy.quantity, itemName(buy.itemID), ns.Money(buy.total or 0)))
    end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    if buy.state ~= "idle" then
      resetBuy("the purchase failed. Nothing was bought.")
    end
  elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
    if post.state == "posting" then
      nextInQueue()
    end
  end
  refresh()
end)
