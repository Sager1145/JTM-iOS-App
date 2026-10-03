import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "build-station-names.py"
spec = importlib.util.spec_from_file_location("station_names", SCRIPT)
names = importlib.util.module_from_spec(spec)
spec.loader.exec_module(names)


class StationNamesTests(unittest.TestCase):
    def fixtures(self):
        lines = [{"id": "a", "operator": "A", "name": "A線", "stations": [["100", "上道", 0, 0]]},
                 {"id": "b", "operator": "B", "name": "B線", "stations": [["200", "上道", 0, 0]]}]
        package = {"version": "v", "lines": lines}
        english = {"byCode": {code: {"memberships": [{"lineId": line, "seq": 0, "name": "上道",
                   "en": en, "source": "source", "status": "official_verified"}]}
                   for code, line, en in [("100", "a", "Agari-michi"), ("200", "b", "Joto")]}}
        stations = {"features": [{"properties": {"n02_group_code": group, "n02_station_code": platform,
                    "station_name": "上道", "operator": op, "line_name": op + "線"}}
                    for group, platform, op in [("100", "101", "A"), ("200", "100", "B")]]}
        return package, english, stations

    def test_homonyms_and_platform_group_collision_are_not_merged(self):
        package, english, stations = self.fixtures()
        readings = {"byCode": {"101": {"name": "上道", "kana": "あがりみち"},
                              "100": {"name": "上道", "kana": "じょうとう"}},
                    "byName": {"上道": {"kana": "wrong"}}}
        table, _ = names.build_region("jp", package, readings, english, stations)
        self.assertEqual(table["byCode"]["a:100"]["kana"], "あがりみち")
        self.assertEqual(table["byCode"]["b:200"]["kana"], "じょうとう")
        self.assertEqual(table["byCode"]["100"]["en"], "Joto")
        self.assertNotIn("上道", table["byName"])

    def test_explicit_kana_and_operator_english_win_over_stale_name_table(self):
        package, english, stations = self.fixtures()
        kana = {"a:100": {"name": "上道", "kana": "あがりみち", "katakana": "アガリミチ"}}
        table, report = names.build_region("jp", package, {"byCode": {}, "byName": {}}, english, stations, kana)
        self.assertEqual(table["byCode"]["a:100"]["romaji"], "Agari-michi")
        self.assertEqual(table["byCode"]["a:100"]["katakana"], "アガリミチ")
        self.assertEqual(table["byCode"]["b:200"]["kana"], "")
        self.assertEqual(report["missingKana"], ["b:200"])
        self.assertEqual(report["memberships"][0]["englishStatus"], "official_verified")

    def test_english_translation_remains_separate_from_romanized_pronunciation(self):
        package, english, stations = self.fixtures()
        package["lines"][0]["stations"][0].append("Agari-michi Roma")
        table, _ = names.build_region("jp", package, {"byCode": {}, "byName": {}}, english, stations)
        self.assertEqual(table["byCode"]["a:100"]["en"], "Agari-michi")
        self.assertEqual(table["byCode"]["a:100"]["romaji"], "Agari-michi Roma")

    def test_character_rendering_does_not_invent_kana_or_ambiguous_translations(self):
        variants = {"jpToTraditional": {"関": "關"}, "traditionalToSimplified": {"關": "关", "東": "东"},
                    "ambiguousJapaneseCharacters": ["弁"]}
        self.assertEqual(names.chinese_rendering("関東", variants), ("關東", "关东"))
        self.assertIsNone(names.chinese_rendering("弁天", variants))
        self.assertIsNone(names.chinese_rendering("関ヶ原", variants))

    def test_north_america_is_outside_generation_scope(self):
        self.assertNotIn("us", names.REGIONS)
        self.assertNotIn("ca", names.REGIONS)


if __name__ == "__main__":
    unittest.main()
