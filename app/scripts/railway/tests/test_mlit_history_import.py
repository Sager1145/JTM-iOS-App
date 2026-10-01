import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[4]
MODULE_PATH = ROOT / "app/scripts/railway/history/import-mlit-history.py"
SPEC = importlib.util.spec_from_file_location("import_mlit_history", MODULE_PATH)
IMPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(IMPORTER)
TEMPORAL_SPEC = importlib.util.spec_from_file_location(
    "temporal_source", ROOT / "app/scripts/railway/history/temporal_source.py"
)
TEMPORAL = importlib.util.module_from_spec(TEMPORAL_SPEC)
TEMPORAL_SPEC.loader.exec_module(TEMPORAL)
SOURCE_DIR = ROOT / "app/data/jp-history-sources"


class MlitHistoryImportTests(unittest.TestCase):
    def copy_checked_inventory(self, output):
        for name in (
            "mlit-openings.json", "mlit-closures.json", "source-registry.json",
            "reviewed-mlit-row-selectors.json",
        ):
            (output / name).write_bytes((SOURCE_DIR / name).read_bytes())

    def test_japanese_era_dates_are_exact_days(self):
        self.assertEqual(IMPORTER.era_day("平9.10.1"), "1997-10-01")
        self.assertEqual(IMPORTER.era_day("令元.5.1"), "2019-05-01")
        with self.assertRaises(SystemExit):
            IMPORTER.era_day("平成9年10月")

    def test_parser_rejects_a_date_bearing_row_outside_date_column(self):
        # A future PDF layout shift must fail rather than silently omit the row.
        rendered_row = [
            {"tx": 60, "text": "試験線"},
            {"tx": 150, "text": "試験事業者"},
            {"tx": 250, "text": "起点"},
            {"tx": 330, "text": "終点"},
            {"tx": 390, "text": "令6.3.16"},  # km column, not the date column
        ]
        with mock.patch.object(IMPORTER, "pypdf_lines", return_value=[(1, 100, rendered_row)]):
            with self.assertRaisesRegex(SystemExit, "date-bearing source row was not captured"):
                IMPORTER.parse_table(Path("unused.pdf"), "openings", "2026-09-27")

    def test_inventory_fingerprint_covers_official_row_identity(self):
        payload = json.loads((SOURCE_DIR / "mlit-openings.json").read_text(encoding="utf-8"))
        rows = payload["rows"]
        self.assertEqual(
            IMPORTER.inventory_fingerprint(rows),
            IMPORTER.TABLES["openings"]["inventory_sha256"],
        )
        review_only = copy.deepcopy(rows)
        review_only[0]["selector"]["reason"] = "review note changed"
        self.assertEqual(IMPORTER.inventory_fingerprint(review_only), IMPORTER.inventory_fingerprint(rows))
        official_change = copy.deepcopy(rows)
        official_change[0]["effective_date"] = "1994-03-31"
        self.assertNotEqual(IMPORTER.inventory_fingerprint(official_change), IMPORTER.inventory_fingerprint(rows))

    def test_check_rejects_same_length_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            self.copy_checked_inventory(output)
            path = output / "mlit-openings.json"
            payload = json.loads(path.read_text(encoding="utf-8"))
            payload["rows"][0]["official_line_name"] = "omitted row replaced by another"
            payload["inventory"]["row_identity_sha256"] = IMPORTER.inventory_fingerprint(payload["rows"])
            path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            with self.assertRaisesRegex(SystemExit, "reviewed complete inventory"):
                IMPORTER.validate_checked_in(output)

    def test_check_rejects_omitted_row(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            self.copy_checked_inventory(output)
            path = output / "mlit-closures.json"
            payload = json.loads(path.read_text(encoding="utf-8"))
            payload["rows"].pop()
            path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            with self.assertRaisesRegex(SystemExit, "expected 78 rows"):
                IMPORTER.validate_checked_in(output)

    def test_review_ledger_resolves_only_explicit_verified_rows_and_replays_idempotently(self):
        inventories = {
            name: json.loads((SOURCE_DIR / spec["filename"]).read_text(encoding="utf-8"))["rows"]
            for name, spec in IMPORTER.TABLES.items()
        }
        for rows in inventories.values():
            for row in rows:
                row["selector"] = {
                    "status": "unresolved",
                    "line_name": row["official_line_name"],
                    "operator": row["official_operator_name"],
                    "reason": "fresh import",
                }
        ledger = json.loads(
            (SOURCE_DIR / "reviewed-mlit-row-selectors.json").read_text(encoding="utf-8")
        )
        expected = {review["source_row_id"] for review in ledger["reviews"]}
        self.assertEqual(len(expected), len(ledger["reviews"]))

        IMPORTER.apply_selector_review_ledger(inventories, ledger)
        first = copy.deepcopy(inventories)
        IMPORTER.apply_selector_review_ledger(inventories, ledger)
        self.assertEqual(inventories, first)

        resolved = {
            row["source_row_id"]
            for rows in inventories.values()
            for row in rows
            if row["selector"]["status"] == "resolved"
        }
        self.assertEqual(resolved, expected)
        self.assertEqual(
            sum(row["selector"]["status"] == "unresolved"
                for rows in inventories.values() for row in rows),
            sum(len(rows) for rows in inventories.values()) - len(expected),
        )
        # A canonical-style link that is absent from the ledger stays unresolved.
        unlisted = next(
            row for rows in inventories.values() for row in rows
            if row["source_row_id"] not in expected
        )
        self.assertEqual(unlisted["selector"]["status"], "unresolved")

    def test_review_ledger_rejects_unverified_or_inexact_decisions(self):
        inventories = {
            name: json.loads((SOURCE_DIR / spec["filename"]).read_text(encoding="utf-8"))["rows"]
            for name, spec in IMPORTER.TABLES.items()
        }
        ledger = json.loads(
            (SOURCE_DIR / "reviewed-mlit-row-selectors.json").read_text(encoding="utf-8")
        )
        unverified = copy.deepcopy(ledger)
        unverified["reviews"][0]["review"]["status"] = "linked"
        with self.assertRaisesRegex(SystemExit, "is not verified"):
            IMPORTER.validate_selector_review_ledger(unverified, inventories)
        inexact = copy.deepcopy(ledger)
        inexact["reviews"][0]["evidence"][0]["date_precision"] = "year"
        with self.assertRaisesRegex(SystemExit, "primary exact-day evidence"):
            IMPORTER.validate_selector_review_ledger(inexact, inventories)

    def test_review_ledger_matches_verified_canonical_official_events_exactly(self):
        canonical = json.loads(
            (ROOT / "app/scripts/railway/jp-rail-history-events.json").read_text(encoding="utf-8")
        )
        verified = {}
        for bucket in ("events", "temporal_events"):
            for event in canonical.get(bucket, []):
                source_row_id = event.get("official_event_id")
                evidence = event.get("evidence")
                if (source_row_id and event.get("review", {}).get("status") == "verified"
                        and isinstance(evidence, list) and evidence
                        and all(item.get("authority") and item.get("reference")
                                and item.get("date_precision") == "exact_day"
                                for item in evidence)):
                    self.assertNotIn(source_row_id, verified)
                    verified[source_row_id] = event
        ledger = json.loads(
            (SOURCE_DIR / "reviewed-mlit-row-selectors.json").read_text(encoding="utf-8")
        )
        reviewed = {item["source_row_id"]: item for item in ledger["reviews"]}
        self.assertEqual(set(reviewed), set(verified))
        for source_row_id, decision in reviewed.items():
            event = verified[source_row_id]
            self.assertEqual(decision["event_id"], event["id"])
            self.assertEqual(decision["evidence"], event["evidence"])
            self.assertEqual(decision["selector"]["line_name"], event.get("after", event)["line"])
            self.assertEqual(decision["selector"]["operator"], event.get("after", event)["operator"])

    def test_check_rejects_resolved_selector_not_in_review_ledger(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            self.copy_checked_inventory(output)
            path = output / "mlit-openings.json"
            payload = json.loads(path.read_text(encoding="utf-8"))
            row = next(row for row in payload["rows"] if row["selector"]["status"] == "unresolved")
            row["selector"] = {
                "status": "resolved", "scope": "whole_identity",
                "line_name": row["official_line_name"],
                "operator": row["official_operator_name"],
            }
            payload["inventory"]["selector_status_counts"] = IMPORTER.selector_status_counts(payload["rows"])
            path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            with self.assertRaisesRegex(SystemExit, "resolved row set differs"):
                IMPORTER.validate_checked_in(output)

    def test_reviewed_seed_never_uses_an_unresolved_geometry_status(self):
        path = SOURCE_DIR / "reviewed-identity-events.json"
        IMPORTER.validate_reviewed_identity_ledger(path)
        payload = json.loads(path.read_text(encoding="utf-8"))
        sections = json.loads((ROOT / "app/data/rail-sections.json").read_text(encoding="utf-8"))["features"]
        stations = json.loads((ROOT / "app/data/stations.json").read_text(encoding="utf-8"))["features"]
        ready_statuses = {
            "ready_whole_identity", "ready_current_station",
            "ready_isolated_segment", "ready_historical_station",
        }
        for row in payload["rows"]:
            if row["review"]["status"] == "reviewed_seed":
                self.assertIn(row["geometry"]["status"], ready_statuses)
                if row["geometry"]["status"] not in {"ready_whole_identity", "ready_current_station"}:
                    continue
                selector = row["geometry"]["selector"]
                section_matches = [
                    feature for feature in sections
                    if feature["properties"]["N02_003"] == selector["line_name"]
                    and feature["properties"]["N02_004"] == selector["operator"]
                ]
                station_matches = [
                    feature for feature in stations
                    if feature["properties"]["line_name"] == selector["line_name"]
                    and feature["properties"]["operator"] == selector["operator"]
                    and (not selector.get("stations") or feature["properties"]["station_name"] in selector["stations"])
                ]
                self.assertTrue(section_matches, row["id"])
                self.assertTrue(station_matches, row["id"])
                if row["geometry"]["status"] == "ready_current_station":
                    self.assertEqual(len(station_matches), 1, row["id"])
            else:
                self.assertTrue(row["geometry"]["status"].startswith("unresolved_"))

    def test_promoted_isolated_seeds_equal_verified_canonical_selectors(self):
        payload = json.loads(
            (SOURCE_DIR / "reviewed-identity-events.json").read_text(encoding="utf-8")
        )
        seeds = {row["id"]: row for row in payload["rows"]}
        canonical_payload = json.loads(
            (ROOT / "app/scripts/railway/jp-rail-history-events.json").read_text(encoding="utf-8")
        )
        canonical = {
            event["id"]: event
            for bucket in ("events", "temporal_events")
            for event in canonical_payload.get(bucket, [])
        }
        promoted = {
            "jp-id-echigo-myoko-transfer-2015": "ready_whole_identity",
            "jp-id-ir-kurikara-kanazawa-transfer-2015": "ready_isolated_segment",
            "jp-id-hankai-uemachi-sumiyoshikoen-closure-2016": "ready_isolated_segment",
            "jp-id-kitahinode-closure-2021": "ready_historical_station",
            "jp-id-ir-kanazawa-daishoji-transfer-2024": "ready_isolated_segment",
        }
        for event_id, status in promoted.items():
            seed = seeds[event_id]
            event = canonical[event_id]
            self.assertEqual(seed["canonical_event_id"], event_id)
            self.assertEqual(seed["review"]["status"], "reviewed_seed")
            self.assertEqual(seed["geometry"]["status"], status)
            self.assertEqual(seed["basis"], event["review"]["basis"])
            self.assertEqual(event["review"]["status"], "verified")
            if event.get("official_event_id"):
                self.assertEqual(seed.get("official_event_id"), event["official_event_id"])
            seed_geometry = {key: value for key, value in seed["geometry"].items() if key != "status"}
            self.assertEqual(seed_geometry, event["geometry"])
            if "boundary_station_evidence" in event:
                self.assertEqual(seed["boundary_station_evidence"], event["boundary_station_evidence"])
            if "shared_predecessor_stations" in event:
                self.assertEqual(seed["shared_predecessor_stations"], event["shared_predecessor_stations"])

        for event_id in (
            "jp-id-aoimori-metoki-hachinohe-transfer-2002",
            "jp-id-aoimori-hachinohe-aomori-transfer-2010",
        ):
            self.assertEqual(seeds[event_id]["review"]["status"], "reviewed_source_only")
            self.assertEqual(seeds[event_id]["geometry"]["status"], "unresolved_segment_selector")

    def test_whole_identity_seeds_with_later_stations_or_alignments_remain_unresolved(self):
        payload = json.loads((SOURCE_DIR / "reviewed-identity-events.json").read_text())
        seeds = {row["id"]: row for row in payload["rows"]}
        for event_id in (
            "jp-id-shinano-transfer-1997", "jp-id-igr-transfer-2002",
            "jp-id-nishitetsu-line-rename-2001",
            "jp-id-nishitetsu-fukuoka-station-rename-2001",
        ):
            seed = seeds[event_id]
            self.assertEqual(seed["review"]["status"], "reviewed_source_only", event_id)
            self.assertEqual(seed["geometry"]["status"], "unresolved_historical_geometry", event_id)
            self.assertEqual(seed["geometry"]["selector"]["role"], "discovery_only_current_identity", event_id)

    def test_later_shinano_and_igr_station_openings_compile_unique_dated_memberships(self):
        ledger = json.loads((SOURCE_DIR / "reviewed-station-openings-shinano-igr.json").read_text())
        canonical = json.loads((ROOT / "app/scripts/railway/jp-rail-history-events.json").read_text())
        events = {event["id"]: event for event in canonical["temporal_events"]}
        sections = json.loads((ROOT / "app/data/rail-sections.json").read_text())["features"]
        stations = json.loads((ROOT / "app/data/stations.json").read_text())["features"]
        for event in ledger["events"]:
            self.assertEqual(event, events[event["id"]])
            compiled = TEMPORAL.compile_event(event, sections, stations)
            self.assertEqual(compiled["sections"], [])
            self.assertEqual(compiled["stations"], [])
            self.assertEqual(len(compiled["retirements"]), 1)
            stamp = compiled["retirements"][0]
            self.assertEqual(stamp["valid_from"], event["service_periods"][0][0])
            matches = TEMPORAL.select(stations, event["after"], stamp["match"]["bbox"])
            self.assertEqual(len(matches), 1)
            self.assertEqual(matches[0]["properties"]["n02_station_code"], event["current_n02_station_code"])

    def test_reviewed_openings_match_official_rows_and_compile(self):
        path = SOURCE_DIR / "reviewed-opening-events.json"
        official = json.loads((SOURCE_DIR / "mlit-openings.json").read_text(encoding="utf-8"))["rows"]
        IMPORTER.validate_reviewed_opening_ledger(path, official)
        payload = json.loads(path.read_text(encoding="utf-8"))
        sections = json.loads((ROOT / "app/data/rail-sections.json").read_text(encoding="utf-8"))["features"]
        stations = json.loads((ROOT / "app/data/stations.json").read_text(encoding="utf-8"))["features"]
        self.assertEqual(len(payload["events"]), 25)
        retirements = []
        for event in payload["events"]:
            compiled = TEMPORAL.compile_event(event, sections, stations)
            retirements.extend(compiled["retirements"])
            self.assertEqual(
                {item["match"]["targets"][0] for item in compiled["retirements"]},
                {"sections", "stations"},
                event["id"],
            )
        self.assertEqual(len(TEMPORAL.normalize_stamps(retirements, sections, stations)), 50)

    def test_reviewed_station_renames_match_current_geometry_and_compile(self):
        path = SOURCE_DIR / "reviewed-station-events.json"
        IMPORTER.validate_reviewed_station_ledger(path)
        payload = json.loads(path.read_text(encoding="utf-8"))
        sections = json.loads((ROOT / "app/data/rail-sections.json").read_text(encoding="utf-8"))["features"]
        stations = json.loads((ROOT / "app/data/stations.json").read_text(encoding="utf-8"))["features"]
        self.assertEqual(len(payload["events"]), 6)
        self.assertEqual(len({event["station_entity_id"] for event in payload["events"]}), 6)
        self.assertEqual(len({event["membership_id"] for event in payload["events"]}), 6)

        retirements = []
        for event in payload["events"]:
            after = event["after"]
            matches = [
                feature for feature in stations
                if feature["properties"]["line_name"] == after["line"]
                and feature["properties"]["operator"] == after["operator"]
                and feature["properties"]["station_name"] == after["station"]
            ]
            self.assertEqual(len(matches), 1, event["id"])
            self.assertEqual(
                matches[0]["properties"]["n02_station_code"],
                event["current_n02_station_code"],
                event["id"],
            )
            historical = event["geometry"]["historical_stations"]
            self.assertEqual(historical[0]["geometry"], matches[0]["geometry"], event["id"])

            compiled = TEMPORAL.compile_event(event, sections, stations)
            self.assertEqual(compiled["sections"], [], event["id"])
            self.assertEqual(len(compiled["stations"]), 1, event["id"])
            self.assertEqual(
                compiled["stations"][0]["properties"]["station_name"],
                event["before"]["station"],
                event["id"],
            )
            self.assertEqual(
                compiled["stations"][0]["properties"]["service_validity"],
                [None, "2020-03-14"],
                event["id"],
            )
            self.assertEqual(len(compiled["retirements"]), 1, event["id"])
            self.assertEqual(compiled["retirements"][0]["match"]["targets"], ["stations"])
            retirements.extend(compiled["retirements"])
        self.assertEqual(len(TEMPORAL.normalize_stamps(retirements, sections, stations)), 6)


if __name__ == "__main__":
    unittest.main()
