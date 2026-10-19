#!/usr/bin/env python3
# coding: utf-8
"""Stage four source-reviewed September 30 Yakumo trains."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-yakumo9-12-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.yakumo.9.2026-09-30': {'identity': ('yakumo', '9', '1009M', '毎日運転', '76271'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('岡山', '007310', None, '11:13', '2'), ('倉敷', '007598', '11:24', '11:24', None), ('備中高梁', '006686', '11:47', '11:48', None), ('新見', '006070', '12:15', '12:16', None), ('生山', '005452', '12:48', '12:49', None), ('米子', '004758', '13:25', '13:26', '2'), ('安来', '004748', '13:33', '13:34', None), ('松江', '004638', '13:48', '13:49', None), ('玉造温泉', '004736', '13:55', '13:56', None), ('宍道', '004793', '14:08', '14:08', None), ('出雲市', '004943', '14:19', None, None)]}, 'jr-west.yakumo.10.2026-09-30': {'identity': ('yakumo', '10', '1010M', '毎日運転', '76321'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('出雲市', '004943', None, '08:34', None), ('宍道', '004793', '08:47', '08:48', None), ('玉造温泉', '004736', '08:56', '08:56', None), ('松江', '004638', '09:05', '09:06', None), ('安来', '004748', '09:26', '09:26', None), ('米子', '004758', '09:34', '09:35', '1'), ('伯耆大山', '004738', '09:39', '09:40', None), ('生山', '005452', '10:13', '10:14', None), ('新見', '006070', '10:44', '10:45', None), ('備中高梁', '006686', '11:13', '11:14', None), ('倉敷', '007598', '11:35', '11:36', None), ('岡山', '007310', '11:47', None, '3')]}, 'jr-west.yakumo.11.2026-09-30': {'identity': ('yakumo', '11', '1011M', '毎日運転', '541'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('岡山', '007310', None, '12:13', '2'), ('倉敷', '007598', '12:24', '12:24', None), ('総社', '007263', '12:32', '12:33', None), ('備中高梁', '006686', '12:49', '12:49', None), ('新見', '006070', '13:20', '13:21', None), ('根雨', '005255', '14:03', '14:03', None), ('米子', '004758', '14:26', '14:28', '2'), ('安来', '004748', '14:34', '14:35', None), ('松江', '004638', '14:54', '14:55', None), ('玉造温泉', '004736', '15:01', '15:01', None), ('宍道', '004793', '15:09', '15:09', None), ('出雲市', '004943', '15:20', None, None)]}, 'jr-west.yakumo.12.2026-09-30': {'identity': ('yakumo', '12', '1012M', '毎日運転', '278901'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('出雲市', '004943', None, '09:40', None), ('宍道', '004793', '09:55', '09:56', None), ('玉造温泉', '004736', '10:04', '10:04', None), ('松江', '004638', '10:10', '10:11', None), ('安来', '004748', '10:26', '10:27', None), ('米子', '004758', '10:34', '10:36', '1'), ('根雨', '005255', '10:59', '11:02', None), ('新見', '006070', '11:44', '11:44', None), ('備中高梁', '006686', '12:13', '12:14', None), ('倉敷', '007598', '12:35', '12:36', None), ('岡山', '007310', '12:47', None, '3')]}}


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
