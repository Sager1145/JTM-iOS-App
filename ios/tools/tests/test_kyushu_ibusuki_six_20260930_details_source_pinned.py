"""Exact-date JR Kyushu Ibusuki numbers and printed endpoint platforms."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable

DAY = "2026-09-30"
SUFFIX = "reviewed-kyushu-ibusuki-six-20260930-details"
OLD_MINUTE_FILE = BASE / "normalized/trip-stop-time-overrides/reviewed-kyushu-sept-time-change/seeds.jsonl"


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


class IbusukiSixExactDateTests(unittest.TestCase):
    def test_source_pinned_candidate_and_no_inferred_intermediate_rows(self):
        candidate = json.loads((BASE / "candidates/jr-kyushu-ibusuki-six-20260930-details.json")
                               .read_text(encoding="utf-8"))
        self.assertEqual((candidate["candidate_status"], candidate["service_date"], candidate["issue"]),
                         ("reviewed_official_html", DAY, "JR時刻表2026年10月号"))
        self.assertEqual(len(candidate["trips"]), 6)
        for number, detail in enumerate(candidate["trips"], 1):
            self.assertEqual(detail["public_number"], str(number))
            self.assertEqual(detail["train_number"], f"807{number}D")
            self.assertIn("/sp/2610/0016/", detail["source_url"])
            self.assertTrue(detail["source_url"].endswith("&d=20260930"))
            self.assertEqual(detail["equipment"], "普通車全車指定席")
            self.assertEqual([row["station_name"] for row in detail["stops"]],
                             ["鹿児島中央", "指宿"] if number % 2 else ["指宿", "鹿児島中央"])
            self.assertEqual(len(detail["stops"]), 2)
            self.assertEqual(sum(row["platform"] is not None for row in detail["stops"]), 1)
            self.assertIsNone(detail["stops"][0]["arrival_time"])
            self.assertIsNone(detail["stops"][1]["departure_time"])

    def test_six_dated_numbers_and_merged_platform(self):
        numbers = rows(BASE / f"normalized/trip-train-number-overrides/{SUFFIX}/seeds.jsonl")
        platforms = rows(BASE / f"normalized/trip-stop-time-overrides/{SUFFIX}/seeds.jsonl")
        old_minute_rows = rows(OLD_MINUTE_FILE)
        sources = rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        facts = rows(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")
        self.assertEqual(len(numbers), 6)
        self.assertEqual(len(platforms), 5)
        self.assertEqual(len(sources), 6)
        self.assertEqual(len(facts), 18)
        self.assertEqual({row["service_date"] for row in numbers + platforms}, {DAY})
        self.assertEqual([row["train_number"] for row in numbers],
                         [f"807{number}D" for number in range(1, 7)])
        self.assertEqual([(row["stop_sequence"], row["platform_override"])
                          for row in platforms], [(1, "4"), (2, "3"), (1, "3"), (2, "4"), (2, "4")])
        for row in platforms:
            self.assertEqual(row["platform_override_present"], 1)
            self.assertNotIn("arrival_override", row)
            self.assertNotIn("departure_override", row)
        self.assertEqual(len(old_minute_rows), 13)
        merged = next(row for row in old_minute_rows if row["service_date"] == DAY)
        self.assertEqual((merged["departure_override"], merged["source_id"],
                          merged["platform_override_present"], merged["platform_override"]),
                         ("13:57", "jr-kyushu-ibusuki-5-20260918-minute-change", 1, "4"))
        keys = [(row["trip_id"], row["service_date"], row["stop_sequence"])
                for row in platforms + old_minute_rows]
        self.assertEqual(len(keys), len(set(keys)))
        self.assertEqual({row["field_name"] for row in facts},
                         {"train_number", "platform", "formation.all_reserved"})

    def test_materialized_occurrence_changes_only_on_selected_date(self):
        data, origins = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        self.assertFalse(timetable.validate_dataset(data, origins, timetable.load_manifest(BASE)))
        selected = {row["public_number"]: row for row in timetable.materialize(data, DAY)
                    if row["service_id"] == "ibusuki-no-tamatebako"}
        prior = {row["public_number"]: row for row in timetable.materialize(data, "2026-09-29")
                 if row["service_id"] == "ibusuki-no-tamatebako"}
        self.assertEqual(set(selected), {str(number) for number in range(1, 7)})
        self.assertEqual(set(prior), set(selected))
        for number in range(1, 7):
            key = str(number)
            self.assertEqual(selected[key]["train_number"], f"807{number}D")
            self.assertIsNone(prior[key]["train_number"])
            printed = selected[key]["stop_times"][0 if number % 2 else 1]
            earlier = prior[key]["stop_times"][0 if number % 2 else 1]
            self.assertEqual(printed["platform"], "3" if number in (2, 3) else "4")
            self.assertIsNone(earlier.get("platform"))
            self.assertEqual(len(selected[key]["stop_times"]), 2)
        self.assertEqual(selected["5"]["stop_times"][0]["departure_time"], "13:57")


if __name__ == "__main__":
    unittest.main()
