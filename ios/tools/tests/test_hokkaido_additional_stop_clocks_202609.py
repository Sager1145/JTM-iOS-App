"""The six additional Hokuto/Niseko columns apply to their exact dates only."""

import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable


BASE = ROOT / "app/data/train-service-history"
CANDIDATES = (
    BASE / "candidates/jr-hokkaido-hokuto-20260919-stop-clocks.json",
    BASE / "candidates/jr-hokkaido-niseko-20260922-stop-clocks.json",
    BASE / "candidates/jr-hokkaido-niseko-20260927-stop-clocks.json",
)


class AdditionalHokkaidoClocksTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reviewed = [trip for path in CANDIDATES
                        for trip in json.loads(path.read_text(encoding="utf-8"))["trips"]]
        manifest = timetable.load_manifest(BASE)
        cls.data, origins = timetable.load_dataset(BASE, manifest)
        errors = timetable.validate_dataset(cls.data, origins, manifest)
        if errors:
            raise AssertionError(errors)
        cls.names = {row["station_id"]: row["name_snapshot"]
                     for row in cls.data["station_identities"]}

    def test_both_selected_columns_match_every_printed_side(self):
        for reviewed in self.reviewed:
            with self.subTest(train=reviewed["train_number"]):
                occurrences = {row["trip_id"]: row for row in
                               timetable.materialize(self.data, reviewed["service_date"])}
                actual = occurrences[reviewed["trip_id"]]
                self.assertEqual(actual["train_number"], reviewed["train_number"])
                calls = [[self.names[stop["station_id"]], stop["arrival_time"],
                          stop["departure_time"]] for stop in actual["stop_times"]]
                self.assertEqual(calls, reviewed["stops"])
        outbound = next(row for row in timetable.materialize(self.data, "2026-09-27")
                        if row["trip_id"] ==
                        "jr-hokkaido.niseko.sapporo-to-hakodate-dated-20260927.2026-09-27")
        self.assertNotIn("大沼公園", [self.names[stop["station_id"]]
                                  for stop in outbound["stop_times"]])

    def test_78_new_clocks_do_not_leak_to_another_date(self):
        selected_ids = {row["trip_id"] for row in self.reviewed}
        overrides = [row for row in self.data["trip_stop_time_overrides"]
                     if row["trip_id"] in selected_ids]
        self.assertEqual(len(overrides), 78)
        sources = {row["source_id"]: row for row in self.data["source_documents"]}
        self.assertTrue(all(sources[row["source_id"]]["effective_date"] == row["service_date"]
                            for row in overrides))
        self.assertTrue(all(sources[row["source_id"]]["issue"] == "JR時刻表 令和8年10月号"
                            for row in overrides))
        other = {row["trip_id"]: row for row in timetable.materialize(self.data, "2026-09-21")}
        for trip_id in ("jr-hokkaido.niseko.sapporo-to-hakodate.2026-09-05",
                        "jr-hokkaido.niseko.hakodate-to-sapporo.2026-09-05"):
            self.assertIsNone(other[trip_id]["stop_times"][1]["departure_time"])
        for reviewed in self.reviewed:
            previous_day = ("2026-09-18" if reviewed["service_date"] == "2026-09-19"
                            else "2026-09-21" if reviewed["service_date"] == "2026-09-22"
                            else "2026-09-26")
            self.assertNotIn(reviewed["trip_id"], {row["trip_id"] for row in
                                                    timetable.materialize(self.data, previous_day)})


if __name__ == "__main__":
    unittest.main()
