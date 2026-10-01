import hashlib
import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
SOURCE_DIR = ROOT / "app/data/jp-history-sources"
LEDGER_PATH = SOURCE_DIR / "reviewed-partial-opening-events.json"
TEMPORAL_SPEC = importlib.util.spec_from_file_location(
    "temporal_source", ROOT / "app/scripts/railway/history/temporal_source.py"
)
TEMPORAL = importlib.util.module_from_spec(TEMPORAL_SPEC)
TEMPORAL_SPEC.loader.exec_module(TEMPORAL)


def geometry_digest(features):
    geometries = sorted(json.dumps(
        feature["geometry"], ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ) for feature in features)
    return hashlib.sha256("\n".join(geometries).encode()).hexdigest()


def coordinates(feature):
    value = feature["geometry"]["coordinates"]
    if value and isinstance(value[0], (int, float)):
        return [value]
    return value


class ReviewedPartialOpeningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ledger = json.loads(LEDGER_PATH.read_text(encoding="utf-8"))
        cls.official = {row["source_row_id"]: row for row in json.loads(
            (SOURCE_DIR / "mlit-openings.json").read_text(encoding="utf-8")
        )["rows"]}
        cls.sections = json.loads(
            (ROOT / "app/data/rail-sections.json").read_text(encoding="utf-8")
        )["features"]
        cls.stations = json.loads(
            (ROOT / "app/data/stations.json").read_text(encoding="utf-8")
        )["features"]
        cls.history = json.loads(
            (ROOT / "app/data/rail-history.json").read_text(encoding="utf-8")
        )
        identity_document = json.loads(
            (SOURCE_DIR / "reviewed-identity-events.json").read_text(encoding="utf-8")
        )
        identity_events = (identity_document if isinstance(identity_document, list)
                           else identity_document.get("events", identity_document["rows"]))
        cls.identity_events = {event["id"]: event for event in identity_events}
        cls.audits = {
            item["event_id"]: item for item in cls.ledger["measured_selection_audit"]
        }

    @staticmethod
    def current_identity(event):
        return event.get("after") or {
            "line": event["line"], "operator": event["operator"]
        }

    def test_events_match_official_rows_and_primary_evidence(self):
        self.assertEqual(self.ledger["schema_version"], "1")
        self.assertEqual({event["id"] for event in self.ledger["events"]}, set(self.audits))
        for event in self.ledger["events"]:
            row = self.official[event["official_event_id"]]
            self.assertEqual(event["kind"], "opening")
            self.assertEqual(event["service_periods"], [[row["effective_date"], None]])
            self.assertEqual(event["segment"], {
                "from_station": row["from_station_name"],
                "to_station": row["to_station_name"],
            })
            self.assertEqual(event["expected"]["business_km"], row["length_km"])
            self.assertEqual(event.get("official_line_name", event["line"]), row["official_line_name"])
            self.assertEqual(event["operator"], row["official_operator_name"])
            self.assertEqual(event["date_precision"], "exact_day")
            self.assertEqual(event["review"]["status"], "verified")
            self.assertGreaterEqual(len(event["evidence"]), 2)
            self.assertTrue(all(item["date_precision"] == "exact_day"
                                for item in event["evidence"]))

    def test_selectors_compile_only_complete_new_features(self):
        for event in self.ledger["events"]:
            audit = self.audits[event["id"]]
            selector = event["geometry"]["selector"]
            identity = self.current_identity(event)
            selected_sections = TEMPORAL.select(
                self.sections, identity, selector["bbox"]
            )
            selected_stations = TEMPORAL.select(
                self.stations, identity, selector["bbox"], selector["stations"]
            )
            current = audit["current_selection"]
            self.assertEqual(len(selected_sections), current["section_count"], event["id"])
            self.assertEqual(
                sum(len(coordinates(feature)) - 1 for feature in selected_sections),
                current["section_edge_count"], event["id"]
            )
            self.assertEqual(len(selected_stations), current["station_count"], event["id"])
            self.assertEqual(
                sorted(feature["properties"]["station_name"] for feature in selected_stations),
                sorted(current["station_names"]), event["id"]
            )
            self.assertEqual(
                sorted(feature["properties"]["n02_station_code"] for feature in selected_stations),
                sorted(current["station_codes"]), event["id"]
            )
            self.assertEqual(geometry_digest(selected_sections),
                             current["section_geometry_sha256"], event["id"])
            self.assertEqual(geometry_digest(selected_stations),
                             current["station_geometry_sha256"], event["id"])

            compiled = TEMPORAL.compile_event(event, self.sections, self.stations)
            self.assertEqual(compiled["sections"], [], event["id"])
            self.assertEqual(compiled["stations"], [], event["id"])
            self.assertEqual(len(compiled["retirements"]), 2, event["id"])
            by_target = {
                retirement["match"]["targets"][0]: retirement
                for retirement in compiled["retirements"]
            }
            self.assertEqual(set(by_target), {"sections", "stations"}, event["id"])
            self.assertEqual(by_target["sections"]["valid_from"],
                             event["service_periods"][0][0], event["id"])
            self.assertEqual(by_target["stations"]["valid_from"],
                             event["service_periods"][0][0], event["id"])

    def test_shared_boundary_platforms_remain_undated_and_connected(self):
        for event in self.ledger["events"]:
            audit = self.audits[event["id"]]
            boundary = audit["shared_boundary"]
            selector = event["geometry"]["selector"]
            identity = self.current_identity(event)
            selected_sections = TEMPORAL.select(
                self.sections, identity, selector["bbox"]
            )
            selected_stations = TEMPORAL.select(
                self.stations, identity, selector["bbox"], selector["stations"]
            )
            boundary_matches = [feature for feature in self.stations
                                if feature["properties"].get("line_name") == identity["line"]
                                and feature["properties"].get("operator") == identity["operator"]
                                and feature["properties"].get("station_name") == boundary["station"]]
            self.assertEqual(len(boundary_matches), 1, event["id"])
            boundary_feature = boundary_matches[0]
            self.assertEqual(boundary_feature["properties"]["n02_station_code"],
                             boundary["n02_station_code"], event["id"])
            self.assertEqual(coordinates(boundary_feature), boundary["geometry"], event["id"])
            self.assertNotIn(boundary["station"], {
                feature["properties"]["station_name"] for feature in selected_stations
            }, event["id"])
            self.assertNotIn(json.dumps(boundary_feature["geometry"], sort_keys=True), {
                json.dumps(feature["geometry"], sort_keys=True)
                for feature in selected_sections
            }, event["id"])
            boundary_points = {tuple(point) for point in coordinates(boundary_feature)}
            selected_points = {
                tuple(point) for feature in selected_sections for point in coordinates(feature)
            }
            self.assertTrue(boundary_points & selected_points, event["id"])

    def test_route_acceptance_controls_use_already_open_track(self):
        events = {event["id"]: event for event in self.ledger["events"]}
        self.assertEqual(
            events["jp.opening.rinkai-tennozu"]["route_acceptance"], {
                "existing_from_station": "国際展示場",
                "existing_from_n02_station_code": "004065",
                "control_to_station": "東京テレポート",
                "control_to_n02_station_code": "004108",
                "expected_before": "solved",
                "expected_at": "solved",
            }
        )
        self.assertEqual(
            events["jp.opening.rinkai-osaki"]["route_acceptance"], {
                "existing_from_station": "東京テレポート",
                "existing_from_n02_station_code": "004108",
                "control_to_station": "天王洲アイル",
                "control_to_n02_station_code": "004129",
                "expected_before": "solved",
                "expected_at": "solved",
            }
        )
        self.assertEqual(
            events["jp.opening.osaka-monorail-minami-ibaraki-kadomashi"]["route_acceptance"], {
                "existing_from_station": "宇野辺",
                "existing_from_n02_station_code": "006596",
                "control_to_station": "南茨木",
                "control_to_n02_station_code": "006612",
                "expected_before": "solved",
                "expected_at": "solved",
            }
        )
        for event_id in (
            "jp.opening.nagoya-tsurumai-kamiotai",
            "jp.opening.kyoto-tozai-rokujizo",
        ):
            acceptance = events[event_id]["route_acceptance"]
            self.assertIsNone(acceptance["existing_from_station"])
            self.assertIn("newly opened", acceptance["reason"])

    def test_cross_identity_candidates_are_promoted_or_explicitly_withheld(self):
        withheld = self.ledger["withheld"]
        dependencies = {
            dependency
            for item in withheld
            for dependency in item.get("predecessor_event_ids", [])
        }
        dependencies.update(
            dependency
            for event in self.ledger["events"]
            for dependency in event.get("predecessor_event_ids", [])
        )
        self.assertEqual(dependencies, {
            "jp-id-osaka-monorail-main-operator-rename-2020",
            "jp-id-osaka-monorail-saito-operator-rename-2020",
        })
        promoted_rows = {event["official_event_id"] for event in self.ledger["events"]}
        withheld_rows = {
            row for item in withheld for row in item["official_event_ids"]
        }
        self.assertTrue(promoted_rows.isdisjoint(withheld_rows))

    def test_predecessor_variants_are_exact_geometry_clones(self):
        for event in self.ledger["events"]:
            dependencies = event.get("predecessor_event_ids")
            if not dependencies:
                continue
            self.assertEqual(len(dependencies), 1, event["id"])
            dependency = dependencies[0]
            identity = self.current_identity(event)
            selector = event["geometry"]["selector"]
            audit = self.audits[event["id"]]["predecessor_geometry_comparison"]
            for target, current_features in (
                ("sections", self.sections), ("stations", self.stations)
            ):
                chosen = TEMPORAL.select(
                    current_features, identity, selector["bbox"],
                    selector["stations"] if target == "stations" else None,
                )
                predecessors = [feature for feature in self.history[target]
                                if feature["properties"].get("history_id", "").startswith(
                                    dependency + "."
                                )]
                matched = [feature for feature in predecessors
                           if any(feature["geometry"] == current["geometry"]
                                  for current in chosen)]
                self.assertEqual(len(matched), len(chosen), event["id"])
                self.assertTrue(all(
                    feature["properties"].get("N02_003",
                                              feature["properties"].get("line_name"))
                    == event["line"]
                    and feature["properties"].get("N02_004",
                                                  feature["properties"].get("operator"))
                    == event["operator"]
                    for feature in matched
                ), event["id"])
                self.assertEqual(
                    geometry_digest(matched), geometry_digest(chosen), event["id"]
                )
                self.assertEqual(
                    len(chosen), audit[target[:-1] + "_count"], event["id"]
                )
                self.assertTrue(
                    audit[target[:-1] + "_geometry_multiset_equal"], event["id"]
                )

    def test_1994_sakuradori_opening_waits_for_pre_rename_station_identity(self):
        row_id = "mlit-openings-20260401:004"
        self.assertNotIn(row_id, {event["official_event_id"] for event in self.ledger["events"]})
        self.assertEqual(self.official[row_id]["selector"]["status"], "unresolved")
        withheld = next(item for item in self.ledger["withheld"]
                        if row_id in item["official_event_ids"])
        names = withheld["measured_selection_audit"]["station_identity_audit"]
        self.assertIn("瑞穂運動場", names["opening_day_new_station_names"])
        self.assertNotIn("瑞穂運動場西", names["opening_day_new_station_names"])
        self.assertEqual(names["renamed_since_opening"][0]["effective_date"], "2004-10-06")
        canonical = json.loads((ROOT / "app/scripts/railway/jp-rail-history-events.json").read_text())
        self.assertNotIn(row_id, {event.get("official_event_id")
                                 for event in canonical["temporal_events"]})

    def test_predecessor_constraint_intersects_old_operator_service_start(self):
        for event in self.ledger["events"]:
            dependencies = event.get("predecessor_event_ids")
            if not dependencies:
                continue
            dependency = dependencies[0]
            constrained_sections, constrained_stations = TEMPORAL.constrain_opening_predecessors(
                [self.identity_events[dependency], event],
                self.history["sections"], self.history["stations"],
                self.sections, self.stations,
            )
            identity = self.current_identity(event)
            selector = event["geometry"]["selector"]
            start = event["service_periods"][0][0]
            for target, current_features, constrained in (
                ("sections", self.sections, constrained_sections),
                ("stations", self.stations, constrained_stations),
            ):
                chosen = TEMPORAL.select(
                    current_features, identity, selector["bbox"],
                    selector["stations"] if target == "stations" else None,
                )
                old = [feature for feature in constrained
                       if feature["properties"].get("history_id", "").startswith(
                           dependency + "."
                       ) and any(feature["geometry"] == current["geometry"]
                                 for current in chosen)]
                self.assertEqual(len(old), len(chosen), event["id"])
                self.assertTrue(all(feature["properties"]["valid_from"] == start
                                    for feature in old), event["id"])


if __name__ == "__main__":
    unittest.main()
