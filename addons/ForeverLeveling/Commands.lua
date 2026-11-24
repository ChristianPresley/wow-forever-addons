local _, ns = ...

local function help()
  ns.Print("commands:")
  print("  /flevel - your experience now")
  print("  /flevel show - show or hide the readout")
  print("  /flevel zones - show or hide the zones for your level")
  print("  /flevel go Westfall - point Forever Compass at a zone")
  print("  /flevel spread 3 - levels around yours for the list of zones")
  print("  /flevel lock - lock or unlock the windows")
  print("  /flevel new - start a new session")
  print("  /flevel reset - put the windows back at the top of the screen")
  print("  /flevel options - open the settings page")
end

local function status()
  local state = ns.State()
  if not state then
    ns.Print("the game hides your experience now.")
    return
  end
  ns.Print(string.format("level %d, %s XP to the next level, %s rested.", state.level, ns.Thousands(state.remaining), ns.Thousands(state.rested)))
  if state.perHour then
    print(string.format("  %s XP an hour: the level in %s.", ns.Thousands(state.perHour), ns.Duration(state.timeToLevel)))
  end
  if state.killsToLevel then
    print(string.format("  %d kills to level, at %s XP each.", state.killsToLevel, ns.Thousands(state.killXP)))
  end
  if state.questsToLevel then
    print(string.format("  %d quests to level, at %s XP each.", state.questsToLevel, ns.Thousands(state.questXP)))
  end
end

local function findZone(text)
  text = text:lower()
  if text == "" then
    return nil
  end
  for _, zone in ipairs(ns.ZONES) do
    if zone.name:lower() == text then
      return zone
    end
  end
  for _, zone in ipairs(ns.ZONES) do
    if zone.name:lower():find(text, 1, true) == 1 then
      return zone
    end
  end
  return nil
end

local function toggle(option, label)
  ns.SetOption(option, not ns.GetOption(option))
  ns.Print(label .. " " .. (ns.GetOption(option) and "|cff40c040on|r" or "|cffc04040off|r") .. ".")
end

SLASH_FOREVERLEVELING1 = "/flevel"
SLASH_FOREVERLEVELING2 = "/foreverleveling"
SlashCmdList["FOREVERLEVELING"] = function(input)
  if not ForeverLevelingDB then
    return
  end
  local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = command:lower()
  if command == "" then
    status()
  elseif command == "show" then
    toggle("show", "the readout is")
  elseif command == "zones" then
    toggle("showZones", "the list of zones is")
  elseif command == "go" then
    local zone = findZone(rest)
    if zone then
      ns.Print(ns.PointAt(zone))
    else
      ns.Print("\"" .. rest .. "\" is not a zone of the list. Type /flevel zones.")
    end
  elseif command == "spread" then
    if tonumber(rest) then
      ns.SetOption("zoneSpread", tonumber(rest))
    end
    ns.Print(string.format("the list has zones up to %d levels around yours.", ns.GetOption("zoneSpread")))
  elseif command == "lock" then
    toggle("lock", "the lock of the windows is")
  elseif command == "new" then
    ns.ResetSession()
    ns.Print("a new session starts now.")
  elseif command == "reset" then
    ns.ResetPositions()
    ns.Print("the windows are back at the top of the screen.")
  elseif command == "options" or command == "config" or command == "settings" then
    ns.OpenSettings()
  else
    help()
  end
end
