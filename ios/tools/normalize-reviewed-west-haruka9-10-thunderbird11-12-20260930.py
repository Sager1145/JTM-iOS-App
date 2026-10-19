#!/usr/bin/env python3
"""Stage four date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka9-10-thunderbird11-12-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.haruka.9.2026-09-30': {'identity': ('haruka', '9', '1009M', '土曜・休日運休', '192661'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('野洲', '005772', None, '07:15', None), ('守山', '005831', '07:18', '07:19', None), ('草津', '005901', '07:23', '07:25', None), ('南草津', '005991', '07:27', '07:28', None), ('石山', '006098', '07:32', '07:32', None), ('大津', '006000', '07:36', '07:37', None), ('山科', '006043', '07:41', '07:42', None), ('京都', '006079', '07:46', '07:48', '7'), ('新大阪', '006911', '08:15', '08:16', '3'), ('大阪', '007068', '08:20', '08:25', '21'), ('天王寺', '007439', '08:39', '08:40', '15'), ('関西空港', '007958', '09:13', None, None)]},
    'jr-west.haruka.10.2026-09-30': {'identity': ('haruka', '10', '1010M', '土曜・休日運休', '203241'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '09:12', None), ('日根野', '008072', '09:20', '09:20', None), ('和泉府中', '007871', '09:30', '09:31', None), ('天王寺', '007439', '09:48', '09:50', '18'), ('大阪', '007068', '10:01', '10:02', '24'), ('新大阪', '006911', '10:07', '10:08', '1'), ('京都', '006079', '10:34', None, '30')]},
    'jr-west.thunderbird.11.2026-09-30': {'identity': ('thunderbird', '11', '4011M', '土曜・休日運休', '257721'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '09:12', '11'), ('新大阪', '006911', '09:17', '09:17', '4'), ('京都', '006079', '09:41', '09:42', '0'), ('敦賀', '010186', '10:35', None, '31')]},
    'jr-west.thunderbird.12.2026-09-30': {'identity': ('thunderbird', '12', '4012M', '毎日運転', '258021'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '09:39', '33'), ('京都', '006079', '10:35', '10:36', '7'), ('新大阪', '006911', '10:58', '10:58', '9'), ('大阪', '007068', '11:02', None, '3')]}}



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
