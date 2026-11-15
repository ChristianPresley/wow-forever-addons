local _, ns = ...

-- "Current zone only", for the quest log (option zoneLog) and for the tracker (option zoneTracker).
--
-- A quest belongs to the current zone when its header in the quest log has the name of the zone
-- (the game sorts quests under zone names), or when it has an objective on the map of the zone.
--
-- The quest log is filtered after the game has built it: the buttons of other zones are hidden and
-- the list is laid out again. The tracker is filtered through the watch list, which is the game's
-- own API: quests of the zone are tracked and the others are untracked. The player's own tracking
-- is saved when the option goes on and comes back when it goes off.

local function key(text)
  if type(text) ~= "string" or text == "" or ns.IsSecret(text) then
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

  local inZone, zoneHeaders, quests = {}, {}, {}
  local headerIndex, headerInZone
  for i = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(i)
    if info and info.isHeader then
      headerIndex = i
      headerInZone = names[key(info.title) or ""] or false
    elseif info and info.questID and not info.isHidden and not info.isTask then
      quests[#quests + 1] = info.questID
      if headerInZone or onMap[info.questID] then
        inZone[info.questID] = true
        if headerIndex then
          zoneHeaders[headerIndex] = true
        end
      end
    end
  end
  return inZone, zoneHeaders, quests
end

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

local function searching()
  return QuestSearcher and QuestSearcher.IsActive and QuestSearcher:IsActive()
end

-- Runs after the game has built the quest log.
local function filterLog()
  local scroll = QuestScrollFrame
  if not (scroll and scroll.titleFramePool and scroll.titleFramePool.EnumerateActive and scroll.Contents and scroll.Contents.Layout) then
    return
  end
  -- A search shows every match, whatever its zone.
  if not ns.GetOption("zoneLog") or searching() then
    showEmptyNote(false)
    return
  end

  local inZone, zoneHeaders = scan()
  local hidden = {}
  local total, shown = 0, 0
  for button in scroll.titleFramePool:EnumerateActive() do
    local questID = button.questID
    if questID then
      total = total + 1
      if inZone[questID] then
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
  local headersHidden = false
  if scroll.headerFramePool and scroll.headerFramePool.EnumerateActive then
    for header in scroll.headerFramePool:EnumerateActive() do
      if header.questLogIndex and not zoneHeaders[header.questLogIndex] then
        header:Hide()
        headersHidden = true
      end
    end
  end
  if total > shown or headersHidden then
    -- The layout leaves out hidden frames, so the list closes up.
    scroll.Contents:Layout()
  end
  -- A collapsed zone header has no quest buttons but is still there to open.
  showEmptyNote(shown == 0 and next(zoneHeaders) == nil)
end

local function refreshLog()
  if QuestMapFrame and QuestMapFrame:IsVisible() and type(QuestLogQuests_Update) == "function" then
    pcall(QuestLogQuests_Update)
  end
end

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

-- Sets which quests are tracked. Untracks first, because the game limits the number of tracked quests.
local function setWatches(quests, shouldWatch)
  for _, questID in ipairs(quests) do
    if shouldWatch(questID) == false and isWatched(questID) then
      pcall(C_QuestLog.RemoveQuestWatch, questID)
    end
  end
  for _, questID in ipairs(quests) do
    if shouldWatch(questID) == true and not isWatched(questID) then
      pcall(C_QuestLog.AddQuestWatch, questID)
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
  if ns.GetOption("zoneLog") then
    refreshLog()
  end
end

local function schedule(delay)
  if not pending and (ns.GetOption("zoneLog") or ns.GetOption("zoneTracker")) then
    pending = true
    C_Timer.After(delay, update)
  end
end

ns.OnOptionChanged(function(option, value)
  if option == "zoneLog" then
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
  hooksecurefunc("QuestLogQuests_Update", function()
    pcall(filterLog)
  end)
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
frame:SetScript("OnEvent", function(self, event)
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
end)
