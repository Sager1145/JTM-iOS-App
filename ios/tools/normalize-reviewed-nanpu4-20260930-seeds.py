#!/usr/bin/env python3
"""Promote one exact-date, manually reviewed Nanpu 4 train page."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-shikoku-nanpu4-20260930.json"
SUFFIX = "reviewed-nanpu4-20260930"
STATION_SOURCE = "jtm-current-station-directory"
EXPECTED_URLS = {
    "jr-odekake-nanpu4-20260930-train": "https://timetable.jr-odekake.net/train-timetable/59421?date=20260930",
    "jr-odekake-nanpu4-20260930-line": "https://timetable.jr-odekake.net/line-timetable/2473?day=30&month=9&year=2026",
}
EXPECTED_STOPS = [
    ("高知", None, "07:00"), ("後免", "07:07", "07:07"),
    ("土佐山田", "07:11", "07:12"), ("大杉", "07:31", "07:32"),
    ("大歩危", "07:50", "07:52"), ("阿波池田", "08:11", "08:13"),
    ("琴平", "08:39", "08:40"), ("善通寺", "08:44", "08:45"),
    ("多度津", "08:50", "08:51"), ("丸亀", "08:55", "08:55"),
    ("宇多津", "08:59", "09:00"), ("児島", "09:14", "09:15"),
    ("岡山", "09:38", None),
]


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in rows), encoding="utf-8")


def other_rows(pattern, target):
    return [json.loads(line) for path in sorted((BASE / "normalized").glob(pattern))
            if path.resolve() != target.resolve()
            for line in path.read_text(encoding="utf-8").splitlines() if line]


def resolve_stations(stops):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    result = {}
    for stop in stops:
        name = stop["name_snapshot"]
        codes = {station[0] for line in package["lines"]
                 if line["operator"] in {"四国旅客鉄道", "西日本旅客鉄道"}
                 for station in line["stations"] if station[1] == name}
        if len(codes) != 1:
            raise ValueError(f"Station {name} must resolve to one current group: {sorted(codes)}")
        code = next(iter(codes))
        result[name] = dict(station_id="jp.n02." + code, name_snapshot=name,
                            reference_kind="current_n02", current_source_code=code,
                            rail_history_id=None)
    target = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    existing = {row["station_id"]: row for row in other_rows("station-identities*.jsonl", target)}
    additions = []
    for station in result.values():
        prior = existing.get(station["station_id"])
        if prior and prior["name_snapshot"] != station["name_snapshot"]:
            raise ValueError(f"Station identity conflict for {station['station_id']}")
        if not prior:
            additions.append(station)
    return result, sorted(additions, key=lambda row: row["station_id"])


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    trip = candidate["trip"]
    date = trip["service_date"]
    if (candidate["candidate_status"], date, trip["trip_id"], trip["service_id"],
            trip["public_number"], trip["train_number"]) != (
            "reviewed_official_html", "2026-09-30", "jr-shikoku.nanpu.4.2026-09-30",
            "nanpu", "4", "34D"):
        raise ValueError("Reviewed Nanpu 4 identity/date changed")
    if date > json.loads((BASE / "manifest.json").read_text())["as_of_date"]:
        raise ValueError("Nanpu date exceeds the database cutoff")
    sources = candidate["sources"]
    if {row["source_id"]: row["url_or_locator"] for row in sources} != EXPECTED_URLS:
        raise ValueError("Reviewed exact-date source URLs changed")
    if any(row["automated_extraction_allowed"] is not False for row in sources):
        raise ValueError("Unreviewed source-extraction permission")
    stops = trip["stop_times"]
    if [(row["name_snapshot"], row["arrival_time"], row["departure_time"])
            for row in stops] != EXPECTED_STOPS:
        raise ValueError("Reviewed complete Nanpu 4 passenger-call matrix changed")
    stations, new_stations = resolve_stations(stops)
    service_target = BASE / f"normalized/services-{SUFFIX}.jsonl"
    existing_services = {row["service_id"]: row for row in other_rows("services*.jsonl", service_target)}
    prior_service = existing_services.get("nanpu")
    if prior_service and prior_service["canonical_name"] != "南風":
        raise ValueError("Nanpu service identity conflict")
    service_rows = [] if prior_service else [dict(
        service_id="nanpu", canonical_name="南風", service_class="limited_express",
        historical_generation=1, first_verified_date=date, last_verified_date=date,
        jr_scope="jr")]

    trip_id = trip["trip_id"]
    version_id, calendar_id = trip_id + ".version", trip_id + ".calendar"
    train_source, line_source = tuple(EXPECTED_URLS)
    dimensions = {
        "identity": ("verified", "high", "Exact-date train page prints 南風4号."),
        "train_number": ("verified", "high", "Exact-date train page and line grid print 34D."),
        "operator": ("unknown", "low", "Publisher alone does not prove ordered operator segments."),
        "validity_calendar": ("verified", "high", "Dated line grid directly lists the train on 2026-09-30."),
        "origin_destination": ("verified", "high", "Train page prints the first and last timed passenger calls."),
        "stops": ("verified", "high", "13 passenger calls are transcribed; レ pass rows excluded."),
        "times": ("verified", "high", "Published minute clocks and their arrival/departure sides are retained."),
        "route_lines": ("unknown", "low", "No ordered dated physical-line identity evidence promoted."),
        "station_refs": ("verified", "high", "Names uniquely match current JR station groups."),
        "provenance": ("partial", "medium", "Official pages are verification-only; redistribution grant unresolved."),
    }
    outputs = {
        BASE / f"sources/source-registry-{SUFFIX}.jsonl": sources,
        service_target: service_rows,
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl": [],
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": [dict(
            timetable_version_id=version_id, operator_scope="jr-shikoku",
            effective_from=date, effective_until="2026-10-01",
            edition_name="JR時刻表2026年10月号; exact-date 南風4号",
            revision_type="source_snapshot", completeness="partial",
            source_ids=[train_source, line_source])],
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": new_stations,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": [dict(
            calendar_id=calendar_id, valid_from=date, valid_until="2026-10-01",
            holiday_policy="none", **{day: 0 for day in
                ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")})],
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": [dict(
            calendar_id=calendar_id, service_date=date, exception_type="add",
            reason="Exact-date official 土讃線 grid shows 南風4号 34D", source_id=line_source)],
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": [dict(
            trip_id=trip_id, timetable_version_id=version_id, service_id="nanpu",
            calendar_id=calendar_id, train_number="34D", public_number="4",
            origin_station_id=stations[stops[0]["name_snapshot"]]["station_id"],
            destination_station_id=stations[stops[-1]["name_snapshot"]]["station_id"],
            service_class="limited_express",
            notes="Exact-date train page: all 13 passenger calls; physical lines and operator boundaries unverified.")],
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": [dict(
            trip_id=trip_id, stop_sequence=index,
            station_id=stations[row["name_snapshot"]]["station_id"],
            arrival_time=row["arrival_time"], departure_time=row["departure_time"],
            day_offset=0, call_type=("origin" if index == 1 else
                "destination" if index == len(stops) else "passenger_stop"),
            pickup_allowed=0 if index == len(stops) else 1,
            dropoff_allowed=0 if index == 1 else 1,
            platform=row["platform"], time_accuracy="minute", source_id=train_source)
            for index, row in enumerate(stops, 1)],
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": [dict(
            entity_type="trip", entity_id=trip_id, dimension=dimension,
            status=status, confidence=confidence, notes=notes)
            for dimension, (status, confidence, notes) in dimensions.items()],
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": [dict(
            entity_type="trip", entity_id=trip_id, field_name=field,
            source_id=(line_source if field == "validity_calendar" else
                STATION_SOURCE if field == "station_refs" else train_source),
            page_or_locator=("Dated line-grid 34D column" if field == "validity_calendar" else
                "Current JR station group in jp-2025.json" if field == "station_refs" else
                "Exact-date train-detail table"), confidence="high", verification_status="verified")
            for field in ("identity", "train_number", "validity_calendar",
                          "origin_destination", "stops", "times", "station_refs")],
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": [dict(
            research_id=f"{trip_id}.{dimension}", entity_type="trip", entity_id=trip_id,
            missing_dimension=dimension, status=("license_blocked" if dimension == "provenance" else "open"),
            notes=notes) for dimension, notes in {
                "operator": "Obtain explicit ordered JR Shikoku / JR West operator-boundary evidence.",
                "route_lines": "Obtain dated ordered physical line identities and historical applicability.",
                "provenance": "Resolve permission to redistribute transcribed official timetable facts.",
            }.items()],
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)
    print(f"Normalized one exact-date Nanpu 4 trip, {len(stops)} passenger calls, two official sources")


if __name__ == "__main__":
    main()
