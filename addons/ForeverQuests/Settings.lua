local _, ns = ...

-- The "Forever Quests" page in the Options window of the game. Every option of the addon is here.

local SECTIONS = {
  { "Automation", { "autoAccept", "autoTurnIn" } },
  { "Alerts", { "announce", "sound" } },
  { "Quest log and tracker", { "zoneLog", "zoneTracker" } },
  { "Party and rewards", { "partyProgress", "rewardHelper" } },
}

local page

local function build()
  local byKey = {}
  for _, option in ipairs(ns.OPTIONS) do
    byKey[option.key] = option
  end

  page = ns.NewSettingsPage("Forever Quests", "These settings are for all your characters. You can also change them with /fq.")
  local placed = {}
  local function check(option)
    placed[option.key] = true
    page:Check({
      label = option.text,
      hint = option.hint,
      get = function()
        return ns.GetOption(option.key)
      end,
      set = function(value)
        ns.SetOption(option.key, value)
      end,
    })
  end
  for _, section in ipairs(SECTIONS) do
    page:Header(section[1])
    for _, key in ipairs(section[2]) do
      if byKey[key] then
        check(byKey[key])
      end
    end
  end
  -- An option that no section names still gets a checkbox.
  local other = false
  for _, option in ipairs(ns.OPTIONS) do
    if not placed[option.key] then
      if not other then
        page:Header("Other")
        other = true
      end
      check(option)
    end
  end

  page:Header("Quest turn-ins")
  page:Info(function()
    local session, total = ns.session, ForeverQuestsCharDB
    return string.format(
      "This session: %d quests, %d experience, %s.   This character: %d quests, %d experience, %s.",
      session.quests, session.xp, ns.Money(session.money), total.quests, total.xp, ns.Money(total.money)
    )
  end)
  page:Buttons({
    {
      label = "Reset the totals",
      hint = "Sets the quest, experience and money totals of this character back to zero.",
      confirm = "Set the quest turn-in totals of this character back to zero?",
      click = function()
        for _, totals in ipairs({ ns.session, ForeverQuestsCharDB }) do
          totals.quests, totals.xp, totals.money = 0, 0, 0
        end
      end,
    },
  })
end

-- /fq options
function ns.OpenOptions()
  if not (page and page:Open()) then
    ns.Print("the options page cannot open now. Type /fq for the settings.")
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  if pcall(build) and page:Register() then
    ns.OnOptionChanged(function()
      page:Refresh()
    end)
  else
    page = nil
  end
end)
