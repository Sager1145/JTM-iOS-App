#!/usr/bin/env python3
"""Normalize the reviewed JR West Inishie schedule selected for 2026-09-27."""

from collections import defaultdict
from datetime import date, timedelta
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE_PATH = BASE / "candidates/jr-west-inishie-20260927.json"
SOURCE_REGISTRY_PATH = BASE / "sources/source-registry-west-inishie-20260927.jsonl"
STATION_OUTPUT_PATH = BASE / "normalized/station-identities-west-inishie-20260927.jsonl"
SUFFIX = "west-inishie-20260927"
NESTED_BATCH = "reviewed-west-inishie-20260927"
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


def ensure_no_collisions(service_id, source_id):
    for path, line_number, row in existing_rows("normalized/services*.jsonl"):
        if path.name != f"services-{SUFFIX}.jsonl" and row["service_id"] == service_id:
            raise ValueError(f"Service id {service_id} already exists at {path}:{line_number}")
    for path, line_number, row in existing_rows("sources/source-registry*.jsonl", SOURCE_REGISTRY_PATH):
        if row["source_id"] == source_id:
            raise ValueError(f"Source id {source_id} already exists at {path}:{line_number}")


def resolve_stations(names):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    resolved = {}
    for name in sorted(set(names)):
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


def main():
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    as_of = date.fromisoformat(manifest["as_of_date"])
    candidate = json.loads(CANDIDATE_PATH.read_text(encoding="utf-8"))
    if candidate.get("candidate_status") != "visually_reviewed" or candidate.get("canonical") is not True:
        raise ValueError("Inishie candidate must be visually reviewed and canonical before normalization")
    if candidate.get("promotion_scope") != "scheduled_service_on_2026-09-27_only":
        raise ValueError("Inishie candidate promotion scope changed")

    source = candidate["source"]
    expected_source = (
        "jr-west-summer-extra-trains-20260515",
        "0e53aa203fcd480ec92823ba7e7cfd468a856618c79ca3b30e4647c80f6563c1",
        "verification_only",
        False,
    )
    actual_source = (
        source["source_id"], source["content_hash"], source["redistribution_status"],
        source["automated_extraction_allowed"],
    )
    if actual_source != expected_source:
        raise ValueError(f"Reviewed source contract changed: {actual_source}")

    service = candidate["service"]
    if (service["service_id"], service["service_class"], service["canonical_name"]) != (
            "inishie", "limited_express", "いにしへ"):
        raise ValueError("Reviewed Inishie service identity changed")
    ensure_no_collisions(service["service_id"], source["source_id"])

    service_day = date.fromisoformat(candidate["selected_service_date"])
    if service_day > as_of or service_day.isoformat() != "2026-09-27" or service_day.weekday() != 6:
        raise ValueError("Selected date must remain Sunday 2026-09-27 within the manifest cutoff")
    valid_from = service_day.isoformat()
    valid_until = (service_day + timedelta(days=1)).isoformat()

    station_names = [stop["station_name"] for trip in candidate["trips"] for stop in trip["stops"]]
    stations, new_station_rows = resolve_stations(station_names)
    source_registry_ids = {
        row["source_id"]
        for _, _, row in existing_rows("sources/source-registry*.jsonl", SOURCE_REGISTRY_PATH)
    }
    if STATION_DIRECTORY_SOURCE not in source_registry_ids:
        raise ValueError(f"Missing canonical station directory source {STATION_DIRECTORY_SOURCE}")

    data = defaultdict(list)
    data["services"].append({**service, "first_verified_date": valid_from, "last_verified_date": valid_from})
    data["service-name-periods"].append({
        "service_id": service["service_id"],
        "name": service["canonical_name"],
        "language": "ja",
        "valid_from": valid_from,
        "valid_until": valid_until,
        "name_type": "canonical",
        "source_id": source["source_id"],
    })

    version_id = "jr-west.inishie.2026-09-27.version"
    calendar_id = "jr-west.inishie.2026-09-27.calendar"
    data["timetable-versions"].append({
        "timetable_version_id": version_id,
        "operator_scope": "jr-west",
        "effective_from": valid_from,
        "effective_until": valid_until,
        "edition_name": "2026 summer Inishie selected Sunday schedule",
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
    data["calendar-exceptions"].append({
        "calendar_id": calendar_id,
        "service_date": valid_from,
        "exception_type": "add",
        "source_id": source["source_id"],
        "reason": "PDF physical page 12 says 土休日 within the 2026-07-01 to 2026-09-30 release period; selected date is Sunday",
    })

    trip_ids = []
    for trip_source in candidate["trips"]:
        public_number = trip_source["public_number"]
        trip_id = f"jr-west.inishie.{public_number}.{valid_from}"
        trip_ids.append(trip_id)
        stop_rows = []
        for sequence, stop in enumerate(trip_source["stops"], 1):
            station = stations[stop["station_name"]]
            stop_rows.append({
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
            })
        data["stop-times"].extend(stop_rows)
        data["trips"].append({
            "trip_id": trip_id,
            "timetable_version_id": version_id,
            "service_id": service["service_id"],
            "calendar_id": calendar_id,
            "train_number": None,
            "public_number": public_number,
            "origin_station_id": stop_rows[0]["station_id"],
            "destination_station_id": stop_rows[-1]["station_id"],
            "direction": trip_source["direction_label"],
            "service_class": service["service_class"],
            "notes": (
                "Official planned timetable for Sunday 2026-09-27. Public number and each printed station clock are exact; "
                "the Uji departure clock, internal train number, physical route identity, ordered operator boundaries, "
                "and actual operation are not established."
            ),
        })

    status_rows = {
        "identity": ("verified", "high", "The section heading identifies Inishie as a limited express."),
        "train_number": ("unknown", "low", "The release does not print internal train numbers."),
        "operator": ("unknown", "low", "JR West publishes the release, but no ordered operator-boundary table is printed."),
        "validity_calendar": ("verified", "high", "The selected date is Sunday within the printed summer period and the table says 土休日."),
        "origin_destination": ("verified", "high", "Each directional row prints its endpoint departure and arrival."),
        "stops": ("verified", "high", "The directional rows list Kyoto, Uji and Nara in order."),
        "times": ("partial", "high", "Every printed clock is retained verbatim; Uji departures are not printed or inferred."),
        "route_lines": ("unknown", "low", "No physical line identities are printed in the selected table."),
        "station_refs": ("verified", "high", "Each source name resolves to one JR West sourceCode in the current package."),
        "provenance": ("partial", "high", "Official URL and SHA-256 are pinned; no reuse grant was identified."),
    }
    locators = {
        "identity": "PDF physical page 12 section heading and introductory sentence",
        "public_number": "PDF physical page 12 directional rows",
        "validity_calendar": "PDF physical pages 1 and 12: release period plus 土休日",
        "origin_destination": "PDF physical page 12 directional row endpoints",
        "stops": "PDF physical page 12 directional columns",
        "times": "PDF physical page 12 directional clock cells",
        "station_refs": "Shipped current station directory; unique JR West name/code resolution",
        "provenance": "Official PDF URL and SHA-256 visually reviewed 2026-09-29",
    }
    for trip_id in trip_ids:
        for dimension, (status, confidence, notes) in status_rows.items():
            data["fact-completeness"].append({
                "entity_type": "trip",
                "entity_id": trip_id,
                "dimension": dimension,
                "status": status,
                "confidence": confidence,
                "notes": notes,
            })
            if dimension in locators:
                data["fact-sources"].append({
                    "entity_type": "trip",
                    "entity_id": trip_id,
                    "field_name": dimension,
                    "source_id": STATION_DIRECTORY_SOURCE if dimension == "station_refs" else source["source_id"],
                    "page_or_locator": locators[dimension],
                    "confidence": confidence,
                    "verification_status": status,
                })

    research = {
        "train_number": "Obtain an official source that prints the internal train number for each exact direction/date.",
        "operator": "Obtain direct evidence for ordered operator boundaries, if any.",
        "times": "Obtain the Uji departure clocks or a source explicitly equating arrival and departure.",
        "route_lines": "Obtain dated direct physical line identities for each adjacent stop pair.",
        "provenance": "No redistribution or automated-extraction grant was found; the PDF remains verification-only.",
    }
    for trip_id in trip_ids:
        for dimension, notes in research.items():
            data["research-queue"].append({
                "research_id": f"{trip_id}.{dimension}",
                "entity_type": "trip",
                "entity_id": trip_id,
                "missing_dimension": dimension,
                "status": "license_blocked" if dimension == "provenance" else "open",
                "notes": notes,
            })

    counts = {
        "inventory": 2,
        "train_number": 0,
        "calendar": 1,
        "stops": len(data["stop-times"]),
        "times": len(data["stop-times"]),
        "route_lines": 0,
        "station_refs": len(data["stop-times"]),
        "provenance": len(trip_ids),
    }
    coverage_notes = {
        "inventory": "Two directional Inishie trip rows for the selected service date only; not a JR West inventory.",
        "train_number": "No internal train number is printed; public numbers 61 and 62 are retained separately.",
        "calendar": "One planned Sunday occurrence on 2026-09-27 selected from the printed 土休日 rule.",
        "stops": "Six ordered stop rows across two directions; only Kyoto, Uji and Nara are printed.",
        "times": "Six printed station clocks; the two Uji departure clocks remain null.",
        "route_lines": "No route-line rows; no physical line identity is promoted from endpoint geography.",
        "station_refs": "Six stop references validated against unique current JR West sourceCodes.",
        "provenance": "Two trip rows tied to one official PDF and its reviewed SHA-256; redistribution remains verification-only.",
    }
    # The existing JR West 2026 operator/year declaration owns these dimensions.

    output_paths = {
        "services": BASE / f"normalized/services-{SUFFIX}.jsonl",
        "service-name-periods": BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl",
        "timetable-versions": BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl",
        "station-identities": STATION_OUTPUT_PATH,
        "fact-sources": BASE / f"normalized/fact-sources-{SUFFIX}.jsonl",
        "fact-completeness": BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl",
        "research-queue": BASE / f"normalized/research-queue-{SUFFIX}.jsonl",
        "coverage-declarations": BASE / f"normalized/coverage-declarations-{SUFFIX}.jsonl",
        "trips": BASE / f"normalized/trips/{NESTED_BATCH}/seeds.jsonl",
        "stop-times": BASE / f"normalized/stop-times/{NESTED_BATCH}/seeds.jsonl",
        "calendars": BASE / f"normalized/calendars/{NESTED_BATCH}/seeds.jsonl",
        "calendar-exceptions": BASE / f"normalized/calendar-exceptions/{NESTED_BATCH}/seeds.jsonl",
    }
    write_jsonl(SOURCE_REGISTRY_PATH, [source])
    data["station-identities"] = new_station_rows
    for entity, path in output_paths.items():
        write_jsonl(path, data[entity])

    print(
        f"Inishie 2026-09-27: {len(trip_ids)} directional trips, "
        f"{len(data['stop-times'])} printed clock rows, 1 scheduled service date."
    )


if __name__ == "__main__":
    main()
