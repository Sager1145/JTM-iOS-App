"""Source-pinned checks for the 12-trip priority current-N02 route batch."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = (
    BASE
    / "sources/candidates/reviewed-priority-current-n02-route-identities-20260930.json"
)
NORMALIZER = (
    ROOT / "ios/tools/normalize-reviewed-priority-current-n02-route-identities-20260930.py"
)
RAIL_PACKAGE = ROOT / "app/public/rail/jp-2025.json"
TOOLS = ROOT / "ios/tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import train_timetable


def read_jsonl(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def load_normalizer():
    spec = importlib.util.spec_from_file_location("priority_route_normalizer", NORMALIZER)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class PriorityCurrentN02RouteIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_normalizer()
        cls.candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        cls.temp = tempfile.TemporaryDirectory()
        cls.canonical = Path(cls.temp.name) / "train-service-history"
        shutil.copytree(BASE, cls.canonical)
        cls.counts = cls.module.normalize(cls.canonical, CANDIDATE, RAIL_PACKAGE)
        cls.line_path = cls.canonical / cls.module.LINE_OUTPUT
        cls.fact_path = cls.canonical / cls.module.FACT_OUTPUT
        cls.source_path = cls.canonical / cls.module.SOURCE_OUTPUT
        cls.lines = read_jsonl(cls.line_path)
        cls.facts = read_jsonl(cls.fact_path)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_scope_is_exactly_12_trips_and_116_passenger_legs(self):
        self.assertEqual(
            self.counts,
            {
                "trips": 12,
                "segments": 116,
                "line_identities": 14,
                "fact_sources": 375,
                "partial_routes": 12,
            },
        )
        self.assertEqual(len(self.lines), 116)
        self.assertEqual(len({row["trip_id"] for row in self.lines}), 12)

    def test_route_rows_are_current_only_and_match_exact_stop_chains(self):
        self.assertTrue(all(row["reference_kind"] == "current_n02" for row in self.lines))
        self.assertTrue(all(row["confidence"] == "high" for row in self.lines))
        self.assertTrue(all(row.get("current_n02_line_id") for row in self.lines))
        self.assertTrue(all("rail_history_id" not in row for row in self.lines))

        targets = {row["trip_id"] for row in self.lines}
        stop_rows = []
        for path in (self.canonical / "normalized/stop-times").rglob("*.jsonl"):
            stop_rows.extend(row for row in read_jsonl(path) if row["trip_id"] in targets)
        for trip_id in targets:
            stops = sorted(
                (row for row in stop_rows if row["trip_id"] == trip_id),
                key=lambda row: row["stop_sequence"],
            )
            route = sorted(
                (row for row in self.lines if row["trip_id"] == trip_id),
                key=lambda row: row["sequence"],
            )
            self.assertEqual(
                [(row["from_station_id"], row["to_station_id"]) for row in route],
                [
                    (left["station_id"], right["station_id"])
                    for left, right in zip(stops, stops[1:])
                ],
            )

    def test_line_boundaries_and_operators_are_exact(self):
        expected = {
            "jr-hokkaido.kamui.7.exact-2026-09-30": [(1, 6, "jp-北海道旅客鉄道-函館線", "jr-hokkaido")],
            "jr-hokkaido.kamui.4.exact-2026-09-30": [(1, 6, "jp-北海道旅客鉄道-函館線", "jr-hokkaido")],
            "jr-hokkaido.soya.51d.exact-2026-09-30": [(1, 6, "jp-北海道旅客鉄道-函館線", "jr-hokkaido"), (7, 16, "jp-北海道旅客鉄道-宗谷線", "jr-hokkaido")],
            "jr-hokkaido.soya.52d.exact-2026-09-30": [(1, 10, "jp-北海道旅客鉄道-宗谷線", "jr-hokkaido"), (11, 14, "jp-北海道旅客鉄道-函館線", "jr-hokkaido")],
            "jr-central.shinano.10.2026-09-30": [(1, 1, "jp-東日本旅客鉄道-信越線-3", "jr-east"), (2, 3, "jp-東日本旅客鉄道-篠ノ井線", "jr-east"), (4, 9, "jp-東海旅客鉄道-中央線", "jr-central")],
            "jr-kyushu.kaio.2.2026-09-30": [(1, 1, "jp-九州旅客鉄道-鹿児島線", "jr-kyushu"), (2, 2, "jp-九州旅客鉄道-篠栗線", "jr-kyushu"), (3, 5, "jp-九州旅客鉄道-筑豊線", "jr-kyushu")],
            "jr-kyushu.kirameki.2.2026-09-30": [(1, 9, "jp-九州旅客鉄道-鹿児島線", "jr-kyushu")],
            "jr-kyushu.midori.7.2026-09-30": [(1, 2, "jp-九州旅客鉄道-鹿児島線", "jr-kyushu"), (3, 5, "jp-九州旅客鉄道-長崎線", "jr-kyushu"), (6, 9, "jp-九州旅客鉄道-佐世保線", "jr-kyushu")],
            "jr-kyushu.relay-kamome.1.2026-09-30": [(1, 2, "jp-九州旅客鉄道-鹿児島線", "jr-kyushu"), (3, 5, "jp-九州旅客鉄道-長崎線", "jr-kyushu"), (6, 6, "jp-九州旅客鉄道-佐世保線", "jr-kyushu")],
            "jr-kyushu.sonic.1.2026-09-30": [(1, 6, "jp-九州旅客鉄道-鹿児島線", "jr-kyushu"), (7, 15, "jp-九州旅客鉄道-日豊線", "jr-kyushu")],
            "jr-shikoku.shimanto.2.2026-09-30": [(1, 8, "jp-四国旅客鉄道-土讃線", "jr-shikoku"), (9, 11, "jp-四国旅客鉄道-予讃線", "jr-shikoku")],
            "jr-shikoku.uzushio.1.2026-09-30": [(1, 10, "jp-四国旅客鉄道-高徳線", "jr-shikoku")],
        }
        for trip_id, ranges in expected.items():
            rows = {row["sequence"]: row for row in self.lines if row["trip_id"] == trip_id}
            for start, end, line_id, operator_id in ranges:
                for sequence in range(start, end + 1):
                    self.assertEqual(rows[sequence]["current_n02_line_id"], line_id)
                    self.assertEqual(rows[sequence]["operator_id"], operator_id)

    def test_each_group_is_monotonic_in_exact_pinned_n02_station_order(self):
        package = json.loads(RAIL_PACKAGE.read_text(encoding="utf-8"))
        self.assertEqual(package["version"], "2025.5.0")
        package_lines = {row["id"]: row for row in package["lines"]}
        station_codes = {}
        for path in self.canonical.glob("normalized/station-identities*.jsonl"):
            for row in read_jsonl(path):
                if row.get("reference_kind") == "current_n02":
                    station_codes[row["station_id"]] = row["current_source_code"]
        for group in self.candidate["segment_groups"]:
            order = [
                station[0]
                for station in package_lines[group["current_n02_line_id"]]["stations"]
            ]
            positions = [order.index(station_codes[station_id]) for station_id in group["station_path"]]
            self.assertTrue(
                all(left < right for left, right in zip(positions, positions[1:]))
                or all(left > right for left, right in zip(positions, positions[1:])),
                (group["trip_id"], group["current_n02_line_id"], positions),
            )

    def test_sources_have_distinct_roles_and_no_train_page_overclaims_line_identity(self):
        sources = {row["source_id"]: row for row in read_jsonl(self.source_path)}
        self.assertEqual(len(sources), 6)
        self.assertEqual(
            sources["mlit-n02-2025-priority-route-batch-a"]["url_or_locator"],
            "https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html",
        )
        self.assertEqual(
            sources["jr-kyushu-line-inventory-priority-route-batch-a"]["effective_date"],
            "2025-03-15",
        )
        roles = self.candidate["evidence_source_roles"]
        train_roles = [value for value in roles.values() if value["role"] == "exact-date train timetable"]
        self.assertEqual(len(train_roles), 12)
        self.assertTrue(all("does not publish" in value["locator"] for value in train_roles))
        self.assertTrue(all("daily line validity" in value["locator"] for value in train_roles))

        self.assertEqual(len(self.facts), 375)
        self.assertTrue(all(row["verification_status"] == "partial" for row in self.facts))
        self.assertTrue(all("Evidence role:" in row["page_or_locator"] for row in self.facts))
        self.assertTrue(all("daily temporal coverage remains unverified" in row["page_or_locator"] for row in self.facts))

    def test_completeness_is_partial_and_queue_stays_open(self):
        targets = {row["trip_id"] for row in self.lines}
        completeness = {}
        for path in self.canonical.glob("normalized/fact-completeness*.jsonl"):
            for row in read_jsonl(path):
                if row.get("entity_id") in targets and row.get("dimension") == "route_lines":
                    completeness[row["entity_id"]] = row
        queue = {}
        for path in self.canonical.glob("normalized/research-queue*.jsonl"):
            for row in read_jsonl(path):
                if row.get("entity_id") in targets and row.get("missing_dimension") == "route_lines":
                    queue[row["entity_id"]] = row
        self.assertEqual(set(completeness), targets)
        self.assertEqual(set(queue), targets)
        self.assertTrue(all(row["status"] == "partial" for row in completeness.values()))
        self.assertTrue(all("daily line validity is unverified" in row["notes"] for row in completeness.values()))
        self.assertTrue(all(row["status"] == "open" for row in queue.values()))
        self.assertTrue(all("no solver result" in row["notes"] for row in queue.values()))

    def test_normalizer_is_rerunnable_without_output_drift(self):
        before = {
            path: path.read_bytes()
            for path in (self.line_path, self.fact_path, self.source_path)
        }
        second_counts = self.module.normalize(self.canonical, CANDIDATE, RAIL_PACKAGE)
        self.assertEqual(second_counts, self.counts)
        self.assertEqual(before, {path: path.read_bytes() for path in before})

    def test_full_dataset_validation_accepts_partial_current_identities(self):
        manifest = train_timetable.load_manifest(self.canonical)
        data, origins = train_timetable.load_dataset(self.canonical, manifest)
        self.assertEqual(
            train_timetable.validate_dataset(data, origins, manifest),
            [],
        )


if __name__ == "__main__":
    unittest.main()
