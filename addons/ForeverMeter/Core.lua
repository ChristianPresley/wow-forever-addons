local _, ns = ...

-- Forever Meter shows what each player of the group did in a fight: damage, healing and more.
--
-- The combat log is closed to addons on this client. The numbers come from the game's own damage
-- data, C_DamageMeter (see Data.lua and docs/addon-development.md). During a fight the game gives
-- these numbers as secret values: an addon can show them, but it cannot calculate with them or
-- compare them. So during a fight the meter shows the game's order and numbers as they are, and
-- after the fight it adds what needs a calculation (percentages, reports to chat).
--
-- Saved data, in ForeverMeterDB (for all characters):
--   version = 1
--   options = see ns.DEFAULTS
--   frames  = { window = { point, relativePoint, x, y }, personal = { ... } }

local DATA_VERSION = 1

function ns.Print(msg)
  print("|cffe0503cForever Meter|r: " .. tostring(msg))
end

-- True for a value that the addon can show but not calculate with.
function ns.IsSecret(value)
  return issecretvalue ~= nil and issecretvalue(value) or false
end

-- True for a number that the addon can calculate with.
function ns.Usable(value)
  return not ns.IsSecret(value) and type(value) == "number"
end

-- What the meter can show. `type` is the name in Enum.DamageMeterType and `id` its value.
-- `rate`: the main number is the amount per second. `noRate`: there is no amount per second.
ns.MODES = {
  { key = "dps", type = "Dps", id = 1, label = "Damage per second", short = "DPS", rate = true },
  { key = "damage", type = "DamageDone", id = 0, label = "Damage done", short = "Damage" },
  { key = "hps", type = "Hps", id = 3, label = "Healing per second", short = "HPS", rate = true },
  { key = "healing", type = "HealingDone", id = 2, label = "Healing done", short = "Healing" },
  { key = "absorbs", type = "Absorbs", id = 4, label = "Absorbs", short = "Absorbs" },
  { key = "taken", type = "DamageTaken", id = 7, label = "Damage taken", short = "Taken" },
  { key = "avoidable", type = "AvoidableDamageTaken", id = 8, label = "Avoidable damage taken", short = "Avoidable" },
  { key = "enemy", type = "EnemyDamageTaken", id = 10, label = "Damage taken by enemies", short = "Enemies" },
  { key = "interrupts", type = "Interrupts", id = 5, label = "Interrupts", short = "Interrupts", noRate = true },
  { key = "dispels", type = "Dispels", id = 6, label = "Dispels", short = "Dispels", noRate = true },
  { key = "deaths", type = "Deaths", id = 9, label = "Deaths", short = "Deaths", noRate = true, deaths = true },
}

ns.ModeByKey = {}
for _, mode in ipairs(ns.MODES) do
  ns.ModeByKey[mode.key] = mode
end

-- Options. The type of the default is the type of the option.
ns.DEFAULTS = {
  show = true, -- the meter window
  lock = false, -- a locked window does not move
  hideOutOfCombat = false,
  showSolo = true, -- show the window without a group
  showParty = true,
  showRaid = true,
  rowsSolo = 3, -- bars in the window without a group
  rowsParty = 5,
  rowsRaid = 10,
  pinSelf = true, -- keep your own bar in view when it is farther down the list
  classColors = true,
  showRank = true, -- the place in the list before the name
  showPercent = true, -- the share of the group total, after a fight
  width = 230, -- pixels
  rowHeight = 18, -- pixels
  alpha = 85, -- percent, of the background
  updateTenths = 5, -- tenths of a second between two updates
  personal = true, -- the read-out of your own DPS
  personalLock = false,
  personalHealing = false, -- the read-out shows your HPS, not your DPS
  reportLines = 5, -- players in a report to chat
  autoReset = false, -- delete the data when you enter a dungeon or a raid
  keepFights = true, -- keep a copy of each fight, so the list survives a log out
  mode = "dps", -- a key of ns.MODES
}

ns.LIMITS = {
  rowsSolo = { 1, 10 },
  rowsParty = { 1, 10 },
  rowsRaid = { 3, 25 },
  width = { 160, 420 },
  rowHeight = { 12, 28 },
  alpha = { 0, 100 },
  updateTenths = { 2, 20 },
  reportLines = { 1, 15 },
}

local listeners = {}

-- fn runs with the key after each change of an option, and with nil after a change of the fight.
function ns.OnChange(fn)
  listeners[#listeners + 1] = fn
end

function ns.Changed(key)
  for _, fn in ipairs(listeners) do
    local ok, err = pcall(fn, key)
    if not ok then
      geterrorhandler()(err)
    end
  end
end

function ns.GetOption(key)
  local options = ForeverMeterDB and ForeverMeterDB.options
  if not options or options[key] == nil then
    return ns.DEFAULTS[key]
  end
  return options[key]
end

-- Each change of an option goes through here. Returns false for a value that the option cannot have.
function ns.SetOption(key, value)
  local default = ns.DEFAULTS[key]
  if default == nil or not ForeverMeterDB then
    return false
  end
  if type(default) == "number" then
    local limit = ns.LIMITS[key]
    value = math.floor((tonumber(value) or default) + 0.5)
    value = math.max(limit[1], math.min(limit[2], value))
  elseif type(default) == "boolean" then
    value = value and true or false
  elseif key == "mode" then
    if not ns.ModeByKey[value] then
      return false
    end
  end
  ForeverMeterDB.options[key] = value
  ns.Changed(key)
  return true
end

function ns.Mode()
  return ns.ModeByKey[ns.GetOption("mode")] or ns.MODES[1]
end

-- Which fight the meter shows: { type = n } for the current fight (1) or the whole session (0),
-- or { id = n, name = s } for an earlier fight. Not saved: the game forgets its fights at logout.
ns.segment = { type = 1 }

function ns.SetSegment(segment)
  ns.segment = segment
  ns.Changed(nil)
end

-- "solo", "party" or "raid".
function ns.GroupType()
  if IsInRaid and IsInRaid() then
    return "raid"
  elseif IsInGroup and IsInGroup() then
    return "party"
  end
  return "solo"
end

function ns.InCombat()
  return UnitAffectingCombat and UnitAffectingCombat("player") and true or false
end

---------------------------------------------------------------------------------------------------
-- Frame positions

function ns.SavePosition(name, frame)
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  if point and ForeverMeterDB then
    ForeverMeterDB.frames[name] = { point = point, relativePoint = relativePoint, x = x, y = y }
  end
end

-- Puts a frame at its saved place, or at the default place.
function ns.RestorePosition(name, frame, point, x, y)
  local saved = ForeverMeterDB and ForeverMeterDB.frames[name]
  frame:ClearAllPoints()
  if type(saved) == "table" and type(saved.point) == "string" and type(saved.x) == "number" and type(saved.y) == "number" then
    if pcall(frame.SetPoint, frame, saved.point, UIParent, saved.relativePoint or saved.point, saved.x, saved.y) then
      return
    end
    frame:ClearAllPoints()
  end
  frame:SetPoint(point, UIParent, point, x, y)
end

local resetters = {}

function ns.OnResetPositions(fn)
  resetters[#resetters + 1] = fn
end

function ns.ResetPositions()
  ForeverMeterDB.frames = {}
  for _, fn in ipairs(resetters) do
    pcall(fn)
  end
end

---------------------------------------------------------------------------------------------------
-- Start

local logins = {}

-- fn runs at PLAYER_LOGIN, when the saved data is ready. An error stops that part only.
function ns.OnLogin(fn)
  logins[#logins + 1] = fn
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
  if event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    for _, fn in ipairs(logins) do
      local ok, err = pcall(fn)
      if not ok then
        geterrorhandler()(err)
      end
    end
    return
  end
  if name ~= "ForeverMeter" then
    return
  end
  self:UnregisterEvent("ADDON_LOADED")
  if type(ForeverMeterDB) ~= "table" then
    ForeverMeterDB = {}
  end
  local db = ForeverMeterDB
  db.version = DATA_VERSION
  if type(db.options) ~= "table" then
    db.options = {}
  end
  if type(db.frames) ~= "table" then
    db.frames = {}
  end
  if type(db.history) ~= "table" then
    db.history = {}
  end
  -- An option that is missing or has the wrong type gets its default.
  for key, default in pairs(ns.DEFAULTS) do
    if type(db.options[key]) ~= type(default) then
      db.options[key] = default
    end
  end
  for key, limit in pairs(ns.LIMITS) do
    db.options[key] = math.max(limit[1], math.min(limit[2], math.floor(db.options[key] + 0.5)))
  end
  if not ns.ModeByKey[db.options.mode] then
    db.options.mode = ns.DEFAULTS.mode
  end
end)
