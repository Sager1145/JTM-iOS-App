#!/usr/bin/env python3
"""Stage six exact-date JR Kyushu Yufuin-no-Mori trains and planned cars."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
DAY = "2026-09-30"
NEXT_DAY = "2026-10-01"
SUFFIX = "reviewed-kyushu-yufuin-six-20260930"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
SOURCE_FILE = BASE / "candidates/jr-kyushu-yufuin-no-mori-six-20260930.json"


def read_rows(pattern):
    for path in sorted(BASE.glob(pattern)):
        if SUFFIX in str(path):
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                yield json.loads(line)


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in records), encoding="utf-8")


def source_record(source, title, kind, note):
    return dict(source_id=source["source_id"], publisher="九州旅客鉄道株式会社",
                title=title, source_type=kind, url_or_locator=source["url_or_locator"],
                effective_date=DAY, accessed_at=DAY,
                license_status="no_reuse_grant_identified",
                redistribution_status="verification_only", automated_extraction_allowed=False,
                notes=note)


def main():
    candidate = json.loads(SOURCE_FILE.read_text(encoding="utf-8"))
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    if (candidate["service_date"] != DAY or DAY > manifest["as_of_date"] or
            len(candidate["trips"]) != 6 or
            {trip["public_number"] for trip in candidate["trips"]} !=
            {str(number) for number in range(1, 7)}):
        raise ValueError("Six complete exact-date Yufuin-no-Mori trips are required")
    pages = {row["public_number"]: row for row in candidate["train_pages"]}
    if len(pages) != 6:
        raise ValueError("Six train-specific official sources are required")
    prior_ids = {row["trip_id"] for row in read_rows("normalized/trips/*/*.jsonl")}
    prior_sources = {row["source_id"] for row in read_rows("sources/source-registry*.jsonl")}
    prior_stations = {row["station_id"]: row for row in read_rows("normalized/station-identities*.jsonl")}
    root_trips = {row["public_number"]: row for row in read_rows("normalized/trips/reviewed-root/seeds.jsonl")
                  if row["service_id"] == "yufuin-no-mori"}
    root_routes = list(read_rows("normalized/trip-lines/reviewed-root/seeds.jsonl"))
    root_operators = list(read_rows("normalized/trip-operator-segments/reviewed-root/seeds.jsonl"))
    existing_root_dates = {(row["calendar_id"], row["service_date"])
                           for row in read_rows("normalized/calendar-exceptions/reviewed-root/seeds.jsonl")}
    if len(root_trips) != 6 or len(root_routes) < 6 or len(root_operators) < 6:
        raise ValueError("The reviewed six-train route baseline is missing")
    for number, old in root_trips.items():
        if (old["calendar_id"], DAY) in existing_root_dates:
            raise ValueError(f"Old Yufuin-no-Mori {number} template remains active on {DAY}")

    names_to_id = {row["name_snapshot"]: row["station_id"] for row in prior_stations.values()}
    names_to_id["天ケ瀬"] = names_to_id["天ヶ瀬"]
    output = {name: [] for name in (
        "source-registry", "service-name-periods", "timetable-versions", "calendars", "calendar-exceptions",
        "trips", "stop-times", "trip-formations", "trip-formation-cars",
        "trip-operator-segments", "trip-lines", "fact-completeness", "fact-sources",
        "research-queue",
    )}
    for number in range(1, 7):
        key = str(number)
        trip = next(t for t in candidate["trips"] if t["public_number"] == key)
        page = pages[key]
        tid = f"jr-kyushu.yufuin-no-mori.{number}.{DAY}"
        if (trip["trip_id"] != tid or tid in prior_ids or trip["source_id"] != page["source_id"] or
                trip["train_number"] != f"800{number}D" or trip["service_date"] != DAY or
                trip["direction"] != ("down" if number % 2 else "up")):
            raise ValueError(f"Train identity changed for {number}")
        if page["source_id"] in prior_sources:
            raise ValueError(f"Duplicate source ID: {page['source_id']}")
        output["source-registry"].append(source_record(
            page, f"JR九州 ゆふいんの森{number}号 2026年9月30日 時刻詳細",
            "official_train_timetable", "Exact date selected; train number and all passenger rows reviewed."))
        calls = trip["stop_times"]
        if len(calls) != (9 if number in (3, 4) else 7):
            raise ValueError(f"Unexpected stop count for {number}")
        station_ids = [names_to_id[row[0]] for row in calls]
        old_stations = [s["station_id"] for s in read_rows("normalized/stop-times/reviewed-root/seeds.jsonl")
                        if s["trip_id"] == root_trips[key]["trip_id"]]
        if station_ids != old_stations:
            raise ValueError(f"Reviewed station order differs from source template for {number}")
        version_id, calendar_id = tid + ".version", tid + ".calendar"
        output["timetable-versions"].append(dict(
            timetable_version_id=version_id, operator_scope="jr-kyushu",
            effective_from=DAY, effective_until=NEXT_DAY,
            edition_name="JR時刻表2026年10月号 exact 2026-09-30 train detail",
            revision_type="source_snapshot", completeness="partial",
            source_ids=[page["source_id"], "jr-kyushu-yufuin-20260930-calendar"]))
        output["calendars"].append(dict(calendar_id=calendar_id, valid_from=DAY,
            valid_until=NEXT_DAY, holiday_policy="none", **{day: 0 for day in WEEKDAYS}))
        output["calendar-exceptions"].append(dict(calendar_id=calendar_id, service_date=DAY,
            exception_type="add", source_id=page["source_id"],
            reason="Train-specific official date selection and operating calendar"))
        output["trips"].append(dict(trip_id=tid, timetable_version_id=version_id,
            service_id="yufuin-no-mori", calendar_id=calendar_id,
            train_number=trip["train_number"], public_number=key,
            origin_station_id=station_ids[0], destination_station_id=station_ids[-1],
            service_class="limited_express", direction=trip["direction"],
            notes="One exact-date official passenger train; planned formation may be substituted."))
        for sequence, ((name, arrival, departure, platform), station_id) in enumerate(zip(calls, station_ids), 1):
            call_type = "origin" if sequence == 1 else "destination" if sequence == len(calls) else "passenger_stop"
            output["stop-times"].append(dict(trip_id=tid, stop_sequence=sequence,
                station_id=station_id, arrival_time=arrival, departure_time=departure,
                day_offset=0, call_type=call_type, pickup_allowed=int(call_type != "destination"),
                dropoff_allowed=int(call_type != "origin"), platform=platform,
                time_accuracy="minute", source_id=page["source_id"]))
        old_id = root_trips[key]["trip_id"]
        output["trip-operator-segments"].extend(
            {**row, "trip_id": tid} for row in root_operators if row["trip_id"] == old_id)
        output["trip-lines"].extend(
            {**row, "trip_id": tid} for row in root_routes if row["trip_id"] == old_id)
        label = trip["formation_label"]
        if label != ("I世" if number in (3, 4) else "III世"):
            raise ValueError(f"Unexpected formation assignment for {number}")
        car_count = 4 if label == "I世" else 5
        formation_id = tid + ".formation." + DAY
        output["trip-formations"].append(dict(formation_id=formation_id, trip_id=tid,
            service_date=DAY, evidence_kind="planned", formation_label=label,
            car_count=car_count, all_reserved=True,
            source_id="jr-kyushu-yufuin-20260930-calendar",
            notes="Official September 30 operation plan and car diagram; actual dispatch may change."))
        car_numbers = list(range(car_count, 0, -1)) if number % 2 else list(range(1, car_count + 1))
        car_source = "jr-kyushu-yufuin-formation-i" if label == "I世" else "jr-kyushu-yufuin-formation-iii"
        for sequence, car_number in enumerate(car_numbers, 1):
            output["trip-formation-cars"].append(dict(formation_id=formation_id,
                car_sequence=sequence, car_number=str(car_number), seat_class="ordinary",
                reservation_type="reserved", source_id=car_source,
                notes="Buffet car" if car_number == (2 if label == "I世" else 3) else None))
        dimensions = {
            "identity": ("verified", "high"), "train_number": ("verified", "high"),
            "operator": ("verified", "high"), "validity_calendar": ("verified", "high"),
            "origin_destination": ("verified", "high"), "stops": ("verified", "high"),
            "times": ("verified", "high"), "route_lines": ("partial", "high"),
            "station_refs": ("verified", "high"), "provenance": ("partial", "medium"),
            "formation": ("partial", "high"),
        }
        for dimension, (status, confidence) in dimensions.items():
            output["fact-completeness"].append(dict(entity_type="trip", entity_id=tid,
                dimension=dimension, status=status, confidence=confidence,
                notes="Exact-date train page and reviewed current station/route references; formation is planned."))
            if status == "verified":
                source_id = ("jtm-current-station-directory" if dimension == "station_refs" else
                             "jr-kyushu-route-map-202601" if dimension == "operator" else page["source_id"])
                output["fact-sources"].append(dict(entity_type="trip", entity_id=tid,
                    field_name=dimension, source_id=source_id,
                    page_or_locator=page["locator"], confidence=confidence,
                    verification_status=status))
            elif dimension in ("route_lines", "provenance"):
                output["research-queue"].append(dict(research_id=tid + "." + dimension,
                    entity_type="trip", entity_id=tid, missing_dimension=dimension,
                    status="open", notes="Dated physical-line validity or reuse permission remains unresolved."))
        output["research-queue"].append(dict(research_id=tid + ".formation",
            entity_type="trip", entity_id=tid, missing_dimension="formation",
            status="open", notes="The calendar and diagrams establish the planned cars, not actual dispatch."))
        output["fact-sources"].append(dict(entity_type="trip", entity_id=tid,
            field_name="formation.planned", source_id="jr-kyushu-yufuin-20260930-calendar",
            page_or_locator="September 30 all-six yellow calendar; I世 3/4, III世 1/2/5/6",
            confidence="high", verification_status="partial"))
    for source in candidate["formation_sources"]:
        if source["source_id"] in prior_sources:
            raise ValueError(f"Duplicate formation source: {source['source_id']}")
        output["source-registry"].append(source_record(
            source, "JR九州 ゆふいんの森 運転カレンダー・編成図",
            "official_formation_calendar" if "calendar" in source["source_id"] else "official_car_diagram",
            source["locator"]))
    output["service-name-periods"].append(dict(
        service_id="yufuin-no-mori", name="ゆふいんの森", language="ja",
        valid_from=DAY, valid_until=NEXT_DAY, name_type="display",
        source_id=pages["1"]["source_id"]))
    paths = {
        "source-registry": BASE / f"sources/source-registry-{SUFFIX}.jsonl",
        "service-name-periods": BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl",
        "timetable-versions": BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl",
        "calendars": BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl",
        "calendar-exceptions": BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl",
        "trips": BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl",
        "stop-times": BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl",
        "trip-formations": BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl",
        "trip-formation-cars": BASE / f"normalized/trip-formation-cars/{SUFFIX}/seeds.jsonl",
        "trip-operator-segments": BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl",
        "trip-lines": BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl",
        "fact-completeness": BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl",
        "fact-sources": BASE / f"normalized/fact-sources-{SUFFIX}.jsonl",
        "research-queue": BASE / f"normalized/research-queue-{SUFFIX}.jsonl",
    }
    for kind, path in paths.items():
        write(path, output[kind])
    print(f"Staged six exact-date trips, {len(output['stop-times'])} calls and "
          f"{len(output['trip-formation-cars'])} planned cars")


if __name__ == "__main__":
    main()
