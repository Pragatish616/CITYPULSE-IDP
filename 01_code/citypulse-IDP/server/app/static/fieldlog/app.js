// Field-log page: wires core.js to the DOM (ADR-028). No innerHTML anywhere: every string goes in through textContent.
import {
  ADHOC, Outbox, buildEntry, cleanToken, clockSkewWarning, defaultSites, formatDistance, searchSites, syncAll, toCsv, validateEntry,
} from './core.js';
import { t } from './i18n.js';

const $ = (id) => document.getElementById(id);
const api = (path) => new URL(path, document.baseURI).toString();

// ---- storage that degrades honestly ------------------------------------------------------------------------------------------------

function makeStorage() {
  try {
    const k = '__fieldlog_probe__';
    localStorage.setItem(k, '1');
    localStorage.removeItem(k);
    return { storage: localStorage, durable: true };
  } catch {
    const m = new Map();
    return { storage: { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), removeItem: (k) => m.delete(k) }, durable: false };
  }
}
const { storage, durable } = makeStorage();
const get = (k, d = '') => { try { return storage.getItem(k) ?? d; } catch { return d; } };
const put = (k, v) => { try { storage.setItem(k, v); return true; } catch { return false; } };

// ---- state ---------------------------------------------------------------------------------------------------------------------------

let lang = get('fieldlog.lang') || ((navigator.language || '').toLowerCase().startsWith('ta') ? 'ta' : 'en');
let token = get('fieldlog.token');
let sites = [];
let pos = null; // the phone's position, kept in memory only and used only to sort the list
let chosen = null; // {id, label, pos?}
let pending = null; // {state, atMs}
let pendingDepth = null;
let syncing = false;
let serverOff = false;
let authBad = false;
let skew = null;
let sitesFailed = false;
let unreachable = false;
const outbox = new Outbox(storage);

const tt = (k, v) => t(lang, k, v);
const locale = () => (lang === 'ta' ? 'ta-IN' : 'en-IN');
const fmtTime = (ms) => new Date(ms).toLocaleString(locale(), { dateStyle: 'medium', timeStyle: 'medium' });

function el(tag, props = {}, ...kids) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === 'class') n.className = v;
    else if (k === 'text') n.textContent = v;
    else if (k.startsWith('on')) n.addEventListener(k.slice(2), v);
    else n.setAttribute(k, v);
  }
  for (const kid of kids) if (kid) n.append(kid);
  return n;
}

function toast(msg) {
  const box = $('toast');
  box.textContent = msg;
  box.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { box.hidden = true; }, 3800);
}

// ---- rendering -----------------------------------------------------------------------------------------------------------------------

function applyText() {
  document.documentElement.lang = lang;
  for (const n of document.querySelectorAll('[data-i18n]')) n.textContent = tt(n.dataset.i18n);
  $('lang').textContent = tt('language');
  $('lang').lang = lang === 'ta' ? 'en' : 'ta';
}

function renderNotices() {
  const box = $('notices');
  box.replaceChildren();
  const add = (text) => box.append(el('p', { class: 'notice', text }));
  if (!durable) add(tt('storage_memory'));
  if (!navigator.onLine) add(tt('offline'));
  if (serverOff) add(tt('server_off'));
  if (unreachable) add(tt('server_unreachable'));
  const w = clockSkewWarning(skew);
  if (w != null) add(tt('clock_warn', { n: Math.max(1, Math.round(Math.abs(w) / 60)) }));
  if (sitesFailed) add(tt('sites_failed'));
}

function renderNet() {
  const on = navigator.onLine;
  $('net').textContent = on ? tt('net_online') : tt('net_offline');
  $('net').className = `badge ${on ? 'online' : 'offline'}`;
}

function renderSites() {
  const q = $('search').value;
  let list = [];
  if (q.trim()) list = searchSites(sites, q);
  else list = defaultSites(sites, pos);
  const ul = $('site-list');
  ul.replaceChildren();
  for (const s of list) {
    const unplaced = s.site_kind === 'subway' && typeof s.lat !== 'number';
    const meta = [s.distance_m != null ? formatDistance(s.distance_m) : null, unplaced ? tt('position_unknown') : null, unplaced ? s.near : null, s.hazard_category, s.basin_hint ? `${s.basin_hint}?` : null].filter(Boolean).join(' · ');
    ul.append(el('li', {}, el('button', { type: 'button', class: 'site', onclick: () => chooseSite({ id: s.id, label: s.label }) }, el('span', { text: s.label }), el('span', { class: 'meta', text: meta }))));
  }
  $('site-none').hidden = !(q.trim() && list.length === 0);
}

function renderChosen() {
  $('chosen-card').hidden = !chosen;
  $('site-picker').hidden = !!chosen;
  $('state-picker').hidden = !chosen;
  if (chosen) $('chosen-label').textContent = chosen.label;
}

function renderHistory() {
  const items = outbox.recent(20);
  const ul = $('history');
  ul.replaceChildren();
  for (const i of items) {
    const e = i.entry;
    const word = e.depth_band ? `${tt(e.state)} · ${tt(`depth_${e.depth_band}`)}` : tt(e.state);
    const li = el('li', { class: 'entry' },
      el('div', { class: 'row' }, el('strong', { text: word }), el('span', { class: `status ${i.status}`, text: tt(`status_${i.status}`) })),
      el('div', { text: i.site_label || e.site_id }),
      el('div', { class: 'when', text: fmtTime(Date.parse(e.observed_at)) }));
    if (i.status === 'rejected' && i.problems) {
      const ul2 = el('ul', { class: 'reasons' });
      for (const p of i.problems) ul2.append(el('li', { text: p.message || p.field }));
      li.append(ul2);
    }
    ul.append(li);
  }
  $('history-empty').hidden = items.length > 0;
  const c = outbox.counts();
  $('pending').textContent = c.queued ? tt('pending_count', { n: c.queued }) : '';
  $('sync-now').disabled = syncing || c.queued === 0 || !token;
  $('export').disabled = outbox.items.length === 0;
}

function render() {
  applyText();
  renderNet();
  renderNotices();
  const ready = !!token;
  $('token-section').hidden = ready;
  $('log-section').hidden = !ready;
  $('history-section').hidden = !ready;
  if (ready) {
    renderChosen();
    renderSites();
    renderHistory();
  }
}

// ---- token ---------------------------------------------------------------------------------------------------------------------------

async function saveToken() {
  const typed = cleanToken($('token-input').value);
  const err = $('token-error');
  err.hidden = true;
  if (typed.length < 16) {
    err.textContent = tt('token_bad');
    err.hidden = false;
    return;
  }
  try {
    const res = await fetch(api('whoami'), { headers: { 'x-fieldlog-token': typed }, cache: 'no-store' });
    if (res.status === 401 || res.status === 429) {
      err.textContent = tt('token_bad');
      err.hidden = false;
      return;
    }
    if (res.status === 403) serverOff = true;
  } catch {
    toast(tt('token_offline')); // not online: keep it, the first send will check it
  }
  token = typed;
  authBad = false;
  put('fieldlog.token', token);
  $('token-input').value = '';
  render();
  trySync();
}

// ---- sites ---------------------------------------------------------------------------------------------------------------------------

async function loadSites() {
  try {
    const res = await fetch(api('sites'), { cache: 'no-cache' });
    if (!res.ok) throw new Error(String(res.status));
    const doc = await res.json();
    sites = doc.sites;
    put('fieldlog.sites.v1', JSON.stringify(doc));
    sitesFailed = false;
  } catch {
    try {
      sites = JSON.parse(get('fieldlog.sites.v1', '{"sites":[]}')).sites;
    } catch {
      sites = [];
    }
    sitesFailed = sites.length === 0;
  }
  render();
}

function locate() {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) return reject(new Error('unsupported'));
    navigator.geolocation.getCurrentPosition(
      (p) => resolve({ lat: p.coords.latitude, lon: p.coords.longitude }),
      (e) => reject(e),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 30000 },
    );
  });
}

async function showNear() {
  const status = $('near-status');
  status.hidden = false;
  status.textContent = tt('near_wait');
  try {
    pos = await locate();
    status.hidden = true;
    $('search').value = '';
    renderSites();
  } catch {
    status.textContent = tt('near_denied');
  }
}

async function chooseAdhoc() {
  const status = $('near-status');
  status.hidden = false;
  status.textContent = tt('near_wait');
  try {
    const p = await locate();
    status.hidden = true;
    chooseSite({ id: ADHOC, label: tt('adhoc_label'), pos: p });
  } catch {
    status.textContent = tt('near_denied');
  }
}

function chooseSite(s) {
  chosen = s;
  pending = null;
  render();
  window.scrollTo({ top: 0 });
}

// ---- logging -------------------------------------------------------------------------------------------------------------------------

const dialog = () => $('confirm');
function openDialog() {
  const d = dialog();
  if (typeof d.showModal === 'function') d.showModal();
  else d.setAttribute('open', '');
}
function closeDialog() {
  const d = dialog();
  if (typeof d.close === 'function') d.close();
  else d.removeAttribute('open');
}

function startLog(state) {
  if (!chosen) return;
  pending = { state, atMs: Date.now() };
  pendingDepth = null;
  $('confirm-site').textContent = chosen.label;
  $('confirm-state').textContent = tt(state);
  $('confirm-time').textContent = fmtTime(pending.atMs);
  $('depth-picker').hidden = state !== 'not_passable';
  for (const c of document.querySelectorAll('.chip')) c.setAttribute('aria-pressed', 'false');
  $('confirm-error').hidden = true;
  for (const b of document.querySelectorAll('.state')) b.setAttribute('aria-pressed', String(b.dataset.state === state));
  openDialog();
}

function confirmLog() {
  const err = $('confirm-error');
  err.hidden = true;
  if (!pending || !chosen) return;
  const entry = buildEntry({ siteId: chosen.id, state: pending.state, depth: pendingDepth, pos: chosen.pos ?? null, nowMs: pending.atMs });
  const problems = validateEntry(entry);
  if (problems.length) {
    err.textContent = problems.map((p) => tt(`reasons.${p.key}`)).join(' ');
    err.hidden = false;
    return;
  }
  try {
    outbox.add(entry, chosen.label);
  } catch {
    // The phone could not keep it. Say so; the entry is NOT logged.
    err.textContent = tt('storage_full');
    err.hidden = false;
    return;
  }
  closeDialog();
  pending = null;
  for (const b of document.querySelectorAll('.state')) b.setAttribute('aria-pressed', 'false');
  toast(tt('saved'));
  renderHistory();
  trySync();
}

// ---- sending -------------------------------------------------------------------------------------------------------------------------

async function post(entry) {
  const res = await fetch(api('entries'), {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-fieldlog-token': token },
    body: JSON.stringify(entry),
    cache: 'no-store',
  });
  let body = {};
  try { body = await res.json(); } catch { /* an error page, not JSON */ }
  return { status: res.status, body };
}

async function trySync() {
  if (syncing || !token || outbox.pending().length === 0) return;
  syncing = true;
  renderHistory();
  try {
    const r = await syncAll(outbox, post);
    if (r.skewSeconds != null) skew = r.skewSeconds;
    serverOff = r.stopped === 'disabled';
    unreachable = r.stopped === 'network' || r.stopped === 'retry';
    authBad = r.stopped === 'auth';
    if (r.synced + r.duplicates > 0) toast(tt('synced'));
    if (authBad) {
      token = '';
      put('fieldlog.token', '');
      $('token-error').textContent = tt('token_bad');
      $('token-error').hidden = false;
    }
  } finally {
    syncing = false;
    render();
  }
}

// ---- wiring --------------------------------------------------------------------------------------------------------------------------

$('lang').addEventListener('click', () => { lang = lang === 'ta' ? 'en' : 'ta'; put('fieldlog.lang', lang); render(); });
$('token-save').addEventListener('click', saveToken);
$('token-input').addEventListener('keydown', (e) => { if (e.key === 'Enter') saveToken(); });
$('near-btn').addEventListener('click', showNear);
$('adhoc-btn').addEventListener('click', chooseAdhoc);
$('search').addEventListener('input', renderSites);
$('change-site').addEventListener('click', () => { chosen = null; pending = null; render(); });
for (const b of document.querySelectorAll('.state')) b.addEventListener('click', () => startLog(b.dataset.state));
for (const c of document.querySelectorAll('.chip')) {
  c.addEventListener('click', () => {
    pendingDepth = pendingDepth === c.dataset.depth ? null : c.dataset.depth;
    for (const o of document.querySelectorAll('.chip')) o.setAttribute('aria-pressed', String(o.dataset.depth === pendingDepth));
  });
}
$('confirm-yes').addEventListener('click', confirmLog);
$('confirm-no').addEventListener('click', () => { closeDialog(); pending = null; for (const b of document.querySelectorAll('.state')) b.setAttribute('aria-pressed', 'false'); });
$('sync-now').addEventListener('click', trySync);
$('export').addEventListener('click', () => {
  const blob = new Blob([toCsv(outbox.items)], { type: 'text/csv;charset=utf-8' });
  const a = el('a', { href: URL.createObjectURL(blob), download: `fieldlog-${new Date().toISOString().slice(0, 10)}.csv` });
  document.body.append(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
});
window.addEventListener('online', () => { renderNet(); renderNotices(); trySync(); });
window.addEventListener('offline', () => { renderNet(); renderNotices(); });
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') trySync(); });
setInterval(() => { if (document.visibilityState === 'visible') trySync(); }, 60000);

outbox.prune();
render();
loadSites();
trySync();
if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => { /* optional: the page works without it */ });
