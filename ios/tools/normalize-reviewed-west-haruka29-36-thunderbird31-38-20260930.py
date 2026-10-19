#!/usr/bin/env python3
"""Stage sixteen date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka29-36-thunderbird31-38-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.haruka.29.2026-09-30': {'identity': ('haruka', '29', '1029M', '毎日運転', '256991'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '13:00', '30'), ('新大阪', '006911', '13:27', '13:28', '3'), ('大阪', '007068', '13:32', '13:33', '21'), ('天王寺', '007439', '13:45', '13:47', '15'), ('関西空港', '007958', '14:20', None, None)]},
    'jr-west.haruka.30.2026-09-30': {'identity': ('haruka', '30', '1030M', '毎日運転', '257251'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '14:14', None), ('天王寺', '007439', '14:48', '14:50', '18'), ('大阪', '007068', '15:01', '15:02', '24'), ('新大阪', '006911', '15:06', '15:07', '1'), ('京都', '006079', '15:34', None, '30')]},
    'jr-west.haruka.31.2026-09-30': {'identity': ('haruka', '31', '1031M', '毎日運転', '257001'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '13:30', '30'), ('新大阪', '006911', '13:57', '13:58', '3'), ('大阪', '007068', '14:02', '14:03', '21'), ('天王寺', '007439', '14:15', '14:17', '15'), ('関西空港', '007958', '14:50', None, None)]},
    'jr-west.haruka.32.2026-09-30': {'identity': ('haruka', '32', '1032M', '毎日運転', '257261'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '14:44', None), ('天王寺', '007439', '15:18', '15:20', '18'), ('大阪', '007068', '15:31', '15:32', '24'), ('新大阪', '006911', '15:36', '15:37', '1'), ('京都', '006079', '16:04', None, '30')]},
    'jr-west.haruka.33.2026-09-30': {'identity': ('haruka', '33', '1033M', '毎日運転', '257011'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '14:00', '30'), ('新大阪', '006911', '14:27', '14:28', '3'), ('大阪', '007068', '14:32', '14:33', '21'), ('天王寺', '007439', '14:45', '14:47', '15'), ('関西空港', '007958', '15:20', None, None)]},
    'jr-west.haruka.34.2026-09-30': {'identity': ('haruka', '34', '1034M', '毎日運転', '257271'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '15:14', None), ('天王寺', '007439', '15:48', '15:50', '18'), ('大阪', '007068', '16:01', '16:02', '24'), ('新大阪', '006911', '16:06', '16:07', '1'), ('京都', '006079', '16:34', None, '30')]},
    'jr-west.haruka.35.2026-09-30': {'identity': ('haruka', '35', '1035M', '毎日運転', '257021'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '14:30', '30'), ('新大阪', '006911', '14:57', '14:58', '3'), ('大阪', '007068', '15:02', '15:03', '21'), ('天王寺', '007439', '15:15', '15:17', '15'), ('関西空港', '007958', '15:50', None, None)]},
    'jr-west.haruka.36.2026-09-30': {'identity': ('haruka', '36', '1036M', '毎日運転', '257281'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '15:44', None), ('天王寺', '007439', '16:18', '16:20', '18'), ('大阪', '007068', '16:31', '16:32', '24'), ('新大阪', '006911', '16:36', '16:37', '1'), ('京都', '006079', '17:04', None, '30')]},
    'jr-west.thunderbird.31.2026-09-30': {'identity': ('thunderbird', '31', '4031M', '毎日運転', '257831'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '15:40', '11'), ('新大阪', '006911', '15:43', '15:44', '4'), ('京都', '006079', '16:06', '16:08', '0'), ('敦賀', '010186', '17:00', None, '32')]},
    'jr-west.thunderbird.32.2026-09-30': {'identity': ('thunderbird', '32', '4032M', '土曜・休日運休', '258131'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '16:43', '33'), ('京都', '006079', '17:39', '17:40', '7'), ('新大阪', '006911', '18:03', '18:04', '9'), ('大阪', '007068', '18:09', None, '5')]},
    'jr-west.thunderbird.33.2026-09-30': {'identity': ('thunderbird', '33', '4033M', '毎日運転', '257841'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '16:09', '11'), ('新大阪', '006911', '16:12', '16:13', '4'), ('京都', '006079', '16:36', '16:37', '0'), ('敦賀', '010186', '17:30', None, '31')]},
    'jr-west.thunderbird.34.2026-09-30': {'identity': ('thunderbird', '34', '4034M', '土曜・休日運休', '258151'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '17:14', '33'), ('京都', '006079', '18:09', '18:10', '7'), ('新大阪', '006911', '18:33', '18:34', '9'), ('大阪', '007068', '18:39', None, '5')]},
    'jr-west.thunderbird.35.2026-09-30': {'identity': ('thunderbird', '35', '4035M', '毎日運転', '257851'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '16:40', '11'), ('新大阪', '006911', '16:43', '16:44', '4'), ('京都', '006079', '17:06', '17:08', '0'), ('敦賀', '010186', '18:00', None, '32')]},
    'jr-west.thunderbird.36.2026-09-30': {'identity': ('thunderbird', '36', '4036M', '土曜・休日運休', '258171'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '17:44', '33'), ('京都', '006079', '18:39', '18:40', '7'), ('新大阪', '006911', '19:02', '19:03', '9'), ('大阪', '007068', '19:07', None, '3')]},
    'jr-west.thunderbird.37.2026-09-30': {'identity': ('thunderbird', '37', '4037M', '毎日運転', '257861'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '17:09', '11'), ('新大阪', '006911', '17:13', '17:13', '4'), ('京都', '006079', '17:36', '17:37', '0'), ('敦賀', '010186', '18:30', None, '31')]},
    'jr-west.thunderbird.38.2026-09-30': {'identity': ('thunderbird', '38', '4038M', '毎日運転', '258191'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '18:12', '33'), ('近江今津', '004835', '18:35', '18:36', None), ('堅田', '005626', '18:54', '18:55', None), ('京都', '006079', '19:09', '19:11', '7'), ('新大阪', '006911', '19:32', '19:33', '9'), ('大阪', '007068', '19:37', None, '3')]}}



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
