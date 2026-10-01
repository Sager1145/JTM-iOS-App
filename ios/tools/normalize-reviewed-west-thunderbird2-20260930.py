#!/usr/bin/env python3
"""Stage dated Thunderbird 2 with current-N02 route-only line boundaries."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-thunderbird2-20260930"
DATE, UNTIL = "2026-09-30", "2026-10-01"
TRIP = "jr-west.thunderbird.2.2026-09-30"
SERVICE = "thunderbird"
TRAIN_SOURCE = "jr-west-odekake-thunderbird2-4002m-20260930"
LINE_SOURCE = "jr-west-thunderbird2-kosei-scope-20260930"
N02_SOURCE = "mlit-n02-2025-thunderbird2-20260930"
KOSEI_ID = "jp-西日本旅客鉄道-湖西線"
TOKAIDO_ID = "jp-西日本旅客鉄道-東海道線"
HOKURIKU_ID = "jp-西日本旅客鉄道-北陸線"
TRAIN_URL = "https://timetable.jr-odekake.net/train-timetable/257941?date=20260930"
EXPECTED = [
    ("敦賀", "010186", None, "07:05", "33", "origin"),
    ("近江今津", "004835", "07:28", "07:29", None, "passenger_stop"),
    ("堅田", "005626", "07:47", "07:47", None, "passenger_stop"),
    ("京都", "006079", "08:02", "08:04", "7", "passenger_stop"),
    ("新大阪", "006911", "08:29", "08:30", "10", "passenger_stop"),
    ("大阪", "007068", "08:34", None, "3", "destination"),
]
ROUTE_NODES = [
    ("敦賀", "010186"), ("近江塩津", "004400"),
    ("近江今津", "004835"), ("堅田", "005626"),
    ("山科", "006043"), ("京都", "006079"),
    ("新大阪", "006911"), ("大阪", "007068"),
]
ROUTE_LINE_IDS = [HOKURIKU_ID, KOSEI_ID, KOSEI_ID, KOSEI_ID,
                  TOKAIDO_ID, TOKAIDO_ID, TOKAIDO_ID]
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def rows(pattern: str, exclude: Path | None = None):
    for path in sorted(BASE.glob(pattern)):
        if not path.is_file() or path == exclude:
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                yield json.loads(line)


def write(path: Path, data: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in data),
        encoding="utf-8",
    )


def prepare() -> dict[Path, list[dict]]:
    candidate = json.loads((BASE / "candidates/jr-west-thunderbird2-20260930.json").read_text(encoding="utf-8"))
    source_path = BASE / f"sources/source-registry-{SUFFIX}.jsonl"
    sources = [json.loads(line) for line in source_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    source_by_id = {source["source_id"]: source for source in sources}
    if set(source_by_id) != {TRAIN_SOURCE, LINE_SOURCE, N02_SOURCE} or len(sources) != 3:
        raise ValueError("reviewed source set changed")
    if any(source["source_id"] in {row["source_id"] for row in rows("sources/source-registry*.jsonl", source_path)} for source in sources):
        raise ValueError("source id collides with another registry")
    if (source_by_id[TRAIN_SOURCE]["url_or_locator"], source_by_id[TRAIN_SOURCE]["effective_date"],
            source_by_id[TRAIN_SOURCE]["redistribution_status"],
            source_by_id[TRAIN_SOURCE]["automated_extraction_allowed"]) != (
            TRAIN_URL, DATE, "verification_only", False):
        raise ValueError("exact train source drift")
    if (source_by_id[LINE_SOURCE]["url_or_locator"],
            source_by_id[N02_SOURCE]["effective_date"]) != (
            "https://timetable.jr-odekake.net/station-timetable/2635014001?date=20260930",
            "2025-12-31"):
        raise ValueError("line evidence drift")

    trip = candidate["trip"]
    if (candidate["candidate_status"], candidate["canonical"],
            candidate["selected_service_date"], candidate["valid_until"],
            candidate["source_calendar_label"]) != (
            "visually_reviewed", False, DATE, UNTIL, "土曜・休日運休"):
        raise ValueError("candidate date/status drift")
    if DATE > json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))["as_of_date"]:
        raise ValueError("trip date exceeds canonical cutoff")
    if (trip["trip_id"], trip["service_id"], trip["public_number"],
            trip["train_number"], trip["origin"], trip["destination"],
            trip["train_source_id"], trip["train_source_url"],
            trip["route_source_ids"]) != (
            TRIP, SERVICE, "2", "4002M", "敦賀", "大阪",
            TRAIN_SOURCE, TRAIN_URL, [LINE_SOURCE, N02_SOURCE]):
        raise ValueError("trip identity or route scope drift")
    actual = [
        (row["name_snapshot"], row["current_source_code"], row["arrival_time"],
         row["departure_time"], row["platform"], row["call_type"])
        for row in trip["stop_times"]
    ]
    if actual != EXPECTED or [row["stop_sequence"] for row in trip["stop_times"]] != list(range(1, 7)):
        raise ValueError("printed passenger calls drift")
    if any(row["trip_id"] == TRIP for row in rows("normalized/trips/**/*.jsonl", BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")):
        raise ValueError("trip id already used")
    if not any(row["service_id"] == SERVICE and row["canonical_name"] == "サンダーバード"
               for row in rows("normalized/services*.jsonl")):
        raise ValueError("Thunderbird service identity missing")
    if any(row["trip_id"] == TRIP for row in rows("normalized/trip-lines/**/*.jsonl", BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl")):
        raise ValueError("trip route already exists")

    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    if package.get("version") != "2025.5.0":
        raise ValueError("N02 package version drift")
    lines = {line["id"]: line for line in package["lines"]}
    for leg_number, line_id in enumerate(ROUTE_LINE_IDS, 1):
        line = lines.get(line_id)
        if line is None or line["operator"] != "西日本旅客鉄道":
            raise ValueError(f"N02 line identity drift: {line_id}")
        left, right = ROUTE_NODES[leg_number - 1], ROUTE_NODES[leg_number]
        positions = [[i for i, station in enumerate(line["stations"])
                      if (station[0], station[1]) == (code, name)]
                     for name, code in (left, right)]
        if any(len(hits) != 1 for hits in positions) or positions[0][0] == positions[1][0]:
            raise ValueError(f"N02 station order missing: {line_id} {leg_number}")
    if [node for node in ROUTE_NODES if node in [(name, code) for name, code, *_ in EXPECTED]] != [(name, code) for name, code, *_ in EXPECTED]:
        raise ValueError("route chain changes passenger anchor order")
    for name, code in ROUTE_NODES:
        if not any(line["operator"] == "西日本旅客鉄道" and
                   any((station[0], station[1]) == (code, name) for station in line["stations"])
                   for line in package["lines"]):
            raise ValueError(f"N02 station identity missing: {name}")
    existing_stations = {
        row["station_id"]: row
        for row in rows("normalized/station-identities*.jsonl",
                        BASE / f"normalized/station-identities-{SUFFIX}.jsonl")
    }
    station_additions = []
    for name, code in ROUTE_NODES:
        station_id = "jp.n02." + code
        prior = existing_stations.get(station_id)
        if prior and (prior.get("name_snapshot"), prior.get("current_source_code")) != (name, code):
            raise ValueError(f"conflicting current station identity: {station_id}")
        if prior is None:
            station_additions.append({
                "station_id": station_id, "name_snapshot": name,
                "reference_kind": "current_n02", "current_source_code": code,
            })

    version, calendar = TRIP + ".version", TRIP + ".calendar"
    fact_state = {
        "identity": ("verified", "high", "Exact-date train page prints サンダーバード2号."),
        "train_number": ("verified", "high", "Exact-date train page prints 4002M."),
        "operator": ("unknown", "low", "Train-operation company segments are not independently dated."),
        "validity_calendar": ("verified", "high", "Only 2026-09-30 is materialized."),
        "origin_destination": ("verified", "high", "Both termini printed on the selected train page."),
        "stops": ("verified", "high", "Six timed calls retained; レ pass rows omitted."),
        "times": ("verified", "high", "Printed minute clocks and side blanks retained."),
        "route_lines": ("partial", "high", "Seven chained current-N02 segments use pass-through line boundaries; 2026-09-30 physical-line validity remains open."),
        "station_refs": ("verified", "high", "All calls match current N02 West station groups."),
        "provenance": ("partial", "medium", "Timetable page is verification-only."),
    }
    outputs = {
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": station_additions,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": [{
            "timetable_version_id": version, "operator_scope": "jr-west",
            "effective_from": DATE, "effective_until": UNTIL,
            "edition_name": "JR Odekake 2026-09-30 Thunderbird 2 selected timetable",
            "revision_type": "observed_date", "publication_date": None,
            "completeness": "partial", "source_ids": [TRAIN_SOURCE],
        }],
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": [{
            "calendar_id": calendar, "valid_from": DATE, "valid_until": UNTIL,
            "holiday_policy": "none", **{weekday: 0 for weekday in WEEKDAYS},
        }],
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": [{
            "calendar_id": calendar, "service_date": DATE, "exception_type": "add",
            "reason": "Selected exact date in official train page", "source_id": TRAIN_SOURCE,
        }],
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": [{
            "trip_id": TRIP, "timetable_version_id": version, "service_id": SERVICE,
            "calendar_id": calendar, "train_number": "4002M", "public_number": "2",
            "origin_station_id": "jp.n02.010186", "destination_station_id": "jp.n02.007068",
            "service_class": "limited_express",
            "notes": "Exact selected date; route has current-N02 identity only and daily physical validity remains open.",
        }],
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": [{
            "trip_id": TRIP, "stop_sequence": index, "station_id": "jp.n02." + code,
            "arrival_time": arrival, "departure_time": departure, "day_offset": 0,
            "call_type": kind, "pickup_allowed": int(kind != "destination"),
            "dropoff_allowed": int(kind != "origin"), "platform": platform,
            "time_accuracy": "minute", "source_id": TRAIN_SOURCE,
        } for index, (_, code, arrival, departure, platform, kind) in enumerate(EXPECTED, 1)],
        BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl": [{
            "trip_id": TRIP, "sequence": index,
            "from_station_id": "jp.n02." + left[1],
            "to_station_id": "jp.n02." + right[1],
            "line_name": lines[line_id]["name"], "operator_id": "jr-west",
            "reference_kind": "current_n02", "current_n02_line_id": line_id,
            "source_id": LINE_SOURCE if line_id == KOSEI_ID else TRAIN_SOURCE,
            "confidence": "high",
        } for index, (left, right, line_id) in enumerate(
            zip(ROUTE_NODES, ROUTE_NODES[1:], ROUTE_LINE_IDS), 1)],
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": [{
            "entity_type": "trip", "entity_id": TRIP, "dimension": dimension,
            "status": status, "confidence": confidence, "notes": note,
        } for dimension, (status, confidence, note) in fact_state.items()],
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": ([{
            "entity_type": "trip", "entity_id": TRIP, "field_name": dimension,
            "source_id": "jtm-current-station-directory" if dimension == "station_refs" else TRAIN_SOURCE,
            "page_or_locator": note, "confidence": confidence,
            "verification_status": status,
        } for dimension, (status, confidence, note) in fact_state.items()
            if dimension not in {"operator", "route_lines"}] + [{
            "entity_type": "trip", "entity_id": TRIP,
            "field_name": f"route_lines.segment.{index}.current_n02_identity",
            "source_id": source_id,
            "page_or_locator": (
                "Exact-date passenger calls and pass sequence, Tsuruga 湖西線 station scope, "
                "and current-N02 line membership; daily validity remains unverified."
            ),
            "confidence": "high", "verification_status": "partial",
        } for index, line_id in enumerate(ROUTE_LINE_IDS, 1)
          for source_id in ((TRAIN_SOURCE, LINE_SOURCE, N02_SOURCE)
                            if line_id == KOSEI_ID else (TRAIN_SOURCE, N02_SOURCE))]),
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": [{
            "research_id": f"{TRIP}.{dimension}", "entity_type": "trip", "entity_id": TRIP,
            "missing_dimension": dimension, "status": "license_blocked" if dimension == "provenance" else "open",
            "notes": note,
        } for dimension, note in {
            "operator": "Obtain independently dated train-operation company segments.",
            "route_lines": "Obtain 2026-09-30 physical-line validity for the 北陸線→湖西線→東海道線 chain; current N02 is a 2025-12-31 snapshot.",
            "provenance": "Resolve timetable-fact redistribution permission.",
        }.items()],
    }
    return outputs


def main() -> None:
    outputs = prepare()
    for path, data in outputs.items():
        write(path, data)
    print(f"Staged {TRIP}: 6 timed calls, 7 partial current-N02 segments, exact date only")


if __name__ == "__main__":
    main()
