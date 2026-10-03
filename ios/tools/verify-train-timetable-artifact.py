#!/usr/bin/env python3
"""Check that timetable and historical map artifacts describe the same snapshot."""
import argparse
import json
from pathlib import Path
import re
import sqlite3

from train_timetable import (
    DEFAULT_CANONICAL, JP_PACKAGE, RAIL_HISTORY, ROOT, file_sha256,
    load_manifest, source_fingerprint,
)


def verify_artifact(canonical_dir=DEFAULT_CANONICAL, database=None, history=RAIL_HISTORY,
                    station_package=JP_PACKAGE, check_runtime=True):
    manifest = load_manifest(canonical_dir)
    database = database or canonical_dir / manifest['database_path']
    expected = {
        'rail_history_hash': file_sha256(history),
        'rail_history_revision': str(json.loads(history.read_text())['revision']),
        'station_package_hash': file_sha256(station_package),
        'timezone': manifest['timezone'],
        'service_day_time_semantics': manifest['service_day_time_semantics'],
        'first_scope_date': manifest['first_scope_date'],
        'as_of_date': manifest['as_of_date'],
        'solver_version': str(manifest['solver_version']),
        'source_hash': source_fingerprint(canonical_dir, manifest),
    }
    errors = []
    if canonical_dir.resolve() == DEFAULT_CANONICAL.resolve():
        for label, path, expression in (
            ('native_solver_version', ROOT / 'ios/RailKit/Sources/RailCore/RouteGraph.swift',
             r'routeSolverCacheVersion\s*=\s*"([^"]+)"'),
            ('web_solver_version', ROOT / 'app/public/app-config.js',
             r'ROUTE_SOLVER_CACHE_VERSION\s*=\s*["\x27]([^"\x27]+)["\x27]'),
        ):
            match = re.search(expression, path.read_text())
            actual_version = match.group(1) if match else None
            expected_version = (str(manifest['coordinate_solver_version'])
                                if label == 'web_solver_version' and 'coordinate_solver_version' in manifest
                                else expected['solver_version'])
            if actual_version != expected_version:
                errors.append({'field': label, 'expected': expected_version,
                               'actual': actual_version})
    with sqlite3.connect(database.resolve().as_uri() + '?mode=ro', uri=True) as connection:
        actual = dict(connection.execute('SELECT key, value FROM metadata'))
        for key, value in expected.items():
            if actual.get(key) != value:
                errors.append({'field': key, 'expected': value, 'actual': actual.get(key)})
        integrity = [r[0] for r in connection.execute('PRAGMA integrity_check')]
        if integrity != ['ok']:
            errors.append({'field': 'integrity', 'actual': integrity})
        foreign_keys = connection.execute('PRAGMA foreign_key_check').fetchall()
        if foreign_keys:
            errors.append({'field': 'foreign_keys', 'actual': foreign_keys})
    if check_runtime and manifest.get('runtime_database_path'):
        runtime = (canonical_dir / manifest['runtime_database_path']).resolve()
        if not runtime.exists() or file_sha256(runtime) != file_sha256(database):
            errors.append({'field': 'runtime_database', 'expected': file_sha256(database),
                           'actual': file_sha256(runtime) if runtime.exists() else None})
    return {'snapshotAligned': not errors, 'databaseHash': file_sha256(database),
            'railHistoryRevision': expected['rail_history_revision'],
            'railHistoryHash': expected['rail_history_hash'],
            'timezone': expected['timezone'], 'errors': errors,
            'note': 'Snapshot alignment does not certify route evidence or timetable coverage.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--canonical', type=Path, default=DEFAULT_CANONICAL)
    parser.add_argument('--database', type=Path)
    args = parser.parse_args()
    try:
        report = verify_artifact(args.canonical, args.database)
    except (OSError, sqlite3.Error, ValueError) as error:
        parser.exit(1, f'Timetable snapshot verification failed: {error}\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['snapshotAligned'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
