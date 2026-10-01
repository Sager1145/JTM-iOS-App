#!/usr/bin/env python3
"""Stage four source-pinned Hokuto/Suzuran columns for 2026-09-30 only."""

import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "hokkaido-hokuto1-2-suzuran2-5-20260930"
CANDIDATE = BASE / "candidates/jr-hokkaido-hokuto1-2-suzuran2-5-20260930.json"
DAY = "2026-09-30"
NEXT_DAY = "2026-10-01"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
EXPECTED = {
    ("hokuto", "1"): ("1D", "s=150", "函館", "札幌", 15),
    ("hokuto", "2"): ("2D", "s=151", "札幌", "函館", 10),
    ("suzuran", "2"): ("1002M", "s=151", "札幌", "東室蘭", 11),
    ("suzuran", "5"): ("1005M", "s=150", "東室蘭", "札幌", 11),
}
EXPECTED_SAPPORO_PLATFORMS = {"1D": "(7)", "2D": "(4)", "1002M": "(6)", "1005M": "(4)"}


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


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


def validate(candidate):
    if candidate["candidate_status"] != "visually_reviewed" or candidate["canonical"] is not False:
        raise ValueError("Review or staging status changed")
    trips = candidate["trips"]
    if len(trips) != 4 or {(t["service_id"], t["public_number"]) for t in trips} != set(EXPECTED):
        raise ValueError("Four reviewed train identities changed")
    for trip in trips:
        service, public = trip["service_id"], trip["public_number"]
        number, page, origin, destination, count = EXPECTED[(service, public)]
        expected_url = f"https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&{page}"
        expected_source = "jr-hokkaido-hokuto-suzuran-down-20260930" if page == "s=150" else "jr-hokkaido-hokuto-suzuran-up-20260930"
        if (trip["trip_id"], trip["service_date"], trip["train_number"], trip["source_id"], trip["source_url"], trip["origin"], trip["destination"]) != (
            f"jr-hokkaido.{service}.{public}.exact-{DAY}", DAY, number, expected_source,
            expected_url, origin, destination
        ):
            raise ValueError(f"Exact-date train/source identity changed: {number}")
        stops = trip["stops"]
        if len(stops) != count or stops[0][0] != origin or stops[0][1] is not None or stops[-1][0] != destination or stops[-1][2] is not None:
            raise ValueError(f"Reviewed stop endpoints/count changed: {number}")
        if len({row[0] for row in stops}) != count:
            raise ValueError(f"Duplicate passenger call: {number}")
        if trip.get("printed_platforms") != {"札幌": EXPECTED_SAPPORO_PLATFORMS[number]}:
            raise ValueError(f"Reviewed Sapporo platform changed: {number}")
        previous = None
        for name, arrival, departure in stops:
            for clock in (arrival, departure):
                if clock is None:
                    continue
                parsed = datetime.strptime(clock, "%H:%M")
                if previous is not None and parsed < previous:
                    raise ValueError(f"Clock reversal at {name} on {number}")
                previous = parsed
    return trips


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    trips = validate(candidate)
    extension = candidate["service_metadata_extension"]
    if (extension["service_id"], extension["current_last_verified_date"], extension["reviewed_last_verified_date"]) != (
        "hokuto", "2026-09-20", DAY
    ):
        raise ValueError("Reviewed Hokuto service-boundary extension changed")
    if DAY > json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))["as_of_date"]:
        raise ValueError("Service day exceeds as-of date")
    service_rows = [
        json.loads(line) for path in BASE.glob("normalized/services*.jsonl")
        if path.name != f"services-{SUFFIX}.jsonl"
        for line in path.read_text(encoding="utf-8").splitlines() if line.strip()
    ]
    hokuto = [row for row in service_rows if row["service_id"] == "hokuto"]
    if len(hokuto) != 1 or hokuto[0]["last_verified_date"] not in (
        extension["current_last_verified_date"], extension["reviewed_last_verified_date"]
    ):
        raise ValueError("Unexpected shared Hokuto identity or verified-date boundary")
    if any(row["service_id"] == "suzuran" for row in service_rows):
        raise ValueError("Suzuran already has a shared service row; reconcile before staging")
    stations = resolve_stations({stop[0] for trip in trips for stop in trip["stops"]})
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
    sources = []
    for direction, page in (("down", "s=150"), ("up", "s=151")):
        sources.append({
            "source_id": f"jr-hokkaido-hokuto-suzuran-{direction}-20260930",
            "publisher": "北海道旅客鉄道株式会社 / 株式会社交通新聞社",
            "title": f"［特急］すずらん・北斗 {('下り' if direction == 'down' else '上り')} 2026年9月30日",
            "source_type": "official_timetable",
            "url_or_locator": f"https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&{page}",
            "issue": "JR時刻表 令和8年10月号", "publication_date": None,
            "effective_date": DAY, "accessed_at": DAY,
            "license_status": "terms_published_no_reuse_grant_identified",
            "redistribution_status": "verification_only", "automated_extraction_allowed": False,
            "notes": "Selected date and two named train columns on this page visually reviewed. Site prohibits unauthorized reproduction or processing.",
        })
    version_rows, trip_rows, stop_rows, calendar_rows, exception_rows = [], [], [], [], []
    symbol_rows = []
    completeness, facts, queue = [], [], []
    for trip in trips:
        tid = trip["trip_id"]
        symbol_rows.extend({"trip_id": tid, "source_id": trip["source_id"], **symbol}
                           for symbol in trip.get("printed_symbols", []))
        vid, cid = tid + ".version", tid + ".calendar"
        version_rows.append({
            "timetable_version_id": vid, "operator_scope": "jr-hokkaido",
            "effective_from": DAY, "effective_until": NEXT_DAY,
            "edition_name": "JR時刻表 令和8年10月号; selected exact 2026-09-30 column",
            "revision_type": "source_snapshot", "completeness": "partial", "source_ids": [trip["source_id"]],
        })
        trip_rows.append({
            "trip_id": tid, "timetable_version_id": vid, "service_id": trip["service_id"],
            "calendar_id": cid, "train_number": trip["train_number"], "public_number": trip["public_number"],
            "origin_station_id": stations[trip["origin"]], "destination_station_id": stations[trip["destination"]],
            "service_class": "limited_express",
            "notes": "Exact-date official column; pass-through rows excluded; unprinted clock sides and route/operator segments unknown.",
        })
        for sequence, (name, arrival, departure) in enumerate(trip["stops"], 1):
            call_type = "origin" if sequence == 1 else "destination" if sequence == len(trip["stops"]) else "passenger_stop"
            stop_rows.append({
                "trip_id": tid, "stop_sequence": sequence, "station_id": stations[name],
                "arrival_time": arrival, "departure_time": departure, "day_offset": 0,
                "call_type": call_type, "pickup_allowed": 0 if call_type == "destination" else 1,
                "dropoff_allowed": 0 if call_type == "origin" else 1,
                "platform": trip["printed_platforms"].get(name),
                "time_accuracy": "minute", "source_id": trip["source_id"],
            })
        calendar_rows.append({
            "calendar_id": cid, "valid_from": DAY, "valid_until": NEXT_DAY,
            "holiday_policy": "none", **{weekday: 0 for weekday in WEEKDAYS},
        })
        exception_rows.append({
            "calendar_id": cid, "service_date": DAY, "exception_type": "add",
            "reason": "Exact selected date on operator timetable", "source_id": trip["source_id"],
        })
        statuses = {
            "identity": ("verified", "high", f"Official {trip['train_number']} named train column."),
            "train_number": ("verified", "high", f"Official column prints {trip['train_number']}."),
            "validity_calendar": ("verified", "high", "Official selector is 2026-09-30."),
            "origin_destination": ("verified", "high", "First and last timed passenger calls are printed."),
            "stops": ("verified", "high", "All printed passenger calls captured; レ pass-through and || off-route rows excluded."),
            "times": ("partial", "medium", "Every printed clock captured; unprinted intermediate arrival sides remain unknown."),
            "station_refs": ("verified", "high", "Names resolve to current JR Hokkaido N02 station groups."),
            "operator": ("unknown", "low", "No dated operator-segment proof."),
            "route_lines": ("unknown", "low", "No ordered physical line IDs."),
            "provenance": ("partial", "medium", "Official URL pinned; reuse grant unconfirmed."),
        }
        for dimension, (status, confidence, note) in statuses.items():
            completeness.append({"entity_type": "trip", "entity_id": tid, "dimension": dimension,
                                 "status": status, "confidence": confidence, "notes": note})
            if status in ("verified", "partial") and dimension != "provenance":
                facts.append({"entity_type": "trip", "entity_id": tid, "field_name": dimension,
                              "source_id": "jtm-current-station-directory" if dimension == "station_refs" else trip["source_id"],
                              "page_or_locator": "app/public/rail/jp-2025.json" if dimension == "station_refs" else trip["source_locator"],
                              "confidence": confidence, "verification_status": status})
            if dimension in ("times", "operator", "route_lines", "provenance"):
                queue.append({"research_id": f"{tid}.{dimension}", "entity_type": "trip", "entity_id": tid,
                              "missing_dimension": dimension, "status": "open", "notes": note})
    outputs = {
        BASE / f"sources/source-registry-{SUFFIX}.jsonl": sources,
        BASE / f"normalized/services-{SUFFIX}.jsonl": [{
            "service_id": "suzuran", "canonical_name": "すずらん", "service_class": "limited_express",
            "jr_scope": "jr", "historical_generation": 1, "first_verified_date": DAY, "last_verified_date": DAY,
        }],
        BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl": [
            {"service_id": service, "name": name, "language": "ja", "valid_from": DAY,
             "valid_until": NEXT_DAY, "name_type": "display", "source_id": source}
            for service, name, source in (
                ("hokuto", "北斗", "jr-hokkaido-hokuto-suzuran-down-20260930"),
                ("suzuran", "すずらん", "jr-hokkaido-hokuto-suzuran-up-20260930"),
            )
        ],
        BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl": version_rows,
        BASE / f"normalized/station-identities-{SUFFIX}.jsonl": station_rows,
        BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl": trip_rows,
        BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl": stop_rows,
        BASE / "normalized/trip-timetable-symbols/hokkaido-hokuto1-2-20260930/seeds.jsonl": symbol_rows,
        BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl": calendar_rows,
        BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl": exception_rows,
        BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl": completeness,
        BASE / f"normalized/fact-sources-{SUFFIX}.jsonl": facts,
        BASE / f"normalized/research-queue-{SUFFIX}.jsonl": queue,
    }
    for path, rows in outputs.items():
        write_jsonl(path, rows)
    print(f"Staged {len(trips)} exact-date Hokuto/Suzuran trips: {len(stop_rows)} passenger calls")


if __name__ == "__main__":
    main()
