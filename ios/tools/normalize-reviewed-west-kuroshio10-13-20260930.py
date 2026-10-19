#!/usr/bin/env python3
# coding: utf-8
"""Stage four date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kuroshio10-13-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.kuroshio.10.2026-09-30': {'identity': ('kuroshio', '10', '2060M', '土曜・休日運休', '144491'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('白浜', '008915', None, '07:10', None), ('紀伊田辺', '008867', '07:20', '07:22', None), ('南部', '008845', '07:28', '07:28', None), ('御坊', '008657', '07:52', '07:53', None), ('湯浅', '008554', '08:06', '08:07', None), ('藤並', '008517', '08:10', '08:11', None), ('箕島', '008481', '08:17', '08:18', None), ('海南', '008442', '08:29', '08:30', None), ('和歌山', '008365', '08:39', '08:41', '1'), ('和泉砂川', '008142', '08:58', '08:58', None), ('日根野', '008072', '09:03', '09:04', None), ('天王寺', '007439', '09:34', '09:35', '18'), ('大阪', '007068', '09:46', '09:47', '24'), ('新大阪', '006911', '09:52', None, '2')]}, 'jr-west.kuroshio.11.2026-09-30': {'identity': ('kuroshio', '11', '61M', '毎日運転', '144341'), 'equipment': ['オーシャンアロー車両で運転', '女性専用席があります', 'グリーン車指定席（パノラマ型グリーン車）', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '12:13', '2'), ('大阪', '007068', '12:17', '12:18', '21'), ('天王寺', '007439', '12:30', '12:32', '15'), ('日根野', '008072', '12:57', '12:57', None), ('和歌山', '008365', '13:15', '13:18', '4'), ('海南', '008442', '13:27', '13:27', None), ('御坊', '008657', '14:00', '14:00', None), ('紀伊田辺', '008867', '14:29', '14:31', None), ('白浜', '008915', '14:41', '14:43', None), ('周参見', '009191', '15:07', '15:08', None), ('串本', '009265', '15:40', '15:40', None), ('古座', '009224', '15:49', '15:50', None), ('太地', '009025', '16:08', '16:09', None), ('紀伊勝浦', '008974', '16:16', '16:17', None), ('新宮', '008874', '16:40', None, None)]}, 'jr-west.kuroshio.12.2026-09-30': {'identity': ('kuroshio', '12', '62M', '土曜・休日運休', '144511'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新宮', '008874', None, '06:27', None), ('紀伊勝浦', '008974', '06:44', '06:45', None), ('太地', '009025', '06:51', '06:52', None), ('古座', '009224', '07:10', '07:10', None), ('串本', '009265', '07:18', '07:19', None), ('周参見', '009191', '07:50', '07:51', None), ('白浜', '008915', '08:13', '08:20', None), ('紀伊田辺', '008867', '08:30', '08:32', None), ('南部', '008845', '08:37', '08:38', None), ('御坊', '008657', '09:02', '09:03', None), ('湯浅', '008554', '09:16', '09:16', None), ('藤並', '008517', '09:19', '09:20', None), ('箕島', '008481', '09:26', '09:27', None), ('海南', '008442', '09:38', '09:39', None), ('和歌山', '008365', '09:48', '09:50', '1'), ('日根野', '008072', '10:08', '10:09', None), ('天王寺', '007439', '10:33', '10:35', '18'), ('大阪', '007068', '10:46', '10:47', '24'), ('新大阪', '006911', '10:51', '10:52', '1'), ('京都', '006079', '11:17', None, '0')]}, 'jr-west.kuroshio.13.2026-09-30': {'identity': ('kuroshio', '13', '2063M', '毎日運転', '144351'), 'equipment': ['女性専用席があります', 'グリーン車指定席', '普通車全車指定席'], 'calls': [('新大阪', '006911', None, '13:13', '2'), ('大阪', '007068', '13:17', '13:18', '21'), ('天王寺', '007439', '13:30', '13:32', '15'), ('日根野', '008072', '13:57', '13:57', None), ('和歌山', '008365', '14:15', '14:18', '4'), ('海南', '008442', '14:27', '14:27', None), ('箕島', '008481', '14:39', '14:40', None), ('藤並', '008517', '14:46', '14:47', None), ('湯浅', '008554', '14:50', '14:50', None), ('御坊', '008657', '15:04', '15:04', None), ('南部', '008845', '15:27', '15:28', None), ('紀伊田辺', '008867', '15:35', '15:36', None), ('白浜', '008915', '15:47', None, None)]}}


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
