local _, ns = ...

-- Shares quest objective progress with party members who also use this addon, over addon messages.
--
-- A message is the version "1", one letter and a list of entries with ";" between them:
--   H  asks the others for their quests (no entries)
--   S  the first part of a full list; it replaces what the sender sent before
--   C  a further part of a full list
--   U  changes
-- An entry is questID:state or questID:state:have.need,have.need with one have.need for each
-- objective. The state is 0 (in progress), 1 (ready to turn in) or x (not in the quest log any more).
-- Only numbers are sent. The quest names come from the quest log of the receiver.

local PREFIX = "ForeverQuests"
local VERSION = "1"
local MAX_BYTES = 250
local MAX_QUESTS = 50
local MAX_OBJECTIVES = 12
local MAX_ENTRIES = 40
local MAX_MEMBERS = 40
local MAX_COUNT = 99999
local SEND_GAP = 1.2
local FULL_GAP = 10
local HELLO_GAP = 60

-- Sender -> questID -> { complete = boolean, objectives = { { have, need }, ... } }.
local members = {}
ns.party = members

local queue = {}
local sent = {} -- questID -> the entry that the party has
local known = {} -- names of the group members; empty while they are not known
local sending = false
local fullPending = false
local rosterPending = false
local wasInGroup = false
local lastFull = 0
local lastHello = -HELLO_GAP
local mutedUntil = 0
local playerName

local function inGroup()
  return IsInGroup ~= nil and IsInGroup() and true or false
end

local function canSend()
  return ns.GetOption("partyProgress") and C_ChatInfo ~= nil and C_ChatInfo.SendAddonMessage ~= nil and inGroup()
    and GetTime() >= mutedUntil
end

local function forget()
  wipe(queue)
  wipe(sent)
end

local function sendFailed(result)
  local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
  return result == false or (type(result) == "number" and result ~= success)
end

local pump

local lastSend = 0

-- At most one message in SEND_GAP seconds.
local function startPump(delay)
  if not sending then
    sending = true
    C_Timer.After(math.max(delay, lastSend + SEND_GAP - GetTime()), pump)
  end
end

pump = function()
  sending = false
  if #queue == 0 then
    return
  end
  if not canSend() then
    forget()
    return
  end
  if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
    startPump(5)
    return
  end
  local message = table.remove(queue, 1)
  lastSend = GetTime()
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, "PARTY")
  if not ok or sendFailed(result) then
    -- The client refuses addon messages in some situations. Nothing is shown; a later change tries again.
    forget()
    mutedUntil = GetTime() + 30
    return
  end
  if #queue > 0 then
    startPump(SEND_GAP)
  end
end

local function clamp(value)
  if ns.IsSecret(value) or type(value) ~= "number" or value ~= value or value < 0 then
    return 0
  end
  return math.min(math.floor(value), MAX_COUNT)
end

local function encode(questID, quest)
  local parts = {}
  for i, objective in ipairs(quest.objectives) do
    if i > MAX_OBJECTIVES then
      break
    end
    parts[i] = clamp(objective.have) .. "." .. clamp(objective.need)
  end
  local entry = questID .. ":" .. (quest.complete and "1" or "0")
  if #parts > 0 then
    entry = entry .. ":" .. table.concat(parts, ",")
  end
  return entry
end

-- Puts the entries into as many messages as they need.
local function pack(kind, entries)
  local head = VERSION .. kind
  local body = ""
  for _, entry in ipairs(entries) do
    if body ~= "" and #head + #body + 1 + #entry > MAX_BYTES then
      queue[#queue + 1] = head .. body
      head = VERSION .. (kind == "S" and "C" or kind)
      body = ""
    end
    body = body == "" and entry or (body .. ";" .. entry)
  end
  queue[#queue + 1] = head .. body
end

local function sendFull()
  forget()
  lastFull = GetTime()
  local entries = {}
  for questID, quest in pairs(ns.quests or {}) do
    if #entries >= MAX_QUESTS then
      break
    end
    local entry = encode(questID, quest)
    sent[questID] = entry
    entries[#entries + 1] = entry
  end
  pack("S", entries)
  startPump(0.1)
end

local function requestFull()
  if fullPending then
    return
  end
  fullPending = true
  C_Timer.After(math.max(1.5, lastFull + FULL_GAP - GetTime()), function()
    fullPending = false
    if canSend() then
      sendFull()
    end
  end)
end

local function sendHello()
  if not canSend() or GetTime() - lastHello < HELLO_GAP then
    return
  end
  lastHello = GetTime()
  table.insert(queue, 1, VERSION .. "H")
  startPump(0.5)
end

-- Called by Progress.lua after each comparison of the quest log.
function ns.OnQuestSnapshot(current)
  if not canSend() then
    forget()
    return
  end
  if fullPending then
    return
  end
  if #queue > 5 then
    requestFull()
    return
  end
  local entries = {}
  for questID, quest in pairs(current) do
    local entry = encode(questID, quest)
    if sent[questID] ~= entry and #entries < MAX_QUESTS then
      sent[questID] = entry
      entries[#entries + 1] = entry
    end
  end
  for questID in pairs(sent) do
    if not current[questID] then
      sent[questID] = nil
      entries[#entries + 1] = questID .. ":x"
    end
  end
  if #entries > 0 then
    pack("U", entries)
    startPump(0.1)
  end
end

-- The names of the group members as addon messages name them, or nil while a name is not known.
local function roster()
  local unit, count = "party", GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
  if IsInRaid and IsInRaid() and GetNumGroupMembers then
    unit, count = "raid", GetNumGroupMembers()
  end
  local names = {}
  for i = 1, count do
    local name, realm = UnitName(unit .. i)
    if ns.IsSecret(name) or ns.IsSecret(realm) or type(name) ~= "string" or name == UNKNOWNOBJECT then
      return nil
    end
    if type(realm) == "string" and realm ~= "" then
      name = name .. "-" .. realm
    end
    names[name] = true
  end
  return names
end

local function onRoster()
  if not inGroup() then
    wipe(members)
    wipe(known)
    forget()
    wasInGroup = false
    return
  end
  local joined = not wasInGroup
  wasInGroup = true
  local names = roster()
  if not names then
    if not rosterPending then
      rosterPending = true
      C_Timer.After(3, function()
        rosterPending = false
        onRoster()
      end)
    end
  else
    for name in pairs(members) do
      if not names[name] then
        members[name] = nil
      end
    end
    local newcomer = false
    for name in pairs(names) do
      if not known[name] and name ~= playerName then
        newcomer = true
      end
    end
    known = names
    if newcomer then
      requestFull()
    end
  end
  if joined then
    sendHello()
    requestFull()
  end
end

local function parseEntry(entry)
  local id, state, rest = entry:match("^(%d+):([01x])(.*)$")
  if not id or #id > 7 then
    return nil
  end
  id = tonumber(id)
  if id < 1 then
    return nil
  end
  if state == "x" then
    if rest ~= "" then
      return nil
    end
    return id, false
  end
  local objectives = {}
  if rest ~= "" then
    if rest:sub(1, 1) ~= ":" or rest:find(",,", 1, true) or rest:sub(-1) == "," or rest:sub(2, 2) == "," then
      return nil
    end
    for pair in rest:sub(2):gmatch("[^,]+") do
      local have, need = pair:match("^(%d+)%.(%d+)$")
      if not have or #have > 5 or #need > 5 or #objectives >= MAX_OBJECTIVES then
        return nil
      end
      objectives[#objectives + 1] = { tonumber(have), tonumber(need) }
    end
    if #objectives == 0 then
      return nil
    end
  end
  return id, { complete = state == "1", objectives = objectives }
end

local function count(list)
  local n = 0
  for _ in pairs(list) do
    n = n + 1
  end
  return n
end

local function onMessage(prefix, text, channel, sender)
  if ns.IsSecret(prefix) or prefix ~= PREFIX or not ns.GetOption("partyProgress") or not inGroup() then
    return
  end
  if ns.IsSecret(text) or ns.IsSecret(channel) or ns.IsSecret(sender) or type(text) ~= "string"
    or type(sender) ~= "string" then
    return
  end
  if (channel ~= "PARTY" and channel ~= "RAID") or #text < 2 or #text > 255 or #sender < 1 or #sender > 64 then
    return
  end
  local name = Ambiguate and Ambiguate(sender, "none") or sender
  if type(name) ~= "string" or name == playerName or sender == playerName then
    return
  end
  if next(known) and not known[name] then
    return
  end
  if text:sub(1, 1) ~= VERSION then
    return
  end
  local kind, body = text:sub(2, 2), text:sub(3)
  if kind == "H" then
    if body == "" then
      requestFull()
    end
    return
  end
  if kind ~= "S" and kind ~= "C" and kind ~= "U" then
    return
  end
  if body == "" and kind ~= "S" then
    return
  end
  -- The whole message is read before anything is stored: one bad entry drops all of it.
  local entries = {}
  for entry in body:gmatch("[^;]+") do
    local id, quest = parseEntry(entry)
    if not id or #entries >= MAX_ENTRIES then
      return
    end
    entries[#entries + 1] = { id, quest }
  end
  if body ~= "" and #entries == 0 then
    return
  end
  if not members[name] and count(members) >= MAX_MEMBERS then
    return
  end
  if kind == "S" or not members[name] then
    members[name] = {}
  end
  local quests = members[name]
  local total = count(quests)
  for _, entry in ipairs(entries) do
    local id, quest = entry[1], entry[2]
    if not quest then
      if quests[id] then
        quests[id] = nil
        total = total - 1
      end
    elseif quests[id] then
      quests[id] = quest
    elseif total < MAX_QUESTS then
      quests[id] = quest
      total = total + 1
    end
  end
end

local function describe(quest)
  if quest.complete then
    return "ready to turn in"
  end
  if #quest.objectives == 0 then
    return "in progress"
  end
  local parts = {}
  for i, objective in ipairs(quest.objectives) do
    parts[i] = objective[1] .. "/" .. objective[2]
  end
  return table.concat(parts, ", ")
end

local function sortedNames()
  local names = {}
  for name in pairs(members) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

local function addToTooltip(questID)
  if not ns.GetOption("partyProgress") or ns.IsSecret(questID) or type(questID) ~= "number" then
    return
  end
  local added = false
  for _, name in ipairs(sortedNames()) do
    local quest = members[name][questID]
    if quest then
      if not added then
        added = true
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Party progress (Forever Quests)")
      end
      GameTooltip:AddDoubleLine(name, describe(quest), 1, 1, 1, 1, 1, 1)
    end
  end
  if added then
    GameTooltip:Show()
  end
end

local function titleOf(questID)
  local quest = ns.quests and ns.quests[questID]
  if quest and quest.title then
    return quest.title
  end
  return C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID) or ("quest " .. questID)
end

-- /fq party
function ns.PrintParty()
  if not ns.GetOption("partyProgress") then
    ns.Print("party progress is off. Type /fq share to turn it on.")
    return
  end
  if not inGroup() then
    ns.Print("you are not in a party.")
    return
  end
  local names = sortedNames()
  if #names == 0 then
    ns.Print("no party member has sent quest progress. They need Forever Quests too.")
    return
  end
  ns.Print("party progress on the quests you share:")
  for _, name in ipairs(names) do
    local shared, others = {}, 0
    for questID, quest in pairs(members[name]) do
      if ns.quests and ns.quests[questID] then
        shared[#shared + 1] = { title = tostring(titleOf(questID)), progress = describe(quest) }
      else
        others = others + 1
      end
    end
    table.sort(shared, function(a, b)
      return a.title < b.title
    end)
    print(string.format("  %s: %d shared, %d that you do not have", name, #shared, others))
    for _, quest in ipairs(shared) do
      print("    " .. quest.title .. ": " .. quest.progress)
    end
  end
end

ns.OnOptionChanged(function(key, value)
  if key ~= "partyProgress" then
    return
  end
  wipe(members)
  forget()
  if value and inGroup() then
    lastHello = -HELLO_GAP
    sendHello()
    requestFull()
  end
end)

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
end

-- The game fires these when the pointer is on a quest in the quest log or on a quest in the tracker.
if EventRegistry and EventRegistry.RegisterCallback and GameTooltip then
  local owner = {}
  EventRegistry:RegisterCallback("QuestMapLogTitleButton.OnEnter", function(_, _, questID)
    if GameTooltip:IsShown() then
      pcall(addToTooltip, questID)
    end
  end, owner)
  EventRegistry:RegisterCallback("OnQuestBlockHeader.OnEnter", function(_, block, questID, grouped)
    -- The game shows a tooltip there only in a group.
    if grouped and block and GameTooltip.IsOwned and GameTooltip:IsOwned(block) then
      pcall(addToTooltip, questID)
    end
  end, owner)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
pcall(frame.RegisterEvent, frame, "GROUP_LEFT")
pcall(frame.RegisterEvent, frame, "CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    onMessage(...)
    return
  end
  if event == "PLAYER_ENTERING_WORLD" and not playerName then
    local name = UnitName("player")
    if not ns.IsSecret(name) and type(name) == "string" then
      playerName = name
    end
  end
  onRoster()
end)
