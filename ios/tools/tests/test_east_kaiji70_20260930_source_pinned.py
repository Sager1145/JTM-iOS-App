"""Kaiji 70 keeps the September 30 JR East train-detail facts."""

from pathlib import Path
import sys
import unittest


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
TRIP = "jr-east.kaiji.70.exact-2026-09-30"
SOURCE = "jr-east-kaiji70-20260930"
PRINTED = [('甲府', None, '05:40', '２'), ('石和温泉', '05:45', '05:45', None), ('山梨市', '05:49', '05:50', '１'), ('塩山', '05:54', '05:54', '３'), ('大月', '06:15', '06:16', '５'), ('八王子', '06:47', '06:49', '２'), ('立川', '06:58', '07:00', '３'), ('新宿', '07:30', '07:32', '７'), ('東京', '07:45', None, '２')]

class Kaiji70Tests(unittest.TestCase):
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
        self.assertEqual((actual["train_number"], actual["public_number"]), ("8170M", "70"))
        self.assertEqual(
            [(self.names[row["station_id"]], row["arrival_time"], row["departure_time"], row["platform"])
             for row in actual["stop_times"]], PRINTED
        )

    def test_source_and_exact_day_scope(self):
        source = next(row for row in self.data["source_documents"] if row["source_id"] == SOURCE)
        self.assertEqual(source["url_or_locator"],
                         "https://timetables.jreast.co.jp/2610/train/110/114981.html")
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
        c = json.loads((BASE / 'candidates/jr-east-kaiji70-20260930.json').read_text())
        self.assertEqual(c['calendar_observation'], {'month':'2026年9月','day':30,'cell_class':'ok'})
        self.assertEqual(c['equipment'], ['座席未指定券','グリーン車指定席','普通車全車指定席'])
        self.assertIsNone(c['formation'])
        self.assertEqual(c['printed_coupling'], None)
        self.assertEqual(c['origin'], '甲府')
        self.assertEqual(c['destination'], '東京')
        spec=importlib.util.spec_from_file_location('normalizer', TOOLS / 'normalize-reviewed-east-kaiji70-20260930.py')
        mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);mod.validate(c)
        c['calendar_observation']['cell_class']='none'
        with self.assertRaises(ValueError): mod.validate(c)

    def test_all_observed_running_trains_staged(self):
        import json
        inv=json.loads((BASE/'audits/jr-east-kaiji-observed-20260930-inventory.json').read_text())
        proven={t['public_number']:t for t in inv['trains'] if t['scheduled_on_date']}
        self.assertEqual(len(proven),29)
        self.assertNotIn('99',proven)
        day={t['public_number']:t for t in timetable.materialize(self.data,'2026-09-30') if t['service_id']=='kaiji'}
        self.assertTrue(set(proven).issubset(day))
        for n,evidence in proven.items():
            self.assertEqual(evidence['date_evidence']['cell_class'],'ok')
            self.assertEqual(day[n]['train_number'],evidence['train_number'])
            candidate=json.loads((BASE/f'candidates/jr-east-kaiji{n}-20260930.json').read_text())
            self.assertEqual(candidate['source_url'],evidence['source_url'])
            self.assertEqual(candidate['train_number'],evidence['train_number'])

if __name__ == "__main__":
    unittest.main()
