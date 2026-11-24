local _, ns = ...

local function onOff(value)
  return value and "|cff40c040on|r" or "|cffc04040off|r"
end

local function help()
  ns.Print("commands:")
  print("  /fmeter - show or hide the meter window")
  print("  /fmeter dps, damage, hps, healing, absorbs, taken, avoidable, enemy, interrupts, dispels, deaths - what the meter shows")
  print("  /fmeter current - show the current fight. /fmeter overall - show the whole session")
  print("  /fmeter report [self, say, party, raid, guild, officer, whisper NAME] - write the top of the list to chat (after a fight)")
  print("  /fmeter reset - delete the data of all fights")
  print("  /fmeter me - show or hide the read-out of your own DPS. /fmeter heal - the read-out shows HPS")
  print("  /fmeter lock - lock or unlock the meter window and the read-out")
  print("  /fmeter combat - hide the window out of combat, or not")
  print("  /fmeter solo, party, raid - show the window in that kind of group, or not")
  print("  /fmeter bars solo 3 - set the number of bars for solo, party or raid")
  print("  /fmeter width 230, /fmeter height 18, /fmeter opacity 85 - the size and the background of the window")
  print("  /fmeter enable - turn on the damage meter of the game, which collects the numbers")
  print("  /fmeter resetpos - put the windows back at their first places")
  print("  /fmeter status - show the settings")
  print("  /fmeter options - open the options page")
end

local function status()
  local available, reason = ns.Available()
  ns.Print(string.format("showing %s, %s. Group: %s.", ns.Mode().label:lower(), ns.SegmentName(ns.segment):lower(), ns.GroupType()))
  print("  window " .. onOff(ns.GetOption("show")) .. ", own read-out " .. onOff(ns.GetOption("personal")) .. ", locked " .. onOff(ns.GetOption("lock")))
  print(string.format("  bars: %d alone, %d in a party, %d in a raid", ns.GetOption("rowsSolo"), ns.GetOption("rowsParty"), ns.GetOption("rowsRaid")))
  local way = ns.NumberWay()
  print("  numbers in a fight: " .. (way == "rules" and "short (12.3K), by the game's function with the rules of the addon"
    or way == "game" and "short (12K), by the game's function with its own rules: this game client does not take the rules of the addon"
    or "two decimals, without K and M: this game client does not take the rules of the addon"))
  -- Why not: the answer of the game, for a report to the author.
  for _, refusal in ipairs(ns.NumberWayRefusals()) do
    print("    not " .. refusal:sub(1, 200))
  end
  if not available then
    print("  " .. reason)
  elseif ns.GameMeterEnabled() == false then
    print("  The damage meter of the game is off. Type /fmeter enable if the bars stay empty.")
  end
end

local function toggle(key, name)
  ns.SetOption(key, not ns.GetOption(key))
  ns.Print(name .. " " .. onOff(ns.GetOption(key)) .. ".")
end

local GROUP_SHOW = { solo = "showSolo", party = "showParty", raid = "showRaid" }
local GROUP_ROWS = { solo = "rowsSolo", party = "rowsParty", raid = "rowsRaid" }
local NUMBERS = { width = "width", height = "rowHeight", opacity = "alpha" }

SLASH_FOREVERMETER1 = "/fmeter"
SLASH_FOREVERMETER2 = "/forevermeter"
SlashCmdList["FOREVERMETER"] = function(input)
  if not ForeverMeterDB then
    return
  end
  local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = command:lower()
  if command == "" or command == "show" or command == "toggle" then
    toggle("show", "the meter window is")
  elseif ns.ModeByKey[command] then
    ns.SetOption("mode", command)
    ns.Print("showing " .. ns.Mode().label:lower() .. ".")
  elseif command == "current" then
    ns.SetSegment({ type = 1 })
    ns.Print("showing the current fight.")
  elseif command == "overall" or command == "session" then
    ns.SetSegment({ type = 0 })
    ns.Print("showing the whole session.")
  elseif command == "report" then
    local channel, target = rest:match("^(%S*)%s*(.-)$")
    ns.Report(channel ~= "" and channel or "SELF", target ~= "" and target or nil)
  elseif command == "reset" then
    ns.ResetData()
    ns.Print("the data of all fights is deleted.")
  elseif command == "me" or command == "personal" then
    toggle("personal", "your own read-out is")
  elseif command == "heal" then
    toggle("personalHealing", "HPS in your own read-out is")
  elseif command == "lock" then
    local locked = not ns.GetOption("lock")
    ns.SetOption("lock", locked)
    ns.SetOption("personalLock", locked)
    ns.Print("the window and the read-out are " .. (locked and "locked." or "unlocked."))
  elseif command == "combat" then
    toggle("hideOutOfCombat", "hiding the window out of combat is")
  elseif GROUP_SHOW[command] then
    toggle(GROUP_SHOW[command], "the window when " .. (command == "solo" and "alone" or ("in a " .. command)) .. " is")
  elseif command == "bars" then
    local group, number = rest:lower():match("^(%a+)%s+(%d+)$")
    local key = group and GROUP_ROWS[group]
    if not key then
      ns.Print("for example: /fmeter bars raid 10. The groups are solo, party and raid.")
      return
    end
    ns.SetOption(key, tonumber(number))
    ns.Print(group .. ": " .. ns.GetOption(key) .. " bars.")
  elseif NUMBERS[command] then
    local key = NUMBERS[command]
    if tonumber(rest) then
      ns.SetOption(key, tonumber(rest))
    end
    ns.Print(command .. " is " .. ns.GetOption(key) .. ". The range is " .. ns.LIMITS[key][1] .. " to " .. ns.LIMITS[key][2] .. ".")
  elseif command == "enable" then
    if ns.EnableGameMeter() then
      ns.Print("the damage meter of the game is on. You can hide its own window in the Edit Mode of the game.")
    else
      ns.Print("the setting could not be changed on this game client.")
    end
  elseif command == "resetpos" then
    ns.ResetPositions()
    ns.Print("the windows are back at their first places.")
  elseif command == "status" then
    status()
  elseif command == "options" or command == "config" or command == "settings" then
    ns.OpenOptions()
  else
    help()
  end
end
