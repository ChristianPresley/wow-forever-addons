local _, ns = ...

local function help()
  ns.Print("commands:")
  print("  /fah - open or close the price history window")
  print("  /fah scan - scan every listing (at the auction house, once per 15 minutes)")
  print("  /fah price [item link] - show the stored price of an item")
  print("  /fah deals - open the price window with the items far below their average price")
  print("  /fah list - show the shopping list. /fah list add [text], /fah list remove [text], /fah list [text] to search")
  print("  /fah watch [item link] [price] - alert when the item is seen at that price or lower, for example 5g")
  print("  /fah watch - show the price alerts. /fah unwatch [item link] removes one")
  print("  /fah mine - your auctions that are above the lowest stored price")
  print("  /fah bags - the auction and vendor value of your bags")
  print("  /fah ledger - open the window with your sales and purchases. /fah ledger text prints the totals")
  print("  /fah record - turn the recording of sales and purchases on or off. /fah ledgerdays [number] sets the days kept")
  print("  /fah dealpercent [number] - set the percentage of the average that makes a deal")
  print("  /fah panel, /fah alerts, /fah undercutcheck - turn the shopping list panel, the price alerts or the undercut message on or off")
  print("  /fah export, /fah import - copy the stored prices as text to another character, or read such a text")
  print("  /fah mail - take the gold and items of all auction house mail (at a mailbox)")
  print("  /fah craft - turn the crafting cost and profit on or off. Select recipes in a profession window so they are known")
  print("  /fah actions - turn the panel with quick buy, the post queue and cancelling on or off")
  print("  /fah stats - show how many prices are stored for this realm")
  print("  /fah tooltip - turn the tooltip auction price on or off")
  print("  /fah vendor - turn the tooltip vendor price on or off")
  print("  /fah stack - turn the tooltip stack value (auction) on or off")
  print("  /fah stackvendor - turn the tooltip stack value (vendor) on or off")
  print("  /fah undercut [amount] - set the undercut of the posting helper, for example 1, 50c, 5s or 1g")
  print("  /fah helper - turn the price helper on the sell tab on or off")
  print("  /fah scanbutton - turn the full scan button on or off")
  print("  /fah days [number] - set how many days of prices are kept")
  print("  /fah options - open the settings page")
  print("  /fah clear yes - delete the stored prices of this realm. /fah clear says how many there are")
  print("  /fah status - when each feature last ran without an error")
  print("  /fah errors - the errors the features caught. /fah errors clear forgets them")
  print("  /fah help - show this list")
end

local function price(rest)
  local itemID = tonumber(rest:match("item:(%d+)")) or tonumber(rest)
  if not itemID then
    ns.Print("shift-click an item into the chat box after /fah price.")
    return
  end
  local entry, average, days = ns.Lookup(itemID)
  if not entry then
    ns.Print("no price stored for that item. Search for it at the auction house first.")
    return
  end
  ns.Print(string.format("%s, seen %s. %d-day average: %s.", ns.Money(entry.price), ns.Age(entry.seen), days, ns.Money(average)))
end

-- /fah status: when each feature last ran without an error.
local FEATURES = { "ledger", "undercut", "sell helper", "tooltip stack", "bags" }
local function status()
  ns.Print("when each feature last ran without an error:")
  for _, area in ipairs(FEATURES) do
    local at = ForeverAuctionsDB.status and ForeverAuctionsDB.status[area]
    print(string.format("  %s: %s", area, at and ns.Age(at) or "not yet"))
  end
end

-- /fah errors: the errors that the features caught. /fah errors clear forgets them.
local function errorsCommand(rest)
  if rest:lower() == "clear" then
    ForeverAuctionsDB.errors = {}
    ns.Print("the caught errors are forgotten.")
    return
  end
  local lines = {}
  for area, record in pairs(ForeverAuctionsDB.errors or {}) do
    lines[#lines + 1] = string.format("  %s: %d times, last %s: %s", area, record.count, ns.Age(record.last), record.message)
  end
  table.sort(lines)
  if #lines == 0 then
    ns.Print("no errors caught.")
    return
  end
  ns.Print("errors caught by the features (their results were left out):")
  for _, line in ipairs(lines) do
    print(line)
  end
end

local function stats()
  local count = 0
  for _ in pairs(ns.Prices()) do
    count = count + 1
  end
  ns.Print(count .. " item prices stored for this realm and faction.")
end

local TOGGLES = {
  tooltip = { key = "tooltip", name = "tooltip auction price" },
  vendor = { key = "tooltipVendor", name = "tooltip vendor price" },
  stack = { key = "tooltipStack", name = "tooltip stack value (auction)" },
  stackvendor = { key = "tooltipStackVendor", name = "tooltip stack value (vendor)" },
  helper = { key = "sellHelper", name = "price helper on the sell tab" },
  scanbutton = { key = "scanButton", name = "full scan button" },
  panel = { key = "shoppingPanel", name = "shopping list panel" },
  alerts = { key = "priceAlerts", name = "price alerts" },
  undercutcheck = { key = "undercutCheck", name = "message about your undercut auctions" },
  record = { key = "ledger", name = "recording of sales and purchases" },
  craft = { key = "craftCost", name = "crafting cost and profit" },
  actions = { key = "actionsPanel", name = "actions panel" },
  mailbutton = { key = "mailButton", name = "\"Open auction mail\" button" },
}

-- /fah ledgerdays 90
local function ledgerDays(rest)
  if tonumber(rest) then
    ns.SetOption("ledgerDays", tonumber(rest))
  end
  ns.Print("the ledger keeps a sale or a purchase for " .. ns.GetOption("ledgerDays") .. " days. Change it with /fah ledgerdays 90.")
end

-- /fah list, /fah list add linen cloth, /fah list remove linen cloth, /fah list linen cloth
local function shopping(rest)
  local action, text = rest:match("^(%S*)%s*(.-)$")
  action = action:lower()
  if rest == "" then
    local list = ns.ShoppingList()
    if #list == 0 then
      ns.Print("the shopping list is empty. Add a search with /fah list add [text].")
      return
    end
    ns.Print("shopping list (" .. #list .. "): " .. table.concat(list, ", "))
  elseif action == "add" then
    local ok, problem = ns.AddSearch(text)
    ns.Print(ok and "added to the shopping list." or problem)
  elseif action == "remove" or action == "delete" then
    ns.Print(ns.RemoveSearch(text) and "removed from the shopping list." or "that search is not on the shopping list.")
  else
    ns.RunSearch(rest)
  end
end

-- /fah watch [link] 5g, /fah watch
local function watch(rest)
  if rest == "" then
    ns.PrintWatchList()
    return
  end
  local itemID = tonumber(rest:match("item:(%d+)"))
  -- The price is the text after the link.
  local amount = ns.ParseMoney(rest:match("|h|r%s*(.-)$") or "")
  if not itemID or not amount or amount <= 0 then
    ns.Print("shift-click an item into the chat box and type a price after it: /fah watch [item link] 5g.")
    return
  end
  ns.SetWatch(itemID, amount)
  ns.Print("price alert: " .. ns.ItemLabel(itemID) .. " at " .. ns.Money(amount) .. " or lower.")
end

local function unwatch(rest)
  local itemID = tonumber(rest:match("item:(%d+)")) or tonumber(rest)
  if not itemID or not ns.WatchTarget(itemID) then
    ns.Print("no price alert for that item. /fah watch shows the alerts.")
    return
  end
  ns.SetWatch(itemID, nil)
  ns.Print("price alert removed: " .. ns.ItemLabel(itemID) .. ".")
end

-- /fah dealpercent 60
local function dealPercent(rest)
  if tonumber(rest) then
    ns.SetOption("dealPercent", tonumber(rest))
  end
  ns.Print("an item is a deal at " .. ns.GetOption("dealPercent") .. "% of its average price or lower. Change it with /fah dealpercent 60.")
end

-- /fah days 21
local function days(rest)
  if tonumber(rest) then
    ns.SetOption("historyDays", tonumber(rest))
  end
  ns.Print("prices are kept for " .. ns.GetOption("historyDays") .. " days. Change it with /fah days 21.")
end

local UNITS = { [""] = 1, c = 1, s = 100, g = 10000 }

local function undercut(rest)
  local amount, unit = rest:lower():match("^(%d+)%s*([gsc]?)$")
  if not amount then
    ns.Print("undercut is " .. ns.Money(ns.GetOption("undercut")) .. ". Change it with, for example, /fah undercut 5s.")
    return
  end
  ns.SetOption("undercut", tonumber(amount) * UNITS[unit])
  local value = ns.GetOption("undercut")
  ns.Print("undercut set to " .. (value > 0 and ns.Money(value) or "0 (match the lowest price)") .. ".")
end

SLASH_FOREVERAUCTIONS1 = "/fah"
SLASH_FOREVERAUCTIONS2 = "/foreverauctions"
SlashCmdList["FOREVERAUCTIONS"] = function(input)
  if not ForeverAuctionsDB then
    return
  end
  local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = command:lower()
  local toggle = TOGGLES[command]
  if command == "" or command == "history" then
    ns.ToggleHistory()
  elseif command == "scan" then
    ns.StartScan()
  elseif command == "price" then
    price(rest)
  elseif command == "stats" then
    stats()
  elseif command == "deals" then
    ns.ShowDeals()
  elseif command == "list" or command == "shop" then
    shopping(rest)
  elseif command == "watch" then
    watch(rest)
  elseif command == "unwatch" then
    unwatch(rest)
  elseif command == "mine" then
    ns.PrintMyAuctions()
  elseif command == "bags" then
    ns.PrintBagValue()
  elseif command == "ledger" then
    if rest:lower() == "text" then
      ns.PrintLedger()
    else
      ns.ToggleLedger()
    end
  elseif command == "export" then
    ns.ShowExport()
  elseif command == "import" then
    ns.ShowImport()
  elseif command == "mail" then
    ns.OpenAuctionMail()
  elseif command == "ledgerdays" then
    ledgerDays(rest)
  elseif command == "dealpercent" then
    dealPercent(rest)
  elseif toggle then
    ns.SetOption(toggle.key, not ns.GetOption(toggle.key))
    ns.Print(toggle.name .. " " .. (ns.GetOption(toggle.key) and "on" or "off") .. ".")
  elseif command == "undercut" then
    undercut(rest)
  elseif command == "days" then
    days(rest)
  elseif command == "options" or command == "config" or command == "settings" then
    ns.OpenOptions()
  elseif command == "status" then
    status()
  elseif command == "errors" then
    errorsCommand(rest)
  elseif command == "clear" then
    -- The settings page asks before it deletes, and so does the command: the word "yes" is the answer.
    local count = 0
    for _ in pairs(ns.Prices()) do
      count = count + 1
    end
    if rest:lower() ~= "yes" then
      ns.Print(count .. " item prices are stored for this realm and faction. Type /fah clear yes to delete them.")
      return
    end
    wipe(ns.Prices())
    ns.RefreshHistory()
    ns.Print(count .. " stored prices of this realm and faction deleted.")
  else
    help()
  end
end
