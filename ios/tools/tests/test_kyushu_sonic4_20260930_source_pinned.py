"""Source-pinned checks for the September 30 Sonic 4 occurrence."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-kyushu-sonic4-20260930"
TRIP_ID = "jr-kyushu.sonic.4.2026-09-30"
URL = "https://www.jrkyushu-timetable.jp/sp/2610/0001/00013501.html?t=2874200e&d=20260930"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class KyushuSonic4SourcePinnedTests(unittest.TestCase):
    def setUp(self):
        self.candidate = json.loads((BASE / "candidates/jr-kyushu-sonic4-20260930.json")
                                    .read_text(encoding="utf-8"))

    def test_exact_day_source_and_calendar(self):
        self.assertEqual((self.candidate["candidate_status"], self.candidate["service_date"],
                          self.candidate["source_url"]),
                         ("reviewed_official_html", "2026-09-30", URL))
        source = rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        self.assertEqual(len(source), 1)
        self.assertEqual(source[0]["url_or_locator"], URL)
        self.assertIs(source[0]["automated_extraction_allowed"], False)
        self.assertEqual(rows(BASE / f"normalized/services-{SUFFIX}.jsonl"), [])
        calendar = rows(BASE / f"normalized/calendars/{SUFFIX}/seeds.jsonl")
        self.assertEqual((calendar[0]["valid_from"], calendar[0]["valid_until"]),
                         ("2026-09-30", "2026-10-01"))
        self.assertEqual(sum(calendar[0][day] for day in WEEKDAYS), 0)

    def test_all_seventeen_calls_and_printed_platforms(self):
        trips = rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        stops = sorted(rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl"),
                       key=lambda row: row["stop_sequence"])
        published = self.candidate["trip"]["stop_times"]
        self.assertEqual((len(trips), len(stops)), (1, 17))
        self.assertEqual((trips[0]["trip_id"], trips[0]["train_number"], trips[0]["public_number"]),
                         (TRIP_ID, "3004M", "4"))
        self.assertEqual(self.candidate["trip"]["seat_description_snapshot"],
                         ["グリーン車指定席", "普通車一部指定席"])
        self.assertEqual([row["name_snapshot"] for row in published], [
            "大分", "別府", "杵築", "宇佐", "柳ケ浦", "中津", "宇島", "行橋",
            "下曽根", "小倉", "戸畑", "黒崎", "折尾", "赤間", "福間", "吉塚", "博多"])
        self.assertEqual([(row["arrival_time"], row["departure_time"], row["platform"])
                          for row in stops],
                         [(row["arrival_time"], row["departure_time"], row["platform"])
                          for row in published])
        self.assertEqual((stops[0]["arrival_time"], stops[0]["departure_time"],
                          stops[-1]["arrival_time"], stops[-1]["departure_time"]),
                         (None, "05:56", "08:36", None))
        self.assertEqual((stops[0]["platform"], stops[9]["platform"],
                          stops[12]["platform"], stops[16]["platform"]),
                         ("3", "4", "3", "5"))

    def test_no_inferred_line_or_operator_segments(self):
        completeness = {row["dimension"]: row["status"] for row in rows(
            BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")}
        self.assertEqual(completeness["operator"], "unknown")
        self.assertEqual(completeness["route_lines"], "unknown")
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
