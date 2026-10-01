#!/usr/bin/env python3
"""Promote the fourth eight source-pinned 2026-09-30 Sonic/Uwakai candidates."""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
DATE, UNTIL = "2026-09-30", "2026-10-01"
SUFFIX = "reviewed-sonic27-33-uwakai26-32-20260930"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
ALIAS = {"柳ケ浦": "柳ヶ浦"}
PLANNED_SONIC = {27: ("885", 6), 31: ("883", 7), 33: ("885", 6)}
ANPANMAN_UWAKAI = set()
GUIDE_ID = "jr-kyushu-sonic-configuration-guide-20260930"
EQUIPMENT_ID = "jr-kyushu-sonic-equipment-guide-20260930"
PINS = {
    ("sonic", 27): "0d50540c736d678e8344050e7b76ad31d06ec8b3a3572d48642ab65b10f0d390",
    ("sonic", 29): "c633ebe61468a3d26476732cbd0def027382547b968ad4b8447f09355f59e248",
    ("sonic", 31): "1c114a78750dc57f435b11e4c59509712df6f4c9bc4365b98e9d5c3d5296e8e2",
    ("sonic", 33): "c47b18fe162183b921136b842806a14cbf16de9aad6ab6f6cb20e4bbe1cd4619",
    ("uwakai", 26): "74343f5c1a74b14dfb091d9db541a7495fc731fe7ba959a026ae7b3cabb9c5eb",
    ("uwakai", 28): "9cb6e4dfffd4198f4333a40473376b0246fab61d837c973189c0b82c72a84df1",
    ("uwakai", 30): "8ec2973a50d4a6cb26930045edc383832771571259a4ef72f74b8084f5138cac",
    ("uwakai", 32): "2852c4ae3fe3db56dd7189195673825e3302722e7da3e5e5f4b7269233b78676",
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
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in records), encoding="utf-8")


def stop_pin(stops):
    matrix = [(s["name_snapshot"], s["arrival_time"], s["departure_time"], s["platform"])
              for s in stops]
    return hashlib.sha256(json.dumps(matrix, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def main():
    inventory = json.loads((BASE / "sources/candidates/sonic-uwakai-closed-inventory-20260930.json")
                           .read_text(encoding="utf-8"))
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    if DATE > manifest["as_of_date"]:
        raise ValueError("Exact date exceeds manifest cutoff")
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    by_number = {service: {int(r["public_number"]): r for r in inventory["services"][service]}
                 for service in ("sonic", "uwakai")}
    target_station = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    target_source = BASE / f"sources/source-registry-{SUFFIX}.jsonl"
    known_stations = {r["station_id"]: r for r in rows("normalized/station-identities*.jsonl", target_station)}
    known_sources = {r["source_id"] for r in rows("sources/source-registry*.jsonl", target_source)}
    guide_sources = {r["source_id"]: r for r in rows("sources/source-registry*.jsonl", target_source)}
    if (guide_sources[GUIDE_ID]["url_or_locator"] != "https://www.jrkyushu.co.jp/english/train/sonic.html" or
            guide_sources[EQUIPMENT_ID]["url_or_locator"] !=
            "https://www.jrkyushu.co.jp/train/kids/guardian/train_equipment/index.html"):
        raise ValueError("Official Sonic guide source changed")
    known_trips = {r["trip_id"] for r in rows("normalized/trips/*/*.jsonl",
                                             BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
    output = {k: [] for k in ("station-identities", "source-registry", "timetable-versions",
                              "calendars", "calendar-exceptions", "trips", "stop-times",
                              "trip-formations", "trip-formation-cars", "fact-completeness", "fact-sources", "research-queue")}
    for (service, number), expected_pin in PINS.items():
        operator = "jr-kyushu" if service == "sonic" else "jr-shikoku"
        candidate_name = f"{operator}-{service}{number}-20260930.json"
        candidate = json.loads((BASE / "candidates" / candidate_name).read_text(encoding="utf-8"))
        trip = candidate["trip"]
        inv = by_number[service][number]
        train_source_id = f"{operator}-{service}{number}-20260930-train"
        trip_id = f"{operator}.{service}.{number}.{DATE}"
        if (candidate["candidate_status"] != "reviewed_official_html" or
                trip["trip_id"] != trip_id or trip["public_number"] != str(number) or
                trip["service_date"] != DATE or trip["train_number"] != inv["train_number"] or
                trip["stop_times"][0]["name_snapshot"] != inv["origin"] or
                trip["stop_times"][-1]["name_snapshot"] != inv["destination"] or
                trip["operating_note"] != "毎日運転" or stop_pin(trip["stop_times"]) != expected_pin or
                trip_id in known_trips):
            raise ValueError(f"Source-pinned candidate mismatch or duplicate: {trip_id}")
        if service == "sonic":
            sources = [candidate["new_source"]]
            if (candidate["source_id"] != train_source_id or candidate["source_url"] != inv["detail_url"] or
                    trip["seat_description_snapshot"] != (["「白いソニック」で運転"] if number == 33 else []) + ["グリーン車指定席", "普通車一部指定席"]):
                raise ValueError(f"Sonic source/equipment mismatch: {trip_id}")
            source_ids = [train_source_id]
            if number in PLANNED_SONIC:
                series, count = PLANNED_SONIC[number]
                expected_evidence = {"vehicle_series": series, "car_count": count,
                    "configuration_source_id": GUIDE_ID, "equipment_source_id": EQUIPMENT_ID,
                    "diagram_source_id": f"jr-kyushu-sonic-{series}-diagram-20260930",
                    "evidence_kind": "planned", "actual_consist_verified": False}
                if candidate.get("formation_evidence") != expected_evidence:
                    raise ValueError(f"Planned formation candidate evidence changed: {trip_id}")
        else:
            sources = candidate["sources"]
            line_source_id = f"{operator}-{service}{number}-20260930-line"
            if (trip["equipment_description_snapshot"] !=
                    (["アンパンマン列車で運転", "普通車一部指定席"] if number in ANPANMAN_UWAKAI else ["普通車一部指定席"])):
                raise ValueError(f"Uwakai equipment mismatch: {trip_id}")
            source_ids = [train_source_id, line_source_id]
        source_map = {s["source_id"]: s for s in sources}
        if (source_map[train_source_id]["url_or_locator"] != inv["detail_url"] or
                set(source_map) != set(source_ids) or
                any(s["automated_extraction_allowed"] is not False for s in sources) or
                known_sources.intersection(source_map)):
            raise ValueError(f"Candidate source registry mismatch: {trip_id}")
        if service == "uwakai" and source_map[line_source_id]["url_or_locator"] != \
                "https://timetable.jr-odekake.net/line-timetable/2470?day=30&month=9&year=2026":
            raise ValueError(f"Uwakai line source mismatch: {trip_id}")
        output["source-registry"].extend(sources)
        known_sources.update(source_map)
        operator_name = "九州旅客鉄道" if service == "sonic" else "四国旅客鉄道"
        stations = {}
        for stop in trip["stop_times"]:
            name = stop["name_snapshot"]
            canonical = ALIAS.get(name, name)
            matches = {station[0] for line in package["lines"] if line["operator"] == operator_name
                       for station in line["stations"] if station[1] == canonical}
            if len(matches) != 1:
                raise ValueError(f"Station reference not unique: {trip_id} {name} {matches}")
            code = next(iter(matches))
            record = dict(station_id="jp.n02." + code, current_source_code=code,
                          name_snapshot=canonical, reference_kind="current_n02")
            if record["station_id"] in known_stations:
                if any(known_stations[record["station_id"]].get(key) != value
                       for key, value in record.items()):
                    raise ValueError(f"Station identity conflict: {name}")
            else:
                output["station-identities"].append(record)
                known_stations[record["station_id"]] = record
            stations[name] = record["station_id"]
        version_id, calendar_id = trip_id + ".version", trip_id + ".calendar"
        output["timetable-versions"].append(dict(
            timetable_version_id=version_id, operator_scope=operator, effective_from=DATE,
            effective_until=UNTIL, edition_name="JR時刻表2026年10月号 exact 2026-09-30 train detail",
            revision_type="source_snapshot", completeness="partial", source_ids=source_ids))
        output["calendars"].append(dict(calendar_id=calendar_id, valid_from=DATE,
                                        valid_until=UNTIL, holiday_policy="none",
                                        **{day: 0 for day in WEEKDAYS}))
        output["calendar-exceptions"].append(dict(calendar_id=calendar_id, service_date=DATE,
            exception_type="add", source_id=source_ids[-1],
            reason="Exact-date official timetable; recurrence not inferred"))
        output["trips"].append(dict(trip_id=trip_id, timetable_version_id=version_id,
            service_id=service, calendar_id=calendar_id, train_number=trip["train_number"],
            public_number=str(number), origin_station_id=stations[inv["origin"]],
            destination_station_id=stations[inv["destination"]], service_class="limited_express",
            direction=trip["direction"],
            notes="Exact-date passenger calls only; physical lines and operator boundaries unresolved."))
        for sequence, stop in enumerate(trip["stop_times"], 1):
            call = "origin" if sequence == 1 else "destination" if sequence == len(trip["stop_times"]) else "passenger_stop"
            output["stop-times"].append(dict(trip_id=trip_id, stop_sequence=sequence,
                station_id=stations[stop["name_snapshot"]], arrival_time=stop["arrival_time"],
                departure_time=stop["departure_time"], day_offset=0, call_type=call,
                pickup_allowed=0 if call == "destination" else 1,
                dropoff_allowed=0 if call == "origin" else 1, platform=stop["platform"],
                time_accuracy="minute", source_id=train_source_id))
        formation_note = ("Official detail prints Green reserved and ordinary partly reserved; vehicle series, "
                          "car count and actual consist unverified." if service == "sonic" else
                          "Official detail prints ordinary partly reserved; vehicle series, car count and actual consist unverified.")
        if service == "uwakai" and number in ANPANMAN_UWAKAI:
            formation_note += " It also prints アンパンマン列車で運転."
        formation = dict(formation_id=f"{trip_id}.formation.{DATE}", trip_id=trip_id,
                         service_date=DATE, evidence_kind="planned", source_id=train_source_id,
                         all_reserved=False, notes=formation_note)
        if service == "sonic":
            formation["green_car_available"] = True
            if number in PLANNED_SONIC:
                series, count = PLANNED_SONIC[number]
                diagram_id = f"jr-kyushu-sonic-{series}-diagram-20260930"
                expected_diagram = f"https://www.jrkyushu.co.jp/lang/assets/img/train/sonic/img_configuration0{'1' if series == '883' else '2'}_pc.png"
                if guide_sources[diagram_id]["url_or_locator"] != expected_diagram:
                    raise ValueError(f"Official Sonic car diagram changed: {trip_id}")
                formation.update(vehicle_series=series, car_count=count,
                    notes=f"Official number-specific planned {series} series, {count} cars, Green and ordinary partly reserved; actual consist and variable cars 3/4 seats unverified.")
                for car_number in range(1, count + 1):
                    car = dict(formation_id=formation["formation_id"], car_sequence=car_number,
                               car_number=str(car_number), vehicle_series=series, source_id=diagram_id)
                    if car_number == 1:
                        car["notes"] = "Diagram depicts both Green and reserved ordinary seats; single seat_class unset."
                    elif car_number == 2:
                        car.update(seat_class="ordinary", reservation_type="reserved")
                    elif car_number >= 5:
                        car.update(seat_class="ordinary", reservation_type="non_reserved")
                    else:
                        car["notes"] = "Reservation category varies by train; exact-day assignment unverified."
                    output["trip-formation-cars"].append(car)
                for field, source_id, locator in (
                    ("vehicle_series", GUIDE_ID, f"Train Configuration / {series} Series / No. {number}"),
                    ("car_count", EQUIPMENT_ID, f"列車の設備 / {series}系 {count}両"),
                ):
                    output["fact-sources"].append(dict(entity_type="trip", entity_id=trip_id,
                        field_name="formation." + field, source_id=source_id,
                        page_or_locator=locator, confidence="high", verification_status="verified"))
        formation_note = formation["notes"]
        output["trip-formations"].append(formation)
        formation_fields = [("all_reserved", "普通車一部指定席")]
        if service == "sonic":
            formation_fields.append(("green_car_available", "グリーン車指定席"))
        if service == "uwakai" and number in ANPANMAN_UWAKAI:
            formation_fields.append(("service_branding", "アンパンマン列車で運転"))
        for field, locator in formation_fields:
            output["fact-sources"].append(dict(entity_type="trip", entity_id=trip_id,
                field_name="formation." + field, source_id=train_source_id,
                page_or_locator="列車設備 / 車両設備情報: " + locator,
                confidence="high", verification_status="verified"))
        output["fact-completeness"].append(dict(entity_type="trip", entity_id=trip_id,
            dimension="formation", status="partial", confidence="high", notes=formation_note))
        dimensions = {
            "identity": ("verified", "high"), "train_number": ("verified", "high"),
            "operator": ("unknown", "low"), "validity_calendar": ("verified", "high"),
            "origin_destination": ("verified", "high"), "stops": ("verified", "high"),
            "times": ("verified", "high"), "route_lines": ("unknown", "low"),
            "station_refs": ("verified", "high"), "provenance": ("partial", "medium"),
        }
        for dimension, (status, confidence) in dimensions.items():
            output["fact-completeness"].append(dict(entity_type="trip", entity_id=trip_id,
                dimension=dimension, status=status, confidence=confidence,
                notes="Exact-date official train detail; unresolved dimensions remain explicit."))
            if status == "verified":
                source = ("jtm-current-station-directory" if dimension == "station_refs" else
                          source_ids[-1] if dimension == "validity_calendar" else train_source_id)
                output["fact-sources"].append(dict(entity_type="trip", entity_id=trip_id,
                    field_name=dimension, source_id=source, page_or_locator="2026-09-30 official train detail",
                    confidence=confidence, verification_status=status))
        for dimension, status, note in (
            ("operator", "open", "Find dated ordered operator segment boundaries."),
            ("route_lines", "open", "Find dated ordered physical line identities."),
            ("provenance", "license_blocked", "No redistribution or automated extraction grant found."),
        ):
            output["research-queue"].append(dict(research_id=f"{trip_id}.{dimension}",
                entity_type="trip", entity_id=trip_id, missing_dimension=dimension,
                status=status, notes=note))
    targets = {
        "station-identities": target_station,
        "source-registry": target_source,
        "timetable-versions": BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl",
        "calendars": BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl",
        "calendar-exceptions": BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl",
        "trips": BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl",
        "stop-times": BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl",
        "trip-formations": BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl",
        "trip-formation-cars": BASE / f"normalized/trip-formation-cars/{SUFFIX}/seeds.jsonl",
        "fact-completeness": BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl",
        "fact-sources": BASE / f"normalized/fact-sources-{SUFFIX}.jsonl",
        "research-queue": BASE / f"normalized/research-queue-{SUFFIX}.jsonl",
    }
    for kind, path in targets.items():
        write(path, sorted(output[kind], key=lambda row: json.dumps(row, ensure_ascii=False, sort_keys=True)))
    print(f"Normalized {len(output['trips'])} exact-day trips and {len(output['stop-times'])} passenger calls")


if __name__ == "__main__":
    main()
