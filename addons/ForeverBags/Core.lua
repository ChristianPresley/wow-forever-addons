local _, ns = ...

-- Forever Bags: one bag window, and the items of all characters.
--
-- Saved data, in ForeverBagsDB (for all characters of the account):
--   version     = 1
--   options     = see ns.DEFAULTS
--   frames      = { window = { point, relativePoint, x, y }, browser = { ... } }
--   characters  = { ["Name-Realm"] = { name, realm, class, level, money, updated,
--                                      bags = { [itemID] = count }, bank = { ... }, equipped = { ... },
--                                      bankSeen = time of the last look at the bank, or nil } }
--   accountBank = { [itemID] = count }   -- the bank that all characters share

local DATA_VERSION = 1

function ns.Print(msg)
  print("|cff6fb7e8Forever Bags|r: " .. tostring(msg))
end

-- How the bag window orders the items.
ns.GROUPINGS = {
  { "category", "By category" },
  { "none", "In the order of the bags" },
}

-- Options. The type of the default is the type of the option.
ns.DEFAULTS = {
  replaceBags = true, -- the bag key and the bag buttons open this window, not the window of the game
  groupBy = "category", -- a key of ns.GROUPINGS
  columns = 10, -- item buttons in a row
  scale = 100, -- percent, of the item buttons
  alpha = 90, -- percent, of the background
  lock = false, -- a locked window does not move
  tooltipCounts = true, -- how many of an item this character owns
  tooltipAlts = true, -- how many the other characters own
}

ns.LIMITS = {
  columns = { 6, 18 },
  scale = { 60, 140 },
  alpha = { 30, 100 },
}

local listeners = {}

-- fn runs with the key after each change of an option.
function ns.OnChange(fn)
  listeners[#listeners + 1] = fn
end

function ns.GetOption(key)
  local options = ForeverBagsDB and ForeverBagsDB.options
  if not options or options[key] == nil then
    return ns.DEFAULTS[key]
  end
  return options[key]
end

-- Each change of an option goes through here. Returns false for a value that the option cannot have.
function ns.SetOption(key, value)
  local default = ns.DEFAULTS[key]
  if default == nil or not ForeverBagsDB then
    return false
  end
  if type(default) == "number" then
    local limit = ns.LIMITS[key]
    value = math.floor((tonumber(value) or default) + 0.5)
    value = math.max(limit[1], math.min(limit[2], value))
  elseif type(default) == "boolean" then
    value = value and true or false
  elseif key == "groupBy" then
    local known = false
    for _, grouping in ipairs(ns.GROUPINGS) do
      known = known or grouping[1] == value
    end
    if not known then
      return false
    end
  end
  ForeverBagsDB.options[key] = value
  for _, fn in ipairs(listeners) do
    local ok, err = pcall(fn, key)
    if not ok then
      geterrorhandler()(err)
    end
  end
  return true
end

function ns.Money(copper)
  return GetMoneyString(copper, true)
end

---------------------------------------------------------------------------------------------------
-- Frame positions

function ns.SavePosition(name, frame)
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  if point and ForeverBagsDB then
    ForeverBagsDB.frames[name] = { point = point, relativePoint = relativePoint, x = x, y = y }
  end
end

-- Puts a frame at its saved place, or at the default place.
function ns.RestorePosition(name, frame, point, x, y)
  local saved = ForeverBagsDB and ForeverBagsDB.frames[name]
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
  ForeverBagsDB.frames = {}
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

local function tableAt(parent, key)
  if type(parent[key]) ~= "table" then
    parent[key] = {}
  end
  return parent[key]
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
  if name ~= "ForeverBags" then
    return
  end
  self:UnregisterEvent("ADDON_LOADED")
  if type(ForeverBagsDB) ~= "table" then
    ForeverBagsDB = {}
  end
  local db = ForeverBagsDB
  db.version = DATA_VERSION
  local options = tableAt(db, "options")
  tableAt(db, "frames")
  tableAt(db, "characters")
  tableAt(db, "accountBank")
  -- An option that is missing or has the wrong type gets its default.
  for key, default in pairs(ns.DEFAULTS) do
    if type(options[key]) ~= type(default) then
      options[key] = default
    end
  end
  for key, limit in pairs(ns.LIMITS) do
    options[key] = math.max(limit[1], math.min(limit[2], math.floor(options[key] + 0.5)))
  end
  if options.groupBy ~= "category" and options.groupBy ~= "none" then
    options.groupBy = ns.DEFAULTS.groupBy
  end
end)
