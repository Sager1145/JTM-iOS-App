"""Review service dates independently from legal railway closure dates."""
import datetime
import json
import math
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
SOURCE_DIR = ROOT / "app/data/jp-history-sources"
CORRECTIONS_PATH = SOURCE_DIR / "reviewed-service-corrections-2026-09-28.json"


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def geometry_km(features):
    total = 0.0
    for feature in features:
        points = feature["geometry"]["coordinates"]
        for a, b in zip(points, points[1:]):
            lat = (a[1] + b[1]) / 2
            total += math.hypot(
                (a[0] - b[0]) * 111320.0 * math.cos(math.radians(lat)),
                (a[1] - b[1]) * 110540.0,
            )
    return round(total / 1000, 2)


class ReviewedServiceCorrectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.payload = load(CORRECTIONS_PATH)
        cls.corrections = {
            correction["canonical_event_id"]: correction
            for correction in cls.payload["corrections"]
        }
        canonical = load(ROOT / "app/scripts/railway/jp-rail-history-events.json")
        cls.events = {
            event["id"]: event
            for bucket in ("events", "temporal_events")
            for event in canonical[bucket]
        }
        cls.official = {
            row["source_row_id"]: row
            for row in load(SOURCE_DIR / "mlit-closures.json")["rows"]
        }
        cls.selector_reviews = {
            review["source_row_id"]: review
            for review in load(SOURCE_DIR / "reviewed-mlit-row-selectors.json")["reviews"]
        }
        overlay = load(ROOT / "app/data/rail-history.json")
        cls.sections = overlay["sections"]
        cls.stations = overlay["stations"]

    def test_sassho_last_train_service_end_and_legal_closure_are_distinct(self):
        correction = self.corrections["jp.jrh.sassho.iryodaigaku-shintotsukawa"]
        event = self.events[correction["canonical_event_id"]]
        proposed = correction["proposed"]
        last_service = datetime.date.fromisoformat(proposed["last_passenger_service_date"])
        first_unavailable = datetime.date.fromisoformat(proposed["first_unavailable_date"])

        self.assertEqual(first_unavailable, last_service + datetime.timedelta(days=1))
        self.assertEqual(proposed["service_periods"], [[None, "2020-04-18"]])
        self.assertEqual(proposed["infrastructure_periods"], [[None, "2020-05-07"]])
        self.assertEqual(proposed["legal_closure_date"], "2020-05-07")
        self.assertEqual(event["valid_to"], correction["existing"]["valid_to"])
        if "service_periods" in event:  # Also passes after the reviewed correction is integrated.
            self.assertEqual(event["service_periods"], proposed["service_periods"])
        if "infrastructure_periods" in event:
            self.assertEqual(event["infrastructure_periods"], proposed["infrastructure_periods"])
        self.assertEqual(
            self.official[correction["official_event_id"]]["effective_date"],
            proposed["legal_closure_date"],
        )
        references = {item["reference"] for item in correction["evidence"]}
        self.assertIn(
            "https://www.jrhokkaido.co.jp/CM/Info/press/pdf/20200416_KO_Sassyouline.pdf",
            references,
        )
        self.assertIn(
            "https://www.jrhokkaido.co.jp/CM/Info/press/pdf/20181221_KO_Sassyoline.pdf",
            references,
        )
        self.assertEqual(
            self.selector_reviews[correction["official_event_id"]]["event_id"], event["id"]
        )

    def test_nose_operator_dates_preserve_canonical_and_reject_conflicting_mlit_row(self):
        correction = self.corrections["jp.nose.cable"]
        event = self.events[correction["canonical_event_id"]]
        proposed = correction["proposed"]

        self.assertEqual(proposed["last_passenger_service_date"], "2023-12-03")
        self.assertEqual(proposed["first_unavailable_date"], "2023-12-04")
        self.assertEqual(proposed["legal_closure_date"], "2023-12-04")
        self.assertEqual(event["valid_to"], proposed["valid_to"])
        self.assertEqual(correction["official_row_resolution"], "unresolved_date_conflict")
        self.assertEqual(
            self.official[correction["official_event_id"]]["effective_date"], "2023-12-03"
        )
        self.assertNotEqual(
            self.official[correction["official_event_id"]]["effective_date"],
            proposed["legal_closure_date"],
        )
        self.assertNotIn(correction["official_event_id"], self.selector_reviews)
        self.assertEqual(
            correction["evidence"][0]["reference"],
            "https://noseden.hankyu.co.jp/upload_file/noseden/information/newsrelease20230922.pdf",
        )

    def test_corrected_selectors_match_shipped_surveyed_geometry(self):
        for event_id, correction in self.corrections.items():
            selector = correction["selector"]
            expected = selector["expected"]
            sections = [
                feature for feature in self.sections
                if feature["properties"]["history_id"] == event_id
            ]
            stations = [
                feature for feature in self.stations
                if feature["properties"]["history_id"].startswith(event_id + ".")
            ]
            with self.subTest(event_id=event_id):
                self.assertEqual(len(sections), expected["historical_sections"])
                self.assertEqual(len(stations), expected["historical_station_features"])
                self.assertEqual(geometry_km(sections), expected["surveyed_overlay_km"])
                event = self.events[event_id]
                if event.get("service_periods"):
                    self.assertTrue(all(feature["properties"]["service_validity"] in
                                        correction["proposed"]["service_periods"]
                                        for feature in sections))
                    self.assertTrue(all(feature["properties"].get("infrastructure_validity") in
                                        correction["proposed"]["infrastructure_periods"]
                                        for feature in sections))
                else:
                    self.assertTrue(all(feature["properties"]["valid_to"] ==
                                        correction["existing"]["valid_to"] for feature in sections))

    def test_nemuro_gap_is_recorded_without_promoting_row_074(self):
        note, = self.payload["unresolved_geometry_notes"]
        self.assertEqual(note["source_row_id"], "mlit-closures-20260401:074")
        self.assertEqual(note["status"], "unresolved_geometry_coverage_gap")
        self.assertEqual(note["official_interval"]["business_km"], 81.7)
        self.assertEqual(note["compiled_n02_23_overlay"]["surveyed_overlay_km"], 54.49)
        self.assertEqual(note["coverage_length_gap_km"], 27.21)
        self.assertNotIn(note["source_row_id"], self.selector_reviews)


if __name__ == "__main__":
    unittest.main()
