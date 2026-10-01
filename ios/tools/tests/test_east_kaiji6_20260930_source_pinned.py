"""Kaiji 6 keeps the September 30 JR East train-detail facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
TRIP = "jr-east.kaiji.6.exact-2026-09-30"
SOURCE = "jr-east-kaiji6-20260930"
PRINTED = [
    ('竜王', None, '07:43', '２'),
    ('甲府', '07:47', '07:50', '２'),
    ('石和温泉', '07:55', '07:55', None),
    ('山梨市', '08:00', '08:00', '１'),
    ('塩山', '08:05', '08:05', '３'),
    ('大月', '08:24', '08:25', '５'),
    ('八王子', '08:52', '08:53', '２'),
    ('立川', '09:01', '09:02', '３'),
    ('新宿', '09:30', '09:31', '７'),
    ('東京', '09:45', None, '２'),
]


class Kaiji6Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = timetable.load_manifest(BASE)
        cls.data, _ = timetable.load_dataset(BASE, manifest)
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}

    def test_printed_train_clocks_and_platforms(self):
        day = {row["trip_id"]: row for row in timetable.materialize(self.data, "2026-09-30")}
        actual = day[TRIP]
        self.assertEqual((actual["train_number"], actual["public_number"]), ("5106M", "6"))
        self.assertEqual(
            [(self.names[row["station_id"]], row["arrival_time"], row["departure_time"], row["platform"])
             for row in actual["stop_times"]], PRINTED
        )

    def test_source_and_exact_day_scope(self):
        source = next(row for row in self.data["source_documents"] if row["source_id"] == SOURCE)
        self.assertEqual(source["url_or_locator"],
                         "https://timetables.jreast.co.jp/2610/train/075/076151.html")
        for other in ("2026-09-29", "2026-10-01"):
            self.assertNotIn(TRIP, {row["trip_id"] for row in timetable.materialize(self.data, other)})
        self.assertEqual(sum(row["service_id"] == "kaiji" for row in self.data["services"]), 1)

    def test_complete_clock_column_and_unresolved_route(self):
        self.assertFalse(any(row["trip_id"] == TRIP for row in self.data["trip_line_segments"]))
        self.assertFalse(any(row["trip_id"] == TRIP for row in self.data["trip_operator_segments"]))
        statuses = {row["dimension"]: row["status"] for row in self.data["fact_completeness"]
                    if row["entity_id"] == TRIP}
        self.assertEqual(statuses["times"], "verified")
        self.assertEqual(statuses["route_lines"], "unknown")


if __name__ == "__main__":
    unittest.main()
