-- Loads one addon in the stand-in for the game (files 01 to 04) and uses everything it has.
--
-- addon = { name = "ForeverQuests", files = { { name = "Core.lua", source = "..." }, ... },
--           saved = { "ForeverQuestsDB", ... }, savedSource = "ForeverQuestsDB = {...}" or nil,
--           scenario = "Lua source" or nil }
--
-- Returns { failures, caught, absent, saved, counts, coverage, printed }
--   failures: errors that reached the game. In the game each one is a Lua error on the screen.
--   caught:   errors that a pcall of the addon caught. The addon goes on, but a part of it did
--             not do its work. Some are meant (a test for a part of the game that is absent).
--   absent:   names that the addon looked for and that are not there.
--   printed:  each line that the addon printed to the chat, in order.

local H, addon = ...
local realPcall, realType, realTostring = pcall, H.realType, H.realTostring
local unpack = unpack
local getinfo = H.debug.getinfo
local secrets = H.secrets

local failures, caught = {}, {}
local seenFailure, seenCaught = {}, {}
local phase = "load"
local counts = { files = 0, frames = 0, events = 0, commands = 0, scripts = 0, menuActions = 0, checks = 0 }

-- A text for an error value. An error can be a table: its address would differ on each run.
local function clean(err)
  if realType(err) ~= "string" then
    if secrets[err] ~= nil then
      return "(the error value is a secret value)"
    end
    return "(the error value is a " .. realType(err) .. ")"
  end
  return (err:gsub("%[string \"([^\"]+)\"%]", "%1"))
end

-- Errors that an addon raises on purpose (a test command of the addon): H.expectError(text)
-- names a text; an error whose text contains it is counted in H.expectedErrors, not a failure.
-- The registration holds for the whole run: every phase, the sweeps included.
H.expectedErrors = { texts = {}, count = 0 }
function H.expectError(text)
  H.expectedErrors.texts[#H.expectedErrors.texts + 1] = text
end

local function fail(where, err)
  local text = clean(err)
  for _, expected in ipairs(H.expectedErrors.texts) do
    if text:find(expected, 1, true) then
      H.expectedErrors.count = H.expectedErrors.count + 1
      return
    end
  end
  -- Two different places with the same message are two failures.
  local key = phase .. "\0" .. where .. "\0" .. text
  if not seenFailure[key] then
    seenFailure[key] = true
    failures[#failures + 1] = string.format("[%s] %s: %s", phase, where, text)
  end
end
H.onError = fail

-- Runs fn and records an error as a failure. The error goes through the game's error handler
-- first (geterrorhandler, as the game calls it): ScriptErrorsFrame sees it with its stack, and then
-- the handler records it as a failure (H.onError), named by `where`.
function H.call(where, fn, ...)
  -- An addon that did not come to an end twice is not called again (see the line hook below).
  if H.stuck and H.stuck() then
    return false
  end
  local ok, err = realPcall(fn, ...)
  if not ok then
    H.errorWhere = where
    geterrorhandler()(err)
    H.errorWhere = nil
  end
  return ok
end
local call = H.call

-- The file and line of the addon code that called the function that calls this.
local function callerPlace()
  local level = 3
  while true do
    local info = getinfo(level, "Sl")
    if not info then
      return "(place not known)"
    end
    if info.what ~= "C" and info.currentline > 0 and not info.source:find("^=harness/") then
      return info.short_src .. ":" .. info.currentline
    end
    level = level + 1
  end
end

local function noteCaught(err)
  local text = callerPlace() .. ": caught: " .. clean(err)
  local key = phase .. "\0" .. text
  if not seenCaught[key] then
    seenCaught[key] = true
    caught[#caught + 1] = string.format("[%s] %s", phase, text)
  end
end

-- The pcall and xpcall that the addon sees: they work as in the game, and they note each error
-- that they catch, with the place of the call. Every result is kept, also a nil.
function pcall(fn, ...)
  local n, results = H.pack(realPcall(fn, ...))
  if not results[1] then
    noteCaught(results[2])
  end
  return unpack(results, 1, n)
end
function xpcall(fn, handler, ...)
  local arguments, count = { ... }, select("#", ...)
  local n, results = H.pack(realPcall(function()
    return fn(unpack(arguments, 1, count))
  end))
  if results[1] then
    return unpack(results, 1, n)
  end
  noteCaught(results[2])
  if realType(handler) == "function" then
    return false, handler(results[2])
  end
  return false, results[2]
end

-- A check of a scenario.
local function expect(condition, what)
  counts.checks = counts.checks + 1
  if not condition then
    fail("scenario", "expected: " .. realTostring(what))
  end
end

---------------------------------------------------------------------------------------------------
-- Saved variables: written as Lua source, so that the second run reads what the first run saved.
--
-- The game saves numbers, texts, booleans and tables with number or text keys. Anything else in
-- a saved variable is lost at logout, so it is a failure here.

local function serialize(value, path, depth, seen)
  local kind = realType(value)
  if secrets[value] ~= nil then
    fail("saved variables", path .. " is a secret value. The game cannot save it")
    return "nil"
  elseif kind == "table" then
    if seen[value] then
      fail("saved variables", path .. " contains itself. The game cannot save that")
      return "nil"
    end
    if depth > 40 then
      fail("saved variables", path .. " is more than 40 tables deep")
      return "nil"
    end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do
      local keyKind = realType(key)
      if secrets[key] ~= nil then
        fail("saved variables", path .. " has a secret value as a key")
      elseif keyKind == "number" or keyKind == "string" then
        keys[#keys + 1] = key
      elseif keyKind ~= "boolean" then
        fail("saved variables", path .. " has a " .. keyKind .. " as a key. The game cannot save it")
      end
    end
    table.sort(keys, function(a, b)
      if realType(a) ~= realType(b) then
        return realType(a) == "number"
      end
      return a < b
    end)
    local parts = {}
    for _, key in ipairs(keys) do
      local name = realType(key) == "number" and ("[" .. serialize(key, path, depth, seen) .. "]") or ("[" .. string.format("%q", key) .. "]")
      parts[#parts + 1] = name .. "=" .. serialize(value[key], path .. "." .. realTostring(key), depth + 1, seen)
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
  elseif kind == "string" then
    return string.format("%q", value)
  elseif kind == "number" then
    if value ~= value then
      return "(0/0)"
    elseif value == math.huge then
      return "math.huge"
    elseif value == -math.huge then
      return "(-math.huge)"
    end
    return string.format("%.17g", value)
  elseif kind == "boolean" then
    return realTostring(value)
  elseif kind == "nil" then
    return "nil"
  end
  fail("saved variables", path .. " is a " .. kind .. ". The game cannot save it")
  return "nil"
end

local function savedSource()
  local parts = {}
  for _, name in ipairs(addon.saved) do
    parts[#parts + 1] = name .. " = " .. serialize(rawget(_G, name), name, 0, {})
  end
  return table.concat(parts, "\n")
end

-- A secret value as a table key is an error in the game. Lua 5.1 cannot catch it when it
-- happens, so the tables of the addon are searched after each phase.
local namespace = {}
local function findSecretKeys()
  local seen = {}
  local function walk(value, path, depth)
    if realType(value) ~= "table" or seen[value] or depth > 12 or H.isWidget(value) then
      return
    end
    seen[value] = true
    for key, entry in pairs(value) do
      if secrets[key] ~= nil then
        fail("secret value", "a secret value is a key of the table " .. path .. ". In the game that is an error")
        return
      end
      walk(entry, path .. "." .. realTostring(H.plain(key)), depth + 1)
    end
  end
  walk(namespace, "ns", 0)
  for _, name in ipairs(addon.saved) do
    walk(rawget(_G, name), name, 0)
  end
end

---------------------------------------------------------------------------------------------------
-- Events

-- The arguments of an event. The documentation gives the kind of each one; a few events get
-- values that mean something in the world of the stand-in.
local function known(event)
  local link = H.itemLink(2589)
  local payloads = {
    ADDON_LOADED = { addon.name, false },
    PLAYER_ENTERING_WORLD = { false, true },
    GET_ITEM_INFO_RECEIVED = { 2589, true },
    COMMODITY_SEARCH_RESULTS_UPDATED = { 2589 },
    ITEM_SEARCH_RESULTS_UPDATED = { { itemID = 2589, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } },
    AUCTION_HOUSE_BROWSE_RESULTS_ADDED = { { { itemKey = { itemID = 769 }, minPrice = 38, totalQuantity = 3 } } },
    QUEST_TURNED_IN = { 40, 450, 1200 },
    QUEST_ACCEPTED = { 61 },
    QUEST_REMOVED = { 40, false },
    BAG_UPDATE = { 0 },
    UNIT_INVENTORY_CHANGED = { "player" },
    CHAT_MSG_SYSTEM = { "A buyer has been found for your auction of " .. link .. "." },
  }
  return payloads[event]
end

local function payloadOf(event)
  local values = known(event)
  if values then
    return values, #values
  end
  local out, n = {}, 0
  for _, entry in ipairs(H.parseCodes(H.knownEvents[event] or "")) do
    n = n + 1
    if not entry.optional then
      local kind = entry.kind
      -- A table has the fields of its documented structure, as a result of a function has.
      out[n] = kind == "n" and 1 or kind == "s" and "player" or kind == "b" and false or kind == "t" and H.defaultOf(entry, 0) or nil
    end
  end
  return out, n
end

local function fire(event, ...)
  -- A handler can make a frame: the list is read before the handlers run.
  local targets = {}
  for _, frame in ipairs(H.frames) do
    if H.state(frame).events[event] then
      targets[#targets + 1] = frame
    end
  end
  for _, frame in ipairs(targets) do
    call(event, H.run, frame, "OnEvent", event, ...)
  end
  return #targets
end
-- The stand-in fires an event of the game from its own functions (04-world.lua, ADDON_ACTION_BLOCKED).
H.fire = fire

local function runMenus()
  -- An action of a menu can open a menu: a few rounds, with a limit.
  for _ = 1, 3 do
    local menus = H.menus
    H.menus = {}
    for _, actions in ipairs(menus) do
      for _, action in ipairs(actions) do
        counts.menuActions = counts.menuActions + 1
        call("menu action", action)
      end
    end
    if #H.menus == 0 then
      break
    end
  end
  H.menus = {}
end

---------------------------------------------------------------------------------------------------
-- Frames
--
-- Each frame of the addon is used as a player can use it. Where the game changes a state before
-- it runs a script (shown, checked, the value of a slider, the text of an edit box), the driver
-- changes the state too. A player can use only what is on the screen: for a frame in a window
-- that is closed, the window opens first (with its OnShow scripts) and closes again after.

local function script(frame, name, ...)
  if H.state(frame).scripts[name] then
    counts.scripts = counts.scripts + 1
    call(name, H.run, frame, name, ...)
    runMenus()
  end
end

local use

local function poke(frame)
  -- The frame itself and the frames above it that are hidden, the top one first.
  local hidden = {}
  local at = frame
  while at do
    if not H.state(at).shown then
      table.insert(hidden, 1, at)
    end
    at = H.state(at).parent
  end
  for _, window in ipairs(hidden) do
    call("opening the window", window.Show, window)
  end
  runMenus()
  use(frame)
  for index = #hidden, 1, -1 do
    call("closing the window", hidden[index].Hide, hidden[index])
  end
end

function use(frame)
  local s = H.state(frame)
  local scripts = s.scripts
  -- Shown and hidden, back to the state of before.
  if scripts.OnShow or scripts.OnHide then
    counts.scripts = counts.scripts + 1
    call("show and hide", function()
      if frame:IsShown() then
        frame:Hide()
        frame:Show()
      else
        frame:Show()
        frame:Hide()
      end
    end)
    runMenus()
  end
  for _, elapsed in ipairs({ 0.02, 1, 30 }) do
    script(frame, "OnUpdate", elapsed)
  end
  script(frame, "OnEnter", true)
  script(frame, "OnLeave", true)
  script(frame, "OnMouseWheel", 1)
  script(frame, "OnMouseWheel", -1)
  for _, button in ipairs({ "LeftButton", "RightButton" }) do
    script(frame, "OnMouseDown", button)
    script(frame, "OnMouseUp", button, true)
  end
  if s.class.scripts.OnClick and (scripts.OnClick or scripts.PreClick or scripts.PostClick) and not s.disabled then
    for _, button in ipairs({ "LeftButton", "RightButton", "LeftButton", "RightButton" }) do
      counts.scripts = counts.scripts + 1
      call("click", H.click, frame, button, false)
      runMenus()
    end
  end
  script(frame, "OnDoubleClick", "LeftButton")
  script(frame, "OnDragStart", "LeftButton")
  script(frame, "OnDragStop")
  script(frame, "OnReceiveDrag")
  script(frame, "OnSizeChanged", s.width, s.height)
  -- Keys, for a frame that takes them.
  script(frame, "OnKeyDown", "ESCAPE")
  script(frame, "OnKeyUp", "ESCAPE")
  script(frame, "OnChar", "a")
  script(frame, "OnHyperlinkEnter", "item:2589", "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r")
  script(frame, "OnHyperlinkClick", "item:2589", "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r", "LeftButton")
  script(frame, "OnHyperlinkLeave")
  script(frame, "OnVerticalScroll", 0)
  script(frame, "OnCooldownDone")
  script(frame, "OnTooltipCleared")
  if s.kind == "Slider" and scripts.OnValueChanged then
    local before = s.value
    for _, value in ipairs({ s.min, (s.min + s.max) / 2, s.max, before }) do
      counts.scripts = counts.scripts + 1
      call("drag of the slider", H.setSliderValue, frame, value, true)
    end
  end
  if s.class.scripts.OnTextChanged then
    local before = frame:GetText()
    call("typing", function()
      frame:SetFocus()
      frame:SetText("linen")
    end)
    script(frame, "OnTextChanged", true)
    script(frame, "OnTabPressed")
    script(frame, "OnSpacePressed")
    script(frame, "OnEnterPressed")
    script(frame, "OnEscapePressed")
    call("typing", function()
      frame:SetText(before)
    end)
    -- Enter in the box as it was before, which for most boxes is empty.
    script(frame, "OnEnterPressed")
    call("typing", function()
      frame:ClearFocus()
    end)
  end
  -- Textures and font strings can have mouse scripts too.
  for _, region in ipairs(s.regions) do
    script(region, "OnEnter", true)
    script(region, "OnLeave", true)
    for _, button in ipairs({ "LeftButton", "RightButton" }) do
      script(region, "OnMouseDown", button)
      script(region, "OnMouseUp", button, true)
    end
  end
  -- An animation that the use of the frame started comes to its end.
  local playing = H.playing or {}
  H.playing = {}
  for _, group in ipairs(playing) do
    counts.scripts = counts.scripts + 1
    call("the end of an animation", H.finishAnimation, group)
  end
end

-- Uses every frame of the addon from index `from`. Frames that this makes are for the next round.
local function pokeFrames(from)
  local last = #H.frames
  for index = from, last do
    local frame = H.frames[index]
    if not H.gameFrameSet[frame] then
      poke(frame)
    end
  end
  return last + 1
end

---------------------------------------------------------------------------------------------------
-- Slash commands

local function runCommands()
  local names = {}
  for name in pairs(SlashCmdList) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local handler = SlashCmdList[name]
    local slash = rawget(_G, "SLASH_" .. name .. "1")
    if realType(slash) ~= "string" then
      fail("slash command", "SlashCmdList." .. name .. " has no SLASH_" .. name .. "1")
      slash = "/" .. name
    end
    -- The words of the help text are the commands of the addon.
    local words, seen = { "", "help" }, { [""] = true, help = true }
    local function add(word)
      if not seen[word] then
        seen[word] = true
        words[#words + 1] = word
      end
    end
    local before = #H.printed
    call(slash .. " help", handler, "help")
    for index = before + 1, #H.printed do
      local line = H.printed[index]
      -- "/fah scan - ..." and also "/fmeter dps, damage, hps - ..." and "  accept - ...".
      for word in line:gmatch("/%w+ ([%a]+)") do
        add(word)
      end
      local list = line:match("/%w+ ([%a, ]+) %- ")
      for word in (list or ""):gmatch("%a+") do
        add(word)
      end
      local first = line:match("^%s+(%a+) %- ")
      if first then
        add(first)
      end
    end
    -- An odd number of calls for each word: a command that turns an option on or off leaves it
    -- changed, so the phases after this one run with the options the other way.
    local arguments = { "", " 5", " " .. H.itemLink(2589) .. " 5g", " solo 4", " 45.2 61.8" }
    for _, word in ipairs(words) do
      for _, argument in ipairs(arguments) do
        counts.commands = counts.commands + 1
        call(slash .. " " .. word .. argument, handler, word .. argument)
        runMenus()
      end
    end
  end
end

---------------------------------------------------------------------------------------------------
-- One pass: everything the addon has, in the state of the world as it is now

local LOGIN_EVENTS = { ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_LOGOUT = true }
local FIGHT_EVENTS = { PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true }

local bagButton -- a bag slot of the game, as the owner of an item tooltip

local function useEverything(suffix)
  local function enter(name)
    phase = name .. suffix
  end

  enter("settings")
  for _, panel in ipairs(H.settingsPanels) do
    call("settings page", function()
      panel:Hide()
      panel:Show()
    end)
  end

  enter("commands")
  runCommands()
  H.advance(2)

  enter("game windows")
  -- The game builds its quest log: the hooks of the addon run after it.
  call("QuestLogQuests_Update", QuestLogQuests_Update)
  -- The game lays out its quest tracker: the hooks of the addon run after it.
  call("QuestObjectiveTracker:Update", QuestObjectiveTracker.Update, QuestObjectiveTracker)
  -- A click on the world map, without and with the Alt key.
  for _, alt in ipairs({ false, true }) do
    H.world.alt = alt
    for _, handler in ipairs(H.canvasClickHandlers) do
      call("click on the world map", handler, WorldMapFrame, "LeftButton", 0.4, 0.6)
    end
  end
  H.world.alt = false
  -- The bag key, and a bag of the character and of the bank by number.
  for _, name in ipairs(H.bagFunctions) do
    call(name, _G[name])
  end
  for _, bag in ipairs({ 0, 3, 7 }) do
    call("ToggleBag", ToggleBag, bag)
    call("OpenBag", OpenBag, bag)
    call("CloseBag", CloseBag, bag)
  end
  -- The auction house opens: the game loads its window, then says so.
  H.openAuctionHouse()
  fire("AUCTION_HOUSE_SHOW")
  -- The pointer on a quest in the quest log and on a quest in the tracker.
  call("quest tooltip", function()
    GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
    EventRegistry:TriggerEvent("QuestMapLogTitleButton.OnEnter", H.questLogFrames[2], 176)
    EventRegistry:TriggerEvent("OnQuestBlockHeader.OnEnter", UIParent, 176, true)
    GameTooltip:Hide()
  end)
  H.advance(1)

  enter("frames")
  local nextFrame = H.gameFrames + 1
  for _ = 1, 3 do
    nextFrame = pokeFrames(nextFrame)
    H.advance(2)
  end

  enter("events")
  -- Each event that the addon listens to, with arguments of the documented kinds.
  local events, seen = {}, {}
  for _, frame in ipairs(H.frames) do
    for event in pairs(H.state(frame).events) do
      if not seen[event] and not LOGIN_EVENTS[event] and not FIGHT_EVENTS[event] then
        seen[event] = true
        events[#events + 1] = event
      end
    end
  end
  table.sort(events)
  for _, event in ipairs(events) do
    counts.events = counts.events + 1
    local values, n = payloadOf(event)
    -- In a fight the arguments are secret where the documentation says so.
    H.concealPayload(event, values, n)
    fire(event, unpack(values, 1, n))
    H.advance(1)
  end
  -- A message of another player with the addon, for each prefix that the addon listens to.
  for _, entry in ipairs(H.did) do
    if entry[1] == "prefix" then
      fire("CHAT_MSG_ADDON", entry[2], "1H", "PARTY", "Friend", "Friend", 0, 0, "", 0)
    end
  end
  -- A change in the quest log, for the code that compares two states of it.
  H.questProgress = H.questProgress + 1
  fire("QUEST_LOG_UPDATE")
  H.advance(2)
  call("QuestLogQuests_Update", QuestLogQuests_Update)
  H.advance(8)
  call("QuestLogQuests_Update", QuestLogQuests_Update)

  enter("tooltips")
  -- The tooltip of each item: of a link, and of a slot of the bags.
  for _, postCall in ipairs(H.postCalls) do
    for _, owner in ipairs({ UIParent, bagButton }) do
      for itemID in pairs(H.items) do
        call("item tooltip", function()
          GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
          GameTooltip:SetItemByID(itemID)
          postCall.fn(GameTooltip, { id = itemID, type = postCall.kind })
          GameTooltip:Hide()
        end)
      end
    end
    call("item tooltip", postCall.fn, GameTooltip, { id = 999999, type = postCall.kind })
  end

  enter("frames again")
  -- A second time, now that windows are open and have data.
  pokeFrames(H.gameFrames + 1)
  H.advance(2)
  findSecretKeys()
end

---------------------------------------------------------------------------------------------------
-- Coverage: which lines of the addon ran. The same hook stops an addon that does not end.

local hits = {} -- [chunk name] = { [line] = true }
-- The limit is for one stretch of addon code without a step of the driver between: an endless
-- loop ends with an error after CALL_LIMIT lines, in a handler that is called again too, and
-- inside a pcall of the addon (the error comes again at the next line). The hook stays in place.
-- After two such stops the addon is not called again: one failure says so.
local lineCount, LINE_LIMIT = 0, 60000000
local stretch, CALL_LIMIT = 0, 3000000
local stops = 0
function H.stuck()
  return stops >= 2 or lineCount > LINE_LIMIT
end
local realCall = H.call
function H.call(where, fn, ...)
  stretch = 0
  local ok = realCall(where, fn, ...)
  stretch = 0
  return ok
end
call = H.call
H.debug.sethook(function(_, line)
  local source = getinfo(2, "S").source
  lineCount = lineCount + 1
  stretch = stretch + 1
  if (stretch > CALL_LIMIT or lineCount > LINE_LIMIT) and not source:find("^=harness/") then
    if stretch > CALL_LIMIT then
      stops, stretch = stops + 1, CALL_LIMIT - 1000
    end
    error("the addon does not come to an end: more than " .. CALL_LIMIT .. " lines ran without a pause", 2)
  end
  local lines = hits[source]
  if not lines then
    lines = {}
    hits[source] = lines
  end
  lines[line] = true
end, "l")

-- True for a line with code that can run: not empty, not a comment, not only the end of a block,
-- and not the first line of a function (Lua counts the making of a function at its last line).
local function isCode(line)
  local text = line:gsub("%-%-.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then
    return false
  end
  if text:find("^local%s+function%s") or text:find("^function%s") or text:find("function%s*%b()$") then
    return false
  end
  local only = text:gsub("[%s,;%)%}%]]", "")
  return not (only == "" or only == "end" or only == "else" or only == "do" or only == "then" or only == "{" or only == "(")
end

-- For each file: the number of code lines, how many of them ran, and the lines that did not run.
local function coverage()
  local files = {}
  for _, file in ipairs(addon.files) do
    local ran = hits["=" .. addon.name .. "/" .. file.name] or {}
    local total, hit, missed = 0, 0, {}
    local number = 0
    for line in (file.source:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
      number = number + 1
      if isCode(line) then
        total = total + 1
        if ran[number] then
          hit = hit + 1
        else
          missed[#missed + 1] = number
        end
      end
    end
    files[#files + 1] = { name = file.name, total = total, hit = hit, missed = missed }
  end
  return files
end

---------------------------------------------------------------------------------------------------
-- Names that the addon looks for and that are not there. An addon tests for a part of the game
-- with `if Name then`, and with the name absent it leaves that part out without an error. Each
-- name here is one of two things: a part of the game that the stand-in lacks, or a name that
-- the game does not have, in which case the code behind the test never runs.

local absent, seenAbsent = {}, {}
local function note(name)
  if not seenAbsent[name] then
    seenAbsent[name] = true
    absent[#absent + 1] = name
  end
end
local savedNames = {}
for _, name in ipairs(addon.saved) do
  savedNames[name] = true
end
setmetatable(_G, {
  __index = function(_, key)
    if realType(key) == "string" and not savedNames[key] and not key:find("^SLASH_") then
      -- Only a look by the addon counts, not one by the stand-in or the driver.
      local info = getinfo(2, "S")
      if info and not info.source:find("^=harness/") then
        note(key)
      end
    end
    return nil
  end,
})
for name, value in pairs(_G) do
  if realType(value) == "table" and name:find("^C_") and getmetatable(value) == nil then
    setmetatable(value, {
      __index = function(_, key)
        note(name .. "." .. realTostring(key))
        return nil
      end,
    })
  end
end

---------------------------------------------------------------------------------------------------
-- The run

-- A bag slot of the game, as the owner of an item tooltip: its parent has the number of the
-- bag, as in the bag window of the game.
do
  local bag = CreateFrame("Frame", nil, UIParent)
  bag:SetID(0)
  bagButton = CreateFrame("ItemButton", nil, bag, "ContainerFrameItemButtonTemplate")
  bagButton:SetID(2)
  H.gameFrameSet[bag], H.gameFrameSet[bagButton] = true, true
end

-- Replaced functions. An addon that puts its own function in the place of a global function of
-- the game makes the game's own code run addon code. The game then counts what follows as
-- addon code, and refuses the actions that only its own UI may do (buying a bank slot, casting,
-- using an item in a fight) with "blocked from an action only available to the Blizzard UI".
-- hooksecurefunc is the way that the game allows. This list has each global function of the
-- game before the addon loads; replacedFunctions() compares.
local gameFunctions = {}
for name, value in pairs(_G) do
  if realType(name) == "string" and realType(value) == "function" then
    gameFunctions[name] = value
  end
end
local function replacedFunctions()
  local names = {}
  for name, original in pairs(gameFunctions) do
    local now = rawget(_G, name)
    -- A hook keeps the game's function under it.
    while H.hookedOriginal and H.hookedOriginal[now] do
      now = H.hookedOriginal[now]
    end
    if now ~= original then
      names[#names + 1] = name
      gameFunctions[name] = nil -- one failure for each name
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    fail("taint", "the addon put its own function in the place of the game's " .. name .. ": the game then refuses actions that only its own UI may do. Use hooksecurefunc(\"" .. name .. "\", ...)")
  end
end

-- The game loads the files of the addon, then its saved variables, then sends ADDON_LOADED.
for _, file in ipairs(addon.files) do
  counts.files = counts.files + 1
  local chunk, err = loadstring(file.source, "=" .. addon.name .. "/" .. file.name)
  if not chunk then
    fail(file.name, err)
  else
    call(file.name, chunk, addon.name, namespace)
  end
end
if addon.savedSource then
  local chunk, err = loadstring(addon.savedSource, "=saved variables")
  if chunk then
    call("saved variables", chunk)
  else
    fail("saved variables", err)
  end
end

-- The errors that an addon raises on purpose, by its test command (H.expectError). They are
-- named here, not only in its scenario: a run after a reload does not run the scenario.
local EXPECTED_ERRORS = {
  ForeverTrace = { "raised on purpose by /ftrace test" },
}
for _, text in ipairs(EXPECTED_ERRORS[addon.name] or {}) do
  H.expectError(text)
end

phase = "login"
fire("ADDON_LOADED", addon.name, false)
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)
H.advance(5)
replacedFunctions()

-- The scenario of the addon: what only this addon does, with checks of the results. It is for
-- a first login: after a reload the saved data is what the first run left.
if addon.scenario and not addon.savedSource then
  phase = "scenario"
  local chunk, err = loadstring(addon.scenario, "=harness/scenarios/" .. addon.name .. ".lua")
  if not chunk then
    fail("scenario", err)
  else
    local T = {
      H = H, ns = namespace, world = H.world, fire = fire, advance = H.advance, expect = expect,
      runMenus = runMenus,
      slash = function(command, text)
        for name, handler in pairs(SlashCmdList) do
          if rawget(_G, "SLASH_" .. name .. "1") == command or rawget(_G, "SLASH_" .. name .. "2") == command then
            call(command .. " " .. (text or ""), handler, text or "")
            return
          end
        end
        fail("scenario", "no slash command " .. realTostring(command))
      end,
      printed = function(pattern)
        for _, line in ipairs(H.printed) do
          if line:find(pattern) then
            return line
          end
        end
      end,
    }
    call("scenario", chunk, T)
  end
  H.advance(5)
end

useEverything("")

-- In a party.
H.world.group = "party"
phase = "party"
fire("GROUP_ROSTER_UPDATE")
H.advance(5)
useEverything(" (in a party)")

-- In a fight, in a raid: the numbers of the fight, and the name of an NPC, are secret values.
H.world.group = "raid"
H.world.secret = true
H.world.npc = "Marshal Dughan"
phase = "fight"
fire("GROUP_ROSTER_UPDATE")
fire("PLAYER_REGEN_DISABLED")
H.advance(2)
useEverything(" (in a fight)")
H.world.secret = false
phase = "after the fight"
fire("PLAYER_REGEN_ENABLED")
H.advance(5)
H.world.group = nil
fire("GROUP_ROSTER_UPDATE")
H.advance(5)

-- The game sends PLAYER_LOGOUT, then saves the variables.
replacedFunctions()
phase = "logout"
fire("PLAYER_LOGOUT")
local saved = savedSource()

-- What the stand-in itself got wrong against the documentation: the results of hand-written
-- functions (H.problems in 01-api.lua) and the widget kinds (H.selfCheck in 02-widgets.lua).
phase = "stand-in"
for _, text in ipairs(H.selfCheck()) do
  fail("conformance", text)
end
for _, text in ipairs(H.problems) do
  fail("conformance", text)
end

counts.frames = #H.frames - H.gameFrames
H.debug.sethook()
setmetatable(_G, nil)
table.sort(absent)
return { failures = failures, caught = caught, absent = absent, saved = saved, counts = counts, coverage = coverage(), printed = H.printed }
