"""Keep the reviewed one-day Akagi 6 facts tied to its official detail page."""

import json
from pathlib import Path
import unittest


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
SUFFIX = "akagi-20260930"
SOURCE_URL = "https://timetables.jreast.co.jp/2610/train/075/076101.html"


def rows(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line]


class AkagiSourcePinnedTests(unittest.TestCase):
    def test_one_official_date_and_complete_published_clocks(self):
        candidate = json.loads(
            (BASE / "candidates/jr-east-akagi-20260930.json").read_text()
        )
        reviewed = candidate["trips"]
        self.assertEqual(len(reviewed), 3)
        evening_trip = next(row for row in reviewed if row["public_number"] == "3")
        trip = next(row for row in reviewed if row["public_number"] == "6")
        return_trip = next(row for row in reviewed if row["public_number"] == "9")
        self.assertEqual(trip["source"]["url_or_locator"], SOURCE_URL)
        self.assertEqual(
            candidate["english_name_source"]["url_or_locator"],
            "https://timetables.jreast.co.jp/en/2610/train/075/076101.html",
        )
        self.assertEqual(trip["operating_dates"], ["2026-09-30"])
        self.assertEqual((trip["service_name"], trip["train_number"]), ("あかぎ", "4006M"))
        self.assertEqual(len(trip["stop_times"]), 12)
        self.assertEqual(
            (evening_trip["source"]["url_or_locator"], evening_trip["train_number"],
             evening_trip["operating_dates"], len(evening_trip["stop_times"])),
            ("https://timetables.jreast.co.jp/2610/train/030/034771.html",
             "4003M", ["2026-09-30"], 11),
        )
        self.assertEqual(
            (return_trip["source"]["url_or_locator"], return_trip["train_number"],
             return_trip["operating_dates"], len(return_trip["stop_times"])),
            ("https://timetables.jreast.co.jp/2610/train/065/068071.html",
             "4009M", ["2026-09-30"], 13),
        )
        self.assertEqual(
            [(stop["name_snapshot"], stop["arrival_time"], stop["departure_time"])
             for stop in trip["stop_times"]],
            [
                ("高崎", None, "07:40"), ("新町", "07:48", "07:49"),
                ("本庄", "07:54", "07:55"), ("深谷", "08:01", "08:02"),
                ("熊谷", "08:10", "08:10"), ("鴻巣", "08:20", "08:20"),
                ("北本", "08:23", "08:24"), ("桶川", "08:27", "08:28"),
                ("上尾", "08:31", "08:32"), ("大宮", "08:39", "08:40"),
                ("池袋", "09:01", "09:03"), ("新宿", "09:09", None),
            ],
        )
        self.assertEqual(
            [(stop["name_snapshot"], stop["arrival_time"], stop["departure_time"])
             for stop in return_trip["stop_times"]],
            [
                ("上野", None, "20:00"), ("赤羽", "20:09", "20:09"),
                ("浦和", "20:18", "20:18"), ("大宮", "20:25", "20:26"),
                ("上尾", "20:32", "20:33"), ("桶川", "20:36", "20:37"),
                ("北本", "20:40", "20:41"), ("鴻巣", "20:44", "20:44"),
                ("熊谷", "20:54", "20:55"), ("深谷", "21:02", "21:03"),
                ("本庄", "21:10", "21:10"), ("新町", "21:16", "21:16"),
                ("高崎", "21:24", None),
            ],
        )
        self.assertEqual(
            [(stop["name_snapshot"], stop["arrival_time"], stop["departure_time"])
             for stop in evening_trip["stop_times"]],
            [
                ("上野", None, "18:30"), ("赤羽", "18:40", "18:40"),
                ("浦和", "18:49", "18:49"), ("大宮", "18:55", "18:56"),
                ("上尾", "19:03", "19:04"), ("桶川", "19:07", "19:08"),
                ("北本", "19:11", "19:12"), ("鴻巣", "19:15", "19:16"),
                ("熊谷", "19:25", "19:26"), ("深谷", "19:33", "19:34"),
                ("本庄", "19:42", None),
            ],
        )

        normalized = rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        stops = rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        exceptions = rows(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(normalized), 3)
        self.assertEqual({row["train_number"] for row in normalized},
                         {"4003M", "4006M", "4009M"})
        self.assertEqual(len(stops), 36)
        self.assertEqual([row["service_date"] for row in exceptions],
                         ["2026-09-30"] * 3)
        english_names = [
            row for row in rows(BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl")
            if row["language"] == "en"
        ]
        self.assertEqual(
            [(row["name"], row["valid_from"], row["valid_until"]) for row in english_names],
            [("Akagi", "2026-09-30", "2026-10-01")],
        )


if __name__ == "__main__":
    unittest.main()
