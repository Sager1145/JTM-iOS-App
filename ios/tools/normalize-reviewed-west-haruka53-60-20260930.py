#!/usr/bin/env python3
# coding: utf-8
"""Stage eight date-selected JR West limited-express train pages."""

import json
from pathlib import Path

import train_timetable as timetable

from reviewed_timetable_staging import emit_jsonl, stage_odekake_expected_batch

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-haruka53-60-20260930"
DAY, UNTIL = "2026-09-30", "2026-10-01"
EXPECTED = {'jr-west.haruka.53.2026-09-30': {'identity': ('haruka', '53', '1053M', '土曜・休日運休', '257131'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '19:00', '30'), ('新大阪', '006911', '19:27', '19:28', '3'), ('大阪', '007068', '19:32', '19:33', '21'), ('天王寺', '007439', '19:49', '19:50', '15'), ('和泉府中', '007871', '20:06', '20:07', None), ('日根野', '008072', '20:16', '20:17', None), ('関西空港', '007958', '20:25', None, None)]}, 'jr-west.haruka.54.2026-09-30': {'identity': ('haruka', '54', '1054M', '土曜・休日運休', '192741'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '20:16', None), ('天王寺', '007439', '20:48', '20:49', '18'), ('大阪', '007068', '21:01', '21:02', '24'), ('新大阪', '006911', '21:06', '21:07', '1'), ('高槻', '006432', '21:19', '21:19', None), ('京都', '006079', '21:32', '21:34', '0'), ('山科', '006043', '21:39', '21:39', None), ('大津', '006000', '21:43', '21:44', None), ('石山', '006098', '21:48', '21:48', None), ('南草津', '005991', '21:52', '21:53', None), ('草津', '005901', '21:56', '21:56', None), ('守山', '005831', '22:00', '22:00', None), ('野洲', '005772', '22:04', None, None)]}, 'jr-west.haruka.55.2026-09-30': {'identity': ('haruka', '55', '1055M', '土曜・休日運休', '129411'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '19:30', '30'), ('新大阪', '006911', '19:57', '19:58', '3'), ('大阪', '007068', '20:02', '20:03', '21'), ('天王寺', '007439', '20:18', '20:20', '15'), ('和泉府中', '007871', '20:37', '20:37', None), ('日根野', '008072', '20:46', '20:47', None), ('関西空港', '007958', '20:59', None, None)]}, 'jr-west.haruka.56.2026-09-30': {'identity': ('haruka', '56', '1056M', '土曜・休日運休', '257381'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '20:46', None), ('天王寺', '007439', '21:18', '21:19', '18'), ('大阪', '007068', '21:31', '21:32', '24'), ('新大阪', '006911', '21:36', '21:37', '1'), ('高槻', '006432', '21:49', '21:49', None), ('京都', '006079', '22:03', None, '0')]}, 'jr-west.haruka.57.2026-09-30': {'identity': ('haruka', '57', '1057M', '土曜・休日運休', '257151'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '20:00', '30'), ('新大阪', '006911', '20:27', '20:28', '3'), ('大阪', '007068', '20:32', '20:33', '21'), ('天王寺', '007439', '20:48', '20:50', '15'), ('和泉府中', '007871', '21:07', '21:07', None), ('日根野', '008072', '21:16', '21:17', None), ('関西空港', '007958', '21:27', None, None)]}, 'jr-west.haruka.58.2026-09-30': {'identity': ('haruka', '58', '1058M', '毎日運転', '129471'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '21:25', None), ('天王寺', '007439', '21:57', '21:59', '18'), ('大阪', '007068', '22:10', '22:11', '24'), ('新大阪', '006911', '22:15', '22:17', '1'), ('京都', '006079', '22:42', None, '30')]}, 'jr-west.haruka.59.2026-09-30': {'identity': ('haruka', '59', '1059M', '土曜・休日運休', '129431'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('京都', '006079', None, '20:30', '30'), ('新大阪', '006911', '20:57', '20:58', '3'), ('大阪', '007068', '21:02', '21:03', '21'), ('天王寺', '007439', '21:18', '21:21', '15'), ('和泉府中', '007871', '21:37', '21:38', None), ('日根野', '008072', '21:47', '21:49', None), ('関西空港', '007958', '21:59', None, None)]}, 'jr-west.haruka.60.2026-09-30': {'identity': ('haruka', '60', '1060M', '毎日運転', '129481'), 'equipment': ['グリーン車指定席', '普通車一部指定席'], 'calls': [('関西空港', '007958', None, '22:16', None), ('天王寺', '007439', '22:49', '22:50', '18'), ('大阪', '007068', '23:03', '23:04', '24'), ('新大阪', '006911', '23:08', '23:09', '1'), ('京都', '006079', '23:32', None, '30')]}}


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
        'notes': 'Published seat categories only; actual car count, series and dispatch unverified.',
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
        source_count=8,
        trip_count_error='Expected precisely eight reviewed trips',
    )


if __name__ == "__main__":
    main()
