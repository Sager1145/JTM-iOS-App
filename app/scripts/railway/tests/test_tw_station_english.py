"""AFR bilingual identity, alias coverage, and collision regressions."""
import copy
import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "apply-tw-station-english.py"
spec = importlib.util.spec_from_file_location("tw_station_english", SCRIPT)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class TaiwanEnglishTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = builder.read(builder.SOURCE)
        cls.readings = builder.read(builder.READINGS)

    def test_complete_station_and_branch_alias_coverage(self):
        repaired, _ = builder.apply_evidence(self.readings, self.source)
        stations = builder.read(builder.DATA / "stations-tw.json")["features"]
        self.assertTrue(all(repaired["byCode"][f["properties"]["n02_station_code"]]["en"]
                            for f in stations))
        # 阿里山 occurs on four lines; all four line/group aliases must agree.
        alishan = [row["en"] for key, row in repaired["byCode"].items()
                   if key.endswith(":tw-official-afr-q0000001651")]
        self.assertEqual(alishan, ["Alishan"] * 4)

    def test_rebuild_repairs_empty_values_and_is_idempotent(self):
        fresh = copy.deepcopy(self.readings)
        for row in fresh["byCode"].values():
            if row["name"] == "阿里山":
                row["en"] = ""
        fresh["byName"]["阿里山"]["en"] = ""
        repaired, changed = builder.apply_evidence(fresh, self.source)
        self.assertEqual(changed, {"byCode": 5, "byName": 1})
        repeated, changed = builder.apply_evidence(repaired, self.source)
        self.assertEqual(repeated, repaired)
        self.assertEqual(changed, {"byCode": 0, "byName": 0})

    def test_same_native_name_does_not_overwrite_other_station(self):
        readings = copy.deepcopy(self.readings)
        readings["byCode"]["UNRELATED"] = {"name": "阿里山", "en": "Different station"}
        readings["byName"]["阿里山"]["en"] = ""
        repaired, _ = builder.apply_evidence(readings, self.source)
        self.assertEqual(repaired["byCode"]["UNRELATED"]["en"], "Different station")
        self.assertEqual(repaired["byName"]["阿里山"]["en"], "")

    def test_identity_conflict_fails_without_mutating_input(self):
        readings = copy.deepcopy(self.readings)
        readings["byCode"]["AFR-Q0000001651"]["name"] = "Other station"
        original = copy.deepcopy(readings)
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            builder.apply_evidence(readings, self.source)
        self.assertEqual(readings, original)

    def test_official_spelling_variants_keep_station_specific_evidence(self):
        self.assertEqual(len(self.source["byCode"]), 19)
        shuisheliao = self.source["byCode"]["AFR-Q0000002368"]
        self.assertEqual(shuisheliao["en"], "Shuisheliao")
        self.assertIn("Shueisheliao", shuisheliao["alternativeOfficialEnglish"])
        wood = self.source["byCode"]["AFR-Q0000004496"]
        self.assertEqual(wood["zh_Hant"], "木履寮")
        self.assertIn("木屐寮", wood["identityAliases"])
        for row in self.source["byCode"].values():
            self.assertTrue(row["source"].startswith("https://afrch.forest.gov.tw/"))
            self.assertTrue(row["englishEvidence"])
            self.assertTrue(row["chineseEvidence"])
            self.assertEqual(row["retrievedAt"], self.source["retrievedAt"])


if __name__ == "__main__":
    unittest.main()
