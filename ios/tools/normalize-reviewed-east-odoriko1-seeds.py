#!/usr/bin/env python3
"""Normalize source-pinned Odoriko 1 branches for 2026-09-29/30.

The official table has separate 3021M and 4021M columns. The 4021M column is
blank before the Atami split, so those shared-segment clocks and platforms stay
null even though the printed coupling statement and station rows establish the
Tokyo origin and shared stop sequence.
"""
from datetime import date, timedelta
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-east-odoriko1-20260929-30.json"
SUFFIX = "east-odoriko1-20260929-30"
SCOPE = "jr-east"
SOURCE_ID = "jr-east-odoriko1-20260929-30"
SOURCE_URL = "https://timetables.jreast.co.jp/2610/train/095/098901.html"
SOURCE_HASH = "sha256:35f39d356ca9f8e1cb1493a86b95235387c2f05128fa83c59658895493027c66"
STATION_SOURCE_ID = "jtm-current-station-directory"
OPERATING_DATES = ["2026-09-29", "2026-09-30"]
WEEKDAYS = [
    "monday", "tuesday", "wednesday", "thursday",
    "friday", "saturday", "sunday",
]
EXPECTED_STATION_CODES = {
    "東京": "003766",
    "品川": "004095",
    "川崎": "004432",
    "横浜": "004633",
    "大船": "004961",
    "小田原": "005215",
    "湯河原": "005541",
    "熱海": "005685",
    "伊東": "006117",
    "伊豆高原": "006370",
    "伊豆熱川": "006557",
    "伊豆稲取": "006730",
    "河津": "006846",
    "伊豆急下田": "007218",
    "三島": "005601",
    "三島田町": "005642",
    "大場": "005718",
    "伊豆長岡": "005856",
    "大仁": "006036",
    "修善寺": "006101",
}
EXPECTED_BRANCHES = {
    "3021M": {
        "branch_id": "izukyu-shimoda",
        "variant_id": "izukyu-shimoda-requested-dates",
        "times_completeness": "verified",
        "names": [
            "東京", "品川", "川崎", "横浜", "大船", "小田原", "湯河原", "熱海",
            "伊東", "伊豆高原", "伊豆熱川", "伊豆稲取", "河津", "伊豆急下田",
        ],
    },
    "4021M": {
        "branch_id": "shuzenji",
        "variant_id": "shuzenji-requested-dates",
        "times_completeness": "partial",
        "names": [
            "東京", "品川", "川崎", "横浜", "大船", "小田原", "湯河原", "熱海",
            "三島", "三島田町", "大場", "伊豆長岡", "大仁", "修善寺",
        ],
    },
}


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(
        json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows
    ))


def day_after(value):
    return (date.fromisoformat(value) + timedelta(days=1)).isoformat()


def load_normalized_rows(pattern, excluded_path):
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
    source = candidate["source"]
    if source["source_id"] != SOURCE_ID:
        raise ValueError("Reviewed source ID changed")
    if source["url_or_locator"] != SOURCE_URL:
        raise ValueError("Official Odoriko 1 URL changed")
    if source["content_hash"] != SOURCE_HASH:
        raise ValueError("Reviewed Odoriko 1 content hash changed")
    if source["automated_extraction_allowed"] is not False:
        raise ValueError("Unexpected extraction permission")

    trips = candidate["trips"]
    by_number = {trip["train_number"]: trip for trip in trips}
    if set(by_number) != set(EXPECTED_BRANCHES) or len(trips) != 2:
        raise ValueError("Expected exactly the reviewed 3021M and 4021M branches")
    for train_number, expected in EXPECTED_BRANCHES.items():
        trip = by_number[train_number]
        if trip["operating_dates"] != OPERATING_DATES:
            raise ValueError(f"Reviewed td.ok dates changed for {train_number}")
        if any(value > as_of for value in trip["operating_dates"]):
            raise ValueError(f"Candidate date exceeds manifest cutoff for {train_number}")
        if (
            trip["service_id"], trip["service_name"], trip["public_number"],
            trip["branch_id"], trip["variant_id"], trip["times_completeness"],
        ) != (
            "odoriko", "踊り子", "1", expected["branch_id"],
            expected["variant_id"], expected["times_completeness"],
        ):
            raise ValueError(f"Reviewed branch identity changed for {train_number}")
        stops = trip["stop_times"]
        if [row["name_snapshot"] for row in stops] != expected["names"]:
            raise ValueError(f"Reviewed stop order changed for {train_number}")
        if [row["stop_sequence"] for row in stops] != list(range(1, 15)):
            raise ValueError(f"Stop sequence changed for {train_number}")
        if stops[0]["call_type"] != "origin" or stops[-1]["call_type"] != "destination":
            raise ValueError(f"Endpoint call types changed for {train_number}")

    main_stops = by_number["3021M"]["stop_times"]
    if any(row["arrival_time"] is None and row["departure_time"] is None for row in main_stops):
        raise ValueError("3021M must retain a printed clock at every passenger call")
    if (main_stops[0]["departure_time"], main_stops[-1]["arrival_time"]) != ("09:00", "11:39"):
        raise ValueError("3021M endpoint clocks changed")

    branch_stops = by_number["4021M"]["stop_times"]
    for row in branch_stops[:7]:
        if any(row[key] is not None for key in ("arrival_time", "departure_time", "platform")):
            raise ValueError("Unprinted 4021M pre-Atami clocks/platforms must stay null")
        if row.get("time_evidence") != "not_printed_in_4021M_column":
            raise ValueError("4021M unknown-time provenance changed")
    atami = branch_stops[7]
    if (atami["arrival_time"], atami["departure_time"], atami["platform"]) != (None, "10:25", "２"):
        raise ValueError("4021M Atami split facts changed")
    if atami.get("time_evidence") != "departure_only_printed_after_split":
        raise ValueError("4021M Atami evidence marker changed")
    if branch_stops[-1]["arrival_time"] != "11:08":
        raise ValueError("4021M Shuzenji arrival changed")


def resolve_stations(candidate):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    available = {
        (station[0], station[1])
        for line in package["lines"]
        for station in line["stations"]
    }
    candidate_names = {
        row["name_snapshot"]
        for trip in candidate["trips"]
        for row in trip["stop_times"]
    }
    if candidate_names != set(EXPECTED_STATION_CODES):
        raise ValueError("Reviewed Odoriko station inventory changed")
    stations = {}
    for name, code in EXPECTED_STATION_CODES.items():
        if (code, name) not in available:
            raise ValueError(f"Reviewed current station group disappeared: ({code}, {name})")
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
    source = candidate["source"]

    source_target = BASE / f"sources/source-registry-{SUFFIX}.jsonl"
    for path in sorted((BASE / "sources").glob("source-registry*.jsonl")):
        if path.resolve() == source_target.resolve():
            continue
        for line in path.read_text().splitlines():
            if line.strip() and json.loads(line)["source_id"] == SOURCE_ID:
                raise ValueError(f"Source ID collision outside this batch: {path}")

    station_target = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    existing_station_rows = load_normalized_rows("station-identities*.jsonl", station_target)
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
    existing_services = {
        row["service_id"]: row
        for row in load_normalized_rows("services*.jsonl", service_target)
    }
    existing_service = existing_services.get("odoriko")
    if existing_service and existing_service["canonical_name"] != "踊り子":
        raise ValueError("Existing Odoriko service identity conflict")
    services = [] if existing_service else [{
        "service_id": "odoriko",
        "canonical_name": "踊り子",
        "service_class": "limited_express",
        "historical_generation": 1,
        "first_verified_date": OPERATING_DATES[0],
        "last_verified_date": OPERATING_DATES[-1],
        "jr_scope": "through_jr",
    }]

    trip_target = BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl"
    existing_trip_ids = {
        row["trip_id"]
        for row in load_normalized_rows("trips/**/*.jsonl", trip_target)
    }
    valid_from = OPERATING_DATES[0]
    valid_until = day_after(OPERATING_DATES[-1])
    trip_ids = {
        "3021M": f"{SCOPE}.odoriko.1.3021m-izukyu-shimoda.{valid_from}",
        "4021M": f"{SCOPE}.odoriko.1.4021m-shuzenji.{valid_from}",
    }
    collisions = set(trip_ids.values()) & existing_trip_ids
    if collisions:
        raise ValueError(f"Trip ID collision outside this batch: {sorted(collisions)}")

    service_names = [{
        "service_id": "odoriko",
        "name": "踊り子",
        "language": "ja",
        "valid_from": valid_from,
        "valid_until": valid_until,
        "name_type": "display",
        "source_id": SOURCE_ID,
    }]
    timetable_versions = []
    calendars = []
    exceptions = []
    trips = []
    stop_times = []
    fact_sources = []
    fact_completeness = []
    research_queue = []
    operation_group_id = f"{SCOPE}.odoriko.1.coupled.{valid_from}"

    for reviewed_trip in candidate["trips"]:
        train_number = reviewed_trip["train_number"]
        trip_id = trip_ids[train_number]
        version_id = trip_id + ".version"
        calendar_id = trip_id + ".calendar"
        timetable_versions.append({
            "timetable_version_id": version_id,
            "operator_scope": SCOPE,
            "effective_from": valid_from,
            "effective_until": valid_until,
            "edition_name": f"JR時刻表2026年10月号 official detail; {train_number} branch",
            "revision_type": "source_snapshot",
            "completeness": "partial",
            "source_ids": [SOURCE_ID],
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
            "reason": "Exact calendar date marked td.ok on the official two-branch page",
            "source_id": SOURCE_ID,
        } for service_date in OPERATING_DATES)

        reviewed_stops = reviewed_trip["stop_times"]
        trips.append({
            "trip_id": trip_id,
            "timetable_version_id": version_id,
            "service_id": "odoriko",
            "calendar_id": calendar_id,
            "train_number": train_number,
            "public_number": "1",
            "origin_station_id": stations["東京"]["station_id"],
            "destination_station_id": stations[reviewed_stops[-1]["name_snapshot"]]["station_id"],
            "service_class": "limited_express",
            "operation_group_id": operation_group_id,
            "notes": (
                "Official two-column Odoriko 1 table. Coupled with the other branch from Tokyo "
                "through Atami and split there. For 4021M, blank shared-segment clocks and "
                "platforms remain null; no 3021M values are copied into that branch."
            ),
        })
        for reviewed_stop in reviewed_stops:
            call_type = reviewed_stop["call_type"]
            has_clock = reviewed_stop["arrival_time"] is not None or reviewed_stop["departure_time"] is not None
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
                "time_accuracy": "minute" if has_clock else "unknown",
                "source_id": SOURCE_ID,
            })

        time_status = reviewed_trip["times_completeness"]
        time_notes = (
            "Every displayed 3021M passenger call has its printed minute clock."
            if train_number == "3021M"
            else "The 4021M column does not print Tokyo-through-Yugawara clocks or Atami arrival; those values remain null. Atami departure and all post-split clocks are printed."
        )
        completeness = {
            "identity": ("verified", "high", "The official page prints the service name and public number in both branch columns."),
            "train_number": ("verified", "high", f"The official page prints branch train number {train_number}."),
            "operator": ("unknown", "low", "Publisher identity and coupling text do not establish operator segments."),
            "validity_calendar": ("verified", "high", "Both emitted dates are exact td.ok cells on the official branch page."),
            "origin_destination": ("verified", "high", "The page heading and table establish the branch endpoints."),
            "stops": ("verified", "high", "The two-column table and coupling statement establish the complete branch stop order."),
            "times": (time_status, "high", time_notes),
            "route_lines": ("unknown", "low", "No ordered physical-line identities are promoted."),
            "station_refs": ("verified", "high", "Every printed station name resolves to its reviewed current N02 group."),
            "provenance": ("partial", "medium", "Official URL and SHA-256 are pinned; redistribution authorization is unresolved."),
        }
        fact_completeness.extend({
            "entity_type": "trip",
            "entity_id": trip_id,
            "dimension": dimension,
            "status": status,
            "confidence": confidence,
            "notes": notes,
        } for dimension, (status, confidence, notes) in completeness.items())

        verified_fields = [
            "identity", "train_number", "validity_calendar", "origin_destination", "stops",
        ]
        fact_sources.extend({
            "entity_type": "trip",
            "entity_id": trip_id,
            "field_name": field_name,
            "source_id": SOURCE_ID,
            "page_or_locator": "Official two-column train-detail page and td.ok September cells",
            "confidence": "high",
            "verification_status": "verified",
        } for field_name in verified_fields)
        fact_sources.extend([
            {
                "entity_type": "trip",
                "entity_id": trip_id,
                "field_name": "times",
                "source_id": SOURCE_ID,
                "page_or_locator": (
                    f"Official {train_number} table column; blank cells are retained as null"
                ),
                "confidence": "high",
                "verification_status": time_status,
            },
            {
                "entity_type": "trip",
                "entity_id": trip_id,
                "field_name": "coupling",
                "source_id": SOURCE_ID,
                "page_or_locator": "併結運転 row: 東京－熱海; split marker at 熱海",
                "confidence": "high",
                "verification_status": "verified",
            },
            {
                "entity_type": "trip",
                "entity_id": trip_id,
                "field_name": "station_refs",
                "source_id": STATION_SOURCE_ID,
                "page_or_locator": "app/public/rail/jp-2025.json; exact current sourceCode/name group matches",
                "confidence": "high",
                "verification_status": "verified",
            },
            {
                "entity_type": "trip",
                "entity_id": trip_id,
                "field_name": "provenance",
                "source_id": SOURCE_ID,
                "page_or_locator": "Official URL and reviewed SHA-256",
                "confidence": "medium",
                "verification_status": "partial",
            },
        ])
        gaps = {
            "operator": "Obtain train-specific operator segments across the through-service boundaries.",
            "route_lines": "Obtain explicit ordered physical-line identities for this branch.",
            "provenance": "Resolve timetable-fact redistribution authorization.",
        }
        if train_number == "4021M":
            gaps["times"] = "Obtain a source that separately prints 4021M clocks and platforms from Tokyo through the Atami arrival."
        research_queue.extend({
            "research_id": f"{trip_id}.{dimension}",
            "entity_type": "trip",
            "entity_id": trip_id,
            "missing_dimension": dimension,
            "status": "open",
            "notes": notes,
        } for dimension, notes in gaps.items())

    trip_relations = [
        {
            "trip_id": trip_ids["3021M"],
            "related_trip_id": trip_ids["4021M"],
            "relation_type": "couples_with",
            "from_sequence": 1,
            "to_sequence": 8,
            "source_id": SOURCE_ID,
        },
        {
            "trip_id": trip_ids["4021M"],
            "related_trip_id": trip_ids["3021M"],
            "relation_type": "couples_with",
            "from_sequence": 1,
            "to_sequence": 8,
            "source_id": SOURCE_ID,
        },
    ]

    outputs = {
        source_target: [source],
        service_target: services,
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl": service_names,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": timetable_versions,
        station_target: new_station_rows,
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": fact_sources,
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": fact_completeness,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": research_queue,
        trip_target: trips,
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stop_times,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendars,
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exceptions,
        BASE / f"normalized/trip-relations/{SUFFIX}/seeds.jsonl": trip_relations,
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)

    unknown_4021m_clocks = sum(
        row["arrival_time"] is None and row["departure_time"] is None
        for row in candidate["trips"][1]["stop_times"][:8]
    )
    print(
        f"Normalized 2 Odoriko 1 branches, {len(stop_times)} stop rows, "
        f"{len(exceptions)} exact occurrences, {len(trip_relations)} coupling relations, "
        f"and {unknown_4021m_clocks} fully unknown 4021M shared-segment clocks."
    )


if __name__ == "__main__":
    main()
