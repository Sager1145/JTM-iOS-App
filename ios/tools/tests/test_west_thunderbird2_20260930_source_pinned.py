"""Source-pinned assertions for the dated Thunderbird 2 candidate."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SCRIPT = ROOT / "ios/tools/normalize-reviewed-west-thunderbird2-20260930.py"
SPEC = importlib.util.spec_from_file_location("west_thunderbird2", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


class WestThunderbird2SourcePinnedTests(unittest.TestCase):
    def test_exact_calls_and_current_n02_order(self) -> None:
        candidate = json.loads((BASE / "candidates/jr-west-thunderbird2-20260930.json").read_text(encoding="utf-8"))
        calls = candidate["trip"]["stop_times"]
        self.assertEqual(len(calls), 6)
        self.assertEqual((calls[0]["departure_time"], calls[-1]["arrival_time"]), ("07:05", "08:34"))
        self.assertEqual([row["name_snapshot"] for row in calls], [row[0] for row in MODULE.EXPECTED])
        segments = read_jsonl(BASE / f"normalized/trip-lines/{MODULE.SUFFIX}/seeds.jsonl")
        self.assertEqual(len(segments), 7)
        self.assertEqual([row["sequence"] for row in segments], list(range(1, 8)))
        self.assertEqual([row["current_n02_line_id"] for row in segments],
                         MODULE.ROUTE_LINE_IDS)
        self.assertTrue(all(row["reference_kind"] == "current_n02" for row in segments))
        self.assertEqual(
            [segments[0]["from_station_id"]] + [row["to_station_id"] for row in segments],
            ["jp.n02." + code for _, code in MODULE.ROUTE_NODES],
        )
        self.assertEqual([row["name_snapshot"] for row in calls],
                         ["敦賀", "近江今津", "堅田", "京都", "新大阪", "大阪"])

    def test_date_is_single_day_route_partial_and_repeatable(self) -> None:
        state = {
            row["dimension"]: row
            for row in read_jsonl(BASE / f"normalized/fact-completeness-{MODULE.SUFFIX}.jsonl")
        }
        self.assertEqual(state["route_lines"]["status"], "partial")
        queue = {
            row["missing_dimension"]: row
            for row in read_jsonl(BASE / f"normalized/research-queue-{MODULE.SUFFIX}.jsonl")
        }
        self.assertEqual(queue["route_lines"]["status"], "open")
        calendar, = read_jsonl(BASE / f"normalized/calendars/{MODULE.SUFFIX}/seeds.jsonl")
        exception, = read_jsonl(BASE / f"normalized/calendar-exceptions/{MODULE.SUFFIX}/seeds.jsonl")
        self.assertEqual((calendar["valid_from"], calendar["valid_until"]), (MODULE.DATE, MODULE.UNTIL))
        self.assertTrue(all(calendar[weekday] == 0 for weekday in MODULE.WEEKDAYS))
        self.assertEqual(exception["service_date"], MODULE.DATE)
        first = MODULE.prepare()
        second = MODULE.prepare()
        self.assertEqual(first, second)

    def test_source_roles_and_tampered_stop_are_rejected(self) -> None:
        sources = {
            row["source_id"]: row
            for row in read_jsonl(BASE / f"sources/source-registry-{MODULE.SUFFIX}.jsonl")
        }
        self.assertEqual(sources[MODULE.TRAIN_SOURCE]["url_or_locator"], MODULE.TRAIN_URL)
        self.assertEqual(sources[MODULE.N02_SOURCE]["effective_date"], "2025-12-31")
        facts = read_jsonl(BASE / f"normalized/fact-sources-{MODULE.SUFFIX}.jsonl")
        route_facts = [row for row in facts if row["field_name"].startswith("route_lines.segment.")]
        self.assertEqual(len(route_facts), 17)
        self.assertTrue(all(row["verification_status"] == "partial" for row in route_facts))
        altered_expected = MODULE.EXPECTED.copy()
        altered_expected[0] = ("敦賀", "010186", None, "07:06", "33", "origin")
        with patch.object(MODULE, "EXPECTED", altered_expected):
            with self.assertRaisesRegex(ValueError, "printed passenger calls drift"):
                MODULE.prepare()


if __name__ == "__main__":
    unittest.main()
