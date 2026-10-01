#!/usr/bin/env python3
"""Stage the reviewed 52D / 宗谷 column for 2026-09-30 only."""

import json
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "hokkaido-soya52d-20260930"
CANDIDATE = BASE / "candidates/jr-hokkaido-soya52d-20260930.json"
DAY = "2026-09-30"
NEXT_DAY = "2026-10-01"
SOURCE_URL = "https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111"
TRIP_ID = "jr-hokkaido.soya.52d.exact-2026-09-30"
SOURCE_ID = "jr-hokkaido-soya52d-20260930"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def validate(candidate):
    if candidate["candidate_status"] != "visually_reviewed" or candidate["canonical"] is not False:
        raise ValueError("Review or staging status changed")
    trip = candidate["trip"]
    expected = (TRIP_ID, DAY, "soya", None, "52D", SOURCE_ID, SOURCE_URL)
    actual = tuple(trip[key] for key in (
        "trip_id", "service_date", "service_id", "public_number", "train_number", "source_id", "source_url"
    ))
    if actual != expected:
        raise ValueError("Exact-date train/source identity changed")
    stops = trip["stops"]
    if len(stops) != 15 or stops[0] != ["稚内", None, "17:44"] or stops[-1] != ["札幌", "22:56", None]:
        raise ValueError("Reviewed stop endpoints or count changed")
    if stops[10] != ["旭川", "21:26", "21:30"] or {row[0] for row in stops} & {"比布", "剣淵", "砂川", "美唄"}:
        raise ValueError("Asahikawa dwell or pass-through classification changed")
    previous = None
    for name, arrival, departure in stops:
        for clock in (arrival, departure):
            if clock is None:
                continue
            parsed = datetime.strptime(clock, "%H:%M")
            if previous is not None and parsed < previous:
                raise ValueError(f"Clock reversal at {name}")
            previous = parsed
    return trip


def resolve_stations(names):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    result = {}
    for name in names:
        codes = {
            station[0] for line in package["lines"] if line["operator"] == "北海道旅客鉄道"
            for station in line["stations"] if station[1] == name
        }
        if len(codes) != 1:
            raise ValueError(f"Expected one JR Hokkaido station group for {name}: {sorted(codes)}")
        result[name] = "jp.n02." + next(iter(codes))
    return result


def main():
    trip = validate(json.loads(CANDIDATE.read_text(encoding="utf-8")))
    if DAY > json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))["as_of_date"]:
        raise ValueError("Service day exceeds as-of date")
    service_path = BASE / "normalized/services-hokkaido-soya51d-20260930.jsonl"
    service_rows = [json.loads(line) for line in service_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(service_rows) != 1 or service_rows[0]["service_id"] != "soya" or service_rows[0]["last_verified_date"] != DAY:
        raise ValueError("Run the source-pinned 51D normalizer first to register the Soya service")
    stations = resolve_stations({stop[0] for stop in trip["stops"]})
    known_station_ids = {
        json.loads(line)["station_id"]
        for path in (BASE / "normalized").glob("station-identities*.jsonl")
        if path.name != f"station-identities-{SUFFIX}.jsonl"
        for line in path.read_text(encoding="utf-8").splitlines() if line.strip()
    }
    station_rows = [
        {"station_id": sid, "name_snapshot": name, "reference_kind": "current_n02",
         "current_source_code": sid.removeprefix("jp.n02."), "rail_history_id": None}
        for name, sid in sorted(stations.items()) if sid not in known_station_ids
    ]
    version_id = TRIP_ID + ".version"
    calendar_id = TRIP_ID + ".calendar"
    stop_rows = []
    for sequence, (name, arrival, departure) in enumerate(trip["stops"], 1):
        call_type = "origin" if sequence == 1 else "destination" if sequence == 15 else "passenger_stop"
        stop_rows.append({
            "trip_id": TRIP_ID, "stop_sequence": sequence, "station_id": stations[name],
            "arrival_time": arrival, "departure_time": departure, "day_offset": 0,
            "call_type": call_type, "pickup_allowed": 0 if call_type == "destination" else 1,
            "dropoff_allowed": 0 if call_type == "origin" else 1,
            "platform": None, "time_accuracy": "minute", "source_id": SOURCE_ID,
        })
    dimension_status = {
        "identity": ("verified", "high", "Official 52D / 宗谷 train column; public number blank."),
        "train_number": ("verified", "high", "Official column prints 52D."),
        "validity_calendar": ("verified", "high", "Official selector is 2026-09-30."),
        "origin_destination": ("verified", "high", "First and last timed passenger calls are printed."),
        "stops": ("verified", "high", "All printed calls captured; 剣淵, 比布, 砂川 and 美唄 are レ pass-throughs."),
        "times": ("partial", "medium", "Every printed clock captured; unprinted intermediate arrival sides remain unknown."),
        "station_refs": ("verified", "high", "Names resolve to current JR Hokkaido N02 station groups."),
        "operator": ("unknown", "low", "No dated operator-segment proof."),
        "route_lines": ("unknown", "low", "No ordered physical line IDs."),
        "provenance": ("partial", "medium", "Official URL pinned; reuse grant unconfirmed."),
    }
    completeness = [
        {"entity_type": "trip", "entity_id": TRIP_ID, "dimension": dimension,
         "status": status, "confidence": confidence, "notes": note}
        for dimension, (status, confidence, note) in dimension_status.items()
    ]
    facts = [
        {"entity_type": "trip", "entity_id": TRIP_ID, "field_name": dimension,
         "source_id": "jtm-current-station-directory" if dimension == "station_refs" else SOURCE_ID,
         "page_or_locator": "app/public/rail/jp-2025.json" if dimension == "station_refs" else trip["source_locator"],
         "confidence": confidence, "verification_status": status}
        for dimension, (status, confidence, _) in dimension_status.items()
        if status in ("verified", "partial") and dimension != "provenance"
    ]
    queue = [
        {"research_id": f"{TRIP_ID}.{dimension}", "entity_type": "trip", "entity_id": TRIP_ID,
         "missing_dimension": dimension, "status": "open", "notes": note}
        for dimension, (_, _, note) in dimension_status.items()
        if dimension in ("times", "operator", "route_lines", "provenance")
    ]
    outputs = {
        BASE / f"sources/source-registry-{SUFFIX}.jsonl": [{
            "source_id": SOURCE_ID, "publisher": "北海道旅客鉄道株式会社 / 株式会社交通新聞社",
            "title": "［特急］宗谷 上り 2026年9月30日 52D 列（号数空欄）",
            "source_type": "official_timetable", "url_or_locator": SOURCE_URL,
            "issue": "JR時刻表 令和8年10月号", "publication_date": None,
            "effective_date": DAY, "accessed_at": DAY,
            "license_status": "terms_published_no_reuse_grant_identified",
            "redistribution_status": "verification_only", "automated_extraction_allowed": False,
            "notes": "Visually reviewed selected date and 52D column only. Site prohibits unauthorized reproduction or processing.",
        }],
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": [{
            "timetable_version_id": version_id, "operator_scope": "jr-hokkaido",
            "effective_from": DAY, "effective_until": NEXT_DAY,
            "edition_name": "JR時刻表 令和8年10月号; selected exact 2026-09-30 column",
            "revision_type": "source_snapshot", "completeness": "partial", "source_ids": [SOURCE_ID],
        }],
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": station_rows,
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": [{
            "trip_id": TRIP_ID, "timetable_version_id": version_id, "service_id": "soya",
            "calendar_id": calendar_id, "train_number": "52D", "public_number": None,
            "origin_station_id": stations["稚内"], "destination_station_id": stations["札幌"],
            "service_class": "limited_express",
            "notes": "Exact-date official column only; unprinted arrival sides and physical line/operator segments remain unknown.",
        }],
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stop_rows,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": [{
            "calendar_id": calendar_id, "valid_from": DAY, "valid_until": NEXT_DAY,
            "holiday_policy": "none", **{weekday: 0 for weekday in WEEKDAYS},
        }],
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": [{
            "calendar_id": calendar_id, "service_date": DAY, "exception_type": "add",
            "reason": "Exact selected date on operator timetable", "source_id": SOURCE_ID,
        }],
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": completeness,
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": facts,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": queue,
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)
    print(f"Staged {TRIP_ID}: {len(stop_rows)} printed passenger calls")


if __name__ == "__main__":
    main()
