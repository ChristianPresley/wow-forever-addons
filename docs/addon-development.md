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
- The game writes the quest level in front of quest names itself, for example `[12] Wanted: Hogger`.
- The auction house is the Mainline one (`AuctionHouseFrame`), with `C_AuctionHouse.ReplicateItems` for a full scan.
- An options page is a frame registered with `Settings.RegisterCanvasLayoutCategory` and `Settings.RegisterAddOnCategory`.

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

## Add an addon

1. Make `addons/<Name>/` with `<Name>.toc`, the Lua files and `addon.json`.
2. List each Lua file in the TOC.
3. Run `cargo dev lint`. It checks the TOC, `addon.json` and the Lua syntax.
4. Run `cargo link-addons` and test in the game with `/reload`.
5. Push to `main`. The publish workflow adds the addon to the marketplace.

## Test status

The lint and the tests of the manager run without the game. The addons themselves need a test in the game: no automated test loads them in a WoW client.
