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

-- `uiFiles` has functions for the large parts of tools/api/forever-ui.json, which are read
-- when they are needed: uiFiles.template(name), uiFiles.mixin(name) and uiFiles.calls().
local snapshot, uiFiles = ...
uiFiles = uiFiles or {}

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
dofile, loadfile, load, module, require, package = nil, nil, nil, nil, nil, nil
-- The game has collectgarbage (Blizzard_FrameXMLBase/IconDataProvider.lua calls it). Here it
-- answers a memory count and does nothing else.
function collectgarbage(option)
  if option == nil or option == "collect" or option == "count" or option == "step" then
    return 0
  end
  error("bad argument #1 to 'collectgarbage' (invalid option '" .. realTostring(option) .. "')", 2)
end
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

-- Keeps every result of a call, also a nil in the middle or at the end.
local function pack(...)
  return select("#", ...), { ... }
end
H.pack = pack

---------------------------------------------------------------------------------------------------
-- Secret values
--
-- In some situations (a fight, an instance) the game gives values as secret values: an addon
-- can show them, but not calculate with them or compare them. Here a secret value is a userdata.
-- Arithmetic, comparison of order, indexing and a call fail; joining with a text gives a secret
-- text; `type` gives the type of the hidden value, as in the game.
--
-- What the game client does (tools/ingame-probe/answers.txt): `==` with a secret value, a
-- secret value as a table key and a test of a secret boolean (`if value then`) are errors;
-- `~= nil` gives a plain result without an error; `type` gives the type of the hidden value;
-- `tostring`, `string.format`, `..` and AbbreviateNumbers give a secret text.
--
-- What Lua 5.1 cannot catch, so that the stand-in lets it pass: `==` with a secret value, a
-- secret value as a table key, and a test of a secret boolean. The driver looks for secret
-- table keys in the tables of the addon after each phase.

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
-- AbbreviateNumbers(value, options) and AbbreviateLargeNumbers (LocalizationDocumentation.lua,
-- NumberAbbreviationBreakpoint in LocalizationSharedDocumentation.lua). The breakpoints go from
-- the largest to the smallest. The first one that the number reaches gives the text:
-- floor(number / significandDivisor) / fractionDivisor, then the abbreviation. So 1234 with
-- 100 and 10 is "1.2K". A number below every breakpoint stays as it is, with all its decimals:
-- the rules are what rounds, not the function.
local DEFAULT_BREAKPOINTS = {
  { breakpoint = 1e9, abbreviation = "B", significandDivisor = 1e8, fractionDivisor = 10 },
  { breakpoint = 1e6, abbreviation = "M", significandDivisor = 1e5, fractionDivisor = 10 },
  { breakpoint = 1e4, abbreviation = "K", significandDivisor = 1e3, fractionDivisor = 1 },
  { breakpoint = 1e3, abbreviation = "K", significandDivisor = 100, fractionDivisor = 10 },
}
local abbreviateConfigs = setmetatable({}, { __mode = "k" })
local function checkBreakpoints(list, where, always)
  if realType(list) ~= "table" then
    fail(where .. ": the breakpoints are not a table")
  end
  local last
  for index, entry in ipairs(list) do
    for _, field in ipairs({ "breakpoint", "significandDivisor", "fractionDivisor" }) do
      if realType(entry[field]) ~= "number" then
        fail(where .. ": breakpoint " .. index .. " has no number " .. field)
      end
    end
    if realType(entry.abbreviation) ~= "string" then
      fail(where .. ": breakpoint " .. index .. " has no text abbreviation")
    end
    if entry.significandDivisor <= 0 or entry.fractionDivisor <= 0 then
      fail(where .. ": breakpoint " .. index .. " has a divisor that is not above zero")
    end
    -- CreateAbbreviateConfig refuses a breakpoint of zero, with this text, and breakpointData
    -- of AbbreviateNumbers takes the same rules: 0.123456 is "0" and 345.678901 is "345" with
    -- them (the game client, tools/ingame-probe/answers.txt). H.world.strictAbbreviate is from
    -- before that answer: with it the stand-in is a client that refuses them for breakpointData
    -- too. The game client is not such a client.
    local positive = entry.breakpoint > 0 and entry.breakpoint < math.huge
    if always and not positive then
      fail(where .. "(): Invalid Breakpoint - must be greater than zero and finite")
    end
    if H.world and H.world.strictAbbreviate and entry.breakpoint <= 0 then
      fail(where .. ": breakpoint " .. index .. " is not above zero (InvalidBreakpoint)")
    end
    if last and entry.breakpoint >= last then
      fail(where .. ": the breakpoints are not in order from the largest to the smallest")
    end
    last = entry.breakpoint
  end
  return list
end
function CreateAbbreviateConfig(breakpoints)
  local config = {}
  abbreviateConfigs[config] = checkBreakpoints(breakpoints, "CreateAbbreviateConfig", true)
  return config
end
function AbbreviateNumbers(value, options)
  local number = plain(value)
  if realType(number) ~= "number" then
    fail("AbbreviateNumbers: a number is needed, got " .. realType(number))
  end
  local breakpoints = DEFAULT_BREAKPOINTS
  if options ~= nil then
    if realType(options) ~= "table" then
      fail("AbbreviateNumbers: the options are not a table")
    end
    if options.config ~= nil then
      breakpoints = abbreviateConfigs[options.config] or fail("AbbreviateNumbers: the config is not from CreateAbbreviateConfig")
    elseif options.breakpointData ~= nil then
      breakpoints = checkBreakpoints(options.breakpointData, "AbbreviateNumbers")
    end
  end
  local text = realTostring(number)
  -- A number below every breakpoint stays as it is: without rules 0.123456 is "0.123456" and
  -- 345.678901 is "345.678901" (the game client, tools/ingame-probe/answers.txt).
  -- H.world.abbreviateWhole is from before that answer: with it the stand-in is a client that
  -- gives a whole number there. The game client is not such a client.
  if H.world and H.world.abbreviateWhole then
    text = realTostring(math.floor(number))
  end
  for _, entry in ipairs(breakpoints) do
    if math.abs(number) >= entry.breakpoint then
      local shown = math.floor(number / entry.significandDivisor) / entry.fractionDivisor
      text = realTostring(shown) .. entry.abbreviation
      break
    end
  end
  if secrets[value] ~= nil then
    return H.secret(text)
  end
  return text
end
AbbreviateLargeNumbers = AbbreviateNumbers
-- BreakUpLargeNumbers puts separators in a number and does not shorten it.
function BreakUpLargeNumbers(value)
  local number = plain(value)
  if realType(number) ~= "number" then
    fail("BreakUpLargeNumbers: a number is needed, got " .. realType(number))
  end
  local text = realTostring(number)
  return secrets[value] ~= nil and H.secret(text) or text
end

-- string.format takes a secret value and gives a secret text. This is not in Blizzard's
-- documentation: the game's own damage meter does it with the amounts and the names of a fight,
-- which are secret then (Blizzard_DamageMeter/DamageMeterEntry.lua, the lines with :format(
-- and string.format).
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

---------------------------------------------------------------------------------------------------
-- When a result is secret
--
-- The documentation marks each function and event whose values can be secret, and names the
-- restriction (snapshot.secretWhen, snapshot.eventSecretWhen). The text of each restriction is
-- in Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua, and is quoted here.
-- The world of the stand-in has one restricted state: the fight (H.world.secret), which is the
-- game's "combat addon restriction". It has no encounter, no keystone dungeon, no PvP match and
-- no restricted map.
--
-- The rule for a hand-written function is the same as for one from the snapshot: the result is
-- made secret here, after the function ran, so the world cannot forget it.
--
-- What no source says: whether a value that is secret in a fight for a unit is secret for that
-- unit out of a fight too. The texts about units name the unit and not the state. The stand-in
-- takes the narrow reading, a fight and the unit, so that everything secret here is secret in
-- the game under either reading, but where the game client answered. tools/ingame-probe asked
-- it (the cases "secret, out of a fight:" and "secret, in a fight:" of answers.txt, a fight
-- with an NPC outside an instance). Its answers:
--   - UnitHealth and UnitInRange are secret at all times, also out of a fight.
--   - UnitHealthMax is secret at all times for a unit that is not the player's, also for a
--     target that is not there, and plain for the player in a fight.
--   - UnitPower of the player is secret at all times.
--   - UnitArmor and GetCritChance are secret in a fight and plain out of it.
--   - UnitThreatSituation of the player is plain in a fight.
--   - The start and the duration of a cooldown are secret in a fight and plain out of it.
--   - The name, the GUID and the class of the NPC that the player fights are plain. Here they
--     stay secret in a fight: the world has no instance and no encounter, where the game hides
--     them, so the fight stands for those too. The stand-in is the stricter one in this.

local function inFight()
  return H.world.secret == true
end
-- The unit of a call: its first argument, if that is a text.
local function unitOf(...)
  local unit = plain((...))
  return realType(unit) == "string" and unit:lower() or ""
end
-- A unit that a player controls: the player's own, and the members of the group. In the world
-- of the stand-in every other unit is an NPC. A compound token ("party1target") is not one:
-- "results are secret if any unit in the chain fails this".
local function ofPlayers(unit)
  return unit == "player" or unit == "pet" or unit == "vehicle" or unit:find("^party%d+$") ~= nil or unit:find("^raid%d+$") ~= nil
    or unit:find("^partypet%d+$") ~= nil or unit:find("^raidpet%d+$") ~= nil
end
local function fightOnly()
  return inFight()
end
local function never()
  return false
end
local function fightAndNotOfPlayers(...)
  return inFight() and not ofPlayers(unitOf(...))
end
local function notOfPlayers(...)
  return not ofPlayers(unitOf(...))
end
local function always()
  return true
end

local RULES = {
  -- "produce secret values when combat, encounter, challenge mode, or PvP match addon
  -- restrictions are in effect". A spell can be flagged as never secret, and no source lists
  -- those spells: here none is.
  SecretWhenUnitAuraRestricted = fightOnly,
  SecretWhenAurasRestricted = fightOnly,
  SecretWhenCooldownsRestricted = fightOnly,
  SecretWhenTotemSlotSecret = fightOnly,
  -- "when the unit isn't player-controlled or in the party/raid".
  SecretWhenUnitIdentityRestricted = fightAndNotOfPlayers,
  -- "under regular unit identity secrecy rules, except in PvP when the queried unit is a player".
  SecretWhenUnitNameIdentityRestricted = fightAndNotOfPlayers,
  -- "when the unit isn't player-controlled". The game client: at all times, also out of a
  -- fight and for a target that is not there.
  SecretWhenUnitHealthMaxRestricted = notOfPlayers,
  -- The same text. The game client was not asked about it: the narrow reading.
  SecretWhenUnitPowerMaxRestricted = fightAndNotOfPlayers,
  -- "for power types not explicitly flagged as being never secret": no source lists those
  -- power types. The game client: UnitPower('player') is secret in a fight and out of it.
  SecretWhenUnitPowerRestricted = always,
  -- "when access to unit stats would generally produce secret values". The game client:
  -- UnitArmor and GetCritChance are secret in a fight and plain out of it.
  SecretWhenUnitStatsRestricted = fightOnly,
  -- "generally not secret" for some pairs of units, with no rule for the others. The game
  -- client: plain in a fight for the player, alone and with its target.
  SecretWhenUnitThreatStateRestricted = never,
  -- "based on aura secrecy, except for unit tokens under the player's direct control".
  SecretWhenUnitPossessionRestricted = function(...)
    local unit = unitOf(...)
    return inFight() and not (unit == "player" or unit == "pet" or unit == "vehicle")
  end,
  -- "if the unit being queried for cast information is not the player or their pet".
  SecretWhenUnitSpellCastRestricted = function(...)
    local unit = unitOf(...)
    return inFight() and not (unit == "player" or unit == "pet")
  end,
  -- "always produce secret values, unless the active player is an active spectator or
  -- commentator of a PvP match".
  SecretWhenLossOfControlRestricted = function() return true end,
  SecretWhenLossOfControlInfoRestricted = function() return true end,
  -- "when encounter, challenge mode, or PvP match addon restrictions are in effect, and when the
  -- player is on a communication-restricted map such as a dungeon or raid": none of these is in
  -- the world of the stand-in.
  SecretInChatMessagingLockdown = never,
  -- "when PvP match addon restrictions are in effect".
  SecretInActivePvPMatch = never,
  -- "This restriction only applies when the player is on an addon-restricted map."
  SecretWhenUnitComparisonRestricted = never,
  -- A table with a secret key: the driver fails an addon that makes one, so there is none.
  SecretWhenLuaTableHasSecretKeys = never,
}
-- Restrictions without a rule: the result stays plain, also in a fight. Each one has the reason.
-- An addon that calculates with such a value passes here and can fail in the game.
local UNKNOWN = {
  SecretWhenUnitThreatValuesRestricted = "The text is \"generally not secret\" for some pairs of units: it gives no rule for the others.",
  SecretWhenEncounterEvent = "SecretPredicatesDocumentation.lua has no text for it, and the world has no encounter.",
  SecretWhenAnchoringSecret = "A property of a region that was anchored with a secret value: the stand-in does not follow where a value of a region came from.",
  SecretWhenCurveSecret = "A property of a curve object that was made with secret values: the stand-in does not follow it.",
  SecretWhenNumericFormatterSecret = "A property of a formatter object that was made with secret values: the stand-in does not follow it.",
}
H.secretRules, H.secretUnknown = RULES, UNKNOWN

-- True if the documentation makes the results of this call secret now. `key` is the name of
-- the function in the snapshot ("UnitName", "C_Spell.GetSpellName"). The flags without a named
-- restriction: C is SecretWhenInCombat ("when combat addon restrictions are in effect"); S is
-- SecretReturns, for which the documentation names no condition. C_Secrets.HasSecretRestrictions
-- calls every such mark "potentially returning secrets", so S is secret in the fight, which is
-- sure, and plain out of it, which no source settles. The game client answered for two such
-- functions, and both are secret out of a fight too: SECRET_AT_ALL_TIMES has them. The others
-- with S were not asked.
local SECRET_AT_ALL_TIMES = { UnitHealth = true, UnitInRange = true }
local function secretNow(names, spec, ...)
  if spec and (spec.secretAlways or spec.secretInCombat) and inFight() then
    return true
  end
  if names then
    for name in names:gmatch("[^,]+") do
      local rule = RULES[name]
      if rule and rule(...) then
        return true
      end
    end
  end
  return false
end

-- True if a table of this structure has, at any depth, a field that is secret at all times
-- (SecretValue in the documentation, "S" in snapshot.secretFields).
local alwaysSecretInside = {}
local function hasAlwaysSecret(structure, depth)
  if not structure or depth > 4 then
    return false
  end
  local known = alwaysSecretInside[structure]
  if known ~= nil then
    return known
  end
  alwaysSecretInside[structure] = false
  local found = false
  for _, mark in pairs(snapshot.secretFields[structure] or {}) do
    if mark == "S" then
      found = true
    end
  end
  for field, code in pairs(snapshot.structures[structure] or {}) do
    if not found then
      found = hasAlwaysSecret(parseCodes(code)[1].structure, depth + 1) or hasAlwaysSecret(snapshot.innerTypes[structure .. "." .. field], depth + 1)
    end
  end
  alwaysSecretInside[structure] = found
  return found
end

-- A copy of a table with its values made secret. `structure` is the documented structure of
-- the table, `entries` the structure of each entry of a list. With `all`, every value is secret
-- but the fields marked NeverSecret; without it, only the fields marked SecretValue. A table
-- with a metatable (a vector, a colour) is an object of the game and stays as it is.
local function concealTable(value, structure, entries, all, depth)
  if getmetatable(value) ~= nil or depth > 6 then
    return value
  end
  local marks = structure and snapshot.secretFields[structure] or {}
  local fields = structure and snapshot.structures[structure] or {}
  local copy = {}
  for key, entry in pairs(value) do
    local kind = realType(entry)
    local named = realType(key) == "string"
    local mark = named and marks[key]
    if secrets[entry] ~= nil or mark == "N" then
      copy[key] = entry
    elseif kind == "table" then
      if named then
        local code = fields[key]
        copy[key] = concealTable(entry, code and parseCodes(code)[1].structure, structure and snapshot.innerTypes[structure .. "." .. key], all, depth + 1)
      else
        copy[key] = concealTable(entry, entries, nil, all, depth + 1)
      end
    elseif (all or mark == "S") and (kind == "number" or kind == "string" or kind == "boolean") then
      copy[key] = H.secret(entry)
    else
      copy[key] = entry
    end
  end
  return copy
end

local neverSets = {}
local function neverSecretSet(list)
  if not list then
    return nil
  end
  local set = neverSets[list]
  if not set then
    set = {}
    for _, position in ipairs(list) do
      set[position] = true
    end
    neverSets[list] = set
  end
  return set
end

-- Makes the values of a call secret where the documentation says so. `codes` are the documented
-- kinds of the values, `never` the positions marked NeverSecret, `inner(position)` the structure
-- of the entries of a list at that position.
local function conceal(codes, never, inner, all, n, out)
  never = neverSecretSet(never)
  local last = codes[#codes]
  for index = 1, n do
    local value = out[index]
    if value ~= nil and secrets[value] == nil then
      local entry = codes[index] or (last and last.list and last)
      local kind = realType(value)
      local secret = all and not (never and never[index])
      if kind == "table" then
        local structure, entries = entry and entry.structure, inner(index)
        if secret or hasAlwaysSecret(structure, 0) or hasAlwaysSecret(entries, 0) then
          out[index] = concealTable(value, structure, entries, secret, 0)
        end
      elseif secret and (kind == "number" or kind == "string" or kind == "boolean") then
        out[index] = H.secret(value)
      end
    end
  end
end

local function concealResults(key, spec, n, out, ...)
  conceal(spec.returns, key and snapshot.neverSecret[key], function(index)
    return key and snapshot.innerTypes[key .. "@" .. index]
  end, (key and SECRET_AT_ALL_TIMES[key]) or secretNow(key and snapshot.secretWhen[key], spec, ...), n, out)
end

-- The same for the arguments of an event that the driver sends. An event with SecretPayloads
-- and no named restriction is as a function with SecretReturns: secret in the fight.
function H.concealPayload(event, values, n)
  local flags = snapshot.eventFlags[event] or ""
  local all = (flags:find("S", 1, true) ~= nil and inFight()) or secretNow(snapshot.eventSecretWhen[event], nil, unpack(values, 1, n))
  conceal(parseCodes(snapshot.events[event] or ""), snapshot.eventNeverSecret[event], function() return nil end, all, n, values)
end

-- The results of a stand-in: defaults of the documented kinds, secret where the documentation
-- says so. `key` is nil for a method of a widget: the restrictions of widgets (a secret
-- anchor, a secret aspect) are not followed, only the flags C and S.
local function results(key, spec, ...)
  local out, n = {}, 0
  for _, entry in ipairs(spec.returns) do
    if entry.list then
      break
    end
    n = n + 1
    out[n] = defaultOf(entry, 0)
  end
  concealResults(key, spec, n, out, ...)
  return out, n
end

local function stub(name, specText, strict)
  local spec = parseSpec(specText)
  return function(...)
    checkArguments(name, spec, strict, ...)
    local out, n = results(name, spec, ...)
    return unpack(out, 1, n)
  end
end
H.stub = stub

-- The same for a method of a widget: the first argument is the widget itself.
function H.methodStub(name, specText)
  local spec = parseSpec(specText)
  return function(_, ...)
    checkArguments(name, spec, false, ...)
    local out, n = results(nil, spec, ...)
    return unpack(out, 1, n)
  end
end

-- Conformance of the stand-in itself. A hand-written function stands for a documented one, so
-- what it returns must be what the documentation says: the number of values, the kind of each
-- one, and for a structure the names and kinds of its fields. A difference is a problem of the
-- stand-in, not of an addon: the driver reports it and the test fails. So the hand-written
-- world cannot drift from Blizzard's documentation without notice.
H.problems, H.problemSeen = {}, {}
local function problem(text)
  if not H.problemSeen[text] then
    H.problemSeen[text] = true
    H.problems[#H.problems + 1] = text
  end
end
H.problem = problem

-- Where the game returns nil although the documentation does not say so. Each entry needs the
-- reason. The kinds of the values are still checked.
H.nilAllowed = {}
function H.allowNil(name, reason)
  if realType(reason) ~= "string" or #reason < 20 then
    error("H.allowNil needs the reason for " .. name)
  end
  H.nilAllowed[name] = reason
end

local KIND_OF_TYPE = { number = "n", string = "s", boolean = "b", table = "t", ["function"] = "f" }

local function checkValue(where, entry, value, depth)
  value = plain(value)
  if value == nil then
    return
  end
  local kind, actual = entry.kind, realType(value)
  if kind == "a" or kind == "o" then
    return
  end
  if KIND_OF_TYPE[actual] ~= kind then
    problem(where .. " is a " .. actual .. ", and the documentation has a " .. (KIND_NAME[kind] or (kind == "b" and "boolean") or kind))
    return
  end
  local fields = kind == "t" and entry.structure and snapshot.structures[entry.structure]
  if not fields or depth > 3 then
    return
  end
  for key, field in pairs(value) do
    if realType(key) == "string" then
      local code = fields[key]
      if not code then
        problem(where .. " has the field " .. key .. ", which the structure " .. entry.structure .. " does not have")
      elseif realType(field) ~= "function" then
        checkValue(where .. "." .. key, parseCodes(code)[1], field, depth + 1)
      end
    end
  end
  -- A field that the documentation always fills, and that the hand-written data left out, gets
  -- its documented default: the addon then reads a value of the right kind, as in the game.
  for key, code in pairs(fields) do
    if value[key] == nil then
      value[key] = defaultOf(parseCodes(code)[1], depth + 1)
    end
  end
end

-- Checks the results of a hand-written function against the documentation.
local function checkResults(name, spec, n, out)
  local returns = spec.returns
  local nilAllowed = H.nilAllowed[name] ~= nil
  local nothing = true
  for index = 1, n do
    if out[index] ~= nil then
      nothing = false
    end
  end
  -- "No result" is right for a function that the documentation marks so, and for one whose
  -- first result can be nil.
  if nothing then
    if #returns > 0 and not (nilAllowed or spec.flags:find("M", 1, true) or returns[1].optional or returns[1].list) then
      problem(name .. " returns nothing, and the documentation has a first result that is never nil")
    end
    return
  end
  local last = returns[#returns]
  for index = 1, n do
    local entry = returns[index] or (last and last.list and last)
    if not entry then
      if out[index] ~= nil then
        problem(name .. " returns " .. n .. " values, and the documentation has " .. #returns)
        return
      end
    elseif out[index] == nil then
      if not entry.optional and not entry.list and not nilAllowed then
        problem(name .. ": result " .. index .. " is nil, and the documentation says that it is never nil")
      end
    else
      checkValue(name .. ": result " .. index, entry, out[index], 0)
    end
  end
end
H.checkResults = checkResults

-- A hand-written function in the place of a documented one: it keeps the documented check of
-- the arguments, and its results are checked against the documentation.
function H.documented(name, specText, strict, fn)
  local spec = parseSpec(specText)
  return function(...)
    checkArguments(name, spec, strict, ...)
    local n, out = pack(fn(...))
    checkResults(name, spec, n, out)
    concealResults(name, spec, n, out, ...)
    return unpack(out, 1, n)
  end
end

-- Each restriction that the documentation names has a rule or a reason for having none. A new
-- one, after a patch of the game, is a problem of the stand-in until someone reads its text.
do
  local seen = {}
  for _, list in ipairs({ snapshot.secretWhen, snapshot.eventSecretWhen }) do
    for _, names in pairs(list) do
      for name in names:gmatch("[^,]+") do
        if not seen[name] then
          seen[name] = true
          if RULES[name] == nil and UNKNOWN[name] == nil then
            problem("the documentation has the restriction " .. name .. ", and the stand-in has no rule for it: read its text in SecretPredicatesDocumentation.lua and add it to RULES or UNKNOWN in 01-api.lua")
          end
        end
      end
    end
  end
  for _, list in ipairs({ RULES, UNKNOWN }) do
    for name in pairs(list) do
      if not seen[name] then
        problem("the stand-in has a rule for the restriction " .. name .. ", which the documentation does not use")
      end
    end
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
  -- A function of the Lua libraries has one right answer for its arguments. A stub would give
  -- 0, false or "" for it, and an addon would run on with a wrong value. So one that is not
  -- written by hand (below) fails when it is called.
  local library = namespace == "math" or namespace == "table" or namespace == "string"
  for name, spec in pairs(functions) do
    if space[name] == nil then
      if library then
        local label = namespace .. "." .. name
        H.unwritten = H.unwritten or {}
        H.unwritten[label] = true
        space[name] = function()
          if H.unwritten[label] then
            error("the stand-in for the game does not have " .. label .. " yet: write it in 01-api.lua", 2)
          end
        end
      else
        space[name] = stub(namespace .. "." .. name, spec, true)
      end
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
  -- A number is a text for the string functions of Lua.
  if realType(text) == "number" then
    text = realTostring(text)
  end
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
-- Any number of arguments, as in the game: Blizzard_AutoComplete/AutoComplete.lua calls
-- bit.bor with three.
local function fold(name, rule)
  return function(first, ...)
    if realType(first) ~= "number" then
      error("bad argument #1 to '" .. name .. "' (number expected, got " .. (first == nil and "no value" or realType(first)) .. ")", 2)
    end
    local result = math.floor(first) % 4294967296
    for index = 1, select("#", ...) do
      local value = select(index, ...)
      if realType(value) ~= "number" then
        error("bad argument #" .. (index + 1) .. " to '" .. name .. "' (number expected, got " .. realType(value) .. ")", 2)
      end
      result = bitwise(result, value, rule)
    end
    return result
  end
end
bit.band = fold("band", function(x, y) return x == 1 and y == 1 end)
bit.bor = fold("bor", function(x, y) return x == 1 or y == 1 end)
bit.bxor = fold("bxor", function(x, y) return x ~= y end)
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
  local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
  local DAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
  local hour = math.floor(seconds / 3600)
  local weekday = (days + 4) % 7 + 1 -- 1970-01-01 was a Thursday
  fields.y = plainFormat("%02d", year % 100)
  fields.B, fields.b = MONTHS[month], MONTHS[month]:sub(1, 3)
  fields.A, fields.a = DAYS[weekday], DAYS[weekday]:sub(1, 3)
  fields.p = hour < 12 and "AM" or "PM"
  fields.I = plainFormat("%02d", (hour + 11) % 12 + 1)
  fields["%"] = "%"
  fields.c = plainFormat("%02d/%02d/%02d %02d:%02d:%02d", month, day, year % 100, hour, math.floor(seconds / 60) % 60, seconds % 60)
  if pattern ~= nil and realType(pattern) ~= "string" then
    error("bad argument #1 to 'date' (string expected, got " .. realType(pattern) .. ")", 2)
  end
  return ((pattern or "%c"):gsub("%%(.)", function(letter)
    -- A letter that is not written here must not give an empty text without a word.
    return fields[letter] or error("the stand-in for the game does not have the date letter %" .. letter .. " yet: add it in 01-api.lua", 3)
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

-- Blizzard_PrintHandler/Blizzard_PrintHandler.lua defines tostringall.
function tostringall(...)
  local out, n = {}, select("#", ...)
  for i = 1, n do
    out[i] = tostring((select(i, ...)))
  end
  return unpack(out, 1, n)
end
-- Blizzard_AnimatedShine/Shared/AnimatedShine.lua: tDeleteItem(list, item) takes every place
-- with the item out of a list, and gives the number of them.
function tDeleteItem(list, item)
  local count = 0
  for index = #list, 1, -1 do
    if list[index] == item then
      table.remove(list, index)
      count = count + 1
    end
  end
  return count
end
-- Blizzard_ActionBar/Shared/ActionButton.lua asks issecure(): never true for the code of an addon.
function issecure()
  return false
end
-- scrub keeps texts, numbers and booleans and gives nil for every other value
-- (Blizzard_RestrictedAddOnEnvironment/RestrictedEnvironment.lua). A secret value is not
-- refused: it is taken out too.
function scrub(...)
  local out, n = {}, select("#", ...)
  for i = 1, n do
    local value = select(i, ...)
    local kind = realType(value)
    if secrets[value] == nil and (kind == "string" or kind == "number" or kind == "boolean") then
      out[i] = value
    end
  end
  return unpack(out, 1, n)
end
-- mapvalues(fn, ...) gives fn(value) for each value
-- (Blizzard_RestrictedAddOnEnvironment/RestrictedEnvironment.lua: mapvalues(ScrubInboundValue, ...)).
function mapvalues(fn, ...)
  if realType(fn) ~= "function" then
    error("bad argument #1 to 'mapvalues' (function expected, got " .. realType(fn) .. ")", 2)
  end
  local out, n = {}, select("#", ...)
  for i = 1, n do
    out[i] = fn((select(i, ...)))
  end
  return unpack(out, 1, n)
end
-- The text of the call stack, as the game's debugstack gives it (Blizzard_ScriptErrors.lua calls it):
-- the file of each addon line is "Interface/AddOns/<addon>/<file>.lua:<line>". The levels of the
-- stack are those of debug.traceback; `top` and `bottom` are not modelled.
-- The lines of the harness (its scenarios and driver) are not in the game: they are left out, so
-- that a stack shows the addons and the game's code only, as in the game.
H.setGlobal("debugstack", function(start)
  local text = H.debug.traceback("", (start or 1) + 1)
  local kept = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local file = line:match("^%s*(%S+%.lua):%d+")
    if not (file and file:sub(1, 8) == "harness/") then
      kept[#kept + 1] = (line:gsub("^(%s*)(%S+%.lua):", "%1Interface/AddOns/%2:"))
    end
  end
  return table.concat(kept, "\n")
end, "Blizzard_ScriptErrors/Blizzard_ScriptErrors.lua")

-- The error handler of the game shows the error in ScriptErrorsFrame first (HandleLuaError in
-- Blizzard_ScriptErrors.lua calls DisplayMessageInternal with the stack), then the driver records it.
function geterrorhandler()
  return function(err)
    if ScriptErrorsFrame then
      pcall(ScriptErrorsFrame.DisplayMessageInternal, ScriptErrorsFrame, err, 0, debugstack(2), "<none>")
    end
    if H.onError then
      H.onError(H.errorWhere or "error handler", err)
    end
  end
end
function seterrorhandler() end


function hooksecurefunc(a, b, c)
  local target, name, hook = _G, a, b
  if realType(a) == "table" then
    target, name, hook = a, b, c
  end
  local original = target[name]
  if realType(original) ~= "function" or realType(hook) ~= "function" then
    fail("hooksecurefunc(): " .. realTostring(name) .. " is not a function")
  end
  local wrapper
  -- The driver tells a hook, which the game allows, from a function that an addon put in the
  -- place of the game's own (see "replaced functions" in driver.lua).
  H.hookedOriginal = H.hookedOriginal or setmetatable({}, { __mode = "k" })
  wrapper = function(...)
    local n, out = pack(original(...))
    hook(...)
    return unpack(out, 1, n)
  end
  H.hookedOriginal[wrapper] = original
  target[name] = wrapper
end
function securecallfunction(fn, ...)
  return fn(...)
end
-- securecall takes a function or the name of a global one (Blizzard_BuffFrame/BuffFrame.lua,
-- Blizzard_CatalogShop/Blizzard_CatalogShop_Outbound.lua).
function securecall(fn, ...)
  if realType(fn) == "string" then
    fn = _G[fn]
  end
  if realType(fn) ~= "function" then
    return
  end
  return fn(...)
end
