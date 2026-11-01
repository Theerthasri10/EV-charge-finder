'use strict';
require('dotenv').config();
const fs = require('fs');
const db = require('../db');

const APPLY = process.argv.includes('--apply');
const DUP_KM = 0.1; // closer than 100 m to an existing station = duplicate

const rad = (d) => (d * Math.PI) / 180;
function distKm(a, b) {
  const dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 12742 * Math.asin(Math.sqrt(h));
}

// OSM socket tag -> the names your table already uses
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
  if (lat == null || lng == null) return { skip: 'no coordinates' };
  if (t.bicycle === 'yes' && t.motorcar !== 'yes') return { skip: 'bicycle only' };
  if (/cycle|bicycle|e-bike|ebike/i.test(t.name || '')) return { skip: 'bicycle only' };

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
      name: (t.name || t.operator || t.brand || 'EV Charging Station').slice(0, 250),
      address: [t['addr:housename'], t['addr:street'], t['addr:city'], t['addr:postcode']]
        .filter(Boolean).join(', ').slice(0, 490),
      latitude: lat,
      longitude: lng,
      connector_types: connectors.length ? [...new Set(connectors)].join(', ') : 'Unknown',
      total_ports: ports || (Number.isFinite(cap) ? cap : 1),
      kwh_rating: kw.length ? [...new Set(kw)].join(', ') : null,
      operator: t.operator || t.brand || null,
    },
  };
}

async function main() {
  const osm = JSON.parse(fs.readFileSync('data/osm_tn.json', 'utf8'));
  const [existing] = await db.query('SELECT latitude, longitude FROM stations');
  const known = existing.map((s) => ({ lat: Number(s.latitude), lng: Number(s.longitude) }));

  const counts = { total: osm.length, 'bicycle only': 0, 'no coordinates': 0, duplicate: 0 };
  const toAdd = [];
  for (const e of osm) {
    const c = convert(e);
    if (c.skip) { counts[c.skip]++; continue; }
    const p = { lat: c.row.latitude, lng: c.row.longitude };
    if (known.some((k) => distKm(k, p) < DUP_KM)) { counts.duplicate++; continue; }
    known.push(p); // also catches duplicates inside the OSM file itself
    toAdd.push(c.row);
  }

  console.log(counts, '| new:', toAdd.length);
  for (const r of toAdd.slice(0, 12)) {
    console.log(' ', r.name.slice(0, 32).padEnd(32), '|', (r.operator || '-').slice(0, 18).padEnd(18),
      '|', r.connector_types, '|', r.kwh_rating || '-', '|', r.latitude.toFixed(3), r.longitude.toFixed(3));
  }

  if (!APPLY) {
    console.log('\nDRY RUN: nothing was changed. Run with --apply to insert these.');
  } else {
    for (const r of toAdd) {
      await db.query(
        `INSERT INTO stations (name, address, latitude, longitude, connector_types, total_ports,
                               kwh_rating, operator, created_at, source)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW(), 'osm')`,
        [r.name, r.address, r.latitude, r.longitude, r.connector_types, r.total_ports, r.kwh_rating, r.operator]
      );
    }
    console.log(`\nInserted ${toAdd.length} stations.`);
  }
  await db.end();
}

main().catch(async (e) => { console.error('FAILED:', e.message); await db.end(); });
