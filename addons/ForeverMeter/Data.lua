local _, ns = ...

-- The game's damage data (C_DamageMeter) and the helpers that show its numbers.
--
-- Every call is in a pcall: a client without the API, or a call that the game refuses during a
-- fight, gives nil and the meter shows less, not an error.

local CVAR = "damageMeterEnabled" -- the switch of the game's own damage meter

local function api()
  return C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and C_DamageMeter
end

-- Returns true, or false and the reason, for the damage data of the game.
function ns.Available()
  local meter = api()
  if not meter then
    return false, "This game client has no damage data for addons."
  end
  if meter.IsDamageMeterAvailable then
    local ok, available, reason = pcall(meter.IsDamageMeterAvailable)
    if ok and available == false then
      return false, type(reason) == "string" and reason ~= "" and reason or "The game does not allow the damage meter now."
    end
  end
  return true
end

-- True, false, or nil if this client has no such switch.
function ns.GameMeterEnabled()
  local get = C_CVar and C_CVar.GetCVar or GetCVar
  if not get then
    return nil
  end
  local ok, value = pcall(get, CVAR)
  if not ok or value == nil then
    return nil
  end
  return value == "1"
end

-- Turns on the damage meter of the game. Its own window can be hidden in the Edit Mode of the game.
function ns.EnableGameMeter()
  local set = C_CVar and C_CVar.SetCVar or SetCVar
  if not set then
    return false
  end
  return (pcall(set, CVAR, "1"))
end

local function modeID(mode)
  local enum = Enum and Enum.DamageMeterType
  local id = enum and enum[mode.type]
  return id == nil and mode.id or id
end

-- The data of a fight for a mode: { combatSources = { ... }, maxAmount, totalAmount }, or nil.
-- The sources are in the order of the game: the highest first.
function ns.GetSession(mode, segment)
  local meter = api()
  if not meter then
    return nil
  end
  local ok, session
  if segment.id then
    ok, session = pcall(meter.GetCombatSessionFromID, segment.id, modeID(mode))
  else
    ok, session = pcall(meter.GetCombatSessionFromType, segment.type, modeID(mode))
  end
  if ok and type(session) == "table" and type(session.combatSources) == "table" then
    return session
  end
  return nil
end

-- The spells of one source: { combatSpells = { ... }, maxAmount, totalAmount }, or nil.
-- The game refuses this during a fight for a source whose identity is secret.
function ns.GetSource(mode, segment, guid, creatureID)
  local meter = api()
  if not (meter and meter.GetCombatSessionSourceFromType) then
    return nil
  end
  local ok, source
  if segment.id then
    ok, source = pcall(meter.GetCombatSessionSourceFromID, segment.id, modeID(mode), guid, creatureID)
  else
    ok, source = pcall(meter.GetCombatSessionSourceFromType, segment.type, modeID(mode), guid, creatureID)
  end
  if ok and type(source) == "table" and type(source.combatSpells) == "table" then
    return source
  end
  return nil
end

-- The fights that the game remembers: { { sessionID, name, durationSeconds }, ... }, the oldest first.
function ns.Sessions()
  local meter = api()
  if not (meter and meter.GetAvailableCombatSessions) then
    return {}
  end
  local ok, sessions = pcall(meter.GetAvailableCombatSessions)
  return ok and type(sessions) == "table" and sessions or {}
end

-- Seconds that a fight lasted, or nil.
function ns.Duration(segment)
  local meter = api()
  if not meter then
    return nil
  end
  if segment.id then
    for _, session in ipairs(ns.Sessions()) do
      if session.sessionID == segment.id then
        return ns.Usable(session.durationSeconds) and session.durationSeconds or nil
      end
    end
    return nil
  end
  if not meter.GetSessionDurationSeconds then
    return nil
  end
  local ok, seconds = pcall(meter.GetSessionDurationSeconds, segment.type)
  return ok and ns.Usable(seconds) and seconds or nil
end

function ns.ResetData()
  local meter = api()
  if not (meter and meter.ResetAllCombatSessions) then
    return false
  end
  local ok = pcall(meter.ResetAllCombatSessions)
  ns.segment = { type = 1 }
  ns.Changed(nil)
  return ok
end

function ns.SegmentName(segment)
  if segment.id then
    return type(segment.name) == "string" and segment.name ~= "" and segment.name or ("Fight " .. segment.id)
  end
  return segment.type == 0 and "Whole session" or "Current fight"
end

---------------------------------------------------------------------------------------------------
-- Numbers and text

-- 1234 -> "1.2K". For a number that the addon can calculate with.
function ns.Short(value)
  local size = math.abs(value)
  if size >= 1e9 then
    return string.format("%.2fB", value / 1e9)
  elseif size >= 1e6 then
    return string.format("%.2fM", value / 1e6)
  elseif size >= 1e4 then
    return string.format("%.1fK", value / 1e3)
  elseif size >= 1e3 then
    return string.format("%.2fK", value / 1e3)
  end
  return string.format("%d", math.floor(value + 0.5))
end

function ns.Clock(seconds)
  seconds = math.max(0, math.floor(seconds + 0.5))
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- The text of a number: short for a number that the addon can read. For a secret number, the
-- text comes from the game's own function, which can read it, and is secret too.
-- Returns true and the text, or false. (A secret text cannot be compared, not even with nil,
-- so the first result says if there is a text.)
--
-- A number on the screen never has more than two decimals. The addon cannot round a secret
-- number, so it gives the game's function its own rules, the same as ns.Short: 2.50M, 12.3K,
-- 1.23K, and a whole number below 1000. Without rules the game's function leaves a small
-- number as it is, with all its decimals.
local BREAKPOINTS = { -- from the largest to the smallest, as the game wants them
  { breakpoint = 1e9, abbreviation = "B", significandDivisor = 1e7, fractionDivisor = 100, abbreviationIsGlobal = false },
  { breakpoint = 1e6, abbreviation = "M", significandDivisor = 1e4, fractionDivisor = 100, abbreviationIsGlobal = false },
  { breakpoint = 1e4, abbreviation = "K", significandDivisor = 100, fractionDivisor = 10, abbreviationIsGlobal = false },
  { breakpoint = 1e3, abbreviation = "K", significandDivisor = 10, fractionDivisor = 100, abbreviationIsGlobal = false },
  { breakpoint = 0, abbreviation = "", significandDivisor = 1, fractionDivisor = 1, abbreviationIsGlobal = false },
}
-- No source says that the game takes these rules as they are (the row for the numbers below
-- 1000 most of all), so the addon tries them once, with numbers that it can read: the rules are
-- used only if every text that comes back has two decimals at most. If not, the font string
-- formats the number itself, with two decimals.
local SAMPLES = { 0.123456, 345.678901, 999.999, 1234.56789, 12345.6789, 2567890.123, 3500000000.123 }
local function twoDecimalsAtMost(text)
  return type(text) == "string" and text ~= "" and not text:find("%.%d%d%d") and not text:find("[eE][+-]?%d")
end
local function rulesWork(options)
  for _, sample in ipairs(SAMPLES) do
    local ok, text = pcall(AbbreviateNumbers, sample, options)
    if not ok or not twoDecimalsAtMost(text) then
      return false
    end
  end
  return true
end
local abbreviateOptions -- nil: not tried yet; false: the game does not take the rules

local function chooseRules()
  abbreviateOptions = false
  if type(AbbreviateNumbers) ~= "function" then
    return
  end
  local candidates = {}
  if type(CreateAbbreviateConfig) == "function" then
    -- A config object makes the many calls cheaper, where the client has it.
    local okConfig, config = pcall(CreateAbbreviateConfig, BREAKPOINTS)
    if okConfig and config then
      candidates[#candidates + 1] = { config = config }
    end
  end
  candidates[#candidates + 1] = { breakpointData = BREAKPOINTS }
  for _, options in ipairs(candidates) do
    if rulesWork(options) then
      abbreviateOptions = options
      return
    end
  end
end

-- How a secret number gets its text: "rules" (the game's function with the rules of the
-- addon) or "plain" (two decimals, by the font string). For /fmeter status and the tests.
function ns.NumberWay()
  if abbreviateOptions == nil then
    chooseRules()
  end
  return abbreviateOptions and "rules" or "plain"
end

-- Tries the rules again (after a change of the game's functions; for the tests).
function ns.ResetNumberWay()
  abbreviateOptions = nil
end

local function numberText(value)
  if ns.Usable(value) then
    return true, ns.Short(value)
  end
  if not ns.IsSecret(value) then
    return false
  end
  if ns.NumberWay() == "rules" then
    local ok, text = pcall(AbbreviateNumbers, value, abbreviateOptions)
    if ok then
      return true, text
    end
  end
  return false
end

-- A number that a font string can format: one that the addon can read, or a secret one.
local function isNumber(value)
  return ns.IsSecret(value) or ns.Usable(value)
end

-- Shows a number in a font string. With hasSecond, a second number follows in brackets. The
-- suffix is a text of the addon that goes at the end. Works for secret numbers.
--
-- The font string puts the parts together (SetFormattedText, which the game's documentation
-- opens to addons for secret values). The addon itself joins no secret text and formats no
-- secret number: no source says that the game lets an addon do that.
function ns.SetNumber(fontString, value, hasSecond, second, suffix)
  suffix = suffix or ""
  local found, text = numberText(value)
  local foundSecond, secondText = false, nil
  if hasSecond then
    foundSecond, secondText = numberText(second)
  end
  if found then
    if foundSecond then
      if pcall(fontString.SetFormattedText, fontString, "%s (%s)%s", text, secondText, suffix) then
        return
      end
    elseif not hasSecond or not isNumber(second) then
      if pcall(fontString.SetFormattedText, fontString, "%s%s", text, suffix) then
        return
      end
    end
  end
  -- Without a text from the game's function: the font string formats the numbers, two decimals.
  if isNumber(value) then
    if hasSecond and isNumber(second) and pcall(fontString.SetFormattedText, fontString, "%.2f (%.2f)%s", value, second, suffix) then
      return
    end
    if pcall(fontString.SetFormattedText, fontString, "%.2f%s", value, suffix) then
      return
    end
  end
  if not (found and pcall(fontString.SetText, fontString, text)) then
    fontString:SetText("")
  end
end

-- The numbers at the right of a bar have a column of a fixed width, and the name ends where
-- the column starts. A font string with a secret text has a secret width, and what hangs on
-- it could not be placed (the game's own code gives such texts a fixed width for that:
-- Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.lua).
-- row: { value = , name = , bar = }. wide: two numbers and a share; else one number.
function ns.SetValueColumn(row, wide)
  local width = wide and 132 or 78
  if row.valueWidth ~= width then
    row.valueWidth = width
    row.value:SetWidth(width)
    row.name:SetPoint("RIGHT", row.bar, "RIGHT", -(width + 10), 0)
  end
end
-- Shows a text that can be secret (a player name during a fight), with an optional number before it.
function ns.SetName(fontString, name, rank)
  if rank then
    if not ns.IsSecret(name) and type(name) == "string" then
      fontString:SetText(rank .. ". " .. name)
      return
    end
    if pcall(fontString.SetFormattedText, fontString, "%d. %s", rank, name) then
      return
    end
  end
  if not pcall(fontString.SetText, fontString, name) then
    fontString:SetText("")
  end
end

-- Fills a status bar. Works for secret numbers.
function ns.SetBar(bar, value, max)
  if ns.Usable(max) and max <= 0 then
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return
  end
  if not (pcall(bar.SetMinMaxValues, bar, 0, max) and pcall(bar.SetValue, bar, value)) then
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
  end
end

-- Red, green and blue for a source: the colour of its class, or grey.
function ns.SourceColor(classFilename)
  if ns.GetOption("classColors") and type(classFilename) == "string" and not ns.IsSecret(classFilename) then
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename]
    if color then
      return color.r, color.g, color.b
    end
  end
  return 0.55, 0.55, 0.6
end

-- The source of the player in a fight, and its place in the list. Nil if the player did nothing.
function ns.OwnSource(session)
  for index, source in ipairs(session.combatSources) do
    if source.isLocalPlayer == true then
      return source, index
    end
  end
  return nil
end
