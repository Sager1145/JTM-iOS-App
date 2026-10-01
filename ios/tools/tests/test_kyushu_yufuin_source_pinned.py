"""Source-pinned timetable checks for JR Kyushu Yufuin no Mori."""

from datetime import date, timedelta
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "sources/candidates/jr-kyushu-yufuin-no-mori-20260314.json"
NORMALIZED_TRIPS = BASE / "normalized/trips/reviewed-root/seeds.jsonl"
NORMALIZED_STOPS = BASE / "normalized/stop-times/reviewed-root/seeds.jsonl"
NORMALIZED_EXCEPTIONS = BASE / "normalized/calendar-exceptions/reviewed-root/seeds.jsonl"
FACT_COMPLETENESS = BASE / "normalized/fact-completeness-root.jsonl"
FACT_SOURCES = BASE / "normalized/fact-sources-root.jsonl"
RESEARCH_QUEUE = BASE / "normalized/research-queue-root.jsonl"
SOURCE_REGISTRY = BASE / "sources/source-registry-root.jsonl"
OPERATOR_SEGMENTS = BASE / "normalized/trip-operator-segments/reviewed-root/seeds.jsonl"
LINE_SEGMENTS = BASE / "normalized/trip-lines/reviewed-root/seeds.jsonl"
CURRENT_N02 = ROOT / "app/public/rail/jp-2025.json"


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


class KyushuYufuinSourcePinnedTests(unittest.TestCase):
    OFFICIAL_CLOCKS = {
        "1": [
            ("jp.n02.009033", None, "09:17"),
            ("jp.n02.009327", None, "09:43"),
            ("jp.n02.009383", None, "09:51"),
            ("jp.n02.009391", None, "10:37"),
            ("jp.n02.009457", None, "10:49"),
            ("jp.n02.009425", None, "11:04"),
            ("jp.n02.009447", "11:31", None),
        ],
        "2": [
            ("jp.n02.009447", None, "12:01"),
            ("jp.n02.009425", None, "12:32"),
            ("jp.n02.009457", None, "12:47"),
            ("jp.n02.009391", None, "13:01"),
            ("jp.n02.009383", None, "13:46"),
            ("jp.n02.009327", None, "13:55"),
            ("jp.n02.009033", "14:19", None),
        ],
        "3": [
            ("jp.n02.009033", None, "10:11"),
            ("jp.n02.009327", None, "10:37"),
            ("jp.n02.009383", None, "10:47"),
            ("jp.n02.009391", None, "11:33"),
            ("jp.n02.009457", None, "11:45"),
            ("jp.n02.009425", None, "12:00"),
            ("jp.n02.009447", None, "12:32"),
            ("jp.n02.009479", None, "13:20"),
            ("jp.n02.009428", "13:31", None),
        ],
        "4": [
            ("jp.n02.009428", None, "14:36"),
            ("jp.n02.009479", None, "14:58"),
            ("jp.n02.009447", None, "15:56"),
            ("jp.n02.009425", None, "16:24"),
            ("jp.n02.009457", None, "16:40"),
            ("jp.n02.009391", None, "16:53"),
            ("jp.n02.009383", None, "17:36"),
            ("jp.n02.009327", None, "17:44"),
            ("jp.n02.009033", "18:10", None),
        ],
        "5": [
            ("jp.n02.009033", None, "14:38"),
            ("jp.n02.009327", None, "15:04"),
            ("jp.n02.009383", None, "15:12"),
            ("jp.n02.009391", None, "15:56"),
            ("jp.n02.009457", None, "16:09"),
            ("jp.n02.009425", None, "16:24"),
            ("jp.n02.009447", "16:50", None),
        ],
        "6": [
            ("jp.n02.009447", None, "17:17"),
            ("jp.n02.009425", None, "17:44"),
            ("jp.n02.009457", None, "17:59"),
            ("jp.n02.009391", None, "18:12"),
            ("jp.n02.009383", None, "18:54"),
            ("jp.n02.009327", None, "19:02"),
            ("jp.n02.009033", "19:27", None),
        ],
    }

    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        cls.as_of = date.fromisoformat(
            json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))["as_of_date"]
        )

    def test_official_timetable_directions_are_normalized_verbatim(self):
        expected = {"1": "down", "2": "up", "3": "down", "4": "up", "5": "down", "6": "up"}
        candidate_directions = {
            trip["public_number"]: trip["direction"] for trip in self.candidate["trips"]
        }
        self.assertEqual(candidate_directions, expected)
        normalized_directions = {
            trip["public_number"]: trip.get("direction")
            for trip in read_jsonl(NORMALIZED_TRIPS)
            if trip["service_id"] == "yufuin-no-mori"
        }
        self.assertEqual(normalized_directions, expected)
        evidence = self.candidate["direction_evidence"]
        self.assertIn("1・3・5号 are under 下り", evidence["locator"])
        self.assertIn("2・4・6号 are under 上り", evidence["locator"])

    def test_all_46_official_clocks_and_sides_are_normalized_verbatim(self):
        self.assertEqual(sum(map(len, self.OFFICIAL_CLOCKS.values())), 46)
        candidate_clocks = {
            trip["public_number"]: [
                (station_id, arrival, departure)
                for station_id, _name, arrival, departure, _call_type in trip["displayed_times"]
            ]
            for trip in self.candidate["trips"]
        }
        self.assertEqual(candidate_clocks, self.OFFICIAL_CLOCKS)

        normalized_clocks = {number: [] for number in self.OFFICIAL_CLOCKS}
        prefix = "jr-kyushu.yufuin-no-mori."
        for stop in read_jsonl(NORMALIZED_STOPS):
            if stop["trip_id"].startswith(prefix):
                number = stop["trip_id"][len(prefix):].split(".", 1)[0]
                normalized_clocks[number].append(
                    (stop["station_id"], stop["arrival_time"], stop["departure_time"])
                )
        self.assertEqual(normalized_clocks, self.OFFICIAL_CLOCKS)
        evidence = self.candidate["time_evidence"]
        self.assertEqual(evidence["effective_date"], "2026-03-14")
        self.assertEqual(evidence["information_current_at"], "2026-08-21")
        self.assertIn("all 46 displayed clocks", evidence["locator"])

    def test_all_six_time_facts_are_verified_and_sourced(self):
        prefix = "jr-kyushu.yufuin-no-mori."
        self.assertEqual(self.candidate["completeness"]["times"], "verified")
        self.assertNotIn("partial_times", self.candidate["promotion_status"])
        time_facts = [
            row for row in read_jsonl(FACT_COMPLETENESS)
            if row["entity_id"].startswith(prefix) and row["dimension"] == "times"
        ]
        self.assertEqual(len(time_facts), 6)
        self.assertTrue(all(row["status"] == "verified" for row in time_facts))
        self.assertTrue(all(row["confidence"] == "high" for row in time_facts))

        time_sources = [
            row for row in read_jsonl(FACT_SOURCES)
            if row["entity_id"].startswith(prefix) and row["field_name"] == "times"
        ]
        self.assertEqual(len(time_sources), 6)
        self.assertTrue(all(
            row["source_id"] == "jr-kyushu-yufuin-no-mori-20260314"
            and "all 46 displayed clocks" in row["page_or_locator"]
            for row in time_sources
        ))

        queued_times = [
            row for row in read_jsonl(RESEARCH_QUEUE)
            if row["entity_id"].startswith(prefix) and row["missing_dimension"] == "times"
        ]
        self.assertEqual(queued_times, [])

    def test_september_30_plan_uses_the_direct_official_pdf(self):
        plan = self.candidate["operating_date_override"]
        self.assertEqual((plan["from"], plan["until_inclusive"]), ("2026-09-19", "2026-09-30"))
        self.assertEqual(
            plan["url_or_locator"],
            "https://www.jrkyushu.co.jp/trains/yufuinnomori/__icsFiles/afieldfile/2026/08/18/"
            "20260818_yuhuin_no_mori_train_plan_0919_1.pdf",
        )
        source = next(
            row for row in read_jsonl(SOURCE_REGISTRY)
            if row["source_id"] == "jr-kyushu-yufuin-plan-20260919"
        )
        self.assertEqual(source["url_or_locator"], plan["url_or_locator"])

    def test_normalized_dates_are_source_bounded_and_capped_at_manifest(self):
        plan = self.candidate["operating_date_override"]
        first = date.fromisoformat(plan["from"])
        last = min(date.fromisoformat(plan["until_inclusive"]), self.as_of)
        expected = {
            (first + timedelta(days=offset)).isoformat()
            for offset in range((last - first).days + 1)
        }
        if (BASE / 'candidates/jr-kyushu-yufuin-no-mori-six-20260930.json').exists():
            expected.remove('2026-09-30')
        by_number = {str(number): set() for number in range(1, 7)}
        for row in read_jsonl(NORMALIZED_EXCEPTIONS):
            prefix = "jr-kyushu.yufuin-no-mori."
            if row["calendar_id"].startswith(prefix):
                number = row["calendar_id"][len(prefix):].split(".", 1)[0]
                by_number[number].add(row["service_date"])
        self.assertEqual(set(by_number), {"1", "2", "3", "4", "5", "6"})
        for dates in by_number.values():
            self.assertEqual(dates, expected)

    def test_operator_and_ordered_line_segments_are_source_pinned(self):
        trips = {
            row["trip_id"]: row for row in read_jsonl(NORMALIZED_TRIPS)
            if row["service_id"] == "yufuin-no-mori"
        }
        operators = [row for row in read_jsonl(OPERATOR_SEGMENTS) if row["trip_id"] in trips]
        self.assertEqual(len(operators), 6)
        for row in operators:
            self.assertEqual(row["operator_id"], "jr-kyushu")
            self.assertEqual(row["from_sequence"], 1)

        expected = self.candidate["route_segments_by_public_number"]
        actual = {}
        for trip_id, trip in trips.items():
            rows = sorted(
                (row for row in read_jsonl(LINE_SEGMENTS) if row["trip_id"] == trip_id),
                key=lambda row: row["sequence"],
            )
            actual[trip["public_number"]] = [
                [row["from_station_id"], row["to_station_id"], row["line_name"], row["current_n02_line_id"]]
                for row in rows
            ]
            self.assertTrue(all(row["reference_kind"] == "current_n02" for row in rows))
        self.assertEqual(actual, expected)

    def test_current_n02_identity_and_partial_status_are_explicit(self):
        package = json.loads(CURRENT_N02.read_text(encoding="utf-8"))
        lines = {row["id"]: row for row in package["lines"]}
        for _, segments in self.candidate["route_segments_by_public_number"].items():
            for from_station, to_station, line_name, line_id in segments:
                line = lines[line_id]
                self.assertEqual((line["operator"], line["name"]), ("九州旅客鉄道", line_name))
                codes = {station[0] for station in line["stations"]}
                self.assertIn(from_station.removeprefix("jp.n02."), codes)
                self.assertIn(to_station.removeprefix("jp.n02."), codes)

        facts = [
            row for row in read_jsonl(FACT_COMPLETENESS)
            if row["entity_id"].startswith("jr-kyushu.yufuin-no-mori.")
        ]
        by_dimension = {}
        for row in facts:
            by_dimension.setdefault(row["dimension"], set()).add(row["status"])
        self.assertEqual(by_dimension["operator"], {"verified"})
        self.assertEqual(by_dimension["route_lines"], {"partial"})
        self.assertEqual(by_dimension["times"], {"verified"})
        queued = [
            row["missing_dimension"] for row in read_jsonl(RESEARCH_QUEUE)
            if row["entity_id"].startswith("jr-kyushu.yufuin-no-mori.")
        ]
        self.assertNotIn("operator", queued)
        self.assertNotIn("times", queued)
        self.assertIn("route_lines", queued)


if __name__ == "__main__":
    unittest.main()
