#!/usr/bin/env python3
"""Stage four date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka11-12-thunderbird13-14-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.haruka.11.2026-09-30': {'identity': ('haruka', '11', '1011M', '土曜・休日運休', '192681'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('野洲', '005772', None, '07:51', None), ('守山', '005831', '07:54', '07:55', None), ('草津', '005901', '07:58', '07:59', None), ('南草津', '005991', '08:01', '08:02', None), ('石山', '006098', '08:06', '08:07', None), ('大津', '006000', '08:11', '08:11', None), ('山科', '006043', '08:15', '08:16', None), ('京都', '006079', '08:20', '08:22', '7'), ('新大阪', '006911', '08:46', '08:47', '3'), ('大阪', '007068', '08:51', '08:52', '21'), ('天王寺', '007439', '09:03', '09:04', '15'), ('関西空港', '007958', '09:36', None, None)]},
    'jr-west.haruka.12.2026-09-30': {'identity': ('haruka', '12', '1012M', '土曜・休日運休', '581'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '09:42', None), ('日根野', '008072', '09:50', '09:51', None), ('和泉府中', '007871', '10:01', '10:02', None), ('天王寺', '007439', '10:18', '10:20', '18'), ('大阪', '007068', '10:31', '10:32', '24'), ('新大阪', '006911', '10:36', '10:37', '1'), ('京都', '006079', '11:04', None, '30')]},
    'jr-west.thunderbird.13.2026-09-30': {'identity': ('thunderbird', '13', '4013M', '毎日運転', '257741'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '09:41', '11'), ('新大阪', '006911', '09:44', '09:45', '4'), ('京都', '006079', '10:07', '10:09', '0'), ('敦賀', '010186', '11:02', None, '31')]},
    'jr-west.thunderbird.14.2026-09-30': {'identity': ('thunderbird', '14', '4014M', '土曜・休日運休', '258031'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '10:14', '33'), ('京都', '006079', '11:09', '11:10', '7'), ('新大阪', '006911', '11:32', '11:32', '9'), ('大阪', '007068', '11:36', None, '3')]}}



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
        source_count=4,
        trip_count_error='Expected precisely four reviewed trips',
    )


if __name__ == "__main__":
    main()
