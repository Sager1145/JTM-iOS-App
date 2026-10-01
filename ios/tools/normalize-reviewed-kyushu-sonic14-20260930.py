#!/usr/bin/env python3
"""Normalize exact-date Sonic 14 eight passenger calls."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
DATE = "2026-09-30"
UNTIL = "2026-10-01"
SUFFIX = "reviewed-kyushu-sonic14-20260930"
STATION_SOURCE = "jtm-current-station-directory"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
STATION_ALIASES = {"柳ケ浦": "柳ヶ浦"}  # Official timetable / current N02 spelling.

SPECS = ({'candidate': 'jr-kyushu-sonic14-20260930.json',
 'trip_id': 'jr-kyushu.sonic.14.2026-09-30',
 'service_id': 'sonic',
 'service_name': 'ソニック',
 'public_number': '14',
 'train_number': '3014M',
 'operator': 'jr-kyushu',
 'source_id': 'jr-kyushu-sonic14-20260930',
 'source_url': 'https://www.jrkyushu-timetable.jp/sp/2610/0011/00117401.html?t=2874200e&d=20260930',
 'expected': (('大分', None, '08:42', '3'),
              ('別府', '08:50', '08:51', None),
              ('中津', '09:29', '09:29', None),
              ('行橋', '09:46', '09:47', None),
              ('小倉', '10:03', '10:05', '4'),
              ('黒崎', '10:13', '10:14', None),
              ('折尾', '10:18', '10:19', '3'),
              ('博多', '10:49', None, '6'))},)

def rows(pattern, exclude=None):
    for path in sorted(BASE.glob(pattern)):
        if path == exclude or not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                yield json.loads(line)


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in records),
        encoding="utf-8",
    )


def resolve_stations(names, package, prior, operator):
    result = {}
    allowed = ({"九州旅客鉄道"} if operator == "jr-kyushu"
               else {"四国旅客鉄道"})
    for name in names:
        directory_name = STATION_ALIASES.get(name, name)
        matches = {
            station[0]
            for line in package["lines"]
            if line["operator"] in allowed
            for station in line["stations"] if station[1] == directory_name
        }
        if len(matches) != 1:
            raise ValueError(f"Ambiguous or absent current station {name}: {sorted(matches)}")
        code = next(iter(matches))
        record = dict(station_id="jp.n02." + code, name_snapshot=directory_name,
                      reference_kind="current_n02", current_source_code=code)
        previous = prior.get(record["station_id"])
        if previous and any(previous.get(key) != value for key, value in record.items()):
            raise ValueError(f"Station identity conflict for {name}")
        result[name] = record
    return result


def main():
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    if DATE > manifest["as_of_date"]:
        raise ValueError("Candidate date exceeds database cutoff")
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    station_target = BASE / f"normalized/station-identities-{SUFFIX}.jsonl"
    service_target = BASE / f"normalized/services-{SUFFIX}.jsonl"
    prior_stations = {row["station_id"]: row for row in rows("normalized/station-identities*.jsonl", station_target)}
    prior_services = {row["service_id"]: row for row in rows("normalized/services*.jsonl", service_target)}
    registry_target = BASE / f"sources/source-registry-{SUFFIX}.jsonl"
    prior_sources = {row["source_id"]: row["url_or_locator"]
                     for row in rows("sources/source-registry*.jsonl", registry_target)}
    output = {name: [] for name in (
        "services", "service-name-periods", "timetable-versions", "station-identities", "calendars",
        "calendar-exceptions", "trips", "stop-times", "trip-formations", "trip-formation-cars", "fact-completeness",
        "fact-sources", "research-queue", "source-registry",
    )}
    trip_ids = {row["trip_id"] for row in rows("normalized/trips/*/*.jsonl", BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")}
    for spec in SPECS:
        candidate = json.loads((BASE / "candidates" / spec["candidate"]).read_text(encoding="utf-8"))
        trip = candidate["trip"]
        if candidate["candidate_status"] != "reviewed_official_html":
            raise ValueError("Candidate review status changed")
        if (trip["trip_id"], trip["service_id"], trip["service_name"],
            trip["public_number"], trip["train_number"]) != tuple(
                spec[key] for key in ("trip_id", "service_id", "service_name", "public_number", "train_number")
            ):
            raise ValueError("Reviewed train identity changed")
        if trip.get("service_date", candidate.get("service_date")) != DATE or trip["trip_id"] in trip_ids:
            raise ValueError("Date changed or trip id already exists")
        actual = tuple((s["name_snapshot"], s["arrival_time"], s["departure_time"], s["platform"])
                       for s in trip["stop_times"])
        if actual != spec["expected"]:
            raise ValueError(f"Reviewed passenger-call matrix changed for {spec['trip_id']}")
        if candidate["source_id"] != spec["source_id"] or candidate["source_url"] != spec["source_url"]:
            raise ValueError("Reviewed Kyushu source changed")
        source = candidate["new_source"]
        if (source["source_id"], source["url_or_locator"], source["effective_date"],
            source["automated_extraction_allowed"]) != (
                spec["source_id"], spec["source_url"], DATE, False):
            raise ValueError("New source registry details changed")
        if source["source_id"] in prior_sources:
            raise ValueError("New source ID collides with existing registry")
        output["source-registry"].append(source)
        names = [s["name_snapshot"] for s in trip["stop_times"]]
        stations = resolve_stations(names, package, prior_stations, spec["operator"])
        for station in stations.values():
            if station["station_id"] not in prior_stations:
                output["station-identities"].append(station)
                prior_stations[station["station_id"]] = station
        existing_service = prior_services.get(spec["service_id"])
        if existing_service and existing_service["canonical_name"] != spec["service_name"]:
            raise ValueError("Service identity conflict")
        if not existing_service:
            service = dict(service_id=spec["service_id"], canonical_name=spec["service_name"],
                           service_class="limited_express", historical_generation=1,
                           first_verified_date=DATE, last_verified_date=DATE, jr_scope="jr")
            output["services"].append(service)
            prior_services[spec["service_id"]] = service
            output["service-name-periods"].append(dict(
                service_id=spec["service_id"], name=spec["service_name"], language="ja",
                valid_from=DATE, valid_until=UNTIL, name_type="canonical",
                source_id=spec["source_id"]))
        trip_id = spec["trip_id"]
        version_id, calendar_id = trip_id + ".version", trip_id + ".calendar"
        source_ids = [spec["source_id"]]
        if "line_source_id" in spec:
            source_ids.append(spec["line_source_id"])
        output["timetable-versions"].append(dict(
            timetable_version_id=version_id, operator_scope=spec["operator"],
            effective_from=DATE, effective_until=UNTIL,
            edition_name="JR時刻表2026年10月号 exact 2026-09-30 train detail",
            revision_type="source_snapshot", completeness="partial", source_ids=source_ids))
        output["calendars"].append(dict(calendar_id=calendar_id, valid_from=DATE,
                                        valid_until=UNTIL, holiday_policy="none",
                                        **{day: 0 for day in WEEKDAYS}))
        output["calendar-exceptions"].append(dict(
            calendar_id=calendar_id, service_date=DATE, exception_type="add",
            source_id=spec.get("line_source_id", spec["source_id"]),
            reason="Exact-date official timetable; no recurrence inferred"))
        trip_record = dict(
            trip_id=trip_id, timetable_version_id=version_id, service_id=spec["service_id"],
            calendar_id=calendar_id, train_number=spec["train_number"],
            public_number=spec["public_number"],
            origin_station_id=stations[names[0]]["station_id"],
            destination_station_id=stations[names[-1]]["station_id"],
            service_class="limited_express",
            notes="One exact-date official detail: published passenger calls only. Operator boundaries and physical lines unresolved.")
        if trip.get("direction"):
            trip_record["direction"] = trip["direction"]
        output["trips"].append(trip_record)
        for sequence, stop in enumerate(trip["stop_times"], 1):
            call = "origin" if sequence == 1 else "destination" if sequence == len(names) else "passenger_stop"
            output["stop-times"].append(dict(
                trip_id=trip_id, stop_sequence=sequence, station_id=stations[stop["name_snapshot"]]["station_id"],
                arrival_time=stop["arrival_time"], departure_time=stop["departure_time"],
                day_offset=0, call_type=call, pickup_allowed=0 if call == "destination" else 1,
                dropoff_allowed=0 if call == "origin" else 1, platform=stop["platform"],
                time_accuracy="minute", source_id=spec["source_id"]))
        printed_seats = trip.get("seat_description_snapshot", [])
        if printed_seats != ["「白いソニック」で運転", "グリーン車指定席", "普通車一部指定席"]:
            raise ValueError("Sonic 14 printed seat categories changed")
        guide_sources = {row["source_id"]: row for row in rows("sources/source-registry*.jsonl")}
        guide_id = "jr-kyushu-sonic-configuration-guide-20260930"
        equipment_id = "jr-kyushu-sonic-equipment-guide-20260930"
        diagram_id = "jr-kyushu-sonic-885-diagram-20260930"
        if (guide_sources[guide_id]["url_or_locator"] != "https://www.jrkyushu.co.jp/english/train/sonic.html" or
                guide_sources[equipment_id]["url_or_locator"] !=
                "https://www.jrkyushu.co.jp/train/kids/guardian/train_equipment/index.html" or
                guide_sources[diagram_id]["url_or_locator"] !=
                "https://www.jrkyushu.co.jp/lang/assets/img/train/sonic/img_configuration02_pc.png"):
            raise ValueError("Sonic 14 formation guide source changed")
        formation_id = f"{trip_id}.formation.{DATE}"
        output["trip-formations"].append(dict(
            formation_id=formation_id, trip_id=trip_id, service_date=DATE,
            evidence_kind="planned", source_id=spec["source_id"], vehicle_series="885", car_count=6,
            all_reserved=False, green_car_available=True,
            notes="Exact-date page prints white Sonic and seat categories; JR Kyushu configuration guide assigns Sonic 14 to 885 series. Equipment guide lists six cars. Actual consist unverified."))
        for car_number in range(1, 7):
            car = dict(formation_id=formation_id, car_sequence=car_number,
                       car_number=str(car_number), vehicle_series="885", source_id=diagram_id)
            if car_number == 1:
                car["notes"] = "Diagram shows Green and reserved ordinary seats; mixed car seat_class is unset."
            elif car_number == 2:
                car.update(seat_class="ordinary", reservation_type="reserved")
            elif car_number >= 5:
                car.update(seat_class="ordinary", reservation_type="non_reserved")
            else:
                car["notes"] = "Reserved versus non-reserved allocation varies by train."
            output["trip-formation-cars"].append(car)
        for field, provenance, locator in (
            ("all_reserved", spec["source_id"], "列車設備: 普通車一部指定席"),
            ("green_car_available", spec["source_id"], "列車設備: グリーン車指定席"),
            ("vehicle_series", guide_id, "Train Configuration / 885 Series / No. 14"),
            ("car_count", equipment_id, "列車の設備 / 885系 6両"),
        ):
            output["fact-sources"].append(dict(entity_type="trip", entity_id=trip_id,
                field_name=f"formation.{field}", source_id=provenance,
                page_or_locator=locator, confidence="high", verification_status="verified"))
        output["fact-completeness"].append(dict(entity_type="trip", entity_id=trip_id,
            dimension="formation", status="partial", confidence="high",
            notes="Published planned series, six cars and seat categories; actual consist and variable car 3/4 seats unknown."))
        dimensions = {
            "identity": ("verified", "high", "Official train detail prints limited express family and public number."),
            "train_number": ("verified", "high", f"Official detail prints {spec['train_number']}."),
            "operator": ("unknown", "low", "Publishing company is not an ordered operator-boundary proof."),
            "validity_calendar": ("verified", "high", "Only the directly listed 2026-09-30 occurrence is emitted."),
            "origin_destination": ("verified", "high", "First and last passenger rows are printed."),
            "stops": ("verified", "high", f"{len(names)} published passenger calls, excluding レ rows."),
            "times": ("verified", "high", "Printed arrival and departure sides are preserved; missing sides remain null."),
            "route_lines": ("unknown", "low", "No dated ordered physical line IDs are established."),
            "station_refs": ("verified", "high", "Names match unique current station source codes."),
            "provenance": ("partial", "medium", "Official page is pinned for verification; reuse permission unresolved."),
        }
        for dimension, (status, confidence, notes) in dimensions.items():
            output["fact-completeness"].append(dict(entity_type="trip", entity_id=trip_id,
                                                     dimension=dimension, status=status,
                                                     confidence=confidence, notes=notes))
            if status == "verified":
                source = STATION_SOURCE if dimension == "station_refs" else (
                    spec.get("line_source_id", spec["source_id"]) if dimension == "validity_calendar"
                    else spec["source_id"])
                output["fact-sources"].append(dict(entity_type="trip", entity_id=trip_id,
                                                   field_name=dimension, source_id=source,
                                                   page_or_locator="exact-date train detail / dated line grid",
                                                   confidence=confidence, verification_status=status))
        for dimension, status, notes in (
            ("operator", "open", "Find dated ordered operator segment boundaries."),
            ("route_lines", "open", "Find dated ordered physical line identities and validity."),
            ("provenance", "license_blocked", "No redistribution or automated extraction grant found."),
        ):
            output["research-queue"].append(dict(
                research_id=f"{trip_id}.{dimension}", entity_type="trip", entity_id=trip_id,
                missing_dimension=dimension, status=status, notes=notes))

    paths = {
        "source-registry": registry_target,
        "services": service_target,
        "service-name-periods": BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl",
        "timetable-versions": BASE / f"normalized/timetable-versions-{SUFFIX}.jsonl",
        "station-identities": station_target,
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
    for kind, path in paths.items():
        write(path, sorted(output[kind], key=lambda row: json.dumps(row, ensure_ascii=False, sort_keys=True)))
    print("Normalized 1 exact-day trip and 8 passenger calls; routes and operators remain unresolved")


if __name__ == "__main__":
    main()
