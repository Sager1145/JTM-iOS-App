"""Source-pinned checks for bounded JR East route evidence."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
CANDIDATE = BASE / "sources/candidates/reviewed-route-evidence-20260928.json"
TOKIWA_ID = "jr-east.tokiwa.55.main.2026-09-19"
AZUSA_IDS = (
    "jr-east.azusa.1.base.2026-09-18",
    "jr-east.azusa.1.selected-saturday-holiday.2026-09-19",
)


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


class RouteEvidenceSourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads(CANDIDATE.read_text())

    def test_official_jr_east_sources_are_pinned(self):
        sources = {row["source_id"]: row for row in self.candidate["sources"]}
        self.assertEqual(
            sources["jr-east-azusa-route-current"]["url_or_locator"],
            "https://www.jreast.co.jp/multi/traininformation/azusa_kaiji/",
        )
        self.assertEqual(
            sources["jr-east-chuo-shinonoi-boundary-20260507"]["url_or_locator"],
            "https://www.jreast.co.jp/press/2026/nagano/20260507_na01.pdf",
        )
        self.assertEqual(
            sources["jr-east-hitachi-route-current"]["url_or_locator"],
            "https://www.jreast.co.jp/multi/traininformation/hitachi/",
        )
        self.assertEqual(
            sources["jr-east-kanto-route-map-202604"]["url_or_locator"],
            "https://www.jreast.co.jp/map/pdf/kanto.pdf",
        )
        exact = next(
            row
            for row in read_jsonl(BASE / "sources/source-registry-east-next-batch.jsonl")
            if row["source_id"] == "jr-east-tokiwa55-202609-east-next"
        )
        self.assertEqual(
            exact["url_or_locator"],
            "https://timetables.jreast.co.jp/2610/train/075/076301.html",
        )

    def test_azusa_variants_have_bounded_chuo_shinonoi_route_labels(self):
        evidence = {row["trip_id"]: row for row in self.candidate["trip_evidence"]}
        normalized = read_jsonl(
            BASE / "normalized/trip-lines/route-evidence/reviewed.jsonl"
        )
        operators = read_jsonl(
            BASE / "normalized/trip-operator-segments/route-evidence/reviewed.jsonl"
        )
        completeness = {
            (row["entity_id"], row["dimension"]): row
            for path in (BASE / "normalized").glob("fact-completeness*.jsonl")
            for row in read_jsonl(path)
        }
        stations = (
            "jp.n02.003700", "jp.n02.003634", "jp.n02.003947",
            "jp.n02.004166", "jp.n02.003867", "jp.n02.003533",
            "jp.n02.002981", "jp.n02.002764", "jp.n02.002706",
            "jp.n02.002696", "jp.n02.002616", "jp.n02.002506",
        )
        for trip_id in AZUSA_IDS:
            with self.subTest(trip_id=trip_id):
                candidate = evidence[trip_id]
                self.assertEqual(
                    [(row["from_station_id"], row["to_station_id"])
                     for row in candidate["line_segments"]],
                    list(zip(stations, stations[1:])),
                )
                rows = [row for row in normalized if row["trip_id"] == trip_id]
                self.assertEqual([row["sequence"] for row in rows], list(range(1, 12)))
                self.assertEqual(
                    [row["line_name"] for row in rows],
                    ["中央線"] * 10 + ["篠ノ井線"],
                )
                self.assertTrue(all(row["confidence"] == "medium" for row in rows))
                self.assertEqual(
                    [row["current_n02_line_id"] for row in rows],
                    ["jp-東日本旅客鉄道-中央線"] * 10 + ["jp-東日本旅客鉄道-篠ノ井線"],
                )
                self.assertTrue(all(row["reference_kind"] == "current_n02" for row in rows))
                self.assertTrue(all("rail_history_id" not in row for row in rows))
                operator = next(row for row in operators if row["trip_id"] == trip_id)
                self.assertEqual(
                    (operator["from_sequence"], operator["to_sequence"], operator["operator_id"]),
                    (1, 12, "jr-east"),
                )
                for dimension in ("operator", "route_lines"):
                    self.assertEqual(
                        (completeness[(trip_id, dimension)]["status"],
                         completeness[(trip_id, dimension)]["confidence"]),
                        ("partial", "medium"),
                    )

    def test_tokiwa_candidate_is_bounded_to_six_joban_passenger_pairs(self):
        evidence = next(
            row for row in self.candidate["trip_evidence"] if row["trip_id"] == TOKIWA_ID
        )
        expected = [
            ("jp.n02.003505", "jp.n02.002984"),
            ("jp.n02.002984", "jp.n02.002660"),
            ("jp.n02.002660", "jp.n02.002552"),
            ("jp.n02.002552", "jp.n02.002350"),
            ("jp.n02.002350", "jp.n02.002319"),
            ("jp.n02.002319", "jp.n02.002280"),
        ]
        segments = evidence["line_segments"]
        self.assertEqual(
            [(row["from_station_id"], row["to_station_id"]) for row in segments],
            expected,
        )
        self.assertEqual([row["sequence"] for row in segments], list(range(1, 7)))
        self.assertTrue(all(row["line_name"] == "常磐線" for row in segments))
        self.assertEqual(evidence["line_segment_defaults"]["confidence"], "medium")
        self.assertEqual(evidence["operator_segment"]["verification_status"], "partial")
        self.assertEqual(
            (evidence["operator_segment"]["from_sequence"], evidence["operator_segment"]["to_sequence"]),
            (1, 9),
        )
        blocked = evidence["unnormalized_corridor_evidence"]
        self.assertEqual(len(blocked), 1)
        self.assertEqual(blocked[0]["from_station_id"], "jp.n02.004095")
        self.assertEqual(blocked[0]["to_station_id"], "jp.n02.003505")
        self.assertEqual(blocked[0]["status"], "blocked")

    def test_normalized_tokiwa_rows_keep_uncalled_boundary_out_of_stop_times(self):
        line_rows = [
            row
            for row in read_jsonl(
                BASE / "normalized/trip-lines/route-evidence/reviewed.jsonl"
            )
            if row["trip_id"] == TOKIWA_ID
        ]
        self.assertEqual(len(line_rows), 6)
        self.assertEqual([row["sequence"] for row in line_rows], [3, 5, 6, 7, 8, 9])
        for row in line_rows:
            self.assertEqual(row["confidence"], "medium")
        self.assertEqual(line_rows[0]["line_name"], "東北線")
        self.assertEqual(line_rows[0]["to_station_id"], "jp.n02.003417")
        self.assertEqual(line_rows[0]["current_n02_line_id"], "jp-東日本旅客鉄道-東北線-2")
        self.assertTrue(all(
            row["line_name"] == "常磐線"
            and
            row["reference_kind"] == "current_n02"
            and row["current_n02_line_id"] == "jp-東日本旅客鉄道-常磐線"
            for row in line_rows[1:]
        ))
        self.assertTrue(all("rail_history_id" not in row for row in line_rows))
        self.assertNotIn("jp.n02.004095", {row["from_station_id"] for row in line_rows})
        self.assertNotIn("jp.n02.003766", {row["from_station_id"] for row in line_rows})

        operator = next(
            row
            for row in read_jsonl(
                BASE / "normalized/trip-operator-segments/route-evidence/reviewed.jsonl"
            )
            if row["trip_id"] == TOKIWA_ID
        )
        self.assertEqual(
            (operator["from_sequence"], operator["to_sequence"], operator["operator_id"]),
            (1, 9, "jr-east"),
        )

        completeness = {}
        for path in (BASE / "normalized").glob("fact-completeness*.jsonl"):
            for row in read_jsonl(path):
                completeness[(row["entity_id"], row["dimension"])] = row
        for dimension in ("operator", "route_lines"):
            row = completeness[(TOKIWA_ID, dimension)]
            self.assertEqual((row["status"], row["confidence"]), ("partial", "medium"))

        provenance = [
            row
            for row in read_jsonl(BASE / "normalized/fact-sources-route-evidence.jsonl")
            if row["entity_id"] == TOKIWA_ID
        ]
        operator_sources = {
            row["source_id"]
            for row in provenance
            if row["field_name"] == "operator_route_evidence"
        }
        self.assertEqual(
            operator_sources,
            {"jr-east-tokiwa55-202609-east-next", "jr-east-hitachi-route-current"},
        )
        line_sources = {
            row["source_id"]
            for row in provenance
            if row["field_name"].startswith("route_lines.segment.")
        }
        self.assertEqual(
            line_sources,
            {
                "jr-east-tokiwa55-202609-east-next",
                "jr-east-hitachi-route-current",
                "jr-east-kanto-route-map-202604",
            },
        )
        self.assertTrue(all(row["verification_status"] == "partial" for row in provenance))


if __name__ == "__main__":
    unittest.main()
