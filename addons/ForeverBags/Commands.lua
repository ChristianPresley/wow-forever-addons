local _, ns = ...

local function onOff(value)
  return value and "|cff40c040on|r" or "|cffc04040off|r"
end

local function help()
  ns.Print("commands:")
  print("  /fbags - open or close the bag window")
  print("  /fbags all - open or close the list of the items of all your characters")
  print("  /fbags find [text] - open the bag window and search for the text")
  print("  /fbags count [item link] - who owns the item, in chat")
  print("  /fbags sort - sort the items in your bags")
  print("  /fbags junk [item link] - mark the item as junk, or take the mark away")
  print("  /fbags sell - at a vendor, sell the grey items and the items marked as junk")
  print("  /fbags ilvl - the item level on weapons and armor, on or off")
  print("  /fbags view - change between items by category and items in the order of the bags")
  print("  /fbags columns 10, /fbags size 100, /fbags opacity 90 - the look of the bag window")
  print("  /fbags blizzard - use the bag window of the game again, or this one")
  print("  /fbags tooltip - the count of this character in item tooltips, on or off")
  print("  /fbags alts - the counts of your other characters in item tooltips, on or off")
  print("  /fbags lock - lock or unlock the bag window")
  print("  /fbags forget [Name-Realm] - delete the stored items of one other character")
  print("  /fbags characters - list the stored characters and their gold")
  print("  /fbags resetpos - put the windows back at their first places")
  print("  /fbags options - open the options page")
end

local function toggle(key, name)
  ns.SetOption(key, not ns.GetOption(key))
  ns.Print(name .. " " .. onOff(ns.GetOption(key)) .. ".")
end

local function count(rest)
  local itemID = tonumber(rest:match("item:(%d+)")) or tonumber(rest)
  if not itemID then
    ns.Print("shift-click an item into the chat box after /fbags count.")
    return
  end
  local lines, shared, total = ns.OwnerLines(itemID)
  if total == 0 then
    ns.Print("none of your stored characters has that item.")
    return
  end
  ns.Print("you own " .. total .. " in total:")
  for _, line in ipairs(lines) do
    print("  " .. line.name .. ": " .. line.text)
  end
  if shared > 0 then
    print("  Shared bank: " .. shared)
  end
end

local function characters()
  ns.Print("stored characters:")
  local total = 0
  for _, character in ipairs(ns.Characters()) do
    local record = character.record
    local money = type(record.money) == "number" and record.money or 0
    total = total + money
    print(string.format("  %s%s, level %s: %s%s", character.key, character.isMe and " (this character)" or "",
      tostring(record.level or "?"), ns.Money(money), record.bankSeen and "" or ", bank not seen yet"))
  end
  print("  Gold of all characters: " .. ns.Money(total))
end

local NUMBERS = { columns = "columns", size = "scale", opacity = "alpha" }

SLASH_FOREVERBAGS1 = "/fbags"
SLASH_FOREVERBAGS2 = "/foreverbags"
SlashCmdList["FOREVERBAGS"] = function(input)
  if not ForeverBagsDB then
    return
  end
  local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = command:lower()
  if command == "" or command == "toggle" then
    if not ns.ToggleWindow() then
      ns.Print("the bag window could not be made on this game client. Type /fbags blizzard.")
    end
  elseif command == "all" or command == "list" then
    ns.ToggleBrowser()
  elseif command == "find" or command == "search" then
    ns.Search(rest)
  elseif command == "count" then
    count(rest)
  elseif command == "sort" then
    pcall(C_Container.SortBags)
  elseif command == "junk" then
    local itemID = tonumber(rest:match("item:(%d+)")) or tonumber(rest)
    if not itemID then
      ns.Print("shift-click an item into the chat box after /fbags junk.")
    else
      local marked = ns.ToggleJunk(itemID)
      ns.Print((rest:match("%[.-%]") or ("item " .. itemID)) .. (marked and " is marked as junk." or " is no longer marked as junk."))
    end
  elseif command == "sell" then
    local sold, copper = ns.SellJunk()
    ns.Print(sold > 0 and ("sold " .. sold .. (sold == 1 and " item" or " items") .. " for " .. ns.Money(copper) .. ".")
      or "no junk sold. Talk to a vendor first.")
  elseif command == "ilvl" then
    toggle("itemLevel", "the item level on weapons and armor is")
  elseif command == "view" then
    ns.SetOption("groupBy", ns.GetOption("groupBy") == "category" and "none" or "category")
    ns.Print("items " .. (ns.GetOption("groupBy") == "category" and "by category." or "in the order of the bags."))
  elseif NUMBERS[command] then
    local key = NUMBERS[command]
    if tonumber(rest) then
      ns.SetOption(key, tonumber(rest))
    end
    ns.Print(command .. " is " .. ns.GetOption(key) .. ". The range is " .. ns.LIMITS[key][1] .. " to " .. ns.LIMITS[key][2] .. ".")
  elseif command == "blizzard" then
    ns.SetOption("replaceBags", not ns.GetOption("replaceBags"))
    ns.Print(ns.GetOption("replaceBags") and "the bag key opens the Forever Bags window."
      or "the bag key opens the bag window of the game. /fbags still opens this one.")
  elseif command == "tooltip" then
    toggle("tooltipCounts", "the count of this character in tooltips is")
  elseif command == "alts" then
    toggle("tooltipAlts", "the counts of your other characters in tooltips are")
  elseif command == "lock" then
    toggle("lock", "the lock of the bag window is")
  elseif command == "forget" then
    if rest == "" then
      ns.Print("give the name as in /fbags characters, for example /fbags forget Name-Realm.")
    elseif ns.Forget(rest) then
      ns.Print("the stored items of " .. rest .. " are deleted.")
    else
      ns.Print("no other character with that name is stored. /fbags characters lists them.")
    end
  elseif command == "characters" or command == "gold" then
    characters()
  elseif command == "resetpos" then
    ns.ResetPositions()
    ns.Print("the windows are back at their first places.")
  elseif command == "options" or command == "config" or command == "settings" then
    ns.OpenOptions()
  else
    help()
  end
end
