import csv, sys

def q(v):
    if v is None or v.strip() == '':
        return 'NULL'
    return "'" + v.replace('\\', '\\\\').replace("'", "''") + "'"

def n(v):
    return 'NULL' if v is None or v.strip() == '' else v.strip()

cols = ['id', 'ocm_id', 'google_place_id', 'name', 'address', 'latitude', 'longitude',
        'connector_types', 'total_ports', 'kwh_rating', 'operator', 'created_at', 'source']

print('DELETE FROM stations;')
count = 0
for r in csv.DictReader(open('data/stations_tn.csv', encoding='utf-8')):
    vals = [n(r['id']), n(r['ocm_id']), q(r['google_place_id']), q(r['name']), q(r['address']),
            n(r['latitude']), n(r['longitude']), q(r['connector_types']), n(r['total_ports']),
            q(r['kwh_rating']), q(r['operator']), q(r['created_at']), q(r['source'])]
    print(f"INSERT INTO stations ({', '.join(cols)}) VALUES ({', '.join(vals)});")
    count += 1
print(f'imported {count} rows', file=sys.stderr)
