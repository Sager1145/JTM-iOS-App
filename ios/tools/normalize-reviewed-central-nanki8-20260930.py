#!/usr/bin/env python3
"""Stage the dated JR Odekake Nanki 8 timetable without route guesses."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "central-nanki8-20260930"
DATE, UNTIL = "2026-09-30", "2026-10-01"
TRIP = "jr-central.nanki.8.2026-09-30"
SOURCE = "jr-west-odekake-nanki8-3008d-20260930"
URL = "https://timetable.jr-odekake.net/train-timetable/59561?date=20260930"
STOPS = [('紀伊勝浦', '008974', None, '17:11', None, 'origin'), ('新宮', '008874', '17:29', '17:31', None, 'passenger_stop'), ('熊野市', '008674', '17:50', '17:50', None, 'passenger_stop'), ('尾鷲', '008495', '18:18', '18:18', None, 'passenger_stop'), ('紀伊長島', '008394', '18:39', '18:40', None, 'passenger_stop'), ('三瀬谷', '008051', '19:08', '19:08', None, 'passenger_stop'), ('多気', '007806', '19:30', '19:32', None, 'passenger_stop'), ('松阪', '007664', '19:38', '19:39', None, 'passenger_stop'), ('津', '006905', '19:53', '19:54', None, 'passenger_stop'), ('鈴鹿', '006367', '20:06', '20:07', None, 'passenger_stop'), ('四日市', '006159', '20:15', '20:15', None, 'passenger_stop'), ('桑名', '005776', '20:26', '20:26', None, 'passenger_stop'), ('名古屋', '005451', '20:49', None, '13', 'destination')]
CALENDAR = {'month': '2026年9月', 'day': 30, 'status': 'displayed_timetable_operates', 'cell_class': 'drivingday-01', 'method': 'Official HTML calendar cell and printed drivingday-01 legend inspected', 'variant_url': 'https://timetable.jr-odekake.net/train-timetable/59561?date=20260930'}
DIRECTION = 'up'
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def rows(pattern, exclude=None):
    for path in sorted(BASE.glob(pattern)):
        if path == exclude:
            continue
        for raw in path.read_text(encoding="utf-8").splitlines():
            if raw.strip():
                yield json.loads(raw)


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in data), encoding="utf-8")


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
            SOURCE, URL, TRIP, "8", "3008D", '紀伊勝浦', '名古屋'):
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
    candidate = json.loads((BASE / "candidates/jr-central-nanki8-20260930.json").read_text())
    source = json.loads((BASE / f"sources/source-registry-{SUFFIX}.jsonl").read_text())
    validate(candidate, source)
    version, calendar = TRIP + ".version", TRIP + ".calendar"
    facts = {
        "identity": ("verified", "high", "Dated page prints 南紀8号."),
        "train_number": ("verified", "high", "Dated page prints 3008D."),
        "operator": ("unknown", "low", "Ordered operator segments not established."),
        "validity_calendar": ("verified", "high", "Only September 30 is promoted."),
        "origin_destination": ("verified", "high", "Both termini printed."),
        "stops": ("verified", "high", "13 timed calls; レ rows excluded."),
        "times": ("verified", "high", "Printed minute clocks and side blanks retained."),
        "route_lines": ("unknown", "low", "Dated physical line identities not established."),
        "station_refs": ("verified", "high", "Exact current N02 name-code matches."),
        "provenance": ("partial", "medium", "Official page is verification-only."),
    }
    outputs = {
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": station_additions(),
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": [{
            "timetable_version_id": version, "operator_scope": "jr-central",
            "effective_from": DATE, "effective_until": UNTIL,
            "edition_name": "JR Odekake 2026-09-30 Nanki 8 selected timetable",
            "revision_type": "observed_date", "publication_date": None,
            "completeness": "partial", "source_ids": [SOURCE]}],
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": [{
            "calendar_id": calendar, "valid_from": DATE, "valid_until": UNTIL,
            "holiday_policy": "none", **{d: 0 for d in WEEKDAYS}}],
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": [{
            "calendar_id": calendar, "service_date": DATE, "exception_type": "add",
            "reason": "September 30 selected in the official dated page", "source_id": SOURCE}],
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": [{
            "trip_id": TRIP, "timetable_version_id": version, "service_id": "nanki",
            "calendar_id": calendar, "train_number": "3008D", "public_number": "8",
            "origin_station_id": "jp.n02.008974", "destination_station_id": "jp.n02.005451",
            "service_class": "limited_express", "notes": "Exact date only; operator and route lines unknown."}],
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": [{
            "trip_id": TRIP, "stop_sequence": i, "station_id": "jp.n02." + code,
            "arrival_time": a, "departure_time": d, "day_offset": 0, "call_type": kind,
            "pickup_allowed": int(kind != "destination"), "dropoff_allowed": int(kind != "origin"),
            "platform": platform, "time_accuracy": "minute", "source_id": SOURCE
        } for i, (_, code, a, d, platform, kind) in enumerate(STOPS, 1)],
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": [{
            "entity_type": "trip", "entity_id": TRIP, "dimension": dim,
            "status": status, "confidence": confidence, "notes": note
        } for dim, (status, confidence, note) in facts.items()],
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": [{
            "entity_type": "trip", "entity_id": TRIP, "field_name": dim,
            "source_id": "jtm-current-station-directory" if dim == "station_refs" else SOURCE,
            "page_or_locator": note, "confidence": confidence, "verification_status": status
        } for dim, (status, confidence, note) in facts.items()
          if dim not in {"operator", "route_lines"}],
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": [{
            "research_id": f"{TRIP}.{dim}", "entity_type": "trip", "entity_id": TRIP,
            "missing_dimension": dim, "status": "license_blocked" if dim == "provenance" else "open",
            "notes": note
        } for dim, note in {
            "operator": "Obtain ordered operator segments.",
            "route_lines": "Obtain dated physical-line identities.",
            "provenance": "Resolve timetable fact redistribution permission.",
        }.items()],
    }
    for path, data in outputs.items():
        write(path, data)
    print(f"Staged {TRIP}: 13 timed passenger calls, exact date only")


if __name__ == "__main__":
    main()
