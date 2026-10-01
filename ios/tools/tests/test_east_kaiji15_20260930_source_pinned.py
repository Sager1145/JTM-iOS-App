"""Kaiji 15 keeps the September 30 JR East train-detail facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
TRIP = "jr-east.kaiji.15.exact-2026-09-30"
SOURCE = "jr-east-kaiji15-20260930"
PRINTED = [('新宿', None, '10:30', '１０'), ('立川', '10:53', '10:54', '６'), ('八王子', '11:02', '11:02', '４'), ('大月', '11:28', '11:31', '３'), ('塩山', '11:52', '11:53', '１'), ('山梨市', '11:57', '11:57', '３'), ('石和温泉', '12:01', '12:02', None), ('甲府', '12:07', None, '１')]

class Kaiji15Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = timetable.load_manifest(BASE)
        cls.data, _ = timetable.load_dataset(BASE, manifest)
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}

    def test_printed_train_clocks_and_platforms(self):
        day = {row["trip_id"]: row for row in timetable.materialize(self.data, "2026-09-30")}
        actual = day[TRIP]
        self.assertEqual((actual["train_number"], actual["public_number"]), ("3115M", "15"))
        self.assertEqual(
            [(self.names[row["station_id"]], row["arrival_time"], row["departure_time"], row["platform"])
             for row in actual["stop_times"]], PRINTED
        )

    def test_source_and_exact_day_scope(self):
        source = next(row for row in self.data["source_documents"] if row["source_id"] == SOURCE)
        self.assertEqual(source["url_or_locator"],
                         "https://timetables.jreast.co.jp/2610/train/060/063481.html")
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

    def test_calendar_seat_and_coupled_column(self):
        import json, importlib.util
        c = json.loads((BASE / 'candidates/jr-east-kaiji15-20260930.json').read_text())
        self.assertEqual(c['calendar_observation'], {'month':'2026年9月','day':30,'cell_class':'ok'})
        self.assertEqual(c['equipment'], ['座席未指定券','グリーン車指定席','普通車全車指定席'])
        self.assertIsNone(c['formation'])
        self.assertEqual(c['printed_coupling'], '新宿－大月は2115Mを併結')
        self.assertEqual(c['origin'], '新宿')
        self.assertEqual(c['destination'], '甲府')
        spec=importlib.util.spec_from_file_location('normalizer', TOOLS / 'normalize-reviewed-east-kaiji15-20260930.py')
        mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);mod.validate(c)
        c['calendar_observation']['cell_class']='none'
        with self.assertRaises(ValueError): mod.validate(c)


if __name__ == "__main__":
    unittest.main()
