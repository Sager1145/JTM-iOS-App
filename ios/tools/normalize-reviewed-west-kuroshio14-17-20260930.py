#!/usr/bin/env python3
# coding: utf-8
"""Stage three date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio14-17-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.kuroshio.14.2026-09-30': {'identity': ('kuroshio', '14', '2064M', '毎日運転', '144531'), 'equipment': ['オーシャンアロー車両で運転', '女性専用車両があります', 'グリーン車指定席（パノラマ型グリーン車）', '普通車全車指定席'], 'calls': [('白浜', '008915', None, '09:20', None), ('紀伊田辺', '008867', '09:30', '09:32', None), ('南部', '008845', '09:38', '09:38', None), ('御坊', '008657', '10:02', '10:03', None), ('湯浅', '008554', '10:16', '10:16', None), ('藤並', '008517', '10:20', '10:20', None), ('箕島', '008481', '10:27', '10:27', None), ('海南', '008442', '10:39', '10:39', None), ('和歌山', '008365', '10:48', '10:50', '1'), ('日根野', '008072', '11:08', '11:08', None), ('天王寺', '007439', '11:33', '11:35', '18'), ('大阪', '007068', '11:46', '11:47', '24'), ('新大阪', '006911', '11:51', None, '2')]}, 'jr-west.kuroshio.16.2026-09-30': {'identity': ('kuroshio', '16', '66M', '毎日運転', '144541'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新宮', '008874', None, '08:32', None), ('紀伊勝浦', '008974', '08:49', '08:49', None), ('太地', '009025', '08:56', '08:56', None), ('古座', '009224', '09:14', '09:14', None), ('串本', '009265', '09:22', '09:23', None), ('周参見', '009191', '09:54', '09:55', None), ('白浜', '008915', '10:19', '10:26', None), ('紀伊田辺', '008867', '10:36', '10:37', None), ('御坊', '008657', '11:06', '11:07', None), ('海南', '008442', '11:39', '11:39', None), ('和歌山', '008365', '11:48', '11:50', '1'), ('日根野', '008072', '12:08', '12:08', None), ('天王寺', '007439', '12:33', '12:35', '18'), ('大阪', '007068', '12:46', '12:47', '24'), ('新大阪', '006911', '12:51', None, '2')]}, 'jr-west.kuroshio.17.2026-09-30': {'identity': ('kuroshio', '17', '67M', '毎日運転', '86211'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '15:13', '2'), ('大阪', '007068', '15:17', '15:18', '21'), ('天王寺', '007439', '15:30', '15:32', '15'), ('日根野', '008072', '15:57', '15:57', None), ('和歌山', '008365', '16:15', '16:18', '4'), ('海南', '008442', '16:27', '16:27', None), ('御坊', '008657', '17:00', '17:00', None), ('紀伊田辺', '008867', '17:29', '17:31', None), ('白浜', '008915', '17:41', '17:43', None), ('周参見', '009191', '18:04', '18:04', None), ('串本', '009265', '18:37', '18:38', None), ('古座', '009224', '18:46', '18:46', None), ('太地', '009025', '19:03', '19:04', None), ('紀伊勝浦', '008974', '19:10', '19:11', None), ('新宮', '008874', '19:28', None, None)]}}


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
        source_count=3,
        trip_count_error='Expected precisely three reviewed trips',
    )


if __name__ == "__main__":
    main()
