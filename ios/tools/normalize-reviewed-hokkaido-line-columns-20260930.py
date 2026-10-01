#!/usr/bin/env python3
"""Stage individually reviewed JR Hokkaido columns for 2026-09-30."""

import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "hokkaido-line-columns-20260930"
CANDIDATE = BASE / "candidates/jr-hokkaido-line-columns-20260930.json"
ADDITIONAL = BASE / "candidates/jr-hokkaido-pending-s110-20260930.json"
OZORA_UP = BASE / "candidates/jr-hokkaido-ozora2-20260930.json"
TOKACHI_UP = BASE / "candidates/jr-hokkaido-tokachi2-4-20260930.json"
UP_REST = BASE / "candidates/jr-hokkaido-ozora-tokachi-up-rest-20260930.json"
HOKUTO_LATER = BASE / "candidates/jr-hokkaido-hokuto13-15-17-19-20260930.json"
LILAC_LATER = BASE / "candidates/jr-hokkaido-lilac25-27-20260930.json"
ASAHIKAWA_UP_LATER = BASE / "candidates/jr-hokkaido-s111-kamui18-lilac20-22-24-20260930.json"
DAY, NEXT_DAY = "2026-09-30", "2026-10-01"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
PAGES = {
    "s=150": ("jr-hokkaido-hokuto-suzuran-down-extra-20260930", "［特急］すずらん・北斗 下り"),
    "s=130": ("jr-hokkaido-ozora-tokachi-down-extra-20260930", "［特急］おおぞら・とかち 下り"),
    "s=110": ("jr-hokkaido-lilac-kamui-down-extra-20260930", "［特急］ライラック・カムイ 下り"),
    "s=111": ("jr-hokkaido-lilac-kamui-up-extra-20260930", "［特急］ライラック・カムイ 上り"),
    "s=131": ("jr-hokkaido-ozora-tokachi-up-20260930", "［特急］おおぞら・とかち 上り"),
}
EXPECTED = {
    ("hokuto", "3"): ("3D", "s=150", "函館", "札幌", 15, "(7)"),
    ("suzuran", "1"): ("1001M", "s=150", "室蘭", "札幌", 15, "(6)"),
    ("ozora", "3"): ("4003D", "s=130", "札幌", "釧路", 12, "(8)"),
    ("tokachi", "3"): ("33D", "s=130", "札幌", "帯広", 11, "(6)"),
    ("suzuran", "3"): ("1003M", "s=150", "室蘭", "札幌", 15, "(5)"),
    ("hokuto", "5"): ("5D", "s=150", "函館", "札幌", 16, "(8)"),
    ("ozora", "5"): ("4005D", "s=130", "札幌", "釧路", 11, "(8)"),
    ("tokachi", "5"): ("35D", "s=130", "札幌", "帯広", 11, "(6)"),
    ("hokuto", "7"): ("7D", "s=150", "函館", "札幌", 16, "(3)"),
    ("suzuran", "7"): ("1007M", "s=150", "室蘭", "札幌", 15, "(3)"),
    ("ozora", "7"): ("4007D", "s=130", "札幌", "釧路", 7, "(8)"),
    ("tokachi", "7"): ("37D", "s=130", "札幌", "帯広", 11, "(5)"),
    ("lilac", "5"): ("3005M", "s=110", "札幌", "旭川", 7, "(10)"),
    ("lilac", "11"): ("3011M", "s=110", "札幌", "旭川", 7, "(10)"),
    ("lilac", "13"): ("3013M", "s=110", "札幌", "旭川", 7, "(10)"),
    ("kamui", "6"): ("2006M", "s=111", "旭川", "札幌", 7, "(3)"),
    ("kamui", "10"): ("2010M", "s=111", "旭川", "札幌", 7, "(2)"),
    ("lilac", "12"): ("3012M", "s=111", "旭川", "札幌", 7, "(2)"),
    ("lilac", "14"): ("3014M", "s=111", "旭川", "札幌", 7, "(2)"),
    ("lilac", "16"): ("3016M", "s=111", "旭川", "札幌", 7, "(2)"),
    ("hokuto", "9"): ("9D", "s=150", "函館", "札幌", 16, "(7)"),
    ("suzuran", "9"): ("1009M", "s=150", "室蘭", "札幌", 15, "(4)"),
    ("ozora", "9"): ("4009D", "s=130", "札幌", "釧路", 14, "(8)"),
    ("tokachi", "9"): ("39D", "s=130", "札幌", "帯広", 10, "(7)"),
    ("lilac", "17"): ("3017M", "s=110", "札幌", "旭川", 7, "(10)"),
    ("kamui", "19"): ("2019M", "s=110", "札幌", "旭川", 7, "(9)"),
    ("hokuto", "11"): ("11D", "s=150", "函館", "札幌", 16, "(4)"),
    ("suzuran", "11"): ("1011M", "s=150", "室蘭", "札幌", 15, "(5)"),
    ("ozora", "11"): ("4011D", "s=130", "札幌", "釧路", 11, "(7)"),
    ("kamui", "21"): ("2021M", "s=110", "札幌", "旭川", 7, "(9)"),
    ("lilac", "23"): ("3023M", "s=110", "札幌", "旭川", 7, "(10)"),
    ("ozora", "2"): ("4002D", "s=131", "釧路", "札幌", 15, "(4)"),
    ("tokachi", "2"): ("32D", "s=131", "帯広", "札幌", 11, "(4)"),
    ("tokachi", "4"): ("34D", "s=131", "帯広", "札幌", 11, "(4)"),
    ("ozora", "4"): ("4004D", "s=131", "釧路", "札幌", 8, "(3)"),
    ("tokachi", "6"): ("36D", "s=131", "帯広", "札幌", 11, "(4)"),
    ("ozora", "6"): ("4006D", "s=131", "釧路", "札幌", 9, "(8)"),
    ("tokachi", "8"): ("38D", "s=131", "帯広", "札幌", 11, "(4)"),
    ("ozora", "8"): ("4008D", "s=131", "釧路", "札幌", 11, "(7)"),
    ("ozora", "10"): ("4010D", "s=131", "釧路", "札幌", 11, "(4)"),
    ("tokachi", "10"): ("40D", "s=131", "帯広", "札幌", 11, "(3)"),
    ("ozora", "12"): ("4012D", "s=131", "釧路", "札幌", 8, "(7)"),
    ("hokuto", "13"): ("13D", "s=150", "函館", "札幌", 16, "(8)"),
    ("hokuto", "15"): ("15D", "s=150", "函館", "札幌", 16, "(3)"),
    ("hokuto", "17"): ("17D", "s=150", "函館", "札幌", 16, "(3)"),
    ("hokuto", "19"): ("19D", "s=150", "函館", "札幌", 15, "(4)"),
    ("lilac", "25"): ("3025M", "s=110", "札幌", "旭川", 7, "(9)"),
    ("lilac", "27"): ("3027M", "s=110", "札幌", "旭川", 7, "(9)"),
    ("kamui", "18"): ("2018M", "s=111", "旭川", "札幌", 7, "(2)"),
    ("lilac", "20"): ("3020M", "s=111", "旭川", "札幌", 7, "(3)"),
    ("lilac", "22"): ("3022M", "s=111", "旭川", "札幌", 7, "(3)"),
    ("lilac", "24"): ("3024M", "s=111", "旭川", "札幌", 7, "(3)"),
}


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def rows_matching(glob, identity):
    return [json.loads(raw) for path in BASE.glob(glob) if SUFFIX not in path.parts and path.name != f"{identity}-{SUFFIX}.jsonl"
            for raw in path.read_text(encoding="utf-8").splitlines() if raw.strip()]


def validate(candidate):
    if candidate["candidate_status"] != "visually_reviewed" or candidate["canonical"] is not False:
        raise ValueError("Line-column review status changed")
    trips = candidate["trips"]
    if len(trips) != 52 or {(t["service_id"], t["public_number"]) for t in trips} != set(EXPECTED):
        raise ValueError("Reviewed train set changed")
    known_trips = {row["trip_id"] for row in rows_matching("normalized/trips/*/*.jsonl", "trips")}
    for trip in trips:
        service, public = trip["service_id"], trip["public_number"]
        train, page, origin, destination, count, platform = EXPECTED[(service, public)]
        source_id = PAGES[page][0]
        url = f"https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&{page}"
        if (trip["trip_id"], trip["service_date"], trip["train_number"], trip["source_id"],
            trip["source_url"], trip["origin"], trip["destination"], trip["printed_platforms"]) != (
                f"jr-hokkaido.{service}.{public}.exact-{DAY}", DAY, train, source_id, url,
                origin, destination, {"札幌": platform}):
            raise ValueError(f"Reviewed identity, source, or platform changed: {train}")
        if trip["trip_id"] in known_trips:
            raise ValueError(f"Already staged trip: {trip['trip_id']}")
        stops = trip["stops"]
        if len(stops) != count or stops[0][:2] != [origin, None] or stops[-1][0] != destination or stops[-1][2] is not None:
            raise ValueError(f"Reviewed passenger-call boundaries changed: {train}")
        names = [row[0] for row in stops]
        if len(set(names)) != count or set(names) & set(trip["pass_through_names"]):
            raise ValueError(f"Passenger and passing rows overlap: {train}")
        previous = None
        for name, arrival, departure in stops:
            if arrival is None and departure is None:
                raise ValueError(f"Blank passenger clock: {train} at {name}")
            for clock in (arrival, departure):
                if clock is None:
                    continue
                current = datetime.strptime(clock, "%H:%M")
                if previous is not None and current < previous:
                    raise ValueError(f"Clock reversal: {train} at {name}")
                previous = current
    return trips


def resolve_stations(trips):
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    stations = {}
    for name in {row[0] for trip in trips for row in trip["stops"]}:
        codes = {station[0] for line in package["lines"] if line["operator"] == "北海道旅客鉄道"
                 for station in line["stations"] if station[1] == name}
        if len(codes) != 1:
            raise ValueError(f"Expected one current station identity for {name}: {sorted(codes)}")
        stations[name] = "jp.n02." + next(iter(codes))
    existing = {row["station_id"]: row for row in rows_matching("normalized/station-identities*.jsonl", "station-identities")}
    new = []
    for name, station_id in sorted(stations.items()):
        if station_id in existing:
            if existing[station_id]["name_snapshot"] != name:
                raise ValueError(f"Conflicting station identity: {name}")
        else:
            new.append({"station_id": station_id, "name_snapshot": name,
                        "reference_kind": "current_n02", "current_source_code": station_id.removeprefix("jp.n02."),
                        "rail_history_id": None})
    return stations, new


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    additional = json.loads(ADDITIONAL.read_text(encoding="utf-8"))
    ozora_up = json.loads(OZORA_UP.read_text(encoding="utf-8"))
    tokachi_up = json.loads(TOKACHI_UP.read_text(encoding="utf-8"))
    up_rest = json.loads(UP_REST.read_text(encoding="utf-8"))
    hokuto_later = json.loads(HOKUTO_LATER.read_text(encoding="utf-8"))
    lilac_later = json.loads(LILAC_LATER.read_text(encoding="utf-8"))
    asahikawa_up_later = json.loads(ASAHIKAWA_UP_LATER.read_text(encoding="utf-8"))
    if (len(candidate["trips"]), additional["candidate_status"], additional["canonical"],
        len(additional["trips"]), ozora_up["candidate_status"], ozora_up["canonical"],
        len(ozora_up["trips"]), tokachi_up["candidate_status"], tokachi_up["canonical"],
        len(tokachi_up["trips"]), up_rest["candidate_status"], up_rest["canonical"],
        len(up_rest["trips"]), hokuto_later["candidate_status"], hokuto_later["canonical"],
        len(hokuto_later["trips"]), lilac_later["candidate_status"], lilac_later["canonical"],
        len(lilac_later["trips"]), asahikawa_up_later["candidate_status"],
        asahikawa_up_later["canonical"], len(asahikawa_up_later["trips"])) != (
                                    29, "visually_reviewed", False, 2,
                                    "visually_reviewed", False, 1, "visually_reviewed", False, 2,
                                    "visually_reviewed", False, 8, "visually_reviewed", False, 4,
                                    "visually_reviewed", False, 2, "visually_reviewed", False, 4):
        raise ValueError("Additional exact-date columns changed")
    candidate["trips"] += (additional["trips"] + ozora_up["trips"] + tokachi_up["trips"]
                           + up_rest["trips"] + hokuto_later["trips"] + lilac_later["trips"]
                           + asahikawa_up_later["trips"])
    trips = validate(candidate)
    if DAY > json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))["as_of_date"]:
        raise ValueError("Service day exceeds dataset as-of date")
    known_services = {row["service_id"] for row in rows_matching("normalized/services*.jsonl", "services")}
    if not {service for service, _ in EXPECTED} <= known_services:
        raise ValueError("Shared service identity missing")
    stations, new_stations = resolve_stations(trips)
    sources = [{"source_id": source_id, "publisher": "北海道旅客鉄道株式会社 / 株式会社交通新聞社",
                "title": f"{title} 2026年9月30日", "source_type": "official_timetable",
                "url_or_locator": f"https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&{page}",
                "issue": "JR時刻表 令和8年10月号", "publication_date": None,
                "effective_date": DAY, "accessed_at": DAY,
                "license_status": "terms_published_no_reuse_grant_identified",
                "redistribution_status": "verification_only", "automated_extraction_allowed": False,
                "notes": "Selected date and named train columns visually reviewed; only printed passenger calls promoted. No other service date inferred."}
               for page, (source_id, title) in PAGES.items()]
    out = {key: [] for key in ("timetable-versions", "trips", "stop-times", "calendars",
                              "calendar-exceptions", "fact-completeness", "fact-sources", "research-queue")}
    for trip in trips:
        tid, source = trip["trip_id"], trip["source_id"]
        vid, cid = tid + ".version", tid + ".calendar"
        out["timetable-versions"].append({"timetable_version_id": vid, "operator_scope": "jr-hokkaido",
            "effective_from": DAY, "effective_until": NEXT_DAY,
            "edition_name": "JR時刻表 令和8年10月号; selected exact 2026-09-30 column",
            "revision_type": "source_snapshot", "completeness": "partial", "source_ids": [source]})
        out["trips"].append({"trip_id": tid, "timetable_version_id": vid, "service_id": trip["service_id"],
            "calendar_id": cid, "train_number": trip["train_number"], "public_number": trip["public_number"],
            "origin_station_id": stations[trip["origin"]], "destination_station_id": stations[trip["destination"]],
            "service_class": "limited_express",
            "notes": "Exact-date official column; passing rows excluded; unprinted clock sides and route segments unknown."})
        for sequence, (name, arrival, departure) in enumerate(trip["stops"], 1):
            call_type = "origin" if sequence == 1 else "destination" if sequence == len(trip["stops"]) else "passenger_stop"
            out["stop-times"].append({"trip_id": tid, "stop_sequence": sequence,
                "station_id": stations[name], "arrival_time": arrival, "departure_time": departure,
                "day_offset": 0, "call_type": call_type,
                "pickup_allowed": 0 if call_type == "destination" else 1,
                "dropoff_allowed": 0 if call_type == "origin" else 1,
                "platform": trip["printed_platforms"].get(name),
                "time_accuracy": "minute", "source_id": source})
        out["calendars"].append({"calendar_id": cid, "valid_from": DAY, "valid_until": NEXT_DAY,
            "holiday_policy": "none", **{weekday: 0 for weekday in WEEKDAYS}})
        out["calendar-exceptions"].append({"calendar_id": cid, "service_date": DAY,
            "exception_type": "add", "reason": "Selected date and 毎日 column on operator timetable", "source_id": source})
        statuses = {
            "identity": ("verified", "high", "Named official column."),
            "train_number": ("verified", "high", f"Official column prints {trip['train_number']}."),
            "validity_calendar": ("verified", "high", "Selected date 2026-09-30; column prints 毎日."),
            "origin_destination": ("verified", "high", "First and last passenger calls printed."),
            "stops": ("verified", "high", "All passenger calls captured; レ and || rows excluded."),
            "times": ("partial", "medium", "Every printed clock captured; unprinted arrival sides unknown."),
            "station_refs": ("partial", "medium", "Current N02 station groups; exact-date identity not independently established."),
            "operator": ("unknown", "low", "No ordered operator-segment proof."),
            "route_lines": ("unknown", "low", "No ordered physical-line IDs."),
            "provenance": ("partial", "medium", "Official URL pinned; reuse grant unconfirmed."),
        }
        for dimension, (status, confidence, note) in statuses.items():
            out["fact-completeness"].append({"entity_type": "trip", "entity_id": tid,
                "dimension": dimension, "status": status, "confidence": confidence, "notes": note})
            if status in ("verified", "partial") and dimension != "provenance":
                station_ref = dimension == "station_refs"
                out["fact-sources"].append({"entity_type": "trip", "entity_id": tid,
                    "field_name": dimension,
                    "source_id": "jtm-current-station-directory" if station_ref else source,
                    "page_or_locator": "app/public/rail/jp-2025.json" if station_ref else trip["source_locator"],
                    "confidence": confidence, "verification_status": status})
            if dimension in ("times", "station_refs", "operator", "route_lines", "provenance"):
                out["research-queue"].append({"research_id": f"{tid}.{dimension}",
                    "entity_type": "trip", "entity_id": tid, "missing_dimension": dimension,
                    "status": "open", "notes": note})
    write(BASE / f"sources/source-registry-{SUFFIX}.jsonl", sources)
    write(BASE / f"normalized/station-identities-{SUFFIX}.jsonl", new_stations)
    for entity, rows in out.items():
        path = (BASE / f"normalized/{entity}/{SUFFIX}/seeds.jsonl"
                if entity in {"trips", "stop-times", "calendars", "calendar-exceptions"}
                else BASE / f"normalized/{entity}-{SUFFIX}.jsonl")
        write(path, rows)
    print(f"Staged {len(trips)} exact-date JR Hokkaido trips: {len(out['stop-times'])} passenger calls")


if __name__ == "__main__":
    main()
