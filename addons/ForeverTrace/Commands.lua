local _, ns = ...

local function help()
  ns.Print("commands:")
  print("  /ftrace status - what is stored, and the last error")
  print("  /ftrace show 10 - the last events in the chat")
  print("  /ftrace errors - the stored errors, the newest first")
  print("  /ftrace mark the bag window looks wrong - a marker in the trace")
  print("  /ftrace marks - your markers, the newest first")
  print("  /ftrace test - raise one harmless error, to prove that Lua errors are recorded")
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
  local proof = ns.session and ns.session.test
  local seen
  if not ns.hooked then
    seen = "|cffc04040not seen|r: the error window of the game is not there."
  elseif proof == true then
    seen = "seen, proved by /ftrace test."
  elseif proof == false then
    seen = "|cffc04040not seen|r: /ftrace test raised an error and it was not recorded."
  else
    seen = "the hook is in place, not proved in this session: /ftrace test proves it."
  end
  local map = ns.where.map
  local lines = {
    string.format("session %d, recording %s. %d errors stored (%d of Forever addons), %d events, %d markers.", db.session, onOff(ns.GetOption("enabled")), total, ours, events, #db.marks),
    "Lua errors: " .. seen .. " Screenshots: " .. onOff(ns.GetOption("screenshots")) .. ".",
    "here: " .. (ns.where.zone or "?") .. ", " .. (map and ("map " .. tostring(map)) or "no map ID: the game gives none here, as inside an instance, so the entries have the zone only") .. ".",
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
  ns.ReadPlace()
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
    local times = ""
    if entry.kind == "zone" then
      times = (entry.from and (" from " .. entry.from) or "") .. (entry.n and (", " .. entry.n .. " times over this border") or "")
    elseif entry.kind == "fight" then
      -- The time at the front is the end of the first fight of the line.
      times = (entry.since and (", from " .. clock(entry.since)) or "") .. (entry.till and (" till " .. clock(entry.till)) or "")
    elseif entry.n and not entry.seconds then
      times = " (" .. entry.n .. " times)"
    end
    print(string.format("  %s %s%s%s%s%s", clock(entry.at), entry.kind, entry.addon and (" " .. entry.addon) or "", text ~= "" and (": " .. text) or "", times, entry.fight and " [fight]" or ""))
  end
end

local function marks(count)
  local stored = ForeverTraceDB.marks
  count = math.max(1, math.min(50, math.floor(tonumber(count) or 10)))
  if #stored == 0 then
    ns.Print("no markers are stored. /ftrace mark with a text makes one.")
    return
  end
  ns.Print("your markers:")
  for index = #stored, math.max(1, #stored - count + 1), -1 do
    local mark = stored[index]
    print(string.format("  %s, %s: %s%s", tostring(mark.at or "?"), mark.zone or "?", firstLine(mark.text, 200), mark.shot and (" (screenshot " .. (mark.shots and table.concat(mark.shots, " or ") or mark.shot) .. ")") or ""))
  end
end

---------------------------------------------------------------------------------------------------
-- /ftrace test: one harmless error, to prove that the Lua errors of this client are recorded.

local TEST_TEXT = "Forever Trace test error"
local TEST_SECONDS = 1
local testing = false

-- The error. It is raised in a timer, so that the game's own error handler gets it, as it gets
-- an error of any addon. The test driver knows this text as an error on purpose
-- (EXPECTED_ERRORS in tools/harness/driver.lua): change it there too.
function ns.RaiseTest()
  error(TEST_TEXT .. ": raised on purpose by /ftrace test, nothing is wrong")
end

-- How many times the test error is in the record, and its entry.
local function testSeen()
  local count, found = 0, nil
  for _, entry in ipairs(ForeverTraceDB.errors) do
    if entry.kind == "error" and entry.message:find(TEST_TEXT, 1, true) then
      count = count + entry.count
      found = entry
    end
  end
  return count, found
end

local function testResult(before)
  testing = false
  local count, entry = testSeen()
  local caught = count > before
  if entry then
    entry.test = true
  end
  if ns.session then
    ns.session.test = caught
  end
  ns.Push("test", nil, caught and "the Lua error was recorded" or "the Lua error was not recorded")
  if caught then
    ns.Print("|cff40c040the test error was recorded|r as #" .. entry.id .. ": the Lua errors of this client are seen.")
  elseif ns.hooked then
    ns.Print("|cffc04040the test error was not recorded|r: the hook is in place, but the game did not call it. Lua errors are not seen on this client.")
  else
    ns.Print("|cffc04040the test error was not recorded|r: the error window of the game is not there.")
  end
  ns.Changed()
end

function ns.Test()
  if not ns.GetOption("enabled") then
    ns.Print("the recording is off: /ftrace record turns it on.")
    return
  end
  if testing then
    return
  end
  testing = true
  local before = testSeen()
  ns.Print("raising one harmless error on purpose. The game may show its error window: that is the test.")
  C_Timer.After(TEST_SECONDS, function()
    ns.Safely(testResult, before)
  end)
  C_Timer.After(0, function()
    ns.RaiseTest()
  end)
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
  elseif command == "marks" then
    marks(rest)
  elseif command == "test" then
    ns.Test()
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
    ns.Print("the stored errors, events and markers are deleted.")
  elseif command == "options" or command == "config" or command == "settings" then
    ns.OpenSettings()
  else
    help()
  end
end
