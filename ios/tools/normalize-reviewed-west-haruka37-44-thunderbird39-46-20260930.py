#!/usr/bin/env python3
# coding: utf-8
"""Stage sixteen date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka37-44-thunderbird39-46-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.haruka.37.2026-09-30': {'identity': ('haruka', '37', '1037M', '毎日運転', '257031'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '15:00', '30'), ('新大阪', '006911', '15:27', '15:28', '3'), ('大阪', '007068', '15:32', '15:33', '21'), ('天王寺', '007439', '15:45', '15:47', '15'), ('関西空港', '007958', '16:20', None, None)]}, 'jr-west.haruka.38.2026-09-30': {'identity': ('haruka', '38', '1038M', '毎日運転', '257291'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '16:14', None), ('天王寺', '007439', '16:48', '16:50', '18'), ('大阪', '007068', '17:01', '17:02', '24'), ('新大阪', '006911', '17:06', '17:07', '1'), ('高槻', '006432', '17:19', '17:20', None), ('京都', '006079', '17:34', None, '30')]}, 'jr-west.haruka.39.2026-09-30': {'identity': ('haruka', '39', '1039M', '毎日運転', '257041'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '15:30', '30'), ('新大阪', '006911', '15:57', '15:58', '3'), ('大阪', '007068', '16:02', '16:03', '21'), ('天王寺', '007439', '16:15', '16:17', '15'), ('関西空港', '007958', '16:50', None, None)]}, 'jr-west.haruka.40.2026-09-30': {'identity': ('haruka', '40', '1040M', '土曜・休日運休', '257301'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '16:43', None), ('天王寺', '007439', '17:17', '17:20', '18'), ('大阪', '007068', '17:31', '17:32', '24'), ('新大阪', '006911', '17:36', '17:37', '1'), ('高槻', '006432', '17:49', '17:50', None), ('京都', '006079', '18:04', None, '30')]}, 'jr-west.haruka.41.2026-09-30': {'identity': ('haruka', '41', '1041M', '土曜・休日運休', '257051'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '16:00', '30'), ('新大阪', '006911', '16:27', '16:28', '3'), ('大阪', '007068', '16:32', '16:33', '21'), ('天王寺', '007439', '16:46', '16:47', '15'), ('関西空港', '007958', '17:23', None, None)]}, 'jr-west.haruka.42.2026-09-30': {'identity': ('haruka', '42', '1042M', '土曜・休日運休', '129451'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '17:16', None), ('天王寺', '007439', '17:48', '17:50', '18'), ('大阪', '007068', '18:01', '18:02', '24'), ('新大阪', '006911', '18:06', '18:07', '1'), ('高槻', '006432', '18:19', '18:20', None), ('京都', '006079', '18:34', None, '30')]}, 'jr-west.haruka.43.2026-09-30': {'identity': ('haruka', '43', '1043M', '土曜・休日運休', '257071'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '16:30', '30'), ('新大阪', '006911', '16:57', '16:58', '3'), ('大阪', '007068', '17:02', '17:03', '21'), ('天王寺', '007439', '17:17', '17:20', '15'), ('和泉府中', '007871', '17:36', '17:37', None), ('日根野', '008072', '17:47', '17:48', None), ('関西空港', '007958', '17:56', None, None)]}, 'jr-west.haruka.44.2026-09-30': {'identity': ('haruka', '44', '1044M', '土曜・休日運休', '257321'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '17:46', None), ('天王寺', '007439', '18:18', '18:20', '18'), ('大阪', '007068', '18:31', '18:32', '24'), ('新大阪', '006911', '18:36', '18:37', '1'), ('高槻', '006432', '18:49', '18:50', None), ('京都', '006079', '19:04', None, '30')]}, 'jr-west.thunderbird.39.2026-09-30': {'identity': ('thunderbird', '39', '4039M', '毎日運転', '257871'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '17:40', '11'), ('新大阪', '006911', '17:43', '17:44', '4'), ('京都', '006079', '18:06', '18:07', '0'), ('敦賀', '010186', '19:00', None, '32')]}, 'jr-west.thunderbird.40.2026-09-30': {'identity': ('thunderbird', '40', '4040M', '土曜・休日運休', '258201'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '18:44', '33'), ('京都', '006079', '19:38', '19:40', '7'), ('新大阪', '006911', '20:03', '20:04', '9'), ('大阪', '007068', '20:09', None, '5')]}, 'jr-west.thunderbird.41.2026-09-30': {'identity': ('thunderbird', '41', '4041M', '毎日運転', '257881'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '18:10', '11'), ('新大阪', '006911', '18:13', '18:14', '4'), ('京都', '006079', '18:37', '18:38', '0'), ('敦賀', '010186', '19:31', None, '31')]}, 'jr-west.thunderbird.42.2026-09-30': {'identity': ('thunderbird', '42', '4042M', '毎日運転', '258221'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '19:14', '33'), ('京都', '006079', '20:09', '20:11', '7'), ('高槻', '006432', '20:23', '20:24', None), ('新大阪', '006911', '20:34', '20:34', '9'), ('大阪', '007068', '20:38', None, '3')]}, 'jr-west.thunderbird.43.2026-09-30': {'identity': ('thunderbird', '43', '4043M', '毎日運転', '257891'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '18:42', '11'), ('新大阪', '006911', '18:45', '18:46', '4'), ('京都', '006079', '19:09', '19:10', '0'), ('近江今津', '004835', '19:44', '19:45', None), ('敦賀', '010186', '20:07', None, '32')]}, 'jr-west.thunderbird.44.2026-09-30': {'identity': ('thunderbird', '44', '4044M', '毎日運転', '258231'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '19:44', '33'), ('京都', '006079', '20:38', '20:40', '7'), ('高槻', '006432', '20:52', '20:53', None), ('新大阪', '006911', '21:03', '21:04', '9'), ('大阪', '007068', '21:09', None, '3')]}, 'jr-west.thunderbird.45.2026-09-30': {'identity': ('thunderbird', '45', '4045M', '毎日運転', '257901'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '19:10', '11'), ('新大阪', '006911', '19:13', '19:14', '4'), ('京都', '006079', '19:36', '19:38', '0'), ('堅田', '005626', '19:52', '19:53', None), ('近江今津', '004835', '20:11', '20:11', None), ('敦賀', '010186', '20:33', None, '31')]}, 'jr-west.thunderbird.46.2026-09-30': {'identity': ('thunderbird', '46', '4046M', '毎日運転', '258241'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '20:11', '33'), ('京都', '006079', '21:05', '21:06', '7'), ('高槻', '006432', '21:19', '21:19', None), ('新大阪', '006911', '21:29', '21:30', '9'), ('大阪', '007068', '21:34', None, '3')]}}


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
