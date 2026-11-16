local _, ns = ...

-- Report: the top of the list as lines in chat.
--
-- Chat needs plain numbers. During a fight the numbers are secret, so a report waits for the end
-- of the fight.

local CHANNELS = { SELF = true, SAY = true, PARTY = true, RAID = true, GUILD = true }

local function send(text, channel)
  if channel == "SELF" then
    print(text)
    return
  end
  local sendMessage = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
  if sendMessage then
    pcall(sendMessage, text, channel)
  end
end

-- Returns the lines of the report, or nil and the reason.
function ns.ReportLines()
  local mode, segment = ns.Mode(), ns.segment
  local session = ns.GetSession(mode, segment)
  if not session or #session.combatSources == 0 then
    return nil, "there is no data to report."
  end
  local duration = ns.Duration(segment)
  local lines = {
    string.format("Forever Meter: %s, %s%s", mode.label, ns.SegmentName(segment), duration and (" (" .. ns.Clock(duration) .. ")") or ""),
  }
  local total = session.totalAmount
  for rank = 1, math.min(ns.GetOption("reportLines"), #session.combatSources) do
    local source = session.combatSources[rank]
    local name, amount, rate = source.name, source.totalAmount, source.amountPerSecond
    if ns.IsSecret(name) or type(name) ~= "string" or not ns.Usable(amount) then
      return nil, "the numbers are hidden during a fight. Report after the fight."
    end
    local line
    if mode.deaths then
      local seconds = source.deathTimeSeconds
      line = string.format("%d. %s%s", rank, name, ns.Usable(seconds) and seconds >= 0 and (" at " .. ns.Clock(seconds)) or "")
    elseif mode.noRate or not ns.Usable(rate) then
      line = string.format("%d. %s  %s", rank, name, ns.Short(amount))
    elseif mode.rate then
      line = string.format("%d. %s  %s (%s)", rank, name, ns.Short(rate), ns.Short(amount))
    else
      line = string.format("%d. %s  %s (%s)", rank, name, ns.Short(amount), ns.Short(rate))
    end
    if not mode.deaths and ns.Usable(total) and total > 0 then
      line = line .. string.format("  %d%%", math.floor(amount / total * 100 + 0.5))
    end
    lines[#lines + 1] = line
  end
  return lines
end

-- channel: "SELF", "SAY", "PARTY", "RAID" or "GUILD".
function ns.Report(channel)
  channel = (channel or "SELF"):upper()
  if not CHANNELS[channel] then
    ns.Print("report to self, say, party, raid or guild. For example: /fmeter report party.")
    return
  end
  if channel == "PARTY" and ns.GroupType() == "solo" then
    ns.Print("you are not in a party.")
    return
  end
  if channel == "RAID" and ns.GroupType() ~= "raid" then
    ns.Print("you are not in a raid.")
    return
  end
  local ok, lines, problem = pcall(ns.ReportLines)
  if not ok then
    ns.Print("the report could not be made now.")
    return
  end
  if not lines then
    ns.Print(problem)
    return
  end
  for _, line in ipairs(lines) do
    send(line, channel)
  end
end
