local _, ns = ...

-- Records prices from whatever the player looks at in the auction house.
-- It sends no queries of its own, so it cannot hit the server's query throttle.

local function recordBrowse(results)
  if type(results) ~= "table" then
    return
  end
  -- One item ID can appear in several rows (item level or suffix variants). Keep the cheapest.
  local lows = {}
  for _, row in ipairs(results) do
    local itemID = row.itemKey and row.itemKey.itemID
    local price = row.minPrice
    if itemID and type(price) == "number" and price > 0 then
      if not lows[itemID] or price < lows[itemID] then
        lows[itemID] = price
      end
    end
  end
  for itemID, price in pairs(lows) do
    ns.Record(itemID, price)
  end
end

local function recordCommodity(itemID)
  local low
  for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
    local row = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    if row and row.unitPrice and row.unitPrice > 0 and (not low or row.unitPrice < low) then
      low = row.unitPrice
    end
  end
  ns.Record(itemID, low)
end

local function recordItem(itemKey)
  if type(itemKey) ~= "table" then
    return
  end
  local low
  for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
    local row = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
    local price = row and row.buyoutAmount
    if price and price > 0 and (not low or price < low) then
      low = price
    end
  end
  ns.Record(itemKey.itemID, low)
end

local frame = CreateFrame("Frame")
ns.SafeRegister(frame, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
ns.SafeRegister(frame, "AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
ns.SafeRegister(frame, "COMMODITY_SEARCH_RESULTS_UPDATED")
ns.SafeRegister(frame, "ITEM_SEARCH_RESULTS_UPDATED")

frame:SetScript("OnEvent", function(_, event, arg1)
  if not C_AuctionHouse or not ForeverAuctionsDB then
    return
  end
  if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    recordBrowse(C_AuctionHouse.GetBrowseResults())
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    recordBrowse(arg1)
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    recordCommodity(arg1)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    recordItem(arg1)
  end
end)
