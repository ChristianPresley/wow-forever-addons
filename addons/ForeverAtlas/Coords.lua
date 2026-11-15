local _, ns = ...

-- Coordinate read-out in the bottom-left corner of the world map.

local INTERVAL = 0.1

local function cursorPosition()
  local container = WorldMapFrame.ScrollContainer
  if not container or not container:IsMouseOver() or not WorldMapFrame.GetNormalizedCursorPosition then
    return nil
  end
  local x, y = WorldMapFrame:GetNormalizedCursorPosition()
  if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then
    return nil
  end
  return x * 100, y * 100
end

local function format(label, x, y)
  if not x then
    return label .. ": --"
  end
  return string.format("%s: %.1f, %.1f", label, x, y)
end

local function build()
  local frame = CreateFrame("Frame", "ForeverAtlasCoords", WorldMapFrame)
  frame:SetSize(280, 18)
  frame:SetPoint("BOTTOMLEFT", WorldMapFrame.ScrollContainer or WorldMapFrame, "BOTTOMLEFT", 10, 8)
  frame:SetFrameLevel(math.min(9000, WorldMapFrame:GetFrameLevel() + 5000))

  local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("LEFT")
  text:SetShadowOffset(1, -1)

  local elapsed = INTERVAL
  frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < INTERVAL then
      return
    end
    elapsed = 0
    if not ForeverAtlasDB or not ForeverAtlasDB.options.coords then
      text:SetText("")
      return
    end
    local px, py = ns.PlayerPosition(WorldMapFrame:GetMapID())
    local cx, cy = cursorPosition()
    text:SetText(format("Player", px, py) .. "    " .. format("Cursor", cx, cy))
  end)
end

if WorldMapFrame then
  build()
else
  local waiter = CreateFrame("Frame")
  waiter:RegisterEvent("ADDON_LOADED")
  waiter:SetScript("OnEvent", function(self)
    if WorldMapFrame then
      self:UnregisterEvent("ADDON_LOADED")
      build()
    end
  end)
end
