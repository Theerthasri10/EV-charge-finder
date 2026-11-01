'use strict';

// Google Maps proxy used by the Powerbunk backend.
// The API key never leaves the server. If the key is missing or Google fails,
// every method falls back to free OSM services (OSRM / Nominatim) so
// development is never blocked. The fallback is for development only: the
// public OSRM and Nominatim servers must not be used for production traffic.

const CHENNAI_BOX = {
  low: { latitude: 12.75, longitude: 79.95 },
  high: { latitude: 13.35, longitude: 80.35 },
};
const CHENNAI_CENTER = { latitude: 13.0827, longitude: 80.2707 };
const AREA_TYPES = ['sublocality', 'neighborhood', 'locality', 'route', 'street_address'];

const TTL = {
  route: 10 * 60 * 1000,
  autocomplete: 5 * 60 * 1000,
  place: 60 * 60 * 1000, // keep short: Google restricts long-term caching of place data
  geocode: 60 * 60 * 1000,
};
const MAX_CACHE = 500;

function httpError(status, code) {
  const e = new Error(code);
  e.status = status;
  return e;
}

function validPoint(p) {
  return (
    p &&
    typeof p.lat === 'number' &&
    typeof p.lng === 'number' &&
    Number.isFinite(p.lat) &&
    Number.isFinite(p.lng) &&
    Math.abs(p.lat) <= 90 &&
    Math.abs(p.lng) <= 180
  );
}

function createMapsService({
  fetchImpl = (...a) => fetch(...a),
  getKey = () => process.env.GOOGLE_MAPS_API_KEY,
  now = () => Date.now(),
  userAgent = process.env.NOMINATIM_UA || 'Powerbunk-dev/0.1',
} = {}) {
  const cache = new Map();

  function cacheGet(k) {
    const e = cache.get(k);
    if (!e) return undefined;
    if (e.exp < now()) {
      cache.delete(k);
      return undefined;
    }
    return e.v;
  }
  function cacheSet(k, v, ttl) {
    if (cache.size >= MAX_CACHE) cache.delete(cache.keys().next().value);
    cache.set(k, { v, exp: now() + ttl });
  }

  async function getJson(url, options = {}) {
    const res = await fetchImpl(url, { ...options, signal: AbortSignal.timeout(8000) });
    if (!res.ok) throw new Error(`upstream_${res.status}`); // never include the URL (it may hold the key)
    return res.json();
  }

  // ---------- Routes ----------
  async function route(origin, destination) {
    if (!validPoint(origin) || !validPoint(destination)) throw httpError(400, 'invalid_coordinates');
    const r4 = (n) => n.toFixed(4);
    const ck = `route:${r4(origin.lat)},${r4(origin.lng)}:${r4(destination.lat)},${r4(destination.lng)}`;
    const hit = cacheGet(ck);
    if (hit) return hit;

    let result = null;
    const key = getKey();
    if (key) {
      try {
        const data = await getJson('https://routes.googleapis.com/directions/v2:computeRoutes', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': key,
            'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
          },
          body: JSON.stringify({
            origin: { location: { latLng: { latitude: origin.lat, longitude: origin.lng } } },
            destination: { location: { latLng: { latitude: destination.lat, longitude: destination.lng } } },
            travelMode: 'DRIVE',
            routingPreference: 'TRAFFIC_UNAWARE', // cheaper tier; traffic-aware is billed higher
            polylineQuality: 'HIGH_QUALITY',
            polylineEncoding: 'ENCODED_POLYLINE',
          }),
        });
        const r = data.routes && data.routes[0];
        if (r && r.polyline && r.polyline.encodedPolyline) {
          result = {
            encodedPolyline: r.polyline.encodedPolyline,
            distanceMeters: r.distanceMeters,
            durationSeconds: parseInt(String(r.duration).replace('s', ''), 10),
            source: 'google',
          };
        }
      } catch (_) {
        /* fall through to OSRM */
      }
    }
    if (!result) {
      try {
        const url =
          `https://router.project-osrm.org/route/v1/driving/${origin.lng},${origin.lat};` +
          `${destination.lng},${destination.lat}?overview=full&geometries=polyline`;
        const data = await getJson(url);
        if (data.code === 'Ok' && data.routes && data.routes[0]) {
          const r = data.routes[0];
          result = {
            encodedPolyline: r.geometry,
            distanceMeters: Math.round(r.distance),
            durationSeconds: Math.round(r.duration),
            source: 'osrm',
          };
        }
      } catch (_) {
        /* handled below */
      }
    }
    if (!result) throw httpError(502, 'route_unavailable');
    cacheSet(ck, result, TTL.route);
    return result;
  }
  // ---------- Multi-stop route ----------
  // points: [{lat,lng}, ...]. First = start, last = destination, anything between = stops.
  async function routeMulti(points) {
    if (!Array.isArray(points) || points.length < 2 || points.length > 12) {
      throw httpError(400, 'need_2_to_12_points');
    }
    if (!points.every(validPoint)) throw httpError(400, 'invalid_coordinates');

    const r4 = (n) => n.toFixed(4);
    const ck = 'multi:' + points.map((p) => `${r4(p.lat)},${r4(p.lng)}`).join(';');
    const hit = cacheGet(ck);
    if (hit) return hit;

    const toWaypoint = (p) => ({ location: { latLng: { latitude: p.lat, longitude: p.lng } } });
    const secs = (d) => parseInt(String(d || '0').replace('s', ''), 10) || 0;

    let result = null;
    const key = getKey();
    if (key) {
      try {
        const data = await getJson('https://routes.googleapis.com/directions/v2:computeRoutes', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': key,
            'X-Goog-FieldMask':
              'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,' +
              'routes.legs.distanceMeters,routes.legs.duration,routes.legs.polyline.encodedPolyline',
          },
          body: JSON.stringify({
            origin: toWaypoint(points[0]),
            destination: toWaypoint(points[points.length - 1]),
            intermediates: points.slice(1, -1).map(toWaypoint),
            travelMode: 'DRIVE',
            routingPreference: 'TRAFFIC_UNAWARE',
            polylineQuality: 'HIGH_QUALITY',
            polylineEncoding: 'ENCODED_POLYLINE',
          }),
        });
        const r = data.routes && data.routes[0];
        if (r && r.polyline && r.legs && r.legs.length === points.length - 1) {
          result = {
            encodedPolyline: r.polyline.encodedPolyline,
            distanceMeters: r.distanceMeters,
            durationSeconds: secs(r.duration),
            legs: r.legs.map((l) => ({
              distanceMeters: l.distanceMeters,
              durationSeconds: secs(l.duration),
              encodedPolyline: (l.polyline && l.polyline.encodedPolyline) || null,
            })),
            source: 'google',
          };
        }
      } catch (_) {
        /* fall through to OSRM */
      }
    }
    if (!result) {
      try {
        const coords = points.map((p) => `${p.lng},${p.lat}`).join(';');
        const data = await getJson(
          `https://router.project-osrm.org/route/v1/driving/${coords}?overview=full&geometries=polyline`
        );
        const r = data.code === 'Ok' && data.routes && data.routes[0];
        if (r && r.legs && r.legs.length === points.length - 1) {
          result = {
            encodedPolyline: r.geometry,
            distanceMeters: Math.round(r.distance),
            durationSeconds: Math.round(r.duration),
            legs: r.legs.map((l) => ({
              distanceMeters: Math.round(l.distance),
              durationSeconds: Math.round(l.duration),
              encodedPolyline: null, // the free fallback has no per-leg line
            })),
            source: 'osrm',
          };
        }
      } catch (_) {
        /* handled below */
      }
    }
    if (!result) throw httpError(502, 'route_unavailable');
    cacheSet(ck, result, TTL.route);
    return result;
  }

  // ---------- Autocomplete ----------
  // scope 'area': restricted to the Chennai box, area/street results only (home search).
  // scope 'trip': any place, biased towards Chennai but not restricted (trips can leave the city).
  async function autocomplete({ q, session, scope = 'area' }) {
    const text = String(q || '').trim().slice(0, 100);
    if (text.length < 3) return { suggestions: [], source: 'none' };
    const ck = `ac:${scope}:${text.toLowerCase()}`;
    const hit = cacheGet(ck);
    if (hit) return hit;

    let out = null;
    const key = getKey();
    if (key) {
      try {
        const body = { input: text, includedRegionCodes: ['in'] };
        if (session) body.sessionToken = String(session).slice(0, 64);
        if (scope === 'area') {
          body.locationRestriction = { rectangle: CHENNAI_BOX };
          body.includedPrimaryTypes = AREA_TYPES;
        } else {
          body.locationBias = { circle: { center: CHENNAI_CENTER, radius: 50000 } };
        }
        const data = await getJson('https://places.googleapis.com/v1/places:autocomplete', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-Goog-Api-Key': key },
          body: JSON.stringify(body),
        });
        const suggestions = (data.suggestions || [])
          .filter((s) => s.placePrediction)
          .map((s) => {
            const p = s.placePrediction;
            const sf = p.structuredFormat || {};
            return {
              placeId: p.placeId,
              title: (sf.mainText && sf.mainText.text) || p.text.text,
              subtitle: (sf.secondaryText && sf.secondaryText.text) || '',
              description: p.text.text,
            };
          });
        out = { suggestions, source: 'google' };
      } catch (_) {
        /* fall through to Nominatim */
      }
    }
    if (!out) {
      try {
        let url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(text)}&format=json&limit=5&countrycodes=in`;
        if (scope === 'area') url += '&viewbox=79.95,13.35,80.35,12.75&bounded=1';
        const data = await getJson(url, { headers: { 'User-Agent': userAgent } });
        out = {
          suggestions: data.map((d) => ({
            placeId: null,
            title: String(d.display_name).split(',')[0],
            subtitle: String(d.display_name).split(',').slice(1, 3).join(',').trim(),
            description: d.display_name,
            lat: parseFloat(d.lat),
            lng: parseFloat(d.lon),
          })),
          source: 'osm',
        };
      } catch (_) {
        out = { suggestions: [], source: 'none' };
      }
    }
    cacheSet(ck, out, TTL.autocomplete);
    return out;
  }

  // ---------- Place details (location only, to stay in the cheapest field tier) ----------
  async function placeLocation({ id, session }) {
    if (!/^[A-Za-z0-9_-]{10,200}$/.test(String(id || ''))) throw httpError(400, 'invalid_place_id');
    const key = getKey();
    if (!key) throw httpError(503, 'places_unavailable');
    const ck = `place:${id}`;
    const hit = cacheGet(ck);
    if (hit) return hit;
    let url = `https://places.googleapis.com/v1/places/${encodeURIComponent(id)}`;
    if (session) url += `?sessionToken=${encodeURIComponent(String(session).slice(0, 64))}`;
    let data;
    try {
      data = await getJson(url, {
        headers: { 'X-Goog-Api-Key': key, 'X-Goog-FieldMask': 'location,formattedAddress' },
      });
    } catch (_) {
      throw httpError(502, 'place_lookup_failed');
    }
    if (!data.location) throw httpError(404, 'place_not_found');
    const out = { lat: data.location.latitude, lng: data.location.longitude, address: data.formattedAddress || '' };
    cacheSet(ck, out, TTL.place);
    return out;
  }

  // ---------- Geocoding ----------
  async function geocode(address) {
    const text = String(address || '').trim().slice(0, 200);
    if (text.length < 2) throw httpError(400, 'invalid_address');
    const ck = `geo:${text.toLowerCase()}`;
    const hit = cacheGet(ck);
    if (hit) return hit;
    let out = null;
    const key = getKey();
    if (key) {
      try {
        const data = await getJson(
          `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(text)}&components=country:IN&key=${encodeURIComponent(key)}`
        );
        if (data.status === 'OK' && data.results[0]) {
          const r = data.results[0];
          out = { lat: r.geometry.location.lat, lng: r.geometry.location.lng, address: r.formatted_address };
        }
      } catch (_) {
        /* fall through */
      }
    }
    if (!out) {
      try {
        const data = await getJson(
          `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(text)}&format=json&limit=1&countrycodes=in`,
          { headers: { 'User-Agent': userAgent } }
        );
        if (data[0]) out = { lat: parseFloat(data[0].lat), lng: parseFloat(data[0].lon), address: data[0].display_name };
      } catch (_) {
        /* handled below */
      }
    }
    if (!out) return null;
    cacheSet(ck, out, TTL.geocode);
    return out;
  }

  async function reverse(lat, lng) {
    if (!validPoint({ lat, lng })) throw httpError(400, 'invalid_coordinates');
    const ck = `rev:${lat.toFixed(4)},${lng.toFixed(4)}`;
    const hit = cacheGet(ck);
    if (hit) return hit;
    let out = null;
    const key = getKey();
    if (key) {
      try {
        const data = await getJson(
          `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${encodeURIComponent(key)}`
        );
        if (data.status === 'OK' && data.results[0]) out = { address: data.results[0].formatted_address };
      } catch (_) {
        /* fall through */
      }
    }
    if (!out) {
      try {
        const data = await getJson(
          `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json`,
          { headers: { 'User-Agent': userAgent } }
        );
        if (data.display_name) out = { address: data.display_name };
      } catch (_) {
        /* handled below */
      }
    }
    if (!out) return null;
    cacheSet(ck, out, TTL.geocode);
    return out;
  }

  return { route, routeMulti, autocomplete, placeLocation, geocode, reverse };
}

module.exports = { createMapsService };
