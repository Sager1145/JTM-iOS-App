"""Evidence and geometry checks for reviewed official MLIT closure rows."""
import copy
import importlib.util
import json
import math
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
SOURCE_DIR = ROOT / "app/data/jp-history-sources"
LEDGER_PATH = SOURCE_DIR / "reviewed-mlit-row-selectors.json"
INITIAL_TARGET_ROWS = {
    "mlit-closures-20260401:046", "mlit-closures-20260401:047",
    "mlit-closures-20260401:048", "mlit-closures-20260401:049",
    "mlit-closures-20260401:050", "mlit-closures-20260401:051",
    "mlit-closures-20260401:053", "mlit-closures-20260401:054",
    "mlit-closures-20260401:057", "mlit-closures-20260401:058",
    "mlit-closures-20260401:059", "mlit-closures-20260401:061",
    "mlit-closures-20260401:063", "mlit-closures-20260401:064",
}
RECENT_TARGET_ROWS = {
    "mlit-closures-20260401:066", "mlit-closures-20260401:071",
    "mlit-closures-20260401:073", "mlit-closures-20260401:075",
    "mlit-closures-20260401:076",
}
TARGET_ROWS = INITIAL_TARGET_ROWS | RECENT_TARGET_ROWS
OPERATOR_ALIASES = {
    "ＪＲ北海道": "北海道旅客鉄道",
    "ＪＲ西日本": "西日本旅客鉄道",
    "東京都交通局": "東京都",
}


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def geometry_km(features):
    total = 0.0
    for feature in features:
        points = feature["geometry"]["coordinates"]
        for a, b in zip(points, points[1:]):
            lat = (a[1] + b[1]) / 2
            mx = 111320.0 * math.cos(math.radians(lat))
            my = 110540.0
            total += math.hypot((a[0] - b[0]) * mx, (a[1] - b[1]) * my)
    return round(total / 1000, 2)


def unique_geometry(features, station=False):
    seen = set()
    result = []
    for feature in features:
        key = json.dumps(feature["geometry"], sort_keys=True, ensure_ascii=False)
        if station:
            key = feature["properties"]["station_name"] + ":" + key
        if key not in seen:
            seen.add(key)
            result.append(feature)
    return result


class ReviewedMlitClosureSelectorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inventory_payload = load(SOURCE_DIR / "mlit-closures.json")
        cls.opening_payload = load(SOURCE_DIR / "mlit-openings.json")
        cls.inventory = {row["source_row_id"]: row for row in cls.inventory_payload["rows"]}
        cls.ledger = load(LEDGER_PATH)
        cls.reviews = {row["source_row_id"]: row for row in cls.ledger["reviews"]}
        canonical = load(ROOT / "app/scripts/railway/jp-rail-history-events.json")
        cls.events = {event["id"]: event for event in canonical["events"]}
        overlay = load(ROOT / "app/data/rail-history.json")
        cls.sections = overlay["sections"]
        cls.stations = overlay["stations"]
        current = load(ROOT / "app/data/stations.json")
        cls.all_station_names = {
            feature["properties"]["station_name"] for feature in cls.stations + current["features"]
        }

    def test_review_ledger_passes_importer_validation_without_promoting_unlisted_rows(self):
        module_path = ROOT / "app/scripts/railway/history/import-mlit-history.py"
        spec = importlib.util.spec_from_file_location("import_mlit_history_for_closures", module_path)
        importer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(importer)
        reviews = importer.validate_selector_review_ledger(
            self.ledger, {
                "closures": self.inventory_payload["rows"],
                "openings": self.opening_payload["rows"],
            }
        )
        reviewed_ids = {review["source_row_id"] for review in reviews}
        self.assertTrue(TARGET_ROWS <= reviewed_ids)
        self.assertEqual(len(INITIAL_TARGET_ROWS), 14)
        self.assertEqual(len(RECENT_TARGET_ROWS), 5)
        inventories = {
            "closures": copy.deepcopy(self.inventory_payload["rows"]),
            "openings": copy.deepcopy(self.opening_payload["rows"]),
        }
        importer.apply_selector_review_ledger(inventories, self.ledger)
        replayed = {row["source_row_id"]: row for row in inventories["closures"]}
        self.assertTrue(all(replayed[row_id]["selector"]["status"] == "resolved"
                            for row_id in TARGET_ROWS))
        self.assertEqual(replayed["mlit-closures-20260401:065"]["selector"]["status"],
                         "unresolved")

    def test_official_rows_match_explicit_canonical_links_and_legal_dates(self):
        for row_id in sorted(TARGET_ROWS):
            with self.subTest(row_id=row_id):
                row = self.inventory[row_id]
                review = self.reviews[row_id]
                event = self.events[review["event_id"]]
                selector = review["selector"]
                expected = selector["expected"]

                self.assertIn(event.get("official_event_id"), (None, row_id))
                if event.get("official_event_id") is None:
                    self.assertEqual(row_id, "mlit-closures-20260401:073")
                self.assertEqual(event["valid_to"], row["effective_date"])
                self.assertEqual(review["official_effective_date"], row["effective_date"])
                self.assertGreaterEqual(row["effective_date"], "2006-01-01")
                self.assertEqual(event["line"], row["official_line_name"])
                self.assertEqual(
                    event["operator"],
                    OPERATOR_ALIASES.get(row["official_operator_name"], row["official_operator_name"]),
                )
                self.assertEqual(expected["from_station"], row["from_station_name"])
                self.assertEqual(expected["to_station"], row["to_station_name"])
                self.assertEqual(expected["business_km"], row["length_km"])
                if "expected" in event:
                    self.assertEqual(
                        event["expected"],
                        {"from_station": expected["from_station"],
                         "to_station": expected["to_station"],
                         "business_km": expected["business_km"]},
                    )
                self.assertEqual(review["review"]["status"], "verified")
                self.assertEqual(review["kind"], "closure")
                self.assertIn(expected["from_station"], self.all_station_names)
                self.assertIn(expected["to_station"], self.all_station_names)
                self.assertEqual(
                    review["evidence"][0]["reference"],
                    self.inventory_payload["source"]["url"],
                )
                self.assertIn(row_id.rsplit(":", 1)[1], review["evidence"][0]["locator"])

    def test_reviewed_n02_overlays_match_recorded_feature_coverage(self):
        for row_id in sorted(TARGET_ROWS):
            review = self.reviews[row_id]
            event = self.events[review["event_id"]]
            selector = review["selector"]
            expected = selector["expected"]
            event_sections = [
                feature for feature in self.sections
                if feature["properties"]["history_id"] == event["id"]
            ]
            event_stations = [
                feature for feature in self.stations
                if feature["properties"]["history_id"].startswith(event["id"] + ".")
            ]
            surveyed_sections = unique_geometry(event_sections)
            surveyed_stations = unique_geometry(event_stations, station=True)
            with self.subTest(row_id=row_id, event=event["id"]):
                self.assertEqual(selector["scope"], "legacy_release_geometry")
                self.assertEqual(selector["release"], "N02-" + event["year"])
                self.assertEqual(len(surveyed_sections), expected["historical_sections"])
                self.assertEqual(len(surveyed_stations), expected["historical_station_features"])
                self.assertEqual(geometry_km(surveyed_sections), expected["surveyed_overlay_km"])
                self.assertEqual(len(event_sections), expected.get("runtime_sections",
                                                                    expected["historical_sections"]))
                self.assertEqual(len(event_stations), expected.get("runtime_station_features",
                                                                    expected["historical_station_features"]))
                self.assertEqual(geometry_km(event_sections), expected.get("runtime_overlay_km",
                                                                           expected["surveyed_overlay_km"]))
                for feature in event_sections:
                    props = feature["properties"]
                    self.assertEqual(props["N02_003"], selector["line_name"])
                    self.assertEqual(props["N02_004"], selector["operator"])
                    if event.get("service_periods"):
                        self.assertIn(props["service_validity"], event["service_periods"])
                        self.assertIn(review["evidence"][1]["reference"], props["source"])
                    else:
                        self.assertEqual(props["valid_to"], review["official_effective_date"])
                        self.assertTrue(props["source"].startswith(selector["release"] + ";"))
                for feature in event_stations:
                    props = feature["properties"]
                    self.assertEqual(props["line_name"], selector["line_name"])
                    self.assertEqual(props["operator"], selector["operator"])
                    if event.get("service_periods"):
                        self.assertIn(props["service_validity"], event["service_periods"])
                        self.assertIn(review["evidence"][1]["reference"], props["source"])
                    else:
                        self.assertEqual(props["valid_to"], review["official_effective_date"])
                        self.assertEqual(props["source"], selector["release"])


if __name__ == "__main__":
    unittest.main()
