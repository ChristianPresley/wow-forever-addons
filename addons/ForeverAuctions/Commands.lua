local _, ns = ...

local function help()
  ns.Print("commands:")
  print("  /fah price [item link] - show the stored price of an item")
  print("  /fah stats - show how many prices are stored for this realm")
  print("  /fah tooltip - turn the tooltip price lines on or off")
  print("  /fah clear - delete the stored prices of this realm")
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

SLASH_FOREVERAUCTIONS1 = "/fah"
SLASH_FOREVERAUCTIONS2 = "/foreverauctions"
SlashCmdList["FOREVERAUCTIONS"] = function(input)
  local command, rest = (input or ""):match("^(%S*)%s*(.-)$")
  command = command:lower()
  if command == "price" then
    price(rest)
  elseif command == "stats" then
    stats()
  elseif command == "tooltip" then
    local options = ForeverAuctionsDB.options
    options.tooltip = not options.tooltip
    ns.Print("tooltip prices " .. (options.tooltip and "on" or "off") .. ".")
  elseif command == "clear" then
    wipe(ns.Prices())
    ns.Print("stored prices of this realm deleted.")
  else
    help()
  end
end
