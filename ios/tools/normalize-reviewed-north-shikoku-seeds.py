#!/usr/bin/env python3
"""Normalize visually reviewed JR Hokkaido limited-express announcement rows.

The source publishes selected 2026 operating dates, endpoint times, and some
complete intermediate-stop lists. Missing internal train numbers, operator
segments, routes, stops, and times stay unknown or partial. Coverage rows are
owned by the integrating task because their schema key is operator/year/dimension.
"""
from datetime import date, timedelta
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-hokkaido-hokuto-2026summer-north-shikoku-batch.json"
SUFFIX = "north-shikoku-batch"
SCOPE = "jr-hokkaido"
STATION_SOURCE_ID = "jtm-current-station-directory"
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
EXPECTED_DATE_COUNTS = {
    "hokuto-84-91": 12,
    "sarobetsu-3-4": 90,
    "kamui-9-26": 32,
    "kamui-15-36": 3,
    "niseko-bidirectional": 16,
    "furano-lavender-bidirectional": 57,
}


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(
        json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows
    ))


def day_after(value):
    return (date.fromisoformat(value) + timedelta(days=1)).isoformat()


def expand_dates(group, as_of):
    values = set(group["single_dates"])
    for first, last in group["date_ranges"]:
        current = date.fromisoformat(first)
        ending = date.fromisoformat(last)
        if current > ending:
            raise ValueError(f"Backward date range in {group['group_id']}: {first}/{last}")
        while current <= ending:
            values.add(current.isoformat())
            current += timedelta(days=1)
    dates = sorted(value for value in values if value <= as_of)
    expected = EXPECTED_DATE_COUNTS[group["group_id"]]
    if len(dates) != expected:
        raise ValueError(
            f"Reviewed date expansion changed for {group['group_id']}: "
            f"expected {expected}, got {len(dates)}"
        )
    return dates


def existing_station_ids(excluded_path):
    found = set()
    for path in sorted((BASE / "normalized").glob("station-identities*.jsonl")):
        if path.resolve() == excluded_path.resolve():
            continue
        for line in path.read_text().splitlines():
            if line.strip():
                found.add(json.loads(line)["station_id"])
    return found


def main():
    candidate = json.loads(CANDIDATE.read_text())
    as_of = json.loads((BASE / "manifest.json").read_text())["as_of_date"]
    source = candidate["source"]
    source_id = source["source_id"]
    groups = candidate["service_groups"]

    if not source["url_or_locator"].startswith(
        "https://www.jrhokkaido.co.jp/CM/Info/press/pdf/"
    ):
        raise ValueError("Candidate must retain the reviewed official JR Hokkaido PDF URL")
    if {group["group_id"] for group in groups} != set(EXPECTED_DATE_COUNTS):
        raise ValueError("Reviewed group inventory changed")
    if any(group["service_id"] == "kamui" and group["emit_service"] for group in groups):
        raise ValueError("Kamui must reuse the existing service row")

    dates_by_group = {group["group_id"]: expand_dates(group, as_of) for group in groups}
    niseko = next(group for group in groups if group["group_id"] == "niseko-bidirectional")
    niseko_stops = {trip["direction"]: trip["intermediate_stops"] for trip in niseko["trips"]}
    if (
        "大沼公園" in niseko_stops["sapporo_to_hakodate"]
        or "大沼公園" not in niseko_stops["hakodate_to_sapporo"]
    ):
        raise ValueError("Niseko direction-specific Onuma-Koen stop review changed")

    station_names = set()
    for group in groups:
        for trip in group["trips"]:
            station_names.update([trip["origin"], trip["destination"]])
            station_names.update(trip["intermediate_stops"] or [])

    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    operator = candidate["operator_name_for_station_match"]
    stations = {}
    for name in sorted(station_names):
        codes = {
            station[0]
            for line in package["lines"]
            if line["operator"] == operator
            for station in line["stations"]
            if station[1] == name
        }
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

    target_station_path = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    already_defined = existing_station_ids(target_station_path)
    new_station_rows = sorted(
        (station for station in stations.values() if station["station_id"] not in already_defined),
        key=lambda row: row["station_id"],
    )

    service_dates = {}
    service_metadata = {}
    for group in groups:
        service_dates.setdefault(group["service_id"], set()).update(
            dates_by_group[group["group_id"]]
        )
        service_metadata[group["service_id"]] = group

    services = []
    service_names = []
    for service_id, dates_set in sorted(service_dates.items()):
        group = service_metadata[service_id]
        dates = sorted(dates_set)
        if group["emit_service"]:
            services.append({
                "service_id": service_id,
                "canonical_name": group["service_name"],
                "service_class": "limited_express",
                "historical_generation": 1,
                "first_verified_date": dates[0],
                "last_verified_date": dates[-1],
                "jr_scope": "jr",
            })
        service_names.append({
            "service_id": service_id,
            "name": group["service_name"],
            "language": "ja",
            "valid_from": dates[0],
            "valid_until": day_after(dates[-1]),
            "name_type": "display",
            "source_id": source_id,
        })

    timetable_versions = []
    calendars = []
    exceptions = []
    trips = []
    stop_times = []
    fact_sources = []
    fact_completeness = []
    research_queue = []

    for group in groups:
        operating_dates = dates_by_group[group["group_id"]]
        valid_from = operating_dates[0]
        valid_until = day_after(operating_dates[-1])
        for reviewed_trip in group["trips"]:
            trip_id = (
                f"{SCOPE}.{group['service_id']}."
                f"{reviewed_trip['trip_id_component']}.{valid_from}"
            )
            version_id = trip_id + ".version"
            calendar_id = trip_id + ".calendar"
            timetable_versions.append({
                "timetable_version_id": version_id,
                "operator_scope": SCOPE,
                "effective_from": valid_from,
                "effective_until": valid_until,
                "publication_date": source["publication_date"],
                "edition_name": f"JR Hokkaido 2026 summer announcement; {group['group_id']}",
                "revision_type": "planned_exception",
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
                "reason": (
                    f"PDF p.{group['page']} operating-date cell for {group['group_id']}; "
                    f"source text: {group['date_cell_text']}"
                ),
                "source_id": source_id,
            } for service_date in operating_dates)

            intermediate = reviewed_trip["intermediate_stops"]
            stops_complete = intermediate is not None
            ordered_names = [
                reviewed_trip["origin"],
                *(intermediate or []),
                reviewed_trip["destination"],
            ]
            trip = {
                "trip_id": trip_id,
                "timetable_version_id": version_id,
                "service_id": group["service_id"],
                "calendar_id": calendar_id,
                "train_number": None,
                "public_number": reviewed_trip["public_number"],
                "origin_station_id": stations[ordered_names[0]]["station_id"],
                "destination_station_id": stations[ordered_names[-1]]["station_id"],
                "service_class": "limited_express",
                "notes": (
                    "Official announcement; endpoint times only. "
                    + (
                        "The complete printed passenger-stop list is recorded. "
                        if stops_complete
                        else "Intermediate passenger stops are not published and are omitted. "
                    )
                    + "Internal train number, operator segments and route lines remain unknown."
                ),
            }
            if reviewed_trip["direction"] is not None:
                trip["direction"] = reviewed_trip["direction"]
            trips.append(trip)

            for sequence, name in enumerate(ordered_names, start=1):
                is_origin = sequence == 1
                is_destination = sequence == len(ordered_names)
                stop_times.append({
                    "trip_id": trip_id,
                    "stop_sequence": sequence,
                    "station_id": stations[name]["station_id"],
                    "arrival_time": reviewed_trip["arrival_time"] if is_destination else None,
                    "departure_time": reviewed_trip["departure_time"] if is_origin else None,
                    "day_offset": 0,
                    "call_type": "origin" if is_origin else "destination" if is_destination else "passenger_stop",
                    "pickup_allowed": 0 if is_destination else 1,
                    "dropoff_allowed": 0 if is_origin else 1,
                    "time_accuracy": "minute" if is_origin or is_destination else "unknown",
                    "source_id": source_id,
                })

            completeness = {
                "identity": ("verified", "high", "The reviewed row prints the service identity and any public number."),
                "train_number": ("unknown", "low", "No internal train number is published; unnumbered services also keep public_number null."),
                "operator": ("unknown", "low", "Publisher identity is not promoted as operator-segment evidence."),
                "validity_calendar": ("verified", "high", group["date_cell_interpretation"]),
                "origin_destination": ("verified", "high", "Both endpoints are printed in the row."),
                "stops": (
                    "verified" if stops_complete else "partial",
                    "high",
                    "The complete intermediate-stop line is printed."
                    if stops_complete
                    else "The table publishes endpoints but no intermediate-stop list.",
                ),
                "times": ("partial", "high", "Only origin departure and destination arrival are printed."),
                "route_lines": ("unknown", "low", "No ordered railway-line evidence is promoted."),
                "station_refs": ("verified", "high", "Every recorded station uniquely matches one sourceCode under 北海道旅客鉄道."),
                "provenance": ("partial", "medium", "Official URL and reviewed content hash are recorded; redistribution authorization is unknown."),
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

            locator = reviewed_trip["source_locator"]
            for field_name in ["identity", "validity_calendar", "origin_destination"]:
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
                    "field_name": "stops",
                    "source_id": source_id,
                    "page_or_locator": locator,
                    "confidence": "high",
                    "verification_status": "verified" if stops_complete else "partial",
                },
                {
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": "times",
                    "source_id": source_id,
                    "page_or_locator": locator + "; endpoint times only",
                    "confidence": "high",
                    "verification_status": "partial",
                },
                {
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": "station_refs",
                    "source_id": STATION_SOURCE_ID,
                    "page_or_locator": "app/public/rail/jp-2025.json; exact (operator, station name) sourceCode match",
                    "confidence": "high",
                    "verification_status": "verified",
                },
                {
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": "provenance",
                    "source_id": source_id,
                    "page_or_locator": "Official PDF URL, publication date and reviewed SHA-256",
                    "confidence": "medium",
                    "verification_status": "partial",
                },
            ])

            queue_notes = {
                "train_number": "Obtain an official internal train-number source; do not invent one from public numbering or direction.",
                "operator": "Obtain explicit operator-segment evidence.",
                "times": "Obtain arrival/departure times for every passenger stop.",
                "route_lines": "Obtain explicit ordered line references valid for every listed operating date.",
                "provenance": "Resolve timetable fact redistribution authorization.",
            }
            if not stops_complete:
                queue_notes["stops"] = "Obtain the complete intermediate passenger-stop list."
            research_queue.extend({
                "research_id": f"{trip_id}.{dimension}",
                "entity_type": "trip",
                "entity_id": trip_id,
                "missing_dimension": dimension,
                "status": "open",
                "notes": notes,
            } for dimension, notes in queue_notes.items())

    outputs = {
        BASE / f"sources/source-registry-{SUFFIX}.jsonl": [source],
        BASE / f"normalized/services-{SUFFIX}.jsonl": services,
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl": service_names,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": timetable_versions,
        target_station_path: new_station_rows,
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
        f"Normalized {len(trips)} limited-express templates, {len(stop_times)} recorded stops, "
        f"{len(exceptions)} explicit occurrences, and {len(new_station_rows)} new station identities."
    )
    print("Manifest-selected outputs:")
    for path, rows in outputs.items():
        print(f"  {path.relative_to(BASE)} ({len(rows)} rows)")


if __name__ == "__main__":
    main()
