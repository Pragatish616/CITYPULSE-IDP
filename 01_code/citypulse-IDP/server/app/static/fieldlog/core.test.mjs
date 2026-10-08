// Run with:  node --test server/app/static/fieldlog/
// Tests the page logic (core.js) and the text tables (i18n.js) with no browser. ADR-028.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  ADHOC, Outbox, buildEntry, cleanToken, clockSkewWarning, defaultSites, formatDistance, haversineM, nearest, newId, normalise, searchSites, syncAll, toCsv, validateEntry,
} from './core.js';
import { TEXT, t } from './i18n.js';

const NOW = Date.parse('2026-10-05T18:00:00Z');
const SITES = [
  { id: 'tw1-0001', label: 'Classic farms Avenue (candidate tw1-0001)', lat: 12.9, lon: 80.2, basin_hint: 'Adyar' },
  { id: 'tw1-0002', label: 'Kalaingar Karunanidhi Road (candidate tw1-0002)', lat: 13.0, lon: 80.25, basin_hint: 'Cooum' },
  { id: 'tw1-0003', label: 'Velachery Main Road (candidate tw1-0003)', lat: 12.98, lon: 80.22, basin_hint: 'Adyar' },
  { id: 'tw1-0004', label: 'Unnamed road, near Pallikaranai (candidate tw1-0004)', lat: 12.93, lon: 80.21, near: 'Pallikaranai', basin_hint: 'Adyar' },
];

class MemStorage {
  constructor() { this.m = new Map(); this.full = false; }
  getItem(k) { return this.m.has(k) ? this.m.get(k) : null; }
  setItem(k, v) { if (this.full) throw new Error('QuotaExceededError'); this.m.set(k, v); }
}

const entry = (over = {}) => buildEntry({ siteId: 'tw1-0003', state: 'not_passable', depth: 'knee', nowMs: NOW, ...over });

// ---- ids, sites ---------------------------------------------------------------------------------------------------------------------

test('ids look like v4 UUIDs, with or without crypto.randomUUID', () => {
  const v4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
  assert.match(newId(), v4);
  assert.match(newId({ getRandomValues: (b) => { b.fill(7); return b; } }), v4);
  assert.match(newId(null), v4);
  assert.notEqual(newId(), newId());
});

test('distance is right to a few metres and nearest sorts by it', () => {
  assert.ok(Math.abs(haversineM(13.0827, 80.2707, 13.0827, 80.2707)) < 1e-6);
  const d = haversineM(12.9791, 80.2209, 13.0012, 80.2565); // Velachery to Adyar, about 4.5 km
  assert.ok(d > 4300 && d < 4900, String(d));
  const n = nearest(SITES, { lat: 12.981, lon: 80.221 }, 2);
  assert.deepEqual(n.map((s) => s.id), ['tw1-0003', 'tw1-0002']);
  assert.ok(n[0].distance_m < 400);
  assert.equal(formatDistance(250), '250 m');
  assert.equal(formatDistance(1240), '1.2 km');
});

test('search needs every word, ignores case and Latin accents, ranks label-start first, and keeps Tamil intact', () => {
  assert.deepEqual(searchSites(SITES, 'velachery').map((s) => s.id), ['tw1-0003']);
  assert.deepEqual(searchSites(SITES, 'ROAD main').map((s) => s.id), ['tw1-0003']);
  assert.deepEqual(searchSites(SITES, 'adyar').map((s) => s.id), ['tw1-0001', 'tw1-0003', 'tw1-0004']);
  assert.deepEqual(searchSites(SITES, 'pallikaranai').map((s) => s.id), ['tw1-0004'], 'a neighbourhood name finds the sites near it');
  assert.deepEqual(searchSites(SITES, 'tw1-0002').map((s) => s.id), ['tw1-0002']);
  assert.deepEqual(searchSites(SITES, 'zzz'), []);
  assert.deepEqual(searchSites(SITES, '   '), []);
  assert.equal(normalise('Café  Road'), 'cafe road');
  assert.equal(normalise('வேளச்சேரி'), 'வேளச்சேரி', 'Tamil vowel signs must survive');
});

// ---- entries ------------------------------------------------------------------------------------------------------------------------

test('an entry takes the phone time as UTC and keeps depth only when blocked', () => {
  const e = entry();
  assert.equal(e.observed_at, '2026-10-05T18:00:00.000Z');
  assert.equal(e.depth_band, 'knee');
  assert.equal(entry({ state: 'passable' }).depth_band, undefined);
  assert.deepEqual(validateEntry(e, NOW), []);
});

test('an ad hoc entry carries a position rounded to 4 places, a listed site never does', () => {
  const e = entry({ siteId: ADHOC, state: 'unknown', depth: null, pos: { lat: 13.08273999, lon: 80.27071999 } });
  assert.deepEqual([e.lat, e.lon], [13.0827, 80.2707]);
  assert.deepEqual(validateEntry(e, NOW), []);
  assert.equal(entry({ pos: { lat: 13, lon: 80 } }).lat, undefined);
  assert.deepEqual(validateEntry({ ...e, lat: undefined, lon: undefined }, NOW).map((p) => p.key), ['adhoc_needs_position']);
  assert.deepEqual(validateEntry({ ...entry(), lat: 13, lon: 80 }, NOW).map((p) => p.key), ['position_only_adhoc']);
});

test('validation mirrors the server: state, site, time, depth', () => {
  const keys = (e) => validateEntry(e, NOW).map((p) => p.key);
  assert.deepEqual(keys({ ...entry(), state: 'dry' }), ['bad_state', 'depth_needs_blocked']);
  assert.deepEqual(keys({ ...entry(), site_id: 'Bad Id' }), ['bad_site']);
  assert.deepEqual(keys({ ...entry(), observed_at: 'yesterday' }), ['bad_time']);
  assert.deepEqual(keys({ ...entry(), observed_at: new Date(NOW + 6 * 60000).toISOString() }), ['future']);
  assert.deepEqual(keys({ ...entry(), observed_at: new Date(NOW + 4 * 60000).toISOString() }), []);
  assert.deepEqual(keys({ ...entry(), observed_at: new Date(NOW - 15 * 86400000).toISOString() }), ['too_old']);
  assert.deepEqual(keys({ ...entry({ state: 'passable' }), depth_band: 'knee' }), ['depth_needs_blocked']);
  assert.deepEqual(keys({ ...entry(), depth_band: 'deep' }), ['bad_depth']);
});

test('a pasted token loses its spaces and line breaks', () => {
  assert.equal(cleanToken('  abc def\n123\t'), 'abcdef123');
  assert.equal(cleanToken(null), '');
});

// ---- the outbox ---------------------------------------------------------------------------------------------------------------------

test('the outbox survives a reload and ignores a repeated id', () => {
  const store = new MemStorage();
  const a = new Outbox(store);
  const e = entry();
  assert.equal(a.add(e, 'Velachery'), true);
  assert.equal(a.add(e, 'Velachery'), false);
  const b = new Outbox(store); // the page was closed and reopened
  assert.equal(b.items.length, 1);
  assert.equal(b.pending()[0].site_label, 'Velachery');
});

test('a broken or hostile stored value is ignored, not a crash', () => {
  for (const raw of ['not json', '{"a":1}', 'null', '[1,2,{"x":1}]']) {
    const s = new MemStorage();
    s.setItem('fieldlog.outbox.v1', raw);
    assert.deepEqual(new Outbox(s).items, []);
  }
});

test('a full phone is reported to the caller, not swallowed', () => {
  const s = new MemStorage();
  const box = new Outbox(s);
  s.full = true;
  assert.throws(() => box.add(entry()), /Quota/);
});

test('recent lists newest first and prune only drops old acknowledged entries', () => {
  const box = new Outbox(new MemStorage());
  const old = entry({ nowMs: NOW - 10 * 86400000, id: newId() });
  const mid = entry({ nowMs: NOW - 8 * 86400000, id: newId() });
  const fresh = entry({ nowMs: NOW, id: newId() });
  [old, mid, fresh].forEach((e) => box.add(e));
  box.mark(old.entry_id, { status: 'synced', synced_at: new Date(NOW - 9 * 86400000).toISOString() });
  box.mark(mid.entry_id, { status: 'rejected' });
  assert.deepEqual(box.recent(3).map((i) => i.entry.entry_id), [fresh.entry_id, mid.entry_id, old.entry_id]);
  assert.equal(box.prune(NOW), 1);
  assert.deepEqual(box.items.map((i) => i.status).sort(), ['queued', 'rejected']);
  assert.deepEqual(box.counts(), { queued: 1, synced: 0, rejected: 1 });
});

// ---- syncing ------------------------------------------------------------------------------------------------------------------------

function filled(n = 3) {
  const box = new Outbox(new MemStorage());
  const ids = [];
  for (let i = 0; i < n; i++) {
    const e = entry({ nowMs: NOW - (n - i) * 60000, id: newId() });
    box.add(e);
    ids.push(e.entry_id);
  }
  return { box, ids };
}

test('sync sends oldest first, marks acknowledged entries synced, and reports clock skew', async () => {
  const { box, ids } = filled(3);
  const sent = [];
  const r = await syncAll(box, async (e) => { sent.push(e.entry_id); return { status: 201, body: { received_at: new Date(NOW - 5 * 60000).toISOString() } }; }, () => NOW);
  assert.deepEqual(sent, ids);
  assert.deepEqual([r.synced, r.rejected, r.stopped], [3, 0, null]);
  assert.equal(r.skewSeconds, 300);
  assert.equal(clockSkewWarning(r.skewSeconds), 300);
  assert.equal(clockSkewWarning(30), null);
  assert.equal(box.counts().synced, 3);
});

test('a duplicate answer counts as acknowledged', async () => {
  const { box } = filled(1);
  const r = await syncAll(box, async () => ({ status: 200, body: {} }), () => NOW);
  assert.deepEqual([r.synced, r.duplicates], [0, 1]);
  assert.equal(box.counts().synced, 1);
});

test('a network error stops the round and keeps everything queued', async () => {
  const { box } = filled(3);
  let calls = 0;
  const r = await syncAll(box, async () => { calls += 1; throw new TypeError('offline'); }, () => NOW);
  assert.equal(calls, 1, 'does not hammer a down server');
  assert.equal(r.stopped, 'network');
  assert.equal(box.counts().queued, 3);
  assert.equal(box.pending()[0].attempts, 1);
});

test('429 and 5xx stop the round and keep entries queued', async () => {
  for (const status of [429, 500, 502, 503]) {
    const { box } = filled(2);
    const r = await syncAll(box, async () => ({ status, body: {} }), () => NOW);
    assert.equal(r.stopped, 'retry', String(status));
    assert.equal(box.counts().queued, 2);
  }
});

test('422 and 409 are permanent: the entry is rejected with the reasons and the round carries on', async () => {
  const { box, ids } = filled(3);
  let n = 0;
  const r = await syncAll(box, async () => {
    n += 1;
    if (n === 1) return { status: 422, body: { problems: [{ field: 'site_id', message: 'unknown site' }] } };
    if (n === 2) return { status: 409, body: {} };
    return { status: 201, body: {} };
  }, () => NOW);
  assert.deepEqual([r.rejected, r.synced, r.stopped], [2, 1, null]);
  assert.equal(box.find(ids[0]).status, 'rejected');
  assert.equal(box.find(ids[0]).problems[0].message, 'unknown site');
  assert.equal(box.find(ids[1]).problems[0].message, 'conflict');
});

test('401 and 403 stop the round with a specific reason and nothing is lost', async () => {
  for (const [status, why] of [[401, 'auth'], [403, 'disabled']]) {
    const { box } = filled(2);
    const r = await syncAll(box, async () => ({ status, body: {} }), () => NOW);
    assert.equal(r.stopped, why);
    assert.equal(box.counts().queued, 2);
  }
});

// ---- export -------------------------------------------------------------------------------------------------------------------------

test('the CSV has a header, quotes awkward cells, and neutralises formulas', () => {
  const box = new Outbox(new MemStorage());
  const e = entry();
  box.add(e, '=HYPERLINK("http://x","click")');
  box.add(entry({ id: newId(), state: 'passable' }), 'Road, with "quotes"');
  const csv = toCsv(box.items);
  const lines = csv.trim().split('\n');
  assert.equal(lines[0], 'entry_id,site_id,site_label,state,observed_at_utc,depth_band,lat,lon,sync_status,synced_at_utc');
  assert.ok(lines[1].includes(`"'=HYPERLINK(""http://x"",""click"")"`), lines[1]);
  assert.ok(lines[2].includes('"Road, with ""quotes"""'), lines[2]);
  assert.equal(lines.length, 3);
});

// ---- text ---------------------------------------------------------------------------------------------------------------------------

test('every English key has Tamil text and the other way round', () => {
  const flat = (o, p = '') => Object.entries(o).flatMap(([k, v]) => (typeof v === 'object' ? flat(v, `${p}${k}.`) : [`${p}${k}`]));
  assert.deepEqual(flat(TEXT.ta).sort(), flat(TEXT.en).sort());
  for (const k of flat(TEXT.en)) assert.ok(t('ta', k).length > 0 && t('en', k).length > 0, k);
});

test('placeholders are filled and a missing key shows itself instead of blank', () => {
  assert.equal(t('en', 'pending_count', { n: 3 }), '3 waiting to send');
  assert.ok(t('ta', 'pending_count', { n: 3 }).startsWith('3 '));
  assert.equal(t('en', 'no.such.key'), 'no.such.key');
  for (const lang of ['en', 'ta']) assert.ok(t(lang, 'clock_warn', { n: 7 }).includes('7'));
});

test('the page never tells anyone a road is safe, dry, clear or fine to go', () => {
  const banned = /\b(safe|safely|safest|dry|clear|cleared|open|fine|go ahead|all clear|good to go|no risk|risk-free)\b/i;
  const flat = (o) => Object.values(o).flatMap((v) => (typeof v === 'object' ? flat(v) : [v]));
  for (const s of flat(TEXT.en)) assert.ok(!banned.test(s), s);
  const stems = ['பாதுகாப்', 'வறண்', 'காய்ந்', 'செல்லலாம்', 'போகலாம்', 'கடக்கலாம்', 'தொடரலாம்', 'திறந்', 'தெளிவாக'];
  for (const s of flat(TEXT.ta)) for (const stem of stems) assert.ok(!s.includes(stem), `${stem} in ${s}`);
});

// ---- subways (ADR-031) -------------------------------------------------------------------------------------------------------
const SUBWAYS = [
  { id: 'sub-gcc-rr-12', site_kind: 'subway', label: 'Madley subway (GCC road/rail subway 12) [sub-gcc-rr-12]', lat: 13.035, lon: 80.227, near: 'Thiyagaraya Nagar', aliases: ['Madley road and Easwaran Koil Street'] },
  { id: 'sub-gcc-rr-03', site_kind: 'subway', label: 'Stanley Nagar subways (GCC road/rail subway 3) [sub-gcc-rr-03]', lat: null, lon: null, near: 'Stanley Nagar', aliases: ['CB road subway', 'Cochrane Basin Bridge Road'] },
  { id: 'sub-gcc-rr-04', site_kind: 'subway', label: 'Reserve Bank (RBI) subway (GCC road/rail subway 4) [sub-gcc-rr-04]', lat: 13.085, lon: 80.289, near: 'George Town', aliases: ['இந்தியா ரிசர்வ் வங்கி சுரங்கப்பாதை'] },
];
const MIXED = [...SUBWAYS, ...SITES.map((s) => ({ ...s, site_kind: 'hazard_zone' }))];

test('a subway with no known position is left out of distances, never given NaN', () => {
  const out = nearest(SUBWAYS, { lat: 13.03, lon: 80.22 }, 12);
  assert.deepEqual(out.map((s) => s.id), ['sub-gcc-rr-12', 'sub-gcc-rr-04']);
  assert.ok(out.every((s) => Number.isFinite(s.distance_m)));
});

test('search finds a subway by an alias, by its area, or by Tamil text', () => {
  assert.deepEqual(searchSites(SUBWAYS, 'CB road').map((s) => s.id), ['sub-gcc-rr-03']);
  assert.deepEqual(searchSites(SUBWAYS, 'stanley nagar').map((s) => s.id), ['sub-gcc-rr-03']);
  assert.deepEqual(searchSites(SUBWAYS, 'ரிசர்வ் வங்கி').map((s) => s.id), ['sub-gcc-rr-04']);
  assert.deepEqual(searchSites(SUBWAYS, 'Easwaran Koil').map((s) => s.id), ['sub-gcc-rr-12']);
});

test('before any search the subways are listed first; with a position the placed ones go by distance, none is lost', () => {
  assert.deepEqual(defaultSites(MIXED, null).map((s) => s.id), ['sub-gcc-rr-12', 'sub-gcc-rr-03', 'sub-gcc-rr-04']);
  const withPos = defaultSites(MIXED, { lat: 13.085, lon: 80.289 }).map((s) => s.id);
  assert.deepEqual(withPos.slice(0, 3), ['sub-gcc-rr-04', 'sub-gcc-rr-12', 'sub-gcc-rr-03']);
  assert.ok(withPos.includes('tw1-0002'), 'hazard-zone points follow the subways');
});

