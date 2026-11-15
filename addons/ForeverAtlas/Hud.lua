local _, ns = ...

-- Movable read-out of the player's coordinates, shown without the map.

local INTERVAL = 0.2

local hud

local function apply()
  if not hud then
    return
  end
  hud:SetShown(ns.GetOption("hud"))
  -- Locked: clicks go through to the world.
  hud:EnableMouse(not ns.GetOption("hudLock"))
  hud.area:SetShown(ns.GetOption("hudArea"))
  hud:SetHeight(ns.GetOption("hudArea") and 34 or 20)
end

local function update()
  local x, y = ns.PlayerPosition()
  hud.coords:SetText(x and string.format("%.1f, %.1f", x, y) or "--")
  if ns.GetOption("hudArea") then
    local area = GetSubZoneText()
    if not area or area == "" then
      area = GetRealZoneText() or ""
    end
    hud.area:SetText(area)
  end
end

ns.OnLogin(function()
  hud = CreateFrame("Frame", "ForeverAtlasHud", UIParent)
  hud:SetSize(130, 34)
  ns.MakeMovable(hud, "hud", "TOP", 0, -60)

  local background = hud:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0, 0, 0, 0.35)

  hud.coords = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  hud.coords:SetPoint("TOP", 0, -4)
  hud.area = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hud.area:SetPoint("TOP", hud.coords, "BOTTOM", 0, -2)
  hud.area:SetWidth(126)
  hud.area:SetWordWrap(false)

  local elapsed = INTERVAL
  hud:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < INTERVAL then
      return
    end
    elapsed = 0
    update()
  end)

  ns.OnOption(apply)
  apply()
end)
