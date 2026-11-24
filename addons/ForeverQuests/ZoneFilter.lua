local _, ns = ...

-- "Current zone only", for the quest log (option zoneLog) and for the tracker (option zoneTracker),
-- and "Hide grey quests" for the quest log (option hideGrey).
--
-- A quest belongs to the current zone when its header in the quest log has the name of the zone
-- (the game sorts quests under zone names), or when it has an objective on the map of the zone.
--
-- The quest log is filtered after the game has built it: the buttons of other zones are hidden and
-- the list is laid out again. The tracker is filtered through the watch list, which is the game's
-- own API: quests of the zone are tracked and the others are untracked. The player's own tracking
-- is saved when the option goes on and comes back when it goes off.

local function key(text)
  -- A value that the game hides cannot be compared, so that test is first.
  if ns.IsSecret(text) or type(text) ~= "string" or text == "" then
    return nil
  end
  return text:lower()
end

-- The names of the place where the player is, in lower case, and the player's map.
local function currentZone()
  local names = {}
  local function add(text)
    local name = key(text)
    if name then
      names[name] = true
    end
  end
  add(GetRealZoneText and GetRealZoneText())
  add(GetZoneText and GetZoneText())
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  if info then
    add(info.name)
    -- Inside a smaller map (a cave, a city district), the zone is the parent map.
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone
    if zoneType and type(info.mapType) == "number" and info.mapType > zoneType and info.parentMapID and info.parentMapID > 0 then
      local parent = C_Map.GetMapInfo(info.parentMapID)
      add(parent and parent.name)
    end
  end
  return names, mapID
end

-- Returns:
--   inZone[questID] = true for each quest of the current zone
--   zoneHeaders[questLogIndex] = true for each header with a quest of the current zone
--   quests = list of the quest IDs in the log
--   headerOf[questID] = questLogIndex of the header the quest is under
local function scan()
  local names, mapID = currentZone()
  local onMap = {}
  if mapID and C_QuestLog.GetQuestsOnMap then
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
    if ok and type(list) == "table" then
      for _, quest in ipairs(list) do
        if quest.questID then
          onMap[quest.questID] = true
        end
      end
    end
  end

  local inZone, zoneHeaders, quests, headerOf = {}, {}, {}, {}
  local headerIndex, headerInZone
  for i = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(i)
    if info and info.isHeader then
      headerIndex = i
      headerInZone = names[key(info.title) or ""] or false
    elseif info and info.questID and not info.isHidden and not info.isTask then
      quests[#quests + 1] = info.questID
      headerOf[info.questID] = headerIndex
      if headerInZone or onMap[info.questID] then
        inZone[info.questID] = true
        if headerIndex then
          zoneHeaders[headerIndex] = true
        end
      end
    end
  end
  return inZone, zoneHeaders, quests, headerOf
end

-- True for a quest that the game shows in grey: far below the level of the player, with little
-- experience. The game gives the same answer that colours the name of the quest in its log
-- (Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua, QuestLogQuests_AddQuestButton).
local function isGrey(questID)
  local trivial = Enum and Enum.RelativeContentDifficulty and Enum.RelativeContentDifficulty.Trivial
  if trivial == nil or not (C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer) then
    return false
  end
  local ok, difficulty = pcall(C_PlayerInfo.GetContentDifficultyQuestForPlayer, questID)
  return ok and not ns.IsSecret(difficulty) and difficulty == trivial
end
ns.IsGreyQuest = isGrey

---------------------------------------------------------------------------------------------------
-- Quest log

local emptyNote

local function showEmptyNote(show)
  if show and not emptyNote then
    emptyNote = QuestScrollFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyNote:SetPoint("TOP", QuestScrollFrame, "TOP", 0, -48)
    emptyNote:SetText("No quests for this zone.\nTurn off \"Current zone only\" to see the others.")
  end
  if emptyNote then
    emptyNote:SetShown(show)
  end
end

-- True while the player has a text in the search box of the quest log.
-- (The game's own search object is a local of its file, so an addon reads the box.)
local function searching()
  local box = QuestScrollFrame and QuestScrollFrame.SearchBox
  local text = box and box.GetText and box:GetText()
  return not ns.IsSecret(text) and type(text) == "string" and text:gsub("%s", "") ~= ""
end

-- Runs after the game has built the quest log. Returns true if the log needs a new layout.
local function filterLog()
  local scroll = QuestScrollFrame
  if not (scroll and scroll.titleFramePool and scroll.titleFramePool.EnumerateActive) then
    return false
  end
  -- A search shows every match, whatever its zone or level.
  local zoneOn, greyOn = ns.GetOption("zoneLog"), ns.GetOption("hideGrey")
  if not (zoneOn or greyOn) or searching() then
    showEmptyNote(false)
    return false
  end

  local inZone, _, quests, headerOf = scan()
  -- A grey quest that is ready stays: the player can still turn it in.
  local function keep(questID)
    if zoneOn and not inZone[questID] then
      return false
    end
    return not (greyOn and isGrey(questID) and not ns.IsReady(questID))
  end
  -- A header stays when one of its quests stays. With the zone filter off, a header whose quests
  -- the game does not list (a collapsed header) stays too.
  local keptHeaders, listedHeaders = {}, {}
  for _, questID in ipairs(quests) do
    local header = headerOf[questID]
    if header then
      listedHeaders[header] = true
      if keep(questID) then
        keptHeaders[header] = true
      end
    end
  end
  local hidden = {}
  local total, shown = 0, 0
  for button in scroll.titleFramePool:EnumerateActive() do
    local questID = button.questID
    if questID then
      total = total + 1
      if keep(questID) then
        shown = shown + 1
      else
        hidden[questID] = true
        button:Hide()
      end
    end
  end
  if scroll.objectiveFramePool and scroll.objectiveFramePool.EnumerateActive then
    for line in scroll.objectiveFramePool:EnumerateActive() do
      if line.questID and hidden[line.questID] then
        line:Hide()
      end
    end
  end
  -- The icon of a quest at the left of its name is not a child of the title: it comes from a
  -- pool of the list and only hangs on the title (Blizzard_POIButton/POIButtonOwner.lua). So
  -- it would stay on the screen, over the list that closed up.
  local icons = scroll.Contents and scroll.Contents.buttonPool
  if type(icons) == "table" and type(icons.EnumerateActive) == "function" then
    for icon in icons:EnumerateActive() do
      local questID = type(icon.GetQuestID) == "function" and icon:GetQuestID()
      if questID and hidden[questID] then
        icon:Hide()
      end
    end
  end
  local headersHidden = false
  if scroll.headerFramePool and scroll.headerFramePool.EnumerateActive then
    for header in scroll.headerFramePool:EnumerateActive() do
      local index = header.questLogIndex
      if index and not keptHeaders[index] and (zoneOn or listedHeaders[index]) then
        header:Hide()
        headersHidden = true
      end
    end
  end
  -- A collapsed zone header has no quest buttons but is still there to open.
  showEmptyNote(zoneOn and shown == 0 and next(keptHeaders) == nil)
  -- The layout leaves out hidden frames, so the list closes up.
  return total > shown or headersHidden
end

-- After the game has built the quest log: the order (LogOrder.lua), then the zone filter, then one
-- new layout if either changed something.
local function afterLogUpdate()
  local ordered, moved = pcall(ns.ArrangeLog)
  local filtered, hid = pcall(filterLog)
  local contents = QuestScrollFrame and QuestScrollFrame.Contents
  if ((ordered and moved) or (filtered and hid)) and contents and contents.Layout then
    contents:Layout()
  end
end

local function refreshLog()
  if QuestMapFrame and QuestMapFrame:IsVisible() and type(QuestLogQuests_Update) == "function" then
    pcall(QuestLogQuests_Update)
  end
end
ns.RefreshQuestLog = refreshLog

local function addMenuItem()
  -- The settings menu of the quest log (the button next to its search box).
  if not (Menu and Menu.ModifyMenu) then
    return
  end
  Menu.ModifyMenu("MENU_QUEST_MAP_FRAME_SETTINGS", function(_, root)
    root:CreateCheckbox("Current zone only", function()
      return ns.GetOption("zoneLog")
    end, function()
      ns.SetOption("zoneLog", not ns.GetOption("zoneLog"))
    end)
    root:CreateCheckbox("Hide grey quests", function()
      return ns.GetOption("hideGrey")
    end, function()
      ns.SetOption("hideGrey", not ns.GetOption("hideGrey"))
    end)
  end)
end

---------------------------------------------------------------------------------------------------
-- Tracker

local function canWatch()
  return C_QuestLog.AddQuestWatch and C_QuestLog.RemoveQuestWatch and C_QuestLog.GetQuestWatchType
end

local function isWatched(questID)
  return C_QuestLog.GetQuestWatchType(questID) ~= nil
end

local lastMissed = 0

-- Sets which quests are tracked. Untracks first, because the game limits the number of tracked quests.
local function setWatches(quests, shouldWatch)
  for _, questID in ipairs(quests) do
    if shouldWatch(questID) == false and isWatched(questID) then
      pcall(C_QuestLog.RemoveQuestWatch, questID)
    end
  end
  -- The game tracks a limited number of quests: past it, it tracks no more. The player hears
  -- of it once for each number of quests left out.
  local missed = 0
  for _, questID in ipairs(quests) do
    if shouldWatch(questID) == true and not isWatched(questID) then
      pcall(C_QuestLog.AddQuestWatch, questID)
      if not isWatched(questID) then
        missed = missed + 1
      end
    end
  end
  if missed ~= lastMissed then
    lastMissed = missed
    if missed > 0 then
      ns.Print(string.format("the game tracks no more quests than it does now: %d %s of this zone %s not tracked.", missed, missed == 1 and "quest" or "quests", missed == 1 and "is" or "are"))
    end
  end
end

-- Remembers what the player tracks, once, before the option changes it.
local function saveWatches(quests)
  if type(ForeverQuestsCharDB.zoneSavedWatches) == "table" then
    return
  end
  local saved = {}
  for _, questID in ipairs(quests) do
    saved[questID] = isWatched(questID)
  end
  ForeverQuestsCharDB.zoneSavedWatches = saved
end

local function applyTracker()
  if not (ns.GetOption("zoneTracker") and ForeverQuestsCharDB and canWatch()) then
    return
  end
  local inZone, _, quests = scan()
  if #quests == 0 then
    return -- the quest log is not loaded yet
  end
  saveWatches(quests)
  setWatches(quests, function(questID)
    return inZone[questID] == true
  end)
end

-- Gives back the tracking of before. A quest accepted since then keeps its state.
local function restoreTracker()
  local saved = ForeverQuestsCharDB and ForeverQuestsCharDB.zoneSavedWatches
  if type(saved) ~= "table" then
    return
  end
  ForeverQuestsCharDB.zoneSavedWatches = nil
  if not canWatch() then
    return
  end
  local _, _, quests = scan()
  setWatches(quests, function(questID)
    return saved[questID]
  end)
end

---------------------------------------------------------------------------------------------------
-- Wiring

local pending = false

local function update()
  pending = false
  pcall(applyTracker)
  if ns.GetOption("zoneLog") or ns.GetOption("hideGrey") then
    refreshLog()
  end
end

local function schedule(delay)
  if not pending and (ns.GetOption("zoneLog") or ns.GetOption("zoneTracker") or ns.GetOption("hideGrey")) then
    pending = true
    C_Timer.After(delay, update)
  end
end

ns.OnOptionChanged(function(option, value)
  if option == "zoneLog" or option == "hideGrey" then
    refreshLog()
  elseif option == "zoneTracker" then
    if value then
      pcall(applyTracker)
    else
      pcall(restoreTracker)
    end
  end
end)

-- /fq zone: both on, or both off.
function ns.ToggleZoneFilter()
  local on = not (ns.GetOption("zoneLog") or ns.GetOption("zoneTracker"))
  ns.SetOption("zoneLog", on)
  ns.SetOption("zoneTracker", on)
  return on
end

local hooked = false

local function hook()
  if hooked or type(QuestLogQuests_Update) ~= "function" or not QuestScrollFrame then
    return hooked
  end
  hooked = true
  hooksecurefunc("QuestLogQuests_Update", afterLogUpdate)
  -- The game also builds the log while it is not on the screen. When the log comes onto the
  -- screen, the order and the glow of a quest that made progress are set again: the glow starts
  -- when the player sees it.
  for _, shown in ipairs({ QuestScrollFrame, QuestMapFrame }) do
    if type(shown) == "table" and type(shown.HookScript) == "function" then
      pcall(shown.HookScript, shown, "OnShow", function()
        pcall(afterLogUpdate)
      end)
    end
  end
  pcall(addMenuItem)
  return true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
pcall(frame.RegisterEvent, frame, "QUEST_ACCEPTED")
local loggedIn = false
frame:SetScript("OnEvent", ns.Safely("the zone filter", function(self, event)
  if event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then
    loggedIn = loggedIn or event == "PLAYER_LOGIN"
    -- The quest log of the game can load later than this addon.
    if loggedIn and hook() then
      self:UnregisterEvent("ADDON_LOADED")
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    schedule(2) -- the quest log needs a moment after a loading screen
  else
    schedule(0.5)
  end
end))
