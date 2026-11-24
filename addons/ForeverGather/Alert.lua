local _, ns = ...

-- Says when a learned node comes near: one line in the chat, and a sound. A node is said once
-- for each visit: again only after the player went away from it. A node that was gathered a few
-- minutes ago (the option "dimMinutes") is not said, and no node inside an instance.

local CHECK_SECONDS = 0.5
local LEAVE = 1.5 -- a visit ends beyond this many times the distance of the alert
local JUST_NOW = 10 -- seconds

-- The nodes that the player is near: [node] = true. Weak, so a forgotten node goes.
local visiting = setmetatable({}, { __mode = "k" })
local alerts = 0

local DIRECTIONS = { "east", "north-east", "north", "north-west", "west", "south-west", "south", "south-east" }
-- "north-east" for a point so many yards east and north of the player.
function ns.DirectionWord(east, north)
  local turn = math.atan2(north, east) / (math.pi / 4)
  return DIRECTIONS[math.floor(turn + 0.5) % 8 + 1]
end

-- Looks for nodes that came near. Returns how many were said.
function ns.CheckNearby()
  if not ns.GetOption("alert") then
    return 0
  end
  local mapID, px, py = ns.PlayerPosition()
  if not mapID then
    return 0
  end
  local width, height = ns.MapYards(mapID)
  if not width then
    return 0
  end
  local yards = ns.GetOption("alertYards")
  local nearest, nearestDistance, nearestEast, nearestNorth
  local new = 0
  for _, entry in ipairs((ns.NearList(mapID))) do
    local east, north = (entry.x - px) * width, (py - entry.y) * height
    local distance = math.sqrt(east * east + north * north)
    local node = entry.node
    if distance > yards * LEAVE then
      visiting[node] = nil
    elseif distance <= yards and not visiting[node] then
      visiting[node] = true
      -- Not a node that was gathered just now, or a few minutes ago.
      local justNow = type(node.last) == "number" and time() - node.last < JUST_NOW
      if not justNow and not ns.RecentlyGathered(node) then
        new = new + 1
        if not nearestDistance or distance < nearestDistance then
          nearest, nearestDistance, nearestEast, nearestNorth = node, distance, east, north
        end
      end
    end
  end
  if new == 0 then
    return 0
  end
  local where = nearestDistance < 5 and "here" or string.format("%d yards to the %s", math.floor(nearestDistance + 0.5), ns.DirectionWord(nearestEast, nearestNorth))
  local more = new > 1 and string.format(", and %d more |4node:nodes; near", new - 1) or ""
  ns.Print(string.format("%s is %s%s.", nearest.name, where, more))
  if ns.GetOption("alertSound") then
    PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE)
  end
  alerts = alerts + new
  return new
end

function ns.AlertCount()
  return alerts
end

local frame = CreateFrame("Frame")
local since = 0
frame:SetScript("OnUpdate", function(_, elapsed)
  since = since + elapsed
  if since >= CHECK_SECONDS then
    since = 0
    ns.CheckNearby()
  end
end)
