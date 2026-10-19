#!/usr/bin/env python3
"""Stage the two source-pinned Narita Express 3 branches for September 30."""

import json
from datetime import datetime
from pathlib import Path

import reviewed_timetable_staging as staging


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "east-narita-express3-20260930"
CANDIDATE = BASE / "candidates/jr-east-narita-express3-20260930.json"
DAY, NEXT_DAY = "2026-09-30", "2026-10-01"
SOURCE = "jr-east-narita-express3-20260930"
URL = "https://timetables.jreast.co.jp/2610/train/035/037961.html"
SERVICE = "narita-express"
STATION_NAME_ALIASES = {"空港第２ビル": "空港第2ビル"}
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
EXPECTED = {
    "2005M": ("大船", "成田空港", 9, "06:38", "08:36"),
    "2205M": ("新宿", "成田空港", 7, "07:07", None),
}


STAGING_FACTS = {
    'edition_prefix': 'JR時刻表2026年10月号; 成田エクスプレス3号 ',
    'public_number': '3',
    'coupling_note': '東京－成田空港は2203Mを併結 / 東京－成田空港は2003Mに併結 ',
    'incomplete_note': 'After Tokyo this column prints no independent clock or platform; unknown cells remain null.',
    'identity_note': 'Official numbered-column Narita Express 3 page.',
    'partial_stops_note': 'Post-Tokyo coupled-column cells are blank; shared calls follow coupling note.',
    'partial_times_note': 'Tokyo departure and all later coupled-column clocks are unprinted.',
    'title': '成田エクスプレス 3号 2003M / 2203M 停車駅一覧',
    'summary': 'Staged NEX3: 2 trips',
    'relations': [{'trip_id': 'jr-east.narita-express.3.2003m.exact-2026-09-30', 'related_trip_id': 'jr-east.narita-express.3.2203m.exact-2026-09-30', 'relation_type': 'couples_with', 'from_sequence': 6, 'to_sequence': 9, 'source_id': 'jr-east-narita-express3-20260930'}, {'trip_id': 'jr-east.narita-express.3.2203m.exact-2026-09-30', 'related_trip_id': 'jr-east.narita-express.3.2003m.exact-2026-09-30', 'relation_type': 'couples_with', 'from_sequence': 4, 'to_sequence': 7, 'source_id': 'jr-east-narita-express3-20260930'}],
}

def read_rows(pattern, exclude=None):
    yield from staging.iter_jsonl(BASE, pattern, exclude)


def write_jsonl(path, rows):
    staging.emit_jsonl(path, rows)


PINNED = {'candidate_id': 'jr-east-narita-express3-20260930',
 'candidate_status': 'reviewed_official_html',
 'canonical': False,
 'service_date': '2026-09-30',
 'source_id': 'jr-east-narita-express3-20260930',
 'source_url': 'https://timetables.jreast.co.jp/2610/train/035/037961.html',
 'source_locator': '2026年9月30日 td.ok; full printed numbered columns',
 'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
 'coupling_note': '東京－成田空港は2203Mを併結 / 東京－成田空港は2003Mに併結',
 'printed_operating_labels': ['１１月７日は運休', '１１月７日は運休'],
 'printed_remarks': ['普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
                     '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です'],
 'trips': [{'trip_id': 'jr-east.narita-express.3.2003m.exact-2026-09-30',
            'train_number': '2003M',
            'origin': '大船',
            'destination': '成田空港',
            'stops': [['大船', None, '06:06', '５', 'origin'],
                      ['戸塚', '06:11', '06:12', None, 'passenger_stop'],
                      ['横浜', '06:21', '06:22', '１０', 'passenger_stop'],
                      ['武蔵小杉', '06:33', '06:34', None, 'passenger_stop'],
                      ['品川', '06:45', '06:47', '１３', 'passenger_stop'],
                      ['東京', '06:54', '07:00', '４', 'passenger_stop'],
                      ['千葉', '07:26', '07:26', '１０', 'passenger_stop'],
                      ['空港第２ビル', '07:54', '07:56', None, 'passenger_stop'],
                      ['成田空港', '07:58', None, None, 'destination']],
            'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'],
            'formation': None},
           {'trip_id': 'jr-east.narita-express.3.2203m.exact-2026-09-30',
            'train_number': '2203M',
            'origin': '新宿',
            'destination': '成田空港',
            'stops': [['新宿', None, '06:34', '５', 'origin'],
                      ['渋谷', '06:39', '06:40', None, 'passenger_stop'],
                      ['品川', None, None, None, 'pass'],
                      ['東京', '06:58', None, '４', 'passenger_stop'],
                      ['千葉', None, None, None, 'passenger_stop'],
                      ['空港第２ビル', None, None, None, 'passenger_stop'],
                      ['成田空港', None, None, None, 'destination']],
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
