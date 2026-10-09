const express = require('express');
const router = express.Router();
const db = require('../db');

// The radius steps we try, smallest first
const RADIUS_STEPS_KM = [5, 10, 15, 20, 50, 100];
const MAX_RADIUS_KM = RADIUS_STEPS_KM[RADIUS_STEPS_KM.length - 1];

// MySQL formula: distance in km between the user (lat, lng) and a station
const DISTANCE_SQL = `
  6371 * ACOS(LEAST(1, GREATEST(-1,
    COS(RADIANS(?)) * COS(RADIANS(latitude)) *
    COS(RADIANS(longitude) - RADIANS(?)) +
    SIN(RADIANS(?)) * SIN(RADIANS(latitude))
  )))
`;

// GET /stations - returns all EV stations
router.get('/', async (req, res) => {
  try {
    const [rows] = await db.query('SELECT * FROM stations');
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to fetch stations' });
  }
});

// GET /stations/nearby?lat=13.08&lng=80.27
router.get('/nearby', async (req, res) => {
  const lat = parseFloat(req.query.lat);
  const lng = parseFloat(req.query.lng);

  // 1. Check the input
  if (Number.isNaN(lat) || Number.isNaN(lng) ||
      lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return res.status(400).json({ error: 'lat and lng are required and must be valid coordinates' });
  }

  try {
    // 2. All stations within 100 km, nearest first
    const [nearby] = await db.query(
      `SELECT *, ${DISTANCE_SQL} AS distance_km
       FROM stations
       WHERE latitude IS NOT NULL AND longitude IS NOT NULL
       HAVING distance_km <= ?
       ORDER BY distance_km ASC`,
      [lat, lng, lat, MAX_RADIUS_KM]
    );

    // 3. Found something within 100 km: pick the smallest radius step that fits
    if (nearby.length > 0) {
      const nearestKm = nearby[0].distance_km;
      const matchedRadius = RADIUS_STEPS_KM.find((r) => nearestKm <= r);
      const stations = nearby
        .filter((s) => s.distance_km <= matchedRadius)
        .map((s) => ({ ...s, distance_km: Number(s.distance_km.toFixed(2)) }));

      return res.json({
        matchedRadiusKm: matchedRadius,
        fallbackUsed: false,
        count: stations.length,
        stations,
      });
    }

    // 4. Nothing within 100 km: return the single nearest station anywhere
    const [nearest] = await db.query(
      `SELECT *, ${DISTANCE_SQL} AS distance_km
       FROM stations
       WHERE latitude IS NOT NULL AND longitude IS NOT NULL
       ORDER BY distance_km ASC
       LIMIT 1`,
      [lat, lng, lat]
    );

    const stations = nearest.map((s) => ({ ...s, distance_km: Number(s.distance_km.toFixed(2)) }));

    return res.json({
      matchedRadiusKm: null,
      fallbackUsed: true,
      count: stations.length,
      stations,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to fetch nearby stations' });
  }
});

module.exports = router;