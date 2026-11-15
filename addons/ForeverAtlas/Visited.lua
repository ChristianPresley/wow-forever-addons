local _, ns = ...

-- A pin on the world map for each visited area of the shown map (ForeverAtlasCharDB.zones).

local LOOK = { atlas = "WhiteCircle-RaidBlips", texture = "Interface\\Buttons\\WHITE8X8", color = { 0.5, 0.85, 1 } }

ns.AddPinProvider(function(mapID, add)
  if not ns.GetOption("pins") then
    return
  end
  for zone, areas in pairs(ForeverAtlasCharDB.zones) do
    if type(areas) == "table" then
      for area, entry in pairs(areas) do
        if type(entry) == "table" and entry.mapID == mapID and ns.Usable(entry.x) and ns.Usable(entry.y) then
          add(entry.x, entry.y, {
            look = LOOK,
            size = 9,
            tooltip = function(tooltip)
              tooltip:AddLine(area, 1, 1, 1)
              if area ~= zone then
                tooltip:AddLine(zone, 0.6, 0.6, 0.6)
              end
              if ns.Usable(entry.t) then
                tooltip:AddLine("First visit: " .. date("%Y-%m-%d", entry.t), 1, 0.82, 0)
              end
            end,
          })
        end
      end
    end
  end
end)

ns.OnOption(function(key)
  if key == "pins" then
    ns.RefreshPins()
  end
end)
