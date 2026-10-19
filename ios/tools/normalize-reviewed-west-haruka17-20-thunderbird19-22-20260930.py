#!/usr/bin/env python3
"""Stage eight date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka17-20-thunderbird19-22-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.haruka.17.2026-09-30': {'identity': ('haruka', '17', '1017M', '土曜・休日運休', '256921'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '10:00', '30'), ('新大阪', '006911', '10:27', '10:28', '3'), ('大阪', '007068', '10:32', '10:33', '21'), ('天王寺', '007439', '10:45', '10:47', '15'), ('関西空港', '007958', '11:24', None, None)]},
    'jr-west.haruka.18.2026-09-30': {'identity': ('haruka', '18', '1018M', '毎日運転', '257191'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '11:14', None), ('天王寺', '007439', '11:48', '11:50', '18'), ('大阪', '007068', '12:01', '12:02', '24'), ('新大阪', '006911', '12:06', '12:07', '1'), ('京都', '006079', '12:34', None, '30')]},
    'jr-west.haruka.19.2026-09-30': {'identity': ('haruka', '19', '1019M', '毎日運転', '256941'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '10:30', '30'), ('新大阪', '006911', '10:57', '10:58', '3'), ('大阪', '007068', '11:02', '11:03', '21'), ('天王寺', '007439', '11:15', '11:17', '15'), ('関西空港', '007958', '11:50', None, None)]},
    'jr-west.haruka.20.2026-09-30': {'identity': ('haruka', '20', '1020M', '毎日運転', '257201'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '11:44', None), ('天王寺', '007439', '12:18', '12:20', '18'), ('大阪', '007068', '12:31', '12:32', '24'), ('新大阪', '006911', '12:36', '12:37', '1'), ('京都', '006079', '13:04', None, '30')]},
    'jr-west.thunderbird.19.2026-09-30': {'identity': ('thunderbird', '19', '4019M', '毎日運転', '257771'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '11:12', '11'), ('新大阪', '006911', '11:15', '11:16', '4'), ('京都', '006079', '11:39', '11:40', '0'), ('敦賀', '010186', '12:33', None, '32')]},
    'jr-west.thunderbird.20.2026-09-30': {'identity': ('thunderbird', '20', '4020M', '毎日運転', '258071'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '12:14', '33'), ('京都', '006079', '13:09', '13:10', '7'), ('新大阪', '006911', '13:32', '13:32', '9'), ('大阪', '007068', '13:36', None, '3')]},
    'jr-west.thunderbird.21.2026-09-30': {'identity': ('thunderbird', '21', '4021M', '毎日運転', '257781'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '12:12', '11'), ('新大阪', '006911', '12:15', '12:16', '4'), ('京都', '006079', '12:39', '12:40', '0'), ('敦賀', '010186', '13:33', None, '32')]},
    'jr-west.thunderbird.22.2026-09-30': {'identity': ('thunderbird', '22', '4022M', '毎日運転', '258081'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '13:14', '33'), ('京都', '006079', '14:09', '14:10', '7'), ('新大阪', '006911', '14:32', '14:32', '9'), ('大阪', '007068', '14:36', None, '3')]}}



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
        source_count=8,
        trip_count_error='Expected precisely eight reviewed trips',
    )


if __name__ == "__main__":
    main()
