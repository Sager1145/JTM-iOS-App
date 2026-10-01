#!/usr/bin/env python3
"""Inventory legacy IDs without treating route summaries as timetable evidence."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LEGACY = ROOT / 'ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json'
HISTORY = ROOT / 'app/data/train-service-history'


def generate():
    patterns = json.loads(LEGACY.read_text())
    if len({p['patternId'] for p in patterns}) != len(patterns):
        raise ValueError('duplicate legacy pattern ID')
    derived_path = HISTORY / 'derived/train-service-patterns.json'
    derived = json.loads(derived_path.read_text()) if derived_path.exists() else []
    if isinstance(derived, dict):
        derived = derived.get('patterns', [])
    # Retained legacy rows are not independently derived evidence candidates.
    derived = [p for p in derived
               if p.get('_derivation', {}).get('status') != 'legacy_unverified_fallback']
    mapping, differences = [], []
    for old in patterns:
        candidates = [p for p in derived if p.get('serviceId') == old['serviceId']]
        # A matching stop signature alone cannot attest the full historical interval.
        exact = [p for p in candidates if p.get('stops') == old['stops']
                 and p.get('lines') == old['lines']
                 and p.get('origin') == old['origin']
                 and p.get('destination') == old['destination']]
        mapping.append(dict(legacyPatternId=old['patternId'], serviceId=old['serviceId'],
                            derivedPatternIds=sorted(p['patternId'] for p in exact),
                            migrationStatus='pending_evidence',
                            reason='Legacy record retained; exact trip/date/route coverage is not yet certified.'))
        differences.append(dict(legacyPatternId=old['patternId'],
                                classification='new DB missing evidence',
                                candidatePatternIds=sorted(p['patternId'] for p in candidates),
                                matchingSignatureIds=sorted(p['patternId'] for p in exact),
                                legacyOptionalStopCount=len(old.get('optionalStops', [])),
                                verificationStatus='unknown'))
    return {
        HISTORY / 'migration/legacy-pattern-map.json': mapping,
        HISTORY / 'audits/legacy-differential.json': dict(
            schemaVersion=1, legacyCatalogHash=hashlib.sha256(LEGACY.read_bytes()).hexdigest(),
            legacyPatternCount=len(patterns), complete=False,
            note='No legacy summary is promoted to a verified timetable trip. Candidate equality is not daily validity evidence.',
            differences=differences)
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    for path, value in generate().items():
        content = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + '\n'
        if args.check:
            if not path.exists() or path.read_text() != content:
                raise SystemExit(f'Stale migration artifact: {path}')
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    print('Legacy ID mapping and evidence differential verified' if args.check else 'Legacy ID mapping and evidence differential generated')


if __name__ == '__main__':
    main()
