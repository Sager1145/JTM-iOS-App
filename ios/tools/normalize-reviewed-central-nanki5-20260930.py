#!/usr/bin/env python3
"""Stage the dated JR Odekake Nanki 5 timetable without route guesses."""

import json
from pathlib import Path

import reviewed_timetable_staging as staging

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "central-nanki5-20260930"
DATE, UNTIL = "2026-09-30", "2026-10-01"
TRIP = "jr-central.nanki.5.2026-09-30"
SOURCE = "jr-west-odekake-nanki5-3005d-20260930"
URL = "https://timetable.jr-odekake.net/train-timetable/28091?date=20260930"
STOPS = [('名古屋', '005451', None, '12:58', '12', 'origin'), ('桑名', '005776', '13:22', '13:22', None, 'passenger_stop'), ('四日市', '006159', '13:36', '13:37', None, 'passenger_stop'), ('鈴鹿', '006367', '13:45', '13:45', None, 'passenger_stop'), ('津', '006905', '14:00', '14:00', None, 'passenger_stop'), ('松阪', '007664', '14:16', '14:16', None, 'passenger_stop'), ('多気', '007806', '14:22', '14:23', None, 'passenger_stop'), ('三瀬谷', '008051', '14:45', '14:46', None, 'passenger_stop'), ('紀伊長島', '008394', '15:12', '15:14', None, 'passenger_stop'), ('尾鷲', '008495', '15:36', '15:36', None, 'passenger_stop'), ('熊野市', '008674', '16:04', '16:05', None, 'passenger_stop'), ('新宮', '008874', '16:24', '16:26', None, 'passenger_stop'), ('紀伊勝浦', '008974', '16:44', None, None, 'destination')]
CALENDAR = {'month': '2026年9月', 'day': 30, 'status': 'displayed_timetable_operates', 'cell_class': 'drivingday-01', 'method': 'Official HTML calendar cell and printed drivingday-01 legend inspected', 'variant_url': 'https://timetable.jr-odekake.net/train-timetable/28091?date=20260930'}
DIRECTION = 'down'
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


STAGING_FACTS = {
    'candidate_path': 'candidates/jr-central-nanki5-20260930.json',
    'identity_note': 'Dated page prints 南紀5号.',
    'train_number_note': 'Dated page prints 3005D.',
    'stops_note': '13 timed calls; レ rows excluded.',
    'edition_name': 'JR Odekake 2026-09-30 Nanki 5 selected timetable',
    'service_id': 'nanki',
    'train_number': '3005D',
    'public_number': '5',
    'origin_station_id': 'jp.n02.005451',
    'destination_station_id': 'jp.n02.008974',
    'summary_suffix': ': 13 timed passenger calls, exact date only',
}

def rows(pattern, exclude=None):
    yield from staging.iter_jsonl(BASE, pattern, exclude)


def write(path, data):
    staging.emit_jsonl(path, data)


def validate(candidate, source):
    trip = candidate["trip"]
    if candidate["calendar_observation"] != CALENDAR or trip["equipment"] != ["普通車一部指定席"] or trip["formation"] is not None or trip["direction"] != DIRECTION:
        raise ValueError("Dated calendar/equipment/direction changed")
    if (candidate["candidate_status"], candidate["canonical"],
            candidate["selected_service_date"], candidate["valid_until"],
            candidate["service_id"], candidate["source_calendar_label"]) != (
            "visually_reviewed", False, DATE, UNTIL, "nanki", "毎日運転"):
        raise ValueError("Candidate status/date changed")
    if DATE > json.loads((BASE / "manifest.json").read_text())["as_of_date"]:
        raise ValueError("Date exceeds cutoff")
    if (candidate["source_id"], candidate["source_url"], trip["trip_id"],
            trip["public_number"], trip["train_number"], trip["origin"],
            trip["destination"]) != (
            SOURCE, URL, TRIP, "5", "3005D", '名古屋', '紀伊勝浦'):
        raise ValueError("Identity/source changed")
    if (source["source_id"], source["url_or_locator"], source["effective_date"],
            source["redistribution_status"], source["automated_extraction_allowed"]) != (
            SOURCE, URL, DATE, "verification_only", False):
        raise ValueError("Source registry changed")
    expected = [(n, a, d, p, k) for n, _, a, d, p, k in STOPS]
    actual = [(r["name_snapshot"], r["arrival_time"], r["departure_time"],
               r["platform"], r["call_type"]) for r in trip["stop_times"]]
    if actual != expected or [r["stop_sequence"] for r in trip["stop_times"]] != list(range(1, 14)):
        raise ValueError("Printed passenger timetable changed")
    if len([r for r in rows("normalized/services*.jsonl") if r["service_id"] == "nanki"]) != 1:
        raise ValueError("Shared Nanki service identity missing or duplicate")
    if any(r["trip_id"] == TRIP for r in rows("normalized/trips/*/*.jsonl",
                    BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")):
        raise ValueError("Trip ID duplicate")


def station_additions():
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    existing = {r["station_id"]: r for r in rows("normalized/station-identities*.jsonl",
                    BASE / f"normalized/station-identities-{SUFFIX}.jsonl")}
    additions = []
    for name, code, *_ in STOPS:
        found = {s[0] for line in package["lines"] for s in line["stations"] if s[1] == name}
        if found != {code}:
            raise ValueError(f"Station code mismatch: {name} {found}")
        station_id = "jp.n02." + code
        prior = existing.get(station_id)
        if prior and prior["name_snapshot"] != name:
            raise ValueError(f"Station identity conflict: {station_id}")
        if prior is None:
            additions.append({"station_id": station_id, "name_snapshot": name,
                              "reference_kind": "current_n02", "current_source_code": code,
                              "rail_history_id": None})
    return additions


def main():
    staging.stage_odekake_single_trip(
        base=BASE,
        suffix=SUFFIX,
        trip_id=TRIP,
        service_date=DATE,
        valid_until=UNTIL,
        source_id=SOURCE,
        weekdays=WEEKDAYS,
        stops=STOPS,
        validate=validate,
        station_additions=station_additions,
        copy=STAGING_FACTS,
    )


if __name__ == "__main__":
    main()
