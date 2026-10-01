"""Narita Express 37 keeps the September 30 JR East train-detail facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
TRIP = "jr-east.narita-express.37.exact-2026-09-30"
SOURCE = "jr-east-narita-express37-20260930"
PRINTED = [('新宿', None, '15:08', '５'), ('渋谷', '15:13', '15:14', None), ('品川', '15:23', '15:24', '１３'), ('東京', '15:31', '15:33', '４'), ('空港第2ビル', '16:27', '16:29', None), ('成田空港', '16:31', None, None)]

class NaritaExpress37Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest = timetable.load_manifest(BASE)
        cls.data, _ = timetable.load_dataset(BASE, manifest)
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}

    def test_printed_train_clocks_and_platforms(self):
        day = {row["trip_id"]: row for row in timetable.materialize(self.data, "2026-09-30")}
        actual = day[TRIP]
        trip = next(r for r in self.data["trips"] if r["trip_id"] == TRIP)
        self.assertEqual(trip["origin_station_id"], actual["stop_times"][0]["station_id"])
        self.assertEqual(trip["destination_station_id"], actual["stop_times"][-1]["station_id"])
        self.assertEqual((actual["train_number"], actual["public_number"]), ("2237M", "37"))
        self.assertEqual(
            [(self.names[row["station_id"]], row["arrival_time"], row["departure_time"], row["platform"])
             for row in actual["stop_times"]], PRINTED
        )

    def test_source_and_exact_day_scope(self):
        source = next(row for row in self.data["source_documents"] if row["source_id"] == SOURCE)
        self.assertEqual(source["url_or_locator"],
                         "https://timetables.jreast.co.jp/2610/train/075/076551.html")
        for other in ("2026-09-29", "2026-10-01"):
            self.assertNotIn(TRIP, {row["trip_id"] for row in timetable.materialize(self.data, other)})
        self.assertEqual(sum(row["service_id"] == "narita-express" for row in self.data["services"]), 1)

    def test_complete_clock_column_and_unresolved_route(self):
        self.assertFalse(any(row["trip_id"] == TRIP for row in self.data["trip_line_segments"]))
        self.assertFalse(any(row["trip_id"] == TRIP for row in self.data["trip_operator_segments"]))
        statuses = {row["dimension"]: row["status"] for row in self.data["fact_completeness"]
                    if row["entity_id"] == TRIP}
        self.assertEqual(statuses["times"], "verified")
        self.assertEqual(statuses["route_lines"], "unknown")

    def test_printed_number_change(self):
        segments=[r for r in self.data['trip_number_segments'] if r['trip_id']==TRIP]
        self.assertEqual([{k:v for k,v in r.items() if k!='trip_id'} for r in segments], [{'from_sequence': 1, 'to_sequence': 4, 'train_number': '2237M'}, {'from_sequence': 4, 'to_sequence': 6, 'train_number': '2037M'}])
    def test_calendar_equipment_and_unknown_formation(self):
        import json, importlib.util
        c=json.loads((BASE/'candidates/jr-east-narita-express37-20260930.json').read_text())
        self.assertEqual(c['calendar_observation'], {'month':'2026年9月','day':30,'cell_class':'ok'})
        self.assertEqual(c['equipment'], ['座席未指定券','グリーン車指定席','普通車全車指定席'])
        self.assertIsNone(c['formation'])
        self.assertEqual(c['printed_coupling'], [])
        spec=importlib.util.spec_from_file_location('nex',TOOLS/'normalize-reviewed-east-narita-express37-20260930.py')
        mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);mod.validate(c)
        c['train_number_segments'][1]['train_number']='wrong'
        with self.assertRaises(ValueError):mod.validate(c)


if __name__ == "__main__":
    unittest.main()
