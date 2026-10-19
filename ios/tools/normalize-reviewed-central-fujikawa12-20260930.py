#!/usr/bin/env python3
"""Stage the dated JR East Fujikawa 12 timetable without route guesses."""

import json
from pathlib import Path

import reviewed_timetable_staging as staging

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "central-fujikawa12-20260930"
DATE, UNTIL = "2026-09-30", "2026-10-01"
TRIP = "jr-central.fujikawa.12.2026-09-30"
# Opaque legacy identity retained; publisher and edition follow the pinned JR East URL.
SOURCE = "jr-west-odekake-fujikawa12-4012m-20260930"
URL = "https://timetables.jreast.co.jp/2610/train/010/011121.html"
STOPS = [('甲府', '003867', None, '16:35', None, 'origin'), ('南甲府', '004018', '16:39', '16:40', None, 'passenger_stop'), ('東花輪', '004252', '16:48', '16:48', None, 'passenger_stop'), ('市川大門', '004337', '16:55', '16:56', None, 'passenger_stop'), ('鰍沢口', '004397', '16:59', '17:00', None, 'passenger_stop'), ('甲斐岩間', '004545', '17:06', '17:07', None, 'passenger_stop'), ('下部温泉', '004754', '17:16', '17:19', None, 'passenger_stop'), ('身延', '004939', '17:28', '17:29', None, 'passenger_stop'), ('内船', '005155', '17:42', '17:43', None, 'passenger_stop'), ('富士宮', '005304', '18:12', '18:13', None, 'passenger_stop'), ('富士', '005522', '18:24', '18:28', None, 'passenger_stop'), ('清水', '005898', '18:46', '18:46', None, 'passenger_stop'), ('静岡', '006128', '18:56', None, '３', 'destination')]
CALENDAR = {'month': '2026年9月', 'day': 30, 'cell_class': 'ok', 'status': 'displayed_timetable_operates', 'method': 'Official September calendar cell inspected', 'variant_url': 'https://timetables.jreast.co.jp/2610/train/010/011121.html'}
DIRECTION = 'up'
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


STAGING_FACTS = {
    'candidate_path': 'candidates/jr-central-fujikawa12-20260930.json',
    'identity_note': 'Dated page prints ふじかわ12号.',
    'train_number_note': 'Dated page prints 4012M.',
    'stops_note': '13 timed calls; レ rows excluded.',
    'edition_name': 'JR East 2026-09-30 Fujikawa 12 selected timetable',
    'service_id': 'fujikawa',
    'train_number': '4012M',
    'public_number': '12',
    'origin_station_id': 'jp.n02.003867',
    'destination_station_id': 'jp.n02.006128',
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
            "visually_reviewed", False, DATE, UNTIL, "fujikawa", "2026年9月30日 運転格ok"):
        raise ValueError("Candidate status/date changed")
    if DATE > json.loads((BASE / "manifest.json").read_text())["as_of_date"]:
        raise ValueError("Date exceeds cutoff")
    if (candidate["source_id"], candidate["source_url"], trip["trip_id"],
            trip["public_number"], trip["train_number"], trip["origin"],
            trip["destination"]) != (
            SOURCE, URL, TRIP, "12", "4012M", '甲府', '静岡'):
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
    if len([r for r in rows("normalized/services*.jsonl") if r["service_id"] == "fujikawa"]) != 1:
        raise ValueError("Shared Fujikawa service identity missing or duplicate")
    if any(r["trip_id"] == TRIP for r in rows("normalized/trips/*/*.jsonl",
                    BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")):
        raise ValueError("Trip ID duplicate")


def station_additions():
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    existing = {r["station_id"]: r for r in rows("normalized/station-identities*.jsonl",
                    BASE / f"normalized/station-identities-{SUFFIX}.jsonl")}
    additions = []
    for name, code, *_ in STOPS:
        found = {s[0] for line in package["lines"] for s in line["stations"] if s[1] == name and line["operator"] == "東海旅客鉄道"}
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
