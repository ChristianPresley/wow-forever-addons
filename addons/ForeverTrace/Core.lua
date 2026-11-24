local ADDON, ns = ...

-- A record on disk of what went wrong and what happened while you played, for a developer to
-- read after /reload. The game writes ForeverTraceDB to
-- WTF/Account/<account>/SavedVariables/ForeverTrace.lua on /reload and on logout only.
--
-- Saved data, in ForeverTraceDB (for all characters):
--   version  = 1
--   options  = { enabled, announce, screenshots, shotGap, ring, errors }
--   session  = the number of this session; each login and each /reload starts a new one
--   sessions = the last sessions, the oldest first:
--     { session, t, at, how = "login"|"reload", build, character, versions = { ForeverBags = "0.3.1" },
--       others = { "Questie", ... }, hook = true if the Lua errors of this session were seen }
--   errors   = one entry for each different error, the oldest first:
--     { id, kind = "error"|"warning"|"taint"|"blocked"|"forbidden"|"reported",
--       message, stack, locals, addon = the addon of the first file in the message or the stack,
--       forever = the first Forever addon in them, ours = true if there is one,
--       count, first = stamp, last = stamp, versions, early = true if it happened before this
--       addon loaded, shot = the time in the name of the screenshot }
--   events   = the last events, the oldest first:
--     stamp + { kind = "login"|"reload"|"world"|"zone"|"fight"|"log"|"mark"|"error"|..., addon, text,
--       n = how many times in a row }
--   internal = { count, last }: errors of Forever Trace itself, which it caught
-- A stamp is { t = time(), at = "2026-11-23 14:02:11", session, map, zone, fight }.
-- A value that the game hides is stored as the text "secret".

local DATA_VERSION = 1
local SESSIONS_KEPT = 20
local SLACK = 50 -- a list is cut when it is this much over its limit, not at each entry
local MESSAGE_LIMIT, STACK_LIMIT, LOCALS_LIMIT, TEXT_LIMIT = 1000, 4000, 2000, 300
local RING_AGAIN_SECONDS = 30 -- a repeat of an error is an event again after this long
local ANNOUNCE_SECONDS = 2

function ns.Print(msg)
  print("|cffc9a227Forever Trace|r: " .. tostring(msg))
end

-- A text that can be stored: "secret" for a value that the game hides, nil for nil.
function ns.Plain(value, limit)
  if issecretvalue(value) then
    return "secret"
  end
  if value == nil then
    return nil
  end
  local kind = type(value)
  if kind == "number" or kind == "boolean" then
    value = tostring(value)
  elseif kind ~= "string" then
    return "(" .. kind .. ")"
  end
  if limit and #value > limit then
    value = value:sub(1, limit) .. "..."
  end
  return value
end

-- Runs fn and never raises an error: an error of this addon is counted, not shown.
function ns.Safely(fn, ...)
  local ok, a, b = pcall(fn, ...)
  if ok then
    return a, b
  end
  local db = ForeverTraceDB
  if type(db) == "table" and type(db.internal) == "table" then
    db.internal.count = (db.internal.count or 0) + 1
    db.internal.last = ns.Plain(a, MESSAGE_LIMIT)
  end
  return nil
end

---------------------------------------------------------------------------------------------------
-- Options

ns.OPTION_DEFAULTS = {
  enabled = true, -- record at all
  announce = true, -- a line in the chat for a new error
  screenshots = false, -- a screenshot for a new error: off until you have tried /ftrace shot
  shotGap = 30, -- seconds between two screenshots
  ring = 300, -- events kept
  errors = 100, -- different errors kept
}

ns.OPTION_LIMITS = {
  shotGap = { 5, 300 },
  ring = { 50, 1000 },
  errors = { 20, 300 },
}

local listeners = {}

-- fn runs after each change of an option or of the stored data.
function ns.OnChange(fn)
  listeners[#listeners + 1] = fn
end

function ns.Changed()
  for _, fn in ipairs(listeners) do
    ns.Safely(fn)
  end
end

function ns.GetOption(key)
  if not ForeverTraceDB then
    return ns.OPTION_DEFAULTS[key]
  end
  return ForeverTraceDB.options[key]
end

-- Returns false for a key that is not an option.
function ns.SetOption(key, value)
  local default = ns.OPTION_DEFAULTS[key]
  if default == nil or not ForeverTraceDB then
    return false
  end
  if type(default) == "number" then
    local limit = ns.OPTION_LIMITS[key]
    value = math.floor((tonumber(value) or default) + 0.5)
    value = math.max(limit[1], math.min(limit[2], value))
  else
    value = value and true or false
  end
  ForeverTraceDB.options[key] = value
  ns.Changed()
  return true
end

---------------------------------------------------------------------------------------------------
-- Where and when. The place is read when it changes, so that an error costs no call of the game.

ns.where = { map = nil, zone = nil }
ns.inFight = false
ns.versions = {} -- the loaded Forever addons: name -> version
ns.hooked = false -- true when the Lua errors of the game are seen (see Capture.lua)

function ns.ReadPlace()
  local map = C_Map.GetBestMapForUnit("player")
  if issecretvalue(map) then
    map = "secret"
  end
  ns.where.map = map
  ns.where.zone = ns.Plain(GetRealZoneText(), 80)
end

local function stamp(target)
  target.t = time()
  target.at = date("%Y-%m-%d %H:%M:%S")
  target.session = ForeverTraceDB.session
  target.map = ns.where.map
  target.zone = ns.where.zone
  target.fight = ns.inFight
  return target
end

-- Keeps the last `keep` entries of a list.
local function trim(list, keep)
  local count = #list
  local extra = count - keep
  if extra <= 0 then
    return
  end
  for index = 1, keep do
    list[index] = list[index + extra]
  end
  for index = keep + 1, count do
    list[index] = nil
  end
end

---------------------------------------------------------------------------------------------------
-- The ring of events

-- Adds an event. The same event again, directly after itself, raises its `n`.
function ns.Push(kind, addon, text)
  local db = ForeverTraceDB
  if not db or not db.options.enabled then
    return nil
  end
  addon = ns.Plain(addon, 60)
  text = ns.Plain(text, TEXT_LIMIT)
  local events = db.events
  local last = events[#events]
  if last and last.kind == kind and last.addon == addon and last.text == text and last.session == db.session then
    last.n = (last.n or 1) + 1
    return last
  end
  local entry = stamp({})
  entry.kind, entry.addon, entry.text = kind, addon, text
  events[#events + 1] = entry
  if #events > db.options.ring + SLACK then
    trim(events, db.options.ring)
  end
  return entry
end

---------------------------------------------------------------------------------------------------
-- Errors: one entry for each different one, with a count

local index = {} -- key -> entry
local seenNow = {} -- key -> the GetTime() of its last event in the ring, in this session
local busy = false
local lastAnnounce = nil

local function keyOf(entry)
  return entry.kind .. "\n" .. entry.message .. "\n" .. (entry.stack or "")
end

-- The addon of the first file in the texts, and the first Forever addon in them.
function ns.OwnerOf(message, stack)
  local text = message .. "\n" .. stack
  local addon = text:match("AddOns[/\\]([^/\\]+)[/\\]")
  local forever = text:match("AddOns[/\\](Forever[^/\\]*)[/\\]")
  return addon, forever
end

local function copy(source)
  local out = {}
  for key, value in pairs(source) do
    out[key] = value
  end
  return out
end

-- The entry that was seen last goes when the list is full.
local function makeRoom(db)
  local errors = db.errors
  while #errors >= db.options.errors do
    local oldest, at = 1, nil
    for position, entry in ipairs(errors) do
      local t = entry.last and entry.last.t or 0
      if at == nil or t < at then
        oldest, at = position, t
      end
    end
    local gone = table.remove(errors, oldest)
    index[keyOf(gone)] = nil
  end
end

local function announce(entry)
  if not ForeverTraceDB.options.announce then
    return
  end
  local now = GetTime()
  if lastAnnounce and now - lastAnnounce < ANNOUNCE_SECONDS then
    return
  end
  lastAnnounce = now
  local line = entry.message:gsub("\n.*", "")
  if #line > 140 then
    line = line:sub(1, 140) .. "..."
  end
  ns.Print(string.format("%s in %s: %s", entry.kind, entry.addon or "?", line))
end

local function record(db, kind, message, stack, locals, addon, early)
  message = ns.Plain(message, MESSAGE_LIMIT) or "?"
  stack = ns.Plain(stack, STACK_LIMIT) or ""
  local key = kind .. "\n" .. message .. "\n" .. stack
  local entry = index[key]
  if entry then
    entry.count = entry.count + 1
    stamp(entry.last)
  else
    makeRoom(db)
    local first, forever = ns.OwnerOf(message, stack)
    addon = ns.Plain(addon, 60)
    if addon then
      -- The caller named the owner: the files in the stack do not decide.
      forever = addon:find("^Forever") and addon or nil
    else
      addon = first
    end
    db.lastId = (db.lastId or 0) + 1
    entry = {
      id = db.lastId,
      kind = kind,
      message = message,
      stack = stack,
      locals = ns.Plain(locals, LOCALS_LIMIT),
      addon = addon or "?",
      forever = forever,
      ours = forever ~= nil,
      count = 1,
      first = stamp({}),
      last = stamp({}),
      early = early or nil,
    }
    db.errors[#db.errors + 1] = entry
    index[key] = entry
  end
  local now = GetTime()
  local isNew = seenNow[key] == nil
  if isNew then
    entry.versions = copy(ns.versions)
  end
  if isNew or now - seenNow[key] >= RING_AGAIN_SECONDS then
    seenNow[key] = now
    ns.Push(kind, entry.addon, "#" .. entry.id .. " " .. message:gsub("\n.*", ""))
  end
  if isNew and not early then
    announce(entry)
  end
  return entry, isNew
end

-- Records an error. `addon` names the owner when the caller knows it; `early` is for an error
-- that happened before this addon loaded. Returns the entry, and true if this session had not
-- seen it yet. An error in here is not recorded again: `busy` stops the circle.
function ns.Record(kind, message, stack, locals, addon, early)
  local db = ForeverTraceDB
  if busy or not db or not db.options.enabled then
    return nil, false
  end
  busy = true
  local entry, isNew = ns.Safely(record, db, kind, message, stack, locals, addon, early)
  busy = false
  ns.Changed()
  return entry, isNew or false
end

function ns.Clear()
  local db = ForeverTraceDB
  if not db then
    return
  end
  db.errors, db.events = {}, {}
  db.internal = { count = 0 }
  index, seenNow = {}, {}
  busy = false
  ns.Changed()
end

-- How many errors are stored, how many of them are of Forever addons, and the one seen last.
function ns.Counts()
  local db = ForeverTraceDB
  local total, ours, latest = 0, 0, nil
  for _, entry in ipairs(db and db.errors or {}) do
    total = total + 1
    if entry.ours then
      ours = ours + 1
    end
    if not latest or entry.last.t >= latest.last.t then
      latest = entry
    end
  end
  return total, ours, latest, db and #db.events or 0
end

---------------------------------------------------------------------------------------------------
-- Start

local logins = {}

function ns.OnLogin(fn)
  logins[#logins + 1] = fn
end

local function list(db, key)
  if type(db[key]) ~= "table" then
    db[key] = {}
  end
  return db[key]
end

local function load()
  if type(ForeverTraceDB) ~= "table" then
    ForeverTraceDB = {}
  end
  local db = ForeverTraceDB
  db.version = DATA_VERSION
  local options = list(db, "options")
  for key, default in pairs(ns.OPTION_DEFAULTS) do
    if type(options[key]) ~= type(default) then
      options[key] = default
    end
  end
  for key, limit in pairs(ns.OPTION_LIMITS) do
    options[key] = math.max(limit[1], math.min(limit[2], math.floor(options[key] + 0.5)))
  end
  db.session = (type(db.session) == "number" and db.session or 0) + 1
  list(db, "sessions")
  list(db, "events")
  if type(db.internal) ~= "table" then
    db.internal = { count = 0 }
  end
  -- Entries that an older version or a hand left in a wrong form go.
  local kept = {}
  for _, entry in ipairs(list(db, "errors")) do
    if type(entry) == "table" and type(entry.kind) == "string" and type(entry.message) == "string" and type(entry.count) == "number" and type(entry.first) == "table" and type(entry.last) == "table" and type(entry.last.t) == "number" then
      kept[#kept + 1] = entry
      index[keyOf(entry)] = entry
    end
  end
  db.errors = kept
end

-- Cuts the lists to their limits: at logout, just before the game writes the file.
function ns.Tidy()
  local db = ForeverTraceDB
  if not db then
    return
  end
  trim(db.events, db.options.ring)
  trim(db.sessions, SESSIONS_KEPT)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
  if event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    for _, fn in ipairs(logins) do
      ns.Safely(fn)
    end
    return
  end
  if name ~= ADDON then
    return
  end
  self:UnregisterEvent("ADDON_LOADED")
  ns.Safely(load)
end)
