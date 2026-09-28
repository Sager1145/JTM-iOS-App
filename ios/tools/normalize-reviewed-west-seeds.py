#!/usr/bin/env python3
"""Normalize the visually reviewed JR West summer 2026 Kinan timetables."""

from collections import defaultdict
from datetime import date, timedelta
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE_PATH = BASE / "candidates/jr-west-ginga-kumano-2026-summer-west-batch.json"
SOURCE_REGISTRY_PATH = BASE / "sources/source-registry-west-batch.jsonl"
STATION_OUTPUT_PATH = BASE / "normalized/station-identities-west-batch.jsonl"
STATION_DIRECTORY_SOURCE = "jtm-current-station-directory"
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows)
    path.write_text(payload, encoding="utf-8")


def existing_rows(pattern, excluded_path=None):
    for path in sorted(BASE.glob(pattern)):
        if not path.is_file() or path == excluded_path:
            continue
        for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if raw.strip():
                yield path, line_number, json.loads(raw)


def resolve_stations(stops):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    station_rows = {}
    for stop in stops:
        name = stop["station_name"]
        codes = {
            station[0]
            for line in package["lines"]
            if line["operator"] == "西日本旅客鉄道"
            for station in line["stations"]
            if station[1] == name
        }
        if len(codes) != 1:
            raise ValueError(f"Ambiguous or missing JR West station identity for {name}: {sorted(codes)}")
        code = codes.pop()
        station_rows[name] = {
            "station_id": "jp.n02." + code,
            "name_snapshot": name,
            "reference_kind": "current_n02",
            "current_source_code": code,
        }

    existing_by_id = {}
    for path, line_number, row in existing_rows("normalized/station-identities*.jsonl", STATION_OUTPUT_PATH):
        existing_by_id.setdefault(row["station_id"], []).append((path, line_number, row))
    for row in station_rows.values():
        matches = existing_by_id.get(row["station_id"], [])
        for path, line_number, existing in matches:
            expected = {key: row[key] for key in ("station_id", "name_snapshot", "reference_kind", "current_source_code")}
            actual = {key: existing.get(key) for key in expected}
            if actual != expected:
                raise ValueError(f"Conflicting station identity at {path}:{line_number}: {actual} != {expected}")

    new_rows = [row for row in station_rows.values() if row["station_id"] not in existing_by_id]
    return station_rows, sorted(new_rows, key=lambda row: row["station_id"])


def ensure_unique_service(service):
    collisions = []
    for path, line_number, row in existing_rows("normalized/services*.jsonl"):
        if path.name == "services-west-batch.jsonl":
            continue
        if row["service_id"] == service["service_id"]:
            collisions.append(f"{path}:{line_number}")
    if collisions:
        raise ValueError(f"Service id {service['service_id']} already exists at {collisions}")


def main():
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    as_of = date.fromisoformat(manifest["as_of_date"])
    candidate = json.loads(CANDIDATE_PATH.read_text(encoding="utf-8"))
    if candidate.get("candidate_status") != "visually_reviewed":
        raise ValueError("Candidate must be visually reviewed before normalization")

    source = candidate["source"]
    service = candidate["service"]
    trip_sources = [candidate["trip"], candidate["night_trip"]]
    ensure_unique_service(service)

    days_by_key = {}
    excluded_dates = []
    for trip_source in trip_sources:
        source_dates = [date.fromisoformat(value) for value in trip_source["operating_dates"]]
        days_by_key[trip_source["template_key"]] = sorted(day for day in source_dates if day <= as_of)
        excluded_dates.extend(day.isoformat() for day in source_dates if day > as_of)
    if any(not days for days in days_by_key.values()):
        raise ValueError("Each source trip must have an operating date within manifest as_of_date")
    excluded_dates = sorted(set(excluded_dates))
    normalized_days = sorted(day for days in days_by_key.values() for day in days)
    service_valid_from = normalized_days[0].isoformat()
    service_valid_until = (normalized_days[-1] + timedelta(days=1)).isoformat()

    daytime_source = candidate["trip"]
    daytime_days = days_by_key[daytime_source["template_key"]]
    holiday_days = {
        date.fromisoformat(value) for value in daytime_source["holiday_timetable_dates"]
        if date.fromisoformat(value) <= as_of
    }
    if not holiday_days.issubset(set(daytime_days)):
        raise ValueError("Holiday timetable dates must be a subset of normalized operating dates")

    station_rows, new_station_rows = resolve_stations(
        [stop for trip_source in trip_sources for stop in trip_source["stops"]])
    source_registry_ids = {
        row["source_id"]
        for _, _, row in existing_rows("sources/source-registry*.jsonl", SOURCE_REGISTRY_PATH)
    }
    if STATION_DIRECTORY_SOURCE not in source_registry_ids:
        raise ValueError(f"Missing canonical station directory source {STATION_DIRECTORY_SOURCE}")

    data = defaultdict(list)
    data["services"].append({
        **service,
        "first_verified_date": service_valid_from,
        "last_verified_date": normalized_days[-1].isoformat(),
    })
    data["service-name-periods"].append({
        "service_id": service["service_id"],
        "name": service["canonical_name"],
        "language": "ja",
        "valid_from": service_valid_from,
        "valid_until": service_valid_until,
        "name_type": "canonical",
        "source_id": source["source_id"],
    })
    trip_ids = []
    for trip_source in trip_sources:
        days = days_by_key[trip_source["template_key"]]
        trip_id = f"jr-west.{service['service_id']}.{trip_source['template_key']}.{days[0].isoformat()}"
        trip_ids.append(trip_id)
        version_id = trip_id + ".version"
        calendar_id = trip_id + ".calendar"
        valid_from = days[0].isoformat()
        valid_until = (days[-1] + timedelta(days=1)).isoformat()
        data["timetable-versions"].append({
            "timetable_version_id": version_id,
            "operator_scope": "jr-west",
            "effective_from": valid_from,
            "effective_until": valid_until,
            "edition_name": f"2026 summer WEST EXPRESS Ginga Kinan {trip_source['template_key']} announced dates",
            "revision_type": "planned_exception",
            "publication_date": source["publication_date"],
            "completeness": "partial",
            "source_ids": [source["source_id"]],
        })
        data["calendars"].append({
            "calendar_id": calendar_id,
            "valid_from": valid_from,
            "valid_until": valid_until,
            "holiday_policy": "none",
            **{weekday: 0 for weekday in WEEKDAYS},
        })
        data["calendar-exceptions"].extend({
            "calendar_id": calendar_id,
            "service_date": day.isoformat(),
            "exception_type": "add",
            "source_id": source["source_id"],
            "reason": "Colored origin-date cell in PDF p.1 section 2; capped at manifest as_of_date",
        } for day in days)

        trip_stop_rows = []
        sequence_by_name = {}
        for sequence, stop in enumerate(trip_source["stops"], 1):
            station = station_rows[stop["station_name"]]
            sequence_by_name[stop["station_name"]] = sequence
            row = {
                "trip_id": trip_id,
                "stop_sequence": sequence,
                "station_id": station["station_id"],
                "arrival_time": stop["arrival_time"],
                "departure_time": stop["departure_time"],
                "day_offset": 0,
                "call_type": stop["call_type"],
                "pickup_allowed": stop["pickup_allowed"],
                "dropoff_allowed": stop["dropoff_allowed"],
                "time_accuracy": "minute",
                "source_id": source["source_id"],
            }
            if stop.get("arrival_day_offset") is not None:
                row["arrival_day_offset"] = stop["arrival_day_offset"]
            if stop.get("departure_day_offset") is not None:
                row["departure_day_offset"] = stop["departure_day_offset"]
            trip_stop_rows.append(row)
        data["stop-times"].extend(trip_stop_rows)
        data["trips"].append({
            "trip_id": trip_id,
            "timetable_version_id": version_id,
            "service_id": service["service_id"],
            "calendar_id": calendar_id,
            "train_number": None,
            "public_number": None,
            "origin_station_id": trip_stop_rows[0]["station_id"],
            "destination_station_id": trip_stop_rows[-1]["station_id"],
            "direction": trip_source["direction_label"],
            "service_class": service["service_class"],
            "notes": (
                "Official directional stop/time table. Internal/public train numbers, ordered route identities "
                "and operator-segment boundaries are not printed."
            ),
        })
        if trip_source is daytime_source:
            for day in sorted(holiday_days):
                for station_name, overrides in trip_source["holiday_overrides"].items():
                    data["trip-stop-time-overrides"].append({
                        "trip_id": trip_id,
                        "service_date": day.isoformat(),
                        "stop_sequence": sequence_by_name[station_name],
                        "source_id": source["source_id"],
                        **overrides,
                    })

    statuses = {
        "identity": ("verified", "high", "Official title and section 1 identify the named limited express."),
        "train_number": ("unknown", "low", "The official PDF prints no public or internal train number."),
        "operator": ("unknown", "low", "The PDF does not print an ordered operator-boundary table."),
        "validity_calendar": ("verified", "high", "Only peach origin-date cells through manifest as_of_date are normalized."),
        "origin_destination": ("verified", "high", "Section 1 and each directional table state their endpoints."),
        "stops": ("verified", "high", "Section 3 is explicitly headed stopping stations and times."),
        "times": ("verified", "high", "Source clocks remain verbatim; independent day offsets model the overnight table."),
        "route_lines": ("unknown", "low", "The schematic map and station order do not establish dated physical line identities."),
        "station_refs": ("verified", "high", "Each source name resolves to one JR West sourceCode in the shipped directory."),
        "provenance": ("partial", "high", "Official PDF and content hash are recorded; no redistribution grant was identified."),
    }
    source_locators = {
        "identity": "PDF p.1 title and section 1",
        "operator": "PDF p.1 publisher and section 1; no segment boundary table",
        "validity_calendar": "PDF p.1 section 2, peach origin-date cells",
        "origin_destination": "PDF p.1 sections 1 and 3",
        "stops": "PDF p.1 section 3 directional tables and purchase restriction notes",
        "times": "PDF p.1 section 3 directional tables; parenthesized daytime holiday clocks",
        "station_refs": "Shipped current station directory; exact JR West name/code resolution",
        "provenance": "Official PDF URL and SHA-256 reviewed 2026-09-28",
    }
    for trip_id in trip_ids:
        for dimension, (status, confidence, notes) in statuses.items():
            data["fact-completeness"].append({
                "entity_type": "trip",
                "entity_id": trip_id,
                "dimension": dimension,
                "status": status,
                "confidence": confidence,
                "notes": notes,
            })
            if dimension in source_locators:
                data["fact-sources"].append({
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": dimension,
                    "source_id": STATION_DIRECTORY_SOURCE if dimension == "station_refs" else source["source_id"],
                    "page_or_locator": source_locators[dimension],
                    "confidence": confidence,
                    "verification_status": status,
                })

    research = {
        "train_number": ("open", "Obtain an official consist/working timetable that prints the public and internal train numbers."),
        "operator": ("open", "Obtain source evidence for the ordered operator boundary, if any."),
        "route_lines": ("open", "Obtain dated direct line identities for every adjacent stop pair; do not infer them from the schematic map."),
        "provenance": ("license_blocked", "No redistribution or automated-extraction grant was found; the PDF remains verification-only."),
    }
    for trip_id in trip_ids:
        for dimension, (status, notes) in research.items():
            data["research-queue"].append({
                "research_id": f"{trip_id}.{dimension}",
                "entity_type": "trip",
                "entity_id": trip_id,
                "missing_dimension": dimension,
                "status": status,
                "notes": notes,
            })

    coverage_counts = {
        "inventory": len(trip_ids),
        "train_number": 0,
        "calendar": len(normalized_days),
        "stops": len(data["stop-times"]),
        "times": len(data["stop-times"]),
        "route_lines": 0,
        "station_refs": len(data["stop-times"]),
        "provenance": len(trip_ids),
    }
    coverage_notes = {
        "inventory": "2 directional WEST EXPRESS Ginga Kinan templates only; not a JR West company-wide or full-year inventory.",
        "train_number": "0 numbered templates; the official PDF prints no public or internal train number.",
        "calendar": f"{len(normalized_days)} explicit directional origin-date occurrences through {manifest['as_of_date']}; excluded later source dates: {excluded_dates}.",
        "stops": f"{len(data['stop-times'])} ordered stop rows across 2 directional templates; no other JR West service is covered.",
        "times": f"{len(data['stop-times'])} stop rows with printed minute clocks, plus {len(data['trip-stop-time-overrides'])} date/stop override rows.",
        "route_lines": "0 route-line rows; the PDF schematic map is not promoted to physical line identity evidence.",
        "station_refs": f"{len(data['stop-times'])} stop references validated against unique current JR West sourceCodes.",
        "provenance": "2 templates tied to 1 official PDF source for this local date slice; redistribution remains verification-only.",
    }
    for dimension, count in coverage_counts.items():
        data["coverage-declarations"].append({
            "coverage_id": f"jr-west.2026.{dimension}.west-express-ginga-west-batch",
            "operator_scope": "jr-west",
            "year": 2026,
            "dimension": dimension,
            "status": "missing" if count == 0 else "partial",
            "record_count": count,
            "source_id": source["source_id"],
            "notes": coverage_notes[dimension],
        })

    output_paths = {
        "services": BASE / "normalized/services-west-batch.jsonl",
        "service-name-periods": BASE / "normalized/service-name-periods-west-batch.jsonl",
        "timetable-versions": BASE / "normalized/timetable-versions-west-batch.jsonl",
        "station-identities": STATION_OUTPUT_PATH,
        "fact-sources": BASE / "normalized/fact-sources-west-batch.jsonl",
        "fact-completeness": BASE / "normalized/fact-completeness-west-batch.jsonl",
        "research-queue": BASE / "normalized/research-queue-west-batch.jsonl",
        "coverage-declarations": BASE / "normalized/coverage-declarations-west-batch.jsonl",
        "trips": BASE / "normalized/trips/reviewed-west-batch/seeds-west-batch.jsonl",
        "stop-times": BASE / "normalized/stop-times/reviewed-west-batch/seeds-west-batch.jsonl",
        "calendars": BASE / "normalized/calendars/reviewed-west-batch/seeds-west-batch.jsonl",
        "calendar-exceptions": BASE / "normalized/calendar-exceptions/reviewed-west-batch/seeds-west-batch.jsonl",
        "trip-stop-time-overrides": BASE / "normalized/trip-stop-time-overrides/reviewed-west-batch/seeds-west-batch.jsonl",
    }
    write_jsonl(SOURCE_REGISTRY_PATH, [source])
    data["station-identities"] = new_station_rows
    for entity, path in output_paths.items():
        write_jsonl(path, data[entity])

    print(
        f"Normalized {len(trip_ids)} JR West directional templates, {len(normalized_days)} explicit occurrences, "
        f"{len(data['stop-times'])} stop rows, and {len(data['trip-stop-time-overrides'])} holiday override rows; "
        f"excluded post-as-of dates {excluded_dates}."
    )


if __name__ == "__main__":
    main()
