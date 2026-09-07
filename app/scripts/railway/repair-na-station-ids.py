#!/usr/bin/env python3
"""Apply the reviewed station-identity catalog to an isolated NA app tree.

No routing, station positions, line order, colours or track geometry change.
Use --app-root for staging, then regenerate audits, display data and fixtures.
"""
import argparse
import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE / 'lib'))
from na_build_inputs import digest_file
from na_release import release_locks
from na_station_ids import apply_repairs


def write(path, value):
    temporary = path.with_name(path.name + f'.{os.getpid()}.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n')
    os.replace(temporary, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-root', type=Path, required=True)
    parser.add_argument('--catalog', type=Path, default=HERE / 'na-station-id-repairs.json')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    rail, data = args.app_root / 'public/rail', args.app_root / 'data'
    with release_locks([rail, data]):
        package_path, stations_path = rail / 'us-2025.json', data / 'stations-us.json'
        package = json.loads(package_path.read_text())
        stations = json.loads(stations_path.read_text())
        catalog = json.loads(args.catalog.read_text())
        package, stations, changes = apply_repairs(package, stations, catalog)
        if not changes:
            print('Already applied; no files changed')
            return
        spec = importlib.util.spec_from_file_location('na_station_repair_builder',
                    HERE / 'build-north-america-rail-package.py')
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        readings = json.loads((data / 'station-readings-us.json').read_text())
        fresh = builder.readings_for(stations['features'], 'us')
        for key in ('byCode', 'byName', 'stats'):
            readings[key] = fresh[key]
        inputs = [args.catalog.resolve(), Path(__file__).resolve(), HERE / 'lib/na_station_ids.py',
                  HERE / 'build-north-america-rail-package.py']
        previous_repair = package.get('stationIdentityRepair')
        package['stationIdentityRepair'] = {
            'generatedAt': dt.datetime.now(dt.timezone.utc).isoformat(),
            'inputPackageSha256': digest_file(package_path),
            'inputStationsSha256': digest_file(stations_path),
            'inputs': {str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p): digest_file(p)
                       for p in inputs},
            'changes': changes,
        }
        if previous_repair:
            package['stationIdentityRepair']['previousRepair'] = previous_repair
        package['generatedAt'] = package['stationIdentityRepair']['generatedAt']
        print(json.dumps({'groupsReviewed': len(catalog['repairs']),
                          'membershipsChanged': len(changes), 'dryRun': args.dry_run}))
        if not args.dry_run:
            write(package_path, package)
            write(stations_path, stations)
            write(data / 'station-readings-us.json', readings)
            report_path = rail / 'na-2025-build-report.json'
            if report_path.exists():
                report = json.loads(report_path.read_text())
                summary = report['regions']['us']
                summary['stationGroups'] = len({f['properties']['n02_group_code']
                                                for f in stations['features']})
                for key, path in [('package', package_path), ('stations', stations_path),
                                  ('readings', data / 'station-readings-us.json')]:
                    summary['bytes'][key] = path.stat().st_size
                report['stationIdentityRepair'] = package['stationIdentityRepair']
                write(report_path, report)


if __name__ == '__main__':
    main()
