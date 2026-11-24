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
  if not cast.spell then
    return cast.target or "a thing without a name" -- a node that was seen: no cast
  end
  local text = string.format("%s (spell %s)", cast.spellName or "a spell without a name", tostring(cast.spell))
  if cast.target then
    text = text .. " at " .. cast.target
  end
  return text
end

local function castLine(gather)
  return string.format("%s%s, %s: %s.", ns.CastText(gather), ago(gather.at), gather.kind, gather.result)
end

local function history()
  local list = ForeverGatherDB.history
  if #list == 0 then
    ns.Print("No gathering cast seen yet.")
    return
  end
  ns.Print(string.format("The last %d gathering casts, the newest last:", #list))
  for index, gather in ipairs(list) do
    ns.Print(string.format("  %d. %s", index, castLine(gather)))
  end
end

local function sessionReport()
  local session = ns.Session()
  if session.total == 0 then
    ns.Print("No gather in this session yet.")
    return
  end
  local hours = math.max(GetTime() - session.start, 60) / 3600
  ns.Print(string.format("This session: %d |4gather:gathers;, %.0f for each hour.", session.total, session.total / hours))
  for _, kind in ipairs(ns.KINDS) do
    local count = session.kinds[kind.key]
    if count then
      ns.Print(string.format("  %s: %d", kind.name, count))
    end
  end
  local names = {}
  for name, count in pairs(session.names) do
    names[#names + 1] = { name = name, count = count }
  end
  table.sort(names, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.name < b.name
  end)
  for index = 1, math.min(#names, 8) do
    ns.Print(string.format("  %s: %d", names[index].name, names[index].count))
  end
end

local function zoneReport()
  local mapID, reason = ns.PlayerPosition()
  if not mapID then
    ns.Print("No list: " .. reason .. ".")
    return
  end
  local list = ns.ZoneList(mapID)
  local info = C_Map.GetMapInfo(mapID)
  local zone = info and info.name or ("map " .. mapID)
  if #list == 0 then
    ns.Print("Nothing is learned in " .. zone .. " yet.")
    return
  end
  ns.Print(string.format("Learned in %s, the lowest skill first:", zone))
  for _, entry in ipairs(list) do
    local skill = entry.skill and string.format(", gathered at %s %d", ns.KIND[entry.kind].skill, entry.skill) or ""
    ns.Print(string.format("  %s (%s): %d |4place:places;, %d |4gather:gathers;%s", entry.name, ns.KIND[entry.kind].name:lower(), entry.nodes, entry.gathers, skill))
  end
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
  local history = ForeverGatherDB.history
  local gather, other = history[#history], ForeverGatherDB.last.other
  if gather then
    ns.Print("Last gathering cast: " .. castLine(gather))
  else
    ns.Print("Last gathering cast: none seen yet. A gather is the spell Herb Gathering, Mining, Fishing or Opening.")
  end
  if other then
    ns.Print(string.format("Last other cast at a target: %s%s. If this was a gather, report this line.", ns.CastText(other), ago(other.at)))
  end
  local problem = ForeverGatherDB.last.error
  if problem then
    ns.Print(string.format("Last red message with a thing under the pointer%s: \"%s\" at %s (%s). If this was a node that needs more skill and it is not stored, report this line.",
      ago(problem.at), problem.message, problem.name, table.concat(problem.lines, " / ")))
  end
end

local function help()
  ns.Print("/fgather status - what is learned, the settings, and the last gathering cast with what came of it")
  ns.Print("/fgather history - the last gathering casts and what came of each")
  ns.Print("/fgather zone - what is learned in this zone, by name")
  ns.Print("/fgather session - the gathers of this session; /fgather session reset starts again")
  ns.Print("/fgather export | import - the nodes as text, for another player")
  ns.Print("/fgather alert - say when a learned node comes near, or not")
  ns.Print("/fgather route - a line through the nodes of the zone on the world map, or not")
  ns.Print("/fgather clean - merge the nodes that are one node")
  ns.Print("/fgather herb | ore | fish | treasure | quest - show or hide a kind")
  ns.Print("/fgather map | minimap - show or hide the pins there")
  ns.Print("/fgather trivial - hide nodes that give no more skill")
  ns.Print("/fgather skill <n> - hide nodes learned below skill n")
  ns.Print("/fgather size <n> - the size of the pins")
  ns.Print("/fgather options - the settings page")
  ns.Print("/fgather forget [kind] - forget the nodes (of one kind)")
  ns.Print("/fgather forget here - forget the node nearest to you")
end

local TOGGLES = { map = "worldMap", minimap = "minimap", trivial = "hideTrivial", alert = "alert", route = "route" }

SLASH_FOREVERGATHER1 = "/fgather"
SlashCmdList.FOREVERGATHER = function(text)
  local command, rest = (text or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  if command == "" or command == "status" then
    status()
  elseif ns.KIND[command] or TOGGLES[command] then
    local key = TOGGLES[command] or command
    ns.SetOption(key, not ns.GetOption(key))
    ns.Print(string.format("%s: %s", command, onOff(ns.GetOption(key))))
    if key == "route" and ns.GetOption("route") then
      local mapID = ns.PlayerPosition()
      local route, yards = ns.Route(mapID)
      if #route > 1 then
        ns.Print(string.format("The route of this zone: %d nodes, %d yards around.", #route, math.floor(yards + 0.5)))
      else
        ns.Print("This zone has no two nodes for a route yet.")
      end
    end
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
  elseif command == "history" then
    history()
  elseif command == "zone" then
    zoneReport()
  elseif command == "session" then
    if rest == "reset" then
      ns.ResetSession()
      ns.Print("The count of this session starts again.")
    else
      sessionReport()
    end
  elseif command == "clean" then
    ns.Print(string.format("%d |4node:nodes; merged into another.", ns.CleanNodes()))
  elseif command == "export" then
    ns.ShowExport()
  elseif command == "import" then
    ns.ShowImport()
  elseif command == "forget" and rest == "here" then
    local node, reason = ns.ForgetHere()
    ns.Print(node and ("Forgot " .. node.name .. ".") or ("Nothing forgotten: " .. reason .. "."))
  elseif command == "forget" then
    if rest ~= "" and not ns.KIND[rest] then
      ns.Print("No kind " .. rest .. ". The kinds: " .. ns.KIND_KEYS .. ".")
      return
    end
    ns.Forget(rest ~= "" and rest or nil)
    ns.Print(rest ~= "" and ("Forgot the " .. ns.KIND[rest].name:lower() .. " nodes.") or "Forgot all nodes.")
  else
    help()
  end
end
