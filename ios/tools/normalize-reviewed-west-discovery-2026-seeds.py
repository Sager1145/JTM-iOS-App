#!/usr/bin/env python3
"""Normalize the exact-date reviewed JR West Yakumo 15 discovery seed."""

from collections import defaultdict
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE_PATH = BASE / "candidates/jr-west-yakumo15-20260930-discovery.json"
SOURCE_REGISTRY_PATH = BASE / "sources/source-registry-discovery-west-2026.jsonl"
SUFFIX = "discovery-west-2026"
STATION_DIRECTORY_SOURCE = "jtm-current-station-directory"
ENGLISH_NAME_SOURCE = "jr-west-yakumo-official-english-2026"
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


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


def resolve_stations(stops, output_path):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    resolved = {}
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
        resolved[name] = {
            "station_id": "jp.n02." + code,
            "name_snapshot": name,
            "reference_kind": "current_n02",
            "current_source_code": code,
        }

    existing_by_id = defaultdict(list)
    for path, line_number, row in existing_rows("normalized/station-identities*.jsonl", output_path):
        existing_by_id[row["station_id"]].append((path, line_number, row))
    for row in resolved.values():
        expected = {
            key: row[key]
            for key in ("station_id", "name_snapshot", "reference_kind", "current_source_code")
        }
        for path, line_number, existing in existing_by_id.get(row["station_id"], []):
            actual = {key: existing.get(key) for key in expected}
            if actual != expected:
                raise ValueError(f"Conflicting station identity at {path}:{line_number}: {actual} != {expected}")
    new_rows = [row for row in resolved.values() if row["station_id"] not in existing_by_id]
    return resolved, sorted(new_rows, key=lambda row: row["station_id"])


def validate_sources(candidate, sources):
    source_by_id = {row["source_id"]: row for row in sources}
    if len(source_by_id) != len(sources):
        raise ValueError("Duplicate source ids in JR West discovery registry")
    family_sources = [row for row in sources if row["source_type"] == "official_service_detail"]
    if len(family_sources) != 23:
        raise ValueError(f"Expected 23 distinct official-directory family sources, found {len(family_sources)}")
    if set(candidate["source_ids"]) != {
        "jr-west-limited-express-directory-20260929",
        "jr-west-family-yakumo-20260929",
        "jr-west-odekake-yakumo15-1015m-20260930",
    }:
        raise ValueError("Candidate source contract changed")
    for source_id in candidate["source_ids"]:
        if source_id not in source_by_id:
            raise ValueError(f"Missing candidate source {source_id}")
    if ENGLISH_NAME_SOURCE not in source_by_id or source_by_id[ENGLISH_NAME_SOURCE]["url_or_locator"] != "https://www.westjr.co.jp/global/en/train/yakumo/":
        raise ValueError("Official English Yakumo guide is missing or changed")
    train_source = source_by_id[candidate["trip"]["source_id"]]
    if train_source["effective_date"] != candidate["observed_service_date"]:
        raise ValueError("Exact train source date disagrees with candidate")
    if f"date={candidate['observed_service_date'].replace('-', '')}" not in train_source["url_or_locator"]:
        raise ValueError("Exact service date is not pinned in the official train URL")
    if train_source["license_status"] != "explicit_reproduction_and_processing_prohibition":
        raise ValueError("Train-page source terms must remain explicit")

    local_ids = set(source_by_id)
    for path, line_number, row in existing_rows("sources/source-registry*.jsonl", SOURCE_REGISTRY_PATH):
        if row["source_id"] in local_ids:
            raise ValueError(f"Source id collision at {path}:{line_number}: {row['source_id']}")
    return source_by_id


def validate_candidate(candidate):
    if candidate.get("candidate_status") != "visually_reviewed":
        raise ValueError("Candidate must be visually reviewed")
    if candidate["observed_service_date"] != "2026-09-30":
        raise ValueError("This seed is deliberately pinned to 2026-09-30")
    if (candidate["valid_from"], candidate["valid_until"]) != ("2026-09-30", "2026-10-01"):
        raise ValueError("Candidate must retain its one-day half-open validity")
    trip = candidate["trip"]
    if (trip["train_number"], trip["public_number"], trip["calendar_verification"]) != (
        "1015M", "15", "observed_date_only"
    ):
        raise ValueError("Reviewed Yakumo 15 identity/calendar contract changed")
    stops = trip["passenger_stops"]
    expected_names = [
        "岡山", "倉敷", "備中高梁", "新見", "根雨", "米子",
        "安来", "松江", "玉造温泉", "宍道", "出雲市",
    ]
    if [row["station_name"] for row in stops] != expected_names:
        raise ValueError("Reviewed Yakumo 15 passenger-stop order changed")
    if stops[0]["departure_time"] != "14:13" or stops[-1]["arrival_time"] != "17:23":
        raise ValueError("Reviewed Yakumo 15 endpoint clocks changed")
    if stops[0]["arrival_time"] is not None or stops[-1]["departure_time"] is not None:
        raise ValueError("Missing endpoint clock sides must remain null")


def main():
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    candidate = json.loads(CANDIDATE_PATH.read_text(encoding="utf-8"))
    sources = read_jsonl(SOURCE_REGISTRY_PATH)
    validate_candidate(candidate)
    validate_sources(candidate, sources)
    if candidate["observed_service_date"] > manifest["as_of_date"]:
        raise ValueError("Observed service date exceeds manifest as_of_date")

    service = candidate["service"]
    service_output = BASE / f"normalized/services-{SUFFIX}.jsonl"
    for path, line_number, row in existing_rows("normalized/services*.jsonl", service_output):
        if row["service_id"] == service["service_id"]:
            raise ValueError(f"Service id collision at {path}:{line_number}: {service['service_id']}")

    station_output = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    trip_source = candidate["trip"]
    stations, new_station_rows = resolve_stations(trip_source["passenger_stops"], station_output)
    canonical_source_ids = {
        row["source_id"]
        for _, _, row in existing_rows("sources/source-registry*.jsonl", SOURCE_REGISTRY_PATH)
    }
    if STATION_DIRECTORY_SOURCE not in canonical_source_ids:
        raise ValueError(f"Missing canonical station directory source {STATION_DIRECTORY_SOURCE}")

    service_date = candidate["observed_service_date"]
    valid_until = candidate["valid_until"]
    source_id = trip_source["source_id"]
    trip_id = f"jr-west.yakumo.15.{service_date}"
    version_id = trip_id + ".version"
    calendar_id = trip_id + ".calendar"
    data = defaultdict(list)

    data["services"].append({
        **service,
        "first_verified_date": service_date,
        "last_verified_date": service_date,
    })
    data["service-name-periods"].append({
        "service_id": service["service_id"],
        "name": service["canonical_name"],
        "language": "ja",
        "valid_from": service_date,
        "valid_until": valid_until,
        "name_type": "canonical",
        "source_id": source_id,
    })
    data["service-name-periods"].append({
        "service_id": service["service_id"],
        "name": "Yakumo",
        "language": "en",
        "valid_from": service_date,
        "valid_until": valid_until,
        "name_type": "official_english",
        "source_id": ENGLISH_NAME_SOURCE,
    })
    data["timetable-versions"].append({
        "timetable_version_id": version_id,
        "operator_scope": "jr-west",
        "effective_from": service_date,
        "effective_until": valid_until,
        "edition_name": "JR Odekake exact-date Yakumo 15 timetable for 2026-09-30",
        "revision_type": "observed_date",
        "publication_date": None,
        "completeness": "partial",
        "source_ids": [source_id],
    })
    data["calendars"].append({
        "calendar_id": calendar_id,
        "valid_from": service_date,
        "valid_until": valid_until,
        "holiday_policy": "none",
        **{weekday: 0 for weekday in WEEKDAYS},
    })
    data["calendar-exceptions"].append({
        "calendar_id": calendar_id,
        "service_date": service_date,
        "exception_type": "add",
        "source_id": source_id,
        "reason": "Exact date parameter and displayed September 2026 calendar; daily label not expanded",
    })

    stop_rows = []
    for sequence, stop in enumerate(trip_source["passenger_stops"], 1):
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
            "source_id": source_id,
        })
    data["stop-times"].extend(stop_rows)
    data["trips"].append({
        "trip_id": trip_id,
        "timetable_version_id": version_id,
        "service_id": service["service_id"],
        "calendar_id": calendar_id,
        "train_number": trip_source["train_number"],
        "public_number": trip_source["public_number"],
        "origin_station_id": stop_rows[0]["station_id"],
        "destination_station_id": stop_rows[-1]["station_id"],
        "direction": trip_source["direction"],
        "service_class": service["service_class"],
        "notes": (
            "Exact 2026-09-30 official train page; passenger calls only. "
            "Operator boundaries and ordered physical line identities remain unresolved."
        ),
    })

    statuses = {
        "identity": ("verified", "high", "The exact-date page prints 特急 やくも15号."),
        "train_number": ("verified", "high", "The exact-date page prints 1015M and public number 15."),
        "operator": ("unknown", "low", "The train page does not print an ordered operator-boundary table."),
        "validity_calendar": ("verified", "high", "Only the URL-pinned and displayed date 2026-09-30 is normalized."),
        "origin_destination": ("verified", "high", "The displayed table begins at 岡山 and ends at 出雲市."),
        "stops": ("verified", "high", "All 11 displayed passenger calls with clocks are retained in order."),
        "times": ("verified", "high", "Passenger-call clocks are retained verbatim to the minute."),
        "route_lines": ("unknown", "low", "No dated ordered physical line identities are promoted from this page."),
        "station_refs": ("verified", "high", "Every passenger-call name resolves to one current JR West N02 sourceCode."),
        "provenance": ("partial", "high", "Official URL and source terms are recorded; reuse permission was not identified."),
    }
    source_locators = {
        "identity": "Header and fields 列車種別 / 列車名",
        "train_number": "Fields 列車番号 1015M / 列車名 やくも15号",
        "validity_calendar": "URL date=20260930 and displayed 2026年9月 calendar",
        "origin_destination": "時刻詳細 first and last passenger-clock rows",
        "stops": "時刻詳細 passenger-clock rows; レ pass rows excluded",
        "times": "時刻詳細 着発時刻",
        "provenance": "Page footer and exact-date URL",
    }
    for dimension, (status, confidence, notes) in statuses.items():
        data["fact-completeness"].append({
            "entity_type": "trip",
            "entity_id": trip_id,
            "dimension": dimension,
            "status": status,
            "confidence": confidence,
            "notes": notes,
        })
        if dimension in source_locators or dimension == "station_refs":
            data["fact-sources"].append({
                "entity_type": "trip",
                "entity_id": trip_id,
                "field_name": dimension,
                "source_id": STATION_DIRECTORY_SOURCE if dimension == "station_refs" else source_id,
                "page_or_locator": (
                    "Shipped current station directory; exact JR West name/code resolution"
                    if dimension == "station_refs" else source_locators[dimension]
                ),
                "confidence": confidence,
                "verification_status": status,
            })

    for dimension, status, notes in [
        ("operator", "open", "Find official ordered operator-boundary evidence before adding operator segments."),
        ("route_lines", "open", "Find dated ordered physical line identities before adding route-line rows."),
        ("validity_calendar", "open", "Do not expand 毎日運転 beyond 2026-09-30 without a bounded reviewed calendar policy."),
        ("provenance", "license_blocked", "The official page explicitly prohibits unauthorized reproduction, copying, and processing."),
    ]:
        data["research-queue"].append({
            "research_id": f"{trip_id}.{dimension}",
            "entity_type": "trip",
            "entity_id": trip_id,
            "missing_dimension": dimension,
            "status": status,
            "notes": notes,
        })

    counts = {
        "inventory": 1,
        "train_number": 1,
        "calendar": 1,
        "stops": len(stop_rows),
        "times": len(stop_rows),
        "route_lines": 0,
        "station_refs": len(stop_rows),
        "provenance": 1,
    }
    notes = {
        "inventory": "1 exact-date Yakumo template normalized; the discovery registry separately inventories 23 directory families without promoting them.",
        "train_number": "1015M / public number 15 on the exact-date official page.",
        "calendar": "1 explicit occurrence on 2026-09-30; the wider daily label is not expanded.",
        "stops": "11 passenger calls from one exact-date timetable; pass rows are intentionally excluded.",
        "times": "11 passenger-call rows with printed minute clocks, including null on the absent endpoint side.",
        "route_lines": "0 route-line rows; no dated ordered physical line source was promoted.",
        "station_refs": "11 passenger-call references resolved to unique current JR West sourceCodes.",
        "provenance": "1 official exact-date timetable source; verification-only under its explicit reuse prohibition.",
    }
    # The original JR West 2026 operator/year declaration owns these dimensions.

    paths = {
        "services": service_output,
        "service-name-periods": BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl",
        "timetable-versions": BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl",
        "station-identities": station_output,
        "fact-sources": BASE / f"normalized/fact-sources-{SUFFIX}.jsonl",
        "fact-completeness": BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl",
        "research-queue": BASE / f"normalized/research-queue-{SUFFIX}.jsonl",
        "coverage-declarations": BASE / f"normalized/coverage-declarations-{SUFFIX}.jsonl",
        "trips": BASE / f"normalized/trips/reviewed-{SUFFIX}/seeds.jsonl",
        "stop-times": BASE / f"normalized/stop-times/reviewed-{SUFFIX}/seeds.jsonl",
        "calendars": BASE / f"normalized/calendars/reviewed-{SUFFIX}/seeds.jsonl",
        "calendar-exceptions": BASE / f"normalized/calendar-exceptions/reviewed-{SUFFIX}/seeds.jsonl",
    }
    data["station-identities"] = new_station_rows
    for entity, path in paths.items():
        write_jsonl(path, data[entity])
    print(
        f"Normalized Yakumo 15 on {service_date}: 1 trip, {len(stop_rows)} passenger calls, "
        f"{len(new_station_rows)} new station identities; 23-family discovery registry retained separately."
    )


if __name__ == "__main__":
    main()
