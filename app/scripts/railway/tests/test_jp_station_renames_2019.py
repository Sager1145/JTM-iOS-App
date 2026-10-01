import json
import sys
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "app/data/jp-history-sources/reviewed-station-renames-2019.json"
sys.path.insert(0, str(ROOT / "app/scripts/railway/history"))
import temporal_source as temporal  # noqa: E402


class StationRenames2019Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.payload = json.loads(SOURCE.read_text(encoding="utf-8"))
        cls.stations = json.loads(
            (ROOT / "app/data/stations.json").read_text(encoding="utf-8")
        )["features"]
        cls.sections = json.loads(
            (ROOT / "app/data/rail-sections.json").read_text(encoding="utf-8")
        )["features"]

    def test_primary_sources_and_all_reviewable_memberships_are_explicit(self):
        self.assertEqual(len(self.payload["events"]), 5)
        self.assertEqual(len(self.payload["withheld"]), 1)
        self.assertEqual(
            {event["membership_id"] for event in self.payload["events"]},
            {
                "jp.membership.hankyu.kobe.hk01",
                "jp.membership.hankyu.takarazuka.hk01",
                "jp.membership.hanshin-main.hs01",
                "jp.membership.hankyu-kyoto.hk86",
                "jp.membership.hanshin-main.hs13",
            },
        )
        withheld = self.payload["withheld"][0]
        self.assertEqual(withheld["membership_id"], "jp.membership.hankyu.kyoto.hk01")
        self.assertEqual(withheld["review"]["status"], "withheld_missing_current_membership")
        self.assertTrue(all(event["date"] == "2019-10-01" for event in self.payload["events"]))
        self.assertTrue(all(event["date_precision"] == "exact_day" for event in self.payload["events"]))
        source_ids = {source["source_id"] for source in self.payload["sources"]}
        self.assertIn("hankyu-station-renames-2019", source_ids)
        self.assertIn("hanshin-station-renames-2019", source_ids)
        self.assertEqual(
            self.payload["primary_source_ids"],
            ["hankyu-station-renames-2019", "hanshin-station-renames-2019"],
        )

    def test_current_memberships_are_exact_and_old_geometry_compiles(self):
        expected_feature_counts = {
            "jp.station-rename.hankyu.hk01.osaka-umeda.kobe": 2,
            "jp.station-rename.hankyu.hk01.osaka-umeda.takarazuka": 1,
            "jp.station-rename.hanshin.hs01.osaka-umeda": 1,
            "jp.station-rename.hankyu.hk86.kyoto-kawaramachi": 1,
            "jp.station-rename.hanshin.hs13.naruo-mukogawajoshidai-mae": 1,
        }
        retirements = []
        for event in self.payload["events"]:
            with self.subTest(event=event["id"]):
                temporal.validate(event)
                after = event["after"]
                current = [
                    feature
                    for feature in self.stations
                    if feature["properties"]["line_name"] == after["line"]
                    and feature["properties"]["operator"] == after["operator"]
                    and feature["properties"]["station_name"] == after["station"]
                ]
                self.assertEqual(len(current), expected_feature_counts[event["id"]])
                self.assertEqual(
                    {feature["properties"]["n02_station_code"] for feature in current},
                    {event["current_n02_station_code"]},
                )
                historical = event["geometry"]["historical_stations"]
                self.assertCountEqual(
                    [feature["geometry"] for feature in historical],
                    [feature["geometry"] for feature in current],
                )
                self.assertTrue(
                    all("n02_station_code" not in feature["properties"] for feature in historical)
                )
                compiled = temporal.compile_event(event, self.sections, self.stations)
                self.assertEqual(compiled["sections"], [])
                self.assertEqual(len(compiled["stations"]), len(historical))
                self.assertEqual(len(compiled["retirements"]), 1)
                self.assertEqual(
                    {feature["properties"]["station_name"] for feature in compiled["stations"]},
                    {event["before"]["station"]},
                )
                self.assertEqual(
                    {tuple(feature["properties"]["service_validity"])
                     for feature in compiled["stations"]},
                    {(None, "2019-10-01")},
                )
                self.assertEqual(
                    {feature["properties"].get("n02_station_code")
                     for feature in compiled["stations"]},
                    {event["current_n02_station_code"]},
                )
                self.assertTrue(
                    all(feature["properties"].get("station_code_basis")
                        == "exact_current_geometry_identity"
                        for feature in compiled["stations"])
                )
                retirements.extend(compiled["retirements"])
        self.assertEqual(
            len(temporal.normalize_stamps(retirements, self.sections, self.stations)), 5
        )

    def test_kyoto_line_hk01_is_withheld_because_current_selector_is_empty(self):
        withheld = self.payload["withheld"][0]
        for name in (withheld["before"]["station"], withheld["after"]["station"]):
            matches = [
                feature
                for feature in self.stations
                if feature["properties"]["line_name"] == "京都線"
                and feature["properties"]["operator"] == "阪急電鉄"
                and feature["properties"]["station_name"] == name
            ]
            self.assertEqual(matches, [], name)

    def test_fixture_constraints_pin_only_the_adjacent_origin(self):
        expected = {
            "jp.station-rename.hankyu.hk01.osaka-umeda.kobe": ("十三", "006970"),
            "jp.station-rename.hankyu.hk01.osaka-umeda.takarazuka": ("十三", "006968"),
            "jp.station-rename.hanshin.hs01.osaka-umeda": ("福島", "007098"),
            "jp.station-rename.hankyu.hk86.kyoto-kawaramachi": ("烏丸", "005992"),
            "jp.station-rename.hanshin.hs13.naruo-mukogawajoshidai-mae": ("甲子園", "006954"),
        }
        events = {event["id"]: event for event in self.payload["events"]}
        for audit in self.payload["selection_audit"]:
            with self.subTest(event=audit["event_id"]):
                fixture = audit["route_fixture"]
                self.assertEqual(
                    (fixture["origin_station"], fixture["origin_n02_station_code"]),
                    expected[audit["event_id"]],
                )
                self.assertIsNone(fixture["target_station_code"])
                self.assertEqual(
                    events[audit["event_id"]]["route_acceptance"],
                    {"from_station": fixture["origin_station"]},
                )
                event = events[audit["event_id"]]
                origin_matches = [
                    feature
                    for feature in self.stations
                    if feature["properties"]["station_name"] == fixture["origin_station"]
                    and feature["properties"]["line_name"] == event["after"]["line"]
                    and feature["properties"]["operator"] == event["after"]["operator"]
                    and feature["properties"]["n02_station_code"]
                    == fixture["origin_n02_station_code"]
                ]
                self.assertEqual(len(origin_matches), 1)

    def test_recorded_route_service_probe_selects_the_real_membership(self):
        events = {event["id"]: event for event in self.payload["events"]}
        umeda_ids = {
            "jp.station-rename.hankyu.hk01.osaka-umeda.kobe",
            "jp.station-rename.hankyu.hk01.osaka-umeda.takarazuka",
            "jp.station-rename.hanshin.hs01.osaka-umeda",
        }
        for audit in self.payload["selection_audit"]:
            event = events[audit["event_id"]]
            results = {
                (item["query_name_side"], item["ride_date_side"]): item
                for item in audit["route_service_probe"]["results"]
            }
            with self.subTest(event=event["id"]):
                old_before = results[("old", "before")]
                self.assertEqual(old_before["outcome"], "solved")
                self.assertEqual(old_before["selected_endpoint"]["name"], event["before"]["station"])
                self.assertEqual(old_before["selected_endpoint"]["line"], event["before"]["line"])
                self.assertEqual(old_before["selected_endpoint"]["operator"], event["before"]["operator"])
                self.assertEqual(results[("new", "before")]["outcome"], "unsolvable")
                new_after = results[("new", "after")]
                self.assertEqual(new_after["outcome"], "solved")
                self.assertEqual(new_after["selected_endpoint"]["name"], event["after"]["station"])
                self.assertEqual(new_after["selected_endpoint"]["line"], event["after"]["line"])
                self.assertEqual(new_after["selected_endpoint"]["operator"], event["after"]["operator"])
                old_after = results[("old", "after")]
                if event["id"] in umeda_ids:
                    self.assertEqual(old_after["outcome"], "solved")
                    self.assertEqual(old_after["selected_endpoint"]["operator"], "大阪市高速電気軌道")
                    self.assertEqual(old_after["selected_endpoint"]["line"], "1号線(御堂筋線)")
                else:
                    self.assertEqual(old_after["outcome"], "unsolvable")

    def test_local_n02_release_names_when_snapshot_archive_is_available(self):
        archive_root = Path(
            "/Users/sager/Documents/GitHub/Japan-Train-Map/app/data/raw/railway/jp/history"
        )
        if not archive_root.exists():
            self.skipTest("local N02 history archive is not installed")

        def station_features(release):
            archive = archive_root / f"{release}_GML.zip"
            with zipfile.ZipFile(archive) as source:
                member = next(name for name in source.namelist() if name.endswith("_Station.geojson"))
                return json.loads(source.read(member))["features"]

        def values(feature):
            props = feature["properties"]
            return (
                props.get("N02_003", props.get("路線名")),
                props.get("N02_004", props.get("運営会社")),
                props.get("N02_005", props.get("駅名")),
            )

        releases = {name: station_features(name) for name in ("N02-18", "N02-19", "N02-20")}
        for event in self.payload["events"]:
            with self.subTest(event=event["id"]):
                old_release = event["geometry"]["release"]
                old_key = tuple(event["before"].values())
                old = [feature for feature in releases[old_release] if values(feature) == old_key]
                self.assertEqual(len(old), len(event["geometry"]["historical_stations"]))
                self.assertTrue(
                    all("N02_005c" not in feature["properties"]
                        and "N02_005g" not in feature["properties"] for feature in old)
                )
                self.assertCountEqual(
                    [feature["geometry"]["coordinates"] for feature in old],
                    [feature["geometry"]["coordinates"]
                     for feature in event["geometry"]["historical_stations"]],
                )
                post_release = next(
                    audit["earliest_post_rename_observation"]["release"]
                    for audit in self.payload["selection_audit"]
                    if audit["event_id"] == event["id"]
                )
                post_key = tuple(event["after"].values())
                post = [feature for feature in releases[post_release] if values(feature) == post_key]
                self.assertEqual(len(post), len(old))


if __name__ == "__main__":
    unittest.main()
