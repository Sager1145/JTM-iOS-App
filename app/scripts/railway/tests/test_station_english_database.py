"""Validate the actual seven-region SQLite projection and line-specific names."""
import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest

APP = Path(__file__).resolve().parents[3]


class StationEnglishDatabaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="station-english-db-")
        cls.path = Path(cls.scratch.name) / "rail.db"
        subprocess.run(["node", str(APP / "scripts/build/build-rail-database.mjs"),
            "--out", str(cls.path), "--no-geometry", "--quiet"], check=True, capture_output=True, text=True)
        cls.db = sqlite3.connect(cls.path)
        cls.catalog = json.loads((APP / "data/station-english.json").read_text())

    @classmethod
    def tearDownClass(cls):
        cls.db.close()
        cls.scratch.cleanup()

    def test_all_seven_regions_have_exact_station_and_membership_coverage(self):
        counts = dict(self.db.execute("SELECT country_code,count(*) FROM station_detail GROUP BY country_code"))
        expected = {region.upper(): len(country["byCode"]) for region, country in self.catalog["byCountry"].items()}
        self.assertEqual(counts, expected)
        self.assertEqual(self.db.execute("SELECT count(*) FROM station_detail WHERE name_en IS NULL OR name_en='' ").fetchone()[0], 0)
        self.assertEqual(self.db.execute("SELECT count(*) FROM line_station_english").fetchone(),
                         self.db.execute("SELECT count(*) FROM line_station").fetchone())
        self.assertEqual(self.db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_every_line_preserves_the_name_and_provenance_it_identifies(self):
        expected = {(m["lineId"], m["seq"]): (m["en"], m["status"], int(m["translationMayBeWrong"]), m["source"])
            for country in self.catalog["byCountry"].values() for row in country["byCode"].values()
            for m in row["memberships"]}
        actual = {(line_id, seq): (en, status, warning, source) for line_id, seq, en, status, warning, source
            in self.db.execute("SELECT line_id,seq,en,en_status,en_translation_may_be_wrong,en_source FROM station_name_wide")}
        self.assertEqual(actual, expected)

    def test_japan_legacy_view_and_warning_constraint(self):
        self.assertEqual(self.db.execute("SELECT count(*) FROM jp_station_detail").fetchone()[0],
                         len(self.catalog["byCountry"]["jp"]["byCode"]))
        self.assertEqual(self.db.execute("""SELECT count(*) FROM station_english_jp legacy
            JOIN station_english unified ON unified.station_id=legacy.station_id
            WHERE legacy.en<>unified.en OR legacy.status<>unified.status
               OR legacy.translation_may_be_wrong<>unified.translation_may_be_wrong
               OR legacy.source<>unified.source""").fetchone()[0], 0)
        self.assertGreater(self.db.execute("SELECT count(*) FROM station_detail WHERE translation_may_be_wrong=1").fetchone()[0], 0)
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE station_english SET translation_may_be_wrong=1 WHERE status='official_verified'")


if __name__ == "__main__":
    unittest.main()
