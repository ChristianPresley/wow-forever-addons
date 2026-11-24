local _, ns = ...

function ns.Print(msg)
  print("|cff7fb4caForever Atlas|r: " .. tostring(msg))
end

local function usable(value)
  return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end
ns.Usable = usable

-- Player position on a map as two numbers from 0 to 100, or nil where the game hides it (instances).
function ns.PlayerPosition(mapID)
  mapID = mapID or C_Map.GetBestMapForUnit("player")
  if not mapID then
    return nil
  end
  local ok, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
  if not ok or not position then
    return nil
  end
  local x, y = position:GetXY()
  if not usable(x) or not usable(y) then
    return nil
  end
  return x * 100, y * 100
end

function ns.MapName(mapID)
  local ok, info = pcall(C_Map.GetMapInfo, mapID)
  return ok and info and info.name or ("map " .. tostring(mapID))
end

-- Sets a texture from { atlas = , texture = , coords = { left, right, top, bottom }, color = { r, g, b },
-- fallbackColor = { r, g, b } }.
-- The texture is the fallback for a missing atlas; coords cut a part out of the texture file.
-- fallbackColor is the colour of the fallback only: an atlas with its own colours keeps them.
-- fallbackAtlas is a second atlas to try before the texture; it has the fallback colour too.
function ns.SetIcon(texture, look)
  texture:SetTexCoord(0, 1, 0, 1)
  local color = look.color
  local has = C_Texture and C_Texture.GetAtlasInfo
  if look.atlas and has and has(look.atlas) then
    texture:SetAtlas(look.atlas)
  else
    if look.fallbackAtlas and has and has(look.fallbackAtlas) then
      texture:SetAtlas(look.fallbackAtlas)
    else
      texture:SetTexture(look.texture)
      if look.coords then
        texture:SetTexCoord(look.coords[1], look.coords[2], look.coords[3], look.coords[4])
      end
    end
    color = look.fallbackColor or color
  end
  texture:SetVertexColor(color and color[1] or 1, color and color[2] or 1, color and color[3] or 1, 1)
end

-- Options, in ForeverAtlasDB.options. The type of the default is the type of the option.
ns.defaults = {
  coords = true,
  announce = false,
  hud = true,
  hudArea = true,
  hudLock = false,
  notes = true,
  mapKey = true, -- the key of the world map opens the Forever Atlas map
  arrow = true, -- the direction arrow of the newest waypoint
  arrivalYards = 5, -- a waypoint is reached, and removed, within this distance
}

-- Lowest and highest value of each number option.
ns.limits = {
  arrivalYards = { 2, 50 },
}

local watchers = {}

-- fn(key, value) runs after each change of an option.
function ns.OnOption(fn)
  watchers[#watchers + 1] = fn
end

function ns.GetOption(key)
  return ForeverAtlasDB and ForeverAtlasDB.options[key] or false
end

function ns.SetOption(key, value)
  local default = ns.defaults[key]
  if type(default) == "number" then
    local limit = ns.limits[key]
    value = math.floor((tonumber(value) or default) + 0.5)
    if limit then
      value = math.max(limit[1], math.min(limit[2], value))
    end
  else
    value = value and true or false
  end
  ForeverAtlasDB.options[key] = value
  for _, fn in ipairs(watchers) do
    local ok, err = pcall(fn, key, value)
    if not ok then
      geterrorhandler()(err)
    end
  end
end

local movable = {}

-- Puts every movable frame back where it was at first.
function ns.ResetFrames()
  wipe(ForeverAtlasDB.frames)
  for _, entry in ipairs(movable) do
    entry.frame:ClearAllPoints()
    entry.frame:SetPoint(entry.point, UIParent, entry.point, entry.x, entry.y)
  end
end

-- Makes a frame movable with the left button and keeps its place in ForeverAtlasDB.frames[key].
function ns.MakeMovable(frame, key, point, x, y)
  movable[#movable + 1] = { frame = frame, point = point, x = x, y = y }
  local saved = ForeverAtlasDB.frames[key]
  frame:ClearAllPoints()
  if type(saved) == "table" and type(saved[1]) == "string" and usable(saved[3]) and usable(saved[4]) then
    frame:SetPoint(saved[1], UIParent, saved[2] or saved[1], saved[3], saved[4])
  else
    frame:SetPoint(point, UIParent, point, x, y)
  end
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if not ns.GetOption("hudLock") then
      self:StartMoving()
    end
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local anchor, _, relative, offsetX, offsetY = self:GetPoint(1)
    if anchor then
      ForeverAtlasDB.frames[key] = { anchor, relative, offsetX, offsetY }
    end
  end)
end

local logins = {}

-- fn runs at PLAYER_LOGIN, when the saved variables are ready. An error stops that feature only.
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
  if name ~= "ForeverAtlas" then
    return
  end
  self:UnregisterEvent("ADDON_LOADED")
  if type(ForeverAtlasDB) ~= "table" then
    ForeverAtlasDB = {}
  end
  local options = tableAt(ForeverAtlasDB, "options")
  for key, value in pairs(ns.defaults) do
    if type(options[key]) ~= type(value) then
      options[key] = value
    end
  end
  tableAt(ForeverAtlasDB, "notes")
  tableAt(ForeverAtlasDB, "frames")
  if type(ForeverAtlasCharDB) ~= "table" then
    ForeverAtlasCharDB = {}
  end
  tableAt(ForeverAtlasCharDB, "zones")
  tableAt(ForeverAtlasCharDB, "waypoints")
end)
