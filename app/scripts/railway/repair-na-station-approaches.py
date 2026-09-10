#!/usr/bin/env python3
"""Apply reviewed station approaches after an NA build; no raw downloads needed.

Use --app-root for an isolated/staged tree. Regenerate display data, audits and
cross-platform fixtures afterwards. Unexpected source windows stop publication.
"""
import argparse
import json
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / 'lib'))
from na_release import release_locks
from na_station_approaches import apply_repairs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-root', required=True, type=Path)
    parser.add_argument('--catalog', type=Path,
                        default=HERE / 'na-station-approach-repairs.json')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    rail, data = args.app_root / 'public/rail', args.app_root / 'data'
    paths = [rail / 'us-2025.json', data / 'stations-us.json', data / 'rail-sections-us.json']
    with release_locks([rail, data]):
        values = [json.loads(p.read_text()) for p in paths]
        catalog = json.loads(args.catalog.read_text())
        package, stations, sections, changes = apply_repairs(*values, catalog)
        print(json.dumps({'repairs': len(changes), 'dryRun': args.dry_run,
                          'lines': sorted({c['lineId'] for c in changes})}))
        outputs = [package, stations, sections]
        if outputs == values or args.dry_run:
            return
        for path, value, previous in zip(paths, outputs, values):
            if value == previous:
                continue
            temporary = path.with_name(path.name + f'.{os.getpid()}.tmp')
            temporary.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n')
            os.replace(temporary, path)


if __name__ == '__main__':
    main()
