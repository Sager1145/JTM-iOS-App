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
                        self.assertNotEqual(evidence.get("stationId"), entry["stationId"])

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

    def test_kyushu_bilingual_source_corrects_community_labels(self):
        package = builder.read(builder.PACKAGE)
        kyushu_codes = {s[0] for line in package["lines"] if line["operator"] == "九州旅客鉄道"
                        for s in line["stations"]}
        rows = [CATALOG["byCode"][code] for code in kyushu_codes]
        self.assertEqual(sum(row["status"] == "official_verified" for row in rows), 562)
        for name, expected in [("新大牟田", "Shin-Omuta"), ("引治", "Hikiji"),
                               ("豊後国分", "Bungo-Kokubu"), ("歓遊舎ひこさん", "Kanyusha-Hikosan")]:
            match = next(row for row in rows if row["ja"] == name)
            self.assertEqual(match["en"], expected)
            self.assertEqual(match["status"], "official_verified")
            evidence = match["identityEvidence"][0]
            self.assertEqual(evidence["source"], builder.KYUSHU_SOURCE)
            self.assertTrue(evidence["pages"])

    def test_current_timetable_supersedes_old_typo_and_station_name(self):
        for name, expected in [("新大村", "Shin-Ōmura"), ("江北", "Kōhoku")]:
            row = next(row for row in CATALOG["byCode"].values()
                       if row["ja"] == name and row["source"] == builder.KYUSHU_TIMETABLE)
            self.assertEqual(row["en"], expected)
            self.assertEqual(row["status"], "official_verified")
            self.assertEqual(row["source"], builder.KYUSHU_TIMETABLE)
        superseded = self.row("新大村")["identityEvidence"][0]["supersededEvidence"]
        self.assertEqual(superseded["publishedEn"], "SIN-OMURA")
        unmatched = {row["ja"] for row in CATALOG["identityReview"]
                     if row["operator"] == "九州旅客鉄道" and not row["packageCodes"]}
        self.assertIn("肥前山口", unmatched)
        self.assertIn("神崎", unmatched)
        self.assertIn("安部山公园", unmatched)

    def test_kyushu_extraction_preserves_words_and_removes_pdf_spacing(self):
        rows = builder.extract_kyushu_station_rows([(2, """
TOKYO 도쿄 東京 东京 東京
MOJ IKO 모지코 門司港 门司港 門司港
SPACE WORLD 스페이스월드 太空世界 太空世界 スペースワールド
S AT SUMA-MAT SUMOTO사츠마마츠모토 薩摩松元 萨摩松元 薩摩松元
HUIS TEN BOSCH 하우스텐보스 豪斯登堡 豪斯登堡 ハウステンボス
"""), (3, "MOJIKO 모지코 門司港 门司港 門司港")])
        self.assertNotIn("東京", rows)
        self.assertEqual(rows["門司港"]["en"], "Mojiko")
        self.assertEqual(rows["門司港"]["pages"], [2, 3])
        self.assertEqual(rows["スペースワールド"]["en"], "Space World")
        self.assertEqual(rows["薩摩松元"]["publishedEn"], "SATSUMA-MATSUMOTO")
        self.assertEqual(rows["ハウステンボス"]["en"], "Huis Ten Bosch")
        with self.assertRaisesRegex(ValueError, "conflicting JR Kyushu"):
            builder.extract_kyushu_station_rows([(2, "MOJIKO 모지코 門司港 门司港 門司港\nWRONG 모지코 門司港 门司港 門司港")])

    def test_every_operator_is_in_coverage_ledger(self):
        package = builder.read(builder.PACKAGE)
        summary = CATALOG["coverage"]
        self.assertEqual(summary["stationGroups"], len(CATALOG["byCode"]))
        self.assertEqual(sum(summary["statusCounts"].values()), summary["stationGroups"])
        self.assertEqual(set(summary["operatorCoverage"]), {line["operator"] for line in package["lines"]})
        for operator, coverage in summary["operatorCoverage"].items():
            codes = {s[0] for line in package["lines"] if line["operator"] == operator for s in line["stations"]}
            self.assertEqual(coverage["stationGroups"], len(codes))
            verified = sum(CATALOG["byCode"][code]["status"] == "official_verified" for code in codes)
            self.assertEqual(coverage["officialVerified"], verified)
            self.assertEqual(coverage["unresolved"], len(codes) - verified)

    def test_verified_group_evidence_identifies_its_operator(self):
        package = builder.read(builder.PACKAGE)
        operators = {line["operator"] for line in package["lines"]}
        for code, row in CATALOG["byCode"].items():
            if row["status"] == "official_verified":
                self.assertTrue(row.get("identityEvidence"), code)
            for evidence in row.get("identityEvidence", []):
                self.assertIn(evidence["operator"], operators, code)
                self.assertTrue(evidence["source"].startswith("https://"), code)
                self.assertTrue(evidence["identitySource"].startswith("https://"), code)
                self.assertTrue(evidence["retrievedAt"], code)

    def test_shared_iseshi_group_retains_only_jr_central_official_evidence(self):
        # JR Central's index proves its own Ise-shi spelling. The shared group
        # also belongs to Kintetsu; group membership cannot manufacture proof
        # of Kintetsu's operator-specific English label.
        row = CATALOG["byCode"]["007857"]
        self.assertEqual(row["ja"], "伊勢市")
        self.assertEqual({evidence["operator"] for evidence in row["identityEvidence"]},
                         {"東海旅客鉄道"})
        self.assertEqual(row["identityEvidence"][0]["mapping"], "reviewed group code override")

    def test_toei_evidence_keeps_bilingual_number_join(self):
        row = self.row("西馬込")
        evidence = next(e for e in row["identityEvidence"] if e["operator"] == "東京都")
        self.assertEqual(evidence["stationNumber"], "A01")
        self.assertEqual(evidence["ja"], "西馬込")
        self.assertTrue(evidence["japaneseSource"].endswith("/subway/stations/"))

    def test_kyushu_duplicate_identity_revokes_verification(self):
        package = copy.deepcopy(builder.read(builder.PACKAGE))
        line = next(line for line in package["lines"] if line["operator"] == "九州旅客鉄道"
                    and any(s[1] == "新大牟田" for s in line["stations"]))
        station = copy.deepcopy(next(s for s in line["stations"] if s[1] == "新大牟田"))
        original_code = station[0]
        station[0] = "990001"
        package["lines"].append({"operator": "九州旅客鉄道", "stations": [station]})
        with tempfile.TemporaryDirectory() as scratch:
            package_path = Path(scratch) / "package.json"
            output_path = Path(scratch) / "catalog.json"
            package_path.write_text(json.dumps(package, ensure_ascii=False), encoding="utf-8")
            with patch.object(builder, "PACKAGE", package_path), patch.object(builder, "OUTPUT", output_path), \
                    patch.object(sys, "argv", [str(SCRIPT)]), contextlib.redirect_stdout(io.StringIO()):
                builder.build()
            rebuilt = builder.read(output_path)
            for code in (original_code, "990001"):
                self.assertNotEqual(rebuilt["byCode"][code]["status"], "official_verified")
            self.assertTrue(any(row["operator"] == "九州旅客鉄道" and row["ja"] == "新大牟田"
                                and len(row["packageCodes"]) == 2 for row in rebuilt["identityReview"]))


if __name__ == "__main__":
    unittest.main()
