local _, ns = ...

-- The minimap of the game, changed only where the player turns an option on: a square shape, a
-- larger size, and the coordinates under it. With every option off nothing of the minimap is
-- touched. Another addon that already shapes the minimap (SexyMap) keeps it: then these
-- options do nothing.
--
-- A square minimap tells other addons so through the global GetMinimapShape, as the minimap
-- addons do, so that their buttons sit on the corners. It is set only when no addon has it.

ns.defaults.minimapSquare = false
ns.defaults.minimapScale = 100
ns.defaults.minimapCoords = false
ns.limits.minimapScale = { 80, 160 }

local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
-- The round mask of the minimap of this client, which this addon puts back.
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local COORDS_INTERVAL = 0.2
local OTHER_ADDONS = { "SexyMap" }

local changed = { mask = false, scale = false, shape = false } -- what this addon changed, to give it back
local border, coords
local ownShape -- the GetMinimapShape of this addon, when it set the global

local function loaded(name)
  local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
  local ok, yes = pcall(isLoaded or error, name)
  return ok and yes and true or false
end

-- The name of an addon that shapes the minimap, or nil.
function ns.MinimapOwner()
  for _, name in ipairs(OTHER_ADDONS) do
    if loaded(name) then
      return name
    end
  end
  return nil
end

local function setShape(square)
  if not (Minimap and Minimap.SetMaskTexture) then
    return
  end
  if square then
    Minimap:SetMaskTexture(SQUARE_MASK)
    changed.mask = true
    if not border then
      border = CreateFrame("Frame", nil, Minimap)
      border:SetPoint("TOPLEFT", -2, 2)
      border:SetPoint("BOTTOMRIGHT", 2, -2)
      border:SetFrameLevel(math.max(0, Minimap:GetFrameLevel() - 1))
      local fill = border:CreateTexture(nil, "BACKGROUND")
      fill:SetAllPoints()
      fill:SetColorTexture(0, 0, 0, 0.8)
    end
    border:Show()
    if GetMinimapShape == nil or GetMinimapShape == ownShape then
      ownShape = ownShape or function()
        return "SQUARE"
      end
      GetMinimapShape = ownShape
      changed.shape = true
    end
  elseif changed.mask then
    Minimap:SetMaskTexture(ROUND_MASK)
    changed.mask = false
    if border then
      border:Hide()
    end
    if changed.shape and GetMinimapShape == ownShape then
      GetMinimapShape = nil
      changed.shape = false
    end
  end
end

local function setScale(percent)
  -- The frame that holds the minimap and its buttons.
  local cluster = Minimap and (Minimap:GetParent() ~= UIParent and Minimap:GetParent() or Minimap)
  if not cluster then
    return
  end
  if percent ~= 100 then
    cluster:SetScale(percent / 100)
    changed.scale = true
  elseif changed.scale then
    cluster:SetScale(1)
    changed.scale = false
  end
end

local function updateCoords()
  local x, y = ns.PlayerPosition()
  coords.text:SetText(x and string.format("%.1f, %.1f", x, y) or "")
end

local function setCoords(on)
  if not Minimap then
    return
  end
  if on and not coords then
    coords = CreateFrame("Frame", nil, Minimap)
    coords:SetSize(80, 16)
    coords:SetPoint("TOP", Minimap, "BOTTOM", 0, -2)
    coords:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    coords.text = coords:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    coords.text:SetAllPoints()
    local since = 0
    coords:SetScript("OnUpdate", function(_, elapsed)
      since = since + elapsed
      if since >= COORDS_INTERVAL then
        since = 0
        updateCoords()
      end
    end)
  end
  if coords then
    coords:SetShown(on)
    if on then
      updateCoords()
    end
  end
end

-- Puts the minimap as the options say. Returns false when another addon has the minimap.
function ns.ApplyMinimap()
  if ns.MinimapOwner() then
    return false
  end
  setShape(ns.GetOption("minimapSquare"))
  local scale = ns.GetOption("minimapScale")
  setScale(ns.Usable(scale) and scale or 100)
  setCoords(ns.GetOption("minimapCoords"))
  return true
end

-- What this addon does to the minimap now, for the tests and /fatlas status.
function ns.MinimapState()
  return {
    owner = ns.MinimapOwner(),
    square = changed.mask,
    scale = changed.scale,
    shape = changed.shape,
    coords = coords ~= nil and coords:IsShown() and coords.text:GetText() or nil,
  }
end

ns.OnOption(function(key)
  if key == "minimapSquare" or key == "minimapScale" or key == "minimapCoords" then
    ns.ApplyMinimap()
  end
end)

ns.OnLogin(function()
  ns.ApplyMinimap()
end)
