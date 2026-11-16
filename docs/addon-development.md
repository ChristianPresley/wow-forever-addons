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
- **The combat log is closed to addons.**
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

## Test status

The lint and the tests of the manager run without the game. The addons themselves need a test in the game: no automated test loads them in a WoW client.
