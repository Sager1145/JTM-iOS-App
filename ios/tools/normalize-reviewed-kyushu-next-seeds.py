#!/usr/bin/env python3
"""Normalize reviewed JR Kyushu Ibusuki no Tamatebako summer 2026 facts."""

from collections import defaultdict
from datetime import date, timedelta
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE_PATH = BASE / "candidates/jr-kyushu-ibusuki-no-tamatebako-2026-summer-kyushu-next-batch.json"
SOURCE_REGISTRY_PATH = BASE / "sources/source-registry-kyushu-next-batch.jsonl"
STATION_OUTPUT_PATH = BASE / "normalized/station-identities-kyushu-next-batch.jsonl"
STATION_DIRECTORY_SOURCE = "jtm-current-station-directory"
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def existing_rows(pattern, excluded_path=None):
    for path in sorted(BASE.glob(pattern)):
        if not path.is_file() or path == excluded_path:
            continue
        for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if raw.strip():
                yield path, line_number, json.loads(raw)


def resolve_stations(names):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    resolved = {}
    for name in sorted(set(names)):
        codes = {
            station[0]
            for line in package["lines"]
            if line["operator"] == "九州旅客鉄道"
            for station in line["stations"]
            if station[1] == name
        }
        if len(codes) != 1:
            raise ValueError(f"Ambiguous or missing JR Kyushu station identity for {name}: {sorted(codes)}")
        code = codes.pop()
        resolved[name] = {
            "station_id": "jp.n02." + code,
            "name_snapshot": name,
            "reference_kind": "current_n02",
            "current_source_code": code,
        }

    existing_by_id = defaultdict(list)
    for path, line_number, row in existing_rows("normalized/station-identities*.jsonl", STATION_OUTPUT_PATH):
        existing_by_id[row["station_id"]].append((path, line_number, row))
    for row in resolved.values():
        expected = {key: row[key] for key in ("station_id", "name_snapshot", "reference_kind", "current_source_code")}
        for path, line_number, existing in existing_by_id.get(row["station_id"], []):
            actual = {key: existing.get(key) for key in expected}
            if actual != expected:
                raise ValueError(f"Conflicting station identity at {path}:{line_number}: {actual} != {expected}")
    new_rows = [row for row in resolved.values() if row["station_id"] not in existing_by_id]
    return resolved, sorted(new_rows, key=lambda row: row["station_id"])


def ensure_no_collisions(service, sources):
    for path, line_number, row in existing_rows("normalized/services*.jsonl"):
        if path.name != "services-kyushu-next-batch.jsonl" and row["service_id"] == service["service_id"]:
            raise ValueError(f"Service id {service['service_id']} already exists at {path}:{line_number}")
    source_ids = {source["source_id"] for source in sources}
    for path, line_number, row in existing_rows("sources/source-registry*.jsonl", SOURCE_REGISTRY_PATH):
        if row["source_id"] in source_ids:
            raise ValueError(f"Source id {row['source_id']} already exists at {path}:{line_number}")


def main():
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    as_of = date.fromisoformat(manifest["as_of_date"])
    candidate = json.loads(CANDIDATE_PATH.read_text(encoding="utf-8"))
    if candidate.get("candidate_status") != "visually_reviewed":
        raise ValueError("Candidate must be visually reviewed before normalization")

    sources = candidate["sources"]
    source_by_id = {source["source_id"]: source for source in sources}
    service_source_id = "jr-kyushu-ibusuki-no-tamatebako-timetable-20260314"
    calendar_source_id = candidate["operating_date_range"]["source_id"]
    if set(source_by_id) != {service_source_id, calendar_source_id}:
        raise ValueError("Candidate source ids do not match the reviewed source contract")
    service = candidate["service"]
    ensure_no_collisions(service, sources)

    source_registry_ids = {
        row["source_id"]
        for _, _, row in existing_rows("sources/source-registry*.jsonl", SOURCE_REGISTRY_PATH)
    }
    if STATION_DIRECTORY_SOURCE not in source_registry_ids:
        raise ValueError(f"Missing canonical station directory source {STATION_DIRECTORY_SOURCE}")

    date_range = candidate["operating_date_range"]
    first_source_day = date.fromisoformat(date_range["from"])
    last_source_day = date.fromisoformat(date_range["until_inclusive"])
    source_days = [
        first_source_day + timedelta(days=offset)
        for offset in range((last_source_day - first_source_day).days + 1)
    ]
    days = [day for day in source_days if day <= as_of]
    excluded_dates = [day.isoformat() for day in source_days if day > as_of]
    if not days:
        raise ValueError("No source operating dates fall within manifest as_of_date")
    valid_from = days[0].isoformat()
    valid_until = (days[-1] + timedelta(days=1)).isoformat()

    station_rows, new_station_rows = resolve_stations(
        [value for trip in candidate["trips"] for value in (trip["origin"], trip["destination"])]
    )
    data = defaultdict(list)
    data["services"].append({
        **service,
        "first_verified_date": valid_from,
        "last_verified_date": days[-1].isoformat(),
    })
    data["service-name-periods"].append({
        "service_id": service["service_id"],
        "name": service["canonical_name"],
        "language": "ja",
        "valid_from": valid_from,
        "valid_until": valid_until,
        "name_type": "canonical",
        "source_id": service_source_id,
    })

    version_id = f"jr-kyushu.{service['service_id']}.2026-summer.version"
    calendar_id = f"jr-kyushu.{service['service_id']}.2026-summer.calendar"
    data["timetable-versions"].append({
        "timetable_version_id": version_id,
        "operator_scope": "jr-kyushu",
        "effective_from": valid_from,
        "effective_until": valid_until,
        "edition_name": "2026-03-14 timetable with reviewed 2026 summer operating range",
        "revision_type": "planned_exception",
        "publication_date": source_by_id[calendar_source_id]["publication_date"],
        "completeness": "partial",
        "source_ids": [service_source_id, calendar_source_id],
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
        "source_id": calendar_source_id,
        "reason": "PDF p.10 contiguous operating range, capped at manifest as_of_date",
    } for day in days)

    trip_ids = []
    for trip_source in candidate["trips"]:
        public_number = trip_source["public_number"]
        trip_id = f"jr-kyushu.{service['service_id']}.{public_number}.{valid_from}"
        trip_ids.append(trip_id)
        origin = station_rows[trip_source["origin"]]
        destination = station_rows[trip_source["destination"]]
        data["trips"].append({
            "trip_id": trip_id,
            "timetable_version_id": version_id,
            "service_id": service["service_id"],
            "calendar_id": calendar_id,
            "train_number": None,
            "public_number": public_number,
            "origin_station_id": origin["station_id"],
            "destination_station_id": destination["station_id"],
            "direction": trip_source["direction_label"],
            "service_class": service["service_class"],
            "notes": (
                "Official timetable displays only the two endpoint stops. Public号次 and endpoint clocks are exact; "
                "internal train number, operator boundary and physical route identity remain unresolved."
            ),
        })
        data["stop-times"].extend([
            {
                "trip_id": trip_id,
                "stop_sequence": 1,
                "station_id": origin["station_id"],
                "arrival_time": None,
                "departure_time": trip_source["departure_time"],
                "day_offset": 0,
                "call_type": "origin",
                "pickup_allowed": 1,
                "dropoff_allowed": 0,
                "time_accuracy": "minute",
                "source_id": service_source_id,
            },
            {
                "trip_id": trip_id,
                "stop_sequence": 2,
                "station_id": destination["station_id"],
                "arrival_time": trip_source["arrival_time"],
                "departure_time": None,
                "day_offset": 0,
                "call_type": "destination",
                "pickup_allowed": 0,
                "dropoff_allowed": 1,
                "time_accuracy": "minute",
                "source_id": service_source_id,
            },
        ])

    statuses = {
        "identity": ("verified", "high", "Official service page and PDF identify the named limited express."),
        "train_number": ("partial", "high", "Public numbers 1-6 are printed; internal train numbers are absent."),
        "operator": ("unknown", "low", "Neither source prints ordered operator-boundary segments."),
        "validity_calendar": ("verified", "high", "PDF p.10 explicitly gives one contiguous date range for every numbered row."),
        "origin_destination": ("verified", "high", "Both official sources print the directional endpoints."),
        "stops": ("verified", "high", "The official page labels its two-row directional tables 停車駅."),
        "times": ("verified", "high", "Both sources agree on all twelve endpoint minute clocks."),
        "route_lines": ("unknown", "low", "No dated physical line identities are printed."),
        "station_refs": ("verified", "high", "Each source station name resolves to one JR Kyushu sourceCode."),
        "provenance": ("partial", "high", "Official sources are recorded, but no redistribution grant was identified."),
    }
    fact_sources = {
        "identity": (service_source_id, "Official HTML title and timetable heading"),
        "train_number": (calendar_source_id, "PDF p.10 列車名 rows; public号次 only"),
        "validity_calendar": (calendar_source_id, "PDF p.10 merged operating-date cells and 276-per-direction totals"),
        "origin_destination": (service_source_id, "Official HTML two directional timetable tables"),
        "stops": (service_source_id, "Official HTML tables explicitly headed 停車駅"),
        "times": (service_source_id, "Official HTML timetable, 2026-03-14 revision"),
        "station_refs": (STATION_DIRECTORY_SOURCE, "Shipped current station directory; exact JR Kyushu name/code resolution"),
        "provenance": (calendar_source_id, "Official PDF URL and SHA-256 reviewed 2026-09-28"),
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
            if dimension in fact_sources:
                source_id, locator = fact_sources[dimension]
                data["fact-sources"].append({
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": dimension,
                    "source_id": source_id,
                    "page_or_locator": locator,
                    "confidence": confidence,
                    "verification_status": status,
                })

    research = {
        "train_number": ("open", "Obtain an official working timetable that prints the internal train number."),
        "operator": ("open", "Obtain ordered operator-boundary evidence; do not infer it from the publisher."),
        "route_lines": ("open", "Obtain dated direct route identities; do not infer them from endpoint connectivity."),
        "provenance": ("license_blocked", "No redistribution or automated-extraction grant was found."),
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

    output_paths = {
        "services": BASE / "normalized/services-kyushu-next-batch.jsonl",
        "service-name-periods": BASE / "normalized/service-name-periods-kyushu-next-batch.jsonl",
        "timetable-versions": BASE / "normalized/timetable-versions-kyushu-next-batch.jsonl",
        "station-identities": STATION_OUTPUT_PATH,
        "fact-sources": BASE / "normalized/fact-sources-kyushu-next-batch.jsonl",
        "fact-completeness": BASE / "normalized/fact-completeness-kyushu-next-batch.jsonl",
        "research-queue": BASE / "normalized/research-queue-kyushu-next-batch.jsonl",
        "trips": BASE / "normalized/trips/reviewed-kyushu-next-batch/seeds-kyushu-next-batch.jsonl",
        "stop-times": BASE / "normalized/stop-times/reviewed-kyushu-next-batch/seeds-kyushu-next-batch.jsonl",
        "calendars": BASE / "normalized/calendars/reviewed-kyushu-next-batch/seeds-kyushu-next-batch.jsonl",
        "calendar-exceptions": BASE / "normalized/calendar-exceptions/reviewed-kyushu-next-batch/seeds-kyushu-next-batch.jsonl",
    }
    write_jsonl(SOURCE_REGISTRY_PATH, sources)
    data["station-identities"] = new_station_rows
    for entity, path in output_paths.items():
        write_jsonl(path, data[entity])

    print(
        f"Normalized {len(trip_ids)} JR Kyushu numbered templates, {len(days)} explicit service dates, "
        f"{len(trip_ids) * len(days)} occurrences, and {len(data['stop-times'])} endpoint stop rows; "
        f"excluded post-as-of dates {excluded_dates}; coverage declarations intentionally unchanged."
    )


if __name__ == "__main__":
    main()
