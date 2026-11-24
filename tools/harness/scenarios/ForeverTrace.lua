-- What Forever Trace does, with checks. T is the test table of the driver (see driver.lua).
local T = ...
local H, ns, expect = T.H, T.ns, T.expect
local db = ForeverTraceDB

local function lastEvent()
  return db.events[#db.events]
end
local function lastError()
  return db.errors[#db.errors]
end
-- An error as the game's handler hands it to its error window.
local function raise(message, stack, locals)
  ScriptErrorsFrame:DisplayMessageInternal(message, 0, stack or "", locals)
end

-- The login: a session with its number, and the login in the ring.
expect(db.version == 1 and db.session == 1, "the first login is session 1")
expect(#db.sessions == 1 and db.sessions[1].session == 1 and db.sessions[1].how == "login", "the session is stored as a login")
expect(type(db.sessions[1].build) == "string" and type(db.sessions[1].versions) == "table", "the session has the build and the versions")
expect(db.events[1] and db.events[1].kind == "login" and db.events[1].zone == "Elwynn Forest" and db.events[1].map == 37, "the login is the first event, with the zone and the map")
expect(db.events[1].t and db.events[1].at:find("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$") and db.events[1].session == 1 and db.events[1].fight == false, "an event has the time, the session and the fight")

-- The loaded addons: the Forever ones with their versions, the others by name.
local addOns = { { "ForeverBags", true, "0.3.1" }, { "Questie", true, "11.2" }, { "ForeverGear", false, "0.2.0" }, { "ForeverMeter", true, nil } }
local realNum, realInfo, realLoaded, realMeta = C_AddOns.GetNumAddOns, C_AddOns.GetAddOnInfo, C_AddOns.IsAddOnLoaded, C_AddOns.GetAddOnMetadata
C_AddOns.GetNumAddOns = function() return #addOns end
C_AddOns.GetAddOnInfo = function(position) return addOns[position][1] end
C_AddOns.IsAddOnLoaded = function(position) return addOns[position][2] end
C_AddOns.GetAddOnMetadata = function(name)
  for _, entry in ipairs(addOns) do
    if entry[1] == name then
      return entry[3]
    end
  end
end
local versions, others = ns.ReadAddons()
expect(versions.ForeverBags == "0.3.1" and versions.ForeverMeter == "?" and versions.ForeverGear == nil and versions.Questie == nil, "the versions of the loaded Forever addons")
expect(#others == 1 and others[1] == "Questie", "the other loaded addons by name")
ns.versions = versions
-- An addon that loads later joins the versions.
addOns[3][2] = true
T.fire("ADDON_LOADED", "ForeverGear", false)
expect(ns.versions.ForeverGear == "0.2.0" and lastEvent().kind == "loaded" and lastEvent().addon == "ForeverGear", "an addon that loads on demand is added")
C_AddOns.GetNumAddOns, C_AddOns.GetAddOnInfo, C_AddOns.IsAddOnLoaded, C_AddOns.GetAddOnMetadata = realNum, realInfo, realLoaded, realMeta

-- Lua errors come through the error window of the game.
expect(ns.hooked == true and db.sessions[1].hook == true, "the error window of the game is hooked at the login")
local BAGS = "Interface/AddOns/ForeverBags/Core.lua:12: attempt to index local 'slot' (a nil value)"
local BAGS_STACK = "[Interface/AddOns/ForeverBags/Core.lua]:12: in function <Interface/AddOns/ForeverBags/Core.lua:10>"
raise(BAGS, BAGS_STACK, "slot = nil")
local bags = lastError()
expect(#db.errors == 1 and bags.kind == "error" and bags.message == BAGS and bags.stack == BAGS_STACK and bags.locals == "slot = nil", "a Lua error is stored with its message, stack and locals")
expect(bags.addon == "ForeverBags" and bags.forever == "ForeverBags" and bags.ours == true, "the path says that it is an error of Forever Bags")
expect(bags.count == 1 and bags.first.session == 1 and bags.first.zone == "Elwynn Forest" and bags.first.map == 37 and bags.first.fight == false, "the error has the session, the place and the fight")
expect(bags.version == "0.3.1" and bags.versions == nil, "the error has the version of its Forever addon, not the whole list")
expect(T.printed("error in ForeverBags: Interface/AddOns/ForeverBags/Core.lua:12"), "a new error is said in the chat")
expect(lastEvent().kind == "error" and lastEvent().addon == "ForeverBags" and lastEvent().text:find("^#1 "), "a new error is an event of the ring")
local eventsBefore = #db.events
raise(BAGS, BAGS_STACK, "slot = nil")
raise(BAGS, BAGS_STACK, "slot = nil")
expect(#db.errors == 1 and bags.count == 3 and #db.events == eventsBefore, "a repeat is counted, not stored again")
-- The same message from another place is another error.
raise(BAGS, "[Interface/AddOns/ForeverBags/Window.lua]:40: in function 'Refresh'")
expect(#db.errors == 2 and lastError().count == 1, "the same message with another stack is another error")
raise("Interface/AddOns/Questie/Modules/Map.lua:7: boom", "[Interface/AddOns/Questie/Modules/Map.lua]:7: in function 'Draw'")
expect(lastError().addon == "Questie" and lastError().ours == false and lastError().forever == nil, "an error of another addon is stored as not ours")
raise("Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:900: bad argument", "[Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua]:900: in function 'Update'\n[Interface/AddOns/ForeverGear/Core.lua]:55: in function 'Scan'")
expect(lastError().addon == "Blizzard_UIPanels_Game" and lastError().forever == "ForeverGear" and lastError().ours == true, "an error in the game's code that a Forever addon called is ours")
local before = #db.errors
ScriptErrorsFrame:DisplayMessageInternal("a warning of the game", 1)
expect(#db.errors == before, "a warning in the error window is not stored as an error")
-- A hidden message is stored as the word, not as the value.
local hidden = ns.Record("error", H.secret("Interface/AddOns/ForeverMeter/Core.lua:1: hidden"), H.secret("stack"), H.secret("locals"))
expect(hidden.message == "secret" and hidden.stack == "secret" and hidden.locals == "secret" and hidden.addon == "?", "a secret message is stored as the text secret")

-- The errors from before the addon loaded are read from the error window.
before = #db.errors
local found = ns.ReadEarlier({ errorData = {
  { count = 4, messageType = 0, message = "Interface/AddOns/ForeverAtlas/Core.lua:3: early", stack = "[Interface/AddOns/ForeverAtlas/Core.lua]:3: in main chunk", locals = "" },
  { count = 1, messageType = 1, message = "an early warning" },
  { count = 1, messageType = 0, message = "Interface/AddOns/ForeverAuctions/Scan.lua:9: early too", stack = "" },
} })
expect(found == 2 and #db.errors == before + 2, "two early errors are read, the warning is not")
expect(db.errors[before + 1].early == true and db.errors[before + 1].count == 4 and db.errors[before + 1].addon == "ForeverAtlas", "an early error keeps its count and is marked")
expect(ns.ReadEarlier({}) == 0, "an error window without a list gives nothing")

-- Blocked actions and warnings.
T.fire("ADDON_ACTION_BLOCKED", "ForeverBags", "UseContainerItem()")
expect(lastError().kind == "blocked" and lastError().addon == "ForeverBags" and lastError().ours == true and lastError().message == "ForeverBags was blocked from UseContainerItem()", "a blocked action is stored with the addon and the function")
expect(not lastError().stack:find("ForeverTrace", 1, true), "the stack of a blocked action has no line of Forever Trace")
T.fire("ADDON_ACTION_BLOCKED", "ForeverBags", "UseContainerItem()")
expect(lastError().count == 2, "the same blocked action again is counted")
T.fire("ADDON_ACTION_FORBIDDEN", "Questie", "CastSpellByName()")
expect(lastError().kind == "forbidden" and lastError().addon == "Questie" and lastError().ours == false, "a forbidden action of another addon is not ours")
T.fire("MACRO_ACTION_BLOCKED", "TargetUnit()")
expect(lastError().kind == "blocked" and lastError().addon == "(macro)" and lastError().message:find("TargetUnit()", 1, true), "a blocked macro is stored")
T.fire("LUA_WARNING", "Lua Taint: Interface/AddOns/ForeverCompass/Core.lua:20 tainted ActionButton1")
expect(lastError().kind == "taint" and lastError().addon == "ForeverCompass" and lastError().ours == true, "a taint message is stored with its addon")
T.fire("LUA_WARNING", "Deprecated function called")
expect(lastError().kind == "warning", "another warning is a warning")

-- A fight and a new zone are events, and the next error has them.
local before = #db.events
T.fire("PLAYER_REGEN_DISABLED")
expect(#db.events == before, "the start of a fight is not a line of the ring")
raise("Interface/AddOns/ForeverMeter/Core.lua:77: in the fight", "")
expect(lastError().first.fight == true and lastEvent().fight == true, "an error in a fight says so")
T.advance(3)
T.fire("PLAYER_REGEN_ENABLED")
expect(lastEvent().kind == "fight" and lastEvent().text == "lasted 3 s" and lastEvent().seconds == 3 and lastEvent().fight == false, "a fight is one line at its end, with its length")
-- Fights with nothing between them are one line.
before = #db.events
for _ = 1, 3 do
  T.fire("PLAYER_REGEN_DISABLED")
  T.advance(5)
  T.fire("PLAYER_REGEN_ENABLED")
  T.advance(2)
end
expect(#db.events == before and lastEvent().n == 4 and lastEvent().seconds == 18 and lastEvent().text == "4 fights, 18 s in all" and type(lastEvent().till) == "string", "fights in a row are one line: " .. tostring(lastEvent().text))
ForeverTrace.Log("ForeverMeter", "between two fights")
T.fire("PLAYER_REGEN_DISABLED")
T.advance(2)
T.fire("PLAYER_REGEN_ENABLED")
expect(#db.events == before + 2 and lastEvent().text == "lasted 2 s" and lastEvent().n == nil, "a fight after another event is a new line")

T.world.zone = "Westfall"
T.fire("ZONE_CHANGED_NEW_AREA")
expect(lastEvent().kind == "zone" and lastEvent().text == "Westfall" and lastEvent().map == 52 and lastEvent().from == "Elwynn Forest", "a new zone is an event, with the zone before")
raise("Interface/AddOns/ForeverMeter/Core.lua:78: in Westfall", "")
expect(lastError().first.zone == "Westfall" and lastError().first.map == 52, "an error has the zone it happened in")
-- The same zone again is no new line.
before = #db.events
T.fire("ZONE_CHANGED_NEW_AREA")
expect(#db.events == before, "the event of a new zone without a new zone is no line")
-- At a border the zone flips: one line for the border, with the crossings.
T.world.zone = "Duskwood"
T.fire("ZONE_CHANGED_NEW_AREA")
before = #db.events
for _ = 1, 3 do
  T.advance(2)
  T.world.zone = "Westfall"
  T.fire("ZONE_CHANGED_NEW_AREA")
  T.advance(2)
  T.world.zone = "Duskwood"
  T.fire("ZONE_CHANGED_NEW_AREA")
end
expect(#db.events == before and lastEvent().text == "Duskwood" and lastEvent().zone == "Duskwood" and lastEvent().from == "Westfall" and lastEvent().n == 7, "flips over one border are one line: " .. tostring(lastEvent().n))
T.advance(2)
T.world.zone = "Stranglethorn Vale"
T.fire("ZONE_CHANGED_NEW_AREA")
expect(#db.events == before + 1 and lastEvent().from == "Duskwood" and lastEvent().n == nil, "a third zone is a new line")
T.advance(120)
T.world.zone = "Duskwood"
T.fire("ZONE_CHANGED_NEW_AREA")
expect(#db.events == before + 2 and lastEvent().n == nil, "a way back after a long time is a new line")
-- The game gives the map of the zone before at the event, and the right one a moment later.
local realMap = C_Map.GetBestMapForUnit
C_Map.GetBestMapForUnit = function() return 1414 end
T.world.zone = "Westfall"
T.fire("ZONE_CHANGED_NEW_AREA")
expect(lastEvent().map == 1414, "at the event the line has the map that the game gives")
C_Map.GetBestMapForUnit = realMap
T.advance(2)
expect(lastEvent().text == "Westfall" and lastEvent().map == 52 and ns.where.map == 52, "a moment later the line has the right map")
-- No map inside an instance: /ftrace status says so.
C_Map.GetBestMapForUnit = function() return nil end
T.slash("/ftrace", "status")
expect(T.printed("here: Westfall, no map ID: the game gives none here"), "/ftrace status says that the game gives no map here")
C_Map.GetBestMapForUnit = realMap
T.slash("/ftrace", "status")
expect(T.printed("here: Westfall, map 52"), "/ftrace status says the zone and the map")
T.world.zone = nil
T.fire("PLAYER_ENTERING_WORLD", false, false)
expect(lastEvent().kind == "world" and lastEvent().text == "Elwynn Forest" and db.sessions[1].how == "login", "a loading screen is an event, and does not change how the session started")

-- The calls for the other addons.
ForeverTrace.Log("ForeverBags", "the bank opened")
expect(lastEvent().kind == "log" and lastEvent().addon == "ForeverBags" and lastEvent().text == "the bank opened" and lastEvent().n == nil, "an addon logs a line")
before = #db.events
ForeverTrace.Log("ForeverBags", "the bank opened")
expect(#db.events == before and lastEvent().n == 2, "the same line directly again is counted")
ForeverTrace.Log("ForeverBags", H.secret("12 health"))
expect(lastEvent().text == "secret", "a hidden text in a log line is stored as the word")
ForeverTrace.Error("ForeverGear", "the scan failed: no item")
expect(lastError().kind == "reported" and lastError().addon == "ForeverGear" and lastError().ours == true and lastError().message == "the scan failed: no item", "an addon reports an error that it caught")
ForeverTrace.Error("Questie", "not ours")
expect(lastError().addon == "Questie" and lastError().ours == false, "a report of another addon is not ours")
before = #db.errors
ForeverTrace.Log()
ForeverTrace.Log({}, function() end)
ForeverTrace.Error()
ForeverTrace.Mark()
expect(#db.errors == before + 1 and lastError().message == "?" and lastEvent().kind == "mark" and lastEvent().text == "marker", "calls without arguments raise no error")

-- An error of the addon itself is counted, not raised.
local internal = db.internal.count
expect(ns.Safely(function() error("inside") end) == nil and db.internal.count == internal + 1 and db.internal.last:find("inside", 1, true), "an error of Forever Trace itself is caught and counted")

-- Screenshots: off at first; on, one for each new error, with a gap.
local realShot = Screenshot
local shots = 0
Screenshot = function() shots = shots + 1 end
expect(ns.GetOption("screenshots") == false, "screenshots are off until the player turns them on")
raise("Interface/AddOns/ForeverQuests/Core.lua:1: no shot", "")
T.advance(1)
expect(shots == 0 and lastError().shot == nil, "no screenshot while the option is off")
T.slash("/ftrace", "screenshots")
expect(ns.GetOption("screenshots") == true, "/ftrace screenshots turns them on")
raise("Interface/AddOns/ForeverQuests/Core.lua:2: first shot", "")
local shotFor = lastError()
T.advance(1)
expect(shots == 1, "a new error takes a screenshot")
T.fire("SCREENSHOT_STARTED")
T.fire("SCREENSHOT_SUCCEEDED")
expect(type(shotFor.shot) == "string" and shotFor.shot:find("^%d%d%d%d%d%d_%d%d%d%d%d%d$") and lastEvent().kind == "screenshot", "the error has the time in the name of its screenshot: " .. tostring(shotFor.shot))
raise("Interface/AddOns/ForeverQuests/Core.lua:2: first shot", "")
raise("Interface/AddOns/ForeverQuests/Core.lua:3: too soon", "")
T.advance(1)
expect(shots == 1, "no screenshot for a repeat, and none for a new error within the gap")
T.advance(ns.GetOption("shotGap"))
raise("Interface/AddOns/ForeverQuests/Core.lua:4: after the gap", "")
shotFor = lastError()
T.advance(1)
T.fire("SCREENSHOT_FAILED")
expect(shots == 2 and shotFor.shot == "failed", "after the gap the next new error takes one, and a failure is stored")
before = #db.events
T.fire("SCREENSHOT_SUCCEEDED")
expect(#db.events == before, "a screenshot of the player is not an event")
T.slash("/ftrace", "shot")
T.advance(1)
T.fire("SCREENSHOT_SUCCEEDED")
expect(shots == 3 and T.printed("the screenshot worked"), "/ftrace shot takes one and says that it worked")
T.slash("/ftrace", "mark the bag window looks wrong")
T.advance(1)
expect(shots == 4 and db.events[#db.events].kind == "mark" and db.events[#db.events].text == "the bag window looks wrong", "/ftrace mark stores the text and takes a screenshot")
T.fire("SCREENSHOT_SUCCEEDED")
local mark = db.marks[#db.marks]
expect(mark.text == "the bag window looks wrong" and mark.zone == "Elwynn Forest" and mark.session == 1 and type(mark.shot) == "string" and mark.shot:find("^%d%d%d%d%d%d_%d%d%d%d%d%d$"), "the marker is in its own list, with the place and the name of its screenshot")
T.slash("/ftrace", "marks")
expect(T.printed("Elwynn Forest: the bag window looks wrong %(screenshot %d+_%d+"), "/ftrace marks lists the markers")

-- Which screenshot belongs to which entry.
local function lastMarks(count)
  local out = {}
  for position = #db.marks - count + 1, #db.marks do
    out[#out + 1] = db.marks[position]
  end
  return unpack(out)
end
-- The screenshot of a marker is taken on the next frame; the one of an error waits half a second.
local shotsBefore = shots
ns.Mark("at once")
T.advance(0.05)
expect(shots == shotsBefore + 1, "the screenshot of a marker is taken on the next frame")
T.fire("SCREENSHOT_STARTED")
T.fire("SCREENSHOT_SUCCEEDED")
T.advance(ns.GetOption("shotGap"))
raise("Interface/AddOns/ForeverQuests/Core.lua:6: with the error window", "")
ns.Mark("while an error waits")
T.advance(0.05)
expect(shots == shotsBefore + 2 and lastError().shot == nil, "the screenshot of an error waits, the one of a marker does not wait with it")
T.fire("SCREENSHOT_STARTED")
T.fire("SCREENSHOT_SUCCEEDED")
expect(db.marks[#db.marks].shot ~= nil and lastError().shot == nil, "the first screenshot is the marker's")
T.advance(1)
T.fire("SCREENSHOT_STARTED")
T.fire("SCREENSHOT_SUCCEEDED")
expect(shots == shotsBefore + 3 and lastError().shot ~= nil and lastError().shot ~= "failed", "half a second later the error has its own screenshot")
-- Two markers before the screenshot is taken: one screenshot, and both have its name.
shotsBefore = shots
ns.Mark("first of two")
ns.Mark("second of two")
T.advance(1)
T.fire("SCREENSHOT_STARTED")
T.fire("SCREENSHOT_SUCCEEDED")
local one, two = lastMarks(2)
expect(shots == shotsBefore + 1 and one.shot ~= nil and one.shot ~= "failed" and one.shot == two.shot, "two markers before one screenshot both have its name")
-- Two screenshots on the way at the same time: each entry gets the result of its own.
ns.Mark("the first call")
T.advance(1)
ns.Mark("the second call")
T.advance(1)
T.fire("SCREENSHOT_STARTED")
T.fire("SCREENSHOT_STARTED")
T.fire("SCREENSHOT_SUCCEEDED")
T.fire("SCREENSHOT_FAILED")
one, two = lastMarks(2)
expect(shots == shotsBefore + 3 and one.shot ~= nil and one.shot ~= "failed" and two.shot == "failed", "two screenshots on the way: the first entry has the first result, the second the second")
-- The player presses Print Screen before the addon's own call: the marker does not take that one.
ns.Mark("the player was faster")
local eventsNow = #db.events
T.fire("SCREENSHOT_STARTED")
T.fire("SCREENSHOT_SUCCEEDED")
one = lastMarks(1)
expect(one.shot == nil and #db.events == eventsNow, "a screenshot of the player before the addon's call is not given to the marker")
T.advance(1)
T.fire("SCREENSHOT_STARTED")
T.fire("SCREENSHOT_SUCCEEDED")
expect(shots == shotsBefore + 4 and one.shot ~= nil and one.shot ~= "failed", "the marker gets the addon's own screenshot")
-- A screenshot of the player while the addon's one is on the way: the order of the starts decides.
ns.Mark("the player was second")
T.advance(1)
T.fire("SCREENSHOT_STARTED")
T.fire("SCREENSHOT_STARTED")
T.fire("SCREENSHOT_SUCCEEDED")
one = lastMarks(1)
eventsNow = #db.events
T.fire("SCREENSHOT_FAILED")
expect(one.shot ~= nil and one.shot ~= "failed" and #db.events == eventsNow, "a screenshot of the player after the addon's start does not change the marker")
-- The clock goes on between the call and the end: all names that the file can have are stored.
local realTime = time
local late = 0
time = function() return realTime() + late end
ns.Mark("a slow screenshot")
T.advance(1)
T.fire("SCREENSHOT_STARTED")
late = 1
T.fire("SCREENSHOT_SUCCEEDED")
time = realTime
one = lastMarks(1)
expect(type(one.shots) == "table" and #one.shots >= 2 and one.shots[1] == one.shot and one.shots[2] ~= one.shot and lastEvent().text == table.concat(one.shots, " or "), "a screenshot over more than one second has each name that the file can have: " .. tostring(one.shot) .. " / " .. tostring(one.shots and table.concat(one.shots, ",")) .. " / " .. tostring(lastEvent().text))
expect(two.shots == nil, "a screenshot within one second has one name")
-- The game says nothing after the call: the entry does not wait for ever.
ns.Mark("no answer")
T.advance(1)
one = lastMarks(1)
expect(one.shot == nil, "before the game answers the marker has no name")
T.advance(15)
expect(one.shot == "failed", "a call that the game does not answer is stored as failed")
eventsNow = #db.events
T.fire("SCREENSHOT_SUCCEEDED")
expect(#db.events == eventsNow, "a later screenshot of the player is still not an event")
T.slash("/ftrace", "screenshots")
Screenshot = realShot

-- Commands.
T.slash("/ftrace", "status")
expect(T.printed("session 1, recording .+ errors stored %(%d+ of Forever addons%), %d+ events"), "/ftrace status has the counts")
expect(T.printed("last: #%d+ error in ForeverQuests, 1 times"), "/ftrace status has the last error")
T.slash("/ftrace", "show 50")
expect(T.printed("mark: the bag window looks wrong"), "/ftrace show lists the last events")
T.slash("/ftrace", "errors")
expect(T.printed("in Questie %(not ours%)"), "/ftrace errors marks the errors of other addons")
T.slash("/ftrace", "record")
before = #db.errors
local eventCount = #db.events
raise("Interface/AddOns/ForeverQuests/Core.lua:5: while off", "")
ForeverTrace.Log("ForeverBags", "while off")
T.slash("/ftrace", "mark while off")
expect(ns.GetOption("enabled") == false and #db.errors == before and #db.events == eventCount, "with the recording off nothing is stored")
T.slash("/ftrace", "record")
expect(ns.GetOption("enabled") == true, "/ftrace record turns it on again")
expect(ns.SetOption("noSuchOption", 1) == false, "an option that does not exist is refused")

-- /ftrace test raises one error and says if the record caught it. Here the error is handed to
-- the error window as the game's handler does it.
local realRaise = ns.RaiseTest
ns.RaiseTest = function()
  raise("Interface/AddOns/ForeverTrace/Commands.lua:1: Forever Trace test error: raised on purpose", "[Interface/AddOns/ForeverTrace/Commands.lua]:1: in function 'RaiseTest'")
end
T.slash("/ftrace", "status")
expect(T.printed("the hook is in place, not proved in this session"), "before the test /ftrace status says that nothing is proved")
T.slash("/ftrace", "test")
T.advance(2)
expect(db.sessions[1].test == true and lastError().test == true and lastEvent().kind == "test" and T.printed("the test error was recorded"), "/ftrace test says that the error was recorded")
T.slash("/ftrace", "status")
expect(T.printed("Lua errors: seen, proved by /ftrace test"), "after the test /ftrace status says that it is proved")
-- A client that does not hand the error to the error window.
ns.RaiseTest = function() end
T.slash("/ftrace", "test")
T.advance(2)
expect(db.sessions[1].test == false and lastEvent().text == "the Lua error was not recorded" and T.printed("the test error was not recorded"), "/ftrace test says so when the error was not recorded")
ns.RaiseTest = function()
  raise("Interface/AddOns/ForeverTrace/Commands.lua:1: Forever Trace test error: raised on purpose", "[Interface/AddOns/ForeverTrace/Commands.lua]:1: in function 'RaiseTest'")
end
T.slash("/ftrace", "test")
T.advance(2)
expect(db.sessions[1].test == true and lastError().count == 2, "the test error again is counted, and proves it again")
ns.RaiseTest = realRaise

-- The limits: the oldest go.
ns.SetOption("ring", 50)
for number = 1, 150 do
  ForeverTrace.Log("ForeverBags", "line " .. number)
end
expect(#db.events <= 100 and lastEvent().text == "line 150", "the ring stays near its limit while it fills: " .. #db.events)
ns.Tidy()
expect(#db.events == 50 and db.events[1].text == "line 101", "at logout the ring has its last 50 events")
local inRing = false
for _, entry in ipairs(db.events) do
  inRing = inRing or entry.kind == "mark"
end
expect(not inRing and #db.marks >= 2 and db.marks[#db.marks].text == "no answer", "the events pushed the markers out of the ring, not out of their list")
for number = 1, 200 do
  ns.Mark("marker " .. number)
end
ns.Tidy()
expect(#db.marks == 100 and db.marks[100].text == "marker 200", "the list of markers keeps the last 100")
ns.SetOption("errors", 20)
for number = 1, 30 do
  T.advance(1)
  raise("Interface/AddOns/ForeverBags/Core.lua:" .. number .. ": many", "")
end
expect(#db.errors == 20 and db.errors[1].message:find(":11: many", 1, true) and lastError().message:find(":30: many", 1, true), "only the 20 errors that were seen last are kept")
raise("Interface/AddOns/ForeverBags/Core.lua:1: many", "")
expect(#db.errors == 20 and lastError().count == 1, "an error that was dropped is a new one when it comes again")
ns.SetOption("ring", 9999)
expect(ns.GetOption("ring") == 1000, "the ring stops at 1000 events")

-- Deleting.
T.slash("/ftrace", "clear")
expect(#db.errors == 0 and #db.events == 0 and #db.marks == 0 and db.session == 1, "/ftrace clear deletes the errors, the events and the markers, not the session")
raise(BAGS, BAGS_STACK)
expect(#db.errors == 1 and lastError().count == 1, "after the deletion an old error is new again")
ns.SetOption("ring", 300)
ns.SetOption("errors", 100)
