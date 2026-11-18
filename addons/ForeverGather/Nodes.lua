local _, ns = ...

-- Learning nodes from the player's own gathering.
--
-- The client has no combat log for addons, and no list of nodes. A gather is a spell of the
-- player: UNIT_SPELLCAST_SENT names the target (the node, "Peacebloom"), and
-- UNIT_SPELLCAST_SUCCEEDED with the same cast says that it worked. At that moment the player
-- stands at the node, so the node is where the player is.

-- The spells of gathering, by spell ID (each rank), and by name as a fallback.
local SPELLS = {
  [2366] = "herb", [2368] = "herb", [3570] = "herb", [11993] = "herb",
  [2575] = "ore", [2576] = "ore", [3564] = "ore", [10248] = "ore",
  [7620] = "fish", [7731] = "fish", [7732] = "fish", [18248] = "fish",
  [3365] = "treasure", [6247] = "treasure", [6477] = "treasure", [6478] = "treasure", [21248] = "treasure", [22810] = "treasure",
}
local SPELL_NAMES = { ["Herb Gathering"] = "herb", ["Mining"] = "ore", ["Fishing"] = "fish", ["Opening"] = "treasure" }

-- Two nodes of the same name nearer than this (a part of the map) are one node. Fish are caught
-- anywhere along a shore, so their places merge over a wider span.
local SAME = { herb = 0.004, ore = 0.004, treasure = 0.004, fish = 0.012 }
-- A cast that does not succeed within this many seconds is forgotten.
local PENDING_SECONDS = 30

function ns.KindOfSpell(spellID)
  if not ns.Usable(spellID) then
    return nil
  end
  local kind = SPELLS[spellID]
  if kind then
    return kind
  end
  local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
  if ns.PlainString(name) then
    return SPELL_NAMES[name]
  end
  return nil
end

-- Remembers a gather of kind at the player's place. Returns the node, or nil without a place.
function ns.Record(kind, name)
  if not ForeverGatherDB or not ns.KIND[kind] then
    return nil
  end
  local mapID, x, y = ns.PlayerPosition()
  if not mapID then
    return nil
  end
  if not ns.PlainString(name) then
    name = kind == "fish" and "Fishing spot" or ns.KIND[kind].name
  end
  local nodes = ForeverGatherDB.nodes
  nodes[mapID] = nodes[mapID] or {}
  local list = nodes[mapID]
  local same = SAME[kind]
  local found
  for _, node in ipairs(list) do
    if node.kind == kind and node.name == name and math.abs(node.x - x) < same and math.abs(node.y - y) < same then
      found = node
      break
    end
  end
  if found then
    -- The place moves toward the average of the gathers there.
    local count = found.count + 1
    found.x = found.x + (x - found.x) / count
    found.y = found.y + (y - found.y) / count
    found.count = count
  else
    found = { kind = kind, name = name, x = x, y = y, count = 1 }
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
  ns.Changed()
  return found
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

-- The cast that is under way: { kind, name, castGUID, time }.
local pending

local handlers = {
  UNIT_SPELLCAST_SENT = function(unit, target, castGUID, spellID)
    if not ns.PlainString(unit) or unit ~= "player" then
      return
    end
    local kind = ns.KindOfSpell(spellID)
    if not kind then
      return
    end
    pending = {
      kind = kind,
      name = ns.PlainString(target) and target or nil,
      castGUID = ns.PlainString(castGUID) and castGUID or nil,
      time = GetTime(),
    }
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
    ns.Record(kind, name)
  end,
  UNIT_SPELLCAST_FAILED = function(unit)
    if ns.PlainString(unit) and unit == "player" then
      pending = nil
    end
  end,
}
handlers.UNIT_SPELLCAST_INTERRUPTED = handlers.UNIT_SPELLCAST_FAILED

local frame = CreateFrame("Frame")
for event in pairs(handlers) do
  frame:RegisterUnitEvent(event, "player")
end
frame:SetScript("OnEvent", function(_, event, ...)
  local ok, err = pcall(handlers[event], ...)
  if not ok then
    geterrorhandler()(err)
  end
end)
