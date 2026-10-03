"""Official master identity checks for Hokkaido, Osaka and JR Central."""
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "verify-jp-station-english.py"
spec = importlib.util.spec_from_file_location("jp_source_verification", SCRIPT)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


def sources():
    central = {"ryokakuSenkuCd": "050010", "ryokakuEkiCd": "90", "ryokakuSenkuKbn": "1",
               "ryokakuSenkuMei": "東海道線", "ekiMei": "豊橋"}
    raw = {"hokkaido": json.dumps([{"ja": "（臨）細岡", "en": "(Special)Hosooka", "key": "123"}]).encode(),
        "osaka-ja": '<a class="cs-stationLink" href="M/m20/index.php">なんば</a>'.encode(),
        "osaka-en": b'<a class="cs-stationLink" href="M/m20/index.php">Namba</a>',
        "central-ja": json.dumps({"lst": [central]}).encode(),
        "central-en": json.dumps({"lst": [{**central, "ekiMei": "Toyohashi"}]}).encode()}
    return raw, {key: {"sha256": hashlib.sha256(value).hexdigest(), "retrievedAt": "2026-10-01"}
                 for key, value in raw.items()}


def package(operator, name, station):
    return {"version": "test", "lines": [{"id": "l", "operator": operator, "name": name,
        "stations": [["group", station, 1, 2, "Incorrect package transliteration", 1]]}]}


class JapaneseMasterVerificationTests(unittest.TestCase):
    def test_osaka_native_alias_and_same_page_id(self):
        result = verifier.build(package("Osaka Metro", "1号線(御堂筋線)", "難波"), *sources())
        row = result["byLineStation"]["l:group"]
        self.assertEqual(row["en"], "Namba")
        self.assertEqual(row["identityEvidence"][0]["officialStationId"], "M/m20")
        self.assertEqual(row["identityEvidence"][0]["packageName"], "難波")

    def test_osaka_name_on_another_line_does_not_verify(self):
        result = verifier.build(package("Osaka Metro", "千日前線", "難波"), *sources())
        self.assertFalse(result["byLineStation"])
        self.assertEqual(len(result["unresolved"]), 1)

    def test_seasonal_marker_is_preserved_in_evidence(self):
        row = verifier.build(package("北海道旅客鉄道", "釧網線", "細岡"), *sources())["byLineStation"]["l:group"]
        self.assertEqual(row["en"], "Hosooka")
        self.assertEqual(row["identityEvidence"][0]["en"], "(Special)Hosooka")
        self.assertNotEqual(row["identityEvidence"][0]["transformation"], "none")

    def test_central_requires_published_own_line(self):
        row = verifier.build(package("東海旅客鉄道", "東海道線", "豊橋"), *sources())["byLineStation"]["l:group"]
        self.assertEqual(row["en"], "Toyohashi")
        self.assertEqual(row["identityEvidence"][0]["officialStationId"], "90")
        result = verifier.build(package("東海旅客鉄道", "飯田線", "豊橋"), *sources())
        self.assertFalse(result["byLineStation"])

    def test_other_operator_cannot_inherit_master_evidence(self):
        result = verifier.build(package("名古屋鉄道", "名古屋本線", "豊橋"), *sources())
        self.assertFalse(result["byLineStation"])

    def test_changed_source_bytes_fail_hash_check(self):
        raw, manifest = sources()
        raw["central-en"] += b" "
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            verifier.build(package("東海旅客鉄道", "東海道線", "豊橋"), raw, manifest)

    def test_duplicate_and_disagreeing_published_ids_fail(self):
        with self.assertRaisesRegex(ValueError, "conflicting official Osaka"):
            verifier.extract_osaka('<a class="cs-stationLink" href="M/m20/index.php">Namba</a>'
                '<a class="cs-stationLink" href="M/m20/index.php">Another</a>')
        raw, manifest = sources()
        raw["central-en"] = b'{"lst": []}'
        manifest["central-en"]["sha256"] = hashlib.sha256(raw["central-en"]).hexdigest()
        with self.assertRaisesRegex(ValueError, "bilingual station IDs disagree"):
            verifier.build(package("東海旅客鉄道", "東海道線", "豊橋"), raw, manifest)


if __name__ == "__main__":
    unittest.main()
