#!/usr/bin/env python3
# coding: utf-8
"""Stage four source-reviewed September 30 Yakumo trains."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-yakumo5-8-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.yakumo.5.2026-09-30': {'identity': ('yakumo', '5', '1005M', '毎日運転', '76251'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('岡山', '007310', None, '09:13', '2'), ('倉敷', '007598', '09:24', '09:24', None), ('総社', '007263', '09:32', '09:33', None), ('備中高梁', '006686', '09:49', '09:49', None), ('新見', '006070', '10:18', '10:18', None), ('生山', '005452', '10:48', '10:49', None), ('米子', '004758', '11:25', '11:26', '2'), ('安来', '004748', '11:33', '11:33', None), ('松江', '004638', '11:48', '11:49', None), ('宍道', '004793', '12:06', '12:06', None), ('出雲市', '004943', '12:17', None, None)]}, 'jr-west.yakumo.6.2026-09-30': {'identity': ('yakumo', '6', '1006M', '毎日運転', '76291'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('出雲市', '004943', None, '06:30', None), ('宍道', '004793', '06:45', '06:46', None), ('玉造温泉', '004736', '06:54', '06:55', None), ('松江', '004638', '07:02', '07:03', None), ('安来', '004748', '07:18', '07:19', None), ('米子', '004758', '07:27', '07:30', '1'), ('伯耆大山', '004738', '07:35', '07:35', None), ('生山', '005452', '08:08', '08:08', None), ('新見', '006070', '08:38', '08:39', None), ('備中高梁', '006686', '09:13', '09:14', None), ('倉敷', '007598', '09:35', '09:36', None), ('岡山', '007310', '09:47', None, '3')]}, 'jr-west.yakumo.7.2026-09-30': {'identity': ('yakumo', '7', '1007M', '毎日運転', '76261'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('岡山', '007310', None, '10:13', '2'), ('倉敷', '007598', '10:24', '10:24', None), ('備中高梁', '006686', '10:47', '10:48', None), ('新見', '006070', '11:15', '11:16', None), ('根雨', '005255', '12:01', '12:02', None), ('米子', '004758', '12:25', '12:27', '2'), ('安来', '004748', '12:33', '12:34', None), ('松江', '004638', '12:49', '12:50', None), ('玉造温泉', '004736', '12:55', '12:56', None), ('宍道', '004793', '13:03', '13:04', None), ('出雲市', '004943', '13:15', None, None)]}, 'jr-west.yakumo.8.2026-09-30': {'identity': ('yakumo', '8', '1008M', '毎日運転', '76301'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('出雲市', '004943', None, '07:30', None), ('宍道', '004793', '07:41', '07:42', None), ('玉造温泉', '004736', '07:49', '07:50', None), ('松江', '004638', '07:56', '07:57', None), ('安来', '004748', '08:16', '08:17', None), ('米子', '004758', '08:25', '08:29', '1'), ('伯耆大山', '004738', '08:33', '08:34', None), ('根雨', '005255', '08:57', '08:58', None), ('新見', '006070', '09:40', '09:41', None), ('備中高梁', '006686', '10:08', '10:08', None), ('倉敷', '007598', '10:30', '10:31', None), ('岡山', '007310', '10:43', None, '3')]}}


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
        'notes': 'Printed Green reserved and all ordinary reserved categories only; actual vehicle, car count, capacity and dispatch unverified.',
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
        source_count=4,
        trip_count_error='Expected precisely four reviewed trips',
    )


if __name__ == "__main__":
    main()
