#!/usr/bin/env python3
"""Stage two date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka5-6-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {
    "jr-west.haruka.5.2026-09-30": {
        "identity": ("haruka", "5", "1005M", "土曜・休日運休", "271"),
        "equipment": ["グリーン車指定席", "普通車一部指定席"],
        "calls": [
            ("京都", "006079", None, "06:44", "30"),
            ("高槻", "006432", "07:00", "07:00", None),
            ("新大阪", "006911", "07:14", "07:15", "3"),
            ("大阪", "007068", "07:19", "07:20", "21"),
            ("天王寺", "007439", "07:35", "07:37", "15"),
            ("関西空港", "007958", "08:19", None, None),
        ],
    },
    "jr-west.haruka.6.2026-09-30": {
        "identity": ("haruka", "6", "1006M", "土曜・休日運休", "321"),
        "equipment": ["グリーン車指定席", "普通車一部指定席"],
        "calls": [
            ("関西空港", "007958", None, "07:56", None),
            ("日根野", "008072", "08:04", "08:05", None),
            ("和泉府中", "007871", "08:17", "08:18", None),
            ("天王寺", "007439", "08:40", "08:42", "18"),
            ("大阪", "007068", "09:00", "09:01", "24"),
            ("新大阪", "006911", "09:06", "09:08", "1"),
            ("京都", "006079", "09:34", None, "30"),
        ],
    },
}


def rows(pattern):
    return [json.loads(line) for path in BASE.glob(pattern)
            if SUFFIX not in str(path)
            for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write(path, records):
    emit_jsonl(path, records)


def equipment(item, tid, source_id):
    (formations, fact_rows) = ([], [])
    all_reserved = '普通車全車指定席' in item['printed_equipment']
    formations.append({
        'formation_id': f'{tid}.formation.{DAY}',
        'trip_id': tid,
        'service_date': DAY,
        'evidence_kind': 'planned',
        'all_reserved': all_reserved,
        'green_car_available': True,
        'source_id': source_id,
        'notes': 'Published seat categories only; actual car count, series and dispatch unverified.',
    })
    fact_rows.extend(({
        'entity_type': 'trip',
        'entity_id': tid,
        'field_name': f'formation.{field}',
        'source_id': source_id,
        'page_or_locator': '2026-09-30 車両設備情報',
        'confidence': 'high',
        'verification_status': 'verified',
    } for field in ('all_reserved', 'green_car_available')))
    return (formations[0], fact_rows)

def main():
    stage_odekake_expected_batch(
        base=BASE,
        root=ROOT,
        suffix=SUFFIX,
        day=DAY,
        until=UNTIL,
        expected=EXPECTED,
        load_manifest=timetable.load_manifest,
        rows=rows,
        write=write,
        equipment=equipment,
        source_count=2,
        trip_count_error='Expected precisely two reviewed trips',
    )


if __name__ == "__main__":
    main()
