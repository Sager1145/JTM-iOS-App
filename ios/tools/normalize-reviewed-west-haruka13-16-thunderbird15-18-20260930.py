#!/usr/bin/env python3
"""Stage eight date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka13-16-thunderbird15-18-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.haruka.13.2026-09-30': {'identity': ('haruka', '13', '1013M', '土曜・休日運休', '192701'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '08:45', '30'), ('新大阪', '006911', '09:13', '09:13', '3'), ('大阪', '007068', '09:18', '09:19', '21'), ('天王寺', '007439', '09:31', '09:32', '15'), ('関西空港', '007958', '10:05', None, None)]},
    'jr-west.haruka.14.2026-09-30': {'identity': ('haruka', '14', '1014M', '毎日運転', '257171'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '10:16', None), ('天王寺', '007439', '10:48', '10:50', '18'), ('大阪', '007068', '11:01', '11:02', '24'), ('新大阪', '006911', '11:06', '11:07', '1'), ('京都', '006079', '11:34', None, '30')]},
    'jr-west.haruka.15.2026-09-30': {'identity': ('haruka', '15', '1015M', '土曜・休日運休', '661'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '09:30', '30'), ('新大阪', '006911', '09:57', '09:58', '3'), ('大阪', '007068', '10:02', '10:03', '21'), ('天王寺', '007439', '10:15', '10:17', '15'), ('関西空港', '007958', '10:54', None, None)]},
    'jr-west.haruka.16.2026-09-30': {'identity': ('haruka', '16', '1016M', '毎日運転', '257181'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '10:44', None), ('天王寺', '007439', '11:18', '11:20', '18'), ('大阪', '007068', '11:31', '11:32', '24'), ('新大阪', '006911', '11:36', '11:37', '1'), ('京都', '006079', '12:04', None, '30')]},
    'jr-west.thunderbird.15.2026-09-30': {'identity': ('thunderbird', '15', '4015M', '毎日運転', '257751'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '10:09', '11'), ('新大阪', '006911', '10:12', '10:13', '4'), ('京都', '006079', '10:36', '10:37', '0'), ('敦賀', '010186', '11:30', None, '32')]},
    'jr-west.thunderbird.16.2026-09-30': {'identity': ('thunderbird', '16', '4016M', '毎日運転', '258051'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '10:44', '33'), ('京都', '006079', '11:39', '11:40', '7'), ('新大阪', '006911', '12:02', '12:02', '9'), ('大阪', '007068', '12:06', None, '3')]},
    'jr-west.thunderbird.17.2026-09-30': {'identity': ('thunderbird', '17', '4017M', '毎日運転', '257761'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '10:42', '11'), ('新大阪', '006911', '10:45', '10:46', '4'), ('京都', '006079', '11:09', '11:10', '0'), ('敦賀', '010186', '12:03', None, '31')]},
    'jr-west.thunderbird.18.2026-09-30': {'identity': ('thunderbird', '18', '4018M', '毎日運転', '258061'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '11:14', '33'), ('京都', '006079', '12:09', '12:10', '7'), ('新大阪', '006911', '12:32', '12:32', '9'), ('大阪', '007068', '12:36', None, '3')]}}



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
