#!/usr/bin/env python3
"""Stage exact-day Ibusuki train numbers and printed endpoint platforms."""

import json
from pathlib import Path

import train_timetable as timetable

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
DAY = "2026-09-30"
SUFFIX = "reviewed-kyushu-ibusuki-six-20260930-details"
CANDIDATE = BASE / "candidates/jr-kyushu-ibusuki-six-20260930-details.json"
BASE_STOPS = BASE / "normalized/stop-times/reviewed-kyushu-next-batch/seeds-kyushu-next-batch.jsonl"
BASE_TRIPS = BASE / "normalized/trips/reviewed-kyushu-next-batch/seeds-kyushu-next-batch.jsonl"
MINUTE_OVERRIDE = BASE / "normalized/trip-stop-time-overrides/reviewed-kyushu-sept-time-change/seeds.jsonl"
NUMBER_OUTPUT = BASE / f"normalized/trip-train-number-overrides/{SUFFIX}/seeds.jsonl"
PLATFORM_OUTPUT = BASE / f"normalized/trip-stop-time-overrides/{SUFFIX}/seeds.jsonl"
SOURCE_OUTPUT = BASE / f"sources/source-registry-{SUFFIX}.jsonl"
FACT_OUTPUT = BASE / f"normalized/fact-sources-{SUFFIX}.jsonl"

# Public number, internal number, source page ID, printed platform stop and value.
EXPECTED = (
    (1, "8071D", "00167701", 1, "4", ("鹿児島中央", "09:56", "指宿", "10:47")),
    (2, "8072D", "00168001", 2, "3", ("指宿", "10:56", "鹿児島中央", "11:48")),
    (3, "8073D", "00167801", 1, "3", ("鹿児島中央", "11:56", "指宿", "12:48")),
    (4, "8074D", "00168101", 2, "4", ("指宿", "12:57", "鹿児島中央", "13:48")),
    (5, "8075D", "00167901", 1, "4", ("鹿児島中央", "13:57", "指宿", "14:49")),
    (6, "8076D", "00168201", 2, "4", ("指宿", "15:07", "鹿児島中央", "16:00")),
)


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def same_clock(left, right):
    if left is None or right is None:
        return left is right
    return timetable.service_seconds(left, 0, "Ibusuki baseline") == timetable.service_seconds(
        right, 0, "Ibusuki candidate")


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
                            for row in records), encoding="utf-8")


def merge_ibusuki_five_platform():
    """Add its platform to the existing 13:57 row, retaining clock and source."""
    lines = MINUTE_OVERRIDE.read_text(encoding="utf-8").splitlines(keepends=True)
    target = ("jr-kyushu.ibusuki-no-tamatebako.5.2026-07-01", DAY, 1)
    matches = []
    for index, line in enumerate(lines):
        row = json.loads(line)
        if (row["trip_id"], row["service_date"], row["stop_sequence"]) == target:
            matches.append((index, row))
    if len(matches) != 1:
        raise ValueError("Expected one existing Ibusuki 5 September 30 minute override")
    index, row = matches[0]
    if (row.get("departure_override"), row.get("source_id"), row.get("arrival_override")) != (
        "13:57", "jr-kyushu-ibusuki-5-20260918-minute-change", None
    ) or row.get("platform_override") not in (None, "4"):
        raise ValueError("Ibusuki 5 minute override conflicts with dated platform")
    if row.get("platform_override_present") == 1 and row.get("platform_override") == "4":
        return
    row["platform_override_present"] = 1
    row["platform_override"] = "4"
    newline = "\n" if lines[index].endswith("\n") else ""
    lines[index] = json.dumps(row, ensure_ascii=False, sort_keys=True) + newline
    MINUTE_OVERRIDE.write_text("".join(lines), encoding="utf-8")


def main():
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    if (candidate["candidate_status"], candidate["canonical"], candidate["service_date"],
            candidate["issue"], candidate["accessed_at"]) != (
            "reviewed_official_html", False, DAY, "JR時刻表2026年10月号", DAY):
        raise ValueError("Ibusuki exact-date candidate metadata changed")
    if len(candidate["trips"]) != 6 or DAY > json.loads((BASE / "manifest.json").read_text())["as_of_date"]:
        raise ValueError("Expected six in-scope September 30 train details")

    templates = {row["trip_id"]: row for row in rows(BASE_TRIPS)}
    stops = {(row["trip_id"], row["stop_sequence"]): row for row in rows(BASE_STOPS)}
    station_names = {row["station_id"]: row["name_snapshot"]
                     for path in BASE.glob("normalized/station-identities*.jsonl") for row in rows(path)}
    dataset, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
    operating = {row["trip_id"] for row in timetable.materialize(dataset, DAY)}
    existing_sources = {row["source_id"] for path in BASE.glob("sources/source-registry*.jsonl")
                        if path != SOURCE_OUTPUT for row in rows(path)}
    existing_platform_keys = {(row["trip_id"], row["service_date"], row["stop_sequence"])
                              for path in BASE.glob("normalized/trip-stop-time-overrides/**/*.jsonl")
                              if path not in (PLATFORM_OUTPUT, MINUTE_OVERRIDE) for row in rows(path)}

    sources, numbers, platforms, facts = [], [], [], []
    for detail, (number, internal, page_id, platform_sequence, platform, clocks) in zip(candidate["trips"], EXPECTED):
        trip_id = f"jr-kyushu.ibusuki-no-tamatebako.{number}.2026-07-01"
        source_id = f"jr-kyushu-ibusuki{number}-detail-20260930"
        station_code = "2900703" if number % 2 else "2891900"
        expected_url = (f"https://www.jrkyushu-timetable.jp/sp/2610/0016/{page_id}.html"
                        f"?t={station_code}&d=20260930")
        if (detail["trip_id"], detail["public_number"], detail["train_number"],
                detail["source_id"], detail["source_url"], detail["equipment"],
                detail["operating_note"]) != (
                trip_id, str(number), internal, source_id, expected_url,
                "普通車全車指定席", "１１月３０日まで運転"):
            raise ValueError(f"Ibusuki {number} official detail changed")
        if source_id in existing_sources or trip_id not in operating:
            raise ValueError(f"Ibusuki {number} source collision or no exact-date occurrence")
        template = templates[trip_id]
        if template["public_number"] != str(number) or template.get("train_number") is not None:
            raise ValueError(f"Ibusuki {number} template identity changed")
        expected_stops = (
            (1, clocks[0], None, clocks[1], platform if platform_sequence == 1 else None),
            (2, clocks[2], clocks[3], None, platform if platform_sequence == 2 else None),
        )
        actual_stops = tuple((s["stop_sequence"], s["station_name"], s["arrival_time"],
                              s["departure_time"], s["platform"]) for s in detail["stops"])
        if actual_stops != expected_stops:
            raise ValueError(f"Ibusuki {number} printed endpoint cells changed")
        for sequence, name, arrival, departure, _ in expected_stops:
            baseline = stops[(trip_id, sequence)]
            if station_names[baseline["station_id"]] != name or not same_clock(baseline.get("arrival_time"), arrival):
                raise ValueError(f"Ibusuki {number} station or arrival baseline changed")
            if not same_clock(baseline.get("departure_time"),
                              "13:56" if number == 5 and sequence == 1 else departure):
                raise ValueError(f"Ibusuki {number} departure baseline changed")
            if baseline.get("platform") is not None:
                raise ValueError(f"Ibusuki {number} template already specifies a platform")
        key = (trip_id, DAY, platform_sequence)
        if key in existing_platform_keys:
            raise ValueError(f"Ibusuki {number} platform override already exists")
        if number != 5:
            platforms.append({"trip_id": trip_id, "service_date": DAY,
                              "stop_sequence": platform_sequence, "platform_override_present": 1,
                              "platform_override": platform, "source_id": source_id})
        sources.append({
            "source_id": source_id, "publisher": "九州旅客鉄道株式会社 / 株式会社交通新聞社",
            "title": f"指宿のたまて箱 {number}号 2026年09月30日の時刻",
            "source_type": "official_dated_train_timetable", "url_or_locator": expected_url,
            "issue": candidate["issue"], "effective_date": DAY,
            "accessed_at": candidate["accessed_at"],
            "license_status": "no_reuse_grant_identified",
            "redistribution_status": "verification_only", "automated_extraction_allowed": False,
            "notes": "Official exact-date train detail; the two endpoint rows and expanded train information were visually checked. No page copy is redistributed.",
        })
        numbers.append({"trip_id": trip_id, "service_date": DAY,
                        "train_number": internal, "source_id": source_id})
        facts.extend((
            {"entity_type": "trip", "entity_id": trip_id, "field_name": "train_number",
             "source_id": source_id, "page_or_locator": f"2026-09-30 列車番号 {internal}",
             "confidence": "high", "verification_status": "verified"},
            {"entity_type": "stop_time", "entity_id": f"{trip_id}:{platform_sequence}",
             "field_name": "platform", "source_id": source_id,
             "page_or_locator": f"2026-09-30 鹿児島中央 のりば {platform}",
             "confidence": "high", "verification_status": "verified"},
            {"entity_type": "trip", "entity_id": trip_id, "field_name": "formation.all_reserved",
             "source_id": source_id, "page_or_locator": "2026-09-30 列車設備 普通車全車指定席",
             "confidence": "high", "verification_status": "verified"},
        ))

    # The existing Ibusuki 5 row owns 13:57. Only its platform cells are added.
    merge_ibusuki_five_platform()
    write(SOURCE_OUTPUT, sources)
    write(NUMBER_OUTPUT, numbers)
    write(PLATFORM_OUTPUT, platforms)
    write(FACT_OUTPUT, facts)
    print("Staged six dated train numbers, six printed platforms, and six equipment citations")


if __name__ == "__main__":
    main()
