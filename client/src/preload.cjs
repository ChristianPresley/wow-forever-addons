// Bridge between the window and the main process. The window gets these functions only.

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('wfam', {
  scan: () => ipcRenderer.invoke('scan'),
  marketplace: () => ipcRenderer.invoke('marketplace'),
  install: (installId, addonId, options) => ipcRenderer.invoke('install', installId, addonId, options),
  uninstall: (installId, folders, options) => ipcRenderer.invoke('uninstall', installId, folders, options),
  addInstall: () => ipcRenderer.invoke('add-install'),
  setSource: (source) => ipcRenderer.invoke('set-source', source),
  openAddonsFolder: (installId) => ipcRenderer.invoke('open-addons-folder', installId),
});
