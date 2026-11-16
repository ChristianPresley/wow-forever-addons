// Window logic of the Forever Addon Manager. The page runs in the Tauri webview.
'use strict';

// The commands of the Rust side (client/src-tauri/src/main.rs).
const invoke = window.__TAURI__.core.invoke;
const api = {
  scan: () => invoke('scan'),
  marketplace: () => invoke('marketplace'),
  install: (installId, addonId, allowUnmanaged) => invoke('install', { installId, addonId, allowUnmanaged }),
  uninstall: (installId, folders, allowUnmanaged) => invoke('uninstall', { installId, folders, allowUnmanaged }),
  addInstall: () => invoke('add_install'),
  setSource: (source) => invoke('set_source', { source }),
  openAddonsFolder: (installId) => invoke('open_addons_folder', { installId }),
  updateAll: () => invoke('update_all'),
  setAutoUpdate: (enabled) => invoke('set_auto_update', { enabled }),
};

// With "Update automatically" on, the manager looks for updates when it starts and then at this interval.
const AUTO_UPDATE_MINUTES = 30;

const state = {
  installs: [],
  selectedId: null,
  source: '',
  isDefaultSource: true,
  market: null,
  marketError: null,
  tab: 'market',
  busy: false,
  autoUpdate: false,
  autoStatus: '',
};

const $ = (id) => document.getElementById(id);

function h(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key === 'class') node.className = value;
    else if (key === 'onclick') node.addEventListener('click', value);
    else if (value === true) node.setAttribute(key, '');
    else if (value !== false && value != null) node.setAttribute(key, value);
  }
  for (const child of children.flat()) {
    if (child != null && child !== false) node.append(child);
  }
  return node;
}

// A failed command rejects with { message, code }. This turns it into an Error.
async function call(promise) {
  try {
    return await promise;
  } catch (failure) {
    const error = new Error(failure?.message ?? String(failure));
    error.code = failure?.code ?? null;
    throw error;
  }
}

/** Asks a yes-or-no question in a dialog. Resolves to true if the user agrees. */
function ask(title, text, yesLabel) {
  const dialog = $('confirm');
  $('confirm-title').textContent = title;
  $('confirm-text').textContent = text;
  $('confirm-yes').textContent = yesLabel;
  return new Promise((resolve) => {
    const finish = (answer) => {
      $('confirm-yes').onclick = null;
      $('confirm-no').onclick = null;
      dialog.onclose = null;
      if (dialog.open) dialog.close();
      resolve(answer);
    };
    $('confirm-yes').onclick = () => finish(true);
    $('confirm-no').onclick = () => finish(false);
    dialog.onclose = () => finish(false);
    dialog.showModal();
    $('confirm-no').focus();
  });
}

function compareVersions(a, b) {
  const parts = (v) => String(v ?? '').replace(/^v/i, '').split(/[-+]/)[0].split('.').map((p) => Number.parseInt(p, 10) || 0);
  const pa = parts(a);
  const pb = parts(b);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const diff = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (diff !== 0) return diff;
  }
  return 0;
}

function selectedInstall() {
  return state.installs.find((install) => install.id === state.selectedId) ?? null;
}

/** How a marketplace addon relates to the selected install. */
function statusOf(addon, install) {
  const present = addon.folders.map((folder) => install.addons.find((item) => item.folder === folder)).filter(Boolean);
  if (present.length === 0) return { kind: 'absent' };
  const first = present[0];
  if (first.linked) return { kind: 'linked', version: first.version };
  const managed = present.every((item) => item.managed);
  const outdated = compareVersions(first.version, addon.version) < 0;
  return { kind: outdated ? 'outdated' : 'current', version: first.version, managed };
}

function notify(message, kind = '') {
  const notice = $('notice');
  notice.hidden = !message;
  notice.className = `notice ${kind}`.trim();
  notice.textContent = message ?? '';
}

// ---- Actions ----

async function refresh({ withMarket = false } = {}) {
  const scan = await call(api.scan());
  state.installs = scan.installs;
  state.source = scan.source;
  state.isDefaultSource = scan.isDefaultSource;
  state.autoUpdate = scan.autoUpdate;
  if (!selectedInstall()) state.selectedId = state.installs[0]?.id ?? null;
  if (withMarket || !state.market) {
    try {
      state.market = await call(api.marketplace());
      state.marketError = null;
    } catch (error) {
      state.market = null;
      state.marketError = error.message;
    }
  }
  render();
}

async function run(action, successMessage) {
  if (state.busy) return;
  state.busy = true;
  render();
  try {
    await action();
    notify(successMessage, 'success');
  } catch (error) {
    notify(error.message, 'error');
  } finally {
    state.busy = false;
    await refresh().catch((error) => notify(error.message, 'error'));
  }
}

async function installOne(install, addon) {
  try {
    await call(api.install(install.id, addon.id, false));
  } catch (error) {
    if (error.code !== 'UNMANAGED') throw error;
    const replace = await ask(
      `Replace ${addon.name}?`,
      `${addon.name} is already in your AddOns folder, but this manager did not install it. Replace that copy with version ${addon.version} from the marketplace?`,
      'Replace',
    );
    if (!replace) throw new Error(`${addon.name} was not changed.`);
    await call(api.install(install.id, addon.id, true));
  }
}

function install(addon) {
  const target = selectedInstall();
  return run(() => installOne(target, addon), `${addon.name} ${addon.version} is installed. Type /reload in the game to load it.`);
}

function updateAll() {
  const target = selectedInstall();
  const outdated = state.market.addons.filter((addon) => {
    const status = statusOf(addon, target);
    return status.kind === 'outdated' && status.managed;
  });
  return run(async () => {
    for (const addon of outdated) await installOne(target, addon);
  }, `${outdated.length} addon(s) updated. Type /reload in the game to load them.`);
}

/**
 * Installs each available update of the addons that this manager installed, in every install.
 * It asks no question: a copy installed by hand and a development link are left as they are.
 */
async function autoUpdate() {
  if (!state.autoUpdate || state.busy) return;
  state.busy = true;
  state.autoStatus = 'Looking for updates…';
  render();
  const time = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  try {
    const report = await call(api.updateAll());
    const updated = report.updated.map((addon) => `${addon.name} ${addon.from} → ${addon.to}`);
    const failed = report.failed.map((failure) => `${failure.name}: ${failure.message}`);
    if (failed.length > 0) {
      notify(`Not updated automatically. ${failed.join(' ')}`, 'error');
    } else if (updated.length > 0) {
      notify(`Updated automatically: ${updated.join(', ')}. Type /reload in the game to load ${updated.length === 1 ? 'it' : 'them'}.`, 'success');
    }
    state.autoStatus = updated.length > 0 ? `${updated.length} updated at ${time}.` : `Up to date. Checked at ${time}.`;
  } catch (error) {
    state.autoStatus = `The check at ${time} failed. ${error.message}`;
  } finally {
    state.busy = false;
    await refresh({ withMarket: true }).catch((error) => notify(error.message, 'error'));
  }
}

async function uninstall(name, folders, managed) {
  const question = managed
    ? `This deletes the addon folder from this install. Its settings in the WTF folder stay.`
    : `${name} was not installed by this manager. This deletes its folder from AddOns. Its settings in the WTF folder stay.`;
  if (!(await ask(`Remove ${name}?`, question, 'Remove'))) return;
  const target = selectedInstall();
  run(() => call(api.uninstall(target.id, folders, !managed)), `${name} was removed.`);
}

// ---- Rendering ----

function renderSidebar() {
  const list = $('installs');
  list.replaceChildren();
  if (state.installs.length === 0) {
    list.append(
      h('li', { class: 'empty-side' }, 'No WoW: Forever install was found. Use "Add folder…" and select your World of Warcraft folder.'),
    );
  }
  for (const install of state.installs) {
    list.append(
      h(
        'li',
        {},
        h(
          'button',
          {
            class: 'install',
            'aria-current': String(install.id === state.selectedId),
            onclick: () => {
              state.selectedId = install.id;
              notify(null);
              render();
            },
          },
          h('div', { class: 'install-name' }, `WoW: Forever${install.version ? ` ${install.version}` : ''}`),
          h('div', { class: 'install-meta' }, install.flavorDir),
        ),
      ),
    );
  }
  $('source-value').textContent = state.isDefaultSource ? `Default: ${state.source}` : state.source;
  $('auto-update').checked = state.autoUpdate;
  $('auto-update').disabled = state.busy;
  $('auto-status').textContent = state.autoUpdate
    ? state.autoStatus || `Checks when the manager starts and every ${AUTO_UPDATE_MINUTES} minutes while it is open.`
    : 'Off. Use the Update buttons.';
}

function marketCard(addon, install) {
  const status = statusOf(addon, install);
  const chips = [h('span', { class: 'chip' }, addon.category)];
  const actions = [];
  if (status.kind === 'absent') {
    actions.push(h('button', { disabled: state.busy, onclick: () => install && installAddonClick(addon) }, 'Install'));
  } else if (status.kind === 'linked') {
    chips.push(h('span', { class: 'chip dev' }, 'Development link'));
  } else if (status.kind === 'outdated') {
    chips.push(h('span', { class: 'chip update' }, `Update: ${status.version} → ${addon.version}`));
    actions.push(h('button', { disabled: state.busy, onclick: () => installAddonClick(addon) }, 'Update'));
  } else {
    chips.push(h('span', { class: 'chip ok' }, status.managed ? 'Installed' : `Installed by hand (${status.version || 'no version'})`));
    if (!status.managed) actions.push(h('button', { class: 'ghost', disabled: state.busy, onclick: () => installAddonClick(addon) }, 'Reinstall'));
  }
  if (status.kind === 'outdated' || status.kind === 'current') {
    actions.push(h('button', { class: 'danger', disabled: state.busy, onclick: () => uninstall(addon.name, addon.folders, status.managed) }, 'Remove'));
  }
  return h(
    'article',
    { class: 'card' },
    h(
      'div',
      { class: 'card-body' },
      h('div', { class: 'card-title' }, h('span', { class: 'card-name' }, addon.name), h('span', { class: 'card-version' }, addon.version), chips),
      h('div', { class: 'card-text' }, addon.description || addon.summary),
    ),
    h('div', { class: 'card-actions' }, actions),
  );
}

function installAddonClick(addon) {
  install(addon);
}

function installedCard(item, install) {
  const marketAddon = state.market?.addons.find((addon) => addon.folders.includes(item.folder));
  const chips = [];
  const actions = [];
  if (item.linked) chips.push(h('span', { class: 'chip dev' }, 'Development link'));
  else if (item.managed) chips.push(h('span', { class: 'chip ok' }, 'Managed'));
  else chips.push(h('span', { class: 'chip' }, 'Installed by hand'));
  if (marketAddon && !item.linked && compareVersions(item.version, marketAddon.version) < 0) {
    chips.push(h('span', { class: 'chip update' }, `Update: ${marketAddon.version}`));
    actions.push(h('button', { disabled: state.busy, onclick: () => installAddonClick(marketAddon) }, 'Update'));
  }
  if (!item.linked) {
    actions.push(
      h('button', { class: 'danger', disabled: state.busy, onclick: () => uninstall(item.title, marketAddon?.folders ?? [item.folder], Boolean(item.managed)) }, 'Remove'),
    );
  }
  return h(
    'article',
    { class: 'card' },
    h(
      'div',
      { class: 'card-body' },
      h('div', { class: 'card-title' }, h('span', { class: 'card-name' }, item.title), h('span', { class: 'card-version' }, item.version), chips),
      h('div', { class: 'card-text' }, `AddOns\\${item.folder}`),
    ),
    h('div', { class: 'card-actions' }, actions),
  );
}

function renderMain() {
  const install = selectedInstall();
  $('install-title').textContent = install ? `WoW: Forever${install.version ? ` ${install.version}` : ''}` : 'No install selected';
  $('install-path').textContent = install ? install.addonsDir : '';
  $('open-folder').hidden = !install;
  $('installed-count').textContent = install ? `(${install.addons.length})` : '';
  for (const tab of document.querySelectorAll('.tab')) tab.setAttribute('aria-selected', String(tab.dataset.tab === state.tab));

  const list = $('list');
  list.replaceChildren();
  $('update-all').hidden = true;

  if (!install) {
    list.append(h('div', { class: 'empty' }, 'Add your World of Warcraft folder to see and install addons.'));
    return;
  }
  if (state.tab === 'market') {
    if (state.marketError) {
      list.append(h('div', { class: 'empty' }, `The marketplace could not be loaded. ${state.marketError}`));
      return;
    }
    if (!state.market || state.market.addons.length === 0) {
      list.append(h('div', { class: 'empty' }, 'The marketplace has no addons yet.'));
      return;
    }
    const outdated = state.market.addons.filter((addon) => {
      const status = statusOf(addon, install);
      return status.kind === 'outdated' && status.managed;
    });
    $('update-all').hidden = outdated.length === 0;
    $('update-all').disabled = state.busy;
    $('update-all').textContent = `Update all (${outdated.length})`;
    for (const addon of state.market.addons) list.append(marketCard(addon, install));
  } else {
    if (install.addons.length === 0) {
      list.append(h('div', { class: 'empty' }, 'This install has no addons.'));
      return;
    }
    for (const item of install.addons) list.append(installedCard(item, install));
  }
}

function render() {
  renderSidebar();
  renderMain();
}

// ---- Wiring ----

for (const tab of document.querySelectorAll('.tab')) {
  tab.addEventListener('click', () => {
    state.tab = tab.dataset.tab;
    render();
  });
}

$('rescan').addEventListener('click', () => {
  notify(null);
  refresh({ withMarket: true }).catch((error) => notify(error.message, 'error'));
});

$('add-install').addEventListener('click', async () => {
  try {
    const result = await call(api.addInstall());
    if (result.canceled) return;
    if (!result.added) notify('That folder has no WoW: Forever install. Select the World of Warcraft folder that holds "_forever_".', 'error');
    else notify(null);
    await refresh();
  } catch (error) {
    notify(error.message, 'error');
  }
});

$('open-folder').addEventListener('click', () => {
  const install = selectedInstall();
  if (install) call(api.openAddonsFolder(install.id)).catch((error) => notify(error.message, 'error'));
});

$('update-all').addEventListener('click', updateAll);

$('change-source').addEventListener('click', () => {
  const form = $('source-form');
  form.hidden = !form.hidden;
  $('source-input').value = state.isDefaultSource ? '' : state.source;
  if (!form.hidden) $('source-input').focus();
});

async function saveSource(value) {
  try {
    await call(api.setSource(value));
    $('source-form').hidden = true;
    notify(null);
    await refresh({ withMarket: true });
  } catch (error) {
    notify(error.message, 'error');
  }
}

$('source-form').addEventListener('submit', (event) => {
  event.preventDefault();
  saveSource($('source-input').value);
});
$('source-default').addEventListener('click', () => saveSource(''));

$('auto-update').addEventListener('change', async (event) => {
  const enabled = event.target.checked;
  try {
    await call(api.setAutoUpdate(enabled));
    state.autoUpdate = enabled;
    state.autoStatus = '';
    render();
    if (enabled) await autoUpdate();
  } catch (error) {
    notify(error.message, 'error');
    render();
  }
});

refresh({ withMarket: true })
  .then(autoUpdate)
  .catch((error) => notify(error.message, 'error'));
setInterval(() => autoUpdate().catch((error) => notify(error.message, 'error')), AUTO_UPDATE_MINUTES * 60 * 1000);
