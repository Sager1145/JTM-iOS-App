#!/usr/bin/env python3
"""Retain row-specific evidence for reviewed, explicitly printed pass marks."""
import json
from pathlib import Path
from train_timetable import DEFAULT_CANONICAL, load_dataset, load_manifest


def main():
    base = DEFAULT_CANONICAL
    review = json.loads((base / 'sources/candidates/reviewed-pass-marks-20261003.json').read_text())
    data, _ = load_dataset(base, load_manifest(base))
    stops = {(r['trip_id'], r['stop_sequence']): r for r in data['stop_times']}
    facts = []
    for row in review['records']:
        if row['published_mark'] != 'レ':
            raise ValueError('Unreviewed pass symbol')
        stop = stops[(row['trip_id'], row['stop_sequence'])]
        if (stop['call_type'], stop['station_id'], stop['source_id']) != ('pass', row['station_id'], row['source_id']):
            raise ValueError('Reviewed pass mark no longer matches its source-pinned station row')
        facts.append(dict(entity_type='stop_time', entity_id=f"{row['trip_id']}:{row['stop_sequence']}",
                          field_name='call_type', source_id=row['source_id'], confidence='high',
                          verification_status='verified', page_or_locator=row['locator']))
    target = base / 'normalized/fact-sources-explicit-pass-marks.jsonl'
    target.write_text(''.join(json.dumps(r, ensure_ascii=False, sort_keys=True) + '\n' for r in facts))
    print(f'Retained {len(facts)} explicitly published pass marks')


if __name__ == '__main__':
    main()
