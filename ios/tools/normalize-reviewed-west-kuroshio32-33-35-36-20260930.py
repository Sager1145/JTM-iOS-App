#!/usr/bin/env python3
# coding: utf-8
"""Stage four date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio32-33-35-36-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.kuroshio.32.2026-09-30': {'identity': ('kuroshio', '32', '2082M', '毎日運転', '100421'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('白浜', '008915', None, '17:20', None), ('紀伊田辺', '008867', '17:30', '17:32', None), ('南部', '008845', '17:38', '17:38', None), ('御坊', '008657', '18:02', '18:03', None), ('湯浅', '008554', '18:16', '18:16', None), ('藤並', '008517', '18:20', '18:20', None), ('箕島', '008481', '18:27', '18:27', None), ('海南', '008442', '18:39', '18:39', None), ('和歌山', '008365', '18:48', '18:50', '1'), ('日根野', '008072', '19:08', '19:09', None), ('天王寺', '007439', '19:33', '19:35', '18'), ('大阪', '007068', '19:46', '19:47', '24'), ('新大阪', '006911', '19:51', None, '2')]}, 'jr-west.kuroshio.33.2026-09-30': {'identity': ('kuroshio', '33', '2083M', '土曜・休日運休', '144421'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '21:44', '2'), ('大阪', '007068', '21:49', '21:50', '21'), ('天王寺', '007439', '22:04', '22:06', '15'), ('和泉府中', '007871', '22:24', '22:24', None), ('日根野', '008072', '22:34', '22:35', None), ('和泉砂川', '008142', '22:39', '22:40', None), ('和歌山', '008365', '22:55', None, '5')]}, 'jr-west.kuroshio.35.2026-09-30': {'identity': ('kuroshio', '35', '2085M', '毎日運転', '144441'), 'equipment': ['オーシャンアロー車両で運転', '女性専用席があります', 'グリーン車指定席（パノラマ型グリーン車）', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '22:47', '2'), ('大阪', '007068', '22:51', '22:52', '21'), ('天王寺', '007439', '23:09', '23:10', '15'), ('和泉府中', '007871', '23:27', '23:27', None), ('日根野', '008072', '23:37', '23:38', None), ('和泉砂川', '008142', '23:42', '23:43', None), ('和歌山', '008365', '23:58', None, '1')]}, 'jr-west.kuroshio.36.2026-09-30': {'identity': ('kuroshio', '36', '86M', '土曜・休日運休', '144551'), 'equipment': ['オーシャンアロー車両で運転', '女性専用席があります', 'グリーン車指定席（パノラマ型グリーン車）', '普通車全車指定席'], 'calls': [('新宮', '008874', None, '17:46', None), ('紀伊勝浦', '008974', '18:03', '18:04', None), ('太地', '009025', '18:10', '18:11', None), ('古座', '009224', '18:28', '18:29', None), ('串本', '009265', '18:37', '18:38', None), ('周参見', '009191', '19:09', '19:10', None), ('白浜', '008915', '19:30', '19:37', None), ('紀伊田辺', '008867', '19:48', '19:50', None), ('御坊', '008657', '20:19', '20:19', None), ('海南', '008442', '20:51', '20:52', None), ('和歌山', '008365', '21:01', '21:02', '1'), ('日根野', '008072', '21:22', '21:23', None), ('天王寺', '007439', '21:47', '21:49', '18'), ('大阪', '007068', '22:02', '22:03', '24'), ('新大阪', '006911', '22:08', None, '2')]}}


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
