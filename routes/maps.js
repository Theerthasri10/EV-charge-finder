'use strict';

const express = require('express');
const rateLimit = require('express-rate-limit');
const { createMapsService } = require('../services/mapsService');
const db = require('../db');
const { decodePolyline, routeBox, stationsAlongRoute, routeLengthKm, findGaps } = require('../services/routeStations');

const router = express.Router();
const maps = createMapsService();

// Each call can cost money upstream, so keep it tight per client.
router.use(
  rateLimit({
    windowMs: 60 * 1000,
    limit: 60,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'too_many_requests' },
  })
);

const num = (v) => (v === undefined ? NaN : Number(v));

function wrap(fn) {
  return async (req, res) => {
    try {
      await fn(req, res);
    } catch (err) {
      const status = err.status || 502;
      if (status >= 500) console.error('maps error:', err.message); // message never contains the API key
      res.status(status).json({ error: err.message || 'maps_error' });
    }
  };
}

// POST /maps/route  { origin:{lat,lng}, destination:{lat,lng} }
router.post('/route', wrap(async (req, res) => {
  const { origin, destination } = req.body || {};
  res.json(await maps.route(origin, destination));
}));

// POST /maps/route-multi  { points:[{lat,lng}, ...] }  start, stops..., destination
router.post('/route-multi', wrap(async (req, res) => {
  const { points } = req.body || {};
  res.json(await maps.routeMulti(points));
}));

// GET /maps/autocomplete?q=T%20Nag&session=<uuid>&scope=area|trip
router.get('/autocomplete', wrap(async (req, res) => {
  const scope = req.query.scope === 'trip' ? 'trip' : 'area';
  res.json(await maps.autocomplete({ q: req.query.q, session: req.query.session, scope }));
}));

// GET /maps/place?id=<placeId>&session=<uuid>
router.get('/place', wrap(async (req, res) => {
  res.json(await maps.placeLocation({ id: req.query.id, session: req.query.session }));
}));

// GET /maps/geocode?address=...
router.get('/geocode', wrap(async (req, res) => {
  const out = await maps.geocode(req.query.address);
  if (!out) return res.status(404).json({ error: 'not_found' });
  res.json(out);
}));

// GET /maps/reverse?lat=..&lng=..
router.get('/reverse', wrap(async (req, res) => {
  const out = await maps.reverse(num(req.query.lat), num(req.query.lng));
  if (!out) return res.status(404).json({ error: 'not_found' });
  res.json(out);
}));
// POST /maps/trip  { points:[{lat,lng}, ...], radiusKm: 3 }
// One call: the multi-stop route + every charger within radiusKm of the road.
router.post('/trip', wrap(async (req, res) => {
  const { points } = req.body || {};
  let radiusKm = Number(req.body && req.body.radiusKm);
  if (!Number.isFinite(radiusKm)) radiusKm = 3;
  radiusKm = Math.min(5, Math.max(1, radiusKm)); // clamp to 1-5 km

  const route = await maps.routeMulti(points);
  const line = decodePolyline(route.encodedPolyline);
  const box = routeBox(line, radiusKm);
  const [rows] = await db.query(
    'SELECT * FROM stations WHERE is_active = 1 AND latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?',
    [box.minLat, box.maxLat, box.minLng, box.maxLng]
  );
  const stations = stationsAlongRoute(rows, line, radiusKm);
  const gaps = findGaps(stations, routeLengthKm(line));
  res.json({
    ...route,
    radiusKm,
    stationCount: stations.length,
    stations,
    gaps,
    longestGapKm: gaps.length ? gaps[0].lengthKm : 0,
  });
}));
module.exports = router;
