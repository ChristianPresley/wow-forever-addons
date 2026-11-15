local _, ns = ...

function ns.Print(msg)
  print("|cff7fb4caForever Atlas|r: " .. tostring(msg))
end

local function usable(value)
  return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

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

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name ~= "ForeverAtlas" then
    return
  end
  self:UnregisterEvent("ADDON_LOADED")
  ForeverAtlasDB = ForeverAtlasDB or {}
  ForeverAtlasDB.options = ForeverAtlasDB.options or {}
  local options = ForeverAtlasDB.options
  if options.coords == nil then
    options.coords = true
  end
  if options.announce == nil then
    options.announce = false
  end
  ForeverAtlasCharDB = ForeverAtlasCharDB or {}
  ForeverAtlasCharDB.zones = ForeverAtlasCharDB.zones or {}
end)
