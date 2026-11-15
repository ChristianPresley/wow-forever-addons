# WoW: Forever Addons

Addons for **World of Warcraft: Forever**, and the **Forever Addon Manager**, a desktop app that finds your game install and installs or updates the addons from this repository.

![Forever Addon Manager](docs/client.png)

## Addons

Addons are written in Lua. The game loads the `.toc` and `.lua` files of each addon folder and nothing else.

| Addon | Folder | What it does | Command |
|---|---|---|---|
| Forever Auctions | [addons/ForeverAuctions](addons/ForeverAuctions) | Records the lowest price of each item you see at the auction house, and shows the price, its age and a 14-day average in item tooltips | `/fah` |
| Forever Atlas | [addons/ForeverAtlas](addons/ForeverAtlas) | Shows player and cursor coordinates on the world map, and records each area a character visits | `/fatlas` |
| Forever Quests | [addons/ForeverQuests](addons/ForeverQuests) | Tells you when a quest is ready to turn in, can accept and turn in quests for you (off by default), and counts quest experience | `/fq` |

## Repository layout

| Path | Language | Contents |
|---|---|---|
| `addons/<Name>/` | Lua | One folder for each addon: `<Name>.toc`, the Lua files, and `addon.json` with the marketplace text |
| `client/core/` | Rust | Install detection, the marketplace reader and the install logic, with the `wfam` command line and the tests |
| `client/src-tauri/` | Rust | The desktop app (Tauri 2). It wraps `client/core` in commands for the window |
| `client/ui/` | HTML, CSS, JavaScript | The window of the desktop app. Plain files, no build step |
| `tools/` | Node | Addon lint, marketplace build and the icon source |
| `.github/workflows/` | | Tests on each push, and the marketplace publish |

## Requirements

- [Node](https://nodejs.org) 22 or later, for the tools and the Tauri command line.
- [Rust](https://rustup.rs) (stable), for the addon manager.
- On Windows: the Visual Studio 2022 Build Tools with the "Desktop development with C++" workload. WebView2 is part of Windows 11.

## Use the addon manager

```bash
npm install
```

```bash
npm --prefix client install
```

```bash
npm run build:marketplace
```

```bash
npm run client
```

`npm run client` builds and starts the app in development mode. `npm run client:build` makes a release build and a Windows installer in `client/target/release/bundle/`.

The manager finds installs from the Battle.net product database, the registry, and the usual folders on each drive. If it finds nothing, use **Add folder…** and select your World of Warcraft folder. It installs only into the `_forever_` flavor.

- An addon that the manager installed has a `.wfam.json` file in its folder. The manager updates these without a question.
- An addon that you installed by hand is not changed unless you confirm it.
- A development link (see below) is never changed.
- Each package is checked against the SHA-256 in the marketplace index before it is installed.

The same operations are available on the command line:

```bash
npm run wfam -- detect
```

```bash
npm run wfam -- market
```

```bash
npm run wfam -- install forever-quests
```

## The marketplace

`npm run build:marketplace` writes one ZIP for each addon and an `index.json` to `dist/marketplace/`. The publish workflow uploads these files to the GitHub release with the tag `marketplace`. The manager reads the index from that release:

`https://github.com/ChristianPresley/wow-forever-addons/releases/download/marketplace/index.json`

A development build of the manager uses the local `dist/marketplace/index.json` when that file exists. You can also set a different source in the app, or with the `WFAM_SOURCE` environment variable.

## Develop an addon

See [docs/addon-development.md](docs/addon-development.md) for the facts about the Forever client and the steps to add an addon.

```bash
npm run link
```

This command links each addon folder into `_forever_\Interface\AddOns`, so the game loads your working copy. Type `/reload` in the game after a change. `npm run unlink` removes the links.

```bash
npm test
```

This command checks the TOC files and the Lua syntax of each addon, and runs the tests of `client/core`.

Not affiliated with Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment, Inc.
