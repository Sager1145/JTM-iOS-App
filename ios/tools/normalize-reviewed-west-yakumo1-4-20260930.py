#!/usr/bin/env python3
# coding: utf-8
"""Stage four source-reviewed September 30 Yakumo trains."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-yakumo1-4-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.yakumo.1.2026-09-30': {'identity': ('yakumo', '1', '1001M', '毎日運転', '76231'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('岡山', '007310', None, '07:05', '2'), ('倉敷', '007598', '07:16', '07:16', None), ('備中高梁', '006686', '07:40', '07:40', None), ('新見', '006070', '08:10', '08:11', None), ('生山', '005452', '08:43', '08:44', None), ('米子', '004758', '09:21', '09:23', '2'), ('安来', '004748', '09:30', '09:30', None), ('松江', '004638', '09:49', '09:50', None), ('玉造温泉', '004736', '09:56', '09:56', None), ('宍道', '004793', '10:06', '10:07', None), ('出雲市', '004943', '10:18', None, None)]}, 'jr-west.yakumo.2.2026-09-30': {'identity': ('yakumo', '2', '1002M', '９月１８日・１０月１４～１６・２０～２３・２７～３０日・１１月５・６・１０～１３・１７～２０日は出雲市－米子間運休', '76332'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('出雲市', '004943', None, '04:42', None), ('宍道', '004793', '04:52', '04:53', None), ('松江', '004638', '05:06', '05:07', None), ('安来', '004748', '05:22', '05:23', None), ('米子', '004758', '05:30', '05:32', '1'), ('伯耆大山', '004738', '05:36', '05:36', None), ('生山', '005452', '06:09', '06:10', None), ('新見', '006070', '06:39', '06:40', None), ('備中高梁', '006686', '07:06', '07:06', None), ('倉敷', '007598', '07:28', '07:29', None), ('岡山', '007310', '07:41', None, '3')]}, 'jr-west.yakumo.3.2026-09-30': {'identity': ('yakumo', '3', '1003M', '毎日運転', '76241'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('岡山', '007310', None, '08:13', '2'), ('倉敷', '007598', '08:24', '08:24', None), ('備中高梁', '006686', '08:47', '08:48', None), ('新見', '006070', '09:14', '09:15', None), ('根雨', '005255', '10:00', '10:00', None), ('米子', '004758', '10:23', '10:25', '2'), ('安来', '004748', '10:32', '10:32', None), ('松江', '004638', '10:47', '10:48', None), ('宍道', '004793', '11:01', '11:01', None), ('出雲市', '004943', '11:12', None, None)]}, 'jr-west.yakumo.4.2026-09-30': {'identity': ('yakumo', '4', '1004M', '毎日運転', '76281'), 'equipment': ['グリーン車指定席', '普通車全車指定席'], 'calls': [('出雲市', '004943', None, '05:27', None), ('宍道', '004793', '05:37', '05:38', None), ('松江', '004638', '05:51', '05:52', None), ('安来', '004748', '06:07', '06:08', None), ('米子', '004758', '06:15', '06:23', '1'), ('伯耆大山', '004738', '06:27', '06:27', None), ('根雨', '005255', '06:47', '06:48', None), ('新見', '006070', '07:29', '07:29', None), ('備中高梁', '006686', '07:59', '08:00', None), ('総社', '007263', '08:15', '08:15', None), ('倉敷', '007598', '08:23', '08:24', None), ('岡山', '007310', '08:35', None, '3')]}}


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
