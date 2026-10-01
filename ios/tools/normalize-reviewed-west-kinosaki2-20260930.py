#!/usr/bin/env python3
"""Stage one dated Kinosaki 2 trip with partial current-N02 route evidence."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "west-kinosaki2-20260930"
DATE, UNTIL = "2026-09-30", "2026-10-01"
TRIP = "jr-west.kinosaki.2.2026-09-30"
SERVICE = "kinosaki"
TRAIN_SOURCE = "jr-west-odekake-kinosaki2-5002m-20260930"
LINE_SOURCE = "jr-west-kinosaki2-sanin-scope-20260930"
N02_SOURCE = "mlit-n02-2025-kinosaki2-20260930"
LINE_ID = "jp-西日本旅客鉄道-山陰線"
TRAIN_URL = "https://timetable.jr-odekake.net/train-timetable/90831?date=20260930"
EXPECTED = [
    ("福知山", "005124", None, "06:02", "1", "origin"),
    ("綾部", "005106", "06:11", "06:12", "2", "passenger_stop"),
    ("日吉", "005489", "06:41", "06:41", None, "passenger_stop"),
    ("園部", "005695", "06:48", "06:49", "2", "passenger_stop"),
    ("亀岡", "005925", "07:00", "07:00", None, "passenger_stop"),
    ("二条", "005949", "07:12", "07:13", None, "passenger_stop"),
    ("京都", "006079", "07:18", None, "30", "destination"),
]
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
    candidate = json.loads((BASE / "candidates/jr-west-kinosaki2-20260930.json").read_text(encoding="utf-8"))
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
            "https://www.jr-odekake.net/ticket/guide/ebook/pages/pageindices/index15.html",
            "2025-12-31"):
        raise ValueError("line evidence drift")

    trip = candidate["trip"]
    if (candidate["candidate_status"], candidate["canonical"],
            candidate["selected_service_date"], candidate["valid_until"],
            candidate["source_calendar_label"]) != (
            "visually_reviewed", False, DATE, UNTIL, "毎日運転"):
        raise ValueError("candidate date/status drift")
    if DATE > json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))["as_of_date"]:
        raise ValueError("trip date exceeds canonical cutoff")
    if (trip["trip_id"], trip["service_id"], trip["public_number"],
            trip["train_number"], trip["origin"], trip["destination"],
            trip["train_source_id"], trip["train_source_url"],
            trip["route_current_n02_line_id"], trip["route_source_ids"]) != (
            TRIP, SERVICE, "2", "5002M", "福知山", "京都",
            TRAIN_SOURCE, TRAIN_URL, LINE_ID, [LINE_SOURCE, N02_SOURCE]):
        raise ValueError("trip identity or route scope drift")
    actual = [
        (row["name_snapshot"], row["current_source_code"], row["arrival_time"],
         row["departure_time"], row["platform"], row["call_type"])
        for row in trip["stop_times"]
    ]
    if actual != EXPECTED or [row["stop_sequence"] for row in trip["stop_times"]] != list(range(1, 8)):
        raise ValueError("printed passenger calls drift")
    if any(row["trip_id"] == TRIP for row in rows("normalized/trips/**/*.jsonl", BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")):
        raise ValueError("trip id already used")
    if not any(row["service_id"] == SERVICE and row["canonical_name"] == "きのさき"
               for row in rows("normalized/services*.jsonl")):
        raise ValueError("Kinosaki service identity missing")
    if any(row["trip_id"] == TRIP for row in rows("normalized/trip-lines/**/*.jsonl", BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl")):
        raise ValueError("trip route already exists")

    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    if package.get("version") != "2025.5.0":
        raise ValueError("N02 package version drift")
    matched = [line for line in package["lines"] if line["id"] == LINE_ID]
    if len(matched) != 1 or (matched[0]["name"], matched[0]["operator"]) != (
            "山陰線", "西日本旅客鉄道"):
        raise ValueError("N02 line identity drift")
    ordered_stations = matched[0]["stations"]
    positions = []
    for name, code, *_ in EXPECTED:
        hits = [index for index, station in enumerate(ordered_stations)
                if (station[0], station[1]) == (code, name)]
        if len(hits) != 1:
            raise ValueError(f"N02 station identity missing or ambiguous: {name}")
        positions.append(hits[0])
    if not all(a < b for a, b in zip(positions, positions[1:])):
        raise ValueError("N02 Sanin station order changed")
    existing_stations = {
        row["station_id"]: row
        for row in rows("normalized/station-identities*.jsonl",
                        BASE / f"normalized/station-identities-{SUFFIX}.jsonl")
    }
    station_additions = []
    for name, code, *_ in EXPECTED:
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
        "identity": ("verified", "high", "Exact-date train page prints きのさき2号."),
        "train_number": ("verified", "high", "Exact-date train page prints 5002M."),
        "operator": ("unknown", "low", "Train-operation company segments are not independently dated."),
        "validity_calendar": ("verified", "high", "Only 2026-09-30 is materialized."),
        "origin_destination": ("verified", "high", "Both termini printed on the selected train page."),
        "stops": ("verified", "high", "Seven timed calls retained; レ pass rows omitted."),
        "times": ("verified", "high", "Printed minute clocks and side blanks retained."),
        "route_lines": ("partial", "high", "Six passenger legs match current N02 山陰線; 2026-09-30 physical-line validity is unverified."),
        "station_refs": ("verified", "high", "All calls match ordered current N02 station groups."),
        "provenance": ("partial", "medium", "Timetable page is verification-only."),
    }
    outputs = {
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": station_additions,
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": [{
            "timetable_version_id": version, "operator_scope": "jr-west",
            "effective_from": DATE, "effective_until": UNTIL,
            "edition_name": "JR Odekake 2026-09-30 Kinosaki 2 selected timetable",
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
            "calendar_id": calendar, "train_number": "5002M", "public_number": "2",
            "origin_station_id": "jp.n02.005124", "destination_station_id": "jp.n02.006079",
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
            "line_name": "山陰線", "operator_id": "jr-west",
            "reference_kind": "current_n02", "current_n02_line_id": LINE_ID,
            "source_id": LINE_SOURCE, "confidence": "high",
        } for index, (left, right) in enumerate(zip(EXPECTED, EXPECTED[1:]), 1)],
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
                "Exact-date passenger calls, official 山陰本線 route scope, and ordered "
                "current-N02 station membership; daily line validity remains unverified."
            ),
            "confidence": "high", "verification_status": "partial",
        } for index in range(1, 7) for source_id in (TRAIN_SOURCE, LINE_SOURCE, N02_SOURCE)]),
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": [{
            "research_id": f"{TRIP}.{dimension}", "entity_type": "trip", "entity_id": TRIP,
            "missing_dimension": dimension, "status": "license_blocked" if dimension == "provenance" else "open",
            "notes": note,
        } for dimension, note in {
            "operator": "Obtain independently dated train-operation company segments.",
            "route_lines": "Obtain a physical-line validity interval covering 2026-09-30; current N02 is only a 2025-12-31 snapshot.",
            "provenance": "Resolve timetable-fact redistribution permission.",
        }.items()],
    }
    return outputs


def main() -> None:
    outputs = prepare()
    for path, data in outputs.items():
        write(path, data)
    print(f"Staged {TRIP}: 7 timed calls, 6 partial current-N02 segments, exact date only")


if __name__ == "__main__":
    main()
