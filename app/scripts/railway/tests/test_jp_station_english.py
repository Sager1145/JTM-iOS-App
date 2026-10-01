"""Station identity and warning regressions for the JP English catalog."""
import contextlib
import copy
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "build-jp-station-english.py"
spec = importlib.util.spec_from_file_location("jp_station_english", SCRIPT)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
CATALOG = builder.read(builder.OUTPUT)


class StationEnglishTests(unittest.TestCase):
    def row(self, name):
        matches = [r for r in CATALOG["byCode"].values() if r["ja"] == name]
        self.assertEqual(len(matches), 1)
        return matches[0]

    def test_complete_group_coverage_and_warning_contract(self):
        package = builder.read(builder.PACKAGE)
        codes = {s[0] for line in package["lines"] for s in line["stations"]}
        self.assertEqual(set(CATALOG["byCode"]), codes)
        for row in CATALOG["byCode"].values():
            self.assertTrue(row["en"].strip())
            self.assertEqual(row["translationMayBeWrong"], row["status"] != "official_verified")

    def test_bilingual_identity_verifies_different_romanization(self):
        # Earlier Romanized-label matching missed Omote-sando and Myogadani.
        for name in ("表参道", "茗荷谷", "虎ノ門ヒルズ", "空港第2ビル"):
            row = self.row(name)
            self.assertEqual(row["status"], "official_verified")
            self.assertTrue(row["identityEvidence"])
            self.assertTrue(all(e["identitySource"].startswith("https://")
                                for e in row["identityEvidence"]))

    def test_nagaoka_index_mislink_is_resolved_and_retained(self):
        source = builder.read(builder.DATA / "jp-station-english-jre-source.json")
        nagaoka = source["byEnglishName"]["Nagaoka"]
        nagano = source["byEnglishName"]["Nagano"]
        self.assertEqual(nagaoka["indexStationId"], nagano["stationId"])
        self.assertEqual(nagaoka["stationId"], "1085")
        self.assertEqual(nagaoka["ja"], "長岡")
        self.assertEqual(self.row("長岡")["identityEvidence"][0]["source"],
                         "https://www.jreast.co.jp/e/stations/e1085.html")

    def test_source_typo_never_loses_warning(self):
        row = self.row("新松戸")
        self.assertEqual(row["status"], "official_spelling_candidate")
        self.assertTrue(row["translationMayBeWrong"])
        self.assertIn("reviewNote", row["identityEvidence"][0])

    def test_ambiguous_station_groups_are_in_review_ledger(self):
        expected = {("東京メトロ", "池袋"), ("東日本旅客鉄道", "武蔵小杉"),
                    ("東日本旅客鉄道", "東京")}
        actual = {(r["operator"], r["ja"]) for r in CATALOG["identityReview"]
                  if len(r["packageCodes"]) > 1}
        self.assertEqual(actual, expected)
        for entry in CATALOG["identityReview"]:
            if len(entry["packageCodes"]) > 1:
                for code in entry["packageCodes"]:
                    for evidence in CATALOG["byCode"][code].get("identityEvidence", []):
                        self.assertNotEqual(evidence["stationId"], entry["stationId"])

    def test_new_duplicate_identity_cannot_be_promoted(self):
        # A new group with the same operator/name must revoke a unique join.
        package = copy.deepcopy(builder.read(builder.PACKAGE))
        line = next(l for l in package["lines"] if l["operator"] == "東京メトロ"
                    and any(s[1] == "表参道" for s in l["stations"]))
        station = copy.deepcopy(next(s for s in line["stations"] if s[1] == "表参道"))
        original_code = station[0]
        station[0] = "990000"
        station[4] = "Different provisional label"
        package["lines"].append({"operator": "東京メトロ", "stations": [station]})
        with tempfile.TemporaryDirectory() as scratch:
            package_path = Path(scratch) / "package.json"
            output_path = Path(scratch) / "catalog.json"
            package_path.write_text(json.dumps(package, ensure_ascii=False), encoding="utf-8")
            with patch.object(builder, "PACKAGE", package_path), patch.object(builder, "OUTPUT", output_path), \
                    patch.object(sys, "argv", [str(SCRIPT)]), contextlib.redirect_stdout(io.StringIO()):
                builder.build()
            rebuilt = builder.read(output_path)
            for code in (original_code, "990000"):
                self.assertNotEqual(rebuilt["byCode"][code]["status"], "official_verified")
                self.assertTrue(rebuilt["byCode"][code]["translationMayBeWrong"])


if __name__ == "__main__":
    unittest.main()
