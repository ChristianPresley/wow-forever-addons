local _, ns = ...

local function help()
  ns.Print("commands:")
  print("  /fcompass - show what each tracker points to")
  print("  /fcompass show - show or hide the compass bar")
  print("  /fcompass 2 on - turn tracker 2 on (off turns it off)")
  print("  /fcompass 2 vendor - make tracker 2 point to the nearest vendor")
  print("  /fcompass 2 opacity 75 - set the opacity of the marker of tracker 2, in percent")
  print("  /fcompass kinds - list the kinds of things a tracker can point to")
  print("  /fcompass opacity 75 - set the opacity of the bar, in percent")
  print("  /fcompass width 67 - set the width of the bar, in percent of the screen")
  print("  /fcompass view 180 - set how many degrees the bar shows at one time")
  print("  /fcompass degrees - show the heading in degrees, or not")
  print("  /fcompass lock - lock or unlock the bar")
  print("  /fcompass combat - hide the bar in combat, or not")
  print("  /fcompass reset - put the bar back at the top of the screen")
  print("  /fcompass options - open the settings page")
end

local function onOff(value)
  return value and "|cff40c040on|r" or "|cffc04040off|r"
end

local function status()
  ns.Print("the bar is " .. onOff(ns.GetOption("show")) .. ". Trackers (type /fcompass help for commands):")
  for index = 1, ns.COUNT do
    local kind = ns.KindByKey[ns.GetCompass(index, "kind")]
    local line = string.format("  %d: %s - %s", index, onOff(ns.GetCompass(index, "enabled")), kind and kind.name or "?")
    if ns.GetCompass(index, "enabled") then
      line = line .. " (" .. ns.TrackerStatus(index) .. ")"
    end
    print(line)
  end
end

local function kinds()
  ns.Print("a tracker can point to the nearest of these. Use the word with /fcompass 1 <word>:")
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

local function trackerCommand(index, rest)
  local word = rest:lower():gsub("%s", "")
  local opacity = word:match("^opacity(%d+)$")
  if opacity then
    ns.SetCompass(index, "alpha", tonumber(opacity))
    ns.Print(string.format("the marker of tracker %d has an opacity of %d percent.", index, ns.GetCompass(index, "alpha")))
    return
  end
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
  ns.Print(string.format("tracker %d is %s and points to: %s.", index, onOff(ns.GetCompass(index, "enabled")), kind and kind.name or "?"))
end

local function toggle(option, label)
  ns.SetOption(option, not ns.GetOption(option))
  ns.Print(label .. " " .. onOff(ns.GetOption(option)) .. ".")
end

local function number(option, rest, text)
  if tonumber(rest) then
    ns.SetOption(option, tonumber(rest))
  end
  ns.Print(string.format(text, ns.GetOption(option)))
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
      trackerCommand(index, rest)
    else
      ns.Print("trackers have the numbers 1 to " .. ns.COUNT .. ".")
    end
  elseif command == "" then
    status()
  elseif command == "kinds" then
    kinds()
  elseif command == "show" then
    toggle("show", "the compass bar is")
  elseif command == "opacity" then
    number("barAlpha", rest, "the bar has an opacity of %d percent.")
  elseif command == "width" then
    number("barWidth", rest, "the bar is %d percent of the screen wide.")
  elseif command == "view" then
    number("fov", rest, "the bar shows %d degrees at one time.")
  elseif command == "degrees" then
    toggle("showDegrees", "heading in degrees")
  elseif command == "lock" then
    toggle("lock", "bar lock")
  elseif command == "combat" then
    toggle("hideInCombat", "hide in combat")
  elseif command == "reset" then
    ns.ResetPositions()
    ns.Print("the bar is back at the top of the screen.")
  elseif command == "options" or command == "config" or command == "settings" then
    ns.OpenSettings(tonumber(rest))
  else
    help()
  end
end
