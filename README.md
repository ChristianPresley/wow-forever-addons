# WoW: Forever Addons

Addons for **World of Warcraft: Forever**, and the **Forever Addon Manager**, a desktop app that finds your game install and installs or updates the addons from this repository.

![Forever Addon Manager](docs/client.png)

## Addons

Addons are written in Lua. The game loads the `.toc` and `.lua` files of each addon folder and nothing else.

| Addon | Folder | What it does | Command |
|---|---|---|---|
| Forever Auctions | [addons/ForeverAuctions](addons/ForeverAuctions) | Records auction house prices as you browse, or all at once with the full scan button. Shows auction, vendor and stack values in item tooltips, suggests an undercut price when you post, and has a searchable price history window | `/fah` |
| Forever Atlas | [addons/ForeverAtlas](addons/ForeverAtlas) | Shows coordinates on the world map and on screen. Sets waypoints with a direction arrow (`/way 45.2 61.8`), keeps your own map notes (Alt-click the map), and pins each area a character has visited | `/fatlas` |
| Forever Compass | [addons/ForeverCompass](addons/ForeverCompass) | Puts up to four compasses on screen. Each one points to the nearest thing of a kind you choose, with its name and distance: quest objectives, turn-ins, quest givers, rare enemies, flight masters, party members and more. Vendors, repairers, trainers, bankers, auctioneers and mailboxes are learned as you visit them | `/fcompass` |
| Forever Quests | [addons/ForeverQuests](addons/ForeverQuests) | Tells you when a quest is ready to turn in, and can accept and turn in quests for you (off by default). Can show only the quests of your current zone in the quest log and the tracker (`/fq zone`). Shows the vendor price of each reward choice, shares objective progress with party members, and counts quest experience | `/fq` |

Each addon has a full settings page in the game's Options window, under AddOns. This is a requirement for every addon in the repository, and the lint checks it.

## Repository layout

Everything outside the addons is Rust, in one Cargo workspace.

| Path | Language | Contents |
|---|---|---|
| `addons/<Name>/` | Lua | One folder for each addon: `<Name>.toc`, the Lua files, and `addon.json` with the marketplace text |
| `client/core/` | Rust | Install detection, the marketplace reader and the install logic, with the `wfam` command line |
| `client/src-tauri/` | Rust | The desktop app (Tauri 2). It wraps `client/core` in commands for the window |
| `client/ui/` | HTML, CSS, JavaScript | The window of the desktop app, which Tauri shows in a webview. Plain files, no build step |
| `tools/` | Rust | Repository tools: addon lint, marketplace build and the icon source |
| `.cargo/config.toml` | | Short names for the commands below |
| `.github/workflows/` | | Tests on each push, and the marketplace publish |

## Requirements

- [Rust](https://rustup.rs) (stable).
- On Windows: the Visual Studio 2022 Build Tools with the "Desktop development with C++" workload. WebView2 is part of Windows 11.
- For the desktop app, the Tauri command line:

```bash
cargo install tauri-cli --version "^2" --locked
```

## Commands

Run these from any folder of the repository.

| Command | What it does |
|---|---|
| `cargo dev lint` | Checks the TOC, `addon.json`, the file list, the settings page and the Lua syntax of each addon |
| `cargo dev marketplace` | Writes one ZIP for each addon and an `index.json` to `dist/marketplace/` |
| `cargo dev icon <out.png>` | Draws the source image of the app icon |
| `cargo wfam <command>` | The addon manager on the command line: `detect`, `list`, `market`, `install <id>`, `uninstall <id>` |
| `cargo link-addons` | Links each addon folder into the game, so the game loads your working copy |
| `cargo unlink-addons` | Removes those links |
| `cargo test -p wfam-core -p wfam-dev` | Runs the tests of the manager core and the tools |
| `cargo tauri dev` | Builds and starts the desktop app in development mode |
| `cargo tauri build` | Makes a release build and a Windows installer in `target/release/bundle/` |

## Use the addon manager

```bash
cargo dev marketplace
```

```bash
cargo tauri dev
```

The manager finds installs from the Battle.net product database, the registry, and the usual folders on each drive. If it finds nothing, use **Add folder…** and select your World of Warcraft folder. It installs only into the `_forever_` flavor.

- An addon that the manager installed has a `.wfam.json` file in its folder. The manager updates these without a question.
- An addon that you installed by hand is not changed unless you confirm it.
- A development link (see below) is never changed.
- Each package is checked against the SHA-256 in the marketplace index before it is installed.

The same operations are available on the command line:

```bash
cargo wfam detect
```

```bash
cargo wfam market
```

```bash
cargo wfam install forever-quests
```

## The marketplace

`cargo dev marketplace` writes one ZIP for each addon and an `index.json` to `dist/marketplace/`. The publish workflow uploads these files to the GitHub release with the tag `marketplace`. The manager reads the index from that release:

`https://github.com/ChristianPresley/wow-forever-addons/releases/download/marketplace/index.json`

A development build of the manager uses the local `dist/marketplace/index.json` when that file exists. You can also set a different source in the app, or with the `WFAM_SOURCE` environment variable.

## Develop an addon

See [docs/addon-development.md](docs/addon-development.md) for the facts about the Forever client and the steps to add an addon.

```bash
cargo link-addons
```

This command links each addon folder into `_forever_\Interface\AddOns`. Type `/reload` in the game after a change. `cargo unlink-addons` removes the links.

Not affiliated with Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment, Inc.
