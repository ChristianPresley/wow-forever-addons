local _, ns = ...

-- The experience of the player: how fast it comes, how long the level takes, how many kills and
-- quests are left, and the rested bonus.
--
-- Saved data, in ForeverLevelingDB (for all characters):
--   version = 1
--   options = { show, lock, showBar, showZones, zoneSpread, samples, scale }
--   frames  = { readout = { point, relativePoint, x, y }, zones = { ... } }

local DATA_VERSION = 1

function ns.Print(msg)
  print("|cffc9a227Forever Leveling|r: " .. tostring(msg))
end

-- True for a number that the addon can calculate with (see docs/addon-development.md).
function ns.Usable(value)
  if issecretvalue and issecretvalue(value) then
    return false
  end
  return type(value) == "number"
end

---------------------------------------------------------------------------------------------------
-- Options

ns.OPTION_DEFAULTS = {
  show = true, -- the readout
  lock = false, -- a locked readout does not move
  showBar = true, -- the experience bar in the readout
  showZones = false, -- the window with the zones for your level
  zoneSpread = 3, -- levels below and above yours that still suit you
  samples = 20, -- the last kills and quests that make the averages
  scale = 100, -- percent, of the readout
}

ns.OPTION_LIMITS = {
  zoneSpread = { 0, 10 },
  samples = { 3, 50 },
  scale = { 60, 150 },
}

local listeners = {}

-- fn runs after each change of an option, and after each change of the numbers.
function ns.OnChange(fn)
  listeners[#listeners + 1] = fn
end

function ns.Changed()
  for _, fn in ipairs(listeners) do
    local ok, err = pcall(fn)
    if not ok then
      geterrorhandler()(err)
    end
  end
end

function ns.GetOption(key)
  if not ForeverLevelingDB then
    return ns.OPTION_DEFAULTS[key]
  end
  return ForeverLevelingDB.options[key]
end

-- Returns false for a key that is not an option.
function ns.SetOption(key, value)
  local default = ns.OPTION_DEFAULTS[key]
  if default == nil or not ForeverLevelingDB then
    return false
  end
  if type(default) == "number" then
    local limit = ns.OPTION_LIMITS[key]
    value = math.floor((tonumber(value) or default) + 0.5)
    value = math.max(limit[1], math.min(limit[2], value))
  else
    value = value and true or false
  end
  ForeverLevelingDB.options[key] = value
  ns.Changed()
  return true
end

---------------------------------------------------------------------------------------------------
-- Numbers. These functions take their inputs, so that the scenario can check them.

-- Experience per hour from what the session gained in so many seconds. Nil for less than a minute.
function ns.PerHour(gained, seconds)
  if not (ns.Usable(gained) and ns.Usable(seconds)) or seconds < 60 or gained <= 0 then
    return nil
  end
  return gained * 3600 / seconds
end

-- Seconds to the next level at a rate per hour, or nil.
function ns.TimeToLevel(remaining, perHour)
  if not (ns.Usable(remaining) and ns.Usable(perHour)) or perHour <= 0 then
    return nil
  end
  return remaining * 3600 / perHour
end

-- How many times an average gain is left, rounded up, or nil without an average.
function ns.CountToLevel(remaining, average)
  if not (ns.Usable(remaining) and ns.Usable(average)) or average <= 0 then
    return nil
  end
  return math.ceil(remaining / average)
end

function ns.Average(list)
  if type(list) ~= "table" or #list == 0 then
    return nil
  end
  local sum = 0
  for _, value in ipairs(list) do
    sum = sum + value
  end
  return sum / #list
end

-- 3725 seconds is "1h 2m"; 95 is "1m 35s".
function ns.Duration(seconds)
  if not ns.Usable(seconds) then
    return "?"
  end
  seconds = math.floor(seconds + 0.5)
  if seconds >= 3600 then
    return string.format("%dh %dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
  elseif seconds >= 60 then
    return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
  end
  return seconds .. "s"
end

-- 12345 is "12,345".
function ns.Thousands(value)
  if not ns.Usable(value) then
    return "?"
  end
  local text = tostring(math.floor(value + 0.5))
  local sign, digits = text:match("^(-?)(%d+)$")
  if not digits then
    return text
  end
  digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return sign .. digits
end

---------------------------------------------------------------------------------------------------
-- The state of the player, read from the game

ns.session = { start = 0, gained = 0, kills = {}, quests = {} }

local last = { xp = nil, max = nil, level = nil }

-- The game says in one event that the experience changed, and in another one why (a kill, a
-- quest). The order of the two is not sure, so each waits this long for the other.
local CLAIM_SECONDS = 2
local pendingQuestXP, pendingQuestAt = 0, nil -- a quest was turned in, its experience is not here yet
local pendingKillAt = nil -- the game reported a kill, its experience is not here yet
local unclaimed, unclaimedAt = 0, nil -- experience that no event has explained yet

local function fresh(at)
  return at ~= nil and GetTime() - at <= CLAIM_SECONDS
end

local function read()
  local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  if not (ns.Usable(xp) and ns.Usable(max) and ns.Usable(level)) then
    return nil
  end
  return xp, max, level
end

-- What the readout shows: a table of plain numbers, or nil if the game hides them.
function ns.State()
  local xp, max, level = read()
  if not xp then
    return nil
  end
  local rested = GetXPExhaustion()
  if not ns.Usable(rested) then
    rested = 0
  end
  local cap = GetMaxLevelForPlayerExpansion()
  local state = {
    xp = xp,
    max = max,
    level = level,
    remaining = math.max(0, max - xp),
    rested = rested,
    maxLevel = ns.Usable(cap) and level >= cap or false,
  }
  local now = GetTime()
  state.elapsed = now - ns.session.start
  state.perHour = ns.PerHour(ns.session.gained, state.elapsed)
  state.timeToLevel = ns.TimeToLevel(state.remaining, state.perHour)
  state.killXP = ns.Average(ns.session.kills)
  state.questXP = ns.Average(ns.session.quests)
  state.killsToLevel = ns.CountToLevel(state.remaining, state.killXP)
  state.questsToLevel = ns.CountToLevel(state.remaining, state.questXP)
  return state
end

local function remember(list, value)
  list[#list + 1] = value
  local keep = ns.GetOption("samples")
  while #list > keep do
    table.remove(list, 1)
  end
end

-- A new reading of the experience: the gain goes to the session, to a quest that was just turned
-- in, and the rest to a kill if the game reported one.
function ns.Update()
  local xp, max, level = read()
  if not xp then
    return
  end
  if last.xp then
    -- A new level: the experience starts again. The level and the experience do not always
    -- change in the same event, so a reading with the same experience as the last one is no gain.
    local gained = xp - last.xp
    if xp < last.xp or ((level > last.level or max ~= last.max) and xp ~= last.xp) then
      gained = (last.max - last.xp) + xp
    end
    if gained > 0 then
      ns.session.gained = ns.session.gained + gained
      local fromQuest = fresh(pendingQuestAt) and math.min(gained, pendingQuestXP) or 0
      if fromQuest > 0 then
        remember(ns.session.quests, fromQuest)
      end
      local rest = gained - fromQuest
      if rest > 0 and fresh(pendingKillAt) then
        remember(ns.session.kills, rest)
        unclaimed, unclaimedAt = 0, nil
      else
        unclaimed, unclaimedAt = rest, GetTime()
      end
      pendingQuestXP, pendingQuestAt, pendingKillAt = 0, nil, nil
    end
  end
  last.xp, last.max, last.level = xp, max, level
  ns.Changed()
end

function ns.ResetSession()
  ns.session = { start = GetTime(), gained = 0, kills = {}, quests = {} }
  last.xp = nil
  pendingQuestXP, pendingQuestAt, pendingKillAt = 0, nil, nil
  unclaimed, unclaimedAt = 0, nil
  ns.Update()
end

-- The experience that came just before its reason: it goes to the list, up to a limit.
local function claim(list, limit)
  if unclaimed <= 0 or not fresh(unclaimedAt) then
    return false
  end
  remember(list, limit and math.min(unclaimed, limit) or unclaimed)
  unclaimed, unclaimedAt = 0, nil
  ns.Changed()
  return true
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
  if event == "QUEST_TURNED_IN" then
    local _, xpReward = ...
    if ns.Usable(xpReward) and xpReward > 0 and not claim(ns.session.quests, xpReward) then
      pendingQuestXP = (fresh(pendingQuestAt) and pendingQuestXP or 0) + xpReward
      pendingQuestAt = GetTime()
    end
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    if not claim(ns.session.kills) then
      pendingKillAt = GetTime()
    end
  elseif event == "PLAYER_XP_UPDATE" then
    local unit = ...
    if unit == nil or unit == "player" then
      ns.Update()
    end
  else
    ns.Update()
  end
end)
for _, event in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "QUEST_TURNED_IN", "CHAT_MSG_COMBAT_XP_GAIN", "ZONE_CHANGED_NEW_AREA" }) do
  pcall(events.RegisterEvent, events, event)
end

---------------------------------------------------------------------------------------------------
-- Start

local logins = {}

function ns.OnLogin(fn)
  logins[#logins + 1] = fn
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
  if event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    ns.session.start = GetTime()
    for _, fn in ipairs(logins) do
      local ok, err = pcall(fn)
      if not ok then
        geterrorhandler()(err)
      end
    end
    ns.Update()
    return
  end
  if name ~= "ForeverLeveling" then
    return
  end
  self:UnregisterEvent("ADDON_LOADED")
  if type(ForeverLevelingDB) ~= "table" then
    ForeverLevelingDB = {}
  end
  local db = ForeverLevelingDB
  db.version = DATA_VERSION
  if type(db.options) ~= "table" then
    db.options = {}
  end
  for key, default in pairs(ns.OPTION_DEFAULTS) do
    if type(db.options[key]) ~= type(default) then
      db.options[key] = default
    end
  end
  for key, limit in pairs(ns.OPTION_LIMITS) do
    db.options[key] = math.max(limit[1], math.min(limit[2], math.floor(db.options[key] + 0.5)))
  end
  if type(db.frames) ~= "table" then
    db.frames = {}
  end
end)
