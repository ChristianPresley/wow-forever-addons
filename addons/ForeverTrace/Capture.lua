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

---------------------------------------------------------------------------------------------------
-- Screenshots

local lastShot = nil -- GetTime() of the last one
local pending = nil -- { entry = the error it is for, test = true for /ftrace shot, name = ... }

-- The time in the file name of a screenshot: Screenshots/WoWScrnShot_MMDDYY_HHMMSS.jpg.
local function shotName()
  return date("%m%d") .. date("%Y"):sub(3) .. "_" .. date("%H%M%S")
end

local function shoot(entry, test)
  pending = { entry = entry, test = test }
  lastShot = GetTime()
  C_Timer.After(test and 0 or SHOT_DELAY, function()
    ns.Safely(Screenshot)
  end)
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

local function shotDone(ok)
  local shot = pending
  pending = nil
  if not shot then
    return -- a screenshot of the player
  end
  local name = ok and (shot.name or shotName()) or "failed"
  if shot.entry then
    shot.entry.shot = name
  end
  ns.Push("screenshot", nil, name)
  if shot.test then
    if ok then
      ns.Print("the screenshot worked: WoWScrnShot_" .. name .. ".jpg in the Screenshots folder. /ftrace screenshots turns them on for new errors.")
    else
      ns.Print("the game did not take the screenshot.")
    end
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

function handlers.PLAYER_ENTERING_WORLD(isLogin, isReload)
  ns.ReadPlace()
  local how = is(isLogin) and "login" or is(isReload) and "reload" or "world"
  if session and not session.how and how ~= "world" then
    session.how = how
  end
  ns.Push(how, nil, ns.where.zone)
end

function handlers.ZONE_CHANGED_NEW_AREA()
  ns.ReadPlace()
  ns.Push("zone", nil, ns.where.zone)
end

handlers.ZONE_CHANGED = ns.ReadPlace
handlers.ZONE_CHANGED_INDOORS = ns.ReadPlace

function handlers.PLAYER_REGEN_DISABLED()
  ns.inFight = true
  fightStart = GetTime()
  ns.Push("fight", nil, "start")
end

function handlers.PLAYER_REGEN_ENABLED()
  ns.inFight = false
  local seconds = fightStart and math.floor(GetTime() - fightStart + 0.5)
  fightStart = nil
  ns.Push("fight", nil, seconds and ("end after " .. seconds .. " s") or "end")
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

function handlers.SCREENSHOT_STARTED()
  if pending then
    pending.name = shotName()
  end
end

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
  local entry = ns.Push("mark", nil, text)
  if entry and ns.GetOption("screenshots") then
    shoot(nil, false)
  end
  return entry
end
