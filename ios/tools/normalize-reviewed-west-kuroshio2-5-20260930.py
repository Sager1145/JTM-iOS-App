#!/usr/bin/env python3
# coding: utf-8
"""Stage four date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio2-5-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.kuroshio.2.2026-09-30': {'identity': ('kuroshio', '2', '2052M', '毎日運転', '100391'), 'equipment': ['オーシャンアロー車両で運転', '女性専用席があります', 'グリーン車指定席（パノラマ型グリーン車）', '普通車全車指定席'], 'calls': [('和歌山', '008365', None, '05:14', '1'), ('和泉砂川', '008142', '05:28', '05:29', None), ('日根野', '008072', '05:33', '05:34', None), ('和泉府中', '007871', '05:43', '05:44', None), ('天王寺', '007439', '06:00', '06:02', '18'), ('大阪', '007068', '06:15', '06:16', '24'), ('新大阪', '006911', '06:21', None, '3')]}, 'jr-west.kuroshio.3.2026-09-30': {'identity': ('kuroshio', '3', '2053M', '土曜・休日運休', '144311'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '08:58', '2'), ('大阪', '007068', '09:03', '09:04', '21'), ('天王寺', '007439', '09:18', '09:20', '15'), ('日根野', '008072', '09:46', '09:46', None), ('和歌山', '008365', '10:05', '10:06', '4'), ('海南', '008442', '10:15', '10:15', None), ('箕島', '008481', '10:27', '10:27', None), ('藤並', '008517', '10:34', '10:34', None), ('湯浅', '008554', '10:37', '10:38', None), ('御坊', '008657', '10:51', '10:51', None), ('南部', '008845', '11:14', '11:15', None), ('紀伊田辺', '008867', '11:21', '11:23', None), ('白浜', '008915', '11:37', None, None)]}, 'jr-west.kuroshio.4.2026-09-30': {'identity': ('kuroshio', '4', '2054M', '土曜・休日運休', '144451'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('和歌山', '008365', None, '06:00', '1'), ('和泉砂川', '008142', '06:15', '06:15', None), ('日根野', '008072', '06:20', '06:21', None), ('和泉府中', '007871', '06:33', '06:34', None), ('天王寺', '007439', '06:56', '06:59', '18'), ('大阪', '007068', '07:13', '07:14', '24'), ('新大阪', '006911', '07:19', None, '2')]}, 'jr-west.kuroshio.5.2026-09-30': {'identity': ('kuroshio', '5', '6055M', '９月１８・２４・２５・２８～３０日・１０月１・２・５～９・１３～１６・１９～２３・２６～３０日・１１月２・４～６・９～１３・１６～２０・２４～２７・３０日運転', '198471'), 'equipment': ['オーシャンアロー車両で運転', '女性専用席があります', 'グリーン車指定席（パノラマ型グリーン車）', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '09:28', '2'), ('大阪', '007068', '09:32', '09:33', '21'), ('天王寺', '007439', '09:45', '09:47', '15'), ('日根野', '008072', '10:14', '10:15', None), ('和歌山', '008365', '10:34', '10:35', '4'), ('海南', '008442', '10:44', '10:44', None), ('御坊', '008657', '11:16', '11:17', None), ('紀伊田辺', '008867', '11:46', '11:47', None), ('白浜', '008915', '11:58', '12:01', None), ('周参見', '009191', '12:21', '12:22', None), ('串本', '009265', '12:55', '12:56', None), ('古座', '009224', '13:04', '13:05', None), ('太地', '009025', '13:22', '13:23', None), ('紀伊勝浦', '008974', '13:29', '13:30', None), ('新宮', '008874', '13:53', None, None)]}}


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
