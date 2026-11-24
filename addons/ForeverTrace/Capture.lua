local ADDON, ns = ...

-- What the game tells, and how this addon hears it.
--
-- Lua errors. The game's own handler (Blizzard_ScriptErrors/Blizzard_ScriptErrors.lua) hands
-- each error, with its stack and locals, to ScriptErrorsFrame:DisplayMessageInternal
-- (Blizzard_ScriptErrorsFrame/Blizzard_ScriptErrorsFrame.lua), also when the error window is off.
-- A hook with hooksecurefunc runs after that function: the game's handler stays in place, the
-- error is shown as before, and no code of the game runs as addon code. The other two ways are
-- closed or dirty: AddLuaErrorHandler is for the game's own code only, and seterrorhandler puts
-- addon code in the place of the game's handler.
--
-- Blocked actions and warnings come as events.

local SHOT_DELAY = 0.5 -- the error window of the game is on the screen by then
local SHOT_WAIT = 10 -- seconds until a call of Screenshot() that the game did not answer is "failed"
local SHOT_NAMES = 3 -- seconds after the call whose names are stored at most
local SETTLE_SECONDS = 1 -- after a zone event the game gives the right map by then
local BORDER_SECONDS = 60 -- a crossing back within this time is the same border

---------------------------------------------------------------------------------------------------
-- Screenshots

-- One call of Screenshot() is one batch: { entries = the errors and markers it is for,
-- test = true for /ftrace shot, from = time() of the call, done }. An entry that asks while a
-- batch waits for its call joins that batch, so no entry loses its screenshot to the next one.
--
-- Which screenshot of the game is which batch: the game says SCREENSHOT_STARTED and then
-- SCREENSHOT_SUCCEEDED or SCREENSHOT_FAILED for each screenshot, in the order of the calls. A
-- start that no call of this addon waits for is a screenshot of the player (the Print Screen
-- key): it is followed to its end, and no entry gets it.
local lastShot = nil -- GetTime() of the last request
local waiting = nil -- the batch of the next call
local called = {} -- the batches whose call is made and which the game has not started, the oldest first
local started = {} -- the screenshots that the game has started, the oldest first: a batch, or false for one of the player

-- The time in the file name of a screenshot: Screenshots/WoWScrnShot_MMDDYY_HHMMSS.jpg.
local function shotName(t)
  return date("%m%d", t) .. date("%Y", t):sub(3) .. "_" .. date("%H%M%S", t)
end

local function drop(list, batch)
  for position = #list, 1, -1 do
    if list[position] == batch then
      table.remove(list, position)
    end
  end
end

-- The end of a batch. The game takes the time for the file name at some moment between the call
-- and the end. Mostly that is one second, and `shot` is the name. If the clock went on in
-- between, the file has one of the names in `shots`.
local function finish(batch, ok)
  if batch.done then
    return
  end
  batch.done = true
  local name, names = "failed", nil
  if ok then
    local from, to = batch.from, time()
    if to < from or to - from > SHOT_NAMES then
      to = from + SHOT_NAMES
    end
    name = shotName(from)
    if to > from then
      names = {}
      for t = from, to do
        names[#names + 1] = shotName(t)
      end
    end
  end
  for _, entry in ipairs(batch.entries) do
    entry.shot, entry.shots = name, names
  end
  ns.Push("screenshot", nil, names and table.concat(names, " or ") or name)
  if batch.test then
    if ok then
      ns.Print("the screenshot worked: WoWScrnShot_" .. name .. ".jpg in the Screenshots folder. /ftrace screenshots turns them on for new errors.")
    else
      ns.Print("the game did not take the screenshot.")
    end
  end
  ns.Changed()
end

-- The game said nothing about a call for SHOT_WAIT seconds: its entries do not wait for ever.
local function expire(batch)
  drop(called, batch)
  drop(started, batch)
  finish(batch, false)
end

local function take(batch)
  if waiting == batch then
    waiting = nil
  end
  batch.from = time()
  called[#called + 1] = batch
  C_Timer.After(SHOT_WAIT, function()
    ns.Safely(expire, batch)
  end)
  Screenshot()
end

local function shoot(entry, test)
  lastShot = GetTime()
  local batch = waiting
  if not batch then
    batch = { entries = {} }
    waiting = batch
    C_Timer.After(test and 0 or SHOT_DELAY, function()
      ns.Safely(take, batch)
    end)
  end
  if entry then
    batch.entries[#batch.entries + 1] = entry
  end
  batch.test = batch.test or test or nil
end

-- A screenshot for a new error, if the option is on and the last one is long enough ago.
function ns.ShootFor(entry)
  if not ns.GetOption("screenshots") then
    return false
  end
  if lastShot and GetTime() - lastShot < ns.GetOption("shotGap") then
    return false
  end
  shoot(entry, false)
  return true
end

-- /ftrace shot: one screenshot now, to see if this client lets an addon take one.
function ns.TestShot()
  shoot(nil, true)
end

local function shotStarted()
  started[#started + 1] = table.remove(called, 1) or false
end

local function shotDone(ok)
  local batch
  if #started > 0 then
    batch = table.remove(started, 1)
  else
    -- An end without a start: of a call of this addon, if one waits.
    batch = table.remove(called, 1)
  end
  if batch then
    finish(batch, ok)
  end
end

---------------------------------------------------------------------------------------------------
-- Lua errors

-- The stack from `level`, without the lines of this addon: what is left is who called.
function ns.CallerStack(level)
  local stack = debugstack(level)
  if issecretvalue(stack) or type(stack) ~= "string" then
    return ""
  end
  return (stack:gsub("[^\n]*AddOns[/\\]" .. ADDON .. "[/\\][^\n]*\n?", ""))
end

local function recorded(entry, isNew)
  if entry and isNew then
    ns.ShootFor(entry)
  end
end

-- Runs after ScriptErrorsFrame:DisplayMessageInternal(message, messageType, stack, locals).
-- messageType 0 is an error, 1 is a warning; the warnings come as the event LUA_WARNING too.
local function onDisplay(_, message, messageType, stack, locals)
  if issecretvalue(messageType) or messageType ~= 0 then
    return
  end
  recorded(ns.Record("error", message, stack, locals))
end

-- The errors that the game showed before this addon loaded: the Forever addons with a name
-- before "ForeverTrace" load first.
function ns.ReadEarlier(frame)
  local data = frame.errorData
  if type(data) ~= "table" then
    return 0
  end
  local found = 0
  for position = 1, #data do
    local shown = data[position]
    if type(shown) == "table" and not issecretvalue(shown.messageType) and shown.messageType == 0 then
      local entry = ns.Record("error", shown.message, shown.stack, shown.locals, nil, true)
      if entry then
        found = found + 1
        local count = shown.count
        if not issecretvalue(count) and type(count) == "number" and count > 1 then
          entry.count = entry.count + count - 1
        end
      end
    end
  end
  return found
end

local function attach()
  local frame = ScriptErrorsFrame
  if ns.hooked or not frame then
    return
  end
  hooksecurefunc(frame, "DisplayMessageInternal", function(...)
    ns.Safely(onDisplay, ...)
  end)
  ns.hooked = true
  local found = ns.ReadEarlier(frame)
  if found > 0 and ns.GetOption("announce") then
    ns.Print(found .. (found == 1 and " error" or " errors") .. " from before Forever Trace loaded. /ftrace errors lists them.")
  end
end

function ns.Attach()
  ns.Safely(attach)
  return ns.hooked
end

---------------------------------------------------------------------------------------------------
-- The session: the loaded addons and the build

function ns.ReadAddons()
  local versions, others = {}, {}
  for position = 1, C_AddOns.GetNumAddOns() do
    local name = C_AddOns.GetAddOnInfo(position)
    if type(name) == "string" and not issecretvalue(name) and C_AddOns.IsAddOnLoaded(position) then
      if name:find("^Forever") then
        versions[name] = ns.Plain(C_AddOns.GetAddOnMetadata(name, "Version"), 20) or "?"
      else
        others[#others + 1] = name
      end
    end
  end
  return versions, others
end

local session = nil -- the record of this session in ForeverTraceDB.sessions

local function startSession()
  local db = ForeverTraceDB
  local others
  ns.versions, others = ns.ReadAddons()
  local version, build = GetBuildInfo()
  session = {
    session = db.session,
    t = time(),
    at = date("%Y-%m-%d %H:%M:%S"),
    build = (ns.Plain(version, 20) or "?") .. " " .. (ns.Plain(build, 20) or "?"),
    character = ns.Plain(UnitName("player"), 40),
    versions = ns.versions,
    others = others,
    hook = false,
  }
  db.sessions[#db.sessions + 1] = session
  ns.session = session
  ns.inFight = InCombatLockdown() and true or false
  ns.ReadPlace()
  session.hook = ns.Attach()
end

---------------------------------------------------------------------------------------------------
-- Events

local fightStart = nil

local function is(value)
  return not issecretvalue(value) and value == true
end

local handlers = {}

function handlers.ADDON_LOADED(name)
  if issecretvalue(name) or type(name) ~= "string" then
    return
  end
  if name == "Blizzard_ScriptErrorsFrame" then
    local hooked = ns.Attach()
    if session then
      session.hook = hooked
    end
  elseif session and name ~= ADDON and name:find("^Forever") then
    -- An addon that loads on demand, after the login.
    ns.versions[name] = ns.Plain(C_AddOns.GetAddOnMetadata(name, "Version"), 20) or "?"
    ns.Push("loaded", name, ns.versions[name])
  end
end

-- At the event of a new zone the game often still gives the map of the zone before, or of the
-- continent. A second later it gives the right one: the place is read again, and the line of the
-- event gets it.
local function settled(entry)
  ns.ReadPlace()
  if entry and entry.zone == ns.where.zone then
    entry.map = ns.where.map
  end
end

local function settle(entry)
  C_Timer.After(SETTLE_SECONDS, function()
    ns.Safely(settled, entry)
  end)
end

function handlers.PLAYER_ENTERING_WORLD(isLogin, isReload)
  ns.ReadPlace()
  local how = is(isLogin) and "login" or is(isReload) and "reload" or "world"
  if session and not session.how and how ~= "world" then
    session.how = how
  end
  settle(ns.Push(how, nil, ns.where.zone))
end

local zoneLine = nil -- the last "zone" line of the ring
local zoneTime = nil -- GetTime() of its last change

-- Near a border the zone flips several times a second. One line holds one border: `from` is the
-- other side, `n` counts the crossings, and the stamp is that of the last one.
function handlers.ZONE_CHANGED_NEW_AREA()
  local from = ns.where.zone
  ns.ReadPlace()
  local zone = ns.where.zone
  local now = GetTime()
  local line = zoneLine
  if zone == from then
    settle(line)
    return
  end
  if line and line == ns.LastEvent() and line.from == zone and now - zoneTime < BORDER_SECONDS then
    line.from = line.text
    line.text, line.zone, line.map = zone, zone, ns.where.map
    line.n = (line.n or 1) + 1
    line.t, line.at = time(), date("%Y-%m-%d %H:%M:%S")
  else
    line = ns.Push("zone", nil, zone)
    if line then
      line.from = from
    end
  end
  zoneLine, zoneTime = line, now
  settle(line)
end

handlers.ZONE_CHANGED = ns.ReadPlace
handlers.ZONE_CHANGED_INDOORS = ns.ReadPlace

local fightLine = nil -- the last "fight" line of the ring

function handlers.PLAYER_REGEN_DISABLED()
  ns.inFight = true
  fightStart = GetTime()
end

-- One line for a fight, at its end: what happened in the fight is above it, with fight = true.
-- A fight directly after a fight line joins that line, so that an hour of fights does not push
-- everything else out of the ring.
function handlers.PLAYER_REGEN_ENABLED()
  ns.inFight = false
  local seconds = fightStart and math.floor(GetTime() - fightStart + 0.5)
  fightStart = nil
  local line = fightLine
  if seconds and line and line.seconds and line == ns.LastEvent() and ns.GetOption("enabled") then
    line.n = (line.n or 1) + 1
    line.seconds = line.seconds + seconds
    line.text = line.n .. " fights, " .. line.seconds .. " s in all"
    line.till = date("%Y-%m-%d %H:%M:%S")
    return
  end
  line = ns.Push("fight", nil, seconds and ("lasted " .. seconds .. " s") or "end")
  if line and seconds and not line.n then
    line.seconds = seconds
  end
  fightLine = line
end

-- The game refused an action because addon code was in the way. The event comes while the code
-- that asked for the action still runs, so the stack shows who asked.
local function blocked(kind, text, addon)
  recorded(ns.Record(kind, text, ns.CallerStack(2), nil, addon))
end

function handlers.ADDON_ACTION_BLOCKED(addon, action)
  addon = ns.Plain(addon, 60) or "?"
  blocked("blocked", addon .. " was blocked from " .. (ns.Plain(action, 200) or "?"), addon)
end

function handlers.ADDON_ACTION_FORBIDDEN(addon, action)
  addon = ns.Plain(addon, 60) or "?"
  blocked("forbidden", addon .. " may not call " .. (ns.Plain(action, 200) or "?"), addon)
end

function handlers.MACRO_ACTION_BLOCKED(action)
  blocked("blocked", "a macro was blocked from " .. (ns.Plain(action, 200) or "?"), "(macro)")
end

function handlers.MACRO_ACTION_FORBIDDEN(action)
  blocked("forbidden", "a macro may not call " .. (ns.Plain(action, 200) or "?"), "(macro)")
end

-- A warning of the game, for example "Lua Taint: ...".
function handlers.LUA_WARNING(text)
  text = ns.Plain(text, 1000) or "?"
  recorded(ns.Record(text:find("[Tt]aint") and "taint" or "warning", text, "", nil, nil))
end

handlers.SCREENSHOT_STARTED = shotStarted

function handlers.SCREENSHOT_SUCCEEDED()
  shotDone(true)
end

function handlers.SCREENSHOT_FAILED()
  shotDone(false)
end

function handlers.PLAYER_LOGOUT()
  ns.Push("logout", nil, nil)
  ns.Tidy()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
  if ForeverTraceDB and handlers[event] then
    ns.Safely(handlers[event], ...)
  end
end)
for event in pairs(handlers) do
  pcall(events.RegisterEvent, events, event)
end

ns.OnLogin(startSession)

---------------------------------------------------------------------------------------------------
-- For the other addons. Each call is safe at any time, also in a fight, and never raises an error.
--
--   if ForeverTrace then ForeverTrace.Log("ForeverBags", "the bank opened") end
--   if ForeverTrace then ForeverTrace.Error("ForeverBags", err) end   -- an error that a pcall caught

ForeverTrace = {}

-- A line for the ring of events.
function ForeverTrace.Log(addon, text)
  ns.Safely(ns.Push, "log", addon, text)
end

-- An error that the addon caught itself and did not hand to the game's error handler. (An error
-- that goes to geterrorhandler() is recorded already.)
local function report(addon, text)
  recorded(ns.Record("reported", text, ns.CallerStack(2), nil, addon or "?"))
end

function ForeverTrace.Error(addon, text)
  ns.Safely(report, addon, text)
end

-- A marker of the player or of an addon, with a screenshot if screenshots are on.
function ForeverTrace.Mark(text)
  ns.Safely(ns.Mark, text)
end

function ns.Mark(text)
  text = ns.Plain(text, 300)
  if not text or text == "" then
    text = "marker"
  end
  local mark = ns.AddMark(text)
  if mark and ns.GetOption("screenshots") then
    shoot(mark, false)
  end
  return mark
end
