import importlib.util
import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUDIT_PATH = ROOT / "app/scripts/railway/history/audit-jp-history-coverage.py"
BOUNDARY_PATH = ROOT / "app/scripts/railway/history/verify-jp-history-boundaries.mjs"

SPEC = importlib.util.spec_from_file_location("jp_history_coverage", AUDIT_PATH)
audit_module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = audit_module
assert SPEC.loader is not None
SPEC.loader.exec_module(audit_module)


def feature(history_id, line="Line", operator="Operator", valid_to="2020-01-02"):
    return {
        "type": "Feature",
        "properties": {
            "history_id": history_id,
            "N02_003": line,
            "N02_004": operator,
            "valid_to": valid_to,
        },
        "geometry": {"type": "LineString", "coordinates": [[0, 0], [1, 1]]},
    }


def canonical_event(event_id="jp.test.line"):
    return {
        "id": event_id,
        "line": "Line",
        "operator": "Operator",
        "year": "19",
        "valid_to": "2020-01-02",
        "source": "official fixture",
    }


def reviewed_source_event(event):
    event.update(
        {
            "date_precision": "exact_day",
            "review": {"status": "verified"},
            "corridor_id": "jp.corridor.fixture",
            "alignment_id": "jp.alignment.fixture",
            "service_identity_id": "jp.service.fixture",
            "evidence": [
                {
                    "authority": "official fixture",
                    "reference": "https://example.test/history",
                    "date_precision": "exact_day",
                }
            ],
            "geometry": {"source": "N02", "licence_status": "redistributable"},
        }
    )
    return event


class CoverageAuditTests(unittest.TestCase):
    def test_explicit_opening_constraint_explains_predecessor_boundary(self):
        rename = reviewed_source_event({
            'id': 'rename', 'kind': 'operator_rename', 'date': '2020-01-02',
            'before': {'line': 'Line', 'operator': 'Old'},
            'after': {'line': 'Line', 'operator': 'Operator'},
        })
        opening = reviewed_source_event({
            'id': 'opening', 'kind': 'opening', 'line': 'Line', 'operator': 'Old',
            'after': {'line': 'Line', 'operator': 'Operator'},
            'service_periods': [['2010-01-01', None]], 'predecessor_event_ids': ['rename'],
        })
        old = feature('rename.sections', operator='Old')
        old['properties']['valid_from'] = '2010-01-01'
        history = {'sections': [old], 'stations': [], 'retirements': [
            {'history_id': 'rename.current.sections', 'valid_from': '2020-01-02',
             'match': {'line_name': 'Line', 'operator': 'Operator'}},
            {'history_id': 'opening.current.sections', 'valid_from': '2010-01-01',
             'match': {'line_name': 'Line', 'operator': 'Operator'}},
        ]}
        events = {'events': [], 'temporal_events': [rename, opening]}
        self.assertEqual(audit_module.audit(events, history)['counts']['errors'], 0)
        opening.pop('predecessor_event_ids')
        report = audit_module.audit(events, history)
        self.assertTrue(any(item['code'] == 'BOUNDARY_MISMATCH' for item in report['findings']))

    def test_identity_predecessor_survey_boundaries_are_official_boundaries(self):
        event = {
            "kind": "operator_transfer", "date": "2015-03-14",
            "geometry": {"historical_periods": [
                {"service_period": [None, "2014-10-19"]},
                {"service_period": ["2014-10-19", "2015-03-14"]},
            ]},
        }
        findings = []
        self.assertEqual(audit_module.canonical_periods(event, findings, "myoko"), [
            (None, "2014-10-19"), ("2014-10-19", "2015-03-14"),
            ("2015-03-14", None),
        ])
        self.assertEqual(findings, [])

    def test_real_compiled_history_accounts_for_every_canonical_event(self):
        events = json.loads((ROOT / "app/scripts/railway/jp-rail-history-events.json").read_text())
        history = json.loads((ROOT / "app/data/rail-history.json").read_text())

        report = audit_module.audit(events, history)

        self.assertEqual(report["counts"]["errors"], 0)
        self.assertEqual(report["counts"]["matched_nothing"], 0)
        self.assertEqual(report["counts"]["unknown"], 0)
        self.assertEqual(report["counts"]["unresolved"], len(events["not_in_n02"]))
        self.assertTrue(report["claims"]["route_solver_regression"].startswith("NOT_EVALUATED"))

    def test_event_that_emits_nothing_is_a_real_coverage_error(self):
        report = audit_module.audit(
            {"events": [canonical_event()], "retirements": [], "not_in_n02": []},
            {"sections": [], "stations": [], "retirements": []},
        )
        codes = [finding["code"] for finding in report["findings"]]
        self.assertIn("MATCHED_NOTHING", codes)
        self.assertEqual(report["counts"]["matched_nothing"], 1)

    def test_service_validity_takes_precedence_over_legacy_bounds(self):
        event = canonical_event()
        event.update(
            {
                "valid_from": "1999-01-01",
                "valid_to": "1999-01-02",
                "service_validity": ["2010-01-01", "2020-01-02"],
            }
        )
        section = feature(event["id"], valid_to=None)
        section["properties"].pop("valid_to")
        section["properties"].update(
            {
                "valid_from": "1999-01-01",
                "valid_to": "1999-01-02",
                "service_validity": ["2010-01-01", "2020-01-02"],
            }
        )
        report = audit_module.audit(
            {"events": [event], "retirements": [], "not_in_n02": []},
            {"sections": [section], "stations": [], "retirements": []},
        )
        self.assertEqual(report["counts"]["errors"], 0)

    def test_service_periods_replace_legal_retirement_date_and_accept_suffixes(self):
        event = reviewed_source_event(canonical_event())
        event.update(
            {
                "valid_to": "2023-01-01",
                "service_periods": [[None, "2010-01-01"], ["2011-01-01", "2020-01-02"]],
            }
        )
        first = feature(event["id"], valid_to="2010-01-01")
        second = feature(event["id"] + ".period1", valid_to="2020-01-02")
        second["properties"]["valid_from"] = "2011-01-01"
        report = audit_module.audit(
            {"events": [event], "retirements": [], "not_in_n02": []},
            {"sections": [first, second], "stations": [], "retirements": []},
        )
        self.assertEqual(report["counts"]["errors"], 0)
        self.assertEqual(
            report["events"][0]["source_service_periods"],
            [[None, "2010-01-01"], ["2011-01-01", "2020-01-02"]],
        )

    def test_temporal_event_can_compile_only_to_a_current_stamp(self):
        event = reviewed_source_event({
            "id": "jp.opening.fixture",
            "kind": "opening",
            "line": "Line",
            "operator": "Operator",
            "service_periods": [["2020-01-02", None]],
        })
        retirement = {
            "history_id": event["id"] + ".current.sections",
            "match": {
                "line_name": "Line",
                "operator": "Operator",
                "bbox": [0, 0, 1, 1],
                "targets": ["sections"],
            },
            "valid_from": "2020-01-02",
        }
        report = audit_module.audit(
            {"events": [], "temporal_events": [event], "retirements": [], "not_in_n02": []},
            {"sections": [], "stations": [], "retirements": [retirement]},
        )
        self.assertEqual(report["counts"]["errors"], 0)
        self.assertEqual(report["events"][0]["generated"]["retirements"], 1)

    def test_partition_periods_are_checked_per_compiled_half(self):
        event = reviewed_source_event(canonical_event("jp.partition.fixture"))
        event["service_periods"] = [[None, "2015-01-08"]]
        event["service_partition"] = {
            "longitude": 0.5,
            "lower_periods": [[None, "2015-01-08"]],
            "upper_periods": [[None, "2015-01-08"], ["2015-01-27", "2015-03-01"]],
        }
        lower = feature(event["id"], valid_to="2015-01-08")
        upper_first = feature(event["id"], valid_to="2015-01-08")
        upper_second = feature(event["id"], valid_to="2015-03-01")
        lower['properties']['service_partition_side'] = 'lower'
        upper_first['properties']['service_partition_side'] = 'upper'
        upper_second['properties']['service_partition_side'] = 'upper'
        upper_second["properties"]["valid_from"] = "2015-01-27"
        report = audit_module.audit(
            {"events": [event], "retirements": [], "not_in_n02": []},
            {
                "sections": [lower, upper_first, upper_second],
                "stations": [],
                "retirements": [],
            },
        )
        self.assertEqual(report["counts"]["errors"], 0)
        self.assertEqual(
            report["events"][0]["service_partition"]["upper"]["source_periods"],
            [[None, "2015-01-08"], ["2015-01-27", "2015-03-01"]],
        )

    def test_suspended_old_alignment_and_later_replacement_have_separate_boundaries(self):
        event = reviewed_source_event(canonical_event('jp.fixture.old-alignment'))
        event.update(kind='relocation', valid_to='2015-05-30',
                     service_periods=[[None, '2011-03-12']])
        retirement = {'history_id': 'jp.fixture.new-alignment',
            'valid_from': '2015-05-30', 'match': {'line_name': 'Line',
                'operator': 'Operator', 'bbox': [0, 0, 1, 1]}}
        report = audit_module.audit({'events': [event], 'retirements': [], 'not_in_n02': []},
            {'sections': [feature(event['id'], valid_to='2011-03-12')],
             'stations': [], 'retirements': [retirement]})
        self.assertEqual(report['counts']['errors'], 0)

    def test_unreviewed_rich_source_event_fails_closed(self):
        event = reviewed_source_event(canonical_event("jp.unreviewed.fixture"))
        event.update(kind="opening", service_periods=[["2020-01-02", None]])
        event["review"] = {"status": "candidate"}
        retirement = {
            "history_id": event["id"] + ".current.sections",
            "match": {
                "line_name": "Line",
                "operator": "Operator",
                "bbox": [0, 0, 1, 1],
                "targets": ["sections"],
            },
            "valid_from": "2020-01-02",
        }
        report = audit_module.audit(
            {"events": [], "temporal_events": [event], "retirements": [], "not_in_n02": []},
            {"sections": [], "stations": [], "retirements": [retirement]},
        )
        self.assertIn("INVALID_SOURCE_EVENT", [item["code"] for item in report["findings"]])
        self.assertGreater(report["counts"]["errors"], 0)

    def test_planned_official_inventory_schema_reports_unresolved_rows(self):
        event = canonical_event()
        event["official_event_id"] = "fixture:1"
        report = audit_module.audit(
            {"events": [event], "retirements": [], "not_in_n02": []},
            {"sections": [feature(event["id"])], "stations": [], "retirements": []},
            [
                {
                    "source_row_id": "fixture:1",
                    "official_line_name": "Line",
                    "official_operator_name": "Operator",
                    "effective_date": "2020-01-02",
                    "kind": "closure",
                    "selector": {
                        "status": "unresolved",
                        "line_name": "Line",
                        "operator": "Operator",
                        "reason": "awaiting review",
                    },
                }
            ],
        )
        self.assertEqual(report["official_inventory"]["matched"], 1)
        self.assertEqual(report["official_inventory"]["unresolved"], 1)
        self.assertEqual(report["counts"]["unresolved"], 1)

    def test_reviewed_inventory_id_links_to_compiled_canonical_event(self):
        event = canonical_event("jp.reviewed.fixture")
        report = audit_module.audit(
            {"events": [event], "retirements": [], "not_in_n02": []},
            {"sections": [feature(event["id"])], "stations": [], "retirements": []},
            [
                {
                    "id": event["id"],
                    "kind": "closure",
                    "effective_date": "2020-01-02",
                    "after": {"line": "Line", "operator": "Operator"},
                    "review": {"status": "reviewed_seed"},
                    "geometry": {
                        "status": "ready_whole_identity",
                        "selector": {
                            "scope": "whole_identity",
                            "line_name": "Line",
                            "operator": "Operator",
                        },
                    },
                }
            ],
        )
        self.assertEqual(report["official_inventory"]["matched"], 1)
        self.assertEqual(report["official_inventory"]["explicitly_linked"], 1)
        self.assertEqual(report["counts"]["unknown"], 0)

    def test_inventory_directory_deduplicates_promoted_official_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            (directory / "mlit-openings.json").write_text(
                json.dumps({"rows": [{"source_row_id": "mlit:1"}]}), encoding="utf-8"
            )
            (directory / "reviewed-openings.json").write_text(
                json.dumps(
                    {
                        "events": [
                            {"id": "jp.opening.fixture", "official_event_id": "mlit:1"},
                            {"id": "jp.opening.unique", "official_event_id": "mlit:2"},
                        ]
                    }
                ),
                encoding="utf-8",
            )
            rows = audit_module._official_rows(directory)
        self.assertEqual(rows, [{"source_row_id": "mlit:1"}])

    def test_explicit_official_link_allows_legal_date_after_service_cutoff(self):
        event = reviewed_source_event(canonical_event("jp.service-cutoff.fixture"))
        event.update(
            kind="closure",
            official_event_id="mlit-closure:1",
            service_periods=[[None, "2015-01-08"]],
        )
        report = audit_module.audit(
            {"events": [event], "retirements": [], "not_in_n02": []},
            {"sections": [feature(event["id"], valid_to="2015-01-08")], "stations": [], "retirements": []},
            [
                {
                    "source_row_id": "mlit-closure:1",
                    "kind": "closure",
                    "effective_date": "2021-04-01",
                    "selector": {"status": "unresolved"},
                }
            ],
        )
        self.assertEqual(report["official_inventory"]["matched"], 1)
        self.assertEqual(report["official_inventory"]["matched_nothing"], 0)

    def test_baseline_gate_accepts_only_the_configured_legacy_gap_count(self):
        events = {
            "events": [canonical_event()],
            "retirements": [],
            "not_in_n02": ["known gap", "new gap"],
        }
        history = {"sections": [feature("jp.test.line")], "stations": [], "retirements": []}
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            events_path = directory / "events.json"
            history_path = directory / "history.json"
            events_path.write_text(json.dumps(events), encoding="utf-8")
            history_path.write_text(json.dumps(history), encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()):
                result = audit_module.main(
                    [
                        "--events",
                        str(events_path),
                        "--history",
                        str(history_path),
                        "--baseline-max-unresolved",
                        "1",
                    ]
                )
        self.assertEqual(result, 1)

    def test_strict_gate_rejects_any_declared_unresolved_gap(self):
        events = {
            "events": [canonical_event()],
            "retirements": [],
            "not_in_n02": ["known but unresolved"],
        }
        history = {"sections": [feature("jp.test.line")], "stations": [], "retirements": []}
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            events_path = directory / "events.json"
            history_path = directory / "history.json"
            events_path.write_text(json.dumps(events), encoding="utf-8")
            history_path.write_text(json.dumps(history), encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()):
                result = audit_module.main(
                    [
                        "--events",
                        str(events_path),
                        "--history",
                        str(history_path),
                        "--strict",
                    ]
                )
        self.assertEqual(result, 1)

    def test_production_loader_checks_every_real_boundary(self):
        with tempfile.TemporaryDirectory() as directory:
            fixtures_path = Path(directory) / "fixtures.json"
            report_path = Path(directory) / "report.json"
            completed = subprocess.run(
                [
                    "node",
                    str(BOUNDARY_PATH),
                    "--fixtures",
                    str(fixtures_path),
                    "--json-report",
                    str(report_path),
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            fixtures = json.loads(fixtures_path.read_text())["fixtures"]
            report = json.loads(report_path.read_text())
        self.assertGreater(len(fixtures), 0)
        self.assertTrue(
            all(
                [check["label"] for check in fixture["checks"]]
                == ["day_before", "day_of"]
                for fixture in fixtures
            )
        )
        self.assertTrue(
            all(
                check["actual_available"] == check["expected_available"]
                for fixture in fixtures
                for check in fixture["checks"]
            )
        )
        self.assertEqual(report["claims"]["route_solver_regression"], "INCOMPLETE")
        self.assertIn("actual transitions", completed.stdout)
        self.assertIn("route solving and final display were not exercised", completed.stdout)


if __name__ == "__main__":
    unittest.main()
