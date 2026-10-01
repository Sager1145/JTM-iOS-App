"""Evidence bounds for the September 30 Ozora 1 selected column."""

import sys
from pathlib import Path
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import train_timetable as timetable


class HokkaidoOzora1SourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = timetable.load_manifest(timetable.DEFAULT_CANONICAL)
        cls.data, origins = timetable.load_dataset(timetable.DEFAULT_CANONICAL, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.station_names = {row["station_id"]: row["name_snapshot"]
                             for row in cls.data["station_identities"]}

    def test_exact_date_and_ten_passenger_calls(self):
        self.assertFalse([row for row in timetable.materialize(self.data, "2026-09-29")
                          if row["service_id"] == "ozora"])
        trips = [row for row in timetable.materialize(self.data, "2026-09-30")
                 if row["service_id"] == "ozora" and row["public_number"] == "1"]
        self.assertEqual(len(trips), 1)
        trip = trips[0]
        self.assertEqual((trip["public_number"], trip["train_number"]), ("1", "4001D"))
        self.assertEqual([self.station_names[stop["station_id"]] for stop in trip["stop_times"]],
                         ["札幌", "新札幌", "南千歳", "追分", "新夕張", "トマム",
                          "新得", "帯広", "池田", "釧路"])
        self.assertEqual((trip["stop_times"][0]["departure_time"],
                          trip["stop_times"][6]["arrival_time"],
                          trip["stop_times"][6]["departure_time"],
                          trip["stop_times"][7]["arrival_time"],
                          trip["stop_times"][7]["departure_time"],
                          trip["stop_times"][-1]["arrival_time"]),
                         ("6:48", "8:48", "8:49", "9:18", "9:19", "10:56"))
        self.assertIsNone(trip["stop_times"][8]["arrival_time"])

    def test_official_sources_and_open_limits(self):
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        source = sources["jr-hokkaido-ozora1-20260930-timetable"]
        self.assertEqual(source["url_or_locator"],
                         "https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=130")
        self.assertFalse(source["automated_extraction_allowed"])
        english = sources["jr-hokkaido-ozora-2026-english-guide"]
        self.assertEqual(english["url_or_locator"],
                         "https://www.jrhokkaido.co.jp/global/english/train/guide/obihiro.html")
        names = [row for row in self.data["service_name_periods"]
                 if row["service_id"] == "ozora" and row["language"] == "en"]
        self.assertEqual([(row["name"], row["valid_from"], row["valid_until"])
                          for row in names], [("Ozora", "2026-09-30", "2026-10-01")])
        statuses = {row["dimension"]: row["status"]
                    for row in self.data["fact_completeness"]
                    if row["entity_id"] == "jr-hokkaido.ozora.1.2026-09-30"}
        self.assertEqual(statuses["stops"], "verified")
        self.assertEqual(statuses["times"], "partial")
        self.assertEqual(statuses["route_lines"], "unknown")


if __name__ == "__main__":
    unittest.main()
