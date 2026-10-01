#!/usr/bin/env python3
"""Promote only the visually checked 2026-09-29/30 Tokachi 1 columns."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-hokkaido-tokachi1-20260929-30.json"
SUFFIX = "hokkaido-tokachi1-20260929-30"
STATION_SOURCE = "jtm-current-station-directory"
DATES = ("2026-09-29", "2026-09-30")
NAMES = ("札幌", "新札幌", "南千歳", "追分", "新夕張", "占冠", "トマム",
         "新得", "十勝清水", "芽室", "帯広")
CLOCKS = ((None, "7:58"), (None, "8:07"), (None, "8:27"),
          (None, "8:40"), (None, "8:59"), (None, "9:27"),
          (None, "9:42"), ("10:05", "10:05"), (None, "10:13"),
          (None, "10:34"), ("10:43", None))


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in rows), encoding="utf-8")


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    manifest = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    if (candidate["candidate_status"] != "visually_reviewed"
            or tuple(candidate["service_dates"]) != DATES
            or max(DATES) > manifest["as_of_date"]):
        raise ValueError("Tokachi candidate date differs from reviewed columns")
    if (candidate["service_id"], candidate["canonical_name"], candidate["english_name"],
            candidate["public_number"], candidate["train_number"], candidate["direction"]) != (
            "tokachi", "とかち", "Tokachi", "1", "31D", "札幌→帯広"):
        raise ValueError("Tokachi identity differs from reviewed columns")
    calls = candidate["passenger_calls"]
    if (tuple(call["station"] for call in calls) != NAMES
            or tuple((call.get("arrival_time"), call.get("departure_time"))
                     for call in calls) != CLOCKS):
        raise ValueError("Tokachi passenger calls differ from reviewed columns")

    source_ids = candidate["source_ids"]
    if set(source_ids) != set(DATES):
        raise ValueError("Both dated timetable sources are required")
    guide_id = candidate["guide_source_id"]
    english_id = candidate["english_source_id"]
    sources = []
    for day in DATES:
        source_id = source_ids[day]
        compact = day.replace("-", "")
        if source_id != f"jr-hokkaido-tokachi1-{compact}-timetable":
            raise ValueError("Unexpected dated source id")
        sources.append({
            "source_id": source_id,
            "publisher": "北海道旅客鉄道株式会社 / 株式会社交通新聞社",
            "title": f"［特急］おおぞら・とかち 下り {day}",
            "source_type": "official_timetable",
            "url_or_locator": f"https://jrhokkaidonorikae.com/vtime/vtime.php?d={compact}&s=130",
            "issue": "JR時刻表 令和8年10月号" if day == "2026-09-30" else "JR時刻表 令和8年9月号",
            "effective_date": day,
            "accessed_at": "2026-09-29",
            "license_status": "terms_published_no_reuse_grant_identified",
            "redistribution_status": "verification_only",
            "automated_extraction_allowed": False,
            "notes": "Visually checked selected 31D column on this date; no assertion for other dates or unprinted arrival sides.",
        })
    sources += [
        {"source_id": guide_id, "publisher": "北海道旅客鉄道株式会社",
         "title": "特急とかち（キハ261系1000代）", "source_type": "official_train_service_guide",
         "url_or_locator": "https://www.jrhokkaido.co.jp/train/tr005_01.html",
         "issue": None, "accessed_at": "2026-09-29",
         "license_status": "no_reuse_grant_identified", "redistribution_status": "verification_only",
         "automated_extraction_allowed": False,
         "notes": "Official service guide identifies とかち as a limited express between 札幌 and 帯広; stop patterns vary by train."},
        {"source_id": english_id, "publisher": "北海道旅客鉄道株式会社",
         "title": "Information on Limited Express Trains (All Seats Reserved)",
         "source_type": "official_train_service_guide",
         "url_or_locator": "https://www.jrhokkaido.co.jp/global/english/ticket/usage/usage03.html",
         "issue": None, "accessed_at": "2026-09-29",
         "license_status": "no_reuse_grant_identified", "redistribution_status": "verification_only",
         "automated_extraction_allowed": False,
         "notes": "Official English list prints Ltd. Exp. Tokachi (Sapporo – Obihiro)."},
    ]

    rail = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
    stations = {}
    for name in NAMES:
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

    day, until = DATES[0], "2026-10-01"
    source_id = source_ids[DATES[-1]]
    trip_id = "jr-hokkaido.tokachi.1.2026-09-29-30"
    version_id = "jr-hokkaido.tokachi.2026-09-29-30.version"
    calendar_id = "jr-hokkaido.tokachi.2026-09-29-30.calendar"
    output = {
        "services": [{"service_id": "tokachi", "canonical_name": "とかち",
                      "service_class": "limited_express", "historical_generation": 1,
                      "jr_scope": "jr", "first_verified_date": day,
                      "last_verified_date": DATES[-1]}],
        "service-name-periods": [
            {"service_id": "tokachi", "name": "とかち", "language": "ja",
             "valid_from": day, "valid_until": until, "name_type": "canonical", "source_id": source_id},
            {"service_id": "tokachi", "name": "Tokachi", "language": "en",
             "valid_from": day, "valid_until": until, "name_type": "official_english",
             "source_id": english_id},
        ],
        "timetable-versions": [{"timetable_version_id": version_id,
                                "operator_scope": "jr-hokkaido", "effective_from": day,
                                "effective_until": until, "edition_name": "JR時刻表 令和8年9月号・10月号（選択日別）",
                                "revision_type": "planned_exception", "publication_date": None,
                                "completeness": "partial",
                                "source_ids": [source_ids[d] for d in DATES] + [guide_id, english_id]}],
        "calendars": [{"calendar_id": calendar_id, "valid_from": day, "valid_until": until,
                       "holiday_policy": "none", **{weekday: 0 for weekday in
                       ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")}}],
        "calendar-exceptions": [
            {"calendar_id": calendar_id, "service_date": d, "exception_type": "add",
             "source_id": source_ids[d],
             "reason": f"Selected {d} column prints 31D as 毎日; only reviewed dates promoted."}
            for d in DATES],
        "trips": [{"trip_id": trip_id, "timetable_version_id": version_id,
                   "service_id": "tokachi", "calendar_id": calendar_id,
                   "train_number": "31D", "public_number": "1",
                   "origin_station_id": stations["札幌"],
                   "destination_station_id": stations["帯広"],
                   "direction": "札幌→帯広", "service_class": "limited_express",
                   "notes": "Both selected dated columns reviewed; no overnight call. Physical route and unprinted arrival sides unresolved."}],
        "stop-times": [], "fact-completeness": [], "fact-sources": [],
        "research-queue": [], "station-identities": new_stations,
    }
    for index, call in enumerate(calls, 1):
        output["stop-times"].append({
            "trip_id": trip_id, "stop_sequence": index,
            "station_id": stations[call["station"]],
            "arrival_time": call.get("arrival_time"),
            "departure_time": call.get("departure_time"),
            "day_offset": 0,
            "call_type": "origin" if index == 1 else "destination" if index == len(calls) else "passenger_stop",
            "pickup_allowed": 0 if index == len(calls) else 1,
            "dropoff_allowed": 0 if index == 1 else 1,
            "time_accuracy": "minute", "source_id": source_id,
        })
    dimensions = {
        "identity": ("verified", "high", source_id, "31D column and official service guide"),
        "train_number": ("verified", "high", source_id, "31D heading"),
        "operator": ("partial", "medium", guide_id, "JR Hokkaido guide identifies the service, but ordered operating boundary is not promoted"),
        "validity_calendar": ("verified", "high", source_id, "Selected September 29 and 30 columns, 毎日"),
        "origin_destination": ("verified", "high", source_id, "札幌 7:58–帯広 10:43"),
        "stops": ("verified", "high", source_id, "Eleven passenger calls in both selected columns"),
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
    print(f"Normalized Tokachi 1 for {len(DATES)} selected dates with {len(calls)} passenger calls")


if __name__ == "__main__":
    main()
