# Addon development for WoW: Forever

## Client facts

These facts are from a live install of client build 1.60.1.70938 (November 2026).

| Fact | Value |
|---|---|
| Flavor folder | `World of Warcraft\_forever_` |
| AddOns folder | `World of Warcraft\_forever_\Interface\AddOns` |
| Battle.net product code | `wowf` (in `_forever_\.flavor.info` and `.build.info`) |
| Executable | `_forever_\Wow.exe` |
| TOC interface number | `16001` |
| Flavor TOC suffix | `_Camelot`, for example `Questie_Camelot.toc`. Some addons also ship `_Forever` |
| Project constant | `WOW_PROJECT_CAMELOT` |
| API family | Mainline (patch 12.1.5): `C_AuctionHouse`, `C_QuestLog`, `C_Map`, `C_GossipInfo`, `TooltipDataProcessor` |

Where to check an API before you use it:

- **Blizzard's UI source:** the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever). Forever-specific code is in the `Camelot` folders.
- **Addons that work on this client:** read how the addons in your own `Interface\AddOns` folder call the API. Learn from them, but do not copy their code.

What the client does and does not have:

- The quest log is the Mainline one on the world map (`QuestScrollFrame`), and the tracker is `QuestObjectiveTracker`. There is no `QuestLogFrame` or `QuestWatchFrame`.
- The game writes the quest level in front of quest names itself, for example `[12] Wanted: Hogger`, and colours the title by difficulty, in the quest log and in the tracker. An addon does not need to add either.
- The auction house is the Mainline one (`AuctionHouseFrame`), with `C_AuctionHouse.ReplicateItems` for a full scan.
- An options page is a frame registered with `Settings.RegisterCanvasLayoutCategory` and `Settings.RegisterAddOnCategory`.

Where the position of a thing comes from:

| Thing | API |
|---|---|
| Quests of the log (objectives and turn-ins) | `C_QuestLog.GetQuestsOnMap(mapID)`, with `C_QuestLog.IsComplete(questID)` |
| Quests that an area offers (quest givers) | `C_QuestLine.GetAvailableQuestLines(mapID)`, after `C_QuestLine.RequestQuestLinesForMap(mapID)` |
| Rare enemies, treasures, events | `C_VignetteInfo.GetVignettes()` and `GetVignettePosition(guid, mapID)` |
| Flight masters | `C_TaxiMap.GetTaxiNodesForMap(mapID)` |
| The player and party members, in yards | `UnitPosition(unit)`. Nil in instances |
| A map point in yards | `C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))` |
| Vendors, trainers, mailboxes, other NPCs | No API. An addon can only remember where the player met them |

Rules that follow from the Mainline API:

- **Secret values.** In combat, some API results (health, auras, threat, names) are secret: an addon can show them, but cannot calculate with them or compare them. Check with `issecretvalue(value)` before you use a number from a combat-related API.
- **The combat log is closed to addons.** Damage and healing numbers come from the game's own damage meter data, `C_DamageMeter`:
  - `GetCombatSessionFromType(sessionType, damageMeterType)` gives the sources of the current fight (`Enum.DamageMeterSessionType.Current`) or the whole session (`Overall`), the highest first. `GetAvailableCombatSessions()` lists earlier fights, for `GetCombatSessionFromID`.
  - `GetCombatSessionSourceFromType` gives the spells of one source. During a fight the game refuses it for a source whose GUID is secret.
  - During a fight every number and each player name is secret. Show them with `FontString:SetText`, `StatusBar:SetValue` and `AbbreviateNumbers`, and calculate (percentages, text for chat) after the fight. `classFilename` and `isLocalPlayer` are never secret. A secret value cannot be compared, not even with `nil`: test with `issecretvalue` first.
  - The CVar `damageMeterEnabled` is the switch of the game's own meter.
  - Forever Meter is the example.
- Lua `require` has the name `import`.
- Classic Era addon packages do not load. An addon needs `16001` in its `## Interface` line.

## Conventions in this repository

- The folder name, the TOC name and the addon name in `ADDON_LOADED` are the same: `addons/ForeverQuests/ForeverQuests.toc`.
- `## Version` has the form `1.2.3`. The marketplace version comes from this line, so increase it for each release.
- Each Lua file starts with `local _, ns = ...` and shares state through `ns`. Do not add globals other than the saved variables and the slash command.
- Register an event that is possibly absent from the client with `pcall(frame.RegisterEvent, frame, "EVENT")`. A direct call with an unknown event name is an error.
- `addon.json` holds the marketplace text. It is not part of the package:

```json
{
  "id": "forever-quests",
  "category": "Questing",
  "summary": "One sentence for lists.",
  "description": "Two or three sentences for the marketplace card."
}
```

## Settings page (required)

Each addon must have a full page in the game's Options window, under AddOns. `cargo dev lint` fails for an addon without one.

"Full" means:

- **Each option has a control.** A checkbox for an on/off option and a slider for a number. Group the controls under headers, and give each one a hint, which shows as a tooltip.
- **Values that a player can want to change are options.** A distance, a number of days or a switch for an on-screen element is an option, not a constant in the code.
- **Each data action has a button.** Reset a position, delete stored data, open the addon's window. A button that deletes data asks for confirmation.
- **The page and the slash commands agree.** Both change the option through the addon's `ns.SetOption`, and the page listens for changes, so that a slash command updates an open page.
- **The slash command has `options`**, which opens the page, for example `/fq options`.

Build the page with `SettingsKit.lua`:

1. Copy `SettingsKit.lua` from an existing addon and list it in the TOC before the file that builds the page. Do not change the copy: the lint checks that all copies are the same. To change the kit, change every copy.
2. Build the page after the saved variables are loaded:

```lua
local page = ns.NewSettingsPage("Forever Quests", "One line under the title.")
page:Header("Alerts")
page:Check({
  label = "Quest-ready sound",
  hint = "A sound when a quest is ready to turn in.",
  get = function() return ns.GetOption("sound") end,
  set = function(value) ns.SetOption("sound", value) end,
})
page:Slider({ label = "Days to keep", min = 3, max = 30, step = 1, get = getDays, set = setDays, format = function(value) return value .. " days" end })
page:Choice({ label = "Colour", values = { { "gold", "Gold" }, { "red", "Red" } }, get = getColour, set = setColour })
page:Info(function() return "12 prices stored." end)
page:Buttons({ { label = "Delete stored prices", confirm = "Delete all stored prices?", click = deletePrices } })
if page:Register() then
  ns.OnOptionChanged(function() page:Refresh() end)
end
```

Keep the page short enough to fit without scrolling: about 470 pixels of height. A header takes 28, a checkbox 24, a slider 46, a choice 28, a row of buttons 32 and an info line 18.

An addon with more settings than fit on one page puts them on pages under its main page. Give the main page as the third argument, and register the main page first:

```lua
local sub = ns.NewSettingsPage("Compass 1", "One line under the title.", page)
sub:Register()
```

Forever Compass does this: one page for the compass bar, and one page for each tracker.

## Add an addon

1. Make `addons/<Name>/` with `<Name>.toc`, the Lua files and `addon.json`.
2. Add the settings page (see above). It is required.
3. List each Lua file in the TOC.
4. Run `cargo dev lint`. It checks the TOC, `addon.json`, the settings page and the Lua syntax.
5. Run `cargo link-addons` and test in the game with `/reload`.
6. Push to `main`. The publish workflow adds the addon to the marketplace.

## Tests

Blizzard has no sandbox and no test server for addons. An addon runs in the game client and nowhere else. The repository has checks that run without the game: `cargo dev lint`, `cargo dev conformance` and `cargo dev test` for the addons, and the checks under "Conformance with Blizzard's files" for the stand-in itself. The rest needs the game.

### `cargo dev lint`

Checks the TOC, `addon.json`, the settings page and the Lua syntax. It does not know the API of the game.

### `cargo dev conformance`

Reads each Lua file of each addon and checks every name of the game's API in it against the API of this client: each `C_Namespace.Function`, each `Enum.Name.Value`, each event name, each method after a colon and each global function. It does not run the addon, so it also covers the lines that no test reaches. A name that this client does not have is a mistake, or code for another client that never runs here. Take such code out: do not write `C_Item and C_Item.GetItemInfo or GetItemInfo`.

### `cargo dev test`

Loads each addon in a stand-in for the game client and uses everything in it. Run it after each change. It takes a few seconds, and CI runs it on each push.

What it does with an addon:

1. Loads the files in the order of the TOC, then the saved variables, then sends `ADDON_LOADED`, `PLAYER_LOGIN` and `PLAYER_ENTERING_WORLD`. This is the order of the game: a saved variable is nil while the files load.
2. Runs the scenario of the addon, if it has one (see below).
3. Opens each settings page.
4. Runs each slash command: the words come from the help text of the command.
5. Uses each frame as a player can: opens its window if that is closed, shows and hides it, moves the pointer over it, clicks it, turns the mouse wheel, drags it, drags a slider, types in an edit box, and runs each entry of each menu.
6. Sends each event that the addon listens to, with arguments of the documented kinds.
7. Does steps 3 to 6 three times: alone, in a party, and in a fight in a raid. In the fight the values that the documentation marks as secret are secret values (see "Secret values" below).
8. Sends `PLAYER_LOGOUT`, saves the variables, and runs the addon a second time from them, as after `/reload`.

What makes an error show:

- **Names.** A function, an event, a frame type, a template, a font or a script name that the game does not have fails, the same as in the game. A widget has the methods of its own kind only: `texture:SetText()` fails. A template is for one kind of frame: a button template on a plain frame fails.
- **Arguments.** A documented function checks its arguments against the documentation: a missing required argument and a value of the wrong kind fail.
- **Secret values.** Arithmetic with a secret value and a comparison of order fail. `type` gives the real type, so a test of the type does not protect code that calculates. A secret value fails as an argument of a function that the documentation does not open to addon code, and as a table key. In the fight a result is secret where the documentation says so, for every documented function and event, hand-written or not: the health of a unit (`UnitHealth`), the name, GUID and class of a unit that no player controls, auras, cooldowns, the casts of other units, and each field of the damage meter that is not marked as never secret. The rule of each restriction is in `RULES` of `tools/harness/01-api.lua`, with the text of Blizzard's `SecretPredicatesDocumentation.lua` beside it.
- **Saved variables.** A function, a frame, a secret value or a table that contains itself in a saved variable fails: the game cannot save it.
- **Replaced functions.** An addon that puts its own function in the place of a global function of the game (`ToggleAllBags = function() ... end`) fails. In the game this is taint: the game's own code then runs addon code, and the game refuses what only its own UI may do, with "blocked from an action only available to the Blizzard UI". Use `hooksecurefunc`.
- **An addon that does not end.** A loop without an end stops with an error after three million lines, in a handler that runs again too. After two stops the addon is not called again.

The options:

| Option | What it shows |
|---|---|
| `cargo dev test ForeverBags` | One addon only |
| `--coverage` | For each file, the code lines that did not run. A line that did not run is not tested |
| `--caught` | The errors that a `pcall` of the addon caught, and the names that the addon looked for with `if Name then` and that are not there |

A name under "looked for, not there" is one of two things: a part of the game that the stand-in lacks, or a name that the game does not have. Find the name in the game's own UI code. If it is not there, the code behind the test never runs in the game.

#### Scenarios

`tools/harness/scenarios/<Addon>.lua` has what only one addon does, with checks of the results. Add one for each addon, and add to it with each feature.

```lua
local T = ...
local H, ns, expect = T.H, T.ns, T.expect

T.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
expect(ns.Lookup(2589).price == 150, "browsing stores 150 for Linen Cloth")
T.slash("/fah", "scan")
T.advance(2) -- two seconds pass: timers run
expect(H.count("full scan") == 1, "the full scan asks the game once")
```

| Name | What it is |
|---|---|
| `T.ns` | The table that the files of the addon share (`local _, ns = ...`) |
| `T.fire(event, ...)` | Sends an event with these arguments |
| `T.slash(command, text)` | Runs a slash command |
| `T.advance(seconds)` | Moves the clock, runs the timers that are due, then runs `OnUpdate` of each frame that is on the screen |
| `T.expect(condition, text)` | A check. The text says what is expected |
| `T.printed(pattern)` | A line that the addon printed and that matches, or nil |
| `T.world` | Switches of the world: `secret` (in a fight), `group` (`"party"` or `"raid"`), `dead`, `alt`, `shift`, `npc`, `choices`, `cvars`, `sayNo` (the answer to a confirmation), `zone` (the player is in Westfall) |
| `H.did`, `H.count(what)` | What the addon asked the game to do: `"accept"`, `"addon message"`, `"chat"`, `"full scan"` and so on |

A check must be able to fail. Do not expect a value that an earlier step stored already: give the world a different number for the step under test. A comment that says what happens is not a check.

#### Where the stand-in comes from

- **`tools/api/forever-api.json`** is the API of the game, from Blizzard's API documentation: each documented function with its arguments, its results and its flags for secret values, each widget method by widget kind, each event with its arguments, each enumeration, constant and structure. `cargo dev api-snapshot <folder> [note] [--out <file>]` builds it from the `Blizzard_APIDocumentationGenerated` folder of the [UI source](https://github.com/Gethe/wow-ui-source/tree/forever). Build it again after a patch of the game, with `--out` first: compare the new file with the old one before it takes its place. The command runs Blizzard's files with no file or OS access. Where the game takes more than its documentation says, `WIDER_ARGUMENTS` and the table of kinds in `tools/src/snapshot.rs` say so, each line with a call of the game's own code as the proof (`RegisterUnitEvent` takes unit names; `SetAttribute` takes any value).
- **`tools/api/forever-ui.json`** has what the documentation does not list, read from the game's own XML and Lua files. `cargo dev ui-names <Interface/AddOns folder>` builds it from the UI source. It has:
  - the fonts, and the events that the game's own code registers;
  - the frame types and animation types, and the lists of allowed texts (draw layers, strata, blend modes) of `Blizzard_SharedXML/UI.xsd`;
  - the scripts that the XML files put on each kind of widget;
  - each template of the XML files: its kind, what it inherits, its mixins, its child keys and its key values. `CreateFrame` with a template makes the frame from this record, so every template of the game works and has the right keys. A method of a mixin has its name on the frame; a call fails with "the stand-in does not have the method ... yet" until someone writes it in `TEMPLATES` of `02-widgets.lua`;
  - each call of a widget method in the game's Lua code whose arguments are written out, such as `frame:SetAttribute("shown", true)`. The stand-in must accept every one of them.
- **`tools/api/source.txt`** names the repository, the branch and the commit of the UI source that both files come from.
- **`tools/harness/01-api.lua` to `04-world.lua`** are the stand-in. `01` makes a function for each name of the snapshot. `02` has the widgets. `03` has the game's own windows and Lua code, which the documentation does not have. `04` has a small world: one character, a few items, two quests, an auction house, mail, a fight and a party.
- **`tools/harness/driver.lua`** does the steps above.

Rules for a change to the stand-in:

- Blizzard's documentation does not have every function. `GetCVar`, `IsInGroup` and the older tooltip methods are examples. Add such a name only after you find it in the game's own UI code of this client, and give the file: `setGlobal` and `undocumented` take it as an argument and fail without it.
- A hand-written function for a documented name goes in with `set`, `setGlobal` or `define`. These fail for a name that the snapshot does not have, and they keep the documented check of the arguments.
- Do not add a name to make a test pass. A missing name is what the test is for.
- Where the game returns nil and the documentation does not say so, `H.allowNil(name, reason)` says so, with the file of the game's code that shows it.
- A template needs no entry: it comes from `forever-ui.json`. Write an entry in `TEMPLATES` only for what the Lua code of the template does (a close button hides its parent). An entry cannot give the frame a field that the game's template does not have: the check fails. A field that the game's Lua code sets, and no XML file shows, goes in `fields` of the entry with the file.
- A function of `math`, `table` or `string` that the documentation lists and nobody wrote fails when an addon calls it. Write it in `01-api.lua`; a stub would give a wrong value without an error.

#### Conformance with Blizzard's files

The stand-in is checked too, so that a mistake in it cannot make a wrong addon pass or a correct one fail.

| Check | When | What it finds |
|---|---|---|
| Results of hand-written functions | Each `cargo dev test` | A hand-written function or widget method that returns another number of values, a value of another kind, nil where the documentation has a value, or a table with a field that the documented structure does not have. The failure is in the phase `stand-in` |
| Widget kinds | Each `cargo dev test` | A script object of the documentation that no widget kind uses and that is not on the list of those left out; a hand-written method for a name that its kind does not document |
| Form of the snapshot | `cargo test -p wfam-dev` | A letter, a flag or a structure name that the stand-in does not know |
| Calls of the game's own code | `cargo test -p wfam-dev` | A call that Blizzard's UI code makes and the stand-in refuses. Add each such case to the test `calls_of_the_games_own_code_pass` with its file |
| The stand-in against the game's UI files | `cargo dev conformance`, `cargo test -p wfam-dev` | A frame type or animation type of the game that the stand-in cannot make; a script that an XML file of the game puts on a kind and the stand-in refuses for that kind; a hand-written template that the game does not have, or that gives a field that the game's template lacks; a value of a list of `UI.xsd` that the stand-in refuses; and each of the about 3,800 calls with written-out arguments in the game's Lua code that the stand-in refuses. A call on a Lua object of the game that is not a widget goes on the list `NOT_A_WIDGET_CALL` in `02-widgets.lua`, with its file |
| `cargo dev api-snapshot <folder> --check` | CI, each push | Builds the snapshot again from the commit in `source.txt`. It must come out the same, byte for byte: the snapshot was not edited by hand, and the tool was not changed without it |
| `cargo dev ui-names <folder> --check` | CI, each push | The same for `forever-ui.json` |
| The workflow "API drift" | Each day | Both checks against the newest commit of the branch. It fails when a patch of the game changed the API, and lists each name that was added, removed or changed |

After a patch of the game: put the new commit in `tools/api/source.txt`, build both files again (`--out` first for the snapshot), then run `cargo dev conformance` and `cargo dev test`. A name that the addons use and the new client lacks fails there.

#### Where the sources say nothing

The stand-in follows these sources. Where two disagree, the game client wins, then the earlier one in this list:

1. Blizzard's API documentation.
2. The game's own UI code.
3. The tests of the [wowless](https://github.com/wowless/wowless) project (`addon/Wowless/uiobjects.lua` and `test.lua`). They run in the game client, so each one is a fact about the game: `OnShow` runs for the widgets under a frame before the frame; a tooltip with a text that is not an anchor takes `ANCHOR_LEFT` without an error; a button has no font string until it has a text; an anchor to itself and two regions anchored to each other fail with the game's error texts; an animation type that the game does not make from Lua gives a plain animation.
4. The page of the method on [warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/Widget_API): alpha stays between 0 and 1; `SetParent` takes no name; `SetAllPoints` takes a name; an intrinsic frame such as `ItemButton` says that it is of the type it is made from (`"Button"`). The game client confirmed each of these.

The source is named beside the code.

Where these sources say nothing, the game client itself was asked. `tools/ingame-probe/ForeverProbe` is a small addon with one case for each such question: copy the folder to `Interface/AddOns`, log in and type `/foreverprobe`, then `/reload`. It prints one line for each case and saves the lines in `ForeverProbeDB`. `tools/ingame-probe/answers.txt` has what client 1.60.1.70959 answered, and the test `the_stand_in_answers_the_probe_as_the_game_client_did` fails when the stand-in answers otherwise. The cases that the stand-in cannot or does not answer as the game are on the list `STAND_IN_ANSWERS_OTHERWISE` beside that test, each with the reason. From the answers:

- A point, a draw layer, a strata, a justify value and an animation type are taken in any letter case.
- A status bar and a slider bring a value into the range, also when `SetMinMaxValues` makes the range smaller than the value; a slider then calls `OnValueChanged`. A slider that obeys its step goes to a step in `SetValue`.
- `SetAllPoints(true)` and the strata `WORLD` give no error.
- `AbbreviateNumbers` leaves a number below 1000 as it is, with all its decimals. `CreateAbbreviateConfig` refuses a breakpoint of 0; `breakpointData` takes one, and then 345.678901 is `345`.
- The default of the CVar `showQuestObjectivesInLog` is `1`.

The probe also asks about secret values: which results are secret out of a fight and in one, and what the game does with `==`, a table key and `tostring` of a secret number. It runs these cases with `/foreverprobe`, and once more by itself two seconds after a fight starts: target an enemy NPC, attack it, wait for the line "cases of the fight are saved", then `/reload`. The answers are in `ForeverProbeDB.lines` and `ForeverProbeDB.fight` (`WTF/Account/<account>/SavedVariables/ForeverProbe.lua`). From the answers, for a fight with an NPC outside an instance:

- `UnitHealth` and `UnitInRange` are secret at all times, also out of a fight. So are `UnitPower` of the player and `UnitHealthMax` of a unit that is not the player's.
- `UnitArmor`, `GetCritChance` and the start and duration of a cooldown are secret in a fight and plain out of it.
- `UnitHealthMax` and `UnitThreatSituation` of the player are plain in a fight. So are the name, the GUID and the class of the NPC; the stand-in keeps those three secret in its fight, which stands for an encounter too.
- `C_UnitAuras.GetAuraDataByIndex` is an error for addon code in a fight.
- `==` with a secret value, a secret value as a table key and `if` on a secret boolean are errors. `~= nil` is not one, and gives a plain result. `type` gives the type of the hidden value; `tostring`, `string.format`, `..` and `AbbreviateNumbers` give a secret text.

Not asked yet: a target out of a fight, and `UnitCastingInfo` of a unit that casts.

Run the probe again after a patch of the game, and put the new answers in `answers.txt`. Add a case to the probe for each new question that no source settles.

After a patch that adds a restriction to the documentation, the test fails with "the stand-in has no rule for it" until the restriction is in `RULES` or `UNKNOWN` of `01-api.lua`.
#### What it cannot find

- How a window looks: positions, sizes, overlap.
- Taint other than a replaced function: an action that the game refuses because addon code touched a protected value or a frame of the game.
- What the game really returns. The stand-in returns a value of the documented kind, or the small world above.
- A function that the documentation does not list and the stand-in does not have. The game's own code calls about 580 such `C_` functions (`C_PetJournal`, `C_TradeSkillUI`, `C_LFGList` and others). An addon that calls one fails the test until the function is added with the file that proves it.
- Secret results under a restriction that the documentation does not explain. The list `UNKNOWN` in `tools/harness/01-api.lua` has each one with the reason: the threat values (`UnitDetailedThreatSituation`), the events of an encounter, and the values of widgets that were set from a secret value. These give plain values, also in the fight.
- Secret results outside a fight, but for the functions that the game client was asked about (`UnitHealth`, `UnitInRange`, `UnitPower`, `UnitHealthMax`). For every other function the stand-in makes a value secret in the fight only, and the documentation does not say if it is secret out of a fight too. Add a case to the probe for a function that an addon calculates with.
- Encounters, keystone dungeons, PvP matches and restricted maps. The world has none, so what is secret only there (chat messages in an instance) is plain.
- `==` with a secret value, and a test of a secret boolean. The game client fails there (the probe); Lua 5.1 gives the stand-in no way to see it. Test with `issecretvalue` first, before the type and before a comparison.
- Code that the test does not reach. `--coverage` shows it.

### In the game

- `/reload` loads changed files in a few seconds. A new file needs a restart of the game.
- `/console scriptErrors 1` shows each Lua error as it happens.
- `/fstack` shows the frame under the mouse, `/etrace` shows events as they fire, and `/dump <expression>` prints a value.

### The trace of a play session

The game writes no Lua error to the disk. Forever Trace (`addons/ForeverTrace`) keeps a record for a developer to read after the player has played:

- **Where:** `WTF/Account/<account>/SavedVariables/ForeverTrace.lua`, the saved variable `ForeverTraceDB`. The game writes it at `/reload` and at logout only: ask the player to type `/reload`, then read the file.
- **`errors`:** one entry for each different error, with a count: `{ id, kind, message, stack, locals, addon, forever, ours, count, first, last, version, early, shot, test }`. `kind` is `error` (a Lua error), `blocked` or `forbidden` (`ADDON_ACTION_BLOCKED` and the like), `taint` or `warning` (`LUA_WARNING`) or `reported` (an addon called `ForeverTrace.Error`). `addon` is the addon of the first file in the message or the stack, `forever` is the first Forever addon in them, and `ours` is true if there is one. `version` is the version of `forever` when the error was seen last; all versions of a session are in `sessions`, under the number in `first.session` and `last.session`. `early` marks an error from before Forever Trace loaded, `test` the error of `/ftrace test`. `shot` is the time in the file name of the screenshot, `Screenshots/WoWScrnShot_<shot>.jpg`; a screenshot is on the disk at once. The name is the second of the addon's call. If the clock went on before the game said that the screenshot was done, `shots` lists each name that the file can have, the first one first; `shot` is `failed` if the game took none. Only a screenshot that the addon asked for is given to an entry, not one of the Print Screen key.
- **`events`:** the last events, the oldest first: `{ kind, addon, text, n }` and a stamp. `kind` is `login`, `reload`, `world` (a loading screen), `zone`, `fight`, `log`, `mark` (the player typed `/ftrace mark <text>`), `screenshot`, `logout`, or the kind of an error. A `zone` line has `from`, the zone before; flips over one border are one line, with `n` crossings and the stamp of the last one. A `fight` line is written when the fight ends, with `seconds`: what happened in the fight is above it, with `fight` true. Fights with nothing between them are one line: `n` fights, `seconds` in all. The stamp of a fight line is the end of its first fight, `since` is the start of that fight and `till` the end of the last one: a line of many fights covers the time from `since` to `till`, not the moment of its stamp.
- **`marks`:** the markers of the player (`/ftrace mark <text>`), the oldest first, the last 100: a stamp, `text`, and `shot` (and `shots`, as for an error) if a screenshot was taken. They are in `events` too, but no other event pushes them out of this list.
- **A stamp** is `{ t, at, session, map, zone, fight }`: the time as a number and as a text, the number of the session (each login and each `/reload` starts one), the map ID, the name of the zone, and true in a fight. Inside an instance the game gives no map ID: `map` is absent there, and `/ftrace status` says so. `first` and `last` of an error are stamps.
- **`sessions`:** for each of the last 20 sessions the build of the game, the character, the versions of the loaded Forever addons, the names of the other loaded addons, `hook`: true if the hook for Lua errors was in place, and `test`: true if `/ftrace test` raised an error in that session and the record caught it, false if it did not. Only `test` true proves that Lua errors are seen: ask the player to type `/ftrace test` once.
- A value that the game hides is stored as the text `secret`.

An error that an addon hands to `geterrorhandler()` is in the trace already. For an error that an addon catches and keeps, and for a line of context, an addon calls:

```lua
if ForeverTrace then ForeverTrace.Error("ForeverBags", err) end
if ForeverTrace then ForeverTrace.Log("ForeverBags", "the bank opened") end
```
