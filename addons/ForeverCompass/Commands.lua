local _, ns = ...

local function help()
  ns.Print("commands:")
  print("  /fcompass - show what each compass points to")
  print("  /fcompass 2 on - show compass 2 (off hides it)")
  print("  /fcompass 2 vendor - make compass 2 point to the nearest vendor")
  print("  /fcompass kinds - list the kinds of things a compass can point to")
  print("  /fcompass lock - lock or unlock the compasses")
  print("  /fcompass combat - hide the compasses in combat, or not")
  print("  /fcompass reset - put the compasses back in a row at the top of the screen")
  print("  /fcompass options - open the settings page")
end

local function onOff(value)
  return value and "|cff40c040on|r" or "|cffc04040off|r"
end

local function status()
  ns.Print("compasses (type /fcompass help for commands):")
  for index = 1, ns.COUNT do
    local kind = ns.KindByKey[ns.GetCompass(index, "kind")]
    print(string.format("  %d: %s - %s", index, onOff(ns.GetCompass(index, "enabled")), kind and kind.name or "?"))
  end
end

local function kinds()
  ns.Print("a compass can point to the nearest of these. Use the word with /fcompass 1 <word>:")
  for _, kind in ipairs(ns.KINDS) do
    print("  " .. kind.key:lower() .. " - " .. kind.name)
  end
end

-- Finds a kind by its key or by the start of its name, without regard to case.
local function findKind(word)
  word = word:lower()
  for _, kind in ipairs(ns.KINDS) do
    if kind.key:lower() == word then
      return kind
    end
  end
  for _, kind in ipairs(ns.KINDS) do
    if kind.name:lower():gsub("%s", ""):find(word, 1, true) == 1 then
      return kind
    end
  end
  return nil
end

local function compassCommand(index, rest)
  local word = rest:lower():gsub("%s", "")
  if word == "" then
    ns.SetCompass(index, "enabled", not ns.GetCompass(index, "enabled"))
  elseif word == "on" or word == "off" then
    ns.SetCompass(index, "enabled", word == "on")
  else
    local kind = findKind(word)
    if not kind then
      ns.Print("\"" .. rest .. "\" is not a kind. Type /fcompass kinds for the list.")
      return
    end
    ns.SetCompass(index, "kind", kind.key)
    ns.SetCompass(index, "enabled", true)
  end
  local kind = ns.KindByKey[ns.GetCompass(index, "kind")]
  ns.Print(string.format("compass %d is %s and points to: %s.", index, onOff(ns.GetCompass(index, "enabled")), kind and kind.name or "?"))
end

local function toggle(option, label)
  ns.SetOption(option, not ns.GetOption(option))
  ns.Print(label .. " " .. onOff(ns.GetOption(option)) .. ".")
end

SLASH_FOREVERCOMPASS1 = "/fcompass"
SLASH_FOREVERCOMPASS2 = "/forevercompass"
SlashCmdList["FOREVERCOMPASS"] = function(input)
  if not ForeverCompassDB then
    return
  end
  local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = command:lower()
  local index = tonumber(command)
  if index then
    if index >= 1 and index <= ns.COUNT and index == math.floor(index) then
      compassCommand(index, rest)
    else
      ns.Print("compasses have the numbers 1 to " .. ns.COUNT .. ".")
    end
  elseif command == "" then
    status()
  elseif command == "kinds" then
    kinds()
  elseif command == "lock" then
    toggle("lock", "compass lock")
  elseif command == "combat" then
    toggle("hideInCombat", "hide in combat")
  elseif command == "reset" then
    ns.ResetPositions()
    ns.Print("the compasses are back in a row at the top of the screen.")
  elseif command == "options" or command == "config" or command == "settings" then
    ns.OpenSettings(tonumber(rest))
  else
    help()
  end
end
