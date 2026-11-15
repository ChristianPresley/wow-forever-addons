local _, ns = ...

local OPTIONS = {
  accept = { key = "autoAccept", label = "automatic accept" },
  turnin = { key = "autoTurnIn", label = "automatic turn-in" },
  announce = { key = "announce", label = "chat messages" },
  sound = { key = "sound", label = "quest-ready sound" },
}

local function onOff(value)
  return value and "|cff40c040on|r" or "|cffc04040off|r"
end

local function money(copper)
  if GetMoneyString then
    return GetMoneyString(copper, true)
  end
  return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local function status()
  local options = ForeverQuestsDB.options
  ns.Print("settings (type /fq and the word to change one):")
  print("  accept - automatic accept: " .. onOff(options.autoAccept))
  print("  turnin - automatic turn-in: " .. onOff(options.autoTurnIn))
  print("  announce - chat messages: " .. onOff(options.announce))
  print("  sound - quest-ready sound: " .. onOff(options.sound))
  print("  stats - quests, experience and money from turn-ins")
  print("  Hold Shift while you talk to an NPC to skip the automation once.")
end

local function stats()
  local function line(label, totals)
    print(string.format("  %s: %d quests, %d experience, %s", label, totals.quests, totals.xp, money(totals.money)))
  end
  ns.Print("quest turn-ins:")
  line("This session", ns.session)
  line("This character", ForeverQuestsCharDB)
end

SLASH_FOREVERQUESTS1 = "/fq"
SLASH_FOREVERQUESTS2 = "/foreverquests"
SlashCmdList["FOREVERQUESTS"] = function(input)
  local command = (input or ""):match("^(%S*)"):lower()
  local option = OPTIONS[command]
  if option then
    local options = ForeverQuestsDB.options
    options[option.key] = not options[option.key]
    ns.Print(option.label .. " " .. onOff(options[option.key]) .. ".")
  elseif command == "stats" then
    stats()
  else
    status()
  end
end
