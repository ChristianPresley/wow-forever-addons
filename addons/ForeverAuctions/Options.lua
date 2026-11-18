local _, ns = ...

-- The "Forever Auctions" page in the Options window of the game. Every option of the addon is here.

local page, buying, ledgerPage

local function build()
  page = ns.NewSettingsPage("Forever Auctions", "Type /fah for the price history window and /fah help for commands.")
  local function check(key, label, hint)
    page:Check({
      label = label,
      hint = hint,
      get = function()
        return ns.GetOption(key)
      end,
      set = function(value)
        ns.SetOption(key, value)
      end,
    })
  end

  page:Header("Item tooltips")
  check("tooltip", "Auction price and average", "The last known auction price of the item, its age, and the average of the stored days.")
  check("tooltipVendor", "Vendor sell price", "What a vendor pays for the item. Marked when that is more than the auction price.")
  check("tooltipStack", "Auction value of the whole stack", "For a stack in your bags: the auction price times the number of items.")
  check("tooltipStackVendor", "Vendor value of the whole stack", "For a stack in your bags: the vendor price times the number of items.")

  page:Header("Auction house window")
  check("scanButton", "Full scan button", "A button under the auction house window that reads every listing. /fah scan works without it.")
  check("shoppingPanel", "Shopping list", "A panel beside the auction house window with the searches you saved. A click on one starts the search.")
  check("undercutCheck", "Tell me when my auctions are not the lowest", "When you open the Auctions tab: a message if a lower price is stored for an item you have for sale. /fah mine shows the list.")
  check("sellHelper", "Price helper on the sell tab", "Shows the lowest price of the item you put up for sale, with a button that fills in your price.")
  page:Slider({
    label = "Undercut the lowest price by",
    hint = "The price helper fills in the lowest price minus this amount. For more than 100 copper, type /fah undercut 5s. Where the auction house only takes whole silver, the price is rounded down to whole silver.",
    min = 0,
    max = 100,
    step = 1,
    get = function()
      return ns.GetOption("undercut")
    end,
    set = function(value)
      ns.SetOption("undercut", value)
    end,
    format = function(value)
      return value > 0 and ns.Money(value) or "0 (match the lowest price)"
    end,
  })

  page:Header("Price history")
  page:Slider({
    label = "Days of prices to keep for each item",
    hint = "The lowest price of each day is kept this long. The tooltip average and the price history window use these days.",
    min = ns.LIMITS.historyDays[1],
    max = ns.LIMITS.historyDays[2],
    step = 1,
    get = function()
      return ns.GetOption("historyDays")
    end,
    set = function(value)
      ns.SetOption("historyDays", value)
    end,
    format = function(value)
      return value .. " days"
    end,
  })
  page:Info(function()
    local prices = 0
    for _ in pairs(ns.Prices()) do
      prices = prices + 1
    end
    local last = ns.LastScanTime()
    return string.format(
      "%d item prices stored for this realm and faction.   Last full scan: %s.",
      prices, last and ns.Age(last) or "never"
    )
  end)
  page:Buttons({
    {
      label = "Open price history",
      hint = "Opens the window with all stored prices. /fah does the same.",
      click = ns.ShowHistory,
    },
    {
      label = "Reset window position",
      hint = "Puts the price history window back in the middle of the screen.",
      click = ns.ResetHistoryPosition,
    },
    {
      label = "Delete stored prices",
      hint = "Deletes the stored prices of this realm and faction.",
      confirm = "Delete all stored prices of this realm and faction?",
      click = function()
        wipe(ns.Prices())
        ns.RefreshHistory()
      end,
    },
  })
end

-- The second page, under the first: buying.
local function buildBuying()
  buying = ns.NewSettingsPage("Buying and alerts", "Deals, price alerts, the shopping list and the value of your bags.", page)

  buying:Header("Deals")
  buying:Slider({
    label = "An item is a deal at this part of its average price",
    hint = "The price window marks an item as a deal when its latest price is at most this percentage of its average. /fah deals shows only the deals.",
    min = ns.LIMITS.dealPercent[1],
    max = ns.LIMITS.dealPercent[2],
    step = 5,
    get = function()
      return ns.GetOption("dealPercent")
    end,
    set = function(value)
      ns.SetOption("dealPercent", value)
    end,
    format = function(value)
      return value .. "% or lower"
    end,
  })
  buying:Buttons({
    {
      label = "Show deals",
      hint = "Opens the price window with only the deals. /fah deals does the same.",
      click = function()
        ns.ShowDeals()
      end,
    },
  })

  buying:Header("Price alerts")
  buying:Check({
    label = "Price alerts",
    hint = "A message and a sound when a search or a full scan sees a watched item at its target price or lower. Add one with /fah watch [item link] 5g, or right-click an item in the price window.",
    get = function()
      return ns.GetOption("priceAlerts")
    end,
    set = function(value)
      ns.SetOption("priceAlerts", value)
    end,
  })
  buying:Info(function()
    return string.format("%d price alerts for this realm and faction.", ns.CountWatches())
  end)
  buying:Buttons({
    {
      label = "List alerts in chat",
      hint = "Prints each price alert with its target price. /fah watch does the same.",
      click = function()
        ns.PrintWatchList()
      end,
    },
    {
      label = "Remove all alerts",
      hint = "Removes the price alerts of this realm and faction.",
      confirm = "Remove all price alerts of this realm and faction?",
      click = function()
        ns.ClearWatchList()
      end,
    },
  })

  buying:Header("Shopping list")
  buying:Info(function()
    return string.format("%d saved searches, for all your characters.", #ns.ShoppingList())
  end)
  buying:Buttons({
    {
      label = "Delete the shopping list",
      hint = "Deletes all saved searches.",
      confirm = "Delete all saved searches of the shopping list?",
      click = function()
        ns.ClearShoppingList()
      end,
    },
  })

  buying:Header("Actions panel")
  buying:Check({
    label = "Quick buy, post queue and cancelling beside the auction house",
    hint = "A panel below the shopping list. Each button does one step per click: buy a commodity up to its target price, post the items of your bags at an undercut, or cancel an undercut auction.",
    get = function()
      return ns.GetOption("actionsPanel")
    end,
    set = function(value)
      ns.SetOption("actionsPanel", value)
    end,
  })
  buying:Check({
    label = "Crafting cost and profit",
    hint = "Select a recipe in a profession window and the addon notes its reagents. Tooltips and the price window then show the cost of the reagents and the profit at the auction house.",
    get = function()
      return ns.GetOption("craftCost")
    end,
    set = function(value)
      ns.SetOption("craftCost", value)
    end,
  })

  buying:Header("Share prices")
  buying:Buttons({
    {
      label = "Export prices",
      hint = "Shows the stored prices of this realm and faction as text to copy. /fah export does the same.",
      click = function()
        ns.ShowExport()
      end,
    },
    {
      label = "Import prices",
      hint = "Reads the text of an export. A newer price replaces the stored one. /fah import does the same.",
      click = function()
        ns.ShowImport()
      end,
    },
  })

  buying:Header("Bags")
  buying:Buttons({
    {
      label = "Bag value in chat",
      hint = "Prints what the items in your bags are worth at the auction house and at a vendor. /fah bags does the same.",
      click = function()
        ns.PrintBagValue()
      end,
    },
  })
end

-- The third page: the ledger.
local function buildLedger()
  ledgerPage = ns.NewSettingsPage("Ledger", "Your sales and purchases at the auction house, read from the mails in your inbox.", page)

  ledgerPage:Header("Sales and purchases")
  ledgerPage:Check({
    label = "Record sales and purchases",
    hint = "When you open a mailbox, the addon reads the auction house mails in your inbox and writes each sale and each purchase to the ledger. It takes no mail and no money.",
    get = function()
      return ns.GetOption("ledger")
    end,
    set = function(value)
      ns.SetOption("ledger", value)
    end,
  })
  ledgerPage:Check({
    label = "\"Open auction mail\" button at the mailbox",
    hint = "Takes the gold and items of every auction house mail, one after the other. The ledger records each sale and purchase first. Other mail stays. /fah mail does the same.",
    get = function()
      return ns.GetOption("mailButton")
    end,
    set = function(value)
      ns.SetOption("mailButton", value)
    end,
  })
  ledgerPage:Slider({
    label = "Days to keep a sale or a purchase",
    hint = "The ledger deletes lines that are older than this.",
    min = ns.LIMITS.ledgerDays[1],
    max = ns.LIMITS.ledgerDays[2],
    step = 1,
    get = function()
      return ns.GetOption("ledgerDays")
    end,
    set = function(value)
      ns.SetOption("ledgerDays", value)
    end,
    format = function(value)
      return value .. " days"
    end,
  })
  ledgerPage:Info(function()
    local sales, earned, buys, spent = ns.LedgerSummary(7)
    return string.format("Last 7 days: %d sold for %s, %d bought for %s.", sales, ns.Money(earned), buys, ns.Money(spent))
  end)
  ledgerPage:Info(function()
    local sales, earned, buys, spent = ns.LedgerSummary(nil)
    return string.format("In the ledger: %d sold for %s, %d bought for %s.", sales, ns.Money(earned), buys, ns.Money(spent))
  end)
  ledgerPage:Buttons({
    {
      label = "Open the ledger",
      hint = "Opens the window with each sale and purchase. /fah ledger does the same.",
      click = function()
        ns.ShowLedger()
      end,
    },
    {
      label = "Reset window position",
      hint = "Puts the ledger window back in the middle of the screen.",
      click = function()
        ns.ResetLedgerPosition()
      end,
    },
    {
      label = "Delete the ledger",
      hint = "Deletes the sales and purchases of this realm and faction.",
      confirm = "Delete all sales and purchases of this realm and faction from the ledger?",
      click = function()
        ns.ClearLedger()
      end,
    },
  })
end

function ns.OpenOptions()
  if not (page and page:Open()) then
    ns.Print("the settings page cannot open now. Type /fah help for the commands.")
  end
end

ns.OnReady(function()
  if pcall(build) and page:Register() then
    ns.OnOptionChanged(function()
      page:Refresh()
      if buying then
        buying:Refresh()
      end
      if ledgerPage then
        ledgerPage:Refresh()
      end
    end)
    -- A page under the main page is registered after it.
    if not (pcall(buildBuying) and buying:Register()) then
      buying = nil
    end
    if not (pcall(buildLedger) and ledgerPage:Register()) then
      ledgerPage = nil
    end
  else
    page = nil
  end
end)
