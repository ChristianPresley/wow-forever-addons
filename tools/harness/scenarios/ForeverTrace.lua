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
expect(bags.versions.ForeverBags == "0.3.1" and bags.versions.ForeverGear == "0.2.0", "the error has the versions of the Forever addons")
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
T.fire("PLAYER_REGEN_DISABLED")
expect(lastEvent().kind == "fight" and lastEvent().text == "start", "the start of a fight is an event")
raise("Interface/AddOns/ForeverMeter/Core.lua:77: in the fight", "")
expect(lastError().first.fight == true, "an error in a fight says so")
T.advance(3)
T.fire("PLAYER_REGEN_ENABLED")
expect(lastEvent().kind == "fight" and lastEvent().text == "end after 3 s" and lastEvent().fight == false, "the end of the fight has its length")
T.world.zone = "Westfall"
T.fire("ZONE_CHANGED_NEW_AREA")
expect(lastEvent().kind == "zone" and lastEvent().text == "Westfall" and lastEvent().map == 52, "a new zone is an event")
raise("Interface/AddOns/ForeverMeter/Core.lua:78: in Westfall", "")
expect(lastError().first.zone == "Westfall" and lastError().first.map == 52, "an error has the zone it happened in")
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
T.slash("/ftrace", "screenshots")
Screenshot = realShot

-- Commands.
T.slash("/ftrace", "status")
expect(T.printed("session 1, recording .+ errors stored %(%d+ of Forever addons%), %d+ events"), "/ftrace status has the counts")
expect(T.printed("last: #%d+ error in ForeverQuests, 1 times"), "/ftrace status has the last error")
T.slash("/ftrace", "show 3")
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

-- The limits: the oldest go.
ns.SetOption("ring", 50)
for number = 1, 150 do
  ForeverTrace.Log("ForeverBags", "line " .. number)
end
expect(#db.events <= 100 and lastEvent().text == "line 150", "the ring stays near its limit while it fills: " .. #db.events)
ns.Tidy()
expect(#db.events == 50 and db.events[1].text == "line 101", "at logout the ring has its last 50 events")
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
expect(#db.errors == 0 and #db.events == 0 and db.session == 1, "/ftrace clear deletes the errors and the events, not the session")
raise(BAGS, BAGS_STACK)
expect(#db.errors == 1 and lastError().count == 1, "after the deletion an old error is new again")
ns.SetOption("ring", 300)
ns.SetOption("errors", 100)
