local _, ns = ...

-- The items of a quest, beside the details of the quest in the quest log.
--
-- The game shows the item of a quest only while it is in the bags. This list has every item
-- that the game names for the quest, in the bags or not:
--   Use      the item that the quest gives the player to use
--   Collect  an item of an objective, with the progress
--   Reward   an item that the quest gives at the end
--   Choice   an item of the choice of rewards
--
-- The panel is a frame of this addon. It hangs on the right edge of the quest log and is a
-- child of the details of the quest, so it shows and hides with them. No frame of the game is
-- changed.
--
-- For an objective the game gives its text ("Gnoll Paw: 3/8") and no item ID. The name comes from
-- the text; the icon is there once the game has loaded the item.

local ROW = 22
local WIDTH = 230
local PAD = 8
local UNKNOWN_ICON = 134400 -- the question mark

local LABELS = { use = "Use", collect = "Collect", reward = "Reward", choice = "Choice" }

local panel
local rows = {}
local shownQuest

-- The name of the item of an objective, from its text: "3/8 Gnoll Paw" or "Gnoll Paw: 3/8".
local function nameFromObjective(text)
  if type(text) ~= "string" or ns.IsSecret(text) then
    return nil
  end
  local name = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  return name ~= "" and name or nil
end

-- How many of an item are in the bags. `item` is an item ID, a link or a name.
local function inBags(item)
  if not item then
    return 0
  end
  local ok, count = pcall(C_Item.GetItemCount, item)
  return ok and type(count) == "number" and count or 0
end

-- The items of a quest of the quest log:
-- { { kind, name, icon, link, itemID, quantity, have, need, done }, ... }
function ns.QuestItems(questID)
  local items = {}
  if type(questID) ~= "number" then
    return items
  end

  -- The item to use.
  local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
  if logIndex and type(GetQuestLogSpecialItemInfo) == "function" then
    local ok, link, icon = pcall(GetQuestLogSpecialItemInfo, logIndex)
    if ok and type(link) == "string" then
      local name = link:match("%[(.-)%]") or "Quest item"
      items[#items + 1] = { kind = "use", name = name, icon = icon, link = link, have = inBags(link) }
    end
  end

  -- The items of the objectives.
  local okObjectives, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
  if okObjectives and type(objectives) == "table" then
    for _, objective in ipairs(objectives) do
      if objective.type == "item" then
        local name = nameFromObjective(objective.text)
        if name then
          local itemID, icon
          local okInfo, id, _, _, _, texture = pcall(C_Item.GetItemInfoInstant, name)
          if okInfo and id then
            itemID, icon = id, texture
          end
          items[#items + 1] = {
            kind = "collect", name = name, icon = icon, itemID = itemID,
            have = objective.numFulfilled, need = objective.numRequired, done = objective.finished and true or false,
          }
        end
      end
    end
  end

  -- The rewards and the choice of rewards.
  local function rewards(kind, countOf, infoOf)
    if type(countOf) ~= "function" or type(infoOf) ~= "function" then
      return
    end
    local okCount, count = pcall(countOf, questID)
    for index = 1, okCount and type(count) == "number" and count or 0 do
      local ok, name, icon, quantity, _, _, itemID = pcall(infoOf, index, questID)
      if ok and type(name) == "string" and name ~= "" then
        items[#items + 1] = { kind = kind, name = name, icon = icon, itemID = itemID, quantity = quantity, have = inBags(itemID) }
      end
    end
  end
  rewards("reward", GetNumQuestLogRewards, GetQuestLogRewardInfo)
  rewards("choice", GetNumQuestLogChoices, GetQuestLogChoiceInfo)
  return items
end

local function describe(item)
  if item.kind == "collect" then
    if type(item.have) == "number" and type(item.need) == "number" then
      return string.format("%d/%d", item.have, item.need), item.done
    end
    return "", item.done
  elseif item.kind == "use" then
    return item.have > 0 and "in your bags" or "not in your bags", item.have > 0
  end
  local text = type(item.quantity) == "number" and item.quantity > 1 and ("x" .. item.quantity) or ""
  return text, false
end

local function rowAt(index)
  local row = rows[index]
  if row then
    return row
  end
  row = CreateFrame("Frame", nil, panel)
  row:SetSize(WIDTH - PAD * 2, ROW)
  row:SetPoint("TOPLEFT", PAD, -26 - (index - 1) * ROW)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ROW - 4, ROW - 4)
  row.icon:SetPoint("LEFT")
  row.kind = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  row.kind:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
  row.kind:SetWidth(42)
  row.kind:SetJustifyH("LEFT")
  row.state = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.state:SetPoint("RIGHT")
  row.state:SetJustifyH("RIGHT")
  row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row.kind, "RIGHT", 2, 0)
  row.name:SetPoint("RIGHT", row.state, "LEFT", -4, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    local item = self.item
    if not item then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if item.link then
      GameTooltip:SetHyperlink(item.link)
    elseif item.itemID then
      GameTooltip:SetItemByID(item.itemID)
    else
      GameTooltip:SetText(item.name, 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  rows[index] = row
  return row
end

local function create()
  local details = QuestMapFrame and QuestMapFrame.DetailsFrame
  if not details then
    return false
  end
  panel = CreateFrame("Frame", "ForeverQuestsItems", details)
  panel:SetFrameStrata("HIGH")
  panel:SetPoint("TOPLEFT", QuestMapFrame, "TOPRIGHT", 6, -24)
  panel:SetWidth(WIDTH)
  local background = panel:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.04, 0.04, 0.05, 0.9)
  panel.title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  panel.title:SetPoint("TOPLEFT", PAD, -7)
  panel.title:SetText("Quest items")
  panel:Hide()
  return true
end

-- Shows the items of a quest beside its details, or hides the panel for a quest without items.
local function show(questID)
  shownQuest = questID
  if not ns.GetOption("questItems") then
    if panel then
      panel:Hide()
    end
    return
  end
  local items = ns.QuestItems(questID)
  if #items == 0 then
    if panel then
      panel:Hide()
    end
    return
  end
  if not panel and not create() then
    return
  end
  for index, item in ipairs(items) do
    local row = rowAt(index)
    local state, good = describe(item)
    row.item = item
    row.icon:SetTexture(item.icon or UNKNOWN_ICON)
    row.kind:SetText(LABELS[item.kind])
    row.name:SetText(item.name)
    row.state:SetText(state)
    if good then
      row.state:SetTextColor(0.3, 1, 0.3)
    else
      row.state:SetTextColor(1, 1, 1)
    end
    row:Show()
  end
  for index = #items + 1, #rows do
    rows[index]:Hide()
  end
  panel:SetHeight(26 + #items * ROW + PAD)
  panel:Show()
end

-- The rows of the panel as texts, for the tests: "Use Fishing Net not in your bags".
function ns.QuestItemLines(questID)
  local lines = {}
  for _, item in ipairs(ns.QuestItems(questID)) do
    local state = describe(item)
    lines[#lines + 1] = (LABELS[item.kind] .. " " .. item.name .. " " .. state):gsub("%s+$", "")
  end
  return lines
end

local function refresh()
  if shownQuest and panel and panel:IsVisible() then
    pcall(show, shownQuest)
  end
end

ns.OnOptionChanged(function(key)
  if key == "questItems" and shownQuest then
    pcall(show, shownQuest)
  end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    -- The game shows the details of a quest with this function: the panel follows it.
    if type(QuestMapFrame_ShowQuestDetails) == "function" then
      hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
        pcall(show, questID)
      end)
    end
    for _, name in ipairs({ "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "GET_ITEM_INFO_RECEIVED" }) do
      pcall(self.RegisterEvent, self, name)
    end
    return
  end
  refresh()
end)
