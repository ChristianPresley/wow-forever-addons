local _, ns = ...

-- Learning nodes from the player's own gathering.
--
-- The client has no combat log for addons, and no list of nodes. A gather is a spell of the
-- player: UNIT_SPELLCAST_SENT names the target (the node, "Peacebloom"), and
-- UNIT_SPELLCAST_SUCCEEDED with the same cast says that it worked. At that moment the player
-- stands at the node, so the node is where the player is.
--
-- A chest and a quest object are opened with the same spell ("Opening"). What tells them apart
-- is the loot: a chest gives a loot window without a quest item. A quest object gives a quest
-- item, or no loot window at all (a tombstone). So the thing is recorded when its loot shows,
-- at the place of the cast, and not before: as treasure, or as a quest object with a quest
-- item in the loot. Without a loot window nothing is recorded.

-- The spells of gathering, by spell ID (each rank), and by name as a fallback.
local SPELLS = {
  [2366] = "herb", [2368] = "herb", [3570] = "herb", [11993] = "herb",
  [2575] = "ore", [2576] = "ore", [3564] = "ore", [10248] = "ore",
  [7620] = "fish", [7731] = "fish", [7732] = "fish", [18248] = "fish",
  [3365] = "treasure", [6247] = "treasure", [6477] = "treasure", [6478] = "treasure", [21248] = "treasure", [22810] = "treasure",
}
local SPELL_NAMES = { ["Herb Gathering"] = "herb", ["Mining"] = "ore", ["Fishing"] = "fish", ["Opening"] = "treasure" }
-- The first rank of each: its name in the language of the client is a name of the kind too.
local NAMED_BY = { [2366] = "herb", [2575] = "ore", [7620] = "fish", [3365] = "treasure" }

-- Two nodes of the same name nearer than this (a part of the map) are one node. Fish are caught
-- anywhere along a shore, so their places merge over a wider span.
local SAME = { herb = 0.004, ore = 0.004, treasure = 0.004, quest = 0.004, fish = 0.012 }
ns.SAME = SAME
-- The loot of a fishing cast shows when the fish bites: up to this long after the cast.
local FISH_LOOT_SECONDS = 35
-- A node keeps the counts of at most this many different items.
local LOOT_ITEMS = 12
-- A cast that does not succeed within this many seconds is forgotten.
local PENDING_SECONDS = 30
-- The loot of an opened thing shows within this many seconds of the cast.
local LOOT_SECONDS = 5

local function spellName(spellID)
  local name = C_Spell.GetSpellName(spellID)
  return ns.PlainString(name) and name or nil
end

function ns.KindOfSpell(spellID)
  if not ns.Usable(spellID) then
    return nil
  end
  local kind = SPELLS[spellID]
  if kind then
    return kind
  end
  local name = spellName(spellID)
  return name and (SPELL_NAMES[name] or ns.LocalNames()[name]) or nil
end

-- The names of the gathering spells in the language of the client: { [name] = kind }. A name
-- that two kinds share tells nothing and is left out.
local localNames
function ns.LocalNames()
  if localNames then
    return localNames
  end
  local names, shared = {}, {}
  for spellID, kind in pairs(NAMED_BY) do
    local name = spellName(spellID)
    if name then
      if names[name] and names[name] ~= kind then
        shared[name] = true
      end
      names[name] = kind
    end
  end
  for name in pairs(shared) do
    names[name] = nil
  end
  localNames = names
  return names
end

-- Remembers a gather of kind at a place: the given one, or the player's. Returns the node and
-- its map, or nil and the reason without a place.
function ns.Record(kind, name, mapID, x, y)
  if not ForeverGatherDB or not ns.KIND[kind] then
    return nil, "the addon is not ready"
  end
  if not mapID then
    mapID, x, y = ns.PlayerPosition()
    if not mapID then
      return nil, x
    end
  end
  if not ns.PlainString(name) then
    name = kind == "fish" and "Fishing spot" or ns.KIND[kind].name
  end
  local nodes = ForeverGatherDB.nodes
  nodes[mapID] = nodes[mapID] or {}
  local list = nodes[mapID]
  local found = ns.FindNode(list, kind, name, x, y)
  if found then
    -- The place moves toward the average of the gathers there. The first gather of an imported
    -- node puts it where the player stands.
    local count = found.count + 1
    found.x = found.x + (x - found.x) / count
    found.y = found.y + (y - found.y) / count
    found.count = count
    found.first = found.first or time()
    found.last = time()
  else
    found = { kind = kind, name = name, x = x, y = y, count = 1, first = time(), last = time() }
    list[#list + 1] = found
  end
  local entry = ForeverGatherDB.names[name]
  if type(entry) ~= "table" then
    entry = { kind = kind }
    ForeverGatherDB.names[name] = entry
  end
  local rank = ns.SkillRank(ns.KIND[kind].skill)
  if rank and (not entry.skill or rank < entry.skill) then
    entry.skill = rank
  end
  ns.CountInSession(kind, name)
  ns.Changed()
  return found, mapID
end

-- The node of a list with this kind and name at this place, or nil.
function ns.FindNode(list, kind, name, x, y)
  local same = SAME[kind]
  for _, node in ipairs(list) do
    if node.kind == kind and node.name == name and math.abs(node.x - x) < same and math.abs(node.y - y) < same then
      return node
    end
  end
  return nil
end

-- The gathers since the first one after login: { start = GetTime(), total = n, kinds = { [kind] = n },
-- names = { [name] = n } }. Not saved.
local session = { total = 0, kinds = {}, names = {} }
function ns.CountInSession(kind, name)
  session.start = session.start or GetTime()
  session.total = session.total + 1
  session.kinds[kind] = (session.kinds[kind] or 0) + 1
  session.names[name] = (session.names[name] or 0) + 1
end
function ns.Session()
  return session
end
function ns.ResetSession()
  session = { total = 0, kinds = {}, names = {} }
end

-- Adds the items of the loot window to what the node gave.
function ns.CountLoot(node)
  local count = GetNumLootItems()
  if not ns.Usable(count) then
    return
  end
  local loot = node.loot or {}
  local different = 0
  for _ in pairs(loot) do
    different = different + 1
  end
  local any = false
  for slot = 1, count do
    local _, item, quantity = GetLootSlotInfo(slot)
    -- Money has the quantity 0.
    if ns.PlainString(item) and ns.Usable(quantity) and quantity > 0 then
      if loot[item] or different < LOOT_ITEMS then
        if not loot[item] then
          different = different + 1
        end
        loot[item] = (loot[item] or 0) + quantity
        any = true
      end
    end
  end
  if any then
    node.loot = loot
    node.looted = (node.looted or 0) + 1
  end
end

-- What a node gave, the most first: { { item = s, count = n }, ... }.
function ns.LootOf(node)
  local out = {}
  for item, count in pairs(type(node.loot) == "table" and node.loot or {}) do
    out[#out + 1] = { item = item, count = count }
  end
  table.sort(out, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.item < b.item
  end)
  return out
end

-- How hard a node is for the player's skill: a word and a colour, or nil where it is not known.
-- The skill that the node was first gathered at stands for the skill that it needs.
function ns.Difficulty(node)
  local learned = ns.LearnedSkill(node.name)
  local rank = ns.SkillRank(ns.KIND[node.kind].skill)
  if not learned or not rank then
    return nil
  end
  local over = rank - learned
  if over < 0 then
    return "needs more skill", 1, 0.1, 0.1
  elseif over < 25 then
    return "orange", 1, 0.5, 0.25
  elseif over < 50 then
    return "yellow", 1, 1, 0
  elseif over < 100 then
    return "green", 0.25, 0.75, 0.25
  end
  return "grey", 0.5, 0.5, 0.5
end

-- True for a node that was gathered within the minutes of the option "dimMinutes".
function ns.RecentlyGathered(node)
  local minutes = ns.GetOption("dimMinutes")
  return minutes > 0 and type(node.last) == "number" and time() - node.last < minutes * 60
end

-- What is known on a map, by name: { { name, kind, nodes, gathers, skill }, ... }, the lowest
-- skill first, then by name.
function ns.ZoneList(mapID)
  local byName, out = {}, {}
  local list = ForeverGatherDB and ForeverGatherDB.nodes[mapID]
  for _, node in ipairs(type(list) == "table" and list or {}) do
    local key = node.kind .. ":" .. node.name
    local entry = byName[key]
    if not entry then
      entry = { name = node.name, kind = node.kind, nodes = 0, gathers = 0, skill = ns.LearnedSkill(node.name) }
      byName[key] = entry
      out[#out + 1] = entry
    end
    entry.nodes = entry.nodes + 1
    entry.gathers = entry.gathers + node.count
  end
  table.sort(out, function(a, b)
    local sa, sb = a.skill or 1000, b.skill or 1000
    if sa ~= sb then
      return sa < sb
    end
    return a.name < b.name
  end)
  return out
end

-- Forgets one node of a map. Returns true when it was there.
function ns.ForgetNode(mapID, node)
  local list = ForeverGatherDB and ForeverGatherDB.nodes[mapID]
  for index, other in ipairs(type(list) == "table" and list or {}) do
    if other == node then
      table.remove(list, index)
      ns.Changed()
      return true
    end
  end
  return false
end

-- The skill that a node name was first seen gathered at, or nil.
function ns.LearnedSkill(name)
  local entry = ForeverGatherDB and ForeverGatherDB.names[name]
  return entry and entry.skill
end

-- True when the node shows with the current filters.
function ns.Visible(node)
  if not ns.GetOption(node.kind) then
    return false
  end
  local learned = ns.LearnedSkill(node.name)
  if learned then
    if learned < ns.GetOption("minSkill") then
      return false
    end
    if ns.GetOption("hideTrivial") then
      local rank = ns.SkillRank(ns.KIND[node.kind].skill)
      -- A node gives no more skill ups at 100 points over the skill it needs.
      if rank and rank >= learned + 100 then
        return false
      end
    end
  end
  return true
end

-- The nodes of a map that show with the current filters.
function ns.VisibleNodes(mapID)
  local out = {}
  local list = ForeverGatherDB and ForeverGatherDB.nodes[mapID]
  if type(list) ~= "table" then
    return out
  end
  for _, node in ipairs(list) do
    if ns.Visible(node) then
      out[#out + 1] = node
    end
  end
  return out
end

function ns.CountNodes()
  local counts, total = {}, 0
  for _, list in pairs(ForeverGatherDB and ForeverGatherDB.nodes or {}) do
    for _, node in ipairs(list) do
      counts[node.kind] = (counts[node.kind] or 0) + 1
      total = total + 1
    end
  end
  return total, counts
end

-- Forgets the nodes of one kind, or all nodes without a kind.
function ns.Forget(kind)
  if not ForeverGatherDB then
    return
  end
  if not kind then
    wipe(ForeverGatherDB.nodes)
    wipe(ForeverGatherDB.names)
  else
    for _, list in pairs(ForeverGatherDB.nodes) do
      for index = #list, 1, -1 do
        if list[index].kind == kind then
          table.remove(list, index)
        end
      end
    end
  end
  ns.Changed()
end

-- Forgets the node nearest to the player, within reach yards (a part of the map where the game
-- gives no yards). Returns the node, or nil and the reason.
local FORGET_YARDS, FORGET_PART = 20, 0.01
function ns.ForgetHere()
  local mapID, x, y = ns.PlayerPosition()
  if not mapID then
    return nil, x
  end
  local list = ForeverGatherDB.nodes[mapID]
  local width, height = ns.MapYards(mapID)
  local reachX, reachY = FORGET_PART, FORGET_PART
  if width then
    reachX, reachY = FORGET_YARDS / width, FORGET_YARDS / height
  end
  local best, bestIndex, bestDistance
  for index, node in ipairs(type(list) == "table" and list or {}) do
    local dx, dy = (node.x - x) / reachX, (node.y - y) / reachY
    local distance = dx * dx + dy * dy
    if distance <= 1 and (not bestDistance or distance < bestDistance) then
      best, bestIndex, bestDistance = node, index, distance
    end
  end
  if not best then
    return nil, "no node is within " .. FORGET_YARDS .. " yards of you"
  end
  table.remove(list, bestIndex)
  ns.Changed()
  return best
end

-- The gathering casts and what came of each, kept in the saved data for /fgather status and
-- /fgather history. The newest is the last.
local HISTORY = 20
local function note(spellID, target, kind, result)
  local history = ForeverGatherDB and ForeverGatherDB.history
  if not history then
    return
  end
  history[#history + 1] = { spell = spellID, spellName = spellName(spellID), target = target, kind = kind, result = result, at = time() }
  while #history > HISTORY do
    table.remove(history, 1)
  end
end
local function noteResult(result)
  local history = ForeverGatherDB and ForeverGatherDB.history
  local gather = history and history[#history]
  if gather then
    gather.result = result
  end
end
-- The last cast at a target that is no gathering spell here. When a gather is not recognized,
-- this is the spell to report.
local function noteOther(spellID, target)
  local last = ForeverGatherDB and ForeverGatherDB.last
  if last and ns.Usable(spellID) and ns.PlainString(target) then
    last.other = { spell = spellID, spellName = spellName(spellID), target = target, at = time() }
  end
end

local function recorded(node, mapID)
  return string.format("recorded as %s on map %d", ns.KIND[node.kind].name:lower(), mapID)
end

-- What the loot window says about the thing that was opened: "chest", "quest" or "empty".
function ns.LootKind()
  local count = GetNumLootItems()
  if not ns.Usable(count) then
    return "empty"
  end
  local items = 0
  for slot = 1, count do
    local _, item, _, _, _, _, isQuestItem, questID = GetLootSlotInfo(slot)
    if item ~= nil then
      if issecretvalue(isQuestItem) or issecretvalue(questID) then
        return "quest" -- cannot be told: not recorded
      end
      if isQuestItem or (questID and questID ~= 0) then
        return "quest"
      end
      items = items + 1
    end
  end
  return items > 0 and "chest" or "empty"
end

-- The cast that is under way: { kind, name, castGUID, time }.
local pending
-- The thing that was opened and waits for its loot: { name, mapID, x, y, time }.
local opened
-- The node that was gathered and whose loot comes: { node, time, seconds }.
local gathered

local function lootShows()
  local thing, from = opened, gathered
  opened, gathered = nil, nil
  if from and GetTime() - from.time <= from.seconds then
    ns.CountLoot(from.node)
    return
  end
  if not thing or GetTime() - thing.time > LOOT_SECONDS then
    return
  end
  local loot = ns.LootKind()
  if loot == "empty" then
    noteResult("not recorded: its loot window was empty")
  else
    -- A quest item in the loot: a quest object. Else a chest.
    local node, mapID = ns.Record(loot == "quest" and "quest" or "treasure", thing.name, thing.mapID, thing.x, thing.y)
    noteResult(node and recorded(node, mapID) or ("not recorded: " .. mapID))
    if node then
      ns.CountLoot(node)
    end
  end
end

local handlers = {
  UNIT_SPELLCAST_SENT = function(unit, target, castGUID, spellID)
    if not ns.PlainString(unit) or unit ~= "player" then
      return
    end
    local kind = ns.KindOfSpell(spellID)
    if not kind then
      noteOther(spellID, target)
      return
    end
    pending = {
      kind = kind,
      name = ns.PlainString(target) and target or nil,
      castGUID = ns.PlainString(castGUID) and castGUID or nil,
      time = GetTime(),
    }
    note(spellID, pending.name, kind, "the cast started and did not end yet")
  end,
  UNIT_SPELLCAST_SUCCEEDED = function(unit, castGUID, spellID)
    if not ns.PlainString(unit) or unit ~= "player" then
      return
    end
    local kind = ns.KindOfSpell(spellID)
    if not kind then
      return
    end
    local name
    if pending and pending.kind == kind and GetTime() - pending.time < PENDING_SECONDS then
      if not pending.castGUID or not ns.PlainString(castGUID) or pending.castGUID == castGUID then
        name = pending.name
      end
    end
    pending = nil
    if kind == "treasure" then
      -- The place is taken now, at the thing; the loot decides if it is a chest.
      local mapID, x, y = ns.PlayerPosition()
      if not mapID then
        opened = nil
        note(spellID, name, kind, "not recorded: " .. x)
        return
      end
      opened, gathered = { name = name, mapID = mapID, x = x, y = y, time = GetTime() }, nil
      note(spellID, name, kind, "not recorded: no loot window came after it, so it is no chest and no quest object with loot")
      return
    end
    local node, mapID = ns.Record(kind, name)
    note(spellID, name, kind, node and recorded(node, mapID) or ("not recorded: " .. mapID))
    opened = nil
    gathered = node and { node = node, time = GetTime(), seconds = kind == "fish" and FISH_LOOT_SECONDS or LOOT_SECONDS } or nil
  end,
  UNIT_SPELLCAST_FAILED = function(unit)
    if ns.PlainString(unit) and unit == "player" and pending then
      pending = nil
      noteResult("not recorded: the cast failed or was interrupted")
    end
  end,
  LOOT_READY = lootShows,
  LOOT_OPENED = lootShows,
}
handlers.UNIT_SPELLCAST_INTERRUPTED = handlers.UNIT_SPELLCAST_FAILED

local frame = CreateFrame("Frame")
for event in pairs(handlers) do
  if event:find("^UNIT_") then
    frame:RegisterUnitEvent(event, "player")
  else
    frame:RegisterEvent(event)
  end
end
frame:SetScript("OnEvent", function(_, event, ...)
  local ok, err = pcall(handlers[event], ...)
  if not ok then
    geterrorhandler()(err)
  end
end)