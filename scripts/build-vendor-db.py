#!/usr/bin/env python3
"""Generate a deterministic offline IEEE prefix index. --check never writes."""
import argparse, hashlib, json, re
from pathlib import Path
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
result = {'version': 1, 'sourceDate': None, 'sources': {}}
for name, table, extra, minimum in [('oui', 'mal', 0, 10000), ('oui28', 'mam', 1, 1000), ('oui36', 'mas', 3, 1000)]:
    raw = (root / 'data/ieee' / (name + '.txt')).read_bytes()
    result['sources'][name] = {'sha256': hashlib.sha256(raw).hexdigest(), 'url': f'https://standards-oui.ieee.org/{"oui" if not extra else "oui28" if extra == 1 else "oui36"}/{name}.txt'}
    records, prefix = {}, None
    for line in raw.decode('utf-8').splitlines():
        match = re.match(r'^([0-9A-Fa-f]{2}-[0-9A-Fa-f]{2}-[0-9A-Fa-f]{2})\s+\(hex\)\s+(.+?)\s*$', line)
        if '(hex)' in line:
            prefix = match[1].replace('-', '').upper() if match else None
            if match and not extra: records[prefix] = match[2]
        if extra and prefix:
            match = re.match(r'^([0-9A-Fa-f]{6})-([0-9A-Fa-f]{6})\s+\(base 16\)\s+(.+?)\s*$', line)
            if match:
                lo, hi = match[1].upper(), match[2].upper()
                assert lo[:extra] == hi[:extra] and lo[extra:] == '0' * (6-extra) and hi[extra:] == 'F' * (6-extra), 'Unexpected IEEE assignment bounds'
                key = prefix + lo[:extra]
                assert key not in records or records[key] == match[3], 'Conflicting assignment'
                records[key] = match[3]
    assert len(records) >= minimum, f'{table}: incomplete or empty registry'
    result[table] = records
out = (json.dumps(result, sort_keys=True, ensure_ascii=False, separators=(',', ':')) + '\n').encode()
target = root / 'iPScanner/Resources/vendors.json'
if args.check:
    assert target.read_bytes() == out, 'Vendor database is stale; run scripts/build-vendor-db.py'
else: target.write_bytes(out)
print(f'Vendor index verified: {len(result["mal"])} MA-L, {len(result["mam"])} MA-M, {len(result["mas"])} MA-S; {len(out):,} bytes')
