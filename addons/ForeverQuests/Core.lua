local _, ns = ...

function ns.Print(msg)
  print("|cffe6c229Forever Quests|r: " .. tostring(msg))
end

-- An error inside Forever Quests: each different one is printed in chat once. It is not put on the
-- screen as a Lua error, so the game goes on as before. /fq status counts them.
local reported, errorCount, lastError = {}, 0, nil
function ns.Report(where, err)
  local text = where .. ": " .. tostring(err)
  errorCount = errorCount + 1
  lastError = text
  if not reported[text] then
    reported[text] = true
    ns.Print("error in " .. text)
  end
end

function ns.ErrorCount()
  return errorCount, lastError
end

-- A handler that reports its error, for the scripts of the event frames.
function ns.Safely(where, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      ns.Report(where, err)
    end
  end
end

-- Totals of this play session. The lifetime totals are in ForeverQuestsCharDB.
ns.session = { quests = 0, xp = 0, money = 0 }

-- Every option: the key in ForeverQuestsDB.options, the word after /fq, the name in chat messages,
-- and the label and the explanation on the options page.
ns.OPTIONS = {
  {
    key = "autoAccept", command = "accept", label = "automatic accept", default = false,
    text = "Accept quests automatically",
    hint = "Hold Shift while you talk to an NPC to skip it once. Repeatable quests are not accepted.",
  },
  {
    key = "autoTurnIn", command = "turnin", label = "automatic turn-in", default = false,
    text = "Turn in quests automatically",
    hint = "A quest with a choice of rewards is never completed for you.",
  },
  {
    key = "announce", command = "announce", label = "chat messages", default = true,
    text = "Chat messages",
    hint = "A message when an objective is done or a quest is ready to turn in.",
  },
  {
    key = "sound", command = "sound", label = "quest-ready sound", default = true,
    text = "Quest-ready sound",
    hint = "A sound when a quest is ready to turn in.",
  },
  {
    key = "partyProgress", command = "share", label = "party progress", default = true,
    text = "Party progress",
    hint = "Share objective progress with party members who also use Forever Quests.",
  },
  {
    key = "rewardHelper", command = "rewards", label = "reward sell prices", default = true,
    text = "Reward sell prices",
    hint = "The vendor sell price on each reward choice, with the most valuable one marked.",
  },
  {
    key = "popProgress", command = "pop", label = "progressed quest first in the quest log", default = true,
    text = "Quest log: progressed quest first, with a glow",
    hint = "A quest that makes progress goes to the top of its zone in the quest log and glows for a few seconds.",
  },
  {
    key = "sortAlpha", command = "sortname", label = "quests of each zone by name", default = false,
    text = "Quest log: sort each zone by name",
    hint = "The quests of each zone in alphabetical order. With the option above also on, progressed quests are still first.",
  },
  {
    key = "zoneLog", command = "zonelog", label = "current zone only in the quest log", default = false,
    text = "Quest log: current zone only",
    hint = "Hide the quests of other zones in the quest log. Also in the settings menu of the quest log.",
  },
  {
    key = "hideGrey", command = "grey", label = "grey quests hidden in the quest log", default = false,
    text = "Quest log: hide grey quests",
    hint = "Hide the quests that the game shows in grey, far below your level. A grey quest that is ready to turn in stays. Also in the settings menu of the quest log.",
  },
  {
    key = "zoneTracker", command = "zonetracker", label = "current zone only in the tracker", default = false,
    text = "Tracker: current zone only",
    hint = "Track the quests of your zone and untrack the others. Your own tracking comes back when you turn this off.",
  },
  {
    key = "trackerLook", command = "tracker", label = "the look and order of the quest log on the tracker", default = true,
    text = "Tracker: the look and order of the quest log",
    hint = "On the quest tracker at the right of the screen: a ready quest is a green row, a quest that makes progress goes to the top and glows, and each quest has the compass symbol of Forever Compass.",
  },
  {
    key = "completeFanfare", command = "fanfare", label = "quest complete banner", default = true,
    text = "Quest complete: banner and mark",
    hint = "A banner on the screen when a quest is ready to turn in; click it to see where. In the quest log the quest goes to the top of its zone with a COMPLETED mark.",
  },
  {
    key = "questChain", command = "chain", label = "the quest chain beside the quest details", default = true,
    text = "Quest log: the chain of the quest",
    hint = "Beside the details of a quest that is part of a chain: the name of the chain and its steps, done, this one, or still to come.",
  },
  {
    key = "abandonWarning", command = "abandon", label = "progress warning when you abandon a quest", default = true,
    text = "Abandon: say what progress is lost",
    hint = "When you abandon a quest, a chat message lists the objectives you have made progress on, and says so if the quest is ready to turn in.",
  },
  {
    key = "questItems", command = "items", label = "quest items beside the quest details", default = true,
    text = "Quest log: items of the quest",
    hint = "Beside the details of a quest: the item to use, the items to collect, the rewards and the choice of rewards, in your bags or not.",
  },
}

local listeners = {}

-- The function is called with the key and the new value after an option changes.
function ns.OnOptionChanged(listener)
  listeners[#listeners + 1] = listener
end

function ns.GetOption(key)
  return ForeverQuestsDB and ForeverQuestsDB.options and ForeverQuestsDB.options[key] and true or false
end

function ns.SetOption(key, value)
  if not (ForeverQuestsDB and ForeverQuestsDB.options) then
    return
  end
  value = value and true or false
  ForeverQuestsDB.options[key] = value
  for _, listener in ipairs(listeners) do
    listener(key, value)
  end
end

-- True for a value that an addon can show but not calculate with (see docs/addon-development.md).
function ns.IsSecret(value)
  return issecretvalue ~= nil and issecretvalue(value) or false
end

function ns.Money(copper)
  if GetMoneyString then
    return GetMoneyString(copper, true)
  end
  return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name ~= "ForeverQuests" then
    return
  end
  self:UnregisterEvent("ADDON_LOADED")
  ForeverQuestsDB = ForeverQuestsDB or {}
  ForeverQuestsDB.options = ForeverQuestsDB.options or {}
  -- An option that the saved data does not have yet gets its default.
  for _, option in ipairs(ns.OPTIONS) do
    if ForeverQuestsDB.options[option.key] == nil then
      ForeverQuestsDB.options[option.key] = option.default
    end
  end
  ForeverQuestsCharDB = ForeverQuestsCharDB or {}
  local totals = ForeverQuestsCharDB
  totals.quests = totals.quests or 0
  totals.xp = totals.xp or 0
  totals.money = totals.money or 0
end)
