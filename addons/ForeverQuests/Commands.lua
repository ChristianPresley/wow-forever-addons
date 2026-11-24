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
  print("  zone - current zone only, in the quest log and the tracker together")
  print("  stats - quests, experience and money from turn-ins")
  print("  party - the progress of your party on the quests you share")
  print("  demo - show the quest complete banner and the glow in the quest log once, to see them")
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

local function diagnostics()
  local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("ForeverQuests", "Version")
  ns.Print("status, version " .. tostring(version or "?") .. ":")
  local count, last = ns.ErrorCount()
  print("  errors caught so far: " .. count .. (last and (", the last: " .. last) or ""))
  local okLog, entries = pcall(C_QuestLog.GetNumQuestLogEntries)
  local okWatch, watches = pcall(C_QuestLog.GetNumQuestWatches)
  print("  quests in the log: " .. (okLog and type(entries) == "number" and entries or "?"))
  print("  quests in the tracker: " .. (okWatch and type(watches) == "number" and watches or "?"))
  print("  Forever Compass: " .. (rawget(_G, "ForeverCompass") and "loaded" or "not loaded"))
  local on = 0
  for _, option in ipairs(ns.OPTIONS) do
    if ns.GetOption(option.key) then
      on = on + 1
    end
  end
  print("  options on: " .. on .. " of " .. #ns.OPTIONS .. " (/fq lists them)")
end

SLASH_FOREVERQUESTS1 = "/fq"
SLASH_FOREVERQUESTS2 = "/foreverquests"
SlashCmdList["FOREVERQUESTS"] = function(input)
  local command = (input or ""):match("^(%S*)"):lower()
  local option = byCommand[command]
  if option then
    ns.SetOption(option.key, not ns.GetOption(option.key))
    ns.Print(option.label .. " " .. onOff(ns.GetOption(option.key)) .. ".")
  elseif command == "zone" then
    ns.Print("current zone only " .. onOff(ns.ToggleZoneFilter()) .. ".")
  elseif command == "stats" then
    stats()
  elseif command == "status" then
    diagnostics()
  elseif command == "party" then
    ns.PrintParty()
  elseif command == "demo" then
    ns.Demo()
  elseif command == "options" or command == "config" then
    ns.OpenOptions()
  else
    status()
  end
end
