"""Source-pinned checks for the bounded 2026 current-N02 route identities."""

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
    / "sources/candidates/reviewed-current-n02-route-identities-20260930.json"
)
NORMALIZER_PATH = (
    ROOT / "ios/tools/normalize-reviewed-current-n02-route-identities-20260930.py"
)
TOOLS = ROOT / "ios/tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import train_timetable


def load_normalizer():
    spec = importlib.util.spec_from_file_location("current_n02_route_normalizer", NORMALIZER_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def read_jsonl(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


class CurrentN02RouteIdentitiesSourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.normalizer = load_normalizer()
        cls.candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        cls.temp = tempfile.TemporaryDirectory()
        cls.canonical = Path(cls.temp.name) / "train-service-history"
        shutil.copytree(BASE, cls.canonical)
        cls.counts = cls.normalizer.normalize(
            cls.canonical,
            CANDIDATE,
            ROOT / "app/public/rail/jp-2025.json",
        )

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def all_line_rows(self):
        return [
            row
            for path in (self.canonical / "normalized/trip-lines").rglob("*.jsonl")
            for row in read_jsonl(path)
        ]

    def test_candidate_is_bounded_to_reviewed_primary_sources(self):
        self.assertEqual(self.counts["patched_segments"], 57)
        self.assertEqual(self.counts["split_segments"], 2)
        self.assertEqual(self.counts["added_segments"], 6)
        self.assertEqual(self.counts["route_only_stations"], 1)
        sources = {row["source_id"]: row for row in self.candidate["new_sources"]}
        self.assertEqual(
            sources["mlit-n02-2025-20251231"]["url_or_locator"],
            "https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html",
        )
        self.assertEqual(
            sources["jr-east-passenger-lines-rules-20260930"]["url_or_locator"],
            "https://www.jreast.co.jp/ryokaku/02_hen/04_syo/02_setsu/02.html",
        )
        self.assertEqual(
            sources["jr-east-passenger-lines-rules-20260930"]["title"],
            "旅客営業規則 第156条（途中下車）",
        )
        article_notes = sources["jr-east-passenger-lines-rules-20260930"]["notes"]
        self.assertIn(
            "lists 篠ノ井線 without endpoint bounds",
            article_notes,
        )
        self.assertIn("does not establish operator ownership", article_notes)
        self.assertNotIn("篠ノ井線 篠ノ井–塩尻", article_notes)
        self.assertEqual(
            sources["jr-hokkaido-line-inventory-20260401"]["url_or_locator"],
            "https://www.jrhokkaido.co.jp/corporate/company/com_02.html",
        )
        self.assertIn(
            "does not establish a daily service-validity interval",
            self.candidate["review_contract"],
        )
        self.assertIn("is not a canonical timetable stop", self.candidate["review_contract"])
        all_sources = {
            row["source_id"]: row
            for path in self.canonical.glob("sources/source-registry*.jsonl")
            for row in read_jsonl(path)
        }
        self.assertEqual(
            all_sources["jr-east-hitachi26-202609"]["url_or_locator"],
            "https://timetables.jreast.co.jp/2610/train/095/098731.html",
        )
        self.assertEqual(
            all_sources["jr-east-tokiwa55-202609-east-next"]["url_or_locator"],
            "https://timetables.jreast.co.jp/2610/train/075/076301.html",
        )

    def test_fact_sources_state_distinct_evidence_roles_without_direct_overclaim(self):
        facts = read_jsonl(
            self.canonical
            / "normalized/fact-sources-current-n02-route-identities-20260930.jsonl"
        )
        segment_facts = [
            row for row in facts
            if row["entity_id"] == "jr-east.azusa.1.base.2026-09-18"
            and row["field_name"] == "route_lines.segment.1.current_n02_identity"
        ]
        by_source = {row["source_id"]: row["page_or_locator"] for row in segment_facts}
        self.assertEqual(len(by_source), 5)
        self.assertEqual(len(set(by_source.values())), 5)
        self.assertIn(
            "ordered passenger calls, but does not publish a physical line id",
            by_source["jr-east-azusa1-base-202609-east-next"],
        )
        self.assertIn(
            "does not establish ownership, a train path, a jp-* id, or daily validity",
            by_source["jr-east-passenger-lines-rules-20260930"],
        )
        self.assertIn(
            "Canonical jp-* ids and endpoint membership are project-derived",
            by_source["mlit-n02-2025-20251231"],
        )
        self.assertTrue(all("Evidence role:" in locator for locator in by_source.values()))
        self.assertTrue(all(
            "daily temporal coverage remains unverified" in locator
            for locator in by_source.values()
        ))
        self.assertTrue(all(
            "Current identity is direct" not in row["page_or_locator"]
            for row in facts
        ))

    def test_normalizer_accepts_pre_split_and_already_split_boundary_rows(self):
        # setUpClass normalizes a copy of the already-split canonical tree. A
        # second pass must be a logical no-op.
        target_ids = {
            group["trip_id"] for group in self.candidate["segment_groups"]
        }

        def target_snapshot(base):
            rows = [
                row
                for path in (base / "normalized/trip-lines").rglob("*.jsonl")
                for row in read_jsonl(path)
                if row["trip_id"] in target_ids
            ]
            return sorted(rows, key=lambda row: (row["trip_id"], row["sequence"]))

        before = target_snapshot(self.canonical)
        second_counts = self.normalizer.normalize(
            self.canonical,
            CANDIDATE,
            ROOT / "app/public/rail/jp-2025.json",
        )
        self.assertEqual(second_counts, self.counts)
        self.assertEqual(target_snapshot(self.canonical), before)

        # Reconstruct the two original unsplit passenger-pair rows in another
        # isolated copy, then verify the same normalizer produces the split form.
        with tempfile.TemporaryDirectory() as temp:
            pre_split = Path(temp) / "train-service-history"
            shutil.copytree(self.canonical, pre_split)
            addition_output = (
                pre_split
                / "normalized/trip-lines/current-n02-route-identities-20260930/urban-segments.jsonl"
            )
            line_paths = [
                path for path in (pre_split / "normalized/trip-lines").rglob("*.jsonl")
                if path != addition_output
            ]
            for split in self.candidate["route_only_boundary_splits"]:
                matches = []
                for path in line_paths:
                    rows = read_jsonl(path)
                    for row in rows:
                        if (
                            row["trip_id"] == split["trip_id"]
                            and row["from_station_id"] == split["from_station_id"]
                            and row["to_station_id"] == split["boundary_station_id"]
                        ):
                            matches.append((path, rows, row))
                self.assertEqual(len(matches), 1)
                path, rows, row = matches[0]
                row["sequence"] = split["input_sequence"]
                row["to_station_id"] = split["to_station_id"]
                row["line_name"] = "常磐線"
                row.pop("reference_kind", None)
                row.pop("current_n02_line_id", None)
                path.write_text(
                    "".join(
                        json.dumps(item, ensure_ascii=False, sort_keys=True) + "\n"
                        for item in rows
                    ),
                    encoding="utf-8",
                )
            pre_split_counts = self.normalizer.normalize(
                pre_split,
                CANDIDATE,
                ROOT / "app/public/rail/jp-2025.json",
            )
            self.assertEqual(pre_split_counts, self.counts)
            self.assertEqual(target_snapshot(pre_split), before)

    def test_57_existing_and_four_urban_segments_have_exact_current_identities(self):
        target_ids = {
            group["trip_id"] for group in self.candidate["segment_groups"]
        }
        rows = [row for row in self.all_line_rows() if row["trip_id"] in target_ids]
        identified = [row for row in rows if row.get("reference_kind") == "current_n02"]
        unidentified = [row for row in rows if row.get("reference_kind") is None]
        self.assertEqual(len(identified), 65)
        self.assertEqual(unidentified, [])
        self.assertTrue(all("current_n02_line_id" in row for row in identified))
        self.assertTrue(all("rail_history_id" not in row for row in identified))

        azusa = [row for row in rows if ".azusa." in row["trip_id"]]
        self.assertEqual(len(azusa), 22)
        self.assertEqual(
            {row["line_name"] for row in azusa if row["sequence"] <= 10},
            {"中央線"},
        )
        self.assertEqual(
            {row["current_n02_line_id"] for row in azusa if row["sequence"] <= 10},
            {"jp-東日本旅客鉄道-中央線"},
        )
        self.assertEqual(
            {row["current_n02_line_id"] for row in azusa if row["sequence"] == 11},
            {"jp-東日本旅客鉄道-篠ノ井線"},
        )

        sarobetsu = [row for row in rows if ".sarobetsu." in row["trip_id"]]
        self.assertEqual(len(sarobetsu), 20)
        self.assertEqual({row["line_name"] for row in sarobetsu}, {"宗谷線"})
        self.assertEqual(
            {row["current_n02_line_id"] for row in sarobetsu},
            {"jp-北海道旅客鉄道-宗谷線"},
        )

    def test_urban_segments_are_ordered_across_route_only_nippori(self):
        rows_by_trip = {}
        for row in self.all_line_rows():
            rows_by_trip.setdefault(row["trip_id"], []).append(row)
        hitachi_id = "jr-east.hitachi.26.2026-09-18"
        tokiwa_id = "jr-east.tokiwa.55.main.2026-09-19"
        hitachi = sorted(rows_by_trip[hitachi_id], key=lambda row: row["sequence"])
        tokiwa = sorted(rows_by_trip[tokiwa_id], key=lambda row: row["sequence"])
        self.assertEqual([row["sequence"] for row in hitachi], list(range(1, 15)))
        self.assertEqual([row["sequence"] for row in tokiwa], list(range(1, 10)))

        self.assertEqual(
            [row["current_n02_line_id"] for row in hitachi[-4:]],
            [
                "jp-東日本旅客鉄道-常磐線",
                "jp-東日本旅客鉄道-東北線-2",
                "jp-東日本旅客鉄道-東北線-2",
                "jp-東日本旅客鉄道-東海道線",
            ],
        )
        self.assertEqual(
            [row["current_n02_line_id"] for row in tokiwa[:4]],
            [
                "jp-東日本旅客鉄道-東海道線",
                "jp-東日本旅客鉄道-東北線-2",
                "jp-東日本旅客鉄道-東北線-2",
                "jp-東日本旅客鉄道-常磐線",
            ],
        )
        self.assertEqual(
            [
                (row["from_station_id"], row["to_station_id"], row["line_name"])
                for row in hitachi[10:12]
            ],
            [
                ("jp.n02.002319", "jp.n02.003417", "常磐線"),
                ("jp.n02.003417", "jp.n02.003505", "東北線"),
            ],
        )
        self.assertEqual(
            [
                (row["from_station_id"], row["to_station_id"], row["line_name"])
                for row in tokiwa[2:4]
            ],
            [
                ("jp.n02.003505", "jp.n02.003417", "東北線"),
                ("jp.n02.003417", "jp.n02.002984", "常磐線"),
            ],
        )

        station_rows = read_jsonl(
            self.canonical
            / "normalized/station-identities-current-n02-route-identities-20260930.jsonl"
        )
        self.assertEqual(station_rows, [{
            "current_source_code": "003417",
            "name_snapshot": "日暮里",
            "rail_history_id": None,
            "reference_kind": "current_n02",
            "station_id": "jp.n02.003417",
        }])
        manifest = train_timetable.load_manifest(self.canonical)
        data, _ = train_timetable.load_dataset(self.canonical, manifest)
        for trip_id in (hitachi_id, tokiwa_id):
            self.assertNotIn(
                "jp.n02.003417",
                [row["station_id"] for row in data["stop_times"] if row["trip_id"] == trip_id],
            )

        facts = read_jsonl(
            self.canonical
            / "normalized/fact-sources-current-n02-route-identities-20260930.jsonl"
        )
        for trip_id, sequences, exact_source in (
            (hitachi_id, (11, 12), "jr-east-hitachi26-202609"),
            (tokiwa_id, (3, 4), "jr-east-tokiwa55-202609-east-next"),
        ):
            for sequence in sequences:
                segment_facts = [
                    row for row in facts
                    if row["entity_id"] == trip_id
                    and row["field_name"]
                    == f"route_lines.segment.{sequence}.current_n02_identity"
                ]
                self.assertIn(exact_source, {row["source_id"] for row in segment_facts})
                self.assertIn(
                    "jr-east-passenger-lines-rules-20260930",
                    {row["source_id"] for row in segment_facts},
                )

    def test_all_current_ids_match_package_metadata_and_endpoints(self):
        package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
        lines = {row["id"]: row for row in package["lines"]}
        stations = {
            row["station_id"]: row["current_source_code"]
            for path in self.canonical.glob("normalized/station-identities*.jsonl")
            for row in read_jsonl(path)
            if row.get("reference_kind") == "current_n02"
        }
        operators = {
            row["operator_id"]: {row["display_name"], row["legal_name"]}
            for row in read_jsonl(self.canonical / "normalized/operators-root.jsonl")
        }
        target_ids = {
            group["trip_id"] for group in self.candidate["segment_groups"]
        }
        for row in self.all_line_rows():
            if row["trip_id"] not in target_ids or row.get("reference_kind") is None:
                continue
            line = lines[row["current_n02_line_id"]]
            line_codes = {station[0] for station in line["stations"]}
            self.assertEqual(row["line_name"], line["name"])
            self.assertIn(line["operator"], operators[row["operator_id"]])
            self.assertIn(stations[row["from_station_id"]], line_codes)
            self.assertIn(stations[row["to_station_id"]], line_codes)

    def test_route_completeness_and_current_snapshot_validity_remain_partial(self):
        manifest = train_timetable.load_manifest(self.canonical)
        data, origins = train_timetable.load_dataset(self.canonical, manifest)
        target_ids = {
            group["trip_id"] for group in self.candidate["segment_groups"]
        }
        completeness = {
            (row["entity_id"], row["dimension"]): row
            for row in data["fact_completeness"]
        }
        queue = {
            (row["entity_id"], row["missing_dimension"]): row
            for row in data["research_queue"]
        }
        for trip_id in target_ids:
            self.assertEqual(completeness[(trip_id, "route_lines")]["status"], "partial")
            self.assertNotIn(
                "no current N02 physical line id",
                completeness[(trip_id, "route_lines")]["notes"],
            )
            self.assertEqual(queue[(trip_id, "route_lines")]["status"], "open")
            self.assertIn(
                "service-validity interval",
                queue[(trip_id, "route_lines")]["notes"],
            )

        verdicts = train_timetable.route_attestations(data, manifest)
        for trip_id in target_ids:
            for segment in verdicts[trip_id]["segments"]:
                if segment["referenceKind"] == "current_n02":
                    self.assertEqual(segment["status"], "unverified")
                    self.assertEqual(
                        segment["reason"],
                        "current_n02_snapshot_has_no_validity_interval",
                    )
                    self.assertTrue(segment["identityVerified"])
                    self.assertFalse(segment["temporalCoverageVerified"])
        self.assertEqual(train_timetable.validate_dataset(data, origins, manifest), [])


if __name__ == "__main__":
    unittest.main()
