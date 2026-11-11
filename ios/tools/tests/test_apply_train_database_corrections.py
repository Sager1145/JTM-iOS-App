"""Guards for ios/tools/apply-train-database-corrections.py.

The bundled master data and the recheck's confirmed corrections must agree: re-running the script
changes nothing, every confirmed correction is classified, and a sample of corrected records per
audit group is pinned so a later edit of the master file cannot silently undo a confirmed correction.
"""

import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "ios/tools/apply-train-database-corrections.py"
PATTERNS = ROOT / "ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json"
DERIVED = ROOT / "app/data/train-service-history/derived/train-service-patterns.json"
VARIANTS = ROOT / "app/data/train-service-history/audits/needs-variants.json"

spec = importlib.util.spec_from_file_location("apply_corrections", SCRIPT)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


def records():
    return {r["patternId"]: r for r in json.loads(PATTERNS.read_text(encoding="utf-8"))}


def names(items):
    return [s["name"] for s in items]


class AppliedCorrectionsAgreeWithBundledData(unittest.TestCase):
    def test_rerun_changes_nothing(self):
        done = subprocess.run([sys.executable, "-I", str(SCRIPT), "--check", "--quiet"],
                              capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_every_confirmed_correction_is_classified(self):
        corrections = json.loads(tool.CORRECTIONS.read_text(encoding="utf-8"))["corrections"]
        ids = {c["id"]: c for c in corrections}
        status = tool.classify(ids, tool.load_edits())
        self.assertEqual(set(status), set(ids))
        self.assertEqual(len(ids), 487)

    def test_historical_skips_are_historical(self):
        data = records()
        corrections = {c["id"]: c for c in json.loads(tool.CORRECTIONS.read_text(encoding="utf-8"))["corrections"]}
        status = tool.classify(corrections, tool.load_edits())
        for cid, (state, _, _) in status.items():
            if state == "skippedHistorical":
                row = data[corrections[cid]["recordId"]]
                self.assertTrue(row["validUntil"] and row["validUntil"] < tool.CHECKED, cid)

    def test_derived_copy_mirrors_the_master(self):
        master = records()
        derived = {r["patternId"]: r for r in json.loads(DERIVED.read_text(encoding="utf-8"))}
        for pid, row in master.items():
            copy = {k: v for k, v in derived[pid].items() if k != "_derivation"}
            self.assertEqual(copy, row, pid)

    def test_changed_records_carry_the_recheck_marker(self):
        data = records()
        for pid in ("nozomi-tokyo-shin-osaka", "hida-nagoya-takayama", "kuroshio-shinosaka-shirahama", "tobu-none"):
            if pid in data:
                self.assertIn("recheck:", data[pid]["notes"], pid)
                self.assertIn("http", data[pid]["notes"], pid)

    def test_needs_variants_lists_the_same_name_services(self):
        listed = {s["service"] for s in json.loads(VARIANTS.read_text(encoding="utf-8"))["services"]}
        for service in ("のぞみ", "ひかり", "はやぶさ", "ひだ", "ソニック", "くろしお", "はこね"):
            self.assertIn(service, listed)


class SampleOfCorrectedRecordsPerGroup(unittest.TestCase):
    def setUp(self):
        self.data = records()

    def test_shinkansen_tokaido_sanyo(self):
        nozomi = self.data["nozomi-tokyo-shin-osaka"]
        self.assertEqual(names(nozomi["stops"]), ["東京", "品川", "新横浜", "名古屋", "京都", "新大阪"])
        self.assertEqual(nozomi["optionalStops"], [])
        self.assertIsNone(self.data["hikari-rail-star-shin-osaka-hakata"]["validUntil"])
        self.assertTrue(self.data["kodama-tokyo-shin-osaka"]["allStations"])

    def test_shinkansen_kyushu(self):
        kamome = self.data["kamome-takeo-onsen-nagasaki"]
        self.assertEqual(names(kamome["stops"]), ["武雄温泉", "諫早", "長崎"])
        self.assertEqual(names(kamome["optionalStops"]), ["嬉野温泉", "新大村"])

    def test_shinkansen_tohoku_hokkaido(self):
        komachi = self.data["komachi-tokyo-akita"]
        for station in ("宇都宮", "郡山", "福島"):
            self.assertNotIn(station, names(komachi["stops"]) + names(komachi["optionalStops"]))
        self.assertIn("角館", names(komachi["optionalStops"]))

    def test_shinkansen_joetsu_hokuriku(self):
        hakutaka = self.data["hakutaka-tokyo-tsuruga"]
        self.assertIn("福井", names(hakutaka["stops"]))
        self.assertIn("小松", names(hakutaka["optionalStops"]))
        for station in ("熊谷", "本庄早稲田"):
            self.assertNotIn(station, names(hakutaka["stops"]) + names(hakutaka["optionalStops"]))
        self.assertEqual(self.data["kagayaki-tokyo-kanazawa"]["validUntil"], "2024-03-16")

    def test_jr_hokkaido(self):
        suzuran = self.data["suzuran-muroran-sapporo"]
        self.assertIn("室蘭", names(suzuran["optionalStops"]))
        self.assertIn("沼ノ端", names(suzuran["stops"]))
        self.assertIn("宗谷本線", self.data["okhotsk-sapporo-abashiri"]["lines"])

    def test_jr_central(self):
        hida = self.data["hida-nagoya-takayama"]
        self.assertEqual(hida["destination"], "高山")
        self.assertIn("飛騨古川", names(hida["optionalStops"]))
        self.assertNotIn("飛騨古川", names(hida["stops"]))

    def test_jr_east(self):
        stops = names(self.data["super-azusa-shinjuku-matsumoto"]["stops"])
        self.assertLess(stops.index("茅野"), stops.index("上諏訪"))
        yokohama = self.data["narita-express-yokohama"]
        early = self.data["narita-express-yokohama-until-2010-03"]
        self.assertEqual((yokohama["validFrom"], early["validUntil"]), ("2010-03-13", "2010-03-13"))
        self.assertNotIn("武蔵小杉", names(early["stops"]))
        self.assertEqual(self.data["akagi-ueno-maebashi"]["validUntil"], "2021-03-13")

    def test_jr_west(self):
        kuroshio = self.data["kuroshio-shinosaka-shirahama"]
        self.assertIn("日根野", names(kuroshio["stops"]))
        self.assertEqual(kuroshio["validFrom"], "2023-03-18")
        self.assertNotIn("大阪", names(self.data["kuroshio-shinosaka-shirahama-until-2023-03"]["stops"]))
        self.assertIn("城崎温泉", names(self.data["kinosaki-kyoto-kinosaki"]["optionalStops"]))
        self.assertNotIn("大阪", names(self.data["mizukaze-sanin-course"]["stops"]))

    def test_jr_kyushu_shikoku_overnight(self):
        self.assertEqual(self.data["asoboy-kumamoto-beppu"]["validUntil"], "2025-03-15")
        self.assertEqual(self.data["muroto-tokushima-mugi"]["validUntil"], "2025-03-15")
        kinan = self.data["west-express-ginga-kinan"]
        self.assertIn("和歌山", names(kinan["optionalStops"]))
        self.assertIn("土讃線", self.data["sunrise-seto-tokyo-takamatsu"]["lines"])

    def test_private_railways(self):
        self.assertNotIn("町田", names(self.data["fujisan-shinjuku-gotemba"]["stops"]))
        self.assertNotIn("大阪難波", names(self.data["ise-shima-liner-namba-kashikojima"]["stops"]))
        self.assertEqual(names(self.data["sagami-shinjuku-odawara"]["stops"]), ["新宿", "小田原"])
        self.assertIn("町田", names(self.data["sagami-shinjuku-odawara"]["optionalStops"]))
        self.assertEqual(self.data["tango-relay-amanohashidate-toyooka"]["origin"], "福知山")
        self.assertEqual(self.data["urban-park-liner-asakusa-omiya"]["validUntil"], "2024-03-16")
        kegon = self.data["kegon-asakusa-tobunikko"]
        for station in ("板倉東洋大前", "新栃木"):
            self.assertNotIn(station, names(kegon["optionalStops"]))


if __name__ == "__main__":
    unittest.main()
