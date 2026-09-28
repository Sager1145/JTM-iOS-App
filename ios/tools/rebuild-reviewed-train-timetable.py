#!/usr/bin/env python3
"""Rebuild checked-in reviewed facts and audits; does not crawl or infer facts."""
from pathlib import Path
import json
import subprocess
import sys

TOOLS=Path(__file__).resolve().parent
ROOT=TOOLS.parents[1]

# Root seeds own shared identities; later evidence refines their bounds.
NORMALIZERS=[
    'normalize-reviewed-timetable-seeds.py',
    'normalize-reviewed-central-2013-seeds.py',
    'normalize-reviewed-shiokaze-seeds.py',
    'normalize-reviewed-west-seeds.py',
    'normalize-reviewed-north-shikoku-seeds.py',
    'normalize-reviewed-historical-seeds.py',
    'normalize-reviewed-route-evidence.py',
]
STEPS=[
    'validate-train-timetable.py',
    'build-train-timetable-db.py',
    'verify-train-timetable-artifact.py',
    'audit-train-timetable-coverage.py',
    'build-train-service-patterns.py',
    'audit-train-timetable-routes.py',
    'audit-train-timetable-history-alignment.py',
    'audit-train-timetable-migration.py',
]

def refresh_service_evidence_bounds():
    # Reused identities (e.g. Kamui) can acquire dated evidence in another batch.
    # Expand bounds only from explicit add dates; do not infer intervening service.
    from train_timetable import DEFAULT_CANONICAL, load_dataset, load_manifest
    manifest=load_manifest(DEFAULT_CANONICAL)
    data,_=load_dataset(DEFAULT_CANONICAL,manifest)
    versions={r['timetable_version_id']:r for r in data['timetable_versions']}
    calendars={r['calendar_id']:r for r in data['calendars']}
    additions={}
    for row in data['calendar_exceptions']:
        if row['exception_type']=='add':
            additions.setdefault(row['calendar_id'],[]).append(row['service_date'])
    observed={}
    for trip in data['trips']:
        version=versions[trip['timetable_version_id']]
        calendar=calendars[trip['calendar_id']]
        for day in additions.get(trip['calendar_id'],[]):
            if (max(calendar['valid_from'],version['effective_from']) <= day
                    < min(calendar['valid_until'],version['effective_until'])
                    and day <= manifest['as_of_date']):
                observed.setdefault(trip['service_id'],[]).append(day)
    for path in sorted((DEFAULT_CANONICAL/'normalized').glob('services*.jsonl')):
        rows=[json.loads(line) for line in path.read_text().splitlines() if line]
        for row in rows:
            days=observed.get(row['service_id'])
            if days:
                row['first_verified_date']=min([min(days)]+[row['first_verified_date']] if row.get('first_verified_date') else [min(days)])
                row['last_verified_date']=max([max(days)]+[row['last_verified_date']] if row.get('last_verified_date') else [max(days)])
        path.write_text(''.join(json.dumps(row,ensure_ascii=False,sort_keys=True)+'\n' for row in rows))


def main():
    for name in NORMALIZERS:
        path=TOOLS/name
        # Some research batches supply only checked-in source/queue records.
        if path.exists():
            print(f'Reviewed input: {name}',flush=True)
            subprocess.run([sys.executable,str(path)],cwd=ROOT,check=True)
    refresh_service_evidence_bounds()
    for name in STEPS:
        print(f'Build/check: {name}',flush=True)
        subprocess.run([sys.executable,str(TOOLS/name)],cwd=ROOT,check=True)
    subprocess.run([sys.executable,str(TOOLS/'audit-train-timetable-migration.py'),'--check'],cwd=ROOT,check=True)

if __name__=='__main__':main()
