local _, ns = ...

-- Undercut check: compares the player's own auctions with the stored lowest prices.
--
-- The game loads the list of own auctions when the player opens the Auctions tab. This file sends
-- no request of its own. It reads the list when the game has it (OWNED_AUCTIONS_UPDATED) and says
-- in chat how many auctions are above the lowest price that the addon has seen.
--
-- The stored price of an item is the lowest price of all its variants. For equipment with different
-- item levels or suffixes, the lower price can be a different variant.

local ACTIVE = 0 -- Enum.AuctionStatus.Active
local lastSignature

local function supported()
  return C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions and C_AuctionHouse.GetOwnedAuctionInfo
end

-- Returns the list of own auctions with a lower stored price, and the number of active auctions.
-- Each one: { itemID, link, mine = own unit price, low = stored price, seen = time of the stored price }
function ns.UndercutAuctions()
  local undercut, active = {}, 0
  if not supported() then
    return undercut, active
  end
  for i = 1, C_AuctionHouse.GetNumOwnedAuctions() or 0 do
    local info = C_AuctionHouse.GetOwnedAuctionInfo(i)
    local itemID = info and info.itemKey and info.itemKey.itemID
    local mine = info and info.buyoutAmount
    if itemID and info.status == ACTIVE then
      active = active + 1
      local entry = type(mine) == "number" and mine > 0 and ns.Lookup(itemID)
      if entry and entry.price < mine then
        undercut[#undercut + 1] = { itemID = itemID, link = info.itemLink, mine = mine, low = entry.price, seen = entry.seen }
      end
    end
  end
  table.sort(undercut, function(a, b)
    if a.itemID ~= b.itemID then
      return a.itemID < b.itemID
    end
    return a.mine < b.mine
  end)
  return undercut, active
end

-- /fah mine
function ns.PrintMyAuctions()
  if not supported() then
    ns.Print("this game client has no list of own auctions for addons.")
    return
  end
  local ok, undercut, active = pcall(ns.UndercutAuctions)
  if not ok then
    ns.Print("your auctions cannot be read now.")
    return
  end
  if active == 0 then
    ns.Print("no active auctions known. Open the Auctions tab of the auction house first.")
    return
  end
  if #undercut == 0 then
    ns.Print(string.format("%d active auctions, none above the lowest price that is stored.", active))
    return
  end
  ns.Print(string.format("%d of your %d active auctions are above the lowest stored price:", #undercut, active))
  for _, auction in ipairs(undercut) do
    print(string.format("  %s: yours %s, lowest %s (seen %s)", auction.link or ns.ItemLabel(auction.itemID),
      ns.Money(auction.mine), ns.Money(auction.low), ns.Age(auction.seen)))
  end
  print("  Search for an item to see its price now. Cancel and post again on the Auctions tab.")
end

local function check()
  if not (ForeverAuctionsDB and ns.GetOption("undercutCheck")) then
    return
  end
  local ok, undercut, active = pcall(ns.UndercutAuctions)
  if not ok then
    return
  end
  -- The game sends the event several times for one list: one message per different result.
  local parts = { active }
  for _, auction in ipairs(undercut) do
    parts[#parts + 1] = auction.itemID .. ":" .. auction.mine .. ":" .. auction.low
  end
  local signature = table.concat(parts, ",")
  if signature == lastSignature then
    return
  end
  lastSignature = signature
  if #undercut > 0 then
    ns.Print(string.format("%d of your %d auctions are above the lowest stored price. Type /fah mine for the list.", #undercut, active))
  end
end

local events = CreateFrame("Frame")
ns.SafeRegister(events, "OWNED_AUCTIONS_UPDATED")
ns.SafeRegister(events, "AUCTION_HOUSE_CLOSED")
events:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_HOUSE_CLOSED" then
    lastSignature = nil -- the next visit reports again
  else
    check()
  end
end)
