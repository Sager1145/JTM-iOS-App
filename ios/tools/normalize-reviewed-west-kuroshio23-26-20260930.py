#!/usr/bin/env python3
# coding: utf-8
"""Stage four date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio23-26-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.kuroshio.23.2026-09-30': {'identity': ('kuroshio', '23', '2073M', '土曜・休日運休', '100371'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('京都', '006079', None, '17:47', '7'), ('新大阪', '006911', '18:12', '18:13', '2'), ('大阪', '007068', '18:17', '18:18', '21'), ('天王寺', '007439', '18:33', '18:35', '15'), ('和泉府中', '007871', '18:52', '18:52', None), ('日根野', '008072', '19:02', '19:03', None), ('和泉砂川', '008142', '19:08', '19:08', None), ('和歌山', '008365', '19:23', '19:26', '4'), ('海南', '008442', '19:35', '19:36', None), ('箕島', '008481', '19:47', '19:48', None), ('藤並', '008517', '19:54', '19:55', None), ('湯浅', '008554', '19:58', '19:59', None), ('御坊', '008657', '20:12', '20:13', None), ('南部', '008845', '20:36', '20:36', None), ('紀伊田辺', '008867', '20:43', '20:44', None), ('白浜', '008915', '20:55', None, None)]}, 'jr-west.kuroshio.24.2026-09-30': {'identity': ('kuroshio', '24', '2074M', '毎日運転', '183851'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('白浜', '008915', None, '14:20', None), ('紀伊田辺', '008867', '14:30', '14:32', None), ('南部', '008845', '14:38', '14:38', None), ('御坊', '008657', '15:02', '15:03', None), ('湯浅', '008554', '15:16', '15:16', None), ('藤並', '008517', '15:20', '15:20', None), ('箕島', '008481', '15:27', '15:27', None), ('海南', '008442', '15:39', '15:39', None), ('和歌山', '008365', '15:48', '15:50', '1'), ('日根野', '008072', '16:08', '16:08', None), ('天王寺', '007439', '16:33', '16:35', '18'), ('大阪', '007068', '16:46', '16:47', '24'), ('新大阪', '006911', '16:51', None, '2')]}, 'jr-west.kuroshio.25.2026-09-30': {'identity': ('kuroshio', '25', '2075M', '土曜・休日運休', '144361'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '18:43', '2'), ('大阪', '007068', '18:47', '18:48', '21'), ('天王寺', '007439', '19:03', '19:05', '15'), ('和泉府中', '007871', '19:22', '19:22', None), ('日根野', '008072', '19:31', '19:32', None), ('和泉砂川', '008142', '19:37', '19:38', None), ('和歌山', '008365', '19:53', None, '4')]}, 'jr-west.kuroshio.26.2026-09-30': {'identity': ('kuroshio', '26', '76M', '土曜・休日運休', '183831'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新宮', '008874', None, '13:29', None), ('紀伊勝浦', '008974', '13:45', '13:46', None), ('太地', '009025', '13:52', '13:53', None), ('古座', '009224', '14:11', '14:11', None), ('串本', '009265', '14:19', '14:20', None), ('周参見', '009191', '14:52', '14:53', None), ('白浜', '008915', '15:18', '15:26', None), ('紀伊田辺', '008867', '15:36', '15:37', None), ('御坊', '008657', '16:06', '16:07', None), ('海南', '008442', '16:39', '16:39', None), ('和歌山', '008365', '16:48', '16:50', '1'), ('日根野', '008072', '17:07', '17:08', None), ('天王寺', '007439', '17:33', '17:35', '18'), ('大阪', '007068', '17:46', '17:47', '24'), ('新大阪', '006911', '17:51', None, '2')]}}


def rows(pattern):
    return [json.loads(line) for path in BASE.glob(pattern)
            if SUFFIX not in str(path)
            for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write(path, records):
    emit_jsonl(path, records)


def equipment(item, tid, source_id):
    (formations, fact_rows) = ([], [])
    all_reserved = '普通車全車指定席' in item['printed_equipment']
    ocean_arrow = 'オーシャンアロー車両で運転' in item['printed_equipment']
    formations.append({
        'formation_id': f'{tid}.formation.{DAY}',
        'trip_id': tid,
        'service_date': DAY,
        'evidence_kind': 'planned',
        'all_reserved': all_reserved,
        'green_car_available': True,
        'source_id': source_id,
        **({'formation_label': 'オーシャンアロー車両'} if ocean_arrow else {}),
        'notes': 'Printed Ocean Arrow vehicle and panorama Green plan; actual dispatch, car count and capacity unverified.' if ocean_arrow else 'Printed seat categories only; actual vehicle, car count, capacity and dispatch unverified.',
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
    women_only_car = '女性専用車両があります' in item['printed_equipment']
    fact_rows.append({
        'entity_type': 'trip',
        'entity_id': tid,
        'field_name': 'formation.women_only_car_available' if women_only_car else 'formation.women_only_seat_available',
        'source_id': source_id,
        'page_or_locator': '2026-09-30 車両設備情報: 女性専用車両があります' if women_only_car else '2026-09-30 車両設備情報: 女性専用席があります',
        'confidence': 'high',
        'verification_status': 'verified',
    })
    if ocean_arrow:
        fact_rows.append({
            'entity_type': 'trip',
            'entity_id': tid,
            'field_name': 'formation.formation_label',
            'source_id': source_id,
            'page_or_locator': '2026-09-30 車両設備情報: オーシャンアロー車両で運転',
            'confidence': 'high',
            'verification_status': 'verified',
        })
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
