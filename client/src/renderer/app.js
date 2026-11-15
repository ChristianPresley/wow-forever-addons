// Window logic of the Forever Addon Manager.
'use strict';

const api = window.wfam;

const state = {
  installs: [],
  selectedId: null,
  source: '',
  isDefaultSource: true,
  market: null,
  marketError: null,
  tab: 'market',
  busy: false,
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

async function call(promise) {
  const result = await promise;
  if (!result.ok) {
    const error = new Error(result.error);
    error.code = result.code;
    throw error;
  }
  return result.data;
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
    await call(api.install(install.id, addon.id, {}));
  } catch (error) {
    if (error.code !== 'UNMANAGED') throw error;
    const replace = window.confirm(
      `${addon.name} is already in your AddOns folder, but this manager did not install it.\n\nReplace that copy with version ${addon.version} from the marketplace?`,
    );
    if (!replace) throw new Error(`${addon.name} was not changed.`);
    await call(api.install(install.id, addon.id, { allowUnmanaged: true }));
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

function uninstall(name, folders, managed) {
  const question = managed
    ? `Remove ${name} from this install?\n\nIts settings in the WTF folder stay.`
    : `${name} was not installed by this manager.\n\nDelete its folder from AddOns anyway? Its settings in the WTF folder stay.`;
  if (!window.confirm(question)) return;
  const target = selectedInstall();
  run(() => call(api.uninstall(target.id, folders, { allowUnmanaged: !managed })), `${name} was removed.`);
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

refresh({ withMarket: true }).catch((error) => notify(error.message, 'error'));
