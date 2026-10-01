"""Lilac 2 keeps the exact selected-day first-column facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
TRIP = "jr-hokkaido.lilac.2.exact-2026-09-30"
SOURCE = "jr-hokkaido-lilac2-20260930"
PRINTED = [
    ('旭川', None, '06:00', None),
    ('深川', None, '06:19', None),
    ('滝川', None, '06:32', None),
    ('砂川', None, '06:38', None),
    ('美唄', None, '06:49', None),
    ('岩見沢', None, '07:00', None),
    ('札幌', '07:33', None, '(2)'),
]


class Lilac2Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = timetable.load_manifest(BASE)
        cls.data, _ = timetable.load_dataset(BASE, manifest)
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}

    def test_printed_train_clocks_and_platform(self):
        day = {row["trip_id"]: row for row in timetable.materialize(self.data, "2026-09-30")}
        actual = day[TRIP]
        self.assertEqual((actual["train_number"], actual["public_number"]), ("3002M", "2"))
        self.assertEqual(
            [(self.names[row["station_id"]], row["arrival_time"], row["departure_time"], row["platform"])
             for row in actual["stop_times"]], PRINTED
        )

    def test_source_and_exact_day_scope(self):
        source = next(row for row in self.data["source_documents"] if row["source_id"] == SOURCE)
        self.assertEqual(source["url_or_locator"],
                         "https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111")
        for other in ("2026-09-29", "2026-10-01"):
            self.assertNotIn(TRIP, {row["trip_id"] for row in timetable.materialize(self.data, other)})
        self.assertEqual(sum(row["service_id"] == "lilac" for row in self.data["services"]), 1)

    def test_unknown_segments_are_not_filled(self):
        self.assertFalse(any(row["trip_id"] == TRIP for row in self.data["trip_line_segments"]))
        self.assertFalse(any(row["trip_id"] == TRIP for row in self.data["trip_operator_segments"]))
        statuses = {row["dimension"]: row["status"] for row in self.data["fact_completeness"]
                    if row["entity_id"] == TRIP}
        self.assertEqual(statuses["times"], "partial")
        self.assertEqual(statuses["route_lines"], "unknown")


if __name__ == "__main__":
    unittest.main()
