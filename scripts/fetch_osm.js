const fs = require('fs');

// Everything tagged as a charging station in Tamil Nadu and Puducherry
const query = `
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

async function main() {
  const res = await fetch('https://overpass-api.de/api/interpreter', {
    method: 'POST',
    headers: { 'User-Agent': 'PowerBunk/1.0 (learning project)' },
    body: new URLSearchParams({ data: query }),
  });
  if (!res.ok) throw new Error(`Overpass returned ${res.status}`);
  const json = await res.json();
  fs.writeFileSync('data/osm_tn.json', JSON.stringify(json.elements, null, 2));
  console.log(`Saved ${json.elements.length} chargers to data/osm_tn.json`);
}

main().catch((e) => console.error('FAILED:', e.message));
