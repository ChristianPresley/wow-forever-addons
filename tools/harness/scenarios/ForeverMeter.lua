-- What Forever Meter does, with checks. T is the test table of the driver (see driver.lua).
local T = ...
local H, ns, expect = T.H, T.ns, T.expect

-- The data of the fight, out of the fight: plain numbers.
local session = ns.GetSession(ns.Mode(), ns.segment)
expect(session and #session.combatSources == 2, "the fight has two players")
local own, rank = ns.OwnSource(session)
expect(own and rank == 2 and own.totalAmount == 3600, "the player is second with 3600 damage")
expect(ns.Short(1234) == "1.23K" and ns.Short(12345) == "12.3K" and ns.Short(1234567) == "1.23M" and ns.Short(999) == "999", "short numbers")
expect(ns.Clock(151) == "2:31", "a time of 151 seconds is 2:31")

-- A report, out of the fight.
local lines = ns.ReportLines()
expect(lines and #lines == 3, "the report has a title and one line for each player")
expect(lines[2]:find("1. Otherplayer", 1, true) and lines[2]:find("60%%"), "the first line is the player with 60% of the damage: " .. tostring(lines and lines[2]))
ns.Report("SELF")
ns.Report("PARTY")
expect(T.printed("you are not in a party"), "a report to the party needs a party")
T.world.group = "party"
local sent = H.count("chat")
ns.Report("PARTY")
expect(H.count("chat") == sent + 3, "the report sends three lines to the party")
T.world.group = nil

-- Each mode has data, and the window shows it.
for _, mode in ipairs(ns.MODES) do
  expect(ns.SetOption("mode", mode.key) == true, "the mode " .. mode.key .. " is accepted")
  T.advance(1)
end
expect(ns.SetOption("mode", "noSuchMode") == false, "a mode that does not exist is refused")
ns.SetOption("mode", "dps")
ns.SetSegment({ type = 0 })
T.advance(1)
ns.SetSegment({ id = 1, name = "Hogger" })
expect(ns.Duration(ns.segment) == 30, "an earlier fight has its duration")
T.advance(1)
ns.SetSegment({ type = 1 })

-- The spells of a player.
ns.ShowDetails(session.combatSources[2])
T.advance(2)
local source = ns.GetSource(ns.Mode(), ns.segment, session.combatSources[2].sourceGUID, nil)
expect(source and #source.combatSpells == 1, "the player has one spell in the fight")

-- The switch of the game's own damage meter.
expect(ns.GameMeterEnabled() == true, "the damage meter of the game is on")
T.world.cvars.damageMeterEnabled = "0"
expect(ns.GameMeterEnabled() == false, "with the setting at 0 it is off")
T.advance(1)
expect(ns.EnableGameMeter() == true and T.world.cvars.damageMeterEnabled == "1", "the addon turns it on")

-- In a fight the numbers are secret: they show, and nothing is calculated with them.
T.world.secret = true
T.advance(2)
local hiddenLines, reason = ns.ReportLines()
expect(hiddenLines == nil and reason:find("after the fight", 1, true), "a report waits for the end of the fight")
local inFight = ns.GetSession(ns.Mode(), ns.segment)
expect(issecretvalue(inFight.totalAmount) and issecretvalue(inFight.combatSources[1].name), "in a fight the numbers and the names are secret")
expect(inFight.combatSources[2].isLocalPlayer == true, "which bar is the player's is never secret")
expect(ns.GetSource(ns.Mode(), ns.segment, inFight.combatSources[1].sourceGUID, nil) == nil, "the game refuses the spells of a player whose identity is secret")
ns.ShowDetails(inFight.combatSources[1], 1)
T.advance(2)
T.world.secret = false
T.advance(2)
-- After the fight the window reads the player again, and the spells show. (The window updates
-- itself once a second; here the change of the fight does it.)
ns.Changed(nil)
expect(ForeverMeterDetails.rows[1]:IsShown(), "after the fight the spell window of a player who was clicked in the fight fills in")

-- The bars for each kind of group.
ns.SetOption("rowsSolo", 1)
T.advance(1)
ns.SetOption("pinSelf", false)
T.advance(1)
ns.SetOption("pinSelf", true)
ns.SetOption("rowsSolo", 3)
T.slash("/fmeter", "bars raid 12")
expect(ns.GetOption("rowsRaid") == 12, "/fmeter bars raid 12 sets the bars of a raid")
T.slash("/fmeter", "bars raid 99")
expect(ns.GetOption("rowsRaid") == 25, "the bars of a raid stay at 25 or lower")
ns.SetOption("rowsRaid", 10)

-- Deleting the data asks the game.
ns.ResetData()
expect(H.count("reset damage data") == 1, "deleting the fights asks the game")
-- The question before it: "no" deletes nothing, "yes" deletes.
T.world.sayNo = true
ns.ConfirmReset()
expect(H.count("reset damage data") == 1, "with the answer no, nothing is deleted")
T.world.sayNo = nil
ns.ConfirmReset()
expect(H.count("reset damage data") == 2, "with the answer yes, the fights are deleted")

-- A number on the screen has two decimals at most. In a fight the numbers are secret, and the
-- addon cannot round them: the game's function gets the rules of the addon.
local shown = CreateFrame("Frame"):CreateFontString()
local function textOf(value)
  ns.SetNumber(shown, value)
  return H.plain(shown:GetText())
end
expect(textOf(H.secret(345.678901)) == "345", "a secret 345.678901 shows as a whole number, got " .. tostring(textOf(H.secret(345.678901))))
expect(textOf(H.secret(0.123456789)) == "0", "a secret number below 1 shows no decimals, got " .. tostring(textOf(H.secret(0.123456789))))
expect(textOf(H.secret(1234.56789)) == "1.23K", "a secret 1234.56789 shows as 1.23K, got " .. tostring(textOf(H.secret(1234.56789))))
expect(textOf(H.secret(12345.6789)) == "12.3K", "a secret 12345.6789 shows as 12.3K, got " .. tostring(textOf(H.secret(12345.6789))))
expect(textOf(H.secret(2567890.123)) == "2.56M", "a secret 2567890.123 shows as 2.56M, got " .. tostring(textOf(H.secret(2567890.123))))
expect(textOf(345.678901) == "346" and textOf(1234.56789) == "1.23K", "a plain number is rounded by the addon")
expect(issecretvalue(shown:GetText()) == false, "a plain number gives a plain text")
expect(ns.NumberWay() == "rules", "the game takes the rules of the addon: " .. ns.NumberWay())
-- Two numbers and a share: the font string puts them together.
ns.SetNumber(shown, H.secret(1234.56789), true, H.secret(45.678901), "  45%")
expect(H.plain(shown:GetText()) == "1.23K (45)  45%", "two secret numbers and a share, got " .. tostring(H.plain(shown:GetText())))
-- A game client that refuses the rules of the addon (a breakpoint of zero): the addon tries the
-- rules with plain numbers first, sees that, and shows two decimals without K and M.
T.world.strictAbbreviate = true
ns.ResetNumberWay()
expect(ns.NumberWay() == "plain", "a client that refuses the rules: the addon sees it, got " .. ns.NumberWay())
expect(textOf(H.secret(345.678901)) == "345.68", "then a secret 345.678901 shows with two decimals, got " .. tostring(textOf(H.secret(345.678901))))
ns.SetNumber(shown, H.secret(1234.56789), true, H.secret(45.678901), "  45%")
expect(H.plain(shown:GetText()) == "1234.57 (45.68)  45%", "and two secret numbers too, got " .. tostring(H.plain(shown:GetText())))
T.slash("/fmeter", "status")
expect(T.printed("two decimals, without K and M"), "/fmeter status says how the numbers of a fight are shown")
T.world.strictAbbreviate = nil
ns.ResetNumberWay()
expect(ns.NumberWay() == "rules", "without that the rules are back")
