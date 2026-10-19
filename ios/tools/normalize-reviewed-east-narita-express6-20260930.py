#!/usr/bin/env python3
"""Stage the two source-pinned Narita Express 6 branches for September 30."""

import json
from datetime import datetime
from pathlib import Path

import reviewed_timetable_staging as staging


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "east-narita-express6-20260930"
CANDIDATE = BASE / "candidates/jr-east-narita-express6-20260930.json"
DAY, NEXT_DAY = "2026-09-30", "2026-10-01"
SOURCE = "jr-east-narita-express6-20260930"
URL = "https://timetables.jreast.co.jp/2610/train/060/063411.html"
SERVICE = "narita-express"
STATION_NAME_ALIASES = {"空港第２ビル": "空港第2ビル"}
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
EXPECTED = {
    "2005M": ("大船", "成田空港", 9, "06:38", "08:36"),
    "2205M": ("新宿", "成田空港", 7, "07:07", None),
}


STAGING_FACTS = {
    'edition_prefix': 'JR時刻表2026年10月号; 成田エクスプレス6号 ',
    'public_number': '6',
    'coupling_note': '成田空港－東京は2206Mを併結 / 成田空港－東京は2006Mに併結 ',
    'incomplete_note': 'Before Tokyo this column prints no independent clock or platform; unknown cells remain null.',
    'identity_note': 'Official numbered-column Narita Express 6 page.',
    'partial_stops_note': 'Pre-Tokyo coupled-column cells are blank; shared calls follow coupling note.',
    'partial_times_note': 'Tokyo arrival and all earlier coupled-column clocks are unprinted.',
    'title': '成田エクスプレス 6号 2006M / 2206M 停車駅一覧',
    'summary': 'Staged NEX6: 2 trips',
    'relations': [{'trip_id': 'jr-east.narita-express.6.2006m.exact-2026-09-30', 'related_trip_id': 'jr-east.narita-express.6.2206m.exact-2026-09-30', 'relation_type': 'couples_with', 'from_sequence': 1, 'to_sequence': 7, 'source_id': 'jr-east-narita-express6-20260930'}, {'trip_id': 'jr-east.narita-express.6.2206m.exact-2026-09-30', 'related_trip_id': 'jr-east.narita-express.6.2006m.exact-2026-09-30', 'relation_type': 'couples_with', 'from_sequence': 1, 'to_sequence': 7, 'source_id': 'jr-east-narita-express6-20260930'}],
}

def read_rows(pattern, exclude=None):
    yield from staging.iter_jsonl(BASE, pattern, exclude)


def write_jsonl(path, rows):
    staging.emit_jsonl(path, rows)


PINNED = {'candidate_id': 'jr-east-narita-express6-20260930',
 'candidate_status': 'reviewed_official_html',
 'canonical': False,
 'service_date': '2026-09-30',
 'source_id': 'jr-east-narita-express6-20260930',
 'source_url': 'https://timetables.jreast.co.jp/2610/train/060/063411.html',
 'source_locator': '2026年9月30日 td.ok; full printed numbered columns',
 'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
 'coupling_note': '成田空港－東京は2206Mを併結 / 成田空港－東京は2006Mに併結',
 'printed_operating_labels': ['１１月７日は運休', '１１月７日は運休'],
 'printed_remarks': ['普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
                     '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です'],
 'trips': [{'trip_id': 'jr-east.narita-express.6.2006m.exact-2026-09-30',
            'train_number': '2006M',
            'origin': '成田空港',
            'destination': '大船',
            'stops': [['成田空港', None, '08:49', None, 'origin'],
                      ['空港第２ビル', '08:51', '08:53', None, 'passenger_stop'],
                      ['成田', '09:04', '09:04', '１', 'passenger_stop'],
                      ['佐倉', '09:15', '09:16', '３', 'passenger_stop'],
                      ['四街道', '09:21', '09:22', '１', 'passenger_stop'],
                      ['千葉', '09:28', '09:29', '７', 'passenger_stop'],
                      ['東京', '09:54', '09:56', '１', 'passenger_stop'],
                      ['品川', '10:02', '10:03', '１５', 'passenger_stop'],
                      ['武蔵小杉', '10:13', '10:14', None, 'passenger_stop'],
                      ['横浜', '10:26', '10:27', '９', 'passenger_stop'],
                      ['戸塚', '10:38', '10:39', None, 'passenger_stop'],
                      ['大船', '10:44', None, '７', 'destination']],
            'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'],
            'formation': None},
           {'trip_id': 'jr-east.narita-express.6.2206m.exact-2026-09-30',
            'train_number': '2206M',
            'origin': '成田空港',
            'destination': '新宿',
            'stops': [['成田空港', None, None, None, 'origin'],
                      ['空港第２ビル', None, None, None, 'passenger_stop'],
                      ['成田', None, None, None, 'passenger_stop'],
                      ['佐倉', None, None, None, 'passenger_stop'],
                      ['四街道', None, None, None, 'passenger_stop'],
                      ['千葉', None, None, None, 'passenger_stop'],
                      ['東京', None, '09:58', '１', 'passenger_stop'],
                      ['品川', None, None, None, 'pass'],
                      ['渋谷', '10:15', '10:16', None, 'passenger_stop'],
                      ['新宿', '10:20', None, '５', 'destination']],
            'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'],
            'formation': None}]}


def validate(candidate):
    return staging.reject_unless_pinned(candidate, PINNED)


def station_ids(trips):
    return staging.jr_east_forced_station_ids(ROOT, trips, STATION_NAME_ALIASES)


def main():
    staging.stage_jr_east_coupled_columns(
        base=BASE,
        root=ROOT,
        candidate_path=CANDIDATE,
        suffix=SUFFIX,
        day=DAY,
        next_day=NEXT_DAY,
        source_id=SOURCE,
        url=URL,
        service=SERVICE,
        aliases=STATION_NAME_ALIASES,
        weekdays=WEEKDAYS,
        pinned=PINNED,
        copy=STAGING_FACTS,
    )


if __name__ == "__main__":
    main()
