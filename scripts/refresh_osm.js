'use strict';
// scripts/refresh_osm.js
// Downloads OSM chargers for Tamil Nadu + Puducherry and syncs the stations table:
//   - rows already linked by osm_id  -> updated
//   - old OSM rows without osm_id    -> linked (within 100 m)
//   - near any other row (<100 m)    -> skipped as duplicate
//   - otherwise                      -> inserted
//   - linked OSM rows no longer in OSM -> is_active = 0 (never deleted)
// Dry run by default. Add --apply to write changes.
require('dotenv').config();
const fs = require('fs');
const db = require('../db');

const APPLY = process.argv.includes('--apply');
const DUP_KM = 0.1;

const QUERY = `
[out:json][timeout:180];
area["ISO3166-2"="IN-TN"]->.tn;
area["ISO3166-2"="IN-PY"]->.py;
(
  node["amenity"="charging_station"](area.tn);
  way["amenity"="charging_station"](area.tn);
  node["amenity"="charging_station"](area.py);
  way["amenity"="charging_station"](area.py);
);
out center tags;
`;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchOsm() {
  for (let attempt = 1; attempt <= 4; attempt++) {
    try {
      const res = await fetch('https://overpass-api.de/api/interpreter', {
        method: 'POST',
        headers: { 'User-Agent': 'PowerBunk/1.0 (learning project)' },
        body: new URLSearchParams({ data: QUERY }),
        signal: AbortSignal.timeout(200000),
      });
      if (!res.ok) throw new Error(`Overpass returned ${res.status}`);
      const json = await res.json();
      return json.elements;
    } catch (e) {
      console.log(`Download attempt ${attempt} failed: ${e.message}`);
      if (attempt === 4) throw e;
      await sleep(15000 * attempt);
    }
  }
}

const rad = (d) => (d * Math.PI) / 180;
function distKm(a, b) {
  const dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 12742 * Math.asin(Math.sqrt(h));
}

const SOCKETS = {
  type2: 'Type 2',
  type2_combo: 'CCS (Type 2)',
  chademo: 'CHAdeMO',
  type1: 'Type 1',
  type1_combo: 'CCS (Type 1)',
  tesla_supercharger: 'Tesla',
};

function convert(e) {
  const t = e.tags || {};
  const lat = e.lat ?? (e.center && e.center.lat);
  const lng = e.lon ?? (e.center && e.center.lon);
  if (lat == null || lng == null) return { skip: 'noCoords' };
  if (t.bicycle === 'yes' && t.motorcar !== 'yes') return { skip: 'bicycle' };
  if (/cycle|bicycle|e-bike|ebike/i.test(t.name || '')) return { skip: 'bicycle' };

  const connectors = [];
  let ports = 0;
  const kw = [];
  for (const [k, v] of Object.entries(t)) {
    const m = k.match(/^socket:([a-z0-9_]+)(:output)?$/);
    if (!m) continue;
    if (m[2]) {
      const n = parseFloat(v);
      if (Number.isFinite(n)) kw.push(String(n));
    } else if (SOCKETS[m[1]]) {
      connectors.push(SOCKETS[m[1]]);
      const n = parseInt(v, 10);
      ports += Number.isFinite(n) ? n : 1;
    }
  }
  const out = parseFloat(t['charging_station:output']);
  if (Number.isFinite(out)) kw.push(String(out));
  const cap = parseInt(t.capacity, 10);

  return {
    row: {
      osm_id: `${e.type}/${e.id}`,
      name: (t.name || t.operator || t.brand || 'EV Charging Station').slice(0, 250),
      address: [t['addr:housename'], t['addr:street'], t['addr:city'], t['addr:postcode']]
        .filter(Boolean).join(', ').slice(0, 490),
      latitude: lat,
      longitude: lng,
      connector_types: connectors.length ? [...new Set(connectors)].join(', ') : 'Unknown',
      total_ports: ports || (Number.isFinite(cap) ? cap : 1),
      kwh_rating: kw.length ? [...new Set(kw)].join(', ').slice(0, 250) : null,
      operator: t.operator || t.brand || null,
    },
  };
}

async function main() {
  console.log('Downloading from OpenStreetMap (can take a minute)...');
  const elements = await fetchOsm();
  if (!Array.isArray(elements) || elements.length < 20) {
    throw new Error(`Only ${elements ? elements.length : 0} chargers came back. Refusing to continue.`);
  }
  fs.mkdirSync('data', { recursive: true });
  fs.writeFileSync('data/osm_tn.json', JSON.stringify(elements, null, 2));

  const [dbRows] = await db.query(
    'SELECT id, source, osm_id, latitude, longitude, is_active FROM stations'
  );
  const known = dbRows.map((r) => ({
    id: r.id,
    source: r.source,
    osm_id: r.osm_id,
    is_active: r.is_active,
    lat: Number(r.latitude),
    lng: Number(r.longitude),
  }));
  const byOsmId = new Map(known.filter((k) => k.osm_id).map((k) => [k.osm_id, k]));

  const counts = {
    fetched: elements.length, bicycle: 0, noCoords: 0,
    updated: 0, linked: 0, duplicate: 0, inserted: 0, reactivated: 0, deactivated: 0,
  };
  const toUpdate = [], toLink = [], toInsert = [];
  const seen = new Set();

  for (const e of elements) {
    const c = convert(e);
    if (c.skip) { counts[c.skip]++; continue; }
    const row = c.row;
    seen.add(row.osm_id);

    const existing = byOsmId.get(row.osm_id);
    if (existing) {
      if (!existing.is_active) counts.reactivated++;
      toUpdate.push({ id: existing.id, row });
      counts.updated++;
      continue;
    }

    const p = { lat: row.latitude, lng: row.longitude };
    let oldOsm = null, oldOsmD = Infinity, anyNear = false;
    for (const k of known) {
      const d = distKm(k, p);
      if (d >= DUP_KM) continue;
      anyNear = true;
      if (k.source === 'osm' && !k.osm_id && d < oldOsmD) { oldOsm = k; oldOsmD = d; }
    }

    if (oldOsm) {
      oldOsm.osm_id = row.osm_id; // claim it so it links only once
      byOsmId.set(row.osm_id, oldOsm);
      toLink.push({ id: oldOsm.id, row });
      counts.linked++;
    } else if (anyNear) {
      counts.duplicate++;
    } else {
      known.push({ id: null, source: 'osm', osm_id: row.osm_id, is_active: 1, lat: p.lat, lng: p.lng });
      toInsert.push(row);
      counts.inserted++;
    }
  }

  // OSM rows that were linked before but are gone from OSM now
  const linkedOsmRows = known.filter((k) => k.source === 'osm' && k.osm_id && k.id);
  const gone = linkedOsmRows.filter((k) => k.is_active && !seen.has(k.osm_id));
  let toDeactivate = gone;
  if (gone.length > Math.max(5, linkedOsmRows.length * 0.3)) {
    console.log(`WARNING: ${gone.length} chargers look removed. That is too many, so nothing will be deactivated.`);
    toDeactivate = [];
  }
  counts.deactivated = toDeactivate.length;

  console.log(counts);
  for (const r of toInsert.slice(0, 10)) {
    console.log('  NEW:', r.name.slice(0, 32).padEnd(32), '|', (r.operator || '-').slice(0, 18).padEnd(18),
      '|', r.connector_types, '|', r.latitude.toFixed(3), r.longitude.toFixed(3));
  }

  if (!APPLY) {
    console.log('\nDRY RUN: nothing was changed. Run with --apply to write these changes.');
    await db.end();
    return;
  }

  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();
    const upd = `UPDATE stations SET osm_id=?, name=?, address=?, latitude=?, longitude=?,
                   connector_types=?, total_ports=?, kwh_rating=?, operator=?,
                   last_seen_at=NOW(), is_active=1 WHERE id=?`;
    for (const { id, row: r } of [...toUpdate, ...toLink]) {
      await conn.query(upd, [r.osm_id, r.name, r.address, r.latitude, r.longitude,
        r.connector_types, r.total_ports, r.kwh_rating, r.operator, id]);
    }
    for (const r of toInsert) {
      await conn.query(
        `INSERT INTO stations (osm_id, name, address, latitude, longitude, connector_types,
                               total_ports, kwh_rating, operator, created_at, last_seen_at,
                               is_active, source)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW(), 1, 'osm')`,
        [r.osm_id, r.name, r.address, r.latitude, r.longitude, r.connector_types,
          r.total_ports, r.kwh_rating, r.operator]
      );
    }
    if (toDeactivate.length) {
      await conn.query('UPDATE stations SET is_active=0 WHERE id IN (?)', [toDeactivate.map((k) => k.id)]);
    }
    await conn.commit();
    console.log('\nDone. Changes saved.');
  } catch (e) {
    await conn.rollback();
    console.error('FAILED, nothing was saved:', e.message);
  } finally {
    conn.release();
    await db.end();
  }
}

main().catch(async (e) => { console.error('FAILED:', e.message); await db.end(); });
