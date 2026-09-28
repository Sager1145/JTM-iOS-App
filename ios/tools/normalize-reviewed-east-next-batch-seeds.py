#!/usr/bin/env python3
"""Normalize reviewed JR East train-detail pages through the manifest cutoff.

Every calendar is exception-only: an occurrence is emitted only for a date
whose cell is marked ``td.ok`` on that exact schedule-variant page. The JR East
publisher name is not promoted to operator-segment or route-line evidence.
"""
from collections import defaultdict
from datetime import date, timedelta
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-east-202609-east-next-batch.json"
SUFFIX = "east-next-batch"
SCOPE = "jr-east"
STATION_SOURCE_ID = "jtm-current-station-directory"
WEEKDAYS = [
    "monday", "tuesday", "wednesday", "thursday",
    "friday", "saturday", "sunday",
]
EXPECTED = {
    "jr-east-azusa1-202609-east-next": {
        "dates": ["2026-09-19", "2026-09-20", "2026-09-21", "2026-09-26"],
        "stops": 12,
        "url": "https://timetables.jreast.co.jp/2610/train/005/008042.html",
        "hash": "sha256:e715b0b17a9c8c75ef04857689e9d0084ddf0d58813046519a35bc854a375e8c",
    },
    "jr-east-azusa1-base-202609-east-next": {
        "dates": [
            "2026-09-18", "2026-09-22", "2026-09-23", "2026-09-24",
            "2026-09-25", "2026-09-27", "2026-09-28",
        ],
        "stops": 12,
        "url": "https://timetables.jreast.co.jp/2610/train/005/008041.html",
        "hash": "sha256:b86839567b5c38369bd19bc9e72f1e5f6b2bc323863cc488a7de414432e8cb64",
    },
    "jr-east-tokiwa55-202609-east-next": {
        "dates": [
            "2026-09-19", "2026-09-20", "2026-09-21", "2026-09-22",
            "2026-09-23", "2026-09-26", "2026-09-27",
        ],
        "stops": 9,
        "url": "https://timetables.jreast.co.jp/2610/train/075/076301.html",
        "hash": "sha256:aaaa428210b824f16f5fa4a7a786245b19c3fabc1579148da2431b0a181bf380",
    },
}


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(
        json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows
    ))


def day_after(value):
    return (date.fromisoformat(value) + timedelta(days=1)).isoformat()


def load_existing_rows(pattern, excluded_path):
    rows = []
    for path in sorted((BASE / "normalized").glob(pattern)):
        if path.resolve() == excluded_path.resolve():
            continue
        rows.extend(
            json.loads(line)
            for line in path.read_text().splitlines()
            if line.strip()
        )
    return rows


def validate_candidate(candidate, as_of):
    if candidate["candidate_status"] != "reviewed_official_html":
        raise ValueError("Candidate must retain reviewed_official_html status")
    trips = candidate["trips"]
    source_ids = [trip["source"]["source_id"] for trip in trips]
    if set(source_ids) != set(EXPECTED) or len(source_ids) != len(EXPECTED):
        raise ValueError("Reviewed source-page inventory changed")

    seen_dates = defaultdict(set)
    for trip in trips:
        source = trip["source"]
        source_id = source["source_id"]
        expected = EXPECTED[source_id]
        if source["url_or_locator"] != expected["url"]:
            raise ValueError(f"Official URL changed for {source_id}")
        if source["content_hash"] != expected["hash"]:
            raise ValueError(f"Reviewed content hash changed for {source_id}")
        if source["automated_extraction_allowed"] is not False:
            raise ValueError(f"Unexpected extraction permission for {source_id}")
        dates = trip["operating_dates"]
        if dates != expected["dates"] or dates != sorted(set(dates)):
            raise ValueError(f"Reviewed td.ok date cells changed for {source_id}")
        if any(value > as_of for value in dates):
            raise ValueError(f"Candidate date exceeds manifest cutoff for {source_id}")
        if len(trip["stop_times"]) != expected["stops"]:
            raise ValueError(f"Reviewed stop count changed for {source_id}")
        if [row["stop_sequence"] for row in trip["stop_times"]] != list(
            range(1, len(trip["stop_times"]) + 1)
        ):
            raise ValueError(f"Stop sequence changed for {source_id}")
        if trip["stop_times"][0]["call_type"] != "origin" or trip["stop_times"][-1]["call_type"] != "destination":
            raise ValueError(f"Endpoint call types changed for {source_id}")
        key = (trip["service_id"], trip["public_number"])
        overlap = seen_dates[key].intersection(dates)
        if overlap:
            raise ValueError(f"Schedule variants overlap on {sorted(overlap)}")
        seen_dates[key].update(dates)

    azusa_dates = seen_dates[("azusa", "1")]
    expected_azusa = {
        date(2026, 9, day).isoformat() for day in range(18, 29)
    }
    if azusa_dates != expected_azusa:
        raise ValueError("Azusa 1 variants must partition every date through the cutoff")


def resolve_stations(candidate):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    operator = candidate["operator_name_for_station_match"]
    names = {
        row["name_snapshot"]
        for trip in candidate["trips"]
        for row in trip["stop_times"]
    }
    stations = {}
    for name in sorted(names):
        codes = {
            station[0]
            for line in package["lines"]
            if line["operator"] == operator
            for station in line["stations"]
            if station[1] == name
        }
        # Match the already reviewed main Tokyo station group. The other JR East
        # sourceCode is the distinct Keiyo platform family.
        if name == "東京":
            if "003766" not in codes:
                raise ValueError("Reviewed main Tokyo station group disappeared")
            codes = {"003766"}
        if len(codes) != 1:
            raise ValueError(
                f"Station must resolve to one sourceCode for ({operator}, {name}): {sorted(codes)}"
            )
        code = next(iter(codes))
        stations[name] = {
            "station_id": "jp.n02." + code,
            "name_snapshot": name,
            "reference_kind": "current_n02",
            "current_source_code": code,
            "rail_history_id": None,
        }
    return stations


def main():
    candidate = json.loads(CANDIDATE.read_text())
    as_of = json.loads((BASE / "manifest.json").read_text())["as_of_date"]
    validate_candidate(candidate, as_of)
    stations = resolve_stations(candidate)

    station_target = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    existing_station_rows = load_existing_rows("station-identities*.jsonl", station_target)
    existing_stations = {row["station_id"]: row for row in existing_station_rows}
    for station in stations.values():
        existing = existing_stations.get(station["station_id"])
        if existing and existing["name_snapshot"] != station["name_snapshot"]:
            raise ValueError(f"Existing station identity name conflict: {station['station_id']}")
    new_station_rows = sorted(
        (station for station in stations.values() if station["station_id"] not in existing_stations),
        key=lambda row: row["station_id"],
    )

    service_target = BASE / f"normalized/services-{SUFFIX}.jsonl"
    existing_service_rows = load_existing_rows("services*.jsonl", service_target)
    existing_services = {row["service_id"]: row for row in existing_service_rows}

    service_dates = defaultdict(set)
    service_metadata = {}
    service_sources = {}
    for reviewed_trip in candidate["trips"]:
        service_id = reviewed_trip["service_id"]
        service_dates[service_id].update(reviewed_trip["operating_dates"])
        service_metadata[service_id] = reviewed_trip["service_name"]
        earliest = min(reviewed_trip["operating_dates"])
        current_source = service_sources.get(service_id)
        if current_source is None or earliest < current_source[0]:
            service_sources[service_id] = (earliest, reviewed_trip["source"]["source_id"])

    services = []
    service_names = []
    for service_id, dates_set in sorted(service_dates.items()):
        dates = sorted(dates_set)
        canonical_name = service_metadata[service_id]
        existing = existing_services.get(service_id)
        if existing:
            if existing["canonical_name"] != canonical_name:
                raise ValueError(f"Existing service identity conflict: {service_id}")
        else:
            services.append({
                "service_id": service_id,
                "canonical_name": canonical_name,
                "service_class": "limited_express",
                "historical_generation": 1,
                "first_verified_date": dates[0],
                "last_verified_date": dates[-1],
                "jr_scope": "jr",
            })
        service_names.append({
            "service_id": service_id,
            "name": canonical_name,
            "language": "ja",
            "valid_from": dates[0],
            "valid_until": day_after(dates[-1]),
            "name_type": "display",
            "source_id": service_sources[service_id][1],
        })

    timetable_versions = []
    calendars = []
    exceptions = []
    trips = []
    stop_times = []
    fact_sources = []
    fact_completeness = []
    research_queue = []

    for reviewed_trip in candidate["trips"]:
        source = reviewed_trip["source"]
        source_id = source["source_id"]
        operating_dates = reviewed_trip["operating_dates"]
        valid_from = operating_dates[0]
        valid_until = day_after(operating_dates[-1])
        trip_id = (
            f"{SCOPE}.{reviewed_trip['service_id']}.{reviewed_trip['public_number']}."
            f"{reviewed_trip['variant_id']}.{valid_from}"
        )
        version_id = trip_id + ".version"
        calendar_id = trip_id + ".calendar"

        timetable_versions.append({
            "timetable_version_id": version_id,
            "operator_scope": SCOPE,
            "effective_from": valid_from,
            "effective_until": valid_until,
            "edition_name": (
                f"JR時刻表2026年10月号 official detail; {reviewed_trip['variant_id']}"
            ),
            "revision_type": "source_snapshot",
            "completeness": "partial",
            "source_ids": [source_id],
        })
        calendars.append({
            "calendar_id": calendar_id,
            "valid_from": valid_from,
            "valid_until": valid_until,
            "holiday_policy": "none",
            **{weekday: 0 for weekday in WEEKDAYS},
        })
        exceptions.extend({
            "calendar_id": calendar_id,
            "service_date": service_date,
            "exception_type": "add",
            "reason": "Exact calendar date marked td.ok on this schedule-variant page",
            "source_id": source_id,
        } for service_date in operating_dates)

        reviewed_stops = reviewed_trip["stop_times"]
        trips.append({
            "trip_id": trip_id,
            "timetable_version_id": version_id,
            "service_id": reviewed_trip["service_id"],
            "calendar_id": calendar_id,
            "train_number": reviewed_trip["train_number"],
            "public_number": reviewed_trip["public_number"],
            "origin_station_id": stations[reviewed_stops[0]["name_snapshot"]]["station_id"],
            "destination_station_id": stations[reviewed_stops[-1]["name_snapshot"]]["station_id"],
            "service_class": "limited_express",
            "notes": (
                "Official train-detail schedule variant with complete published passenger stops "
                "and minute clocks. Calendar contains only explicit td.ok dates. Operator "
                "segments and ordered route lines remain unknown."
            ),
        })
        for reviewed_stop in reviewed_stops:
            call_type = reviewed_stop["call_type"]
            stop_times.append({
                "trip_id": trip_id,
                "stop_sequence": reviewed_stop["stop_sequence"],
                "station_id": stations[reviewed_stop["name_snapshot"]]["station_id"],
                "arrival_time": reviewed_stop["arrival_time"],
                "departure_time": reviewed_stop["departure_time"],
                "day_offset": 0,
                "call_type": call_type,
                "pickup_allowed": 0 if call_type == "destination" else 1,
                "dropoff_allowed": 0 if call_type == "origin" else 1,
                "platform": reviewed_stop["platform"],
                "time_accuracy": "minute",
                "source_id": source_id,
            })

        completeness = {
            "identity": ("verified", "high", "The official page prints the service name and public number."),
            "train_number": ("verified", "high", "The official page prints the internal train number."),
            "operator": ("unknown", "low", "Publisher identity is not operator-segment evidence."),
            "validity_calendar": ("verified", "high", "Every emitted date is an exact td.ok calendar cell for this variant."),
            "origin_destination": ("verified", "high", "The first and last timed passenger calls are printed."),
            "stops": ("verified", "high", "The official 停車駅一覧 prints the complete passenger-stop sequence."),
            "times": ("verified", "high", "Every published passenger stop has its displayed minute arrival/departure clock."),
            "route_lines": ("unknown", "low", "No ordered physical line evidence is promoted."),
            "station_refs": ("verified", "high", "Each name resolves to one reviewed current station group under 東日本旅客鉄道."),
            "provenance": ("partial", "medium", "Official URL and SHA-256 are pinned; redistribution authorization is unresolved."),
        }
        for dimension, (status, confidence, notes) in completeness.items():
            fact_completeness.append({
                "entity_type": "trip",
                "entity_id": trip_id,
                "dimension": dimension,
                "status": status,
                "confidence": confidence,
                "notes": notes,
            })

        locator = "Official train-detail page: td.ok calendar cells and complete stop/time table"
        for field_name in [
            "identity", "train_number", "validity_calendar",
            "origin_destination", "stops", "times",
        ]:
            fact_sources.append({
                "entity_type": "trip",
                "entity_id": trip_id,
                "field_name": field_name,
                "source_id": source_id,
                "page_or_locator": locator,
                "confidence": "high",
                "verification_status": "verified",
            })
        fact_sources.extend([
            {
                "entity_type": "trip",
                "entity_id": trip_id,
                "field_name": "station_refs",
                "source_id": STATION_SOURCE_ID,
                "page_or_locator": "app/public/rail/jp-2025.json; exact (operator, station name) group match",
                "confidence": "high",
                "verification_status": "verified",
            },
            {
                "entity_type": "trip",
                "entity_id": trip_id,
                "field_name": "provenance",
                "source_id": source_id,
                "page_or_locator": "Official URL and reviewed SHA-256",
                "confidence": "medium",
                "verification_status": "partial",
            },
        ])
        queue_notes = {
            "operator": "Obtain explicit operator-segment evidence for the dated train variant.",
            "route_lines": "Obtain explicit ordered physical line identities for the dated train variant.",
            "provenance": "Resolve timetable-fact redistribution authorization.",
        }
        research_queue.extend({
            "research_id": f"{trip_id}.{dimension}",
            "entity_type": "trip",
            "entity_id": trip_id,
            "missing_dimension": dimension,
            "status": "open",
            "notes": notes,
        } for dimension, notes in queue_notes.items())

    sources = [trip["source"] for trip in candidate["trips"]]
    outputs = {
        BASE / f"sources/source-registry-{SUFFIX}.jsonl": sources,
        service_target: services,
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl": service_names,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": timetable_versions,
        station_target: new_station_rows,
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": fact_sources,
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": fact_completeness,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": research_queue,
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": trips,
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stop_times,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendars,
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exceptions,
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)

    print(
        f"Normalized {len(trips)} JR East schedule variants, {len(stop_times)} complete stop rows, "
        f"{len(exceptions)} explicit occurrences, and {len(new_station_rows)} new station identities."
    )


if __name__ == "__main__":
    main()
