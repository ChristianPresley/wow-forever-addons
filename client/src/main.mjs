// Electron main process of the Forever Addon Manager.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { app, BrowserWindow, dialog, ipcMain, Menu, shell } from 'electron';

import { DEFAULT_SOURCE } from './core/marketplace.mjs';
import { Service } from './service.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));

// When the app runs from the repository, a locally built marketplace takes the place
// of the published one: run "npm run build:marketplace" in the repository root.
function defaultSource() {
  if (process.env.WFAM_SOURCE) return process.env.WFAM_SOURCE;
  if (!app.isPackaged) {
    const local = path.resolve(here, '..', '..', 'dist', 'marketplace', 'index.json');
    if (fs.existsSync(local)) return local;
  }
  return DEFAULT_SOURCE;
}

let service;
let window;

// Each handler answers { ok: true, data } or { ok: false, error, code }.
function handle(channel, handler) {
  ipcMain.handle(channel, async (_event, ...args) => {
    try {
      return { ok: true, data: await handler(...args) };
    } catch (error) {
      return { ok: false, error: error.message ?? String(error), code: error.code ?? null };
    }
  });
}

function registerHandlers() {
  handle('scan', () => service.scan());
  handle('marketplace', () => service.marketplace());
  handle('install', (installId, addonId, options) => service.install(String(installId), String(addonId), { allowUnmanaged: options?.allowUnmanaged === true }));
  handle('uninstall', (installId, folders, options) => {
    if (!Array.isArray(folders)) throw new Error('Invalid request.');
    return service.uninstall(String(installId), folders.map(String), { allowUnmanaged: options?.allowUnmanaged === true });
  });
  handle('add-install', async () => {
    const result = await dialog.showOpenDialog(window, {
      title: 'Select your World of Warcraft folder',
      properties: ['openDirectory'],
    });
    if (result.canceled || result.filePaths.length === 0) return { added: false, canceled: true };
    return { added: await service.addRoot(result.filePaths[0]), canceled: false };
  });
  handle('set-source', (source) => service.setSource(typeof source === 'string' ? source.trim() : ''));
  handle('open-addons-folder', async (installId) => {
    const install = service.findInstall(String(installId));
    const target = fs.existsSync(install.addonsDir) ? install.addonsDir : install.flavorDir;
    const error = await shell.openPath(target);
    if (error) throw new Error(error);
  });
}

function createWindow() {
  window = new BrowserWindow({
    width: 1120,
    height: 760,
    minWidth: 820,
    minHeight: 560,
    backgroundColor: '#14161a',
    title: 'Forever Addon Manager',
    webPreferences: {
      preload: path.join(here, 'preload.cjs'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
    },
  });
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', (event) => event.preventDefault());
  window.loadFile(path.join(here, 'renderer', 'index.html'));

  // WFAM_SCREENSHOT=<file.png> saves a picture of the window and exits. It is a smoke test.
  const screenshot = process.env.WFAM_SCREENSHOT;
  if (screenshot) {
    window.webContents.once('did-finish-load', () => {
      setTimeout(async () => {
        const image = await window.webContents.capturePage();
        fs.writeFileSync(screenshot, image.toPNG());
        app.quit();
      }, 3000);
    });
  }
}

app.whenReady().then(async () => {
  Menu.setApplicationMenu(null);
  service = new Service({
    settingsFile: path.join(app.getPath('userData'), 'settings.json'),
    defaultSource: defaultSource(),
  });
  await service.loadSettings();
  registerHandlers();
  createWindow();
});

app.on('window-all-closed', () => app.quit());
