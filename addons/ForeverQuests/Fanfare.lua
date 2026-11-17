local _, ns = ...

-- The moment a quest is ready to turn in: a banner in the middle of the screen with "QUEST
-- COMPLETE" and the name of the quest. It pops in larger than it stays, shines, and fades out
-- after a few seconds. A click on it shows where to turn the quest in: the quest log opens on
-- the map with this quest, and the game's own arrow points to the place.
--
-- Several quests that are ready at the same time show one after the other.

local HOLD_SECONDS = 5 -- how long a banner stays
local POP_SECONDS = 0.3 -- the banner starts larger and settles
local FADE_SECONDS = 0.8

local banner
local queue = {}
local current

local function nextBanner()
  current = table.remove(queue, 1)
  if not current then
    banner:Hide()
    return
  end
  banner.title:SetText(current.title)
  banner.startTime = GetTime()
  banner:SetAlpha(1)
  banner:SetScale(1 + 0.5)
  banner:Show()
end

local function onUpdate(self)
  local age = GetTime() - self.startTime
  if age >= HOLD_SECONDS then
    nextBanner()
    return
  end
  -- From one and a half times the size down to the size it stays at.
  local settle = math.max(0, 1 - age / POP_SECONDS)
  self:SetScale(1 + 0.5 * settle)
  local left = HOLD_SECONDS - age
  self:SetAlpha(math.min(1, left / FADE_SECONDS))
  -- The shine goes from the left to the right once, and the glow pulses.
  local sweep = math.min(1, age / 1.2)
  self.shine:ClearAllPoints()
  self.shine:SetPoint("CENTER", self, "LEFT", sweep * self:GetWidth(), 0)
  self.shine:SetAlpha(sweep < 1 and 0.6 or 0)
  self.glow:SetAlpha(0.25 + 0.2 * math.abs(math.sin(age * 3)))
end

-- Shows where to turn a quest in: the quest log on the map opens with the quest, and the quest
-- gets the arrow of the game (the tracked quest).
function ns.ShowTurnIn(questID)
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
    pcall(C_SuperTrack.SetSuperTrackedQuestID, questID)
  end
  if type(QuestMapFrame_OpenToQuestDetails) == "function" then
    -- The game does not let an addon open a window in a fight: it would show an error and
    -- still change the chosen quest of the log. The arrow of the game is set all the same.
    if InCombatLockdown and InCombatLockdown() then
      ns.Print("the quest log cannot open in a fight. The arrow of the game points to the quest; click again after the fight.")
      return false
    end
    return (pcall(QuestMapFrame_OpenToQuestDetails, questID))
  end
  return false
end

local function create()
  banner = CreateFrame("Button", "ForeverQuestsFanfare", UIParent)
  banner:SetFrameStrata("HIGH")
  banner:SetSize(420, 86)
  banner:SetPoint("TOP", UIParent, "TOP", 0, -170)

  local back = banner:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  back:SetColorTexture(0, 0, 0, 0.55)
  banner.glow = banner:CreateTexture(nil, "BORDER")
  banner.glow:SetAllPoints()
  banner.glow:SetColorTexture(1, 0.78, 0.12, 1)
  banner.glow:SetBlendMode("ADD")
  for _, point in ipairs({ "TOP", "BOTTOM" }) do
    local edge = banner:CreateTexture(nil, "ARTWORK")
    edge:SetColorTexture(1, 0.9, 0.5, 1)
    edge:SetHeight(2)
    edge:SetPoint(point .. "LEFT")
    edge:SetPoint(point .. "RIGHT")
  end
  banner.shine = banner:CreateTexture(nil, "OVERLAY")
  banner.shine:SetSize(60, 86)
  banner.shine:SetColorTexture(1, 1, 1, 1)
  banner.shine:SetBlendMode("ADD")

  banner.head = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  banner.head:SetPoint("TOP", 0, -10)
  banner.head:SetText("QUEST COMPLETE")
  banner.head:SetTextColor(1, 0.85, 0.2)
  banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  banner.title:SetPoint("TOP", banner.head, "BOTTOM", 0, -6)
  banner.title:SetWidth(400)
  banner.title:SetWordWrap(false)
  banner.hint = banner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  banner.hint:SetPoint("BOTTOM", 0, 6)
  banner.hint:SetText("Click to see where to turn it in")

  banner:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  banner:SetScript("OnClick", function(_, button)
    local questID = current and current.questID
    if button == "LeftButton" and questID then
      ns.ShowTurnIn(questID)
    end
    nextBanner() -- a click of either button takes the banner away
  end)
  banner:SetScript("OnUpdate", onUpdate)
  banner:Hide()
end

-- Shows the banner for a quest that is ready to turn in.
function ns.ShowQuestComplete(questID, title)
  if not ns.GetOption("completeFanfare") then
    return false
  end
  if type(title) ~= "string" or ns.IsSecret(title) or title == "" then
    title = "Quest"
  end
  if not banner then
    if not pcall(create) then
      banner = nil
      return false
    end
  end
  queue[#queue + 1] = { questID = questID, title = title }
  if not current then
    nextBanner()
  end
  return true
end

-- The quest of the banner on the screen now, or nil.
function ns.FanfareQuest()
  return banner and banner:IsShown() and current and current.questID or nil
end

ns.OnOptionChanged(function(key, value)
  if key == "completeFanfare" and not value and banner then
    queue, current = {}, nil
    banner:Hide()
  end
end)
