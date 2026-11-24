local _, ns = ...

-- Places that the addon learns as the player visits them.
--
-- The game has no list of where vendors, trainers or mailboxes are. So the addon remembers the
-- place where the player stands when one of their windows opens:
--   ForeverCompassDB.places[kind] = { { mapID = n, x = n, y = n, name = s }, ... }   with x, y from 0 to 1
-- The places are for all characters.

-- Two places of a kind nearer than this (as a part of the map) are the same place.
local SAME = 0.004

local function npcName(fallback)
  local name = UnitName and UnitName("npc")
  -- The game can hide the name of an NPC. A hidden name cannot be compared, so that test is first.
  if (issecretvalue and issecretvalue(name)) or type(name) ~= "string" or name == "" then
    return fallback
  end
  return name
end

-- Whether a map is a continent or larger (the world, the cosmos), and whether the game knows
-- the map at all. A place on such a map points to a wrong spot: inside an instance the best map
-- for the player is the continent, and the position of the player there is not a place of it.
local function largeMap(mapID)
  local ok, info = pcall(C_Map.GetMapInfo, mapID)
  if not ok or type(info) ~= "table" or not Enum or not Enum.UIMapType then
    return false, false
  end
  for _, name in ipairs({ "Cosmic", "World", "Continent" }) do
    if Enum.UIMapType[name] ~= nil and info.mapType == Enum.UIMapType[name] then
      return true, true
    end
  end
  return false, true
end

local function remember(kind, name)
  if not ForeverCompassDB then
    return
  end
  local mapID = ns.PlayerMap()
  local large, known = largeMap(mapID)
  if large or not known then
    return -- a continent, or a map the game does not name: not a place
  end
  local x, y = ns.PlayerMapPosition(mapID)
  if not x then
    return -- the game hides the position here (an instance)
  end
  local places = ForeverCompassDB.places
  if type(places[kind]) ~= "table" then
    places[kind] = {}
  end
  for _, place in ipairs(places[kind]) do
    if place.mapID == mapID and math.abs(place.x - x) < SAME and math.abs(place.y - y) < SAME then
      place.name = name
      return
    end
  end
  table.insert(places[kind], { mapID = mapID, x = x, y = y, name = name })
end

function ns.Places(kind)
  local list = ForeverCompassDB and ForeverCompassDB.places[kind]
  return type(list) == "table" and list or {}
end

function ns.CountPlaces()
  local count = 0
  for _, list in pairs(ForeverCompassDB.places) do
    if type(list) == "table" then
      count = count + #list
    end
  end
  return count
end

function ns.ForgetPlaces()
  wipe(ForeverCompassDB.places)
end

-- Drops the places that were stored on a continent or larger map (before this check existed),
-- and returns how many. A map the game does not name keeps its places.
function ns.DropLargePlaces()
  local dropped = 0
  if not ForeverCompassDB or type(ForeverCompassDB.places) ~= "table" then
    return dropped
  end
  for _, list in pairs(ForeverCompassDB.places) do
    if type(list) == "table" then
      for index = #list, 1, -1 do
        local large, known = largeMap(list[index].mapID)
        if large and known then
          table.remove(list, index)
          dropped = dropped + 1
        end
      end
    end
  end
  return dropped
end

ns.OnLogin(function()
  local dropped = ns.DropLargePlaces()
  if dropped > 0 then
    ns.Print(dropped .. " learned " .. (dropped == 1 and "place was" or "places were") .. " on a continent map, where it pointed to a wrong spot, and " .. (dropped == 1 and "was" or "were") .. " dropped.")
  end
end)

local handlers = {
  MERCHANT_SHOW = function()
    local name = npcName("Vendor")
    remember("vendor", name)
    if CanMerchantRepair and CanMerchantRepair() then
      remember("repair", name)
    end
  end,
  MAIL_SHOW = function()
    remember("mailbox", "Mailbox")
  end,
  TRAINER_SHOW = function()
    remember("trainer", npcName("Trainer"))
  end,
  BANKFRAME_OPENED = function()
    remember("bank", npcName("Banker"))
  end,
  AUCTION_HOUSE_SHOW = function()
    remember("auction", npcName("Auctioneer"))
  end,
}

local frame = CreateFrame("Frame")
for event in pairs(handlers) do
  pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event)
  local ok, err = pcall(handlers[event])
  if not ok then
    geterrorhandler()(err)
  end
end)
