"""The origin-station inventory distinguishes links from reviewed trains."""

import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
PATH = ROOT / "app/data/train-service-history/audits/jr-west-haruka-thunderbird-20260930-inventory.json"


class WestClosedSetInventoryTests(unittest.TestCase):
    def test_exact_day_closed_set_and_evidence_levels(self):
        inventory = json.loads(PATH.read_text(encoding="utf-8"))
        self.assertEqual(inventory["service_date"], "2026-09-30")
        self.assertEqual(inventory["counts"], {
            "haruka_total": 60, "thunderbird_total": 50,
            "train_pages_reviewed": 110, "page_link_only": 0,
        })
        rows = inventory["trains"]
        self.assertEqual(len(rows), 110)
        self.assertEqual(len({(r["service_id"], r["public_number"]) for r in rows}), 110)
        for service, last in (("haruka", 60), ("thunderbird", 50)):
            self.assertEqual({r["public_number"] for r in rows if r["service_id"] == service},
                             set(range(1, last + 1)))
        self.assertEqual(sum(r["db_present_at_audit"] for r in rows),
                         inventory["db_snapshot"]["haruka_present"] +
                         inventory["db_snapshot"]["thunderbird_present"])
        self.assertEqual({r["verification_status"] for r in rows},
                         {"train_page_reviewed"})
        for row in rows:
            with self.subTest(service=row["service_id"], public=row["public_number"]):
                self.assertTrue(row["train_page_url"].endswith("?date=20260930"))
                self.assertIn(row["station_table_source"], inventory["source_station_tables"])
                if row["verification_status"] == "page_link_only":
                    self.assertNotIn("reviewed_train_number", row)
                    self.assertNotIn("reviewed_trip_id", row)
                    self.assertNotIn("operation_label", row)
                    self.assertNotIn("stops", row)
        url_by_key = {(r["service_id"], r["public_number"]): r["train_page_url"] for r in rows}
        self.assertEqual(url_by_key[("haruka", 11)],
                         "https://timetable.jr-odekake.net/train-timetable/192681?date=20260930")
        self.assertEqual(url_by_key[("thunderbird", 14)],
                         "https://timetable.jr-odekake.net/train-timetable/258031?date=20260930")
        self.assertEqual(url_by_key[("haruka", 60)],
                         "https://timetable.jr-odekake.net/train-timetable/129481?date=20260930")
        self.assertEqual(url_by_key[("thunderbird", 50)],
                         "https://timetable.jr-odekake.net/train-timetable/258261?date=20260930")


if __name__ == "__main__":
    unittest.main()
