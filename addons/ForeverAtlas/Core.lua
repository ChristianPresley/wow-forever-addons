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

-- Sets a texture from { atlas = , texture = , color = { r, g, b } }. The texture is the fallback for a missing atlas.
function ns.SetIcon(texture, look)
  texture:SetTexCoord(0, 1, 0, 1)
  if look.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(look.atlas) then
    texture:SetAtlas(look.atlas)
  else
    texture:SetTexture(look.texture)
  end
  local color = look.color
  texture:SetVertexColor(color and color[1] or 1, color and color[2] or 1, color and color[3] or 1, 1)
end

-- Options. Each key is a boolean in ForeverAtlasDB.options.
ns.defaults = {
  coords = true,
  announce = false,
  hud = true,
  hudArea = true,
  hudLock = false,
  pins = true,
  notes = true,
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
  value = value and true or false
  ForeverAtlasDB.options[key] = value
  for _, fn in ipairs(watchers) do
    local ok, err = pcall(fn, key, value)
    if not ok then
      geterrorhandler()(err)
    end
  end
end

-- Makes a frame movable with the left button and keeps its place in ForeverAtlasDB.frames[key].
function ns.MakeMovable(frame, key, point, x, y)
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
    if type(options[key]) ~= "boolean" then
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
