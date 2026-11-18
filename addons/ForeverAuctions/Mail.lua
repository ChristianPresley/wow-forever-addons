local _, ns = ...

-- Open auction mail: takes the money and the items of every sale and purchase mail in the inbox, one
-- mail at a time. The ledger reads the invoices first, so every sale and purchase is recorded before its
-- mail is gone. Other mail stays where it is, and so does mail with cash on delivery.

local STEP = 0.4 -- seconds between two mails, so the server keeps up
local WAIT_LIMIT = 30 -- steps to wait for a pending mail command before giving up

local running = false
local token = 0
local taken, money = 0, 0
local holder, button

local function freeBagSlots()
  local get = C_Container and C_Container.GetContainerNumFreeSlots
  if not get then
    return 1 -- unknown: let the server refuse
  end
  local free = 0
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local slots = get(bag)
    free = free + (type(slots) == "number" and slots or 0)
  end
  return free
end

-- A sale or a purchase: the mails with an invoice. Expired and cancelled auctions come back without
-- one and stay in the inbox.
local function isAuctionMail(index)
  local invoiceType = GetInboxInvoiceInfo and GetInboxInvoiceInfo(index)
  return invoiceType == "seller" or invoiceType == "buyer"
end

local function finish(text)
  running = false
  token = token + 1
  if C_Mail and C_Mail.SetOpeningAll then
    pcall(C_Mail.SetOpeningAll, false)
  end
  if text then
    ns.Print(text)
  end
  if button then
    button:SetText("Open auction mail")
  end
end

local function summary()
  return string.format("%d auction mails opened, %s taken.", taken, ns.Money(money))
end

-- One mail per step, from the last one up, so the indexes of the mails still to do stay the same.
local function step(id, index, waited)
  if id ~= token or not running then
    return
  end
  if C_Mail and C_Mail.IsCommandPending and C_Mail.IsCommandPending() then
    if waited >= WAIT_LIMIT then
      finish("the mailbox did not answer. " .. summary())
      return
    end
    C_Timer.After(STEP, function()
      step(id, index, waited + 1)
    end)
    return
  end
  ns.ReadLedgerMail()
  while index >= 1 do
    local _, _, _, _, cash, cod, _, itemCount, _, _, _, _, isGM = GetInboxHeaderInfo(index)
    local items = type(itemCount) == "number" and itemCount or 0
    cash = type(cash) == "number" and cash or 0
    if not isGM and (type(cod) ~= "number" or cod == 0) and (cash > 0 or items > 0) and isAuctionMail(index) then
      if items > 0 and freeBagSlots() == 0 then
        finish("your bags are full. " .. summary())
        return
      end
      if items > 0 and AutoLootMailItem then
        AutoLootMailItem(index) -- takes the money too
      elseif TakeInboxMoney then
        TakeInboxMoney(index)
      end
      taken, money = taken + 1, money + cash
      C_Timer.After(STEP, function()
        step(id, index - 1, 0)
      end)
      return
    end
    index = index - 1
  end
  finish(taken > 0 and summary() or "there is no auction mail to open.")
end

function ns.OpenAuctionMail()
  if running then
    finish("stopped. " .. summary())
    return
  end
  if not (GetInboxNumItems and GetInboxHeaderInfo and (TakeInboxMoney or AutoLootMailItem) and C_Timer) then
    ns.Print("this game client has no mail functions for addons.")
    return
  end
  if not (MailFrame and MailFrame:IsShown()) then
    ns.Print("open a mailbox first.")
    return
  end
  running, taken, money = true, 0, 0
  token = token + 1
  if C_Mail and C_Mail.SetOpeningAll then
    pcall(C_Mail.SetOpeningAll, true)
  end
  if button then
    button:SetText("Stop")
  end
  step(token, GetInboxNumItems() or 0, 0)
end

function ns.MailRunning()
  return running
end

local function createButton()
  holder = CreateFrame("Frame", nil, MailFrame)
  holder:SetSize(160, 22)
  holder:SetPoint("TOPLEFT", MailFrame, "BOTTOMLEFT", 4, -4)
  button = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
  button:SetAllPoints()
  button:SetText("Open auction mail")
  button:SetScript("OnClick", function()
    ns.OpenAuctionMail()
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Open auction mail", 1, 1, 1)
    GameTooltip:AddLine("Takes the gold and items of every auction house mail. The ledger records each sale and purchase first. Other mail and mail with cash on delivery stay in the inbox.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end

ns.OnOptionChanged(function(key, value)
  if key == "mailButton" and holder then
    holder:SetShown(value)
  end
end)

local events = CreateFrame("Frame")
ns.SafeRegister(events, "MAIL_SHOW")
ns.SafeRegister(events, "MAIL_CLOSED")
events:SetScript("OnEvent", function(_, event)
  if event == "MAIL_CLOSED" then
    if running then
      finish("the mailbox closed. " .. summary())
    end
    return
  end
  if not ForeverAuctionsDB then
    return
  end
  if not holder and MailFrame then
    if not pcall(createButton) then
      holder = nil
    end
  end
  if holder then
    holder:SetShown(ns.GetOption("mailButton"))
  end
end)
