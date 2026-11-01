# Powerbunk: Google Maps integration

What this adds
- Backend `/maps/*` endpoints (route, autocomplete, place, geocode, reverse). The Google key stays on the server, with rate limiting, short caching and an automatic OSM fallback for development.
- Flutter `PowerbunkMap` widget (Google Maps) behind a small abstraction, replacing flutter_map in the two screens that used it.
- Search and routes in the app now call your backend instead of public OSRM / Nominatim.
- The hardcoded `http://192.168.1.2:3000` is gone (use `--dart-define=BACKEND_URL=...`).
- Bug fixed on the way: the trip planner map started centred on Bengaluru; it now starts on Chennai.

## 1. Backend (ev-backend)
1. Copy into ev-backend: `services/`, `routes/maps.js`, `test/`, `server.js` (replaces yours), `.env.example`.
2. `npm install express-rate-limit`
3. In package.json "scripts" add:  "start": "node server.js",  "test": "node --test"
4. Add to your `.env` (never commit it):  GOOGLE_MAPS_API_KEY=<the team key>
5. `npm test` (7 tests should pass), then `npm run dev`.
6. Try it:
   curl "http://localhost:3000/maps/autocomplete?q=T%20Nag&scope=area"
   curl -X POST http://localhost:3000/maps/route -H "Content-Type: application/json" \
     -d '{"origin":{"lat":13.04,"lng":80.23},"destination":{"lat":13.05,"lng":80.28}}'
   The reply says "source":"google" (or "osrm" if the key is empty or rejected).

## 2. Flutter app (ev)
1. Commit your current work first so you can undo.
2. From the ev folder:  patch -p1 < <path>/flutter/patches/maps-integration.patch
   (or: git apply <path>/flutter/patches/maps-integration.patch)
3. flutter pub add google_maps_flutter
   flutter pub remove flutter_map
4. Add one line to android/local.properties (already git-ignored):  MAPS_API_KEY=<the team key>
5. Run on the phone with your Mac's IP (find it with: ipconfig getifaddr en0):
   flutter run -d e4cb4df2 --dart-define=BACKEND_URL=http://<mac-ip>:3000
   Phone and Mac must be on the same WiFi, and the backend must be running.

## 3. Test checklist
- [ ] Map tiles appear. If the map is grey: adb logcat | grep -i "authorization failure"
      (the Maps SDK prints the exact package name and SHA-1 it sent; that tells us what the key expects).
- [ ] Nearby screen: green pins load, tapping a pin selects the station, the locate button reloads.
- [ ] Trip planner: type "Pondicherry", pick a suggestion, a route line draws and the camera fits it.
- [ ] Trip planner: type "T Nagar" as start, pick it, route to "Marina Beach" works.
- [ ] Stop the backend: the app shows its normal error message instead of crashing.
- [ ] Empty GOOGLE_MAPS_API_KEY in .env: routes still work (source "osrm").

## Notes
- `zIndexInt` in the widget needs a recent google_maps_flutter (pub add fetches the latest).
- Autocomplete: scope=area restricts to Chennai and area/street types (home search); scope=trip biases to Chennai but allows other cities. Tunable in services/mapsService.js.
- Place Details requests only `location,formattedAddress` to stay in the cheaper billing tier. Check the real SKU in the Cloud billing report after a day of testing.
- Never commit the key. Before the Play Store release the key must be restricted (see the launch checklist).
- The OSM fallback is for development only. Public OSRM/Nominatim must not serve production traffic.
