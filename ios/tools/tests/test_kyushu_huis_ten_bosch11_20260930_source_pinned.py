"""Source-pinned checks for September 30 Huis Ten Bosch 11."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-kyushu-huis-ten-bosch11-20260930"
TRIP_ID = "jr-kyushu.huis-ten-bosch.11.2026-09-30"
SOURCE_URL = "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0008/00085801.html?c=28283&ym=202609&d=30"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class KyushuHuisTenBoschSourcePinnedTests(unittest.TestCase):
    def setUp(self):
        self.candidate = json.loads((BASE / "candidates/jr-kyushu-huis-ten-bosch11-20260930.json")
                                    .read_text(encoding="utf-8"))

    def test_exact_date_source_and_identity(self):
        self.assertEqual(self.candidate["candidate_status"], "reviewed_official_html")
        self.assertEqual(self.candidate["source_url"], SOURCE_URL)
        self.assertEqual(self.candidate["service_date"], "2026-09-30")
        trip = self.candidate["trip"]
        self.assertEqual((trip["trip_id"], trip["service_name"], trip["train_number"]),
                         (TRIP_ID, "ハウステンボス", "6011H"))
        self.assertEqual([row["service_id"] for row in rows(
            BASE / f"normalized/services-{SUFFIX}.jsonl")], ["huis-ten-bosch"])
        self.assertEqual(rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl"), [])

    def test_own_column_contains_ten_calls_and_no_sasebo(self):
        trips = rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        stops = sorted(rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl"),
                       key=lambda row: row["stop_sequence"])
        published = self.candidate["trip"]["stop_times"]
        self.assertEqual(len(trips), 1)
        self.assertEqual(trips[0]["trip_id"], TRIP_ID)
        self.assertEqual(len(stops), 10)
        self.assertEqual([row["stop_sequence"] for row in stops], list(range(1, 11)))
        self.assertEqual([row["name_snapshot"] for row in published], [
            "博多", "二日市", "鳥栖", "新鳥栖", "佐賀", "江北", "武雄温泉", "有田", "早岐", "ハウステンボス"])
        self.assertEqual([(row["arrival_time"], row["departure_time"], row["platform"])
                          for row in stops],
                         [(row["arrival_time"], row["departure_time"], row["platform"])
                          for row in published])
        self.assertEqual((stops[-2]["arrival_time"], stops[-2]["departure_time"]),
                         ("10:07", "10:16"))
        self.assertIsNone(stops[0]["arrival_time"])
        self.assertIsNone(stops[-1]["departure_time"])

    def test_calendar_and_unproved_dimensions(self):
        calendar = rows(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl")
        exceptions = rows(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(calendar), 1)
        self.assertEqual((calendar[0]["valid_from"], calendar[0]["valid_until"]),
                         ("2026-09-30", "2026-10-01"))
        self.assertEqual(sum(calendar[0][day] for day in WEEKDAYS), 0)
        self.assertEqual([row["service_date"] for row in exceptions], ["2026-09-30"])
        completeness = {row["dimension"]: row["status"] for row in rows(
            BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")}
        self.assertEqual(completeness["operator"], "unknown")
        self.assertEqual(completeness["route_lines"], "unknown")
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
