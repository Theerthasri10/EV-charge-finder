'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { createMapsService } = require('../services/mapsService');

function mockFetch(handlers) {
  const calls = [];
  const fn = async (url, opts = {}) => {
    calls.push({ url: String(url), opts });
    for (const [match, reply] of handlers) {
      if (String(url).includes(match)) {
        if (reply instanceof Error) throw reply;
        return { ok: reply.ok !== false, status: reply.status || 200, json: async () => reply.body };
      }
    }
    return { ok: false, status: 404, json: async () => ({}) };
  };
  fn.calls = calls;
  return fn;
}

const O = { lat: 13.04, lng: 80.23 };
const D = { lat: 13.05, lng: 80.28 };

test('route uses Google and caches the second identical call', async () => {
  const f = mockFetch([['routes.googleapis.com', { body: { routes: [{ distanceMeters: 6102, duration: '900s', polyline: { encodedPolyline: 'abc' } }] } }]]);
  const s = createMapsService({ fetchImpl: f, getKey: () => 'k' });
  const a = await s.route(O, D);
  assert.deepStrictEqual(a, { encodedPolyline: 'abc', distanceMeters: 6102, durationSeconds: 900, source: 'google' });
  await s.route(O, D);
  assert.strictEqual(f.calls.length, 1);
});

test('route falls back to OSRM when Google fails', async () => {
  const f = mockFetch([
    ['routes.googleapis.com', { ok: false, status: 403, body: {} }],
    ['router.project-osrm.org', { body: { code: 'Ok', routes: [{ geometry: 'xyz', distance: 5000.4, duration: 600.2 }] } }],
  ]);
  const r = await createMapsService({ fetchImpl: f, getKey: () => 'k' }).route(O, D);
  assert.strictEqual(r.source, 'osrm');
  assert.strictEqual(r.distanceMeters, 5000);
});

test('route works without a key and rejects bad coordinates', async () => {
  const f = mockFetch([['router.project-osrm.org', { body: { code: 'Ok', routes: [{ geometry: 'g', distance: 1, duration: 1 }] } }]]);
  const s = createMapsService({ fetchImpl: f, getKey: () => '' });
  assert.strictEqual((await s.route(O, D)).source, 'osrm');
  await assert.rejects(() => s.route({ lat: 999, lng: 0 }, D), (e) => e.status === 400);
});

test('autocomplete maps Google predictions, restricts area scope, biases trip scope', async () => {
  const f = mockFetch([['places:autocomplete', { body: { suggestions: [{ placePrediction: { placeId: 'ChIJ12345678', text: { text: 'T. Nagar, Chennai' }, structuredFormat: { mainText: { text: 'T. Nagar' }, secondaryText: { text: 'Chennai' } } } }] } }]]);
  const s = createMapsService({ fetchImpl: f, getKey: () => 'k' });
  const r = await s.autocomplete({ q: 'T Nag', session: 'abc', scope: 'area' });
  assert.strictEqual(r.suggestions[0].title, 'T. Nagar');
  const sent = JSON.parse(f.calls[0].opts.body);
  assert.ok(sent.locationRestriction && !sent.locationBias);
  assert.strictEqual(sent.sessionToken, 'abc');
  const t = await s.autocomplete({ q: 'Pondicherry', scope: 'trip' });
  assert.ok(JSON.parse(f.calls[1].opts.body).locationBias);
  assert.strictEqual(t.source, 'google');
});

test('autocomplete ignores short input and falls back to Nominatim without a key', async () => {
  const f = mockFetch([['nominatim', { body: [{ display_name: 'Adyar, Chennai, Tamil Nadu', lat: '13.0', lon: '80.25' }] }]]);
  const s = createMapsService({ fetchImpl: f, getKey: () => '' });
  assert.deepStrictEqual((await s.autocomplete({ q: 'ab' })).suggestions, []);
  const r = await s.autocomplete({ q: 'Adyar' });
  assert.strictEqual(r.source, 'osm');
  assert.strictEqual(r.suggestions[0].lat, 13.0);
});

test('place lookup validates the id and returns a location only', async () => {
  const f = mockFetch([['places.googleapis.com/v1/places/', { body: { location: { latitude: 13.04, longitude: 80.23 }, formattedAddress: 'T. Nagar' } }]]);
  const s = createMapsService({ fetchImpl: f, getKey: () => 'k' });
  await assert.rejects(() => s.placeLocation({ id: '../x' }), (e) => e.status === 400);
  assert.deepStrictEqual(await s.placeLocation({ id: 'ChIJcSPapVVmUjoR8Er', session: 's' }), { lat: 13.04, lng: 80.23, address: 'T. Nagar' });
  assert.strictEqual(f.calls[0].opts.headers['X-Goog-FieldMask'], 'location,formattedAddress');
});

test('errors never expose the API key', async () => {
  const f = mockFetch([['place', { ok: false, status: 500, body: {} }]]);
  const s = createMapsService({ fetchImpl: f, getKey: () => 'SECRETKEY123' });
  await assert.rejects(() => s.placeLocation({ id: 'ChIJcSPapVVmUjoR8Er' }), (e) => !String(e.message).includes('SECRETKEY123'));
});
