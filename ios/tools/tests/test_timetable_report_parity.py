"""Keep headline report counts aligned with generated timetable audits."""

import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]
AUDITS = ROOT / "app/data/train-service-history/audits"
REPORT = ROOT / "docs/train-timetable-verification-2026-09-29.md"


class TimetableReportParityTests(unittest.TestCase):
    def test_current_snapshot_and_unverified_totals_match_audits(self):
        report = REPORT.read_text(encoding="utf-8")
        coverage = json.loads((AUDITS / "train-timetable-coverage.json").read_text())
        routes = json.loads((AUDITS / "train-timetable-routes.json").read_text())
        history = json.loads((AUDITS / "train-timetable-history-alignment.json").read_text())
        chronology = json.loads((AUDITS / "train-timetable-stop-chronology.json").read_text())

        def reported(pattern):
            match = re.search(pattern, report)
            self.assertIsNotNone(match, f"Report is missing: {pattern}")
            return int(match.group(1).replace(",", ""))

        self.assertEqual(reported(r"现有 \*\*(\d+) 个模板\*\*"), coverage["tripTemplates"])
        self.assertEqual(reported(r"\*\*([\d,]+) 个有日历证据的计划班次实例"),
                         coverage["dailyOccurrencesRepresented"])
        self.assertEqual(reported(r"([\d,]+) 条模板停站记录"), coverage["stopTimes"])
        self.assertEqual(reported(r"线路审计仍有 ([\d,]+) 个未核实站间区间"),
                         routes["unverifiedLegs"])
        self.assertEqual(reported(r"历史线路对齐审计为 0 个已对齐、([\d,]+) 个未核实"),
                         history["unverifiedChecks"])
        self.assertEqual(reported(r"缺 ([\d,]+) 个覆盖单元"),
                         coverage["missingCoverageCells"])
        self.assertEqual(sum(row["blankCalls"] for row in chronology["blankPassengerCallsByTrip"]),
                         chronology["passengerCallsWithNeitherClock"])
        for row in chronology["blankPassengerCallsByTrip"]:
            self.assertEqual(len(row["serviceDates"]), row["occurrencesWithBlankCalls"])


if __name__ == "__main__":
    unittest.main()
