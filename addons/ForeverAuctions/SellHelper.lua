local _, ns = ...

-- Posting helper on the sell tabs of the auction house: shows the lowest known price of the item in the sell form
-- and a button that writes an undercut of it into the price field. It never posts an auction.

local SILVER = 100

-- False where the auction house only takes whole silver prices.
local function copperAllowed()
  local supports = C_AuctionHouse and C_AuctionHouse.SupportsCopperValues
  if not supports then
    return true
  end
  local ok, result = pcall(supports)
  return not ok or result ~= false
end

-- The price to post at for a lowest price, and whether it was rounded to whole silver.
function ns.UndercutPrice(low)
  local price = low - ns.GetOption("undercut")
  if copperAllowed() then
    return math.max(1, price), false
  end
  return math.max(SILVER, math.floor(price / SILVER) * SILVER), true
end

local function sameVariant(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return true
  end
  return a.itemID == b.itemID and (a.itemLevel or 0) == (b.itemLevel or 0) and (a.itemSuffix or 0) == (b.itemSuffix or 0)
end

-- Lowest unit price of other sellers, lowest price of the player's own auctions, number of result rows.
local function commodityPrices(itemID)
  local low, own
  local count = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
  for i = 1, count do
    local row = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    local price = row and row.unitPrice
    if type(price) == "number" and price > 0 then
      local mine = row.containsOwnerItem and type(row.numOwnerItems) == "number" and type(row.quantity) == "number"
        and row.numOwnerItems >= row.quantity
      if mine then
        own = (not own or price < own) and price or own
      else
        low = (not low or price < low) and price or low
      end
    end
  end
  return low, own, count
end

local function itemPrices(searchKey, ownKey)
  local low, own
  local count = C_AuctionHouse.GetNumItemSearchResults(searchKey) or 0
  for i = 1, count do
    local row = C_AuctionHouse.GetItemSearchResultInfo(searchKey, i)
    local price = row and row.buyoutAmount
    if type(price) == "number" and price > 0 and sameVariant(row.itemKey, ownKey) then
      if row.containsOwnerItem then
        own = (not own or price < own) and price or own
      else
        low = (not low or price < low) and price or low
      end
    end
  end
  return low, own, count
end

-- Reads the item of a sell form and the prices of the search the form started for it.
-- Returns itemID, low, own. itemID is nil while the form is empty.
local function readForm(frame, isCommodity)
  local location = frame.GetItem and frame:GetItem()
  if not (location and location.IsValid and location:IsValid()) then
    return nil
  end
  local itemID = C_Item.GetItemID(location)
  if type(itemID) ~= "number" then
    return nil
  end
  if isCommodity then
    local low, own = commodityPrices(itemID)
    return itemID, low, own
  end
  local searchKey = frame.listDisplayedItemKey
  if type(searchKey) ~= "table" then
    return itemID
  end
  local ownKey = C_AuctionHouse.GetItemKeyFromItem and C_AuctionHouse.GetItemKeyFromItem(location)
  local low, own = itemPrices(searchKey, ownKey)
  return itemID, low, own
end

local function update(panel)
  local ok, itemID, low, own = pcall(readForm, panel.sellFrame, panel.isCommodity)
  if not ok or not itemID then
    panel.text:SetText("")
    panel.button:Hide()
    panel.fill = nil
    return
  end

  local label, fill, action
  if own and (not low or own <= low) then
    label = "Your auction is the lowest: " .. ns.Money(own)
    fill, action = own, "Match"
  elseif low then
    label = "Lowest listed now: " .. ns.Money(low)
    fill, action = ns.UndercutPrice(low), "Undercut:"
  else
    local entry = ns.Lookup(itemID)
    if entry then
      label = "Not listed now. Stored price (" .. ns.Age(entry.seen) .. "): " .. ns.Money(entry.price)
      fill, action = ns.UndercutPrice(entry.price), "Undercut:"
    else
      label = "No price known for this item."
    end
  end

  panel.text:SetText(label)
  panel.fill = fill
  if fill then
    panel.button:SetText(action == "Match" and ("Match " .. ns.Money(fill)) or ("Undercut: " .. ns.Money(fill)))
    panel.button:Show()
  else
    panel.button:Hide()
  end
end

local function createPanel(sellFrame, isCommodity)
  local panel = CreateFrame("Frame", nil, sellFrame)
  panel.sellFrame = sellFrame
  panel.isCommodity = isCommodity
  panel:SetSize(320, 46)
  local post = sellFrame.PostButton
  if post then
    panel:SetPoint("TOP", post, "BOTTOM", 0, -14)
    -- The sell form has an overlay over all of it that takes the mouse. Its Post button is above that, and so is this panel.
    panel:SetFrameLevel(post:GetFrameLevel())
  else
    panel:SetPoint("BOTTOM", sellFrame, "BOTTOM", 0, 14)
    panel:SetFrameLevel(sellFrame:GetFrameLevel() + 20)
  end

  panel.text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  panel.text:SetPoint("TOP")
  panel.text:SetWidth(320)
  panel.text:SetJustifyH("CENTER")

  panel.button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.button:SetSize(220, 22)
  panel.button:SetPoint("BOTTOM")
  panel.button:Hide()
  panel.button:SetScript("OnClick", function()
    local input = sellFrame.PriceInput
    if panel.fill and input and input.SetAmount then
      input:SetAmount(panel.fill)
    end
  end)
  panel.button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Fill the price field", 1, 1, 1)
    GameTooltip:AddLine("Writes this price into the price field. The auction is not posted until you click the post button yourself.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  panel.button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- The form changes with the item put in, the search results and the options: a short poll covers all of them.
  local elapsed = 1
  panel:SetScript("OnUpdate", function(self, seconds)
    elapsed = elapsed + seconds
    if elapsed >= 0.3 then
      elapsed = 0
      update(self)
    end
  end)
  return panel
end

local installed = false

local function install()
  local house = AuctionHouseFrame
  if installed or not house or not (C_AuctionHouse and C_Item and C_Item.GetItemID) then
    return
  end
  if not (C_AuctionHouse.GetNumCommoditySearchResults and C_AuctionHouse.GetCommoditySearchResultInfo
    and C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetItemSearchResultInfo) then
    return
  end
  installed = true
  if house.CommoditiesSellFrame then
    pcall(createPanel, house.CommoditiesSellFrame, true)
  end
  if house.ItemSellFrame then
    pcall(createPanel, house.ItemSellFrame, false)
  end
end

local events = CreateFrame("Frame")
ns.SafeRegister(events, "AUCTION_HOUSE_SHOW")
events:SetScript("OnEvent", install)
