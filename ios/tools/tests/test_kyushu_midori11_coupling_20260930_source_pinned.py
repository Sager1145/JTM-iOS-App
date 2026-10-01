"""Source-pinned checks for Midori 11 and its reciprocal coupling."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "reviewed-kyushu-midori11-coupling-20260930"
RELATED_SUFFIX = "reviewed-kyushu-huis-ten-bosch11-20260930"
MIDORI = "jr-kyushu.midori.11.2026-09-30"
HUIS = "jr-kyushu.huis-ten-bosch.11.2026-09-30"
URL = "https://www.jrkyushu-timetable.jp/jr-k_time/2610/0008/00085801.html?c=28283&ym=202609&d=30"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


class KyushuMidoriCouplingSourcePinnedTests(unittest.TestCase):
    def setUp(self):
        self.candidate = json.loads((BASE / "candidates/jr-kyushu-midori11-20260930.json")
                                    .read_text(encoding="utf-8"))

    def test_source_and_exact_date(self):
        self.assertEqual(self.candidate["candidate_status"], "reviewed_official_html")
        self.assertEqual(self.candidate["source_url"], URL)
        self.assertEqual(self.candidate["service_date"], "2026-09-30")
        source = rows(BASE / f"sources/source-registry-{SUFFIX}.jsonl")
        self.assertEqual(len(source), 1)
        self.assertEqual(source[0]["source_id"], "jr-kyushu-midori11-20260930")
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

    def test_midori_column_and_branch(self):
        trips = rows(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        calls = sorted(rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl"),
                       key=lambda row: row["stop_sequence"])
        published = self.candidate["trip"]["stop_times"]
        self.assertEqual(len(trips), 1)
        self.assertEqual((trips[0]["trip_id"], trips[0]["train_number"], trips[0]["public_number"]),
                         (MIDORI, "4011M", "11"))
        self.assertEqual(len(calls), 10)
        self.assertEqual([row["name_snapshot"] for row in published], [
            "博多", "二日市", "鳥栖", "新鳥栖", "佐賀", "江北", "武雄温泉", "有田", "早岐", "佐世保"])
        self.assertEqual([(row["arrival_time"], row["departure_time"], row["platform"])
                          for row in calls],
                         [(row["arrival_time"], row["departure_time"], row["platform"])
                          for row in published])
        self.assertIsNone(calls[0]["arrival_time"])
        self.assertIsNone(calls[-1]["departure_time"])
        self.assertEqual((calls[8]["arrival_time"], calls[8]["departure_time"], calls[-1]["arrival_time"]),
                         ("10:07", "10:12", "10:22"))

    def test_reciprocal_coupling_ends_at_haiki_arrival(self):
        relations = rows(BASE / f"normalized/trip-relations/{SUFFIX}/seeds.jsonl")
        self.assertEqual({(row["trip_id"], row["related_trip_id"], row["relation_type"],
                           row["from_sequence"], row["to_sequence"]) for row in relations}, {
                               (MIDORI, HUIS, "couples_with", 1, 9),
                               (HUIS, MIDORI, "couples_with", 1, 9)})
        midori = sorted(rows(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl"),
                        key=lambda row: row["stop_sequence"])
        huis = sorted(rows(BASE / f"normalized/stop-times/{RELATED_SUFFIX}/seeds.jsonl"),
                      key=lambda row: row["stop_sequence"])
        self.assertEqual([(row["station_id"], row["arrival_time"], row["departure_time"])
                          for row in midori[:8]],
                         [(row["station_id"], row["arrival_time"], row["departure_time"])
                          for row in huis[:8]])
        self.assertEqual(midori[8]["station_id"], huis[8]["station_id"])
        self.assertEqual(midori[8]["arrival_time"], huis[8]["arrival_time"])
        self.assertEqual((midori[8]["departure_time"], huis[8]["departure_time"]),
                         ("10:12", "10:16"))
        self.assertNotEqual(midori[-1]["station_id"], huis[-1]["station_id"])

    def test_route_and_operator_are_unproved(self):
        completeness = {row["dimension"]: row["status"] for row in rows(
            BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")}
        self.assertEqual(completeness["operator"], "unknown")
        self.assertEqual(completeness["route_lines"], "unknown")
        self.assertFalse((BASE / f"normalized/trip-lines/{SUFFIX}/seeds.jsonl").exists())
        self.assertFalse((BASE / f"normalized/trip-operator-segments/{SUFFIX}/seeds.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
