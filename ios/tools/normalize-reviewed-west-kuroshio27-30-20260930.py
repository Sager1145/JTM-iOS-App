#!/usr/bin/env python3
# coding: utf-8
"""Stage four date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio27-30-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.kuroshio.27.2026-09-30': {'identity': ('kuroshio', '27', '77M', '土曜・休日運休', '144381'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '19:13', '2'), ('大阪', '007068', '19:17', '19:18', '21'), ('天王寺', '007439', '19:33', '19:35', '15'), ('和泉府中', '007871', '19:52', '19:52', None), ('日根野', '008072', '20:01', '20:02', None), ('和泉砂川', '008142', '20:07', '20:07', None), ('和歌山', '008365', '20:23', '20:26', '4'), ('海南', '008442', '20:34', '20:35', None), ('箕島', '008481', '20:46', '20:47', None), ('藤並', '008517', '20:53', '20:54', None), ('湯浅', '008554', '20:57', '20:57', None), ('御坊', '008657', '21:11', '21:11', None), ('南部', '008845', '21:34', '21:35', None), ('紀伊田辺', '008867', '21:42', '21:43', None), ('白浜', '008915', '21:54', '21:56', None), ('周参見', '009191', '22:17', '22:17', None), ('串本', '009265', '22:54', '22:55', None), ('古座', '009224', '23:03', '23:04', None), ('太地', '009025', '23:22', '23:23', None), ('紀伊勝浦', '008974', '23:29', '23:30', None), ('新宮', '008874', '23:49', None, None)]}, 'jr-west.kuroshio.28.2026-09-30': {'identity': ('kuroshio', '28', '2078M', '土曜・休日運休', '127011'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('白浜', '008915', None, '16:20', None), ('紀伊田辺', '008867', '16:30', '16:32', None), ('南部', '008845', '16:38', '16:38', None), ('御坊', '008657', '17:02', '17:03', None), ('湯浅', '008554', '17:16', '17:16', None), ('藤並', '008517', '17:20', '17:20', None), ('箕島', '008481', '17:27', '17:27', None), ('海南', '008442', '17:39', '17:39', None), ('和歌山', '008365', '17:48', '17:50', '1'), ('日根野', '008072', '18:08', '18:08', None), ('天王寺', '007439', '18:32', '18:34', '18'), ('大阪', '007068', '18:46', '18:47', '24'), ('新大阪', '006911', '18:51', None, '2')]}, 'jr-west.kuroshio.29.2026-09-30': {'identity': ('kuroshio', '29', '2079M', '土曜・休日運休', '144401'), 'equipment': ['オーシャンアロー車両で運転', '女性専用席があります', 'グリーン車指定席（パノラマ型グリーン車）', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '20:13', '2'), ('大阪', '007068', '20:17', '20:18', '21'), ('天王寺', '007439', '20:33', '20:35', '15'), ('和泉府中', '007871', '20:52', '20:52', None), ('日根野', '008072', '21:01', '21:02', None), ('和泉砂川', '008142', '21:07', '21:07', None), ('和歌山', '008365', '21:22', '21:26', '4'), ('海南', '008442', '21:34', '21:35', None), ('箕島', '008481', '21:46', '21:47', None), ('藤並', '008517', '21:53', '21:54', None), ('湯浅', '008554', '21:57', '21:57', None), ('御坊', '008657', '22:11', '22:11', None), ('南部', '008845', '22:34', '22:35', None), ('紀伊田辺', '008867', '22:41', '22:43', None), ('白浜', '008915', '22:54', None, None)]}, 'jr-west.kuroshio.30.2026-09-30': {'identity': ('kuroshio', '30', '6080M', '９月１８・２４・２５・２８～３０日・１０月１・２・５～９・１３～１６・１９～２３・２６～３０日・１１月２・４～６・９～１３・１６～２０・２４～２７・３０日運転', '198532'), 'equipment': ['オーシャンアロー車両で運転', '女性専用席があります', 'グリーン車指定席（パノラマ型グリーン車）', '普通車全車指定席'], 'calls': [('新宮', '008874', None, '15:04', None), ('紀伊勝浦', '008974', '15:21', '15:21', None), ('太地', '009025', '15:28', '15:28', None), ('古座', '009224', '15:47', '15:49', None), ('串本', '009265', '15:57', '15:57', None), ('周参見', '009191', '16:29', '16:29', None), ('白浜', '008915', '16:50', '16:56', None), ('紀伊田辺', '008867', '17:06', '17:08', None), ('御坊', '008657', '17:37', '17:37', None), ('海南', '008442', '18:09', '18:09', None), ('和歌山', '008365', '18:18', '18:20', '1'), ('日根野', '008072', '18:37', '18:38', None), ('天王寺', '007439', '19:02', '19:04', '18'), ('大阪', '007068', '19:16', '19:17', '24'), ('新大阪', '006911', '19:21', None, '2')]}}


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
