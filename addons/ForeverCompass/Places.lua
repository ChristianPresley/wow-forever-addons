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

local function remember(kind, name)
  if not ForeverCompassDB then
    return
  end
  local mapID = ns.PlayerMap()
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
