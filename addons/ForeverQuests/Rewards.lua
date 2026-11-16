local _, ns = ...

-- On the reward screen of a quest with a choice of items: the vendor sell price on each choice and
-- a gold frame around the one that sells for the most. Nothing is chosen for the player.

local SELL_PRICE_INDEX = 11
local EDGE = 2

local active = false -- between QUEST_COMPLETE and the end of the dialog
local pending = false -- a price is not known yet
local queued = false
local overlays = {} -- reward button -> our frame on it

local function overlayFor(button)
  local overlay = overlays[button]
  if overlay then
    return overlay
  end
  overlay = CreateFrame("Frame", nil, button)
  overlay:SetAllPoints(button)
  overlay.price = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  overlay.price:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -5, 3)
  overlay.edges = {}
  for i, points in ipairs({
    { "TOPLEFT", "TOPRIGHT" },
    { "BOTTOMLEFT", "BOTTOMRIGHT" },
    { "TOPLEFT", "BOTTOMLEFT" },
    { "TOPRIGHT", "BOTTOMRIGHT" },
  }) do
    local edge = overlay:CreateTexture(nil, "OVERLAY")
    edge:SetColorTexture(1, 0.82, 0, 0.9)
    edge:SetPoint(points[1], overlay, points[1], 0, 0)
    edge:SetPoint(points[2], overlay, points[2], 0, 0)
    if i <= 2 then
      edge:SetHeight(EDGE)
    else
      edge:SetWidth(EDGE)
    end
    overlay.edges[i] = edge
  end
  overlays[button] = overlay
  return overlay
end

local function hideAll()
  for _, overlay in pairs(overlays) do
    overlay:Hide()
  end
end

-- The sell price of the whole stack of a choice in copper, or nil while the item is not loaded.
local function valueOf(index)
  local getItemInfo = C_Item.GetItemInfo
  local link = GetQuestItemLink and GetQuestItemLink("choice", index)
  if not link or not getItemInfo then
    return nil
  end
  -- For an item that is not loaded this asks the server; GET_ITEM_INFO_RECEIVED follows.
  local price = select(SELL_PRICE_INDEX, getItemInfo(link))
  if ns.IsSecret(price) or type(price) ~= "number" then
    return nil
  end
  local count = GetQuestItemInfo and select(3, GetQuestItemInfo("choice", index))
  if ns.IsSecret(count) or type(count) ~= "number" or count < 1 then
    count = 1
  end
  return price * count
end

local function refresh()
  queued = false
  pending = false
  hideAll()
  if not (active and ns.GetOption("rewardHelper")) then
    return
  end
  local frame = QuestInfoRewardsFrame
  local buttons = frame and frame.RewardButtons
  if type(buttons) ~= "table" or not frame:IsVisible() then
    return
  end
  local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
  if choices < 2 then
    return
  end
  local shown = {}
  local best, lowest = 0, nil
  for _, button in ipairs(buttons) do
    if button:IsShown() and button.type == "choice" and button.objectType == "item" then
      local index = button:GetID()
      if index >= 1 and index <= choices then
        local value = valueOf(index)
        if value then
          best = math.max(best, value)
          lowest = lowest and math.min(lowest, value) or value
        else
          pending = true
        end
        shown[#shown + 1] = { overlay = overlayFor(button), value = value }
      end
    end
  end
  for _, choice in ipairs(shown) do
    local overlay, value = choice.overlay, choice.value
    -- Marked only when all prices are known and the choices do not all sell for the same.
    local isBest = not pending and value == best and best > 0 and lowest < best
    if not value then
      overlay.price:SetText("...")
    elseif value == 0 then
      overlay.price:SetText("no sell price")
    else
      overlay.price:SetText(ns.Money(value))
    end
    if isBest then
      overlay.price:SetTextColor(1, 0.82, 0)
    else
      overlay.price:SetTextColor(1, 1, 1)
    end
    for _, edge in ipairs(overlay.edges) do
      edge:SetShown(isBest)
    end
    overlay:Show()
  end
end

local function schedule()
  if not queued then
    queued = true
    -- After the game has laid out its reward buttons for the same event.
    C_Timer.After(0.05, function()
      local ok = pcall(refresh)
      if not ok then
        queued = false
        pcall(hideAll)
      end
    end)
  end
end

ns.OnOptionChanged(function(key)
  if key == "rewardHelper" then
    schedule()
  end
end)

local frame = CreateFrame("Frame")
for _, event in ipairs({
  "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_GREETING",
  "QUEST_ITEM_UPDATE", "GET_ITEM_INFO_RECEIVED",
}) do
  pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event)
  if event == "QUEST_COMPLETE" then
    active = true
    schedule()
  elseif event == "QUEST_ITEM_UPDATE" then
    if active then
      schedule()
    end
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if active and pending then
      schedule()
    end
  else
    active = false
    schedule()
  end
end)

-- The game fills the reward buttons again in QuestInfo_Display.
if type(QuestInfo_Display) == "function" then
  hooksecurefunc("QuestInfo_Display", function()
    if active then
      schedule()
    end
  end)
end
