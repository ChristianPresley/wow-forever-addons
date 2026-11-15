local _, ns = ...

local function help()
  ns.Print("commands:")
  print("  /fah - open or close the price history window")
  print("  /fah scan - scan every listing (at the auction house, once per 15 minutes)")
  print("  /fah price [item link] - show the stored price of an item")
  print("  /fah stats - show how many prices are stored for this realm")
  print("  /fah tooltip - turn the tooltip auction price on or off")
  print("  /fah vendor - turn the tooltip vendor price on or off")
  print("  /fah stack - turn the tooltip stack value (auction) on or off")
  print("  /fah stackvendor - turn the tooltip stack value (vendor) on or off")
  print("  /fah undercut [amount] - set the undercut of the posting helper, for example 1, 50c, 5s or 1g")
  print("  /fah options - open the settings page")
  print("  /fah clear - delete the stored prices of this realm")
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
}

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
  elseif toggle then
    ns.SetOption(toggle.key, not ns.GetOption(toggle.key))
    ns.Print(toggle.name .. " " .. (ns.GetOption(toggle.key) and "on" or "off") .. ".")
  elseif command == "undercut" then
    undercut(rest)
  elseif command == "options" or command == "config" or command == "settings" then
    ns.OpenOptions()
  elseif command == "clear" then
    wipe(ns.Prices())
    ns.RefreshHistory()
    ns.Print("stored prices of this realm deleted.")
  else
    help()
  end
end
