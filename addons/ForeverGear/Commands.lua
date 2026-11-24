local _, ns = ...

local function onOff(value)
  return value and "|cff40c040on|r" or "|cffc04040off|r"
end

local function help()
  ns.Print("commands:")
  print("  /fgear - open or close the gear window")
  print("  /fgear list - the gear list of your role")
  print("  /fgear mine - your own list")
  print("  /fgear loot [dungeon] - the loot of a dungeon, for example /fgear loot brd")
  print("  /fgear role [melee, ranged, caster, healer, tank] - the role of your class")
  print("  /fgear add [item link] [slot] - put an item on your own list, or take it off")
  print("  /fgear check [item link] - what the gear list says about an item, in chat")
  print("  /fgear tooltip - the gear list lines in tooltips, on or off")
  print("  /fgear upgrade - the upgrade line in tooltips, on or off")
  print("  /fgear audit - compare the gear data with the game, in chat")
  print("  /fgear resetpos - put the window back at its first place")
  print("  /fgear options - open the options page")
end

local function itemOf(text)
  return tonumber(text:match("item:(%d+)")) or tonumber(text:match("^(%d+)"))
end

local function toggle(key, name)
  ns.SetOption(key, not ns.GetOption(key))
  ns.Print(name .. " " .. onOff(ns.GetOption(key)) .. ".")
end

local function role(rest)
  local roles = ns.RolesOf(ns.PlayerClass())
  if rest ~= "" and ns.SetRole(rest:lower()) then
    ns.Print("the role is " .. ns.ROLES[ns.GetRole()] .. ".")
    return
  end
  local names = {}
  for _, key in ipairs(roles) do
    names[#names + 1] = key
  end
  ns.Print("the role is " .. ns.ROLES[ns.GetRole()] .. ". Roles of your class: " .. table.concat(names, ", ") .. ".")
end

local function loot(rest)
  local wanted = rest:upper()
  for _, instance in ipairs(ns.INSTANCES) do
    if wanted == instance.key or (wanted ~= "" and instance.name:upper():find(wanted, 1, true)) then
      ns.ShowWindow()
      ns.SetInstance(instance.key)
      return
    end
  end
  ns.ShowWindow()
  ns.SetView("loot")
  if rest ~= "" then
    local keys = {}
    for _, instance in ipairs(ns.INSTANCES) do
      keys[#keys + 1] = instance.key:lower()
    end
    ns.Print("no dungeon by that name. Known: " .. table.concat(keys, ", ") .. ".")
  end
end

local function add(rest)
  local itemID = itemOf(rest)
  if not itemID then
    ns.Print("shift-click an item into the chat box after /fgear add.")
    return
  end
  local slot = rest:match("(%a+)%s*$")
  slot = slot and ns.SLOT_BY_KEY[slot:upper()] and slot:upper() or nil
  if ns.TogglePersonal(itemID, slot) then
    local where = ns.SlotOf(itemID)
    ns.Print("on your own list" .. (where and (", " .. ns.SLOT_BY_KEY[where].name:lower()) or "") .. ".")
  else
    ns.Print("taken off your own list.")
  end
end

local function check(rest)
  local itemID = itemOf(rest)
  if not itemID then
    ns.Print("shift-click an item into the chat box after /fgear check.")
    return
  end
  local lines = ns.TooltipLines(itemID)
  if #lines == 0 then
    ns.Print("that item is not on your gear list.")
    return
  end
  for _, line in ipairs(lines) do
    ns.Print(line[1])
  end
end

local AUDIT_LINES = 40

local function audit()
  local problems, waiting, total = ns.Audit()
  for index = 1, math.min(#problems, AUDIT_LINES) do
    print("  " .. problems[index])
  end
  if #problems > AUDIT_LINES then
    print("  ... and " .. (#problems - AUDIT_LINES) .. " more.")
  end
  ns.Print(string.format("audit: %d of %d items differ from the game.", #problems, total))
  if waiting > 0 then
    ns.Print(string.format("the game has not loaded the name of %d items yet. Type /fgear audit again in a moment.", waiting))
  end
end

SLASH_FOREVERGEAR1 = "/fgear"
SLASH_FOREVERGEAR2 = "/forevergear"
SlashCmdList["FOREVERGEAR"] = function(input)
  if not ForeverGearDB then
    return
  end
  local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = command:lower()
  if command == "" or command == "toggle" then
    ns.ToggleWindow()
  elseif command == "list" or command == "bis" then
    ns.ShowWindow()
    ns.SetView("list")
  elseif command == "mine" then
    ns.ShowWindow()
    ns.SetView("mine")
  elseif command == "loot" then
    loot(rest)
  elseif command == "role" then
    role(rest)
  elseif command == "add" then
    add(rest)
  elseif command == "check" then
    check(rest)
  elseif command == "tooltip" then
    toggle("tooltipList", "the gear list lines in tooltips are")
  elseif command == "upgrade" then
    toggle("tooltipUpgrade", "the upgrade line in tooltips is")
  elseif command == "audit" then
    audit()
  elseif command == "resetpos" then
    ns.ResetPositions()
    ns.Print("the window is back at its first place.")
  elseif command == "options" or command == "config" or command == "settings" then
    ns.OpenOptions()
  else
    help()
  end
end
