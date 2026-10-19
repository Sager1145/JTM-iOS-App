#!/usr/bin/env python3
"""Stage two date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-thunderbird6-9-10-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {
    "jr-west.thunderbird.6.2026-09-30": {
        "identity": ("thunderbird", "6", "4006M", "毎日運転", "257981"),
        "equipment": ["女性専用席があります", "グリーン車指定席", "普通車全車指定席"],
        "calls": [
            ("敦賀", "010186", None, "08:07", "33"),
            ("京都", "006079", "09:02", "09:03", "7"),
            ("新大阪", "006911", "09:28", "09:29", "9"),
            ("大阪", "007068", "09:33", None, "3"),
        ],
    },
    "jr-west.thunderbird.9.2026-09-30": {
        "identity": ("thunderbird", "9", "4009M", "土曜・休日運休", "257701"),
        "equipment": ["女性専用席があります", "グリーン車指定席", "普通車全車指定席"],
        "calls": [
            ("大阪", "007068", None, "08:42", "11"),
            ("新大阪", "006911", "08:46", "08:47", "4"),
            ("京都", "006079", "09:09", "09:11", "0"),
            ("敦賀", "010186", "10:03", None, "31"),
        ],
    },
    "jr-west.thunderbird.10.2026-09-30": {
        "identity": ("thunderbird", "10", "4010M", "土曜・休日運休", "258001"),
        "equipment": ["女性専用席があります", "グリーン車指定席", "普通車全車指定席"],
        "calls": [
            ("敦賀", "010186", None, "09:07", "33"),
            ("京都", "006079", "10:06", "10:07", "7"),
            ("新大阪", "006911", "10:29", "10:29", "9"),
            ("大阪", "007068", "10:33", None, "3"),
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

def validate_sources(candidate, sources):
    if sources['jr-west-odekake-tsuruga-kosei-20260930']['url_or_locator'] != candidate['route_source_url']:
        raise ValueError('Tsuruga route source drift')

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
        source_count=4,
        trip_count_error='Expected precisely three reviewed trips',
        validate_sources=validate_sources,
    )


if __name__ == "__main__":
    main()
