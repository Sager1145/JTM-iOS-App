#!/usr/bin/env python3
"""Promote the exact-date Shinano 4 schedule selected for 2026-09-30."""

import json
from pathlib import Path

import reviewed_timetable_staging as staging


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-central-shinano4-20260930.json"
SUFFIX = "reviewed-central-shinano4-20260930"
SOURCE_ID = "jr-east-shinano4-20260930"
SOURCE_URL = "https://timetables.jreast.co.jp/2610/train/000/000111.html"
ENGLISH_SOURCE_ID = "jr-central-conventional-limited-express-2026-en"
ENGLISH_SOURCE_URL = "https://global.jr-central.co.jp/en/nozomi/pdf/zairai_English.pdf"
STATION_SOURCE_ID = "jtm-current-station-directory"
SERVICE_DATE = "2026-09-30"
VALID_UNTIL = "2026-10-01"
WEEKDAYS = (
    "monday", "tuesday", "wednesday", "thursday",
    "friday", "saturday", "sunday",
)
EXPECTED_STOPS = [('長野', '002031', None, '07:44', '６', 'origin'), ('篠ノ井', '002096', '07:53', '07:53', None, 'passenger_stop'), ('聖高原', '002215', '08:11', '08:12', None, 'passenger_stop'), ('松本', '002506', '08:37', '08:38', '１', 'passenger_stop'), ('塩尻', '002616', '08:46', '08:49', None, 'passenger_stop'), ('木曽福島', '003015', '09:17', '09:19', None, 'passenger_stop'), ('中津川', '004521', '09:56', '09:57', None, 'passenger_stop'), ('多治見', '005009', '10:24', '10:24', None, 'passenger_stop'), ('千種', '005450', '10:42', '10:43', None, 'passenger_stop'), ('名古屋', '005451', '10:53', None, '１１', 'destination')]


STAGING_FACTS = {
    'identity_note': 'Official selected variant prints しなの4号.',
    'train_number_note': 'Official selected variant prints 1004M.',
    'calendar_note': 'September 30 selects official schedule variant 000111.',
    'stops_note': 'The selected variant prints 10 passenger calls.',
    'edition_name': 'JR時刻表2026年10月号; exact-date しなの4号',
    'exception_reason': 'September 30 selects official Shinano 4 schedule variant 000111',
    'train_number': '1004M',
    'public_number': '4',
    'origin_name': '長野',
    'destination_name': '名古屋',
    'trip_notes': 'Equipment: グリーン車指定席; 普通車一部指定席. Exact-date selected variant with 10 passenger calls. Operator segments and ordered physical lines remain unknown.',
    'summary_prefix': 'Normalized exact-date Shinano 4 with ',
    'status_error': 'Shinano 4 candidate must remain reviewed_official_html',
    'cutoff_error': 'Shinano 4 candidate cutoff changed',
    'date_error': 'Shinano 4 date exceeds the database cutoff',
    'pinned_trip_id': 'jr-central.shinano.4.2026-09-30',
    'pinned_public_number': '4',
    'pinned_train_number': '1004M',
    'identity_error': 'Reviewed Shinano 4 identity/date changed',
    'source_error': 'Reviewed Shinano 4 source changed',
    'direction': 'up',
    'stops_error': 'Reviewed September 30 Shinano 4 stop table changed',
    'stop_sequence_end': 11,
    'sequence_error': 'Shinano 4 stop sequence changed',
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
