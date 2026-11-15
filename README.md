# WoW: Forever Addons

Addons for **World of Warcraft: Forever**, and the **Forever Addon Manager**, a desktop app that finds your game install and installs or updates the addons from this repository.

![Forever Addon Manager](docs/client.png)

## Addons

| Addon | Folder | What it does | Command |
|---|---|---|---|
| Forever Auctions | [addons/ForeverAuctions](addons/ForeverAuctions) | Records the lowest price of each item you see at the auction house, and shows the price, its age and a 14-day average in item tooltips | `/fah` |
| Forever Atlas | [addons/ForeverAtlas](addons/ForeverAtlas) | Shows player and cursor coordinates on the world map, and records each area a character visits | `/fatlas` |
| Forever Quests | [addons/ForeverQuests](addons/ForeverQuests) | Tells you when a quest is ready to turn in, can accept and turn in quests for you (off by default), and counts quest experience | `/fq` |

## Repository layout

| Path | Contents |
|---|---|
| `addons/<Name>/` | One folder for each addon: `<Name>.toc`, the Lua files, and `addon.json` with the marketplace text |
| `client/` | The Forever Addon Manager (Electron) and its command-line form `wfam` |
| `client/src/core/` | Install detection, the ZIP reader and writer, and the install logic. No dependencies |
| `tools/` | Lint, marketplace build, and the development link script |
| `.github/workflows/` | Tests on each push, and the marketplace publish |

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

The manager finds installs from the Battle.net product database, the registry, and the usual folders on each drive. If it finds nothing, use **Add folder…** and select your World of Warcraft folder. It installs only into the `_forever_` flavor.

- An addon that the manager installed has a `.wfam.json` file in its folder. The manager updates and removes these without a question.
- An addon that you installed by hand is not changed unless you confirm it.
- A development link (see below) is never changed.
- Each package is checked against the SHA-256 in the marketplace index before it is installed.

If Electron does not start after the install, run `node client/node_modules/electron/install.js` one time to download its binary.

The same operations are available on the command line:

```bash
node client/bin/wfam.mjs detect
```

```bash
node client/bin/wfam.mjs market
```

```bash
node client/bin/wfam.mjs install forever-quests
```

## The marketplace

`npm run build:marketplace` writes one ZIP for each addon and an `index.json` to `dist/marketplace/`. The publish workflow uploads these files to the GitHub release with the tag `marketplace`. The manager reads the index from that release:

`https://github.com/ChristianPresley/wow-forever-addons/releases/download/marketplace/index.json`

The repository must be public for this URL to work without a sign-in. When you start the manager from the repository and `dist/marketplace/index.json` exists, the manager uses that local index. You can also set a different source in the app, or with the `WFAM_SOURCE` environment variable.

## Develop an addon

See [docs/addon-development.md](docs/addon-development.md) for the facts about the Forever client and the steps to add an addon.

```bash
npm run link
```

This command links each addon folder into `_forever_\Interface\AddOns`, so the game loads your working copy. Type `/reload` in the game after a change. `npm run unlink` removes the links.

```bash
npm test
```

This command checks the TOC files and the Lua syntax of each addon, and runs the tests of the client.

Not affiliated with Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment, Inc.
