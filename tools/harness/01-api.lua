-- A stand-in for the game client, for `cargo dev test`. Part 1: the documented API.
--
-- The four files 01 to 04 of this folder are one Lua chunk (the Rust host joins them). It
-- gets the API snapshot (tools/api/forever-api.json) and returns the table H, which the driver
-- uses. The stand-in has two sources:
--   1. The snapshot, from Blizzard's API documentation. Each documented function exists, checks
--      its arguments against the documentation, and returns a value of its documented kind
--      (0, "", false, a table with the documented fields). A name that the snapshot does not
--      have is nil, so a call to it fails, the same as in the game.
--   2. Hand-written code for what the documentation lacks (frames, menus, the settings window)
--      and a small world with a character, items, quests and a fight (files 03 and 04).
--
-- Rules that make an error show:
--   - A widget has the documented methods of its own kind only.
--   - An unknown event, frame type, template or script name fails, the same as in the game.
--   - A wrong kind of argument for a documented function fails.
--   - A secret value fails on arithmetic and on comparison of order, and as an argument of a
--     function that the documentation does not open to addon code.

local snapshot = ...

local H = {
  frames = {}, -- every frame made with CreateFrame, in order
  timers = {},
  now = 100000, -- GetTime
  clock = 1794735005, -- time()
  printed = {},
  postCalls = {}, -- tooltip functions
  settingsPanels = {},
  menus = {}, -- context menus that were opened and not yet run
  world = { secret = false },
  snapshot = snapshot,
}

-- Names that an addon in the game does not have. The debug library is for the coverage count.
H.debug = debug
debug = nil
local newproxy = newproxy
local rawLoadstring = loadstring
dofile, loadfile, load, collectgarbage, module, require, package = nil, nil, nil, nil, nil, nil, nil
_G.newproxy = nil
string.dump = nil
-- Text only: compiled code can break the interpreter.
function loadstring(text, name)
  if type(text) ~= "string" or text:sub(1, 1) == "\27" then
    return nil, "loadstring: text is needed"
  end
  return rawLoadstring(text, name)
end

local unpack = unpack
local realType = type
local realTostring = tostring
local pcall = pcall -- the driver gives the addon a pcall that takes notes; these files use the plain one
local plainFormat = string.format
H.realType, H.realTostring = realType, realTostring

-- Raises an error at the line of the addon that called into the stand-in: the nearest place on
-- the stack that is not a file of this folder.
local function fail(message)
  local getinfo = H.debug.getinfo
  local level = 2
  while true do
    local info = getinfo(level, "Sl")
    if not info then
      break
    end
    if info.what ~= "C" and info.currentline > 0 and not info.source:find("^=harness/") then
      error(info.short_src .. ":" .. info.currentline .. ": " .. message, 0)
    end
    level = level + 1
  end
  error(message, 0)
end
H.fail = fail

---------------------------------------------------------------------------------------------------
-- Secret values
--
-- In some situations (a fight, an instance) the game gives values as secret values: an addon
-- can show them, but not calculate with them or compare them. Here a secret value is a userdata.
-- Arithmetic, comparison of order, indexing and a call fail; joining with a text gives a secret
-- text; `type` gives the type of the hidden value, as in the game.
--
-- What Lua 5.1 cannot catch: `==` and `~=` with a secret value, a secret value as a table key,
-- and a test of a secret boolean. The driver looks for secret table keys after each phase.

local secrets = setmetatable({}, { __mode = "k" })
H.secrets = secrets

local secretMeta
local function refuse()
  fail("attempt to calculate with or compare a secret value")
end

function H.secret(value)
  if secrets[value] ~= nil then
    return value
  end
  local proxy = newproxy(true)
  local meta = getmetatable(proxy)
  for key, handler in pairs(secretMeta) do
    meta[key] = handler
  end
  secrets[proxy] = value
  return proxy
end

secretMeta = {
  __add = refuse, __sub = refuse, __mul = refuse, __div = refuse, __mod = refuse, __pow = refuse, __unm = refuse,
  __lt = refuse, __le = refuse, __len = refuse, __index = refuse, __newindex = refuse, __call = refuse,
  __concat = function(a, b)
    if a == nil or b == nil then
      fail("attempt to concatenate a nil value")
    end
    local left, right = a, b
    if secrets[a] ~= nil then
      left = secrets[a]
    end
    if secrets[b] ~= nil then
      right = secrets[b]
    end
    return H.secret(realTostring(left) .. realTostring(right))
  end,
  __tostring = function()
    return "<secret>"
  end,
}

-- The plain value of a value that can be secret.
local function plain(value)
  local hidden = secrets[value]
  if hidden ~= nil then
    return hidden
  end
  return value
end
H.plain = plain

function type(value)
  return realType(plain(value))
end
function tostring(value)
  if secrets[value] ~= nil then
    return H.secret(realTostring(secrets[value]))
  end
  return realTostring(value)
end

-- The functions of the game about secret values (FrameScriptDocumentation.lua).
function issecretvalue(value)
  return secrets[value] ~= nil
end
function hasanysecretvalues(...)
  for i = 1, select("#", ...) do
    if secrets[(select(i, ...))] ~= nil then
      return true
    end
  end
  return false
end
function canaccessvalue(value)
  return secrets[value] == nil
end
function canaccessallvalues(...)
  return not hasanysecretvalues(...)
end
function canaccesssecrets()
  return false
end
function issecrettable(value)
  if realType(value) ~= "table" then
    return false
  end
  for key, entry in pairs(value) do
    if secrets[key] ~= nil or secrets[entry] ~= nil then
      return true
    end
  end
  return false
end
function canaccesstable(value)
  return not issecrettable(value)
end
function scrubsecretvalues(...)
  local out, n = { ... }, select("#", ...)
  for i = 1, n do
    if secrets[out[i]] ~= nil then
      out[i] = nil
    end
  end
  return unpack(out, 1, n)
end
function secretwrap(...)
  local out, n = { ... }, select("#", ...)
  for i = 1, n do
    out[i] = H.secret(out[i])
  end
  return unpack(out, 1, n)
end
function dropsecretaccess() end

-- Number formatting that takes a secret value (LocalizationDocumentation.lua: these three are
-- open to addon code).
function AbbreviateNumbers(value)
  if realType(plain(value)) ~= "number" then
    fail("AbbreviateNumbers: a number is needed, got " .. realType(plain(value)))
  end
  if secrets[value] ~= nil then
    return H.secret(realTostring(secrets[value]))
  end
  return realTostring(value)
end
AbbreviateLargeNumbers = AbbreviateNumbers
BreakUpLargeNumbers = AbbreviateNumbers

-- string.format takes a secret value and gives a secret text. This is not in Blizzard's
-- documentation: the game's own code does it (Blizzard_Dump/Dump.lua).
function string.format(pattern, ...)
  local args, n, secret = { ... }, select("#", ...), false
  for i = 1, n do
    if secrets[args[i]] ~= nil then
      args[i], secret = secrets[args[i]], true
    end
  end
  local ok, text = pcall(plainFormat, pattern, unpack(args, 1, n))
  if not ok then
    -- The error belongs to the line that called string.format.
    fail((realTostring(text):gsub("'plainFormat'", "'format'"):gsub("^.-:%d+: ", "")))
  end
  return secret and H.secret(text) or text
end
format = string.format

---------------------------------------------------------------------------------------------------
-- Functions from the snapshot

-- "t{Name}?" -> "t", "Name", "?"
local function parseCodes(text)
  local list = {}
  local position = 1
  while position <= #text do
    local kind = text:sub(position, position)
    position = position + 1
    local entry = { kind = kind }
    if text:sub(position, position) == "{" then
      local finish = text:find("}", position, true)
      entry.structure = text:sub(position + 1, finish - 1)
      position = finish + 1
    end
    local mark = text:sub(position, position)
    if mark == "?" or mark == "*" then
      entry.optional = mark == "?"
      entry.list = mark == "*"
      position = position + 1
    end
    list[#list + 1] = entry
  end
  return list
end

local parsed = {}
local function parseSpec(spec)
  local known = parsed[spec]
  if not known then
    local returns, arguments, flags = spec:match("^(.-)|(.-)|(.-)$")
    known = { returns = parseCodes(returns), arguments = parseCodes(arguments), flags = flags }
    known.secretArguments = flags:match("[TUN]")
    known.secretInCombat = flags:find("C", 1, true) ~= nil
    known.secretAlways = flags:find("S", 1, true) ~= nil
    parsed[spec] = known
  end
  return known
end
H.parseSpec = parseSpec
H.parseCodes = parseCodes

-- A value of a documented kind. A structure gets its fields that cannot be nil.
local function defaultOf(entry, depth)
  if entry.optional or entry.list then
    return nil
  end
  local kind = entry.kind
  if kind == "n" then
    return 0
  elseif kind == "s" then
    return ""
  elseif kind == "b" then
    return false
  elseif kind == "f" then
    return function() end
  elseif kind == "t" or kind == "o" then
    local value = {}
    local fields = entry.structure and snapshot.structures[entry.structure]
    if fields and depth < 3 then
      for name, code in pairs(fields) do
        value[name] = defaultOf(parseCodes(code)[1], depth + 1)
      end
    end
    return value
  end
  return nil
end
H.defaultOf = defaultOf

local KIND_NAME = { n = "number", s = "string", t = "table", f = "function" }

-- Checks the arguments of a call against the documentation. `strict`: a missing argument that the documentation requires is
-- an error (for functions; widget methods have forms with fewer arguments that the
-- documentation does not list).
local function checkArguments(name, spec, strict, ...)
  local arguments = spec.arguments
  local given = select("#", ...)
  for index, expected in ipairs(arguments) do
    local value
    if index <= given then
      value = select(index, ...)
    end
    if secrets[value] ~= nil then
      if spec.secretArguments ~= "T" then
        fail(name .. ": a secret value is not allowed as argument " .. index .. " for addon code")
      end
      value = secrets[value]
    end
    if value == nil then
      if strict and not expected.optional and not expected.list then
        fail("bad argument #" .. index .. " to '" .. name .. "' (the documentation requires a value, got nil)")
      end
    else
      local kind, actual = expected.kind, realType(value)
      local fits = true
      if kind == "n" then
        fits = actual == "number" or (actual == "string" and tonumber(value) ~= nil)
      elseif kind == "s" then
        fits = actual == "string" or actual == "number"
      elseif kind == "t" then
        fits = actual == "table"
      elseif kind == "f" then
        fits = actual == "function"
      end
      if not fits then
        fail("bad argument #" .. index .. " to '" .. name .. "' (" .. KIND_NAME[kind] .. " expected, got " .. actual .. ")")
      end
    end
    if expected.list then
      break
    end
  end
end
H.checkArguments = checkArguments

-- The results of a stand-in: defaults of the documented kinds, secret where the documentation
-- says so.
local function results(spec)
  local out, n = {}, 0
  local secret = spec.secretAlways or (spec.secretInCombat and H.world.secret)
  for _, entry in ipairs(spec.returns) do
    if entry.list then
      break
    end
    n = n + 1
    local value = defaultOf(entry, 0)
    if secret and value ~= nil and realType(value) ~= "table" and realType(value) ~= "function" then
      value = H.secret(value)
    end
    out[n] = value
  end
  return out, n
end

local function stub(name, specText, strict)
  local spec = parseSpec(specText)
  return function(...)
    checkArguments(name, spec, strict, ...)
    local out, n = results(spec)
    return unpack(out, 1, n)
  end
end
H.stub = stub

-- The same for a method of a widget: the first argument is the widget itself.
function H.methodStub(name, specText)
  local spec = parseSpec(specText)
  return function(_, ...)
    checkArguments(name, spec, false, ...)
    local out, n = results(spec)
    return unpack(out, 1, n)
  end
end

-- A hand-written function in the place of a documented one: it keeps the argument check.
function H.documented(name, specText, strict, fn)
  local spec = parseSpec(specText)
  return function(...)
    checkArguments(name, spec, strict, ...)
    return fn(...)
  end
end

for name, spec in pairs(snapshot.globals) do
  if _G[name] == nil then
    _G[name] = stub(name, spec, true)
  end
end
for namespace, functions in pairs(snapshot.namespaces) do
  -- The documentation also lists what the game adds to the Lua libraries (table, string, math):
  -- those tables stay, and get the functions that they lack.
  local space = realType(_G[namespace]) == "table" and _G[namespace] or {}
  for name, spec in pairs(functions) do
    if space[name] == nil then
      space[name] = stub(namespace .. "." .. name, spec, true)
    end
  end
  _G[namespace] = space
end

Enum = {}
for name, fields in pairs(snapshot.enums) do
  Enum[name] = fields
end
for name, meta in pairs(snapshot.enumMeta) do
  Enum[name .. "Meta"] = { NumValues = meta[1], MinValue = meta[2], MaxValue = meta[3] }
end
Constants = snapshot.constants

H.knownEvents = snapshot.events

-- Puts a hand-written function in the place of a documented one, with the documented argument
-- check. Fails if the snapshot does not have the name: the world must not invent an API.
function H.set(namespace, name, fn)
  local spec = snapshot.namespaces[namespace] and snapshot.namespaces[namespace][name]
  if not spec then
    error("the stand-in sets " .. namespace .. "." .. name .. ", which the API snapshot does not have")
  end
  _G[namespace][name] = H.documented(namespace .. "." .. name, spec, true, fn)
end

-- The same for a global function. `where`: for a function that is not in the documentation,
-- the file of the game's own UI code that has it.
function H.setGlobal(name, fn, where)
  local spec = snapshot.globals[name]
  if spec then
    if where then
      error("the stand-in calls " .. name .. " undocumented, and the API snapshot has it")
    end
    _G[name] = H.documented(name, spec, true, fn)
  elseif where then
    _G[name] = fn
  else
    error("the stand-in sets " .. name .. ", which the API snapshot does not have")
  end
end

---------------------------------------------------------------------------------------------------
-- Lua library names of the game
--
-- These are C functions or Lua code of the game's shared UI code. The file with the game's
-- definition or use is beside each one that the documentation does not have.

-- Each character of the separator ends a piece; with `pieces`, the last piece is the rest.
function strsplit(separator, text, pieces)
  local class = "[" .. separator:gsub("[%^%]%-%%]", "%%%0") .. "]"
  local out, from = {}, 1
  while not pieces or #out < pieces - 1 do
    local at = text:find(class, from)
    if not at then
      break
    end
    out[#out + 1] = text:sub(from, at - 1)
    from = at + 1
  end
  out[#out + 1] = text:sub(from)
  return unpack(out)
end
function strjoin(separator, ...)
  local parts, n, secret = { ... }, select("#", ...), false
  for i = 1, n do
    if secrets[parts[i]] ~= nil then
      parts[i], secret = realTostring(secrets[parts[i]]), true
    end
  end
  local text = table.concat(parts, separator, 1, n)
  return secret and H.secret(text) or text
end
function strtrim(text, chars)
  local class = chars and ("[" .. chars:gsub("[%^%]%-%%]", "%%%0") .. "]") or "%s"
  return (text:gsub("^" .. class .. "+", ""):gsub(class .. "+$", ""))
end
string.split, string.join, string.trim = strsplit, strjoin, strtrim
strfind, strlower, strupper, strsub, strlen, strmatch, strrep, strbyte, strchar, gsub, gmatch =
  string.find, string.lower, string.upper, string.sub, string.len, string.match, string.rep, string.byte,
  string.char, string.gsub, string.gmatch
tinsert, tremove, sort, tconcat = table.insert, table.remove, table.sort, table.concat
floor, ceil, abs, max, min, sqrt, sin, cos, random, mod = math.floor, math.ceil, math.abs, math.max, math.min,
  math.sqrt, math.sin, math.cos, math.random, math.fmod

function wipe(t)
  for key in pairs(t) do
    t[key] = nil
  end
  return t
end
table.wipe = wipe
-- Blizzard_SharedXMLBase/TableUtil.lua: tContains = table.contains
function table.contains(t, value)
  for _, entry in pairs(t) do
    if entry == value then
      return true
    end
  end
  return false
end
tContains = table.contains
function CopyTable(t, shallow)
  local copy = {}
  for key, value in pairs(t) do
    copy[key] = (realType(value) == "table" and not shallow) and CopyTable(value) or value
  end
  return copy
end
function Mixin(object, ...)
  for i = 1, select("#", ...) do
    for key, value in pairs((select(i, ...))) do
      object[key] = value
    end
  end
  return object
end
function CreateFromMixins(...)
  return Mixin({}, ...)
end
-- Blizzard_SharedXMLBase/MathUtil.lua: Round = math.round, Clamp = math.clamp
function math.round(value)
  if value < 0 then
    return math.ceil(value - 0.5)
  end
  return math.floor(value + 0.5)
end
Round = math.round
function math.clamp(value, low, high)
  return math.max(low, math.min(high, value))
end
Clamp = math.clamp

-- Bit operations: the game has the `bit` library (Blizzard_SharedXMLBase/Flags.lua uses it).
bit = {}
local function bitwise(a, b, rule)
  local result, place = 0, 1
  a, b = math.floor(a) % 4294967296, math.floor(b) % 4294967296
  while a > 0 or b > 0 do
    local x, y = a % 2, b % 2
    if rule(x, y) then
      result = result + place
    end
    a, b, place = (a - x) / 2, (b - y) / 2, place * 2
  end
  return result
end
function bit.band(a, b)
  return bitwise(a, b, function(x, y) return x == 1 and y == 1 end)
end
function bit.bor(a, b)
  return bitwise(a, b, function(x, y) return x == 1 or y == 1 end)
end
function bit.bxor(a, b)
  return bitwise(a, b, function(x, y) return x ~= y end)
end
function bit.bnot(a)
  return 4294967295 - math.floor(a) % 4294967296
end
function bit.lshift(a, n)
  return (math.floor(a) * 2 ^ n) % 4294967296
end
function bit.rshift(a, n)
  return math.floor(math.floor(a) % 4294967296 / 2 ^ n)
end

function time(t)
  if realType(t) == "table" then
    -- Days from the civil date, then seconds: enough for a test.
    local year, month = t.year, t.month
    if month <= 2 then
      year, month = year - 1, month + 12
    end
    local days = 365 * year + math.floor(year / 4) - math.floor(year / 100) + math.floor(year / 400)
      + math.floor((153 * (month - 3) + 2) / 5) + t.day - 719469
    return days * 86400 + (t.hour or 12) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
  end
  return H.clock
end
-- A date text from the clock, in UTC, without the OS library.
function date(pattern, at)
  at = at or H.clock
  local days = math.floor(at / 86400)
  local seconds = at % 86400
  local z = days + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local day = doy - math.floor((153 * mp + 2) / 5) + 1
  local month = mp < 10 and mp + 3 or mp - 9
  local year = yoe + era * 400 + (month <= 2 and 1 or 0)
  local fields = {
    Y = plainFormat("%04d", year), m = plainFormat("%02d", month), d = plainFormat("%02d", day),
    H = plainFormat("%02d", math.floor(seconds / 3600)), M = plainFormat("%02d", math.floor(seconds / 60) % 60),
    S = plainFormat("%02d", seconds % 60),
  }
  if pattern == "*t" then
    return { year = year, month = month, day = day, hour = math.floor(seconds / 3600), min = math.floor(seconds / 60) % 60, sec = seconds % 60 }
  end
  return ((pattern or "%Y-%m-%d %H:%M:%S"):gsub("%%(%a)", function(letter)
    return fields[letter] or ""
  end))
end
function GetTime()
  return H.now
end
function GetServerTime()
  return H.clock
end
function debugprofilestop()
  return H.now * 1000
end

function print(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = realTostring(plain((select(i, ...))))
  end
  H.printed[#H.printed + 1] = table.concat(parts, " ")
end

-- The error handler of the game shows the error. The driver sets H.onError to record it.
function geterrorhandler()
  return function(err)
    if H.onError then
      H.onError("error handler", err)
    end
  end
end
function seterrorhandler() end

-- Keeps every result of a call, also a nil in the middle or at the end.
local function pack(...)
  return select("#", ...), { ... }
end
H.pack = pack

function hooksecurefunc(a, b, c)
  local target, name, hook = _G, a, b
  if realType(a) == "table" then
    target, name, hook = a, b, c
  end
  local original = target[name]
  if realType(original) ~= "function" or realType(hook) ~= "function" then
    fail("hooksecurefunc(): " .. realTostring(name) .. " is not a function")
  end
  target[name] = function(...)
    local n, out = pack(original(...))
    hook(...)
    return unpack(out, 1, n)
  end
end
function securecallfunction(fn, ...)
  return fn(...)
end
