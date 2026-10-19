#!/usr/bin/env python3
# coding: utf-8
"""Stage twelve date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka45-52-thunderbird47-50-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.haruka.45.2026-09-30': {'identity': ('haruka', '45', '1045M', '土曜・休日運休', '257091'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '17:00', '30'), ('新大阪', '006911', '17:27', '17:28', '3'), ('大阪', '007068', '17:32', '17:33', '21'), ('天王寺', '007439', '17:48', '17:50', '15'), ('和泉府中', '007871', '18:06', '18:07', None), ('日根野', '008072', '18:18', '18:18', None), ('関西空港', '007958', '18:26', None, None)]}, 'jr-west.haruka.46.2026-09-30': {'identity': ('haruka', '46', '1046M', '土曜・休日運休', '1151'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '18:16', None), ('天王寺', '007439', '18:48', '18:49', '18'), ('大阪', '007068', '19:01', '19:02', '24'), ('新大阪', '006911', '19:06', '19:07', '1'), ('高槻', '006432', '19:19', '19:20', None), ('京都', '006079', '19:34', None, '30')]}, 'jr-west.haruka.47.2026-09-30': {'identity': ('haruka', '47', '1047M', '土曜・休日運休', '1171'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '17:30', '30'), ('新大阪', '006911', '17:57', '17:58', '3'), ('大阪', '007068', '18:02', '18:03', '21'), ('天王寺', '007439', '18:18', '18:20', '15'), ('和泉府中', '007871', '18:37', '18:37', None), ('日根野', '008072', '18:46', '18:47', None), ('関西空港', '007958', '18:59', None, None)]}, 'jr-west.haruka.48.2026-09-30': {'identity': ('haruka', '48', '1048M', '土曜・休日運休', '257341'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '18:46', None), ('天王寺', '007439', '19:18', '19:19', '18'), ('大阪', '007068', '19:31', '19:32', '24'), ('新大阪', '006911', '19:36', '19:37', '1'), ('高槻', '006432', '19:49', '19:50', None), ('京都', '006079', '20:04', None, '30')]}, 'jr-west.haruka.49.2026-09-30': {'identity': ('haruka', '49', '1049M', '土曜・休日運休', '257111'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '18:00', '30'), ('新大阪', '006911', '18:27', '18:28', '3'), ('大阪', '007068', '18:32', '18:33', '21'), ('天王寺', '007439', '18:48', '18:50', '15'), ('和泉府中', '007871', '19:07', '19:07', None), ('日根野', '008072', '19:16', '19:17', None), ('関西空港', '007958', '19:25', None, None)]}, 'jr-west.haruka.50.2026-09-30': {'identity': ('haruka', '50', '1050M', '土曜・休日運休', '192721'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '19:16', None), ('天王寺', '007439', '19:48', '19:49', '18'), ('大阪', '007068', '20:01', '20:02', '24'), ('新大阪', '006911', '20:06', '20:07', '1'), ('高槻', '006432', '20:19', '20:19', None), ('京都', '006079', '20:32', '20:34', '0'), ('山科', '006043', '20:39', '20:39', None), ('大津', '006000', '20:43', '20:44', None), ('石山', '006098', '20:48', '20:48', None), ('南草津', '005991', '20:52', '20:53', None), ('草津', '005901', '20:56', '20:56', None), ('守山', '005831', '21:00', '21:01', None), ('野洲', '005772', '21:04', None, None)]}, 'jr-west.haruka.51.2026-09-30': {'identity': ('haruka', '51', '1051M', '土曜・休日運休', '129391'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '18:30', '30'), ('新大阪', '006911', '18:57', '18:58', '3'), ('大阪', '007068', '19:02', '19:03', '21'), ('天王寺', '007439', '19:18', '19:20', '15'), ('和泉府中', '007871', '19:37', '19:38', None), ('日根野', '008072', '19:47', '19:47', None), ('関西空港', '007958', '19:59', None, None)]}, 'jr-west.haruka.52.2026-09-30': {'identity': ('haruka', '52', '1052M', '土曜・休日運休', '257361'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '19:46', None), ('天王寺', '007439', '20:18', '20:19', '18'), ('大阪', '007068', '20:31', '20:32', '24'), ('新大阪', '006911', '20:36', '20:37', '1'), ('高槻', '006432', '20:49', '20:49', None), ('京都', '006079', '21:03', None, '30')]}, 'jr-west.thunderbird.47.2026-09-30': {'identity': ('thunderbird', '47', '4047M', '毎日運転', '257911'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '20:07', '11'), ('新大阪', '006911', '20:11', '20:12', '4'), ('京都', '006079', '20:36', '20:38', '0'), ('堅田', '005626', '20:52', '20:53', None), ('近江今津', '004835', '21:11', '21:11', None), ('敦賀', '010186', '21:33', None, '31')]}, 'jr-west.thunderbird.48.2026-09-30': {'identity': ('thunderbird', '48', '4048M', '毎日運転', '258251'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '21:08', '33'), ('京都', '006079', '22:02', '22:03', '7'), ('高槻', '006432', '22:16', '22:16', None), ('新大阪', '006911', '22:26', '22:27', '9'), ('大阪', '007068', '22:31', None, '3')]}, 'jr-west.thunderbird.49.2026-09-30': {'identity': ('thunderbird', '49', '4049M', '毎日運転', '257921'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('大阪', '007068', None, '20:54', '11'), ('新大阪', '006911', '20:57', '20:58', '4'), ('京都', '006079', '21:20', '21:21', '0'), ('堅田', '005626', '21:36', '21:37', None), ('敦賀', '010186', '22:16', None, '32')]}, 'jr-west.thunderbird.50.2026-09-30': {'identity': ('thunderbird', '50', '4050M', '毎日運転', '258261'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('敦賀', '010186', None, '22:05', '33'), ('京都', '006079', '22:59', '23:01', '7'), ('高槻', '006432', '23:14', '23:14', None), ('新大阪', '006911', '23:24', '23:25', '9'), ('大阪', '007068', '23:29', None, '4')]}}


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
        source_count=12,
        trip_count_error='Expected precisely twelve reviewed trips',
    )


if __name__ == "__main__":
    main()
