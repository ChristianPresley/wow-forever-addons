local _, ns = ...

function ns.Print(msg)
  print("|cffe6c229Forever Quests|r: " .. tostring(msg))
end

-- Totals of this play session. The lifetime totals are in ForeverQuestsCharDB.
ns.session = { quests = 0, xp = 0, money = 0 }

local DEFAULTS = {
  autoAccept = false,
  autoTurnIn = false,
  announce = true,
  sound = true,
}

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name ~= "ForeverQuests" then
    return
  end
  self:UnregisterEvent("ADDON_LOADED")
  ForeverQuestsDB = ForeverQuestsDB or {}
  ForeverQuestsDB.options = ForeverQuestsDB.options or {}
  for key, value in pairs(DEFAULTS) do
    if ForeverQuestsDB.options[key] == nil then
      ForeverQuestsDB.options[key] = value
    end
  end
  ForeverQuestsCharDB = ForeverQuestsCharDB or {}
  local totals = ForeverQuestsCharDB
  totals.quests = totals.quests or 0
  totals.xp = totals.xp or 0
  totals.money = totals.money or 0
end)
