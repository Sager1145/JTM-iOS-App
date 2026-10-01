"""Pin English names to the operator evidence and the supported time period."""

import json
from pathlib import Path
import unittest


BASE = Path(__file__).resolve().parents[3] / "app/data/train-service-history"
NAMES = BASE / "normalized/service-name-periods-english.jsonl"
SOURCES = BASE / "sources/source-registry-english-names.jsonl"


def rows(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line]


class EnglishServiceNamesSourcePinnedTests(unittest.TestCase):
    def test_niseko_uses_operator_bilingual_title_for_2026_only(self):
        matches = [row for row in rows(NAMES) if row["service_id"] == "niseko"]
        self.assertEqual(matches, [{
            "language": "en",
            "name": "Niseko express",
            "name_type": "display",
            "service_id": "niseko",
            "source_id": "jr-hokkaido-niseko-train-guide-en",
            "valid_from": "2026-09-05",
            "valid_until": "2026-09-28",
        }])
        source = next(
            row for row in rows(SOURCES)
            if row["source_id"] == "jr-hokkaido-niseko-train-guide-en"
        )
        self.assertEqual(
            source["url_or_locator"],
            "https://www.jrhokkaido.co.jp/train/tr036_01.html",
        )
        self.assertIn("https://www.jrhokkaido.co.jp/travel/niseko/index.html", source["notes"])

    def test_current_english_guide_does_not_backfill_2013_names(self):
        historical = [
            row for row in rows(NAMES)
            if row["service_id"] in {"shinano", "hida", "nanki"}
            and row["valid_from"] < "2026-01-01"
        ]
        self.assertEqual(historical, [])


if __name__ == "__main__":
    unittest.main()
