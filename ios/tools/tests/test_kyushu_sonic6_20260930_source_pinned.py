"""Source-pinned checks for exact-date Sonic 6."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-kyushu-sonic6-20260930"
TRIP_ID = "jr-kyushu.sonic.6.2026-09-30"
URL = "https://www.jrkyushu-timetable.jp/sp/2610/0001/00013701.html?t=2874200e&d=20260930"


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class Sonic6SourcePinnedTests(unittest.TestCase):
    def test_date_source_identity(self):
        candidate = json.loads((BASE / "candidates/jr-kyushu-sonic6-20260930.json").read_text())
        self.assertEqual((candidate["candidate_status"], candidate["service_date"], candidate["source_url"]),
                         ("reviewed_official_html", "2026-09-30", URL))
        source = rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        self.assertEqual((len(source), source[0]["url_or_locator"], source[0]["automated_extraction_allowed"]),
                         (1, URL, False))
        trips = rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        self.assertEqual((trips[0]["trip_id"], trips[0]["train_number"], trips[0]["public_number"]),
                         (TRIP_ID, "3006M", "6"))

    def test_exact_calls_and_platforms(self):
        candidate = json.loads((BASE / "candidates/jr-kyushu-sonic6-20260930.json").read_text())
        stops = sorted(rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl"), key=lambda x: x["stop_sequence"])
        self.assertEqual(len(stops), 14)
        self.assertEqual([(x["arrival_time"], x["departure_time"], x["platform"]) for x in stops],
                         [(x["arrival_time"], x["departure_time"], x["platform"]) for x in candidate["trip"]["stop_times"]])
        self.assertEqual((stops[0]["arrival_time"], stops[0]["departure_time"],
                          stops[-1]["arrival_time"], stops[-1]["departure_time"]),
                         (None, "06:37", "09:02", None))
        self.assertEqual([(stops[i-1]["stop_sequence"], stops[i-1]["platform"]) for i, _ in [(1, '3'), (9, '4'), (11, '3'), (14, '5')]],
                         [(1, '3'), (9, '4'), (11, '3'), (14, '5')])

    def test_calendar_and_unknown_segments(self):
        calendar = rows(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")
        self.assertEqual([x["service_date"] for x in calendar], ["2026-09-30"])
        completeness = {x["dimension"]: x["status"] for x in rows(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")}
        self.assertEqual((completeness["operator"], completeness["route_lines"]), ("unknown", "unknown"))
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
