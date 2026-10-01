#!/usr/bin/env python3
"""Normalize three source-pinned JR Shikoku Ishizuchi trips for 2026-09-30."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-shikoku-ishizuchi1-29-30-20260930.json"
SUFFIX = "reviewed-shikoku-ishizuchi1-29-30-20260930"
DAY = "2026-09-30"
UNTIL = "2026-10-01"
STATION_SOURCE = "jtm-current-station-directory"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")

EXPECTED = {
    "jr-shikoku.ishizuchi.1.1001m.exact-2026-09-30": {
        "number": "1001M", "public": "1", "url_id": "18541",
        "origin": "高松", "destination": "松山", "count": 15,
        "coupled_range": [3, 15], "partner": "jr-shikoku.shiokaze.1.2026-09-30",
    },
    "jr-shikoku.ishizuchi.29.1029m.exact-2026-09-30": {
        "number": "1029M", "public": "29", "url_id": "99561",
        "origin": "高松", "destination": "伊予西条", "count": 12,
        "coupled_range": [5, 12], "partner": None,
    },
    "jr-shikoku.ishizuchi.30.1030m.exact-2026-09-30": {
        "number": "1030M", "public": "30", "url_id": "28651",
        "origin": "松山", "destination": "高松", "count": 16,
        "coupled_range": [1, 14], "partner": None,
    },
}


def rows(pattern, exclude=None):
    for path in sorted(BASE.glob(pattern)):
        if path == exclude or not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                yield json.loads(line)


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    ordered = sorted(records, key=lambda row: json.dumps(row, ensure_ascii=False, sort_keys=True))
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in ordered),
        encoding="utf-8",
    )


def station_map(names):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    allowed = {"四国旅客鉄道"}
    result = {}
    for name in sorted(names):
        codes = {
            station[0]
            for line in package["lines"] if line["operator"] in allowed
            for station in line["stations"] if station[1] == name
        }
        if len(codes) != 1:
            raise ValueError(f"Ambiguous or absent current station {name}: {sorted(codes)}")
        result[name] = "jp.n02." + next(iter(codes))
    return result


def verify(candidate, prior_sources):
    if (candidate["candidate_status"] != "reviewed_official_html"
            or candidate["canonical"] is not False
            or candidate["service_date"] != DAY):
        raise ValueError("Candidate review state or date changed")
    if len(candidate["trips"]) != 3:
        raise ValueError("Expected exactly three bounded Ishizuchi trips")
    source_by_id = {row["source_id"]: row for row in candidate["sources"]}
    for trip in candidate["trips"]:
        expected = EXPECTED.get(trip["trip_id"])
        if expected is None:
            raise ValueError(f"Unexpected trip {trip['trip_id']}")
        if (trip["service_id"], trip["service_name"], trip["train_number"], trip["public_number"]
                ) != ("ishizuchi", "いしづち", expected["number"], expected["public"]):
            raise ValueError(f"Ishizuchi identity changed: {trip['trip_id']}")
        if (trip["origin"], trip["destination"], len(trip["stops"]), trip["coupled_stop_range"]
                ) != (expected["origin"], expected["destination"], expected["count"], expected["coupled_range"]):
            raise ValueError(f"Termini, stop count, or coupling range changed: {trip['trip_id']}")
        if trip["coupling"]["partner_trip_id"] != expected["partner"]:
            raise ValueError(f"Coupling partner changed: {trip['trip_id']}")
        observation = trip["calendar_observation"]
        if observation != {"month": "2026年9月", "day": 30, "cell_class": "ok", "operation_text": "毎日運転"}:
            raise ValueError(f"Exact-date evidence changed: {trip['trip_id']}")
        source = source_by_id[trip["source_id"]]
        expected_url = f"https://timetable.jr-odekake.net/train-timetable/{expected['url_id']}?date=20260930"
        if trip["source_url"] != expected_url or source["url_or_locator"] != expected_url:
            raise ValueError(f"Official URL changed: {trip['trip_id']}")
        if source["automated_extraction_allowed"] is not False:
            raise ValueError(f"Source policy changed: {trip['trip_id']}")
        if trip["stops"][0]["name"] != trip["origin"] or trip["stops"][-1]["name"] != trip["destination"]:
            raise ValueError(f"Printed termini do not bound stops: {trip['trip_id']}")
        if any(not stop["clock_column"] for stop in trip["stops"]):
            raise ValueError(f"Clock-column provenance missing: {trip['trip_id']}")
        formation = trip["formation"]
        if any(formation[field] is not None for field in (
                "car_count", "reserved_seat_capacity", "vehicle_series", "actual_dispatch")):
            raise ValueError(f"Unprinted formation or actual-dispatch fact claimed: {trip['trip_id']}")
    new_ids = {row["source_id"] for row in candidate["sources"] if row["source_id"] not in prior_sources}
    if new_ids != {"jr-odekake-ishizuchi29-20260930-train", "jr-odekake-ishizuchi30-20260930-train"}:
        raise ValueError(f"Unexpected new source identities: {sorted(new_ids)}")


def main():
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    if DAY > manifest["as_of_date"]:
        raise ValueError("Candidate date exceeds database cutoff")
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    registry_target = BASE / f"sources/source-registry-{SUFFIX}.jsonl"
    prior_source_rows = list(rows("sources/source-registry*.jsonl", registry_target))
    prior_sources = {row["source_id"]: row for row in prior_source_rows}
    verify(candidate, prior_sources)

    trip_target = BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl"
    existing_trip_ids = {row["trip_id"] for row in rows("normalized/trips/*/*.jsonl", trip_target)}
    if existing_trip_ids.intersection(EXPECTED):
        raise ValueError("An exact Ishizuchi trip id already exists")
    if "jr-shikoku.shiokaze.1.2026-09-30" not in existing_trip_ids:
        raise ValueError("Materialized Shiokaze 1 partner is required for the reciprocal relation")

    service_target = BASE / f"normalized/services-{SUFFIX}.jsonl"
    prior_services = {row["service_id"]: row for row in rows("normalized/services*.jsonl", service_target)}
    service = prior_services.get("ishizuchi")
    if not service or service["canonical_name"] != "いしづち":
        raise ValueError("Existing Ishizuchi service identity missing or inconsistent")

    all_names = {
        name for trip in candidate["trips"]
        for name in [trip["origin"], trip["destination"], *[stop["name"] for stop in trip["stops"]]]
    }
    stations = station_map(all_names)
    station_target = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    prior_stations = {row["station_id"]: row for row in rows("normalized/station-identities*.jsonl", station_target)}
    station_rows = []
    for name, station_id in stations.items():
        record = {
            "station_id": station_id,
            "name_snapshot": name,
            "reference_kind": "current_n02",
            "current_source_code": station_id.removeprefix("jp.n02."),
        }
        previous = prior_stations.get(station_id)
        if previous and any(previous.get(key) != value for key, value in record.items()):
            raise ValueError(f"Station identity conflict for {name}")
        if previous is None:
            station_rows.append(record)

    source_by_id = {row["source_id"]: row for row in candidate["sources"]}
    source_rows = [row for source_id, row in source_by_id.items() if source_id not in prior_sources]
    versions, calendars, exceptions, trips, stop_times = [], [], [], [], []
    formations, relations, fact_sources, completeness, research = [], [], [], [], []

    for trip in candidate["trips"]:
        trip_id = trip["trip_id"]
        source_id = trip["source_id"]
        calendar_id = trip_id + ".calendar"
        version_id = trip_id + ".version"
        versions.append({
            "timetable_version_id": version_id,
            "operator_scope": "jr-shikoku",
            "effective_from": DAY,
            "effective_until": UNTIL,
            "edition_name": f"JR時刻表2026年10月号 exact 2026-09-30 paired detail: いしづち{trip['public_number']}号",
            "revision_type": "source_snapshot",
            "completeness": "partial",
            "source_ids": [source_id],
        })
        calendars.append({
            "calendar_id": calendar_id, "valid_from": DAY, "valid_until": UNTIL,
            "holiday_policy": "none", **{weekday: 0 for weekday in WEEKDAYS},
        })
        exceptions.append({
            "calendar_id": calendar_id, "service_date": DAY, "exception_type": "add",
            "source_id": source_id, "reason": "2026年9月 day 30 td.ok; 毎日運転",
        })
        trips.append({
            "trip_id": trip_id, "timetable_version_id": version_id,
            "service_id": "ishizuchi", "calendar_id": calendar_id,
            "train_number": trip["train_number"], "public_number": trip["public_number"],
            "origin_station_id": stations[trip["origin"]],
            "destination_station_id": stations[trip["destination"]],
            "service_class": "limited_express", "direction": trip["direction"],
            "notes": (
                "Exact-date paired official detail. Independent-section clocks come from the いしづち column; "
                "through-section clocks come from the しおかぜ column only across the explicitly printed coupling "
                f"{trip['coupling']['printed_section']}. Physical lines and operator segments remain unresolved."
            ),
        })
        for sequence, stop in enumerate(trip["stops"], 1):
            call_type = "origin" if sequence == 1 else "destination" if sequence == len(trip["stops"]) else "passenger_stop"
            stop_times.append({
                "trip_id": trip_id, "stop_sequence": sequence,
                "station_id": stations[stop["name"]],
                "arrival_time": stop["arrival"], "departure_time": stop["departure"],
                "day_offset": 0, "call_type": call_type,
                "pickup_allowed": 0 if call_type == "destination" else 1,
                "dropoff_allowed": 0 if call_type == "origin" else 1,
                "platform": stop["platform"], "time_accuracy": "minute", "source_id": source_id,
            })

        formation = trip["formation"]
        formation_row = {
            "formation_id": f"{trip_id}.formation.{DAY}", "trip_id": trip_id,
            "service_date": DAY, "evidence_kind": "planned",
            "all_reserved": formation["all_reserved"], "source_id": source_id,
            "notes": "Published seat categories only; car count, vehicle series, capacity, and actual dispatch are unknown.",
        }
        if formation["green_car_available"] is not None:
            formation_row["green_car_available"] = formation["green_car_available"]
        formations.append(formation_row)

        printed_range = trip["coupling"]["printed_section"]
        fact_sources.extend([
            {
                "entity_type": "trip", "entity_id": trip_id,
                "field_name": "coupling.partner_train_number", "source_id": source_id,
                "page_or_locator": f"併結運転: {printed_range}は{trip['coupling']['partner_train_number']}に併結",
                "confidence": "high", "verification_status": "verified",
            },
            {
                "entity_type": "trip", "entity_id": trip_id,
                "field_name": "formation.all_reserved", "source_id": source_id,
                "page_or_locator": "車両設備情報: 普通車一部指定席",
                "confidence": "high", "verification_status": "verified",
            },
        ])
        if formation["green_car_available"] is True:
            fact_sources.append({
                "entity_type": "trip", "entity_id": trip_id,
                "field_name": "formation.green_car_available", "source_id": source_id,
                "page_or_locator": "車両設備情報: グリーン車指定席",
                "confidence": "high", "verification_status": "verified",
            })
        verified = {
            "identity": "Paired detail prints 特急 いしづち and public number.",
            "train_number": f"Paired detail prints {trip['train_number']}.",
            "validity_calendar": "September calendar includes day 30 and says 毎日運転.",
            "origin_destination": "Train heading prints both termini.",
            "stops": f"{len(trip['stops'])} passenger calls are printed across the independent and explicitly coupled columns.",
            "times": "Every minute clock and platform is printed; coupled clocks retain their source-column provenance in the reviewed candidate.",
            "station_refs": "Names match unique current N02 station identities.",
        }
        for dimension, note in verified.items():
            completeness.append({
                "entity_type": "trip", "entity_id": trip_id, "dimension": dimension,
                "status": "verified", "confidence": "high", "notes": note,
            })
            fact_sources.append({
                "entity_type": "trip", "entity_id": trip_id, "field_name": dimension,
                "source_id": STATION_SOURCE if dimension == "station_refs" else source_id,
                "page_or_locator": "2026-09-30 paired train detail and printed coupling section",
                "confidence": "high", "verification_status": "verified",
            })
        completeness.extend([
            {"entity_type":"trip","entity_id":trip_id,"dimension":"formation","status":"partial","confidence":"high","notes":"Planned seat categories only; no car count, series, capacity, or actual dispatch."},
            {"entity_type":"trip","entity_id":trip_id,"dimension":"operator","status":"unknown","confidence":"low","notes":"Publishing company is not an ordered train-operator boundary source."},
            {"entity_type":"trip","entity_id":trip_id,"dimension":"route_lines","status":"unknown","confidence":"low","notes":"No dated ordered physical line IDs are established."},
            {"entity_type":"trip","entity_id":trip_id,"dimension":"provenance","status":"partial","confidence":"medium","notes":"Official page is pinned for verification; redistribution is prohibited."},
        ])
        fact_sources.append({
            "entity_type": "trip", "entity_id": trip_id, "field_name": "provenance",
            "source_id": source_id, "page_or_locator": "Exact-date official URL; source bytes not bundled",
            "confidence": "medium", "verification_status": "partial",
        })
        for dimension, status, note in (
            ("operator", "open", "Find dated ordered train-operator segment boundaries."),
            ("route_lines", "open", "Find dated ordered physical line identities."),
            ("formation", "open", "Find train-specific car count, series, capacity, and actual-dispatch evidence."),
            ("provenance", "license_blocked", "Official timetable prohibits reproduction and processing."),
        ):
            research.append({
                "research_id": f"{trip_id}.{dimension}", "entity_type": "trip", "entity_id": trip_id,
                "missing_dimension": dimension, "status": status, "notes": note,
            })
        partner = trip["coupling"]["partner_trip_id"]
        if partner:
            start, end = trip["coupled_stop_range"]
            relations.extend([
                {"trip_id":trip_id,"related_trip_id":partner,"relation_type":"couples_with",
                 "from_sequence":start,"to_sequence":end,"source_id":source_id},
                {"trip_id":partner,"related_trip_id":trip_id,"relation_type":"couples_with",
                 "from_sequence":start,"to_sequence":end,"source_id":source_id},
            ])
        else:
            research.append({
                "research_id": f"{trip_id}.coupling_partner", "entity_type": "trip", "entity_id": trip_id,
                "missing_dimension": "coupling_partner", "status": "open",
                "notes": f"Materialize {trip['coupling']['partner_service_name']}{trip['coupling']['partner_public_number']}号 "
                         f"{trip['coupling']['partner_train_number']} before adding a trip relation.",
            })

    outputs = {
        registry_target: source_rows,
        service_target: [],
        station_target: station_rows,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": versions,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendars,
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exceptions,
        trip_target: trips,
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stop_times,
        BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl": formations,
        BASE / f"normalized/trip-relations/{SUFFIX}/seeds.jsonl": relations,
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": fact_sources,
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": completeness,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": research,
    }
    for path, records in outputs.items():
        write(path, records)
    print(f"Staged {len(trips)} exact-date Ishizuchi trips, {len(stop_times)} printed passenger calls, and {len(relations)} reciprocal relation rows")


if __name__ == "__main__":
    main()
