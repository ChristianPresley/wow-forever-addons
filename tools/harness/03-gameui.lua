
---------------------------------------------------------------------------------------------------
-- Part 3: the game's own windows and Lua code
--
-- This is UI code of the game itself, so Blizzard's API documentation does not have it. Each
-- name here is in the game's own UI code of this client; the file is beside it.

-- Frames of the game that are made later than the ones at the start (see H.gameFrames).
H.gameFrameSet = {}

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
WorldFrame = CreateFrame("Frame", "WorldFrame")
-- The world frame alone has the strata WORLD (wowless, WorldFrame > has strata WORLD).
state(WorldFrame).strata = "WORLD"
-- Blizzard_GameTooltip/Mainline/GameTooltip.xml
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent, "GameTooltipTemplate")
-- Blizzard_UIPanels_Game/Mainline/ItemRef.xml
ItemRefTooltip = CreateFrame("GameTooltip", "ItemRefTooltip", UIParent, "GameTooltipTemplate")
Minimap = CreateFrame("Minimap", "Minimap", UIParent)
-- Blizzard_SharedXML/ScrollingMessageFrame.xml
DEFAULT_CHAT_FRAME = CreateFrame("ScrollingMessageFrame", "ChatFrame1", UIParent)
GameTooltip:Hide()
ItemRefTooltip:Hide()

-- The world map (Blizzard_MapCanvas/Blizzard_MapCanvas.lua, MapCanvasMixin).
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame.ScrollContainer = CreateFrame("ScrollFrame", nil, WorldMapFrame)
WorldMapFrame.ScrollContainer.Child = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
H.canvasClickHandlers = {}
local pinLevels = { GetValidFrameLevel = function() return 2000 end }
function WorldMapFrame:GetMapID()
  return 37
end
function WorldMapFrame:GetNormalizedCursorPosition()
  return 0.4, 0.6
end
function WorldMapFrame:GetCanvas()
  return self.ScrollContainer.Child
end
function WorldMapFrame:GetCanvasScale()
  return 1
end
function WorldMapFrame:AddCanvasClickHandler(handler, priority)
  if realType(handler) ~= "function" then
    fail("AddCanvasClickHandler: not a function")
  end
  H.canvasClickHandlers[#H.canvasClickHandlers + 1] = handler
end
function WorldMapFrame:GetPinFrameLevelsManager()
  return pinLevels
end

-- The quest log on the world map (Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua).
-- QuestLogQuests_Update, in part 4, builds one button for each quest.
QuestMapFrame = CreateFrame("Frame", "QuestMapFrame", WorldMapFrame)
QuestScrollFrame = CreateFrame("EventScrollFrame", "QuestScrollFrame", QuestMapFrame)
QuestScrollFrame.Contents = CreateFrame("Frame", nil, QuestScrollFrame)
-- QuestMapFrame.xml: the details of one quest, a child of the quest log with the key DetailsFrame.
QuestMapFrame.DetailsFrame = CreateFrame("Frame", nil, QuestMapFrame)
QuestMapFrame.DetailsFrame:Hide()
-- QuestMapFrame.lua: shows the details of a quest in the quest log.
function QuestMapFrame_ShowQuestDetails(questID)
  if realType(questID) ~= "number" then
    fail("QuestMapFrame_ShowQuestDetails: a quest ID is needed, got " .. realType(questID))
  end
  QuestMapFrame.DetailsFrame.questID = questID
  QuestMapFrame.DetailsFrame:Show()
end
-- QuestMapFrame.lua: opens the quest log with the details of a quest. It calls
-- QuestMapFrame_ShowQuestDetails by its global name, so a hook on that one runs.
function QuestMapFrame_OpenToQuestDetails(questID)
  if realType(questID) ~= "number" then
    fail("QuestMapFrame_OpenToQuestDetails: a quest ID is needed, got " .. realType(questID))
  end
  H.did[#H.did + 1] = { "open quest", questID }
  QuestMapFrame_ShowQuestDetails(questID)
end
-- QuestMapFrame.xml: the search box of the quest log, an edit box with SearchBoxTemplate.
QuestScrollFrame.SearchBox = CreateFrame("EditBox", nil, QuestScrollFrame, "SearchBoxTemplate")
H.questLogLayouts = 0
function QuestScrollFrame.Contents:Layout()
  H.questLogLayouts = H.questLogLayouts + 1
end
local function newPool()
  local pool = { active = {} }
  function pool:EnumerateActive()
    local index = 0
    return function()
      index = index + 1
      return self.active[index]
    end
  end
  function pool:GetNumActive()
    return #self.active
  end
  return pool
end
QuestScrollFrame.titleFramePool = newPool()
QuestScrollFrame.objectiveFramePool = newPool()
QuestScrollFrame.headerFramePool = newPool()
H.questLogFrames = {} -- the buttons are made once and used again, as the pools of the game do

-- The auction house (Blizzard_AuctionHouseUI). The game loads it when the auction house opens:
-- until the driver calls H.openAuctionHouse, AuctionHouseFrame is nil, as at login in the game.
H.auctionSearches = {}
function H.openAuctionHouse()
  if AuctionHouseFrame then
    return
  end
  AuctionHouseFrameDisplayMode = { Buy = {}, ItemSell = {}, CommoditiesSell = {} }
  local house = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
  house.SearchBar = CreateFrame("Frame", nil, house)
  house.SearchBar.SearchBox = CreateFrame("EditBox", nil, house.SearchBar)
  function house.SearchBar:SetSearchText(text)
    self.SearchBox:SetText(text)
  end
  function house.SearchBar:StartSearch()
    H.auctionSearches[#H.auctionSearches + 1] = self.SearchBox:GetText()
  end
  function house:SetDisplayMode(mode)
    if realType(mode) ~= "table" then
      fail("SetDisplayMode: not a display mode")
    end
  end
  local function newSellFrame(itemKey)
    local frame = CreateFrame("Frame", nil, house)
    frame.PostButton = CreateFrame("Button", nil, frame)
    frame.PriceInput = CreateFrame("Frame", nil, frame)
    function frame.PriceInput:SetAmount(amount)
      if realType(amount) ~= "number" then
        fail("PriceInput:SetAmount: a number is needed, got " .. realType(amount))
      end
      H.did[#H.did + 1] = { "price filled", amount }
    end
    function frame:GetItem()
      return ItemLocation:CreateFromBagAndSlot(0, 2)
    end
    frame.listDisplayedItemKey = itemKey
    return frame
  end
  house.CommoditiesSellFrame = newSellFrame(nil)
  house.ItemSellFrame = newSellFrame({ itemID = 2589, itemLevel = 0, itemSuffix = 0 })
  -- These are the game's own frames: the driver does not use them as frames of the addon.
  H.gameFrameSet = H.gameFrameSet or {}
  for _, frame in ipairs({ house, house.SearchBar, house.SearchBar.SearchBox, house.CommoditiesSellFrame, house.ItemSellFrame,
    house.CommoditiesSellFrame.PostButton, house.CommoditiesSellFrame.PriceInput, house.ItemSellFrame.PostButton,
    house.ItemSellFrame.PriceInput }) do
    H.gameFrameSet[frame] = true
  end
end

-- Blizzard_UIParentPanelManager and Blizzard_StaticPopup/StaticPopup.lua
UISpecialFrames = {}
SlashCmdList = {}
StaticPopupDialogs = {}
-- A confirmation dialog. The stand-in answers at once: yes, or no when H.world.sayNo is set.
function StaticPopup_Show(name, _, _, data)
  local dialog = StaticPopupDialogs[name]
  if not dialog then
    fail("StaticPopup_Show: unknown dialog " .. realTostring(name))
  end
  local shown = { which = name, data = data }
  if H.world.sayNo then
    if dialog.OnCancel then
      dialog.OnCancel(shown, data, "clicked")
    end
  elseif dialog.OnAccept then
    dialog.OnAccept(shown, data)
  end
  return shown
end

-- Timers (C_Timer is in the documentation; the stand-in runs them on its own clock).
local function newTimer(seconds, fn, iterations, passSelf)
  if realType(seconds) ~= "number" or realType(fn) ~= "function" then
    fail("C_Timer: (seconds, function) is needed")
  end
  local timer = { at = H.now + seconds, seconds = seconds, fn = fn, left = iterations, passSelf = passSelf, cancelled = false }
  function timer:Cancel()
    self.cancelled = true
  end
  function timer:IsCancelled()
    return self.cancelled
  end
  H.timers[#H.timers + 1] = timer
  return timer
end
C_Timer.After = function(seconds, fn)
  newTimer(seconds, fn, 1, false)
end
C_Timer.NewTimer = function(seconds, fn)
  return newTimer(seconds, fn, 1, true)
end
-- A ticker runs again and again: `iterations` times, or without end.
C_Timer.NewTicker = function(seconds, fn, iterations)
  return newTimer(seconds, fn, iterations or math.huge, true)
end

-- Moves the clock forward and runs the timers that are due, the earliest first. A timer can
-- start a timer. The limit stops a timer that starts itself again with no delay.
function H.advance(seconds)
  local target = H.now + seconds
  for _ = 1, 2000 do
    local nextIndex, nextTimer
    for index, timer in ipairs(H.timers) do
      if timer.at <= target and (not nextTimer or timer.at < nextTimer.at) then
        nextIndex, nextTimer = index, timer
      end
    end
    if not nextTimer then
      break
    end
    table.remove(H.timers, nextIndex)
    if not nextTimer.cancelled then
      H.now = math.max(H.now, nextTimer.at)
      nextTimer.left = nextTimer.left - 1
      if nextTimer.left > 0 then
        nextTimer.at = nextTimer.at + math.max(nextTimer.seconds, 0.01)
        H.timers[#H.timers + 1] = nextTimer
      end
      if nextTimer.passSelf then
        H.call("timer", nextTimer.fn, nextTimer)
      else
        H.call("timer", nextTimer.fn)
      end
    end
  end
  H.clock = H.clock + seconds
  H.now = target
  -- Time that passes is an OnUpdate of each frame that is on the screen, as in the game.
  local count = #H.frames
  for index = 1, count do
    local frame = H.frames[index]
    local handler = H.state(frame).scripts.OnUpdate
    if handler and frame:IsVisible() then
      H.call("OnUpdate", handler, frame, seconds)
    end
  end
end

-- The settings window (Blizzard_Settings_Shared/Blizzard_Settings.lua).
Settings = {}
local categoryID = 0
local function newCategory(panel, name, parent)
  if not isWidget(panel) then
    fail("Settings: the panel is not a frame")
  end
  categoryID = categoryID + 1
  local category = { ID = categoryID, name = name, panel = panel, parent = parent }
  function category:GetID()
    return self.ID
  end
  H.settingsPanels[#H.settingsPanels + 1] = panel
  return category
end
function Settings.RegisterCanvasLayoutCategory(panel, name)
  return newCategory(panel, name)
end
function Settings.RegisterCanvasLayoutSubcategory(parent, panel, name)
  if realType(parent) ~= "table" or not parent.ID then
    fail("Settings.RegisterCanvasLayoutSubcategory: the parent is not a category")
  end
  return newCategory(panel, name, parent)
end
function Settings.RegisterAddOnCategory(category)
  if realType(category) ~= "table" or not category.ID then
    fail("Settings.RegisterAddOnCategory: not a category")
  end
end
function Settings.OpenToCategory(id)
  if realType(id) ~= "number" then
    fail("Settings.OpenToCategory: the ID is not a number")
  end
end

-- Menus (Blizzard_Menu/Menu.lua and MenuUtil.lua). A menu is a tree of entries, each with the
-- functions that the addon gave. The driver runs them.
local function newMenuEntry(actions)
  local entry = {}
  local function child(kind)
    return function(_, text, a, b, c)
      if text ~= nil and realType(text) ~= "string" then
        fail("menu: the text of an entry is not a text")
      end
      if kind == "button" and a ~= nil then
        if realType(a) ~= "function" then
          fail("menu: the action of a button is not a function")
        end
        actions[#actions + 1] = function()
          a(b)
        end
      elseif kind == "check" then
        if realType(a) ~= "function" or realType(b) ~= "function" then
          fail("menu: a checkbox or radio needs two functions")
        end
        actions[#actions + 1] = function()
          a(c)
          b(c)
        end
      end
      return newMenuEntry(actions)
    end
  end
  entry.CreateButton = child("button")
  entry.CreateCheckbox = child("check")
  entry.CreateRadio = child("check")
  entry.CreateTitle = child("title")
  for _, name in ipairs({ "CreateDivider", "CreateSpacer", "QueueSpacer", "QueueDivider", "QueueTitle", "SetTag", "SetTooltip", "SetEnabled" }) do
    entry[name] = function() end
  end
  return entry
end
MenuUtil = {}
function MenuUtil.CreateContextMenu(owner, generator)
  if realType(generator) ~= "function" then
    fail("MenuUtil.CreateContextMenu: the generator is not a function")
  end
  local actions = {}
  generator(owner, newMenuEntry(actions))
  H.menus[#H.menus + 1] = actions
end
Menu = {}
function Menu.ModifyMenu(tag, generator)
  if realType(tag) ~= "string" or realType(generator) ~= "function" then
    fail("Menu.ModifyMenu: (tag, function) is needed")
  end
  local actions = {}
  generator(UIParent, newMenuEntry(actions))
  H.menus[#H.menus + 1] = actions
end

-- Tooltip data (Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua).
TooltipDataProcessor = {}
function TooltipDataProcessor.AddTooltipPostCall(kind, fn)
  if realType(fn) ~= "function" then
    fail("TooltipDataProcessor.AddTooltipPostCall: not a function")
  end
  H.postCalls[#H.postCalls + 1] = { kind = kind, fn = fn }
end

-- Helpers for a tooltip. Blizzard_GameTooltip/Mainline/GameTooltip.lua:
function GameTooltip_Hide()
  GameTooltip:Hide()
end
-- Blizzard_SharedXML/SharedTooltipTemplates.lua: the place of a tooltip that has no place of
-- its own, then a title, a line, an empty line.
function GameTooltip_SetDefaultAnchor(tooltip, parent)
  tooltip:SetOwner(parent, "ANCHOR_NONE")
end
function GameTooltip_SetTitle(tooltip, text)
  tooltip:SetText(text)
end
for _, name in ipairs({ "GameTooltip_AddNormalLine", "GameTooltip_AddHighlightLine", "GameTooltip_AddInstructionLine", "GameTooltip_AddErrorLine", "GameTooltip_AddColoredLine" }) do
  _G[name] = function(tooltip, text)
    tooltip:AddLine(text)
  end
end
function GameTooltip_AddBlankLineToTooltip(tooltip)
  tooltip:AddLine(" ")
end

-- The scroll box (Blizzard_SharedXML/Shared/Scroll): a list that shows the rows in view.
-- The stand-in makes a frame for each of the first rows and fills it with the addon's function.
local SCROLL_ROWS = 15
TEMPLATES.WowScrollBoxList = { kind = "Frame", setup = function(box)
  local s = { frames = {}, items = {} }
  function box:SetDataProvider(provider, retain)
    if realType(provider) ~= "table" or realType(provider.items) ~= "table" then
      fail("SetDataProvider: a data provider is needed")
    end
    s.items = provider.items
    self:Update()
  end
  function box:Update()
    if not s.view then
      return
    end
    for index = 1, math.max(#s.frames, math.min(#s.items, SCROLL_ROWS)) do
      local item = s.items[index]
      local frame = s.frames[index]
      if item and index <= SCROLL_ROWS then
        if not frame then
          frame = CreateFrame(s.view.frameType, nil, self)
          s.frames[index] = frame
        end
        frame:Show()
        frame.item = item
        s.view.initializer(frame, item)
      elseif frame then
        frame:Hide()
      end
    end
  end
  function box:ForEachFrame(fn)
    for index, frame in ipairs(s.frames) do
      if frame:IsShown() then
        fn(frame, s.items[index])
      end
    end
  end
  state(box).scroll = s
end }
TEMPLATES.MinimalScrollBar = { kind = "Frame", setup = function() end }
function CreateScrollBoxListLinearView()
  local view = {}
  function view:SetElementExtentCalculator(fn)
    if realType(fn) ~= "function" then
      fail("SetElementExtentCalculator: a function is needed")
    end
  end
  function view:SetElementFactory(fn)
    if realType(fn) ~= "function" then
      fail("SetElementFactory: a function is needed")
    end
    -- The game calls the factory for each row; it names the frame type and the row function.
    fn(function(frameType, initializer)
      view.frameType, view.initializer = frameType, initializer
    end)
  end
  return view
end
function CreateDataProvider(items)
  return { items = items or {} }
end
ScrollUtil = {}
function ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  if not (isWidget(box) and state(box).scroll and isWidget(bar) and realType(view) == "table") then
    fail("ScrollUtil.InitScrollBoxListWithScrollBar: (scroll box, scroll bar, view) is needed")
  end
  state(box).scroll.view = view
end
ScrollBoxConstants = { RetainScrollPosition = true, DiscardScrollPosition = false }

-- Colours (Blizzard_SharedXMLBase/Color.lua, Blizzard_SharedXML/ClassColors.lua).
local function color(r, g, b, a)
  local c = { r = r, g = g, b = b, a = a or 1, colorStr = "ffffffff" }
  function c:GetRGB()
    return self.r, self.g, self.b
  end
  function c:GetRGBA()
    return self.r, self.g, self.b, self.a
  end
  function c:WrapTextInColorCode(text)
    return text
  end
  return c
end
CreateColor = color
RAID_CLASS_COLORS = {}
for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
  RAID_CLASS_COLORS[class] = color(0.7, 0.6, 0.4)
end
-- Blizzard_Colors/Mainline/ColorManager.lua: a plain table for each quality, with the colour
-- object under `color`.
ITEM_QUALITY_COLORS = {}
for quality = 0, 8 do
  ITEM_QUALITY_COLORS[quality] = { r = 1, g = 1, b = 1, hex = "|cffffffff", color = color(1, 1, 1) }
end
-- Sounds: the keys that the addons use, each one in the game's own code. Another key is nil,
-- the same as a key that the game does not have.
SOUNDKIT = {
  IG_QUEST_LIST_COMPLETE = 878, -- Blizzard_StaticPopup_Game/GameDialogDefs.lua
  AUCTION_WINDOW_OPEN = 5274, -- Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.lua
  IG_BACKPACK_OPEN = 862, -- Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua
  IG_BACKPACK_CLOSE = 863, -- Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua
  IG_MAINMENU_OPTION_CHECKBOX_ON = 856, -- Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseSearchBar.lua
}
YES, NO, OKAY, CANCEL = "Yes", "No", "Okay", "Cancel"
-- Blizzard_FrameXMLBase/Constants.lua
NUM_BAG_SLOTS = 4
NUM_REAGENTBAG_SLOTS = 1
-- Blizzard_ProjectConstants
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC, WOW_PROJECT_CAMELOT = 1, 2, 18
WOW_PROJECT_ID = WOW_PROJECT_CAMELOT
-- Blizzard_SharedXML/Mainline/Sound.lua
function PlaySound(soundKit)
  if realType(soundKit) ~= "number" then
    fail("PlaySound: a number is needed, got " .. realType(soundKit))
  end
end
-- Blizzard_SharedXML/FormattingUtil.lua
function GetMoneyString(copper)
  if realType(copper) ~= "number" then
    fail("GetMoneyString: a number is needed, got " .. realType(copper))
  end
  return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end
-- Blizzard_SharedXML/Vector2D.lua
function CreateVector2D(x, y)
  return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end
-- Blizzard_ObjectAPI/Mainline/ItemLocation.lua
ItemLocation = {}
function ItemLocation:CreateFromBagAndSlot(bagID, slotIndex)
  local location = { bagID = bagID, slotIndex = slotIndex }
  function location:IsValid()
    return true
  end
  function location:GetBagAndSlot()
    return self.bagID, self.slotIndex
  end
  return location
end
-- Blizzard_ItemButton/Mainline/ItemButtonTemplate.lua
function ClearItemButtonOverlay() end
function SetItemButtonQuality() end
function SetItemButtonCount() end
function SetItemButtonDesaturated() end
-- Blizzard_SharedXMLBase/TextureUtil.lua
function CreateAtlasMarkup()
  return ""
end
