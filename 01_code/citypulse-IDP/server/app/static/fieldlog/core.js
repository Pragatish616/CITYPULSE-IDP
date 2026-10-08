// Field-log page logic with no DOM in it, so it can be tested with Node (core.test.mjs). ADR-028.
// Everything that decides what is stored, what is sent and what is shown lives here; app.js only wires it to the page.

export const STATES = ['passable', 'not_passable', 'unknown'];
export const DEPTHS = ['ankle', 'knee', 'above_knee', 'unknown'];
export const ADHOC = 'adhoc';
export const MAX_AGE_MS = 14 * 24 * 3600 * 1000;
export const CLOCK_WARN_SECONDS = 120;
const FORMULA_START = new Set(['=', '+', '-', '@', '\t', '\r']);

/** A random v4 id. crypto.randomUUID needs a secure context; the fallback keeps an old browser working. */
export function newId(cryptoObj = globalThis.crypto) {
  if (cryptoObj && typeof cryptoObj.randomUUID === 'function') return cryptoObj.randomUUID();
  const b = new Uint8Array(16);
  if (cryptoObj && cryptoObj.getRandomValues) cryptoObj.getRandomValues(b);
  else for (let i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

// ---- sites ---------------------------------------------------------------------------------------------------------------------------

export function haversineM(lat1, lon1, lat2, lon2) {
  const R = 6371008.8;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** The `n` sites closest to `pos` ({lat, lon}), each with `distance_m`. The position stays on the phone. */
export function nearest(sites, pos, n = 12) {
  return sites
    .filter((s) => typeof s.lat === 'number' && typeof s.lon === 'number') // a subway whose position is not known cannot be placed
    .map((s) => ({ ...s, distance_m: haversineM(pos.lat, pos.lon, s.lat, s.lon) }))
    .sort((a, b) => a.distance_m - b.distance_m || a.id.localeCompare(b.id))
    .slice(0, n);
}

/** Lower-case, trim, collapse spaces, and drop Latin accents only (Tamil vowel signs are combining marks and must stay). */
export function normalise(s) {
  return String(s ?? '')
    .toLowerCase()
    .replace(/[A-Za-zÀ-ɏ]+/g, (w) => w.normalize('NFD').replace(/[̀-ͯ]/g, ''))
    .replace(/\s+/g, ' ')
    .trim();
}

/** Sites whose label, id or basin hint contains every word of `query`; best matches (label starts with the first word) first. */
export function searchSites(sites, query, limit = 30) {
  const words = normalise(query).split(' ').filter(Boolean);
  if (!words.length) return [];
  const scored = [];
  for (const s of sites) {
    const hay = normalise(`${s.label} ${s.id} ${s.near ?? ''} ${s.basin_hint ?? ''} ${(s.aliases ?? []).join(' ')}`);
    if (words.every((w) => hay.includes(w))) scored.push({ s, rank: normalise(s.label).startsWith(words[0]) ? 0 : 1 });
  }
  scored.sort((a, b) => a.rank - b.rank || a.s.id.localeCompare(b.s.id));
  return scored.slice(0, limit).map((x) => x.s);
}

/**
 * What to list before anyone has searched: the subways (the places the pilot asks volunteers about). With the phone's position,
 * the nearest placed subways, then those whose position is unknown (so none is lost), then the closest hazard-zone points.
 */
export function defaultSites(sites, pos, limit = 12) {
  const subways = sites.filter((s) => s.site_kind === 'subway');
  if (!pos) return subways;
  const near = nearest(subways, pos, limit);
  const unplaced = subways.filter((s) => typeof s.lat !== 'number' || typeof s.lon !== 'number');
  const rest = nearest(sites.filter((s) => s.site_kind !== 'subway'), pos, 6);
  return [...near, ...unplaced, ...rest];
}

export function formatDistance(m) {
  return m < 1000 ? `${Math.round(m / 10) * 10} m` : `${(m / 1000).toFixed(1)} km`;
}

// ---- entries -------------------------------------------------------------------------------------------------------------------------

/** Mirrors the server's rules (models.py) so a mistake is caught on the phone before it is queued. Returns a list of {field, key}. */
export function validateEntry(e, nowMs = Date.now()) {
  const problems = [];
  if (!STATES.includes(e.state)) problems.push({ field: 'state', key: 'bad_state' });
  if (typeof e.site_id !== 'string' || !/^[a-z0-9][a-z0-9_-]{1,31}$/.test(e.site_id)) problems.push({ field: 'site_id', key: 'bad_site' });
  const t = Date.parse(e.observed_at);
  if (Number.isNaN(t)) problems.push({ field: 'observed_at', key: 'bad_time' });
  else if (t > nowMs + 5 * 60 * 1000) problems.push({ field: 'observed_at', key: 'future' });
  else if (t < nowMs - MAX_AGE_MS) problems.push({ field: 'observed_at', key: 'too_old' });
  if (e.depth_band != null && e.state !== 'not_passable') problems.push({ field: 'depth_band', key: 'depth_needs_blocked' });
  if (e.depth_band != null && !DEPTHS.includes(e.depth_band)) problems.push({ field: 'depth_band', key: 'bad_depth' });
  if (e.site_id === ADHOC) {
    if (typeof e.lat !== 'number' || typeof e.lon !== 'number') problems.push({ field: 'lat', key: 'adhoc_needs_position' });
  } else if (e.lat != null || e.lon != null) problems.push({ field: 'lat', key: 'position_only_adhoc' });
  return problems;
}

/** Builds an entry. The time is the phone's clock at the moment of the tap, as UTC. */
export function buildEntry({ siteId, state, depth = null, pos = null, nowMs = Date.now(), id = newId(), client = 'web-1' }) {
  const e = { entry_id: id, site_id: siteId, state, observed_at: new Date(nowMs).toISOString(), client };
  if (depth != null && state === 'not_passable') e.depth_band = depth;
  if (siteId === ADHOC && pos) {
    // The server rounds again; rounding here means the position is never held more precisely than it will be stored.
    e.lat = Math.round(pos.lat * 1e4) / 1e4;
    e.lon = Math.round(pos.lon * 1e4) / 1e4;
  }
  return e;
}

// ---- the outbox: durable on the phone until the server has acknowledged ---------------------------------------------------------------

/** Items are {entry, status: queued|synced|rejected, attempts, last_error, problems, synced_at, site_label}. `storage` is localStorage-shaped. */
export class Outbox {
  constructor(storage, key = 'fieldlog.outbox.v1') {
    this.storage = storage;
    this.key = key;
    this.items = [];
    this.load();
  }

  load() {
    try {
      const raw = this.storage.getItem(this.key);
      const parsed = raw ? JSON.parse(raw) : [];
      this.items = Array.isArray(parsed) ? parsed.filter((i) => i && i.entry && i.entry.entry_id) : [];
    } catch {
      this.items = [];
    }
  }

  save() {
    // Throws if the phone is full: the caller must tell the volunteer, never swallow it.
    this.storage.setItem(this.key, JSON.stringify(this.items));
  }

  add(entry, siteLabel = '') {
    if (this.items.some((i) => i.entry.entry_id === entry.entry_id)) return false;
    this.items.push({ entry, status: 'queued', attempts: 0, last_error: null, problems: null, synced_at: null, site_label: siteLabel });
    this.save();
    return true;
  }

  find(id) {
    return this.items.find((i) => i.entry.entry_id === id);
  }

  pending() {
    return this.items.filter((i) => i.status === 'queued');
  }

  counts() {
    const c = { queued: 0, synced: 0, rejected: 0 };
    for (const i of this.items) c[i.status] += 1;
    return c;
  }

  mark(id, patch) {
    const it = this.find(id);
    if (!it) return;
    Object.assign(it, patch);
    this.save();
  }

  /** Newest first, as the volunteer expects to read them. */
  recent(n = 20) {
    return [...this.items].sort((a, b) => Date.parse(b.entry.observed_at) - Date.parse(a.entry.observed_at)).slice(0, n);
  }

  /** Forget acknowledged entries older than `ageMs`. Queued and rejected ones are never dropped silently. */
  prune(nowMs = Date.now(), ageMs = 7 * 24 * 3600 * 1000) {
    const before = this.items.length;
    this.items = this.items.filter((i) => !(i.status === 'synced' && nowMs - Date.parse(i.synced_at ?? i.entry.observed_at) > ageMs));
    if (this.items.length !== before) this.save();
    return before - this.items.length;
  }
}

/**
 * Send every queued entry, oldest first. `post(entry)` resolves to {status, body} or rejects on a network failure.
 * - 201 / 200 : acknowledged (a repeat is fine), marked synced.
 * - 409 / 422 : the server will never accept this as it is; marked rejected with the reasons, not retried.
 * - 401       : the token is wrong; stop and say so (nothing else will work either).
 * - 403       : logging is switched off on the server; stop.
 * - 429 / 5xx / network error : try again later; stop this round so a down server is not hammered.
 */
export async function syncAll(outbox, post, nowMs = () => Date.now()) {
  const result = { synced: 0, duplicates: 0, rejected: 0, stopped: null, skewSeconds: null };
  const todo = [...outbox.pending()].sort((a, b) => Date.parse(a.entry.observed_at) - Date.parse(b.entry.observed_at));
  for (const item of todo) {
    let res;
    try {
      res = await post(item.entry);
    } catch (err) {
      outbox.mark(item.entry.entry_id, { attempts: item.attempts + 1, last_error: 'network' });
      result.stopped = 'network';
      break;
    }
    const id = item.entry.entry_id;
    if (res.status === 201 || res.status === 200) {
      outbox.mark(id, { status: 'synced', synced_at: new Date(nowMs()).toISOString(), last_error: null, attempts: item.attempts + 1 });
      if (res.status === 200) result.duplicates += 1;
      else result.synced += 1;
      const rec = res.body && res.body.received_at ? Date.parse(res.body.received_at) : NaN;
      if (!Number.isNaN(rec)) result.skewSeconds = Math.round((nowMs() - rec) / 1000);
    } else if (res.status === 409 || res.status === 422) {
      outbox.mark(id, { status: 'rejected', problems: (res.body && res.body.problems) || [{ field: 'entry', message: res.status === 409 ? 'conflict' : 'rejected' }], attempts: item.attempts + 1 });
      result.rejected += 1;
    } else if (res.status === 401) {
      outbox.mark(id, { attempts: item.attempts + 1, last_error: 'auth' });
      result.stopped = 'auth';
      break;
    } else if (res.status === 403) {
      outbox.mark(id, { attempts: item.attempts + 1, last_error: 'disabled' });
      result.stopped = 'disabled';
      break;
    } else {
      outbox.mark(id, { attempts: item.attempts + 1, last_error: `http_${res.status}` });
      result.stopped = 'retry';
      break;
    }
  }
  return result;
}

/** Is the phone's clock far from the server's? Seconds, signed (positive: the phone is ahead). Null if unknown. */
export function clockSkewWarning(skewSeconds) {
  return skewSeconds != null && Math.abs(skewSeconds) > CLOCK_WARN_SECONDS ? skewSeconds : null;
}

// ---- export from the phone ------------------------------------------------------------------------------------------------------------

const CSV_HEAD = ['entry_id', 'site_id', 'site_label', 'state', 'observed_at_utc', 'depth_band', 'lat', 'lon', 'sync_status', 'synced_at_utc'];

function cell(v) {
  let s = v == null ? '' : String(v);
  if (s && FORMULA_START.has(s[0])) s = `'${s}`;
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/** The volunteer's own copy as CSV; formula-looking cells are neutralised so a spreadsheet cannot run them. */
export function toCsv(items) {
  const rows = [CSV_HEAD.join(',')];
  for (const i of items) {
    const e = i.entry;
    rows.push([e.entry_id, e.site_id, i.site_label, e.state, e.observed_at, e.depth_band, e.lat, e.lon, i.status, i.synced_at].map(cell).join(','));
  }
  return `${rows.join('\n')}\n`;
}

/** The token as typed: spaces and line breaks from a paste removed. */
export function cleanToken(raw) {
  return String(raw ?? '').replace(/\s+/g, '');
}
