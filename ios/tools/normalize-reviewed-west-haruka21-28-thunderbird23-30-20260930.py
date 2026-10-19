#!/usr/bin/env python3
"""Stage sixteen date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka21-28-thunderbird23-30-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.haruka.21.2026-09-30': {'identity': ('haruka', '21', '1021M', '毎日運転', '256951'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '11:00', '30'), ('新大阪', '006911', '11:27', '11:28', '3'), ('大阪', '007068', '11:32', '11:33', '21'), ('天王寺', '007439', '11:45', '11:47', '15'), ('関西空港', '007958', '12:20', None, None)]},
    'jr-west.haruka.22.2026-09-30': {'identity': ('haruka', '22', '1022M', '毎日運転', '257211'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '12:14', None), ('天王寺', '007439', '12:48', '12:50', '18'), ('大阪', '007068', '13:01', '13:02', '24'), ('新大阪', '006911', '13:06', '13:07', '1'), ('京都', '006079', '13:34', None, '30')]},
    'jr-west.haruka.23.2026-09-30': {'identity': ('haruka', '23', '1023M', '毎日運転', '256961'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '11:30', '30'), ('新大阪', '006911', '11:57', '11:58', '3'), ('大阪', '007068', '12:02', '12:03', '21'), ('天王寺', '007439', '12:15', '12:17', '15'), ('関西空港', '007958', '12:50', None, None)]},
    'jr-west.haruka.24.2026-09-30': {'identity': ('haruka', '24', '1024M', '毎日運転', '257221'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '12:44', None), ('天王寺', '007439', '13:18', '13:20', '18'), ('大阪', '007068', '13:31', '13:32', '24'), ('新大阪', '006911', '13:36', '13:37', '1'), ('京都', '006079', '14:04', None, '30')]},
    'jr-west.haruka.25.2026-09-30': {'identity': ('haruka', '25', '1025M', '毎日運転', '256971'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '12:00', '30'), ('新大阪', '006911', '12:27', '12:28', '3'), ('大阪', '007068', '12:32', '12:33', '21'), ('天王寺', '007439', '12:45', '12:47', '15'), ('関西空港', '007958', '13:20', None, None)]},
    'jr-west.haruka.26.2026-09-30': {'identity': ('haruka', '26', '1026M', '毎日運転', '257231'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '13:14', None), ('天王寺', '007439', '13:48', '13:50', '18'), ('大阪', '007068', '14:01', '14:02', '24'), ('新大阪', '006911', '14:06', '14:07', '1'), ('京都', '006079', '14:34', None, '30')]},
    'jr-west.haruka.27.2026-09-30': {'identity': ('haruka', '27', '1027M', '毎日運転', '256981'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '12:30', '30'), ('新大阪', '006911', '12:57', '12:58', '3'), ('大阪', '007068', '13:02', '13:03', '21'), ('天王寺', '007439', '13:15', '13:17', '15'), ('関西空港', '007958', '13:50', None, None)]},
    'jr-west.haruka.28.2026-09-30': {'identity': ('haruka', '28', '1028M', '毎日運転', '257241'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '13:44', None), ('天王寺', '007439', '14:18', '14:20', '18'), ('大阪', '007068', '14:31', '14:32', '24'), ('新大阪', '006911', '14:36', '14:37', '1'), ('京都', '006079', '15:04', None, '30')]},
    'jr-west.thunderbird.23.2026-09-30': {'identity': ('thunderbird', '23', '4023M', '毎日運転', '257791'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '12:42', '11'), ('新大阪', '006911', '12:45', '12:46', '4'), ('京都', '006079', '13:09', '13:10', '0'), ('敦賀', '010186', '14:03', None, '32')]},
    'jr-west.thunderbird.24.2026-09-30': {'identity': ('thunderbird', '24', '4024M', '毎日運転', '258091'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '14:14', '33'), ('京都', '006079', '15:09', '15:10', '7'), ('新大阪', '006911', '15:32', '15:32', '9'), ('大阪', '007068', '15:36', None, '3')]},
    'jr-west.thunderbird.25.2026-09-30': {'identity': ('thunderbird', '25', '4025M', '毎日運転', '257801'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '13:12', '11'), ('新大阪', '006911', '13:15', '13:16', '4'), ('京都', '006079', '13:39', '13:40', '0'), ('敦賀', '010186', '14:33', None, '31')]},
    'jr-west.thunderbird.26.2026-09-30': {'identity': ('thunderbird', '26', '4026M', '毎日運転', '258101'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '15:14', '33'), ('京都', '006079', '16:09', '16:10', '7'), ('新大阪', '006911', '16:32', '16:32', '9'), ('大阪', '007068', '16:36', None, '3')]},
    'jr-west.thunderbird.27.2026-09-30': {'identity': ('thunderbird', '27', '4027M', '毎日運転', '257811'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '14:12', '11'), ('新大阪', '006911', '14:15', '14:16', '4'), ('京都', '006079', '14:39', '14:40', '0'), ('敦賀', '010186', '15:33', None, '31')]},
    'jr-west.thunderbird.28.2026-09-30': {'identity': ('thunderbird', '28', '4028M', '毎日運転', '258111'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '15:44', '33'), ('京都', '006079', '16:39', '16:40', '7'), ('新大阪', '006911', '17:02', '17:02', '9'), ('大阪', '007068', '17:06', None, '3')]},
    'jr-west.thunderbird.29.2026-09-30': {'identity': ('thunderbird', '29', '4029M', '毎日運転', '257821'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '15:09', '11'), ('新大阪', '006911', '15:13', '15:13', '4'), ('京都', '006079', '15:36', '15:37', '0'), ('敦賀', '010186', '16:31', None, '31')]},
    'jr-west.thunderbird.30.2026-09-30': {'identity': ('thunderbird', '30', '4030M', '毎日運転', '258121'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '16:13', '33'), ('京都', '006079', '17:09', '17:10', '7'), ('新大阪', '006911', '17:32', '17:32', '9'), ('大阪', '007068', '17:36', None, '3')]}}



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
        source_count=16,
        trip_count_error='Expected precisely sixteen reviewed trips',
    )


if __name__ == "__main__":
    main()
