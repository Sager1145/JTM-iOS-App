#!/usr/bin/env python3
"""Stage the two source-pinned Narita Express 14 branches for September 30."""

import json
from datetime import datetime
from pathlib import Path

import reviewed_timetable_staging as staging


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "east-narita-express14-20260930"
CANDIDATE = BASE / "candidates/jr-east-narita-express14-20260930.json"
DAY, NEXT_DAY = "2026-09-30", "2026-10-01"
SOURCE = "jr-east-narita-express14-20260930"
URL = "https://timetables.jreast.co.jp/2610/train/045/047971.html"
SERVICE = "narita-express"
STATION_NAME_ALIASES = {"空港第２ビル": "空港第2ビル"}
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
EXPECTED = {
    "2005M": ("大船", "成田空港", 9, "06:38", "08:36"),
    "2205M": ("新宿", "成田空港", 7, "07:07", None),
}


STAGING_FACTS = {
    'edition_prefix': 'JR時刻表2026年10月号; 成田エクスプレス14号 ',
    'public_number': '14',
    'coupling_note': '成田空港－東京は2214Mを併結 / 成田空港－東京は2014Mに併結 ',
    'incomplete_note': 'Before Tokyo this column prints no independent clock or platform; unknown cells remain null.',
    'identity_note': 'Official numbered-column Narita Express 14 page.',
    'partial_stops_note': 'Pre-Tokyo coupled-column cells are blank; shared calls follow coupling note.',
    'partial_times_note': 'Tokyo arrival and all earlier coupled-column clocks are unprinted.',
    'title': '成田エクスプレス 14号 2014M / 2214M 停車駅一覧',
    'summary': 'Staged NEX14: 2 trips',
    'relations': [{'trip_id': 'jr-east.narita-express.14.2014m.exact-2026-09-30', 'related_trip_id': 'jr-east.narita-express.14.2214m.exact-2026-09-30', 'relation_type': 'couples_with', 'from_sequence': 1, 'to_sequence': 4, 'source_id': 'jr-east-narita-express14-20260930'}, {'trip_id': 'jr-east.narita-express.14.2214m.exact-2026-09-30', 'related_trip_id': 'jr-east.narita-express.14.2014m.exact-2026-09-30', 'relation_type': 'couples_with', 'from_sequence': 1, 'to_sequence': 4, 'source_id': 'jr-east-narita-express14-20260930'}],
}

def read_rows(pattern, exclude=None):
    yield from staging.iter_jsonl(BASE, pattern, exclude)


def write_jsonl(path, rows):
    staging.emit_jsonl(path, rows)


PINNED = {'candidate_id': 'jr-east-narita-express14-20260930',
 'candidate_status': 'reviewed_official_html',
 'canonical': False,
 'service_date': '2026-09-30',
 'source_id': 'jr-east-narita-express14-20260930',
 'source_url': 'https://timetables.jreast.co.jp/2610/train/045/047971.html',
 'source_locator': '2026年9月30日 td.ok; full printed numbered columns',
 'calendar_observation': {'month': '2026年9月', 'day': 30, 'cell_class': 'ok'},
 'coupling_note': '成田空港－東京は2214Mを併結 / 成田空港－東京は2014Mに併結',
 'printed_operating_labels': ['１１月７日は運休', '１１月７日は運休'],
 'printed_remarks': ['普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です',
                     '普通車全席で指定が可能な他、座席未指定券では、車内の空席がご利用可能です'],
 'trips': [{'trip_id': 'jr-east.narita-express.14.2014m.exact-2026-09-30',
            'train_number': '2014M',
            'origin': '成田空港',
            'destination': '大船',
            'stops': [['成田空港', None, '10:45', None, 'origin'],
                      ['空港第２ビル', '10:46', '10:48', None, 'passenger_stop'],
                      ['千葉', '11:18', '11:19', '７', 'passenger_stop'],
                      ['東京', '11:44', '11:46', '１', 'passenger_stop'],
                      ['品川', '11:53', '11:53', '１５', 'passenger_stop'],
                      ['武蔵小杉', '12:03', '12:04', None, 'passenger_stop'],
                      ['横浜', '12:15', '12:16', '９', 'passenger_stop'],
                      ['戸塚', '12:25', '12:26', None, 'passenger_stop'],
                      ['大船', '12:32', None, '７', 'destination']],
            'equipment': ['座席未指定券', 'グリーン車指定席', '普通車全車指定席'],
            'formation': None},
           {'trip_id': 'jr-east.narita-express.14.2214m.exact-2026-09-30',
            'train_number': '2214M',
            'origin': '成田空港',
            'destination': '新宿',
            'stops': [['成田空港', None, None, None, 'origin'],
                      ['空港第２ビル', None, None, None, 'passenger_stop'],
                      ['千葉', None, None, None, 'passenger_stop'],
                      ['東京', None, '11:49', '１', 'passenger_stop'],
                      ['品川', None, None, None, 'pass'],
                      ['渋谷', '12:05', '12:06', None, 'passenger_stop'],
                      ['新宿', '12:11', None, '５', 'destination']],
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
