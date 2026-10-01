"""The reviewed Tokachi 1 columns are limited to September 29 and 30."""

import json
from pathlib import Path
import sys
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import train_timetable as timetable


ROOT = Path(__file__).resolve().parents[3]
CANDIDATE = ROOT / "app/data/train-service-history/candidates/jr-hokkaido-tokachi1-20260929-30.json"
TRIP_ID = "jr-hokkaido.tokachi.1.2026-09-29-30"


class HokkaidoTokachi1SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = timetable.load_manifest(timetable.DEFAULT_CANONICAL)
        cls.data, origins = timetable.load_dataset(timetable.DEFAULT_CANONICAL, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.names = {row["station_id"]: row["name_snapshot"]
                     for row in cls.data["station_identities"]}

    def test_two_reviewed_dates_and_full_stop_sequence(self):
        expected_names = ["札幌", "新札幌", "南千歳", "追分", "新夕張", "占冠", "トマム",
                          "新得", "十勝清水", "芽室", "帯広"]
        expected_clocks = [(None, "7:58"), (None, "8:07"), (None, "8:27"),
                           (None, "8:40"), (None, "8:59"), (None, "9:27"),
                           (None, "9:42"), ("10:05", "10:05"), (None, "10:13"),
                           (None, "10:34"), ("10:43", None)]
        for day in ("2026-09-29", "2026-09-30"):
            trips = [row for row in timetable.materialize(self.data, day)
                     if row["trip_id"] == TRIP_ID]
            self.assertEqual(len(trips), 1, day)
            trip = trips[0]
            self.assertEqual((trip["service_id"], trip["public_number"], trip["train_number"]),
                             ("tokachi", "1", "31D"))
            self.assertEqual([self.names[stop["station_id"]] for stop in trip["stop_times"]],
                             expected_names)
            self.assertEqual([(stop["arrival_time"], stop["departure_time"])
                              for stop in trip["stop_times"]], expected_clocks)
            self.assertEqual({stop["day_offset"] for stop in trip["stop_times"]}, {0})
        self.assertFalse([row for row in timetable.materialize(self.data, "2026-09-28")
                          if row["trip_id"] == TRIP_ID])

    def test_source_scope_and_open_evidence(self):
        candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        self.assertEqual(candidate["service_dates"], ["2026-09-29", "2026-09-30"])
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        for day in candidate["service_dates"]:
            source = sources[candidate["source_ids"][day]]
            self.assertEqual(source["url_or_locator"],
                             f"https://jrhokkaidonorikae.com/vtime/vtime.php?d={day.replace('-', '')}&s=130")
            self.assertFalse(source["automated_extraction_allowed"])
        self.assertEqual(sources[candidate["guide_source_id"]]["url_or_locator"],
                         "https://www.jrhokkaido.co.jp/train/tr005_01.html")
        self.assertEqual(sources[candidate["english_source_id"]]["url_or_locator"],
                         "https://www.jrhokkaido.co.jp/global/english/ticket/usage/usage03.html")
        statuses = {row["dimension"]: row["status"]
                    for row in self.data["fact_completeness"] if row["entity_id"] == TRIP_ID}
        self.assertEqual(statuses["stops"], "verified")
        self.assertEqual(statuses["times"], "partial")
        self.assertEqual(statuses["route_lines"], "unknown")


if __name__ == "__main__":
    unittest.main()
