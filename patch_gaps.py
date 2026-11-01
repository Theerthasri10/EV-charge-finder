#!/usr/bin/env python3
"""Adds the 'longest stretch without a charger' warning to /maps/trip.
Run from the ev-backend folder:  python3 patch_gaps.py
Safe to run twice."""
import sys
from pathlib import Path

GAP_CODE = r'''
// Total length of the route line in km
function routeLengthKm(line) {
  let total = 0;
  for (let i = 1; i < line.length; i++) total += haversineKm(line[i - 1], line[i]);
  return total;
}

// Stretches of road with no charger. `stations` must be sorted by along_route_km.
// Only gaps of minGapKm or more are reported, longest first.
function findGaps(stations, totalKm, minGapKm = 40) {
  const marks = [0, ...stations.map((s) => s.along_route_km), totalKm];
  const gaps = [];
  for (let i = 1; i < marks.length; i++) {
    const len = marks[i] - marks[i - 1];
    if (len >= minGapKm) {
      gaps.push({
        fromKm: Math.round(marks[i - 1] * 10) / 10,
        toKm: Math.round(marks[i] * 10) / 10,
        lengthKm: Math.round(len * 10) / 10,
      });
    }
  }
  gaps.sort((a, b) => b.lengthKm - a.lengthKm);
  return gaps;
}
'''


def patch(path, edits):
    p = Path(path)
    if not p.exists():
        sys.exit(f"STOP: {path} not found. Run this from the ev-backend folder.")
    s = p.read_text()
    for done, old, new in edits:
        if done in s:
            continue
        if s.count(old) != 1:
            sys.exit(f"STOP: could not find the expected text in {path}:\n  {old[:70]}")
        s = s.replace(old, new)
    p.write_text(s)
    print("patched", path)


patch("services/routeStations.js", [
    ("function findGaps", "module.exports = {", GAP_CODE + "\nmodule.exports = {"),
    ("routeLengthKm, findGaps", "module.exports = { decodePolyline, routeBox, stationsAlongRoute };",
     "module.exports = { decodePolyline, routeBox, stationsAlongRoute, routeLengthKm, findGaps };"),
])

patch("routes/maps.js", [
    ("routeLengthKm, findGaps",
     "const { decodePolyline, routeBox, stationsAlongRoute } = require('../services/routeStations');",
     "const { decodePolyline, routeBox, stationsAlongRoute, routeLengthKm, findGaps } = require('../services/routeStations');"),
    ("const gaps = findGaps",
     "  res.json({ ...route, radiusKm, stationCount: stations.length, stations });",
     "  const gaps = findGaps(stations, routeLengthKm(line));\n"
     "  res.json({\n"
     "    ...route,\n"
     "    radiusKm,\n"
     "    stationCount: stations.length,\n"
     "    stations,\n"
     "    gaps,\n"
     "    longestGapKm: gaps.length ? gaps[0].lengthKm : 0,\n"
     "  });"),
])
print("Done. Restart the backend (Ctrl+C, then npm run dev).")
