local _, ns = ...

-- Forever Gear: gear lists for each class and role, a loot browser, and tooltip lines.
--
-- Saved data, in ForeverGearDB (for all characters of the account):
--   version  = 1
--   options  = see ns.DEFAULTS
--   roles    = { [classFile] = role key }   -- the role of the lists, for each class
--   personal = { [itemID] = slot key or "" }  -- the items the player put on their own list
--   frames   = { window = { point, relativePoint, x, y } }

local DATA_VERSION = 1

function ns.Print(msg)
  print("|cffe8b96fForever Gear|r: " .. tostring(msg))
end

ns.DEFAULTS = {
  tooltipList = true, -- "On the list" lines in item tooltips
  tooltipUpgrade = true, -- the line that compares the item with the equipped one
  tooltipOtherRoles = false, -- also name the other roles of the class that list the item
  showSource = true, -- where an item comes from, in the window
  lock = false, -- a locked window does not move
}

local listeners = {}

function ns.OnOptionChanged(fn)
  listeners[#listeners + 1] = fn
end

local function changed(key)
  for _, fn in ipairs(listeners) do
    local ok, err = pcall(fn, key)
    if not ok then
      geterrorhandler()(err)
    end
  end
end
ns.Changed = changed

function ns.GetOption(key)
  local options = ForeverGearDB and ForeverGearDB.options
  if not options or options[key] == nil then
    return ns.DEFAULTS[key]
  end
  return options[key]
end

function ns.SetOption(key, value)
  local default = ns.DEFAULTS[key]
  if default == nil or not ForeverGearDB then
    return false
  end
  ForeverGearDB.options[key] = value and true or false
  changed(key)
  return true
end

---------------------------------------------------------------------------------------------------
-- The class and the role

function ns.PlayerClass()
  local _, classFile = UnitClass("player")
  return classFile or "WARRIOR"
end

-- The role keys of a class, in the order of ns.CLASS_ROLES.
function ns.RolesOf(class)
  return ns.CLASS_ROLES[class] or ns.CLASS_ROLES.WARRIOR
end

function ns.GetRole(class)
  class = class or ns.PlayerClass()
  local roles = ns.RolesOf(class)
  local saved = ForeverGearDB and ForeverGearDB.roles[class]
  for _, role in ipairs(roles) do
    if role == saved then
      return saved
    end
  end
  return roles[1]
end

-- Returns false for a role that the class does not have.
function ns.SetRole(role, class)
  class = class or ns.PlayerClass()
  if not ForeverGearDB then
    return false
  end
  for _, known in ipairs(ns.RolesOf(class)) do
    if known == role then
      ForeverGearDB.roles[class] = role
      changed("role")
      return true
    end
  end
  return false
end

---------------------------------------------------------------------------------------------------
-- Frame positions

function ns.SavePosition(name, frame)
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  if point and ForeverGearDB then
    ForeverGearDB.frames[name] = { point = point, relativePoint = relativePoint, x = x, y = y }
  end
end

function ns.RestorePosition(name, frame, point, x, y)
  local saved = ForeverGearDB and ForeverGearDB.frames[name]
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
  ForeverGearDB.frames = {}
  for _, fn in ipairs(resetters) do
    pcall(fn)
  end
end

---------------------------------------------------------------------------------------------------
-- Start

local logins = {}

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
  if name ~= "ForeverGear" then
    return
  end
  self:UnregisterEvent("ADDON_LOADED")
  if type(ForeverGearDB) ~= "table" then
    ForeverGearDB = {}
  end
  local db = ForeverGearDB
  db.version = DATA_VERSION
  local options = tableAt(db, "options")
  tableAt(db, "frames")
  local roles = tableAt(db, "roles")
  local personal = tableAt(db, "personal")
  for key, default in pairs(ns.DEFAULTS) do
    if type(options[key]) ~= type(default) then
      options[key] = default
    end
  end
  for class, role in pairs(roles) do
    if type(class) ~= "string" or type(role) ~= "string" then
      roles[class] = nil
    end
  end
  for itemID, slot in pairs(personal) do
    -- A slot key that the addon does not know would break the order of the own list.
    if type(itemID) ~= "number" or type(slot) ~= "string" or (slot ~= "" and not ns.SLOT_BY_KEY[slot]) then
      personal[itemID] = nil
    end
  end
end)
