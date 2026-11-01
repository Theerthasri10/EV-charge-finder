'use strict';

const R = 6371;
const rad = (d) => (d * Math.PI) / 180;

// Google's encoded polyline (precision 5) -> [{lat,lng}, ...]
function decodePolyline(str) {
  const pts = [];
  let i = 0, lat = 0, lng = 0;
  while (i < str.length) {
    for (let axis = 0; axis < 2; axis++) {
      let shift = 0, result = 0, b;
      do {
        b = str.charCodeAt(i++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && i < str.length);
      const delta = result & 1 ? ~(result >> 1) : result >> 1;
      if (axis === 0) lat += delta; else lng += delta;
    }
    pts.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }
  return pts;
}

function haversineKm(a, b) {
  const dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

// Distance (km) from point p to segment a-b, plus t = where along the segment (0..1).
// Uses a flat local projection, accurate to well under 1% at these distances.
function segDist(p, a, b) {
  const kx = Math.cos(rad(p.lat)) * 111.32, ky = 111.2;
  const ax = (a.lng - p.lng) * kx, ay = (a.lat - p.lat) * ky;
  const bx = (b.lng - p.lng) * kx, by = (b.lat - p.lat) * ky;
  const dx = bx - ax, dy = by - ay;
  const len2 = dx * dx + dy * dy;
  const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, -(ax * dx + ay * dy) / len2));
  return { d: Math.hypot(ax + t * dx, ay + t * dy), t };
}

// Rectangle around the whole route, padded by the radius (for the SQL pre-filter)
function routeBox(line, radiusKm) {
  let minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
  for (const p of line) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lng < minLng) minLng = p.lng;
    if (p.lng > maxLng) maxLng = p.lng;
  }
  const dLat = radiusKm / 111;
  const dLng = radiusKm / (111.32 * Math.max(0.2, Math.cos(rad(Math.max(Math.abs(minLat), Math.abs(maxLat))))));
  return { minLat: minLat - dLat, maxLat: maxLat + dLat, minLng: minLng - dLng, maxLng: maxLng + dLng };
}

// Keep stations within radiusKm of the route line; order them along the trip.
function stationsAlongRoute(rows, line, radiusKm) {
  if (line.length < 2) return [];
  const cum = [0];
  for (let i = 1; i < line.length; i++) cum.push(cum[i - 1] + haversineKm(line[i - 1], line[i]));

  const out = [];
  for (const row of rows) {
    const p = { lat: Number(row.latitude), lng: Number(row.longitude) };
    if (!Number.isFinite(p.lat) || !Number.isFinite(p.lng)) continue;
    let best = Infinity, bestAlong = 0;
    for (let i = 0; i < line.length - 1; i++) {
      const { d, t } = segDist(p, line[i], line[i + 1]);
      if (d < best) {
        best = d;
        bestAlong = cum[i] + t * (cum[i + 1] - cum[i]);
      }
    }
    if (best <= radiusKm) {
      out.push({
        ...row,
        distance_from_route_km: Math.round(best * 100) / 100,
        along_route_km: Math.round(bestAlong * 10) / 10,
      });
    }
  }
  out.sort((a, b) => a.along_route_km - b.along_route_km);
  return out;
}


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

module.exports = { decodePolyline, routeBox, stationsAlongRoute, routeLengthKm, findGaps };
