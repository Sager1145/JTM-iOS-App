"""Pin every published Furano Lavender Express stop clock to JR Hokkaido's table."""

import json
from pathlib import Path
import unittest


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
CANDIDATE = BASE / "candidates/jr-hokkaido-hokuto-2026summer-north-shikoku-batch.json"
STOPS = BASE / "normalized/stop-times/north-shikoku-batch/seeds.jsonl"
COMPLETENESS = BASE / "normalized/fact-completeness-north-shikoku-batch.jsonl"
SOURCES = BASE / "sources/source-registry-north-shikoku-batch.jsonl"


def rows(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line]


class FuranoCompleteClocksSourcePinnedTests(unittest.TestCase):
    def test_both_published_five_stop_tables(self):
        candidate = json.loads(CANDIDATE.read_text())
        self.assertEqual(
            candidate["furano_time_source"]["url_or_locator"],
            "https://www.jrhokkaido.co.jp/CM/Info/press/pdf/260325_KO_Furano-Biei.pdf",
        )
        self.assertIn(
            candidate["furano_time_source"]["source_id"],
            {row["source_id"] for row in rows(SOURCES)},
        )
        expected = {
            "sapporo-to-furano": [
                ("札幌", None, "07:41"),
                ("岩見沢", None, "08:18"),
                ("滝川", None, "08:44"),
                ("芦別", None, "09:10"),
                ("富良野", "09:44", None),
            ],
            "furano-to-sapporo": [
                ("富良野", None, "16:53"),
                ("芦別", "17:22", None),
                ("滝川", "17:48", None),
                ("岩見沢", "18:14", None),
                ("札幌", "18:52", None),
            ],
        }
        station_names = {
            row["station_id"]: row["name_snapshot"]
            for path in sorted((BASE / "normalized").glob("station-identities*.jsonl"))
            for row in rows(path)
        }
        stop_rows = rows(STOPS)
        completeness = rows(COMPLETENESS)
        for direction, clocks in expected.items():
            trip_id = f"jr-hokkaido.furano-lavender-express.{direction}.2026-07-01"
            actual = [
                (station_names[row["station_id"]], row["arrival_time"], row["departure_time"])
                for row in stop_rows if row["trip_id"] == trip_id
            ]
            self.assertEqual(actual, clocks)
            self.assertEqual(
                [row["status"] for row in completeness
                 if row["entity_id"] == trip_id and row["dimension"] == "times"],
                ["verified"],
            )


if __name__ == "__main__":
    unittest.main()
