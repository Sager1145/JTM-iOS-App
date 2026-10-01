#!/usr/bin/env python3
"""Stage source-pinned, planned formation facts on one exact service date."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-formations-20260930"
DAY = "2026-09-30"
IBUSUKI = BASE / "candidates/jr-kyushu-ibusuki-20260930-formation.json"
CALENDAR_SOURCE = "jr-kyushu-ibusuki-formation-calendar-20260928"
POLICY_SOURCE = "jr-hokkaido-all-limited-express-reserved-20260314"
PAGE_IDS = {
    "s=150": {"jr-hokkaido-hokuto-suzuran-down-20260930",
              "jr-hokkaido-hokuto-suzuran-down-extra-20260930"},
    "s=151": {"jr-hokkaido-hokuto-suzuran-up-20260930"},
    "s=130": {"jr-hokkaido-ozora1-20260930-timetable",
              "jr-hokkaido-tokachi1-20260930-timetable",
              "jr-hokkaido-ozora-tokachi-down-extra-20260930"},
    "s=131": {"jr-hokkaido-ozora-tokachi-up-20260930"},
}
ASAHIKAWA_GREEN = {
    "s=110": {"3001M", "3003M", "3005M", "3011M", "3013M", "3017M", "3023M", "3025M", "3027M", "51D", "6063D"},
    "s=111": {"3002M", "3008M", "3012M", "3014M", "3016M", "3020M", "3022M", "3024M", "52D", "6064D"},
}
ASAHIKAWA_ICON_SOURCE = {
    "s=110": "jr-hokkaido-lilac-kamui-down-extra-20260930",
    "s=111": "jr-hokkaido-lilac-kamui-up-extra-20260930",
}
EXPECTED = {
    "hokuto": {"1": "1D", "2": "2D", "3": "3D", "5": "5D", "7": "7D", "9": "9D", "11": "11D", "13": "13D", "15": "15D", "17": "17D", "19": "19D"},
    "suzuran": {"1": "1001M", "2": "1002M", "3": "1003M", "5": "1005M", "7": "1007M", "9": "1009M", "11": "1011M"},
    "ozora": {"1": "4001D", "2": "4002D", "3": "4003D", "4": "4004D", "5": "4005D", "6": "4006D", "7": "4007D", "8": "4008D", "9": "4009D", "10": "4010D", "11": "4011D", "12": "4012D"},
    "tokachi": {"1": "31D", "2": "32D", "3": "33D", "4": "34D", "5": "35D", "6": "36D", "7": "37D", "8": "38D", "9": "39D", "10": "40D"},
}


def read_rows(pattern):
    return [json.loads(line) for path in BASE.glob(pattern)
            if SUFFIX not in path.parts and SUFFIX not in path.name
            for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def main():
    candidate = json.loads(IBUSUKI.read_text(encoding="utf-8"))
    if (candidate["candidate_status"], candidate["canonical"], candidate["service_date"],
        candidate["formation_label"], candidate["car_count"], candidate["reserved_seat_capacity"],
        candidate["all_reserved"]) != ("visually_reviewed", False, DAY, "C", 2, 63, True):
        raise ValueError("JR Kyushu dated C formation changed")
    if [(car["car_sequence"], car["car_number"], car["vehicle_series"])
        for car in candidate["cars_origin_to_destination"]] != [
            (1, "2", "キハ140"), (2, "1", "キハ47")]:
        raise ValueError("JR Kyushu printed two-car diagram changed")
    if DAY > json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))["as_of_date"]:
        raise ValueError("Formation date exceeds dataset as-of date")

    trips = read_rows("normalized/trips/**/*.jsonl")
    stops = read_rows("normalized/stop-times/**/*.jsonl")
    sources = {row["source_id"]: row for row in read_rows("sources/source-registry*.jsonl")}
    first_source = {}
    for row in sorted(stops, key=lambda row: row["stop_sequence"]):
        first_source.setdefault(row["trip_id"], row["source_id"])
    formations, cars, facts, completeness = [], [], [], []
    count = 0
    for service, numbers in EXPECTED.items():
        for public, train_number in numbers.items():
            matches = [trip for trip in trips if trip["service_id"] == service
                       and trip.get("public_number") == public and trip.get("train_number") == train_number
                       and (trip["trip_id"].endswith(DAY) or trip["trip_id"].endswith("2026-09-29-30"))]
            if len(matches) != 1:
                raise ValueError(f"Expected one dated trip for {service} {public}: {matches}")
            trip = matches[0]
            source_id = first_source[trip["trip_id"]]
            source = sources[source_id]
            if source_id not in set().union(*PAGE_IDS.values()) or source["effective_date"] != DAY:
                raise ValueError(f"Formation source is not exact 2026-09-30: {source_id}")
            fid = f"{trip['trip_id']}.formation.{DAY}"
            green = True if service in {"hokuto", "ozora", "tokachi"} else None
            formations.append({"formation_id": fid, "trip_id": trip["trip_id"], "service_date": DAY,
                "evidence_kind": "planned", "all_reserved": True, "green_car_available": green,
                "source_id": source_id,
                "notes": "Date-selected official formation icons; no actual vehicle series, car count, or per-car diagram inferred."})
            for field, locator in (("all_reserved", "2026-09-30 編成 row: 全車指定席 icon"),
                                   ("green_car_available", "2026-09-30 編成 row: グリーン車 icon")):
                if field == "green_car_available" and green is None:
                    continue
                facts.append({"entity_type": "trip", "entity_id": trip["trip_id"],
                    "field_name": f"formation.{field}", "source_id": source_id,
                    "page_or_locator": locator, "confidence": "high", "verification_status": "verified"})
            facts.append({"entity_type": "trip", "entity_id": trip["trip_id"],
                "field_name": "formation.reservation_policy", "source_id": POLICY_SOURCE,
                "page_or_locator": "2026-03-14 all limited express trains reserved-seat policy",
                "confidence": "high", "verification_status": "verified"})
            completeness.append({"entity_type": "trip", "entity_id": trip["trip_id"],
                "dimension": "formation", "status": "partial", "confidence": "high",
                "notes": "All-reserved and published green-car icon recorded; actual car count, vehicle series and per-car assignments not verified."})
            count += 1
    if count != 40:
        raise ValueError(f"Expected 40 dated Hokkaido formation-icon records, got {count}")

    # The operator's 2026-03-14 policy covers every limited express on this
    # service date.  The date-selected Asahikawa columns add green-car icons
    # for only the 21 reviewed train numbers below.
    import train_timetable as timetable
    dataset, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
    detailed_ids = {row["trip_id"] for row in formations}
    externally_sourced_ids = {row["trip_id"] for row in read_rows("normalized/trip-formations/**/*.jsonl")}
    policy_trips = [trip for trip in timetable.materialize(dataset, DAY)
                    if trip["trip_id"].startswith("jr-hokkaido.")
                    and trip["service_class"] == "limited_express"
                    and trip["trip_id"] not in detailed_ids
                    and trip["trip_id"] not in externally_sourced_ids]
    green_sections = {number: section for section, numbers in ASAHIKAWA_GREEN.items()
                      for number in numbers}
    if len(green_sections) != 21:
        raise ValueError("Expected 21 distinct date-reviewed Asahikawa green-car columns")
    seen_green = set()
    for trip in policy_trips:
        tid = trip["trip_id"]
        train_number = trip["train_number"]
        section = green_sections.get(train_number)
        source_id = POLICY_SOURCE
        if section:
            if train_number in seen_green:
                raise ValueError(f"Duplicate Asahikawa train number {train_number}")
            seen_green.add(train_number)
            # Sarobetsu's stop source is the narrower s=2890/2891 table;
            # its green icon was reviewed in the same day's s=110/111 table.
            source_id = first_source[tid]
            expected_url = f"https://jrhokkaidonorikae.com/vtime/vtime.php?d={DAY.replace('-', '')}&{section}"
            if sources[source_id]["url_or_locator"] != expected_url:
                source_id = ASAHIKAWA_ICON_SOURCE[section]
            source = sources[source_id]
            if source["url_or_locator"] != expected_url or source["effective_date"] != DAY:
                raise ValueError(f"Asahikawa green icon lacks exact-day source for {tid}")
        formations.append({"formation_id": f"{tid}.formation.{DAY}", "trip_id": tid,
            "service_date": DAY, "evidence_kind": "planned", "all_reserved": True,
            "green_car_available": True if section else None,
            "source_id": source_id,
            "notes": "Date-selected Asahikawa column prints green-car and all-reserved icons; no dated car count or vehicle series." if section
                     else "Operator-wide all-reserved policy effective 2026-03-14; no dated car count or vehicle-series assignment."})
        facts.append({"entity_type": "trip", "entity_id": tid,
            "field_name": "formation.all_reserved", "source_id": POLICY_SOURCE,
            "page_or_locator": "2026-03-14 all limited express trains reserved-seat policy",
            "confidence": "high", "verification_status": "verified"})
        if section:
            facts.append({"entity_type": "trip", "entity_id": tid,
                "field_name": "formation.green_car_available", "source_id": source_id,
                "page_or_locator": f"2026-09-30 {section} train {train_number}, 編成 row: greensiteidai0.png and zensekisitei0.png",
                "confidence": "high", "verification_status": "verified"})
        completeness.append({"entity_type": "trip", "entity_id": tid,
            "dimension": "formation", "status": "partial", "confidence": "high" if section else "medium",
            "notes": "Date-selected green-car and all-reserved icons; exact car count, series and car diagram unverified." if section
                     else "All-reserved policy applies; exact train car count, series and car diagram unverified."})
    if seen_green != set(green_sections):
        raise ValueError(f"Missing date-reviewed Asahikawa columns: {sorted(set(green_sections) - seen_green)}")
    if len(formations) != 70:
        raise ValueError(f"Expected 70 dated JR Hokkaido limited-express reservation records, got {len(formations)}")

    ibusuki_ids = candidate["trip_ids"]
    expected_ids = [f"jr-kyushu.ibusuki-no-tamatebako.{n}.2026-07-01" for n in range(1, 7)]
    if ibusuki_ids != expected_ids or candidate["trip_id"] != expected_ids[0]:
        raise ValueError("Ibusuki daily calendar trip scope changed")
    by_id = {trip["trip_id"]: trip for trip in trips}
    daily = {trip["trip_id"] for trip in timetable.materialize(dataset, DAY)}
    for number, ibusuki in enumerate(ibusuki_ids, 1):
        if ibusuki not in daily or by_id[ibusuki]["public_number"] != str(number):
            raise ValueError(f"Ibusuki {number} is not an attested September 30 trip")
        fid = f"{ibusuki}.formation.{DAY}"
        formations.append({"formation_id": fid, "trip_id": ibusuki, "service_date": DAY,
            "evidence_kind": "planned", "formation_label": "C", "car_count": 2,
            "reserved_seat_capacity": 63, "all_reserved": True, "source_id": CALENDAR_SOURCE,
            "notes": "Service-wide September 30 C pattern applied to this numbered trip; planned inference, subject to inspection substitutions."})
        directional_cars = candidate["cars_origin_to_destination"]
        if number % 2 == 0:
            directional_cars = list(reversed(directional_cars))
        for sequence, car in enumerate(directional_cars, 1):
            cars.append({"formation_id": fid, **car, "car_sequence": sequence,
                         "source_id": CALENDAR_SOURCE})
        facts.extend([
            {"entity_type": "trip", "entity_id": ibusuki, "field_name": "formation.schedule",
             "source_id": CALENDAR_SOURCE,
             "page_or_locator": f"p1 September 30 C service-wide calendar; p2 C diagram; {number}号 assignment inferred",
             "confidence": "medium", "verification_status": "partial"},
            {"entity_type": "trip", "entity_id": ibusuki, "field_name": "formation.all_reserved",
             "source_id": "jr-kyushu-ibusuki-no-tamatebako-timetable-20260314",
             "page_or_locator": "Official train page: 全車指定席",
             "confidence": "high", "verification_status": "verified"},
        ])
        completeness.append({"entity_type": "trip", "entity_id": ibusuki,
            "dimension": "formation", "status": "partial", "confidence": "medium",
            "notes": "Daily planned C pattern applies to service; numbered-trip assignment inferred, actual dispatch may differ."})

    source_rows = [
        {"source_id": CALENDAR_SOURCE, "publisher": "九州旅客鉄道株式会社",
         "title": "指宿のたまて箱 編成カレンダー 2026年9月–11月",
         "source_type": "official_formation_calendar", "url_or_locator": candidate["calendar_source_url"],
         "issue": "2026年9月28日現在", "publication_date": "2026-09-28",
         "effective_date": DAY, "accessed_at": DAY,
         "license_status": "no_reuse_grant_identified", "redistribution_status": "verification_only",
         "automated_extraction_allowed": False,
         "notes": "p1 September 30=C; p2 C two-car diagram and designated capacity. Planned set may change for inspections."},
        {"source_id": POLICY_SOURCE, "publisher": "北海道旅客鉄道株式会社",
         "title": "特急列車は全車指定席で運転します",
         "source_type": "official_seat_policy", "url_or_locator": "https://www.jrhokkaido.co.jp/zensha/",
         "issue": "2026年3月14日から", "publication_date": None,
         "effective_date": "2026-03-14", "accessed_at": DAY,
         "license_status": "no_reuse_grant_identified", "redistribution_status": "verification_only",
         "automated_extraction_allowed": False,
         "notes": "Policy corroborates the date-selected all-reserved icons; basic formations can change."},
    ]
    write(BASE / f"sources/source-registry-{SUFFIX}.jsonl", source_rows)
    write(BASE / f"normalized/trip-formations/{SUFFIX}/seeds.jsonl", formations)
    write(BASE / f"normalized/trip-formation-cars/{SUFFIX}/seeds.jsonl", cars)
    write(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl", facts)
    write(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl", completeness)
    print(f"Staged {len(formations)} planned formation facts and {len(cars)} car rows")


if __name__ == "__main__":
    main()
