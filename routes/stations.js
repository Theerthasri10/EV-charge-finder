const express = require('express');
const router = express.Router();
const db = require('../db');

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

module.exports = router;