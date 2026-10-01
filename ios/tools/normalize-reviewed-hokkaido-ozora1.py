#!/usr/bin/env python3
"""Promote the reviewed 2026-09-30 Ozora 1 column without inferring other dates."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-hokkaido-ozora1-20260930.json"
SUFFIX = "hokkaido-ozora1-20260930"
STATION_SOURCE = "jtm-current-station-directory"


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in rows), encoding="utf-8")


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    day = candidate["service_date"]
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    if candidate["candidate_status"] != "visually_reviewed" or day != "2026-09-30" or day > manifest["as_of_date"]:
        raise ValueError("Ozora candidate is outside its reviewed date")
    if (candidate["service_id"], candidate["canonical_name"], candidate["english_name"],
            candidate["public_number"], candidate["train_number"]) != (
            "ozora", "おおぞら", "Ozora", "1", "4001D"):
        raise ValueError("Ozora identity differs from the reviewed official column")
    stops = candidate["passenger_calls"]
    expected_names = ["札幌", "新札幌", "南千歳", "追分", "新夕張", "トマム",
                      "新得", "帯広", "池田", "釧路"]
    if [row["station"] for row in stops] != expected_names or len(stops) != 10:
        raise ValueError("Ozora passenger calls differ from the reviewed column")
    if stops[0].get("departure_time") != "6:48" or stops[-1].get("arrival_time") != "10:56":
        raise ValueError("Ozora endpoint clocks differ from the reviewed column")

    source_id = candidate["source_id"]
    guide_id = candidate["train_guide_source_id"]
    english_id = candidate["english_source_id"]
    sources = [
        {
            "source_id": source_id,
            "publisher": "北海道旅客鉄道株式会社 / 株式会社交通新聞社",
            "title": "［特急］おおぞら・とかち 下り 2026年9月30日",
            "source_type": "official_timetable",
            "url_or_locator": "https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=130",
            "issue": "JR時刻表 令和8年10月号",
            "effective_date": day,
            "accessed_at": "2026-09-30",
            "license_status": "terms_published_no_reuse_grant_identified",
            "redistribution_status": "verification_only",
            "automated_extraction_allowed": False,
            "notes": "Visually reviewed selected 4001D column for September 30 only; passing rows are excluded and unprinted arrival sides remain null. No claim for another date.",
        },
        {
            "source_id": guide_id,
            "publisher": "北海道旅客鉄道株式会社",
            "title": "特急おおぞら（261系）",
            "source_type": "official_train_service_guide",
            "url_or_locator": "https://www.jrhokkaido.co.jp/train/tr007_01.html",
            "issue": "2025年3月現在",
            "accessed_at": "2026-09-30",
            "license_status": "no_reuse_grant_identified",
            "redistribution_status": "verification_only",
            "automated_extraction_allowed": False,
            "notes": "Official JR Hokkaido guide identifies おおぞら as a limited express linking 札幌 and 釧路; stop patterns differ by train.",
        },
        {
            "source_id": english_id,
            "publisher": "北海道旅客鉄道株式会社",
            "title": "Trains bound for Obihiro / Kushiro",
            "source_type": "official_train_service_guide",
            "url_or_locator": "https://www.jrhokkaido.co.jp/global/english/train/guide/obihiro.html",
            "issue": "Information current as of March 2026",
            "accessed_at": "2026-09-30",
            "license_status": "no_reuse_grant_identified",
            "redistribution_status": "verification_only",
            "automated_extraction_allowed": False,
            "notes": "Official 2026 English heading uses Ltd. Exp. Ozora and states Sapporo–Kushiro.",
        },
    ]

    rail = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    stations = {}
    for name in expected_names:
        codes = {station[0] for line in rail["lines"] if line["operator"] == "北海道旅客鉄道"
                 for station in line["stations"] if station[1] == name}
        if len(codes) != 1:
            raise ValueError(f"Current station identity is not unique for {name}: {codes}")
        stations[name] = "jp.n02." + codes.pop()
    existing = {}
    for path in (BASE / "normalized").glob("station-identities*.jsonl"):
        if path.name == f"station-identities-{SUFFIX}.jsonl":
            continue
        for raw in path.read_text(encoding="utf-8").splitlines():
            if raw.strip():
                row = json.loads(raw)
                existing[row["station_id"]] = row
    new_stations = []
    for name, station_id in stations.items():
        code = station_id.removeprefix("jp.n02.")
        if station_id in existing:
            if existing[station_id]["name_snapshot"] != name:
                raise ValueError(f"Station name conflict for {station_id}")
        else:
            new_stations.append({"station_id": station_id, "name_snapshot": name,
                                 "reference_kind": "current_n02", "current_source_code": code})

    service_id = candidate["service_id"]
    trip_id = "jr-hokkaido.ozora.1.2026-09-30"
    version_id = "jr-hokkaido.ozora.2026-09-30.version"
    calendar_id = "jr-hokkaido.ozora.2026-09-30.calendar"
    until = "2026-10-01"
    output = {
        "services": [{"service_id": service_id, "canonical_name": candidate["canonical_name"],
                      "service_class": "limited_express", "historical_generation": 1,
                      "jr_scope": "jr", "first_verified_date": day, "last_verified_date": day}],
        "service-name-periods": [
            {"service_id": service_id, "name": candidate["canonical_name"], "language": "ja",
             "valid_from": day, "valid_until": until, "name_type": "canonical", "source_id": source_id},
            {"service_id": service_id, "name": candidate["english_name"], "language": "en",
             "valid_from": day, "valid_until": until, "name_type": "official_english", "source_id": english_id},
        ],
        "timetable-versions": [{"timetable_version_id": version_id,
                                "operator_scope": "jr-hokkaido", "effective_from": day,
                                "effective_until": until, "edition_name": "JR時刻表 令和8年10月号",
                                "revision_type": "planned_exception", "publication_date": None,
                                "completeness": "partial", "source_ids": [source_id, guide_id, english_id]}],
        "calendars": [{"calendar_id": calendar_id, "valid_from": day, "valid_until": until,
                       "holiday_policy": "none", **{weekday: 0 for weekday in
                       ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")}}],
        "calendar-exceptions": [{"calendar_id": calendar_id, "service_date": day,
                                 "exception_type": "add", "source_id": source_id,
                                 "reason": "Selected 2026-09-30 column prints 4001D as 毎日; only this date promoted."}],
        "trips": [{"trip_id": trip_id, "timetable_version_id": version_id,
                   "service_id": service_id, "calendar_id": calendar_id,
                   "train_number": "4001D", "public_number": "1",
                   "origin_station_id": stations["札幌"], "destination_station_id": stations["釧路"],
                   "direction": candidate["direction"], "service_class": "limited_express",
                   "notes": "Only the September 30 selected column is reviewed; physical route and unprinted arrival sides remain unresolved."}],
        "stop-times": [], "fact-completeness": [], "fact-sources": [], "research-queue": [],
        "station-identities": new_stations,
    }
    for index, call in enumerate(stops, 1):
        output["stop-times"].append({
            "trip_id": trip_id, "stop_sequence": index, "station_id": stations[call["station"]],
            "arrival_time": call.get("arrival_time"), "departure_time": call.get("departure_time"),
            "day_offset": 0,
            "call_type": "origin" if index == 1 else "destination" if index == len(stops) else "passenger_stop",
            "pickup_allowed": 0 if index == len(stops) else 1,
            "dropoff_allowed": 0 if index == 1 else 1,
            "time_accuracy": "minute", "source_id": source_id,
        })
    dimensions = {
        "identity": ("verified", "high", source_id, "4001D column and official service guide"),
        "train_number": ("verified", "high", source_id, "4001D heading"),
        "operator": ("partial", "medium", guide_id, "JR Hokkaido guide identifies the service, but no ordered operating boundary is promoted"),
        "validity_calendar": ("verified", "high", source_id, "Selected September 30 column, 毎日"),
        "origin_destination": ("verified", "high", source_id, "札幌 6:48–釧路 10:56"),
        "stops": ("verified", "high", source_id, "Passenger calls in selected column; レ rows omitted"),
        "times": ("partial", "high", source_id, "Only printed arrival/departure sides are known"),
        "route_lines": ("unknown", "low", None, "No complete ordered physical-line evidence"),
        "station_refs": ("partial", "medium", STATION_SOURCE, "Current N02 codes lack exact historical validity"),
        "provenance": ("partial", "high", source_id, "Official timetable is verification only"),
    }
    for dimension, (status, confidence, evidence_source, notes) in dimensions.items():
        output["fact-completeness"].append({"entity_type": "trip", "entity_id": trip_id,
                                            "dimension": dimension, "status": status,
                                            "confidence": confidence, "notes": notes})
        if evidence_source is not None:
            output["fact-sources"].append({"entity_type": "trip", "entity_id": trip_id,
                                           "field_name": dimension, "source_id": evidence_source,
                                           "page_or_locator": notes, "confidence": confidence,
                                           "verification_status": status})
    for dimension, status, notes in [
        ("operator", "open", "Obtain complete ordered operator-boundary evidence."),
        ("times", "open", "Obtain unprinted intermediate arrival sides from a working timetable."),
        ("route_lines", "open", "Obtain dated ordered physical-line identities."),
        ("station_refs", "open", "Confirm exact-date station identities rather than current N02 only."),
        ("provenance", "license_blocked", "Timetable terms do not grant redistribution or automated extraction."),
    ]:
        output["research-queue"].append({"research_id": f"{trip_id}.{dimension}",
                                         "entity_type": "trip", "entity_id": trip_id,
                                         "missing_dimension": dimension, "status": status,
                                         "notes": notes})

    write(BASE / f"sources/source-registry-{SUFFIX}.jsonl", sources)
    for entity, rows in output.items():
        if entity in {"calendars", "calendar-exceptions", "trips", "stop-times"}:
            path = BASE / f"normalized/{entity}/reviewed-{SUFFIX}/seeds.jsonl"
        else:
            path = BASE / f"normalized/{entity}-{SUFFIX}.jsonl"
        write(path, rows)
    print(f"Normalized one dated Ozora trip with {len(stops)} source-pinned passenger calls")


if __name__ == "__main__":
    main()
