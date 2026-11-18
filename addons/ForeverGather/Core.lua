local _, ns = ...

-- Saved data, in ForeverGatherDB (for all characters):
--   version = 1
--   options = { herb, ore, fish, treasure, worldMap, minimap, hideTrivial, minSkill, size }
--   nodes   = { [mapID] = { { kind = s, name = s, x = n, y = n, count = n }, ... } }   x, y from 0 to 1
--   names   = { [name] = { kind = s, skill = n } }   skill: the lowest skill rank seen at a gather

local DATA_VERSION = 1

function ns.Print(msg)
  print("|cff6fc96fForever Gather|r: " .. tostring(msg))
end

-- True for a number that the addon can calculate with.
function ns.Usable(value)
  return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

-- True for a string that the addon can compare and keep.
function ns.PlainString(value)
  return type(value) == "string" and not (issecretvalue and issecretvalue(value)) and value ~= ""
end

-- The kinds of nodes: key, name, the skill line, the icon.
ns.KINDS = {
  { key = "herb", name = "Herbs", skill = "Herbalism", icon = "Interface\\Icons\\INV_Misc_Herb_07" },
  { key = "ore", name = "Ore", skill = "Mining", icon = "Interface\\Icons\\INV_Ore_Copper_01" },
  { key = "fish", name = "Fish", skill = "Fishing", icon = "Interface\\Icons\\INV_Misc_Fish_02" },
  { key = "treasure", name = "Treasure", icon = "Interface\\Icons\\INV_Box_01" },
}
ns.KIND = {}
for _, kind in ipairs(ns.KINDS) do
  ns.KIND[kind.key] = kind
end

ns.OPTION_DEFAULTS = {
  herb = true,
  ore = true,
  fish = true,
  treasure = true,
  worldMap = true,
  minimap = true,
  hideTrivial = false, -- hide nodes that the skill has outgrown (no more skill ups)
  minSkill = 0, -- hide nodes learned at a skill below this
  size = 14, -- pixels, of a pin on the minimap; world map pins are a little larger
}
ns.OPTION_LIMITS = {
  minSkill = { 0, 300 },
  size = { 8, 32 },
}

local listeners = {}
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
  local value = ForeverGatherDB and ForeverGatherDB.options[key]
  if value == nil then
    return ns.OPTION_DEFAULTS[key]
  end
  return value
end

-- Returns true when the key exists and the value was set.
function ns.SetOption(key, value)
  local default = ns.OPTION_DEFAULTS[key]
  if default == nil or not ForeverGatherDB then
    return false
  end
  if type(default) == "number" then
    local limit = ns.OPTION_LIMITS[key]
    value = math.floor((tonumber(value) or default) + 0.5)
    value = math.max(limit[1], math.min(limit[2], value))
  else
    value = value and true or false
  end
  ForeverGatherDB.options[key] = value
  ns.Changed()
  return true
end

local function validate()
  local db = ForeverGatherDB
  if type(db) ~= "table" or db.version ~= DATA_VERSION then
    db = { version = DATA_VERSION }
  end
  if type(db.options) ~= "table" then
    db.options = {}
  end
  for key, default in pairs(ns.OPTION_DEFAULTS) do
    if type(db.options[key]) ~= type(default) then
      db.options[key] = default
    end
  end
  if type(db.nodes) ~= "table" then
    db.nodes = {}
  end
  if type(db.names) ~= "table" then
    db.names = {}
  end
  ForeverGatherDB = db
end

-- The player's map and position on it, or nil where the game hides it (an instance).
function ns.PlayerPosition()
  local mapID = C_Map.GetBestMapForUnit("player")
  if not ns.Usable(mapID) then
    return nil
  end
  local position = C_Map.GetPlayerMapPosition(mapID, "player")
  if not position then
    return nil
  end
  local x, y = position.x, position.y
  if not ns.Usable(x) or not ns.Usable(y) or (x == 0 and y == 0) then
    return nil
  end
  return mapID, x, y
end

-- The player's rank in a skill line by its name, or nil.
function ns.SkillRank(skillName)
  if not skillName or not C_SkillInfo or not C_SkillInfo.GetNumSkillLines then
    return nil
  end
  local count = C_SkillInfo.GetNumSkillLines()
  if not ns.Usable(count) then
    return nil
  end
  for index = 1, count do
    local info = C_SkillInfo.GetSkillLineInfo(index)
    if info and info.name == skillName and ns.Usable(info.rank) then
      return info.rank
    end
  end
  return nil
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" and name == "ForeverGather" then
    validate()
    self:UnregisterEvent("ADDON_LOADED")
    ns.Changed()
  end
end)
