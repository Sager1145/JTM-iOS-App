#!/usr/bin/env python3
# coding: utf-8
"""Stage four date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio19-22-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.kuroshio.19.2026-09-30': {'identity': ('kuroshio', '19', '2069M', '毎日運転', '18841'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '16:13', '2'), ('大阪', '007068', '16:17', '16:18', '21'), ('天王寺', '007439', '16:31', '16:32', '15'), ('日根野', '008072', '16:57', '16:58', None), ('和泉砂川', '008142', '17:02', '17:03', None), ('和歌山', '008365', '17:18', '17:20', '4'), ('海南', '008442', '17:28', '17:29', None), ('箕島', '008481', '17:40', '17:41', None), ('藤並', '008517', '17:47', '17:47', None), ('湯浅', '008554', '17:51', '17:51', None), ('御坊', '008657', '18:04', '18:05', None), ('南部', '008845', '18:28', '18:28', None), ('紀伊田辺', '008867', '18:35', '18:36', None), ('白浜', '008915', '18:47', None, None)]}, 'jr-west.kuroshio.20.2026-09-30': {'identity': ('kuroshio', '20', '2070M', '毎日運転', '183811'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('白浜', '008915', None, '12:20', None), ('紀伊田辺', '008867', '12:30', '12:32', None), ('南部', '008845', '12:38', '12:38', None), ('御坊', '008657', '13:02', '13:03', None), ('湯浅', '008554', '13:16', '13:16', None), ('藤並', '008517', '13:20', '13:20', None), ('箕島', '008481', '13:27', '13:27', None), ('海南', '008442', '13:39', '13:39', None), ('和歌山', '008365', '13:48', '13:50', '1'), ('日根野', '008072', '14:08', '14:08', None), ('天王寺', '007439', '14:33', '14:35', '18'), ('大阪', '007068', '14:46', '14:47', '24'), ('新大阪', '006911', '14:51', None, '2')]}, 'jr-west.kuroshio.21.2026-09-30': {'identity': ('kuroshio', '21', '71M', '土曜・休日運休', '50631'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '17:13', '2'), ('大阪', '007068', '17:17', '17:18', '21'), ('天王寺', '007439', '17:33', '17:35', '15'), ('和泉府中', '007871', '17:52', '17:52', None), ('日根野', '008072', '18:02', '18:02', None), ('和泉砂川', '008142', '18:07', '18:07', None), ('和歌山', '008365', '18:22', '18:25', '4'), ('海南', '008442', '18:33', '18:34', None), ('箕島', '008481', '18:45', '18:46', None), ('藤並', '008517', '18:52', '18:53', None), ('湯浅', '008554', '18:56', '18:56', None), ('御坊', '008657', '19:10', '19:10', None), ('南部', '008845', '19:33', '19:33', None), ('紀伊田辺', '008867', '19:40', '19:42', None), ('白浜', '008915', '19:54', '19:56', None), ('周参見', '009191', '20:17', '20:17', None), ('串本', '009265', '20:50', '20:50', None), ('古座', '009224', '20:59', '20:59', None), ('太地', '009025', '21:16', '21:16', None), ('紀伊勝浦', '008974', '21:23', '21:23', None), ('新宮', '008874', '21:41', None, None)]}, 'jr-west.kuroshio.22.2026-09-30': {'identity': ('kuroshio', '22', '72M', '毎日運転', '183821'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新宮', '008874', None, '11:27', None), ('紀伊勝浦', '008974', '11:49', '11:49', None), ('太地', '009025', '11:56', '11:56', None), ('古座', '009224', '12:14', '12:14', None), ('串本', '009265', '12:22', '12:23', None), ('周参見', '009191', '12:58', '12:58', None), ('白浜', '008915', '13:19', '13:26', None), ('紀伊田辺', '008867', '13:36', '13:37', None), ('御坊', '008657', '14:06', '14:07', None), ('海南', '008442', '14:39', '14:39', None), ('和歌山', '008365', '14:48', '14:50', '1'), ('日根野', '008072', '15:08', '15:08', None), ('天王寺', '007439', '15:33', '15:35', '18'), ('大阪', '007068', '15:46', '15:47', '24'), ('新大阪', '006911', '15:51', None, '2')]}}


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
