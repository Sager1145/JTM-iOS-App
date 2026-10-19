#!/usr/bin/env python3
"""Stage the dated JR Odekake Hida 1 timetable without route guesses."""

import json
from pathlib import Path

import reviewed_timetable_staging as staging

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "central-hida1-20260930"
DATE, UNTIL = "2026-09-30", "2026-10-01"
TRIP = "jr-central.hida.1.2026-09-30"
SOURCE = "jr-west-odekake-hida1-21d-20260930"
URL = "https://timetable.jr-odekake.net/train-timetable/77261?date=20260930"
STOPS = [
    ("名古屋", "005451", None, "07:43", "11", "origin"),
    ("尾張一宮", "005111", "07:54", "07:54", None, "passenger_stop"),
    ("岐阜", "004788", "08:04", "08:05", None, "passenger_stop"),
    ("鵜沼", "004836", "08:17", "08:17", None, "passenger_stop"),
    ("美濃太田", "004693", "08:26", "08:27", None, "passenger_stop"),
    ("白川口", "004293", "08:48", "08:49", None, "passenger_stop"),
    ("飛騨金山", "003902", "09:04", "09:05", None, "passenger_stop"),
    ("下呂", "003075", "09:25", "09:27", None, "passenger_stop"),
    ("飛騨萩原", "002962", "09:35", "09:35", None, "passenger_stop"),
    ("飛騨小坂", "002831", "09:46", "09:47", None, "passenger_stop"),
    ("久々野", "002699", "10:03", "10:03", None, "passenger_stop"),
    ("高山", "002587", "10:16", None, None, "destination"),
]
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


STAGING_FACTS = {
    'candidate_path': 'candidates/jr-central-hida1-20260930.json',
    'identity_note': 'Dated page prints ひだ1号.',
    'train_number_note': 'Dated page prints 21D.',
    'stops_note': 'Twelve timed calls; レ rows excluded.',
    'edition_name': 'JR Odekake 2026-09-30 Hida 1 selected timetable',
    'service_id': 'hida',
    'train_number': '21D',
    'public_number': '1',
    'origin_station_id': 'jp.n02.005451',
    'destination_station_id': 'jp.n02.002587',
    'summary_suffix': ': 12 timed passenger calls, exact date only',
}

def rows(pattern, exclude=None):
    yield from staging.iter_jsonl(BASE, pattern, exclude)


def write(path, data):
    staging.emit_jsonl(path, data)


def validate(candidate, source):
    trip = candidate["trip"]
    if (candidate["candidate_status"], candidate["canonical"],
            candidate["selected_service_date"], candidate["valid_until"],
            candidate["service_id"], candidate["source_calendar_label"]) != (
            "visually_reviewed", False, DATE, UNTIL, "hida", "毎日運転"):
        raise ValueError("Candidate status/date changed")
    if DATE > json.loads((BASE / "manifest.json").read_text())["as_of_date"]:
        raise ValueError("Date exceeds cutoff")
    if (candidate["source_id"], candidate["source_url"], trip["trip_id"],
            trip["public_number"], trip["train_number"], trip["origin"],
            trip["destination"]) != (
            SOURCE, URL, TRIP, "1", "21D", "名古屋", "高山"):
        raise ValueError("Identity/source changed")
    if (source["source_id"], source["url_or_locator"], source["effective_date"],
            source["redistribution_status"], source["automated_extraction_allowed"]) != (
            SOURCE, URL, DATE, "verification_only", False):
        raise ValueError("Source registry changed")
    expected = [(n, a, d, p, k) for n, _, a, d, p, k in STOPS]
    actual = [(r["name_snapshot"], r["arrival_time"], r["departure_time"],
               r["platform"], r["call_type"]) for r in trip["stop_times"]]
    if actual != expected or [r["stop_sequence"] for r in trip["stop_times"]] != list(range(1, 13)):
        raise ValueError("Printed passenger timetable changed")
    if len([r for r in rows("normalized/services*.jsonl") if r["service_id"] == "hida"]) != 1:
        raise ValueError("Shared Hida service identity missing or duplicate")
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
