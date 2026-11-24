local _, ns = ...

local function onOff(value)
  return value and "on" or "off"
end

local function ago(at)
  local seconds = type(at) == "number" and time() - at or -1
  if seconds < 0 then
    return ""
  elseif seconds < 120 then
    return string.format(", %d seconds ago", seconds)
  elseif seconds < 7200 then
    return string.format(", %d minutes ago", math.floor(seconds / 60))
  end
  return string.format(", %d hours ago", math.floor(seconds / 3600))
end

-- "Herb Gathering (spell 2366) at Peacebloom"
function ns.CastText(cast)
  local text = string.format("%s (spell %s)", cast.spellName or "a spell without a name", tostring(cast.spell))
  if cast.target then
    text = text .. " at " .. cast.target
  end
  return text
end

local function status()
  local total, counts = ns.CountNodes()
  ns.Print(string.format("%d nodes learned.", total))
  for _, kind in ipairs(ns.KINDS) do
    ns.Print(string.format("  %s: %d, shown %s", kind.name, counts[kind.key] or 0, onOff(ns.GetOption(kind.key))))
  end
  ns.Print(string.format("World map %s, minimap %s, hide trivial %s, lowest skill %d, size %d.",
    onOff(ns.GetOption("worldMap")), onOff(ns.GetOption("minimap")), onOff(ns.GetOption("hideTrivial")),
    ns.GetOption("minSkill"), ns.GetOption("size")))
  local skills = {}
  for _, kind in ipairs(ns.KINDS) do
    if kind.skill then
      local rank = ns.SkillRank(kind.skill)
      skills[#skills + 1] = kind.skill .. " " .. (rank and tostring(rank) or "not learned")
    end
  end
  ns.Print("Your skills: " .. table.concat(skills, ", ") .. ".")
  local last = ForeverGatherDB.last
  local gather, other = last.gather, last.other
  if gather then
    ns.Print(string.format("Last gathering cast: %s%s, %s: %s.", ns.CastText(gather), ago(gather.at), gather.kind, gather.result))
  else
    ns.Print("Last gathering cast: none seen yet. A gather is the spell Herb Gathering, Mining, Fishing or Opening.")
  end
  if other then
    ns.Print(string.format("Last other cast at a target: %s%s. If this was a gather, report this line.", ns.CastText(other), ago(other.at)))
  end
end

local function help()
  ns.Print("/fgather status - what is learned, the settings, and the last gathering cast with what came of it")
  ns.Print("/fgather herb | ore | fish | treasure - show or hide a kind")
  ns.Print("/fgather map | minimap - show or hide the pins there")
  ns.Print("/fgather trivial - hide nodes that give no more skill")
  ns.Print("/fgather skill <n> - hide nodes learned below skill n")
  ns.Print("/fgather size <n> - the size of the pins")
  ns.Print("/fgather options - the settings page")
  ns.Print("/fgather forget [kind] - forget the nodes (of one kind)")
end

local TOGGLES = { map = "worldMap", minimap = "minimap", trivial = "hideTrivial" }

SLASH_FOREVERGATHER1 = "/fgather"
SlashCmdList.FOREVERGATHER = function(text)
  local command, rest = (text or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  if command == "" or command == "status" then
    status()
  elseif ns.KIND[command] or TOGGLES[command] then
    local key = TOGGLES[command] or command
    ns.SetOption(key, not ns.GetOption(key))
    ns.Print(string.format("%s: %s", command, onOff(ns.GetOption(key))))
  elseif command == "skill" or command == "size" then
    local key = command == "skill" and "minSkill" or "size"
    if not tonumber(rest) then
      ns.Print("Give a number: /fgather " .. command .. " 50")
      return
    end
    ns.SetOption(key, tonumber(rest))
    ns.Print(string.format("%s: %d", command, ns.GetOption(key)))
  elseif command == "options" then
    ns.OpenSettings()
  elseif command == "forget" then
    if rest ~= "" and not ns.KIND[rest] then
      ns.Print("No kind " .. rest .. ". The kinds: herb, ore, fish, treasure.")
      return
    end
    ns.Forget(rest ~= "" and rest or nil)
    ns.Print(rest ~= "" and ("Forgot the " .. ns.KIND[rest].name:lower() .. " nodes.") or "Forgot all nodes.")
  else
    help()
  end
end
