-- What Forever Leveling does, with checks. T is the test table of the driver (see driver.lua).
local T = ...
local H, ns, expect = T.H, T.ns, T.expect

-- The numbers, from their inputs.
expect(ns.PerHour(1000, 30) == nil, "no rate before the first minute")
expect(ns.PerHour(1500, 1800) == 3000, "1500 XP in half an hour is 3000 an hour")
expect(ns.TimeToLevel(4500, 3000) == 5400, "4500 XP at 3000 an hour is 5400 seconds")
expect(ns.TimeToLevel(4500, nil) == nil, "no time without a rate")
expect(ns.CountToLevel(1000, 75) == 14, "1000 XP at 75 a kill is 14 kills, rounded up")
expect(ns.Average({ 60, 80, 100 }) == 80 and ns.Average({}) == nil, "the average of the gains")
expect(ns.Duration(3725) == "1h 2m" and ns.Duration(95) == "1m 35s" and ns.Duration(7) == "7s", "durations")
expect(ns.Thousands(1234567) == "1,234,567" and ns.Thousands(999) == "999", "numbers with commas")

-- The zones for a level: the ones nearest to it first, and none of the other side's towns.
local list = ns.ZonesFor(12, 2, "Alliance")
expect(#list > 0, "a level 12 Alliance character has zones")
local names = {}
for _, zone in ipairs(list) do
  names[zone.name] = true
  expect(zone.side ~= "H", "no Horde zone for the Alliance: " .. zone.name)
  expect(12 >= zone.min - 2 and 12 <= zone.max + 2, "each zone is within two levels: " .. zone.name)
end
expect(names["Westfall"] and names["Loch Modan"] and not names["Silverpine Forest"] and not names["Stranglethorn Vale"], "Westfall and Loch Modan suit level 12, Silverpine and Stranglethorn do not")
local wide = ns.ZonesFor(12, 8, "Horde")
expect(#wide > #ns.ZonesFor(12, 0, "Horde"), "a wider spread lists more zones")
expect(ns.Fit({ min = 10, max = 18 }, 20) == "low" and ns.Fit({ min = 10, max = 18 }, 5) == "high" and ns.Fit({ min = 10, max = 18 }, 12) == "even", "how a zone fits")
for _, zone in ipairs(ns.ZONES) do
  expect(zone.min <= zone.max and (zone.side == "A" or zone.side == "H" or zone.side == "C"), "a zone has a range and a side: " .. zone.name)
end

-- Kills and quests: the game's XP changes, and the addon sorts the gains.
local xp, max, level, rested = 1000, 5000, 12, 600
local realXP, realMax, realLevel, realRested = UnitXP, UnitXPMax, UnitLevel, GetXPExhaustion
UnitXP = function() return xp end
UnitXPMax = function() return max end
UnitLevel = function() return level end
GetXPExhaustion = function() return rested end
ns.ResetSession()
xp = 1080
T.fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold dies, you gain 80 experience.", "", "", "", "", "", 0, 0, "", 0, 0, "", 0, false, false, false, false)
T.fire("PLAYER_XP_UPDATE", "player")
expect(#ns.session.kills == 1 and ns.session.kills[1] == 80, "a kill of 80 XP is counted")
xp = 1430
T.fire("QUEST_TURNED_IN", 176, 350, 0)
T.fire("PLAYER_XP_UPDATE", "player")
expect(#ns.session.quests == 1 and ns.session.quests[1] == 350 and #ns.session.kills == 1, "a quest of 350 XP is counted, and not as a kill")
xp = 1500
T.fire("PLAYER_XP_UPDATE", "player")
expect(#ns.session.kills == 1 and #ns.session.quests == 1 and ns.session.gained == 500, "XP from elsewhere counts for the rate only")
-- A report of a kill long after that XP does not make it a kill, and does not wait for the next XP.
T.advance(5)
T.fire("CHAT_MSG_COMBAT_XP_GAIN", "", "", "", "", "", "", 0, 0, "", 0, 0, "", 0, false, false, false, false)
T.advance(5)
xp = 1520
T.fire("PLAYER_XP_UPDATE", "player")
expect(#ns.session.kills == 1 and ns.session.gained == 520, "an old report of a kill takes no later XP")
T.advance(5)
-- The other order: the XP first, then its reason.
xp = 1560
T.fire("PLAYER_XP_UPDATE", "player")
T.fire("CHAT_MSG_COMBAT_XP_GAIN", "", "", "", "", "", "", 0, 0, "", 0, 0, "", 0, false, false, false, false)
expect(#ns.session.kills == 2 and ns.session.kills[2] == 40, "XP that comes before the report of the kill is a kill of 40")
xp = 1860
T.fire("PLAYER_XP_UPDATE", "player")
T.fire("QUEST_TURNED_IN", 177, 300, 0)
expect(#ns.session.quests == 2 and ns.session.quests[2] == 300 and #ns.session.kills == 2, "XP that comes before the turn-in is a quest of 300")
-- An event between the reason and the XP does not lose the reason.
T.fire("QUEST_TURNED_IN", 178, 120, 0)
T.fire("UPDATE_EXHAUSTION")
xp = 1980
T.fire("PLAYER_XP_UPDATE", "player")
expect(#ns.session.quests == 3 and ns.session.quests[3] == 120, "the rested event between a turn-in and its XP loses nothing")
xp = 1500
ns.ResetSession()
xp = 1580
T.fire("CHAT_MSG_COMBAT_XP_GAIN", "", "", "", "", "", "", 0, 0, "", 0, 0, "", 0, false, false, false, false)
T.fire("PLAYER_XP_UPDATE", "player")
xp = 1930
T.fire("QUEST_TURNED_IN", 179, 350, 0)
T.fire("PLAYER_XP_UPDATE", "player")
-- A level up: the rest of the old level and the start of the new one. The game says the new
-- level in a later event than the new XP: that reading adds nothing.
xp, max = 100, 5500
T.fire("CHAT_MSG_COMBAT_XP_GAIN", "", "", "", "", "", "", 0, 0, "", 0, 0, "", 0, false, false, false, false)
T.fire("PLAYER_XP_UPDATE", "player")
level = 13
T.fire("PLAYER_LEVEL_UP", 13, 0, 0, 0, 0, 0, 0, 0, 0)
expect(ns.session.kills[2] == 3170 and ns.session.gained == 3600, "a kill over the level counts the XP of both levels, once")
-- Low levels: the new level can start above the old XP.
xp, max, level = 380, 400, 1
ns.ResetSession()
xp, max, level = 430, 900, 2
T.fire("QUEST_TURNED_IN", 180, 450, 0)
T.fire("PLAYER_XP_UPDATE", "player")
expect(ns.session.gained == 450 and ns.session.quests[1] == 450, "a quest over a low level counts all its XP")
xp, max, level = 1500, 5000, 12
ns.ResetSession()
xp = 1580
T.fire("CHAT_MSG_COMBAT_XP_GAIN", "", "", "", "", "", "", 0, 0, "", 0, 0, "", 0, false, false, false, false)
T.fire("PLAYER_XP_UPDATE", "player")
xp = 1930
T.fire("QUEST_TURNED_IN", 181, 350, 0)
T.fire("PLAYER_XP_UPDATE", "player")
xp, max, level = 100, 5500, 13
T.fire("CHAT_MSG_COMBAT_XP_GAIN", "", "", "", "", "", "", 0, 0, "", 0, 0, "", 0, false, false, false, false)
T.fire("PLAYER_XP_UPDATE", "player")
expect(ns.session.kills[2] == 3170, "a kill over the level, with level and XP in one event")
T.advance(1800)
local state = ns.State()
expect(state and state.level == 13 and state.remaining == 5400 and state.rested == 600, "the state reads the game")
expect(state.killsToLevel == math.ceil(5400 / 1625) and state.questsToLevel == math.ceil(5400 / 350), "kills and quests to level from the averages")
expect(state.perHour and state.perHour > 0 and state.timeToLevel and state.timeToLevel > 0, "a rate and a time after half an hour")
-- The readout shows these numbers, and says so at the highest level.
local realCap = GetMaxLevelForPlayerExpansion
GetMaxLevelForPlayerExpansion = function() return 60 end
ns.RefreshReadout()
local shown = ForeverLevelingReadout
expect(shown.title:GetText():find("Level 13: 100 / 5,500 (1.8%)", 1, true), "the readout has the level and the XP: " .. tostring(shown.title:GetText()))
expect(shown.kills:GetText() == "Kills to level: 4 (1,625 XP each)" and shown.quests:GetText() == "Quests to level: 16 (350 XP each)", "the readout has the kills and the quests to level, a line each: " .. tostring(shown.kills:GetText()) .. " / " .. tostring(shown.quests:GetText()))
-- No line wraps onto the next one: each is one line, 16 pixels under the one before, and the
-- readout is as wide as its longest line.
local widest = 0
for index, text in ipairs(shown.lines) do
  expect(text:CanWordWrap() == false, "line " .. index .. " of the readout does not wrap")
  widest = math.max(widest, text:GetStringWidth())
end
expect(shown:GetWidth() >= 260 and shown:GetWidth() >= widest + 16, "the readout is as wide as its longest line: " .. shown:GetWidth() .. " for " .. widest)
local _, _, _, _, killsY = shown.kills:GetPoint(1)
local _, _, _, _, questsY = shown.quests:GetPoint(1)
local _, _, _, _, restedY = shown.restedText:GetPoint(1)
expect(killsY - questsY == 16 and questsY - restedY == 16 and shown:GetHeight() >= -restedY + 16, "the lines are 16 pixels apart, inside the readout")
expect(shown.restedText:GetText() == "Rested: 600 XP (11% of the level)" and shown.rate:GetText():find("XP an hour, level in", 1, true), "the readout has the rested XP and the rate")
GetMaxLevelForPlayerExpansion = function() return 13 end
ns.RefreshReadout()
expect(shown.title:GetText() == "Level 13: the highest level" and shown.kills:GetText() == "" and shown.quests:GetText() == "", "at the highest level the readout says so")
GetMaxLevelForPlayerExpansion = realCap
-- The number of samples is an option.
ns.SetOption("samples", 3)
for _ = 1, 5 do
  xp = xp + 10
  T.fire("CHAT_MSG_COMBAT_XP_GAIN", "", "", "", "", "", "", 0, 0, "", 0, 0, "", 0, false, false, false, false)
  T.fire("PLAYER_XP_UPDATE", "player")
end
expect(#ns.session.kills == 3 and ns.Average(ns.session.kills) == 10, "only the last three kills make the average")
-- Hidden numbers stay out of the sums.
local before = ns.session.gained
UnitXP = function() return H.secret(5000) end
T.fire("PLAYER_XP_UPDATE", "player")
expect(ns.session.gained == before, "a hidden XP changes nothing")
UnitXP, UnitXPMax, UnitLevel, GetXPExhaustion = realXP, realMax, realLevel, realRested

-- Options and commands.
expect(ns.SetOption("noSuchOption", 1) == false, "an option that does not exist is refused")
ns.SetOption("zoneSpread", 99)
expect(ns.GetOption("zoneSpread") == 10, "the spread stops at 10 levels")
T.slash("/flevel", "spread 4")
expect(ns.GetOption("zoneSpread") == 4, "/flevel spread 4 sets the spread")
T.slash("/flevel", "zones")
expect(ns.GetOption("showZones") == true and ForeverLevelingZones:IsShown(), "/flevel zones shows the list")
T.slash("/flevel", "go nowhere")
expect(T.printed("is not a zone"), "an unknown zone is refused")

-- Pointing at a zone: the map pin, then the compass through its public interface.
local message = ns.PointAt({ name = "Westfall", min = 9, max = 18, side = "A" })
expect(message:find("Westfall", 1, true), "pointing at Westfall answers: " .. message)
local asked = 0
local realCan, realSet = C_Map.CanSetUserWaypointOnMap, C_Map.SetUserWaypoint
C_Map.CanSetUserWaypointOnMap = function() return true end
C_Map.SetUserWaypoint = function(point) H.pin = point return true end
ForeverCompass = { TrackMapPin = function() asked = asked + 1 return 2 end }
message = ns.PointAt({ name = "Westfall", min = 9, max = 18, side = "A" })
expect(H.pin and H.pin.uiMapID == 52 and asked == 1 and message:find("tracker 2", 1, true), "with Forever Compass, a tracker points to the pin: " .. message)
ForeverCompass = { TrackMapPin = function() return nil, "all 4 trackers of the compass are in use" end }
message = ns.PointAt({ name = "Westfall", min = 9, max = 18, side = "A" })
expect(message:find("in use", 1, true), "a full compass says why")
ForeverCompass = nil
message = ns.PointAt({ name = "Silithus", min = 54, max = 60, side = "C" })
expect(message:find("not known", 1, true), "a zone of another continent has no map here: " .. message)
C_Map.CanSetUserWaypointOnMap, C_Map.SetUserWaypoint = realCan, realSet
