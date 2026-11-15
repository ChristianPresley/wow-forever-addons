local _, ns = ...

-- The "Forever Auctions" page in the Options window of the game. Every option of the addon is here.

local page

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

function ns.OpenOptions()
  if not (page and page:Open()) then
    ns.Print("the settings page cannot open now. Type /fah help for the commands.")
  end
end

ns.OnReady(function()
  if pcall(build) and page:Register() then
    ns.OnOptionChanged(function()
      page:Refresh()
    end)
  else
    page = nil
  end
end)
