local _, ns = ...

-- Full scan: one request for every listing of the auction house (C_AuctionHouse.ReplicateItems).
-- The server accepts it once per 15 minutes per account and ignores a request sent sooner without any answer,
-- so the time of every request is saved and the button stays disabled until the 15 minutes are over.

local COOLDOWN = 15 * 60
local ANSWER_TIMEOUT = 30
local READY_WAIT = 10
local SLICE_MS = 6 -- time per frame spent on reading or storing
local CHUNK = 200 -- listings between two looks at the clock

local IDLE, WAITING, READING, STORING = 0, 1, 2, 3

local state = IDLE
local token = 0 -- changes whenever a scan ends, so its scheduled steps stop
local houseOpen = false
local noAnswer = false
local startedAt = 0
local total, read, listings, seen = 0, 0, 0, 0
local lows, order, seenItems
local note, noteUntil -- short text shown beside the button

local events = CreateFrame("Frame")
local clock = debugprofilestop or function()
  return GetTime() * 1000
end

local function supported()
  return C_AuctionHouse and C_AuctionHouse.ReplicateItems and C_AuctionHouse.GetNumReplicateItems
    and C_AuctionHouse.GetReplicateItemInfo and C_Timer and C_Timer.After and true or false
end

local function duration(seconds)
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function showNote(text)
  note, noteUntil = text, GetTime() + 10
end

-- Seconds until the server accepts the next full scan, 0 if it does now.
function ns.ScanCooldown()
  local last = ForeverAuctionsDB and ForeverAuctionsDB.scan and ForeverAuctionsDB.scan.requested
  if type(last) ~= "number" then
    return 0
  end
  local left = COOLDOWN - (time() - last)
  if left <= 0 or left > COOLDOWN then
    return 0
  end
  return left
end

function ns.ScanRunning()
  return state ~= IDLE
end

local function finish(text)
  state = IDLE
  token = token + 1
  noAnswer = false
  lows, order, seenItems = nil, nil, nil
  events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  if text then
    ns.Print(text)
  end
  if ns.RefreshHistory then
    ns.RefreshHistory()
  end
end

-- Writes the lowest prices to the price store, a slice per frame. This no longer needs the auction house.
local function store(id, position, interrupted)
  if id ~= token or state ~= STORING then
    return
  end
  local started = clock()
  while position <= #order do
    local stop = math.min(position + CHUNK - 1, #order)
    for i = position, stop do
      local itemID = order[i]
      ns.Record(itemID, lows[itemID])
    end
    position = stop + 1
    if clock() - started >= SLICE_MS then
      break
    end
  end
  if position <= #order then
    C_Timer.After(0, function()
      store(id, position, interrupted)
    end)
    return
  end
  local stored = #order
  ForeverAuctionsDB.scan.finished = time()
  local text
  if interrupted then
    text = string.format("full scan stopped because the auction house closed: %d of %d listings read, %d items seen, %d prices stored. Prices of this scan can be higher than the real lowest price.",
      read, total, seen, stored)
    showNote(stored .. " prices stored (scan stopped)")
  else
    text = string.format("full scan finished: %d listings read, %d items seen, %d prices stored in %.1f seconds.",
      listings, seen, stored, GetTime() - startedAt)
    showNote(stored .. " prices stored")
  end
  finish(text)
end

local function beginStore(interrupted)
  token = token + 1
  state = STORING
  store(token, 1, interrupted)
end

-- Reads the listings, a slice per frame. Indexes start at 0.
-- GetReplicateItemInfo returns the stack size as value 3, the buyout of the whole stack as value 10 and the item ID as value 17.
local function readSlice(id, index)
  if id ~= token or state ~= READING then
    return
  end
  local getInfo = C_AuctionHouse.GetReplicateItemInfo
  local started = clock()
  while index < total do
    local stop = math.min(index + CHUNK, total)
    for i = index, stop - 1 do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = getInfo(i)
      if type(itemID) == "number" and itemID > 0 then
        if not seenItems[itemID] then
          seenItems[itemID] = true
          seen = seen + 1
        end
        if type(buyout) == "number" and buyout > 0 then
          if type(count) ~= "number" or count < 1 then
            count = 1
          end
          local unit = math.floor(buyout / count)
          if unit > 0 then
            listings = listings + 1
            local low = lows[itemID]
            if not low then
              order[#order + 1] = itemID
              lows[itemID] = unit
            elseif unit < low then
              lows[itemID] = unit
            end
          end
        end
      end
    end
    index = stop
    read = index
    if clock() - started >= SLICE_MS then
      break
    end
  end
  if index < total then
    C_Timer.After(0, function()
      readSlice(id, index)
    end)
  else
    beginStore(false)
  end
end

local function onListReady()
  if state ~= WAITING then
    return
  end
  -- The event fires again while the client loads item data. The first one means the list is complete.
  events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  total = C_AuctionHouse.GetNumReplicateItems() or 0
  if type(total) ~= "number" or total <= 0 then
    showNote("No listings")
    finish("full scan finished: the auction house has no listings.")
    return
  end
  state = READING
  read, listings, seen = 0, 0, 0
  lows, order, seenItems = {}, {}, {}
  readSlice(token, 0)
end

local function send(id, waited)
  if id ~= token or state ~= WAITING then
    return
  end
  -- Right after the auction house opens the client is busy with its own requests, and a request sent then can get lost.
  local ready = C_AuctionHouse.IsThrottledMessageSystemReady
  if ready and waited < READY_WAIT and not ready() then
    C_Timer.After(0.5, function()
      send(id, waited + 0.5)
    end)
    return
  end
  ForeverAuctionsDB.scan.requested = time()
  startedAt = GetTime()
  local ok = pcall(C_AuctionHouse.ReplicateItems)
  if not ok then
    showNote("Scan failed")
    finish("the full scan request failed.")
    return
  end
  C_Timer.After(ANSWER_TIMEOUT, function()
    if id == token and state == WAITING then
      noAnswer = true
      ns.Print("the server has not answered the full scan. An answer that arrives while the auction house is open is still used.")
    end
  end)
end

-- Starts a full scan. Returns true if the request is on its way.
function ns.StartScan()
  if not ForeverAuctionsDB then
    return false
  end
  if not supported() then
    ns.Print("this game client has no full scan.")
    return false
  end
  if state ~= IDLE then
    ns.Print("a full scan is already running.")
    return false
  end
  if not houseOpen then
    ns.Print("open the auction house first.")
    return false
  end
  local wait = ns.ScanCooldown()
  if wait > 0 then
    ns.Print("the next full scan is possible in " .. duration(wait) .. ".")
    return false
  end
  if not ns.SafeRegister(events, "REPLICATE_ITEM_LIST_UPDATE") then
    ns.Print("this game client has no full scan.")
    return false
  end
  token = token + 1
  state = WAITING
  noAnswer = false
  read, total = 0, 0
  ns.Print("full scan started.")
  send(token, 0)
  return true
end

local function onHouseClosed()
  if state == READING then
    -- Keep what was read so far.
    beginStore(true)
  elseif state == WAITING then
    showNote("Scan stopped")
    finish("full scan stopped because the auction house closed. The next scan is possible in " .. duration(ns.ScanCooldown()) .. ".")
  end
end

-- Text for the status line beside the button.
local function statusText()
  if state == WAITING then
    return noAnswer and "No answer yet" or "Waiting for the server"
  elseif state == READING then
    return string.format("Reading %d of %d (%d%%)", read, total, total > 0 and math.floor(read / total * 100) or 0)
  elseif state == STORING then
    return "Storing prices"
  end
  if note and GetTime() < noteUntil then
    return note
  end
  local wait = ns.ScanCooldown()
  if wait > 0 then
    return "Next scan in " .. duration(wait)
  end
  local finished = ForeverAuctionsDB and ForeverAuctionsDB.scan and ForeverAuctionsDB.scan.finished
  if type(finished) == "number" then
    return "Last scan " .. ns.Age(finished)
  end
  return ""
end

local holder, button, status

local function updateButton()
  if not holder then
    return
  end
  status:SetText(statusText())
  button:SetEnabled(state == IDLE and ns.ScanCooldown() <= 0 and supported())
end

local function showButtonTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText("Full scan", 1, 1, 1)
  GameTooltip:AddLine("Reads every listing of the auction house and stores the lowest price of each item. The server allows this once every 15 minutes.", nil, nil, nil, true)
  local wait = ns.ScanCooldown()
  if state ~= IDLE then
    GameTooltip:AddLine("A scan is running.", 1, 1, 1, true)
  elseif wait > 0 then
    GameTooltip:AddLine("Next scan in " .. duration(wait) .. ".", 1, 1, 1, true)
  end
  GameTooltip:Show()
end

-- The auction house window loads on demand: the button is made the first time it opens.
-- It sits below the bottom right corner of the window, where no other control is.
local function createButton()
  local house = AuctionHouseFrame
  holder = CreateFrame("Frame", nil, house)
  holder:SetSize(320, 22)
  holder:SetPoint("TOPRIGHT", house, "BOTTOMRIGHT", -4, -4)

  button = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
  button:SetSize(100, 22)
  button:SetPoint("RIGHT")
  button:SetText("Full scan")
  if button.SetMotionScriptsWhileDisabled then
    button:SetMotionScriptsWhileDisabled(true)
  end
  button:SetScript("OnClick", function()
    ns.StartScan()
    updateButton()
  end)
  button:SetScript("OnEnter", showButtonTooltip)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  status = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  status:SetPoint("RIGHT", button, "LEFT", -8, 0)
  status:SetJustifyH("RIGHT")

  local elapsed = 0
  holder:SetScript("OnUpdate", function(_, seconds)
    elapsed = elapsed + seconds
    if elapsed >= 0.2 then
      elapsed = 0
      updateButton()
    end
  end)
end

-- The button can be turned off. /fah scan works without it.
ns.OnOptionChanged(function(key, value)
  if key == "scanButton" and holder then
    holder:SetShown(value)
  end
end)

-- Time of the last full scan request, or nil.
function ns.LastScanTime()
  local last = ForeverAuctionsDB and ForeverAuctionsDB.scan and ForeverAuctionsDB.scan.requested
  return type(last) == "number" and last or nil
end

ns.SafeRegister(events, "AUCTION_HOUSE_SHOW")
ns.SafeRegister(events, "AUCTION_HOUSE_CLOSED")
events:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_HOUSE_SHOW" then
    houseOpen = true
    if not holder and AuctionHouseFrame and supported() then
      local ok = pcall(createButton)
      if not ok then
        holder = nil
      end
    end
    if holder then
      holder:SetShown(ns.GetOption("scanButton"))
    end
    updateButton()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    houseOpen = false
    onHouseClosed()
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    onListReady()
  end
end)
