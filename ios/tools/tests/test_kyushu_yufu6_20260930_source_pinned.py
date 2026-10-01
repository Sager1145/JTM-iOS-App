"""Source-pinned checks for the September 30 Yufu 6 occurrence."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-kyushu-yufu6-20260930"
TRIP_ID = "jr-kyushu.yufu.6.2026-09-30"
URL = "https://www.jrkyushu-timetable.jp/sp/2610/0016/00167601.html?t=2880501e&d=20260930"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class KyushuYufu6SourcePinnedTests(unittest.TestCase):
    def setUp(self):
        self.candidate = json.loads((BASE / "candidates/jr-kyushu-yufu6-20260930.json")
                                    .read_text(encoding="utf-8"))

    def test_exact_date_source_and_existing_service(self):
        self.assertEqual(self.candidate["candidate_status"], "reviewed_official_html")
        self.assertEqual((self.candidate["service_date"], self.candidate["source_url"]),
                         ("2026-09-30", URL))
        source = rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        self.assertEqual(len(source), 1)
        self.assertEqual((source[0]["source_id"], source[0]["url_or_locator"]),
                         ("jr-kyushu-yufu6-20260930", URL))
        self.assertIs(source[0]["automated_extraction_allowed"], False)
        self.assertEqual(rows(BASE / f"normalized/services-{SUFFIX}.jsonl"), [])
        calendar = rows(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl")
        self.assertEqual(len(calendar), 1)
        self.assertEqual((calendar[0]["valid_from"], calendar[0]["valid_until"]),
                         ("2026-09-30", "2026-10-01"))
        self.assertEqual(sum(calendar[0][day] for day in WEEKDAYS), 0)

    def test_fourteen_published_calls_and_equipment_note(self):
        trips = rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        stops = sorted(rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl"),
                       key=lambda row: row["stop_sequence"])
        published = self.candidate["trip"]["stop_times"]
        self.assertEqual((len(trips), len(stops)), (1, 14))
        self.assertEqual((trips[0]["trip_id"], trips[0]["train_number"], trips[0]["public_number"]),
                         (TRIP_ID, "86D", "6"))
        self.assertEqual(self.candidate["trip"]["seat_description_snapshot"], "普通車一部指定席")
        self.assertEqual([row["name_snapshot"] for row in published], [
            "別府", "大分", "向之原", "湯平", "由布院", "豊後中村", "豊後森",
            "天ケ瀬", "日田", "筑後吉井", "久留米", "鳥栖", "二日市", "博多"])
        self.assertEqual([(row["arrival_time"], row["departure_time"], row["platform"])
                          for row in stops],
                         [(row["arrival_time"], row["departure_time"], row["platform"])
                          for row in published])
        self.assertEqual((stops[0]["arrival_time"], stops[0]["departure_time"],
                          stops[-1]["arrival_time"], stops[-1]["departure_time"]),
                         (None, "18:09", "21:34", None))
        self.assertEqual((stops[1]["platform"], stops[10]["platform"],
                          stops[11]["platform"], stops[13]["platform"]),
                         ("7", "4", "1", "2"))
        self.assertEqual(stops[7]["station_id"], "jp.n02.009457")

    def test_unproved_dimensions_remain_open(self):
        completeness = {row["dimension"]: row["status"] for row in rows(
            BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")}
        self.assertEqual(completeness["operator"], "unknown")
        self.assertEqual(completeness["route_lines"], "unknown")
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
