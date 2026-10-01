"""Source-pinned checks for the September 30 Yufu 3 occurrence."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-kyushu-yufu3-20260930"
TRIP_ID = "jr-kyushu.yufu.3.2026-09-30"
URL = "https://www.jrkyushu-timetable.jp/sp/2610/0016/00167201.html?t=2828302e&d=20260930"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class KyushuYufu3SourcePinnedTests(unittest.TestCase):
    def setUp(self):
        self.candidate = json.loads((BASE / "candidates/jr-kyushu-yufu3-20260930.json")
                                    .read_text(encoding="utf-8"))

    def test_exact_date_source_and_service_reuse(self):
        self.assertEqual(self.candidate["candidate_status"], "reviewed_official_html")
        self.assertEqual(self.candidate["source_url"], URL)
        self.assertEqual(self.candidate["service_date"], "2026-09-30")
        source = rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        self.assertEqual(len(source), 1)
        self.assertEqual(source[0]["source_id"], "jr-kyushu-yufu3-20260930")
        self.assertEqual(source[0]["url_or_locator"], URL)
        self.assertIs(source[0]["automated_extraction_allowed"], False)
        self.assertEqual(rows(BASE / f"normalized/services-{SUFFIX}.jsonl"), [])
        calendar = rows(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(calendar), 1)
        self.assertEqual((calendar[0]["valid_from"], calendar[0]["valid_until"]),
                         ("2026-09-30", "2026-10-01"))
        self.assertEqual(sum(calendar[0][day] for day in WEEKDAYS), 0)
        self.assertEqual([row["service_date"] for row in rows(
            BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")], ["2026-09-30"])

    def test_all_sixteen_published_calls_and_null_sides(self):
        trips = rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        stops = sorted(rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl"),
                       key=lambda row: row["stop_sequence"])
        published = self.candidate["trip"]["stop_times"]
        self.assertEqual(len(trips), 1)
        self.assertEqual((trips[0]["trip_id"], trips[0]["train_number"], trips[0]["public_number"]),
                         (TRIP_ID, "83D", "3"))
        self.assertEqual(len(stops), 16)
        self.assertEqual([row["stop_sequence"] for row in stops], list(range(1, 17)))
        self.assertEqual([row["name_snapshot"] for row in published], [
            "博多", "二日市", "鳥栖", "久留米", "田主丸", "筑後吉井", "うきは", "日田",
            "天ケ瀬", "豊後森", "豊後中村", "由布院", "湯平", "向之原", "大分", "別府"])
        self.assertEqual([(row["arrival_time"], row["departure_time"], row["platform"])
                          for row in stops],
                         [(row["arrival_time"], row["departure_time"], row["platform"])
                          for row in published])
        self.assertIsNone(stops[0]["arrival_time"])
        self.assertIsNone(stops[-1]["departure_time"])
        self.assertEqual((stops[0]["departure_time"], stops[-1]["arrival_time"]),
                         ("12:14", "15:46"))
        self.assertEqual(stops[8]["station_id"], "jp.n02.009457")  # 天ケ瀬 = N02 天ヶ瀬.

    def test_unproved_dimensions_remain_open(self):
        completeness = {row["dimension"]: row["status"] for row in rows(
            BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")}
        self.assertEqual(completeness["operator"], "unknown")
        self.assertEqual(completeness["route_lines"], "unknown")
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-relations/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
