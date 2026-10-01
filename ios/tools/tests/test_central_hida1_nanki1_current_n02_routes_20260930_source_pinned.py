"""Pinned checks for the Hida 1 and Nanki 1 current-N02 route batch."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
MODULE_PATH = ROOT / "ios/tools/normalize-reviewed-central-hida1-nanki1-current-n02-routes-20260930.py"
SPEC = importlib.util.spec_from_file_location("central_hida_nanki_route_normalizer", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


class CentralHidaNankiCurrentN02RouteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.candidate = json.loads(MODULE.CANDIDATE.read_text(encoding="utf-8"))
        cls.lines = read_jsonl(BASE / MODULE.LINE_OUTPUT)
        cls.facts = read_jsonl(BASE / MODULE.FACT_OUTPUT)

    def test_exact_scope_and_route_only_kawarada(self) -> None:
        self.assertEqual(len(self.lines), 24)
        by_trip = {
            trip_id: [row for row in self.lines if row["trip_id"] == trip_id]
            for trip_id in MODULE.TARGET_TRIPS
        }
        hida = by_trip["jr-central.hida.1.2026-09-30"]
        nanki = by_trip["jr-central.nanki.1.2026-09-30"]
        self.assertEqual([row["sequence"] for row in hida], list(range(1, 12)))
        self.assertEqual([row["sequence"] for row in nanki], list(range(1, 14)))
        self.assertEqual(
            [row["current_n02_line_id"] for row in hida],
            ["jp-東海旅客鉄道-東海道線"] * 2 + ["jp-東海旅客鉄道-高山線"] * 9,
        )
        self.assertEqual(
            [row["current_n02_line_id"] for row in nanki],
            ["jp-東海旅客鉄道-関西線"] * 3
            + ["jp-伊勢鉄道-伊勢線"] * 2
            + ["jp-東海旅客鉄道-紀勢線"] * 7
            + ["jp-西日本旅客鉄道-紀勢線"],
        )
        self.assertEqual(nanki[2]["to_station_id"], "jp.n02.006285")
        self.assertEqual(nanki[3]["from_station_id"], "jp.n02.006285")
        self.assertEqual(
            read_jsonl(BASE / MODULE.STATION_OUTPUT),
            [{
                "current_source_code": "006285",
                "name_snapshot": "河原田",
                "reference_kind": "current_n02",
                "station_id": "jp.n02.006285",
            }],
        )
        self.assertFalse(any(
            row["station_id"] == "jp.n02.006285"
            for row in MODULE.rows_from(BASE, "normalized/stop-times/**/*.jsonl")
        ))

    def test_sources_are_partial_and_exclude_unrelated_osaka_trips(self) -> None:
        self.assertEqual({row["trip_id"] for row in self.lines}, MODULE.TARGET_TRIPS)
        self.assertTrue(all(row["reference_kind"] == "current_n02" for row in self.lines))
        self.assertTrue(all("rail_history_id" not in row for row in self.lines))
        self.assertTrue(all(row["verification_status"] == "partial" for row in self.facts))
        source_urls = {row["url_or_locator"] for row in read_jsonl(BASE / MODULE.SOURCE_OUTPUT)}
        self.assertIn(
            "https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html",
            source_urls,
        )
        self.assertIn("https://isetetu.co.jp/station/", source_urls)
        self.assertEqual(read_jsonl(BASE / MODULE.OPERATOR_OUTPUT)[0]["operator_id"], "ise-railway")

    def test_route_state_is_partial_research_open_and_repeatable(self) -> None:
        observed_paths = [
            BASE / MODULE.SOURCE_OUTPUT,
            BASE / MODULE.OPERATOR_OUTPUT,
            BASE / MODULE.STATION_OUTPUT,
            BASE / MODULE.LINE_OUTPUT,
            BASE / MODULE.FACT_OUTPUT,
        ]
        for trip_id, (completeness_rel, queue_rel) in MODULE.STATUS_PATHS.items():
            completeness_path = BASE / completeness_rel
            queue_path = BASE / queue_rel
            observed_paths.extend((completeness_path, queue_path))
            route_row, = [
                row for row in read_jsonl(completeness_path)
                if row.get("entity_id") == trip_id and row.get("dimension") == "route_lines"
            ]
            research_row, = [
                row for row in read_jsonl(queue_path)
                if row.get("entity_id") == trip_id and row.get("missing_dimension") == "route_lines"
            ]
            self.assertEqual(route_row["status"], "partial")
            self.assertIn("no physical-line validity interval", route_row["notes"])
            self.assertEqual(research_row["status"], "open")
            self.assertIn("2026-09-30", research_row["notes"])
        before = {path: path.read_bytes() for path in observed_paths}
        self.assertEqual(
            MODULE.normalize(BASE, MODULE.CANDIDATE, MODULE.RAIL_PACKAGE),
            {"trips": 2, "segments": 24, "route_only_stations": 1},
        )
        self.assertEqual(before, {path: path.read_bytes() for path in observed_paths})

    def test_changed_passenger_path_is_rejected_before_writing(self) -> None:
        altered = json.loads(json.dumps(self.candidate))
        altered["trips"][1]["expected_passenger_path"][3] = "jp.n02.006285"
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "altered-candidate.json"
            path.write_text(json.dumps(altered, ensure_ascii=False), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "passenger-call chain drift"):
                MODULE.normalize(BASE, path, MODULE.RAIL_PACKAGE)


if __name__ == "__main__":
    unittest.main()
