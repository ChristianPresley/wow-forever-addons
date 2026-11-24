local _, ns = ...

local function help()
  ns.Print("commands:")
  print("  /ftrace status - what is stored, and the last error")
  print("  /ftrace show 10 - the last events in the chat")
  print("  /ftrace errors - the stored errors, the newest first")
  print("  /ftrace mark the bag window looks wrong - a marker in the trace")
  print("  /ftrace record - turn the recording on or off")
  print("  /ftrace screenshots - turn the screenshot for a new error on or off")
  print("  /ftrace shot - take one screenshot now, as a test")
  print("  /ftrace clear - delete the stored errors and events")
  print("  /ftrace options - open the settings page")
  print("  The trace is written to the disk at /reload and at logout.")
end

local function onOff(value)
  return value and "|cff40c040on|r" or "|cffc04040off|r"
end

local function firstLine(text, limit)
  text = tostring(text or ""):gsub("\n.*", "")
  if #text > limit then
    text = text:sub(1, limit) .. "..."
  end
  return text
end

-- "14:02:11" of "2026-11-23 14:02:11".
local function clock(at)
  return tostring(at or ""):match("(%d+:%d+:%d+)$") or "?"
end

function ns.StatusLines()
  local total, ours, latest, events = ns.Counts()
  local db = ForeverTraceDB
  local lines = {
    string.format("session %d, recording %s. %d errors stored (%d of Forever addons), %d events.", db.session, onOff(ns.GetOption("enabled")), total, ours, events),
    "Lua errors: " .. (ns.hooked and "seen through the error window of the game." or "|cffc04040not seen|r: the error window of the game is not there.") .. " Screenshots: " .. onOff(ns.GetOption("screenshots")) .. ".",
  }
  if latest then
    lines[#lines + 1] = string.format("last: #%d %s in %s, %d times, %s: %s", latest.id, latest.kind, latest.addon or "?", latest.count, clock(latest.last.at), firstLine(latest.message, 120))
  end
  if db.internal and (db.internal.count or 0) > 0 then
    lines[#lines + 1] = string.format("Forever Trace itself failed %d times: %s", db.internal.count, firstLine(db.internal.last, 120))
  end
  return lines
end

local function status()
  local lines = ns.StatusLines()
  ns.Print(lines[1])
  for index = 2, #lines do
    print("  " .. lines[index])
  end
end

local function show(count)
  local events = ForeverTraceDB.events
  count = math.max(1, math.min(50, math.floor(tonumber(count) or 10)))
  if #events == 0 then
    ns.Print("no events are stored.")
    return
  end
  ns.Print("the last events:")
  for index = math.max(1, #events - count + 1), #events do
    local entry = events[index]
    local text = firstLine(entry.text, 120)
    print(string.format("  %s %s%s%s%s%s", clock(entry.at), entry.kind, entry.addon and (" " .. entry.addon) or "", text ~= "" and (": " .. text) or "", entry.n and (" (" .. entry.n .. " times)") or "", entry.fight and " [fight]" or ""))
  end
end

local function errors(count)
  local stored = ForeverTraceDB.errors
  count = math.max(1, math.min(30, math.floor(tonumber(count) or 10)))
  if #stored == 0 then
    ns.Print("no errors are stored.")
    return
  end
  local sorted = {}
  for index, entry in ipairs(stored) do
    sorted[index] = entry
  end
  table.sort(sorted, function(a, b)
    if a.last.t ~= b.last.t then
      return a.last.t > b.last.t
    end
    return a.id > b.id
  end)
  ns.Print("the stored errors:")
  for index = 1, math.min(count, #sorted) do
    local entry = sorted[index]
    print(string.format("  #%d %s %s in %s%s, %d times, %s: %s", entry.id, clock(entry.last.at), entry.kind, entry.addon or "?", entry.ours and "" or " (not ours)", entry.count, entry.last.zone or "?", firstLine(entry.message, 120)))
  end
end

SLASH_FOREVERTRACE1 = "/ftrace"
SLASH_FOREVERTRACE2 = "/forevertrace"
SlashCmdList["FOREVERTRACE"] = function(input)
  if not ForeverTraceDB then
    return
  end
  local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = command:lower()
  if command == "status" then
    status()
  elseif command == "show" then
    show(rest)
  elseif command == "errors" then
    errors(rest)
  elseif command == "mark" then
    if not ns.GetOption("enabled") then
      ns.Print("the recording is off: /ftrace record turns it on.")
    else
      local entry = ns.Mark(rest)
      ns.Print("marked: " .. (entry and entry.text or rest))
    end
  elseif command == "record" then
    ns.SetOption("enabled", not ns.GetOption("enabled"))
    ns.Print("the recording is " .. onOff(ns.GetOption("enabled")) .. ".")
  elseif command == "screenshots" then
    ns.SetOption("screenshots", not ns.GetOption("screenshots"))
    ns.Print("a screenshot for a new error is " .. onOff(ns.GetOption("screenshots")) .. ".")
  elseif command == "shot" then
    ns.Print("one screenshot now...")
    ns.TestShot()
  elseif command == "clear" then
    ns.Clear()
    ns.Print("the stored errors and events are deleted.")
  elseif command == "options" or command == "config" or command == "settings" then
    ns.OpenSettings()
  else
    help()
  end
end
