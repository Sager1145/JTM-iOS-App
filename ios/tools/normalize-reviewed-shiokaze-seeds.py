#!/usr/bin/env python3
"""Normalize the exact-date reviewed Shiokaze 5-28 Obon timetables."""

from collections import defaultdict
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-shikoku-shiokaze-obon-2026-full-timetables.json"
SOURCE_REGISTRY = BASE / "sources/source-registry-shiokaze.jsonl"
ANNOUNCEMENT_SOURCE = "jr-shikoku-west-shiokaze-obon-20260624"
STATION_SOURCE = "jtm-current-station-directory"
DATES = ["2026-08-08", "2026-08-09", "2026-08-15", "2026-08-16"]
STATION_OPERATORS = {
    "岡山": "西日本旅客鉄道", "児島": "西日本旅客鉄道",
    "宇多津": "四国旅客鉄道", "丸亀": "四国旅客鉄道",
    "多度津": "四国旅客鉄道", "詫間": "四国旅客鉄道",
    "高瀬": "四国旅客鉄道", "観音寺": "四国旅客鉄道",
    "川之江": "四国旅客鉄道", "伊予三島": "四国旅客鉄道",
    "新居浜": "四国旅客鉄道", "伊予西条": "四国旅客鉄道",
    "壬生川": "四国旅客鉄道", "今治": "四国旅客鉄道",
    "伊予北条": "四国旅客鉄道", "松山": "四国旅客鉄道",
}


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def train_source_id(number, day):
    return f"jr-odekake-shiokaze-{number}m-{day.replace('-', '')}-special"


def train_url(candidate, trip, day):
    return candidate["url_template"].format(
        page_id=trip["page_id"], yyyymmdd=day.replace("-", "")
    )


def load_and_validate_candidate():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    if candidate["candidate_status"] != "reviewed_official_html":
        raise ValueError("Shiokaze candidate has not completed official HTML review")
    evidence = candidate["evidence_interpretation"]
    if evidence["special_dates"] != DATES:
        raise ValueError(f"Unexpected special dates: {evidence['special_dates']}")
    expected_numbers = {str(number) for number in range(5, 29)}
    if set(candidate["trips"]) != expected_numbers:
        raise ValueError("Shiokaze candidate must contain exactly public numbers 5 through 28")

    for number in range(5, 29):
        public_number = str(number)
        trip = candidate["trips"][public_number]
        expected_direction = "down" if number % 2 else "up"
        if trip["direction"] != expected_direction:
            raise ValueError(f"Shiokaze {number}: unexpected direction")
        if trip["train_number"] != f"{number}M":
            raise ValueError(f"Shiokaze {number}: unexpected train number")
        calls = trip["passenger_calls"]
        expected_endpoints = ("岡山", "松山") if expected_direction == "down" else ("松山", "岡山")
        if (calls[0][0], calls[-1][0]) != expected_endpoints:
            raise ValueError(f"Shiokaze {number}: unexpected endpoints")
        if len(calls) + trip["omitted_pass_row_count"] != 59:
            raise ValueError(f"Shiokaze {number}: reviewed call/pass rows do not total 59")
        if calls[0][1] or not calls[0][2] or not calls[-1][1] or calls[-1][2]:
            raise ValueError(f"Shiokaze {number}: origin/destination clocks are malformed")
        for call in calls:
            if len(call) != 4 or call[0] not in STATION_OPERATORS:
                raise ValueError(f"Shiokaze {number}: malformed passenger call {call}")
        for day in DATES:
            url = train_url(candidate, trip, day)
            if f"date={day.replace('-', '')}" not in url:
                raise ValueError(f"Shiokaze {number}: exact date missing from URL")
    return candidate


def resolve_station_ids(candidate):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    used_names = {
        call[0]
        for trip in candidate["trips"].values()
        for call in trip["passenger_calls"]
    }
    station_ids = {}
    station_rows = []
    for name in STATION_OPERATORS:
        if name not in used_names:
            continue
        operator = STATION_OPERATORS[name]
        codes = {
            station[0]
            for line in package["lines"]
            if line["operator"] == operator
            for station in line["stations"]
            if station[1] == name
        }
        if len(codes) != 1:
            raise ValueError(f"Ambiguous station identity: {name} ({operator}): {codes}")
        code = codes.pop()
        station_ids[name] = "jp.n02." + code
        station_rows.append({
            "station_id": station_ids[name], "name_snapshot": name,
            "reference_kind": "current_n02", "current_source_code": code,
        })
    # Canonical station identities are shared across batches. Keep references to
    # identities already supplied by another normalized file without redeclaring
    # their canonical key in this batch.
    own_path = BASE / "normalized/station-identities-shiokaze.jsonl"
    externally_declared = set()
    for path in (BASE / "normalized").glob("station-identities*.jsonl"):
        if path == own_path:
            continue
        externally_declared.update(
            json.loads(line)["station_id"]
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    station_rows = [
        row for row in station_rows if row["station_id"] not in externally_declared
    ]
    return station_ids, station_rows


def source_rows(candidate, announcement):
    policy = candidate["source_policy"]
    rows = [announcement]
    for number in range(5, 29):
        trip = candidate["trips"][str(number)]
        for day in DATES:
            rows.append({
                "source_id": train_source_id(number, day),
                "publisher": policy["train_page_publisher"],
                "title": f"しおかぜ{number}号 列車時刻表（{day}）",
                "source_type": policy["source_type"],
                "url_or_locator": train_url(candidate, trip, day),
                "accessed_at": "2026-09-29T00:00:00-04:00",
                "issue": "JR時刻表 2026年8月号", "effective_date": day,
                "content_hash": None, "archive_locator": None,
                "license_status": policy["license_status"],
                "redistribution_status": policy["redistribution_status"],
                "automated_extraction_allowed": policy["automated_extraction_allowed"],
                "notes": (
                    "Exact dated special-service page visually reviewed. Passenger calls, clocks, "
                    "platforms, train number and published pass marks were checked. Pass rows are "
                    "retained only as negative stop-pattern evidence and are not redistributed."
                ),
            })
    return rows


def add_fact(data, trip_id, field_name, source_ids, locator):
    for source_id in source_ids:
        data["fact-sources"].append({
            "entity_type": "trip", "entity_id": trip_id, "field_name": field_name,
            "source_id": source_id, "page_or_locator": locator, "confidence": "high",
            "verification_status": "verified",
        })


def main():
    candidate = load_and_validate_candidate()
    station_ids, station_rows = resolve_station_ids(candidate)
    existing_sources = [
        json.loads(line) for line in SOURCE_REGISTRY.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    announcement = next(row for row in existing_sources if row["source_id"] == ANNOUNCEMENT_SOURCE)
    sources = source_rows(candidate, announcement)

    data = defaultdict(list)
    data["station-identities"].extend(station_rows)
    data["services"].append({
        "service_id": "shiokaze", "canonical_name": "しおかぜ",
        "service_class": "limited_express", "historical_generation": 1,
        "jr_scope": "through_jr", "first_verified_date": DATES[0],
        "last_verified_date": DATES[-1],
    })
    data["service-name-periods"].append({
        "service_id": "shiokaze", "name": "しおかぜ", "language": "ja",
        "valid_from": DATES[0], "valid_until": "2026-08-17", "name_type": "canonical",
        "source_id": ANNOUNCEMENT_SOURCE,
    })

    total_calls = 0
    for number in range(5, 29):
        public_number = str(number)
        reviewed = candidate["trips"][public_number]
        trip_id = f"jr-shikoku.shiokaze.{number}.2026-08-08"
        calendar_id = trip_id + ".calendar"
        version_id = trip_id + ".version"
        dated_source_ids = [train_source_id(number, day) for day in DATES]
        calls = reviewed["passenger_calls"]
        total_calls += len(calls)

        data["timetable-versions"].append({
            "timetable_version_id": version_id, "operator_scope": "jr-shikoku",
            "effective_from": DATES[0], "effective_until": "2026-08-17",
            "publication_date": "2026-06-24",
            "edition_name": "Four announced Obon dates; complete passenger calls",
            "revision_type": "planned_exception", "completeness": "partial",
            "source_ids": [ANNOUNCEMENT_SOURCE] + dated_source_ids,
        })
        data["calendars"].append({
            "calendar_id": calendar_id, "valid_from": DATES[0],
            "valid_until": "2026-08-17", "holiday_policy": "none",
            **{day: 0 for day in ["monday", "tuesday", "wednesday", "thursday",
                                  "friday", "saturday", "sunday"]},
        })
        data["calendar-exceptions"].extend({
            "calendar_id": calendar_id, "service_date": day, "exception_type": "add",
            "source_id": ANNOUNCEMENT_SOURCE,
            "reason": "Four dates explicitly stated on announcement pages 1 and 2",
        } for day in DATES)
        data["trips"].append({
            "trip_id": trip_id, "service_id": "shiokaze",
            "timetable_version_id": version_id, "calendar_id": calendar_id,
            "public_number": public_number, "train_number": reviewed["train_number"],
            "direction": reviewed["direction"],
            "origin_station_id": station_ids[calls[0][0]],
            "destination_station_id": station_ids[calls[-1][0]],
            "service_class": "limited_express",
            "notes": (
                "Exact-date special-service pages agree on all four announced dates. "
                f"{reviewed['omitted_pass_row_count']} published pass rows are deliberately omitted; "
                "operator segments and route lines remain unverified."
            ),
        })
        for sequence, (name, arrival, departure, platform) in enumerate(calls, start=1):
            first, last = sequence == 1, sequence == len(calls)
            data["stop-times"].append({
                "trip_id": trip_id, "stop_sequence": sequence,
                "station_id": station_ids[name], "arrival_time": arrival or None,
                "departure_time": departure or None, "day_offset": 0,
                "call_type": "origin" if first else "destination" if last else "passenger_stop",
                "pickup_allowed": 0 if last else 1, "dropoff_allowed": 0 if first else 1,
                "platform": platform or None, "time_accuracy": "minute",
                "source_id": dated_source_ids[0],
            })

        statuses = {
            "identity": ("verified", "high"), "train_number": ("verified", "high"),
            "operator": ("unknown", "low"), "validity_calendar": ("verified", "high"),
            "origin_destination": ("verified", "high"), "stops": ("verified", "high"),
            "times": ("verified", "high"), "route_lines": ("unknown", "low"),
            "station_refs": ("verified", "high"), "provenance": ("partial", "medium"),
        }
        for dimension, (status, confidence) in statuses.items():
            data["fact-completeness"].append({
                "entity_type": "trip", "entity_id": trip_id, "dimension": dimension,
                "status": status, "confidence": confidence,
                "notes": (
                    "All four exact dated pages agree; passenger calls are complete and pass marks "
                    "are omitted. Operator and route evidence remains open. Reuse is restricted."
                ),
            })
        for dimension in ["identity", "train_number", "origin_destination", "stops", "times"]:
            add_fact(data, trip_id, dimension, dated_source_ids, "Exact dated train page")
        add_fact(data, trip_id, "validity_calendar", [ANNOUNCEMENT_SOURCE], "PDF pp.1-2")
        add_fact(data, trip_id, "station_refs", [STATION_SOURCE], "Shipped current station directory")
        for source_id in dated_source_ids:
            data["fact-sources"].append({
                "entity_type": "trip", "entity_id": trip_id, "field_name": "provenance",
                "source_id": source_id, "page_or_locator": "Exact dated train page; reuse prohibited",
                "confidence": "medium", "verification_status": "partial",
            })
        for dimension in ["operator", "route_lines", "provenance"]:
            data["research-queue"].append({
                "research_id": trip_id + "." + dimension, "entity_type": "trip",
                "entity_id": trip_id, "missing_dimension": dimension, "status": "open",
                "notes": "Obtain explicit operator/route evidence and reusable timetable provenance.",
            })

    coverage_counts = {
        "inventory": 24, "train_number": 24, "calendar": 24, "stops": total_calls,
        "times": total_calls, "route_lines": 0, "station_refs": total_calls, "provenance": 24,
    }
    for dimension, count in coverage_counts.items():
        data["coverage-declarations"].append({
            "coverage_id": f"jr-shikoku.2026.{dimension}.obon-shiokaze-exact-dates",
            "operator_scope": "jr-shikoku", "year": 2026, "dimension": dimension,
            "status": "missing" if dimension == "route_lines" else "partial",
            "record_count": count, "source_id": ANNOUNCEMENT_SOURCE,
            "notes": (
                "24 templates on four exact announced dates; complete passenger calls for this "
                "date-scoped batch, not full-year coverage. Pass rows are omitted."
            ),
        })

    write_jsonl(SOURCE_REGISTRY, sources)
    for entity, rows in data.items():
        if entity in ["trips", "stop-times", "calendars", "calendar-exceptions"]:
            path = BASE / "normalized" / entity / "reviewed-shiokaze" / "seeds.jsonl"
        else:
            path = BASE / "normalized" / (entity + "-shiokaze.jsonl")
        write_jsonl(path, rows)
    print(
        f"Normalized 24 Shiokaze trips with {total_calls} passenger calls from 96 exact dated "
        "official train pages; published pass rows remain omitted."
    )


if __name__ == "__main__":
    main()
