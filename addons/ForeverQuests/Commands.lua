local _, ns = ...

local byCommand = {}
for _, option in ipairs(ns.OPTIONS) do
  byCommand[option.command] = option
end

local function onOff(value)
  return value and "|cff40c040on|r" or "|cffc04040off|r"
end

local function status()
  ns.Print("settings (type /fq and the word to change one):")
  for _, option in ipairs(ns.OPTIONS) do
    print("  " .. option.command .. " - " .. option.label .. ": " .. onOff(ns.GetOption(option.key)))
  end
  print("  stats - quests, experience and money from turn-ins")
  print("  party - the progress of your party on the quests you share")
  print("  options - open the options page")
  print("  Hold Shift while you talk to an NPC to skip the automation once.")
end

local function stats()
  local function line(label, totals)
    print(string.format("  %s: %d quests, %d experience, %s", label, totals.quests, totals.xp, ns.Money(totals.money)))
  end
  ns.Print("quest turn-ins:")
  line("This session", ns.session)
  line("This character", ForeverQuestsCharDB)
end

SLASH_FOREVERQUESTS1 = "/fq"
SLASH_FOREVERQUESTS2 = "/foreverquests"
SlashCmdList["FOREVERQUESTS"] = function(input)
  local command = (input or ""):match("^(%S*)"):lower()
  local option = byCommand[command]
  if option then
    ns.SetOption(option.key, not ns.GetOption(option.key))
    ns.Print(option.label .. " " .. onOff(ns.GetOption(option.key)) .. ".")
  elseif command == "stats" then
    stats()
  elseif command == "party" then
    ns.PrintParty()
  elseif command == "options" or command == "config" then
    ns.OpenOptions()
  else
    status()
  end
end
