#!/usr/bin/env python3
"""Promote the exact-date Shinano 24 schedule selected for 2026-09-30."""

import json
from pathlib import Path

import reviewed_timetable_staging as staging


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-central-shinano24-20260930.json"
SUFFIX = "reviewed-central-shinano24-20260930"
SOURCE_ID = "jr-east-shinano24-20260930"
SOURCE_URL = "https://timetables.jreast.co.jp/2610/train/020/020101.html"
ENGLISH_SOURCE_ID = "jr-central-conventional-limited-express-2026-en"
ENGLISH_SOURCE_URL = "https://global.jr-central.co.jp/en/nozomi/pdf/zairai_English.pdf"
STATION_SOURCE_ID = "jtm-current-station-directory"
SERVICE_DATE = "2026-09-30"
VALID_UNTIL = "2026-10-01"
WEEKDAYS = (
    "monday", "tuesday", "wednesday", "thursday",
    "friday", "saturday", "sunday",
)
EXPECTED_STOPS = [('長野', '002031', None, '18:11', '６', 'origin'), ('篠ノ井', '002096', '18:19', '18:20', None, 'passenger_stop'), ('明科', '002345', '18:53', '18:54', None, 'passenger_stop'), ('松本', '002506', '19:06', '19:07', '１', 'passenger_stop'), ('塩尻', '002616', '19:16', '19:19', None, 'passenger_stop'), ('木曽福島', '003015', '19:48', '19:48', None, 'passenger_stop'), ('上松', '003139', '19:54', '19:54', None, 'passenger_stop'), ('中津川', '004521', '20:25', '20:26', None, 'passenger_stop'), ('恵那', '004662', '20:34', '20:34', None, 'passenger_stop'), ('多治見', '005009', '20:54', '20:54', None, 'passenger_stop'), ('千種', '005450', '21:13', '21:14', None, 'passenger_stop'), ('名古屋', '005451', '21:21', None, '１０', 'destination')]


STAGING_FACTS = {
    'identity_note': 'Official selected variant prints しなの24号.',
    'train_number_note': 'Official selected variant prints 1024M.',
    'calendar_note': 'September 30 selects official schedule variant 020101.',
    'stops_note': 'The selected variant prints 12 passenger calls.',
    'edition_name': 'JR時刻表2026年10月号; exact-date しなの24号',
    'exception_reason': 'September 30 selects official Shinano 24 schedule variant 020101',
    'train_number': '1024M',
    'public_number': '24',
    'origin_name': '長野',
    'destination_name': '名古屋',
    'trip_notes': 'Equipment: グリーン車指定席; 普通車一部指定席. Exact-date selected variant with 12 passenger calls. Operator segments and ordered physical lines remain unknown.',
    'summary_prefix': 'Normalized exact-date Shinano 24 with ',
    'status_error': 'Shinano 24 candidate must remain reviewed_official_html',
    'cutoff_error': 'Shinano 24 candidate cutoff changed',
    'date_error': 'Shinano 24 date exceeds the database cutoff',
    'pinned_trip_id': 'jr-central.shinano.24.2026-09-30',
    'pinned_public_number': '24',
    'pinned_train_number': '1024M',
    'identity_error': 'Reviewed Shinano 24 identity/date changed',
    'source_error': 'Reviewed Shinano 24 source changed',
    'direction': 'up',
    'stops_error': 'Reviewed September 30 Shinano 24 stop table changed',
    'stop_sequence_end': 13,
    'sequence_error': 'Shinano 24 stop sequence changed',
}

def read_jsonl(path):
    return staging.read_jsonl(path)


def write_jsonl(path, rows):
    staging.emit_jsonl(path, rows)


def other_rows(pattern, target):
    return staging.other_normalized_rows(BASE, pattern, target)


def validate_candidate(candidate):
    staging.validate_shinano_candidate(
        candidate,
        base=BASE,
        service_date=SERVICE_DATE,
        source_id=SOURCE_ID,
        source_url=SOURCE_URL,
        expected_stops=EXPECTED_STOPS,
        english_source_id=ENGLISH_SOURCE_ID,
        english_source_url=ENGLISH_SOURCE_URL,
        copy=STAGING_FACTS,
    )


def verify_existing_service_and_english_name():
    staging.verify_shinano_service(
        BASE,
        english_source_id=ENGLISH_SOURCE_ID,
        english_source_url=ENGLISH_SOURCE_URL,
        service_date=SERVICE_DATE,
    )


def resolve_stations():
    return staging.resolve_shinano_stations(BASE, ROOT, SUFFIX, EXPECTED_STOPS)


def main():
    staging.stage_shinano_exact_date(
        base=BASE,
        candidate_path=CANDIDATE,
        suffix=SUFFIX,
        service_date=SERVICE_DATE,
        valid_until=VALID_UNTIL,
        source_id=SOURCE_ID,
        weekdays=WEEKDAYS,
        station_source_id=STATION_SOURCE_ID,
        copy=STAGING_FACTS,
        validate_candidate=validate_candidate,
        verify_existing_service_and_english_name=verify_existing_service_and_english_name,
        resolve_stations=resolve_stations,
    )


if __name__ == "__main__":
    main()
