#!/usr/bin/env python3
"""Apply the reviewed service-pattern catalog to an isolated NA app tree.

Raw GTFS/official-network inputs are not on this machine, so express-skip
truncations, dropped-station corrections and loop closures are applied
directly to the shipped package, its solver sections and its station
features. No routing or track geometry is re-derived; regenerate audits,
display data and fixtures after this runs.
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
from na_service_patterns import apply_repairs


def write(path, value):
    temporary = path.with_name(path.name + f'.{os.getpid()}.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n')
    os.replace(temporary, path)


def _applied_keys(package):
    """Ids (and, for legacy pre-id ledger entries, (lineId, op) pairs) of
    every repair already folded into `package`, walking `servicePatternRepair`
    and its `previousRepair` chain back to the original build."""
    ids, legacy_pairs = set(), set()
    node = package.get('servicePatternRepair')
    while node:
        for change in node.get('changes', []):
            change_id = change.get('id')
            if change_id:
                ids.add(change_id)
            else:
                legacy_pairs.add((change.get('lineId'), change.get('op')))
        node = node.get('previousRepair')
    return ids, legacy_pairs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-root', required=True, type=Path)
    parser.add_argument('--catalog', type=Path,
                        default=HERE / 'na-service-pattern-repairs.json')
    parser.add_argument('--region', choices=('us', 'ca'), default='us')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    region = args.region
    rail, data = args.app_root / 'public/rail', args.app_root / 'data'
    package_path = rail / f'{region}-2025.json'
    stations_path = data / f'stations-{region}.json'
    sections_path = data / f'rail-sections-{region}.json'
    readings_path = data / f'station-readings-{region}.json'

    with release_locks([rail, data]):
        package = json.loads(package_path.read_text())
        stations = json.loads(stations_path.read_text())
        sections = json.loads(sections_path.read_text())
        catalog = json.loads(args.catalog.read_text())

        region_repairs = [r for r in catalog.get('repairs', [])
                          if r.get('country', 'us') == region]
        applied_ids, legacy_pairs = _applied_keys(package)
        already_applied, to_apply = [], []
        for repair in region_repairs:
            if not repair.get('id'):
                raise ValueError(f"catalog entry missing 'id': {repair.get('lineId')}/"
                                  f"{repair.get('op')}")
            if (repair['id'] in applied_ids
                    or (repair['lineId'], repair['op']) in legacy_pairs):
                already_applied.append(repair['id'])
            else:
                to_apply.append(repair)

        if not to_apply:
            print(json.dumps({
                'repairs': 0, 'dryRun': args.dry_run, 'region': region,
                'alreadyApplied': already_applied, 'lines': [], 'removedStationFeatures': 0,
            }))
            return

        filtered_catalog = {**catalog, 'repairs': to_apply}
        summary = apply_repairs(package, stations, sections, filtered_catalog)
        new_package = summary['package']
        new_stations = summary['stations']
        new_sections = summary['sections']
        changes = summary['changes']

        print(json.dumps({
            'repairs': len(changes), 'dryRun': args.dry_run, 'region': region,
            'alreadyApplied': already_applied,
            'lines': sorted({c['lineId'] for c in changes}),
            'removedStationFeatures': summary['removedStationFeatures'],
        }))
        if args.dry_run:
            return

        spec = importlib.util.spec_from_file_location(
            'na_service_pattern_repair_builder', HERE / 'build-north-america-rail-package.py')
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        readings = json.loads(readings_path.read_text())
        fresh = builder.readings_for(new_stations['features'], region)
        for key in ('byCode', 'byName', 'stats'):
            readings[key] = fresh[key]

        catalog_hash = digest_file(args.catalog.resolve())
        generated_at = dt.datetime.now(dt.timezone.utc).isoformat()
        previous_repair = new_package.get('servicePatternRepair')
        new_package['servicePatternRepair'] = {
            'generatedAt': generated_at,
            'catalogSha256': catalog_hash,
            'inputPackageSha256': digest_file(package_path),
            'inputStationsSha256': digest_file(stations_path),
            'inputSectionsSha256': digest_file(sections_path),
            'changes': changes,
        }
        if previous_repair:
            new_package['servicePatternRepair']['previousRepair'] = previous_repair
        new_package['generatedAt'] = generated_at

        write(package_path, new_package)
        write(stations_path, new_stations)
        write(sections_path, new_sections)
        write(readings_path, readings)

        report_path = rail / 'na-2025-build-report.json'
        if report_path.exists():
            report = json.loads(report_path.read_text())
            summary_region = report.get('regions', {}).get(region)
            if summary_region is not None:
                for key, path in [('package', package_path), ('stations', stations_path),
                                  ('sections', sections_path), ('readings', readings_path)]:
                    summary_region.setdefault('bytes', {})[key] = path.stat().st_size
                if region == 'us':
                    report['servicePatternRepair'] = new_package['servicePatternRepair']
                write(report_path, report)


if __name__ == '__main__':
    main()
