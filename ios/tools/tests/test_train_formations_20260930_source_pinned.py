"""Planned consists retain exact date, provenance, car order, and unknown fields."""

import json
from pathlib import Path
import sqlite3
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-kyushu-ibusuki-20260930-formation.json"
DB = BASE / "derived/train-service-timetable.sqlite"
sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable


class PlannedFormationTests(unittest.TestCase):
    def test_ibusuki_c_is_one_day_planned_car_order(self):
        candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        with sqlite3.connect(DB) as db:
            db.row_factory = sqlite3.Row
            self.assertEqual(len(candidate["trip_ids"]), 6)
            for number, tid in enumerate(candidate["trip_ids"], 1):
                row = db.execute("SELECT * FROM trip_formations WHERE trip_id=?", (tid,)).fetchone()
                self.assertIsNotNone(row)
                self.assertEqual((row["service_date"], row["evidence_kind"], row["formation_label"],
                                  row["car_count"], row["reserved_seat_capacity"], row["all_reserved"]),
                                 ("2026-09-30", "planned", "C", 2, 63, 1))
                self.assertIsNone(row["vehicle_series"])
                self.assertIsNone(row["green_car_available"])
                cars = [(car["car_sequence"], car["car_number"], car["vehicle_series"])
                        for car in db.execute("SELECT * FROM trip_formation_cars WHERE formation_id=? ORDER BY car_sequence",
                                              (row["formation_id"],))]
                expected = [(1, "2", "キハ140"), (2, "1", "キハ47")]
                if number % 2 == 0:
                    expected = [(1, "1", "キハ47"), (2, "2", "キハ140")]
                self.assertEqual(cars, expected)
                source = db.execute("SELECT url_or_locator, effective_date FROM source_documents WHERE source_id=?",
                                    (row["source_id"],)).fetchone()
                self.assertEqual(source["url_or_locator"], candidate["calendar_source_url"])
                self.assertEqual(source["effective_date"], "2026-09-30")

    def test_hokkaido_icons_do_not_become_invented_cars(self):
        with sqlite3.connect(DB) as db:
            db.row_factory = sqlite3.Row
            rows = db.execute("SELECT f.*, t.service_id, t.train_number FROM trip_formations f "
                              "JOIN trips t ON t.trip_id=f.trip_id "
                              "WHERE t.trip_id LIKE 'jr-hokkaido.%'").fetchall()
            self.assertGreaterEqual(len(rows), 70)
            self.assertEqual({row["service_date"] for row in rows}, {"2026-09-30"})
            standard_hokuto = {
                f"jr-hokkaido.hokuto.{number}.exact-2026-09-30"
                for number in (*range(4, 23, 2), 21)
            }
            standard_asahikawa = {row["trip_id"] for row in rows
                                   if row["service_id"] in ("lilac", "kamui")}
            self.assertEqual(len(standard_asahikawa), 42)
            standard_eastern = {row["trip_id"] for row in rows
                                if row["service_id"] in ("ozora", "tokachi")}
            self.assertEqual(len(standard_eastern), 22)
            standard_northern = {
                "jr-hokkaido.okhotsk.4.exact-2026-09-30",
                "jr-hokkaido.sarobetsu.4-dated-20260930.2026-09-30",
                "jr-hokkaido.soya.52d.exact-2026-09-30",
            }
            suzuran_twelve = "jr-hokkaido.suzuran.12.exact-2026-09-30"
            self.assertTrue(all(row["evidence_kind"] == "planned"
                                and (row["all_reserved"] == 0 if row["service_id"] == "taisetsu"
                                     else row["all_reserved"] == 1)
                                for row in rows))
            self.assertEqual({row["trip_id"] for row in rows if row["vehicle_series"] is not None},
                             standard_hokuto | standard_asahikawa | standard_eastern | standard_northern)
            self.assertTrue(all(row["vehicle_series"] == "キハ261系1000代"
                                for row in rows if row["trip_id"] in standard_hokuto))
            self.assertTrue(all(row["car_count"] is None for row in rows
                                if row["trip_id"] not in standard_asahikawa | standard_eastern
                                | standard_northern | {suzuran_twelve}))
            self.assertTrue(all(row["car_count"] == (6 if row["service_id"] == "lilac" else 5)
                                for row in rows if row["trip_id"] in standard_asahikawa))
            self.assertTrue(all(row["car_count"] == 4 and row["vehicle_series"] == "キハ261系1000代"
                                for row in rows if row["trip_id"] in standard_eastern))
            self.assertEqual({row["trip_id"]: row["car_count"] for row in rows
                              if row["trip_id"] in standard_northern | {suzuran_twelve}},
                             {"jr-hokkaido.okhotsk.4.exact-2026-09-30": 3,
                              "jr-hokkaido.sarobetsu.4-dated-20260930.2026-09-30": 4,
                              "jr-hokkaido.soya.52d.exact-2026-09-30": 4,
                              suzuran_twelve: 5})
            self.assertTrue(all(row["green_car_available"] == 1 for row in rows
                                if row["service_id"] in ("hokuto", "ozora", "tokachi")))
            self.assertTrue(all(row["green_car_available"] is None for row in rows
                                if row["service_id"] == "suzuran"))
            self.assertFalse(db.execute("SELECT 1 FROM trip_formations WHERE service_date='2026-09-29'").fetchone())
            self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_asahikawa_date_selected_green_icons_have_train_sources(self):
        expected = {
            "s=110": {"3001M", "3003M", "3005M", "3011M", "3013M", "3017M", "3023M", "3025M", "3027M", "51D", "6063D"},
            "s=111": {"3002M", "3008M", "3012M", "3014M", "3016M", "3020M", "3022M", "3024M", "52D", "6064D"},
        }
        data, origins = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        self.assertEqual(timetable.validate_dataset(data, origins, timetable.load_manifest(BASE)), [])
        daily = {trip["trip_id"]: trip for trip in timetable.materialize(data, "2026-09-30")}
        sources = {row["source_id"]: row for row in data["source_documents"]}
        facts = {(row["entity_id"], row["field_name"]): row for row in data["fact_sources"]
                 if row["field_name"] == "formation.green_car_available"}
        core_path = BASE / "normalized/trip-formations/reviewed-formations-20260930/seeds.jsonl"
        core_ids = {json.loads(line)["formation_id"] for line in core_path.read_text().splitlines()
                    if line.strip()}
        rows = [row for row in data["trip_formations"]
                if row["formation_id"] in core_ids and row["trip_id"].startswith("jr-hokkaido.")
                and row["service_date"] == "2026-09-30"]
        actual = {section: set() for section in expected}
        for row in rows:
            trip = daily[row["trip_id"]]
            number = trip["train_number"]
            section = next((section for section, numbers in expected.items() if number in numbers), None)
            if section is None:
                if trip["service_id"] in ("suzuran", "kamui", "okhotsk"):
                    self.assertIsNone(row.get("green_car_available"))
                continue
            actual[section].add(number)
            self.assertIs(row["green_car_available"], True)
            self.assertEqual(row["evidence_kind"], "planned")
            if trip["service_id"] == "lilac":
                self.assertEqual((row.get("car_count"), row.get("vehicle_series")),
                                 (6, "789系0代"))
            elif number in ("52D", "6064D"):
                self.assertEqual((row.get("car_count"), row.get("vehicle_series")),
                                 (4, "キハ261系0代"))
            else:
                self.assertIsNone(row.get("car_count"))
                self.assertIsNone(row.get("vehicle_series"))
            self.assertFalse(any(car["formation_id"] == row["formation_id"]
                                 for car in data["trip_formation_cars"]))
            expected_url = f"https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&{section}"
            self.assertEqual(sources[row["source_id"]]["url_or_locator"], expected_url)
            self.assertEqual(sources[row["source_id"]]["effective_date"], "2026-09-30")
            fact = facts[(row["trip_id"], "formation.green_car_available")]
            self.assertEqual(fact["source_id"], row["source_id"])
            self.assertIn(number, fact["page_or_locator"])
        self.assertEqual(actual, expected)
        self.assertEqual(len(rows), 70)
        self.assertEqual(sum(row.get("green_car_available") is True for row in rows), 54)
        self.assertEqual(sum(row.get("green_car_available") is None for row in rows), 16)

    def test_ozora_two_reservation_icons_are_exact_date(self):
        data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        tid = "jr-hokkaido.ozora.2.exact-2026-09-30"
        formation = next(row for row in data["trip_formations"] if row["trip_id"] == tid)
        self.assertEqual((formation["service_date"], formation["evidence_kind"],
                          formation["all_reserved"], formation["green_car_available"],
                          formation.get("car_count"), formation.get("vehicle_series")),
                         ("2026-09-30", "planned", True, True, 4, "キハ261系1000代"))
        source = next(row for row in data["source_documents"] if row["source_id"] == formation["source_id"])
        self.assertEqual(source["url_or_locator"],
                         "https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=131")

    def test_new_kyushu_and_shikoku_seat_equipment_is_dated(self):
        expected = {
            "jr-kyushu.yufu.6.2026-09-30": (0, None, None, None),
            "jr-kyushu.sonic.2.2026-09-30": (0, 1, 7, "883"),
            "jr-kyushu.sonic.4.2026-09-30": (0, 1, 7, "883"),
            "jr-kyushu.sonic.6.2026-09-30": (0, 1, 6, "885"),
            "jr-kyushu.sonic.8.2026-09-30": (0, 1, 7, "883"),
            "jr-kyushu.sonic.10.2026-09-30": (0, 1, 6, "885"),
            "jr-kyushu.sonic.12.2026-09-30": (0, 1, 6, "885"),
            "jr-shikoku.shiokaze.1.2026-09-30": (0, None, None, None),
            "jr-shikoku.uwakai.3.2026-09-30": (0, None, None, None),
            "jr-shikoku.uwakai.5.2026-09-30": (0, None, None, None),
            "jr-shikoku.uwakai.7.2026-09-30": (0, None, None, None),
            "jr-shikoku.uwakai.9.2026-09-30": (0, None, None, None),
            "jr-shikoku.uwakai.11.2026-09-30": (0, None, None, None),
        }
        with sqlite3.connect(DB) as db:
            db.row_factory = sqlite3.Row
            for tid, (all_reserved, green, car_count, series) in expected.items():
                with self.subTest(trip=tid):
                    row = db.execute("SELECT * FROM trip_formations WHERE trip_id=?", (tid,)).fetchone()
                    self.assertIsNotNone(row)
                    self.assertEqual((row["service_date"], row["evidence_kind"], row["all_reserved"],
                                      row["green_car_available"], row["car_count"], row["vehicle_series"]),
                                     ("2026-09-30", "planned", all_reserved, green, car_count, series))
                    source = db.execute("SELECT effective_date, url_or_locator FROM source_documents WHERE source_id=?",
                                        (row["source_id"],)).fetchone()
                    self.assertEqual(source["effective_date"], "2026-09-30")
                    self.assertIn("20260930", source["url_or_locator"])

    def test_narita_express_5_reservation_equipment_is_exact_date(self):
        candidate = json.loads((BASE / "candidates/jr-east-narita-express5-20260930.json")
                               .read_text(encoding="utf-8"))
        with sqlite3.connect(DB) as db:
            db.row_factory = sqlite3.Row
            rows = db.execute("SELECT * FROM trip_formations WHERE trip_id IN (?, ?) ORDER BY trip_id",
                              tuple(row["trip_id"] for row in candidate["trips"])).fetchall()
            self.assertEqual(len(rows), 2)
            self.assertEqual({row["service_date"] for row in rows}, {"2026-09-30"})
            self.assertTrue(all(row["all_reserved"] == 1 and row["green_car_available"] == 1
                                and row["car_count"] is None and row["vehicle_series"] is None
                                and row["source_id"] == candidate["source_id"] for row in rows))
            self.assertEqual(db.execute("SELECT url_or_locator FROM source_documents WHERE source_id=?",
                                        (candidate["source_id"],)).fetchone()[0], candidate["source_url"])


if __name__ == "__main__":
    unittest.main()
