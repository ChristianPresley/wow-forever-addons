local _, ns = ...

-- The bag window: all bags of the character in one window, with a search box.
--
-- Each slot is an item button of the game (ContainerFrameItemButtonTemplate), so a click uses the
-- item, a drag moves it, and the tooltip, the cooldown and the quest mark are the game's own.
-- A button finds its bag through the ID of its parent frame, the same way as in the bag window of
-- the game. So there is one parent frame for each bag, and this file sets no bag field on a
-- button: a field set by an addon would make the game refuse to use the item in a fight.
--
-- With the option replaceBags, the bag key and the bag buttons open this window. The functions
-- of the game behind them stay the game's own: this file hooks them (hooksecurefunc) and keeps
-- the bag windows of the game out of sight. A function of an addon in the place of one of the
-- game makes the game refuse what only its own UI may do, such as buying a bank slot.
--
-- The Hearthstone has its own button at the top of the window and is not among the slots.

local BUTTON = 37
local GAP = 4
local PAD = 10
local TOP = 58 -- title and search box
local BOTTOM = 34 -- money and buttons
local HEADER = 18 -- a category name
local HEARTHSTONE = 6948 -- the item ID of the Hearthstone
local HEARTH_SCALE = 0.8 -- the size of its button at the top of the window
local BIND_QUEST = 4 -- the bind type of a quest item: its tooltip says "Quest Item"

-- The categories, in the order of the window. `classes` are item class numbers (Enum.ItemClass).
local CATEGORIES = {
  { key = "equipment", name = "Equipment", classes = { [2] = true, [4] = true } },
  { key = "consumables", name = "Consumables", classes = { [0] = true } },
  { key = "trade", name = "Trade goods", classes = { [3] = true, [5] = true, [7] = true, [8] = true, [9] = true, [16] = true, [19] = true } },
  { key = "quest", name = "Quest items", classes = { [12] = true } },
  { key = "other", name = "Other", classes = {} },
  { key = "junk", name = "Junk", classes = {} },
}

local window, grid
local bagParents = {} -- [bag] = frame with the bag number as its ID
local buttons = {} -- [bag][slot] = item button
local headers = {}
local search = ""
local refreshPending = false

---------------------------------------------------------------------------------------------------
-- Item buttons

local function buttonFor(bag, slot)
  local parent = bagParents[bag]
  if not parent then
    parent = CreateFrame("Frame", nil, grid)
    parent:SetID(bag)
    parent:SetAllPoints(grid)
    bagParents[bag] = parent
    buttons[bag] = {}
  end
  local button = buttons[bag][slot]
  if not button then
    button = CreateFrame("ItemButton", "ForeverBagsItem" .. bag .. "_" .. slot, parent, "ContainerFrameItemButtonTemplate")
    button:SetID(slot)
    buttons[bag][slot] = button
  end
  return button
end

-- Calls a method of the button if this client has it. A method that fails does not stop the rest.
local function call(button, method, ...)
  local fn = button[method]
  if type(fn) == "function" then
    pcall(fn, button, ...)
  end
end

local function callGlobal(name, ...)
  local fn = _G[name]
  if type(fn) == "function" then
    pcall(fn, ...)
  end
end

local function matchesSearch(info)
  if search == "" then
    return true
  end
  if not info then
    return false
  end
  local name = info.itemName
  return type(name) == "string" and name:lower():find(search, 1, true) ~= nil
end

-- Shows the item of the slot on its button, the same way as the bag window of the game.
local function updateButton(button, bag, slot, info)
  local texture = info and info.iconFileID
  local quality = info and info.quality
  callGlobal("ClearItemButtonOverlay", button)
  call(button, "SetHasItem", texture)
  call(button, "SetItemButtonTexture", texture)
  call(button, "SyncAppearanceWithHasItem")
  callGlobal("SetItemButtonQuality", button, quality, info and info.hyperlink, false, info and info.isBound)
  callGlobal("SetItemButtonCount", button, info and info.stackCount)
  callGlobal("SetItemButtonDesaturated", button, info and info.isLocked)
  call(button, "UpdateExtended")
  local okQuest, quest = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
  if okQuest and type(quest) == "table" then
    call(button, "UpdateQuestItem", quest.isQuestItem, quest.questID, quest.isActive)
  end
  call(button, "UpdateNewItem", quality)
  call(button, "UpdateJunkItem", quality, info and info.hasNoValue)
  call(button, "UpdateCooldown", texture)
  call(button, "SetReadable", info and info.isReadable)
  local matches = matchesSearch(info)
  if type(button.SetMatchesSearch) == "function" then
    pcall(button.SetMatchesSearch, button, matches)
  else
    button:SetAlpha(matches and 1 or 0.25)
  end
end

---------------------------------------------------------------------------------------------------
-- Layout

-- The items that the quests of the quest log name: the item of an objective ("Gnoll Paw: 3/8")
-- by its name, and the item that a quest gives to use by its ID. The game gives no item ID for
-- an objective, only the text. Read again when the quest log changes.
local questNames, questIDs
local function readQuestLog()
  questNames, questIDs = {}, {}
  for index = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(index)
    if info and not info.isHeader and info.questID then
      local okObjectives, objectives = pcall(C_QuestLog.GetQuestObjectives, info.questID)
      for _, objective in ipairs(okObjectives and type(objectives) == "table" and objectives or {}) do
        local text = objective.text
        if objective.type == "item" and type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
          -- "3/8 Gnoll Paw" or "Gnoll Paw: 3/8"
          local name = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
          name = name:gsub("^%s+", ""):gsub("%s+$", ""):lower()
          if name ~= "" then
            questNames[name] = true
          end
        end
      end
      if type(GetQuestLogSpecialItemInfo) == "function" then
        local okItem, link = pcall(GetQuestLogSpecialItemInfo, index)
        local itemID = okItem and type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if itemID then
          questIDs[itemID] = true
        end
      end
    end
  end
end

-- A quest item is an item with any of the signs that the game gives:
--   the game marks the slot as a quest item, or as an item that starts a quest
--   the item is of the item class Quest
--   the item binds as a quest item (its tooltip says "Quest Item")
--   a quest of the quest log names the item, as an objective or as the item to use
-- Many quest items say "Soulbound" and not "Quest Item" in the tooltip, so the tooltip line
-- alone is not the test.
local function categoryOf(info, bag, slot)
  if info.quality == 0 and not info.hasNoValue then
    return "junk"
  end
  local okQuest, quest = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
  if okQuest and type(quest) == "table" and (quest.isQuestItem or quest.questID) then
    return "quest"
  end
  local classID = select(6, C_Item.GetItemInfoInstant(info.itemID))
  if classID == 12 then
    return "quest"
  end
  local okInfo, bindType = pcall(function()
    return (select(14, C_Item.GetItemInfo(info.itemID)))
  end)
  if okInfo and bindType == BIND_QUEST then
    return "quest"
  end
  if not questNames then
    pcall(readQuestLog)
  end
  local name = info.itemName
  if (questIDs and questIDs[info.itemID])
    or (questNames and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and questNames[name:lower()]) then
    return "quest"
  end
  for _, category in ipairs(CATEGORIES) do
    if category.classes[classID] then
      return category.key
    end
  end
  return "other"
end
-- The category of the item in a slot: the key of CATEGORIES, or nil for an empty slot.
function ns.CategoryOf(bag, slot)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  return info and categoryOf(info, bag, slot) or nil
end

local function headerAt(index)
  local header = headers[index]
  if not header then
    header = grid:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header:SetJustifyH("LEFT")
    headers[index] = header
  end
  return header
end

-- Reads the bags and puts the buttons in their places. Returns the number of free slots.
local function layout()
  local columns = ns.GetOption("columns")
  local byCategory = ns.GetOption("groupBy") == "category"
  local used = {} -- buttons that show in this layout
  local sections = {} -- { name, slots = { { bag, slot, info } } }
  local free, firstFree = 0, nil
  local hearth -- the slot with the Hearthstone

  if byCategory then
    for _, category in ipairs(CATEGORIES) do
      sections[#sections + 1] = { key = category.key, name = category.name, slots = {} }
    end
  else
    sections[1] = { slots = {} }
  end
  local sectionByKey = {}
  for _, section in ipairs(sections) do
    sectionByKey[section.key or 1] = section
  end

  for _, bag in ipairs(ns.BAGS) do
    local okSlots, slots = pcall(C_Container.GetContainerNumSlots, bag)
    for slot = 1, okSlots and type(slots) == "number" and slots or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if not info then
        free = free + 1
        firstFree = firstFree or { bag, slot }
      end
      if info and info.itemID == HEARTHSTONE and not hearth then
        hearth = { bag, slot, info }
      elseif not byCategory then
        table.insert(sections[1].slots, { bag, slot, info })
      elseif info then
        table.insert(sectionByKey[categoryOf(info, bag, slot)].slots, { bag, slot, info })
      end
    end
  end
  -- By category, one free slot shows, so there is a place to drop an item.
  if byCategory and firstFree then
    sections[#sections + 1] = { name = "Free (" .. free .. ")", slots = { { firstFree[1], firstFree[2], nil } } }
  end

  local y = 0
  local headerIndex = 0
  for _, section in ipairs(sections) do
    if #section.slots > 0 then
      if section.name then
        headerIndex = headerIndex + 1
        local header = headerAt(headerIndex)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", grid, "TOPLEFT", 2, -y - 2)
        header:SetText(section.name)
        header:Show()
        y = y + HEADER
      end
      for index, entry in ipairs(section.slots) do
        local bag, slot, info = entry[1], entry[2], entry[3]
        local button = buttonFor(bag, slot)
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        button:ClearAllPoints()
        button:SetScale(1)
        button:SetPoint("TOPLEFT", grid, "TOPLEFT", column * (BUTTON + GAP), -y - row * (BUTTON + GAP))
        button:Show()
        updateButton(button, bag, slot, info)
        used[button] = true
      end
      y = y + math.ceil(#section.slots / columns) * (BUTTON + GAP) + (section.name and 4 or 0)
    end
  end
  for index = headerIndex + 1, #headers do
    headers[index]:Hide()
  end
  -- The Hearthstone: the item button of its slot, at the top of the window. It is the same
  -- button as in the grid, so a click uses the stone and the tooltip and cooldown are the game's.
  local scale = ns.GetOption("scale") / 100
  if hearth then
    local button = buttonFor(hearth[1], hearth[2])
    button:ClearAllPoints()
    button:SetScale(HEARTH_SCALE / scale)
    button:SetPoint("TOPRIGHT", window, "TOPRIGHT", -30 / HEARTH_SCALE, -22 / HEARTH_SCALE)
    button:Show()
    updateButton(button, hearth[1], hearth[2], hearth[3])
    used[button] = true
    window.hearthstone = button
  else
    window.hearthstone = nil
  end
  for _, bagButtons in pairs(buttons) do
    for _, button in pairs(bagButtons) do
      if not used[button] then
        button:Hide()
      end
    end
  end

  local width = columns * (BUTTON + GAP) - GAP
  grid:SetScale(scale)
  grid:SetSize(width, math.max(y, BUTTON))
  window:SetSize(math.max(width * scale + PAD * 2, 250), math.max(y, BUTTON) * scale + TOP + BOTTOM)
  return free
end

local function refresh()
  refreshPending = false
  if not (window and window:IsShown()) then
    return
  end
  local ok, free = pcall(layout)
  window.background:SetColorTexture(0.04, 0.04, 0.05, ns.GetOption("alpha") / 100)
  window.money:SetText(ns.Money(GetMoney and GetMoney() or 0))
  window.free:SetText(ok and (free .. " free") or "")
  window:SetMovable(not ns.GetOption("lock"))
end

local function scheduleRefresh()
  if not refreshPending and window and window:IsShown() then
    refreshPending = true
    C_Timer.After(0.05, refresh)
  end
end

---------------------------------------------------------------------------------------------------
-- Window

local function smallButton(parent, text, width, tip, click)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width, 20)
  button:SetText(text)
  button:SetScript("OnClick", click)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(text, 1, 1, 1)
    GameTooltip:AddLine(tip, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  return button
end

local function create()
  window = CreateFrame("Frame", "ForeverBagsWindow", UIParent)
  window:SetFrameStrata("MEDIUM")
  window:SetClampedToScreen(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", function(self)
    if not ns.GetOption("lock") then
      self:StartMoving()
    end
  end)
  window:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.SavePosition("window", self)
  end)
  window:Hide()
  tinsert(UISpecialFrames, "ForeverBagsWindow") -- Escape closes the window

  window.background = window:CreateTexture(nil, "BACKGROUND")
  window.background:SetAllPoints()
  for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
    local line = window:CreateTexture(nil, "BORDER")
    line:SetColorTexture(0.35, 0.5, 0.65, 0.9)
    line:SetPoint(edge[1])
    line:SetPoint(edge[2])
    if edge[3] then
      line:SetHeight(1)
    else
      line:SetWidth(1)
    end
  end

  local title = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", PAD, -8)
  title:SetText("Bags")

  local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    window:Hide()
  end)

  local ok, box = pcall(CreateFrame, "EditBox", nil, window, "SearchBoxTemplate")
  if not ok then
    box = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
  end
  box:SetSize(150, 20)
  box:SetPoint("TOPLEFT", PAD + 4, -30)
  box:SetAutoFocus(false)
  box:HookScript("OnTextChanged", function(self)
    local text = ((self:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
    if text ~= search then
      search = text
      scheduleRefresh()
    end
  end)
  box:HookScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  window.search = box

  grid = CreateFrame("Frame", nil, window)
  grid:SetPoint("TOPLEFT", PAD, -TOP)
  grid:SetSize(100, 100)

  window.money = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  window.money:SetPoint("BOTTOMRIGHT", -PAD, 10)
  window.free = window:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  window.free:SetPoint("RIGHT", window.money, "LEFT", -10, 0)

  local sort = smallButton(window, "Sort", 50, "Sorts the items in your bags, the same way as the sort button of the game.", function()
    if C_Container and C_Container.SortBags then
      pcall(C_Container.SortBags)
    end
  end)
  sort:SetPoint("BOTTOMLEFT", PAD, 7)
  local all = smallButton(window, "All", 40, "Opens the list of the items of all your characters.", function()
    ns.ShowBrowser()
  end)
  all:SetPoint("LEFT", sort, "RIGHT", 4, 0)
  local group = smallButton(window, "View", 50, "Changes between items by category and items in the order of the bags.", function()
    ns.SetOption("groupBy", ns.GetOption("groupBy") == "category" and "none" or "category")
  end)
  group:SetPoint("LEFT", all, "RIGHT", 4, 0)

  window:SetScript("OnShow", function()
    refresh()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then
      PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
    end
  end)
  window:SetScript("OnHide", function()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then
      PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
    end
  end)

  ns.RestorePosition("window", window, "BOTTOMRIGHT", -80, 120)
end

-- Shows the window. Returns false if the window could not be made.
function ns.ShowWindow()
  if not window then
    if not pcall(create) then
      window = nil
      return false
    end
  end
  window:Show()
  return true
end

function ns.HideWindow()
  local shown = window ~= nil and window:IsShown()
  if shown then
    window:Hide()
  end
  return shown
end

function ns.ToggleWindow()
  if window and window:IsShown() then
    window:Hide()
    return true
  end
  return ns.ShowWindow()
end

-- Puts a text in the search box of the window and opens the window.
function ns.Search(text)
  if ns.ShowWindow() then
    window.search:SetText(text or "")
  end
end

ns.OnChange(function()
  if window and window:IsShown() then
    refresh()
  end
end)

ns.OnResetPositions(function()
  if window then
    ns.RestorePosition("window", window, "BOTTOMRIGHT", -80, 120)
  end
end)

---------------------------------------------------------------------------------------------------
-- In place of the bag window of the game
--
-- The functions of the game run as before and open or close the game's own bag windows. Those
-- are children of a hidden frame while the option is on, so they are not on the screen. After
-- each function a hook does the same to this window.
--
-- One key press runs several of the functions: ToggleAllBags closes the backpack with
-- CloseBackpack, or opens all with OpenAllBags. The hook of the inner function runs first and
-- the hook of the outer one last. So each hook says where the window must be, from how it was
-- before the key press, and the last one decides.

local installed = false
local hiddenParent
local gameParents = {} -- [bag window of the game] = its parent before

local function isBagOfCharacter(id)
  return id == nil or (type(id) == "number" and id >= 0 and id <= 5)
end

-- The bag windows of the game: the combined one and one for each bag.
local function gameWindows()
  local list = {}
  local combined = _G["ContainerFrameCombinedBags"]
  if type(combined) == "table" then
    list[#list + 1] = combined
  end
  for index = 1, 20 do
    local frame = _G["ContainerFrame" .. index]
    if type(frame) ~= "table" then
      break
    end
    list[#list + 1] = frame
  end
  return list
end

-- Takes the bag windows of the game off the screen, or gives them back.
local function hideGameWindows(hide)
  if hide then
    hiddenParent = hiddenParent or CreateFrame("Frame")
    hiddenParent:Hide()
    for _, frame in ipairs(gameWindows()) do
      if gameParents[frame] == nil and type(frame.SetParent) == "function" then
        gameParents[frame] = frame:GetParent() or UIParent
        pcall(frame.SetParent, frame, hiddenParent)
      end
    end
  else
    for frame, parent in pairs(gameParents) do
      pcall(frame.SetParent, frame, parent)
      gameParents[frame] = nil
    end
  end
end

local pressAt, shownBefore

-- `want`: true to show the window, false to hide it, nil for the other of how it was.
local function follow(want)
  if not ns.GetOption("replaceBags") then
    return
  end
  local now = GetTime()
  if pressAt ~= now then
    pressAt = now
    shownBefore = window ~= nil and window:IsShown()
  end
  if want == nil then
    want = not shownBefore
  end
  if want then
    ns.ShowWindow()
  else
    ns.HideWindow()
  end
end

local function install()
  if installed then
    return
  end
  installed = true
  local function hook(name, fn)
    if type(_G[name]) == "function" then
      hooksecurefunc(name, function(...)
        pcall(fn, ...)
      end)
    end
  end
  hook("ToggleAllBags", function() follow(nil) end)
  hook("ToggleBackpack", function() follow(nil) end)
  hook("OpenAllBags", function() follow(true) end)
  hook("OpenBackpack", function() follow(true) end)
  hook("CloseAllBags", function() follow(false) end)
  hook("CloseBackpack", function() follow(false) end)
  -- A bag of the bank has a higher number: that one stays with the game.
  hook("ToggleBag", function(id)
    if isBagOfCharacter(id) then
      follow(nil)
    end
  end)
  hook("OpenBag", function(id)
    if isBagOfCharacter(id) then
      follow(true)
    end
  end)
end

ns.OnChange(function(key)
  if key == "replaceBags" then
    if ns.GetOption("replaceBags") then
      install()
      hideGameWindows(true)
    else
      ns.HideWindow()
      hideGameWindows(false)
    end
  end
end)
ns.OnLogin(function()
  if ns.GetOption("replaceBags") then
    install()
    hideGameWindows(true)
  end
  local events = CreateFrame("Frame")
  for _, event in ipairs({
    "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "PLAYER_MONEY", "MERCHANT_SHOW",
    "MERCHANT_CLOSED", "BAG_NEW_ITEMS_UPDATED", "QUEST_ACCEPTED", "QUEST_REMOVED", "BAG_SLOT_FLAGS_UPDATED",
  }) do
    pcall(events.RegisterEvent, events, event)
  end
  pcall(events.RegisterEvent, events, "QUEST_LOG_UPDATE")
  events:SetScript("OnEvent", function(_, event)
    if event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
      questNames, questIDs = nil, nil -- read again at the next layout
    end
    scheduleRefresh()
  end)
end)
