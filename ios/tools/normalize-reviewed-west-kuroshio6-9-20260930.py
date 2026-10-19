#!/usr/bin/env python3
# coding: utf-8
"""Stage four date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio6-9-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.kuroshio.6.2026-09-30': {'identity': ('kuroshio', '6', '2056M', '土曜・休日運休', '144471'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('海南', '008442', None, '06:39', None), ('和歌山', '008365', '06:48', '06:50', '1'), ('和泉砂川', '008142', '07:04', '07:05', None), ('日根野', '008072', '07:10', '07:11', None), ('和泉府中', '007871', '07:20', '07:20', None), ('天王寺', '007439', '07:44', '07:45', '18'), ('大阪', '007068', '08:01', '08:03', '24'), ('新大阪', '006911', '08:07', None, '2')]}, 'jr-west.kuroshio.7.2026-09-30': {'identity': ('kuroshio', '7', '2057M', '土曜・休日運休', '126971'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '10:13', '2'), ('大阪', '007068', '10:17', '10:18', '21'), ('天王寺', '007439', '10:30', '10:32', '15'), ('日根野', '008072', '10:57', '10:57', None), ('和歌山', '008365', '11:15', '11:18', '4'), ('海南', '008442', '11:27', '11:27', None), ('箕島', '008481', '11:39', '11:39', None), ('藤並', '008517', '11:46', '11:46', None), ('湯浅', '008554', '11:49', '11:50', None), ('御坊', '008657', '12:03', '12:04', None), ('南部', '008845', '12:27', '12:27', None), ('紀伊田辺', '008867', '12:34', '12:35', None), ('白浜', '008915', '12:46', None, None)]}, 'jr-west.kuroshio.8.2026-09-30': {'identity': ('kuroshio', '8', '2058M', '土曜・休日運休', '126991'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('白浜', '008915', None, '06:39', None), ('紀伊田辺', '008867', '06:49', '06:51', None), ('南部', '008845', '06:57', '06:57', None), ('御坊', '008657', '07:21', '07:22', None), ('湯浅', '008554', '07:35', '07:35', None), ('藤並', '008517', '07:39', '07:39', None), ('箕島', '008481', '07:46', '07:46', None), ('海南', '008442', '07:58', '07:58', None), ('和歌山', '008365', '08:07', '08:09', '1'), ('和泉砂川', '008142', '08:24', '08:24', None), ('日根野', '008072', '08:29', '08:30', None), ('和泉府中', '007871', '08:39', '08:40', None), ('天王寺', '007439', '08:59', '09:01', '18'), ('大阪', '007068', '09:14', '09:15', '24'), ('新大阪', '006911', '09:19', None, '1')]}, 'jr-west.kuroshio.9.2026-09-30': {'identity': ('kuroshio', '9', '2059M', '毎日運転', '144331'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '11:13', '2'), ('大阪', '007068', '11:17', '11:18', '21'), ('天王寺', '007439', '11:30', '11:32', '15'), ('日根野', '008072', '11:57', '11:57', None), ('和歌山', '008365', '12:15', '12:18', '4'), ('海南', '008442', '12:27', '12:27', None), ('箕島', '008481', '12:39', '12:40', None), ('藤並', '008517', '12:46', '12:47', None), ('湯浅', '008554', '12:50', '12:50', None), ('御坊', '008657', '13:04', '13:04', None), ('南部', '008845', '13:27', '13:28', None), ('紀伊田辺', '008867', '13:35', '13:36', None), ('白浜', '008915', '13:47', None, None)]}}


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
    fact_rows.append({
        'entity_type': 'trip',
        'entity_id': tid,
        'field_name': 'formation.women_only_seat_available',
        'source_id': source_id,
        'page_or_locator': '2026-09-30 車両設備情報: 女性専用席があります',
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
