"""Shared behavior for the consolidated reviewed timetable staging clusters."""
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TOOLS = ROOT / "ios/tools"
sys.path.insert(0, str(TOOLS))

import reviewed_timetable_staging as staging

WEEKDAY = ("monday",)


def load(filename):
    spec = importlib.util.spec_from_file_location(
        "reviewed_" + filename.replace("-", "_").removesuffix(".py"), TOOLS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def east_package(names, aliases):
    stations = []
    serial = 1
    for name in sorted(names):
        directory = aliases.get(name, name)
        if name == "東京":
            stations.extend([["003766", directory], ["009999", directory]])
        elif name == "武蔵小杉":
            stations.extend([["004301", directory], ["008888", directory]])
        else:
            stations.append([f"{serial:06d}", directory])
            serial += 1
    return {"lines": [
        {"operator": "東日本旅客鉄道", "stations": stations},
        {"operator": "東海旅客鉄道", "stations": [["003766", "東京"]]},
    ]}


class SharedStagingTests(unittest.TestCase):

    def test_odekake_stage_keeps_unknown_route_zero_offset_and_rejects_first(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            suffix = "scratch-odekake"
            (base / "candidates").mkdir()
            (base / "sources").mkdir()
            (base / "candidates" / "one.json").write_text('{"trip": {}}', encoding="utf-8")
            (base / f"sources/source-registry-{suffix}.jsonl").write_text("{}", encoding="utf-8")
            stops = [
                ("甲府", "003867", None, "23:50", None, "origin"),
                ("静岡", "006128", "00:10", None, "４", "destination"),
            ]
            copy = {
                "candidate_path": "candidates/one.json",
                "identity_note": "id",
                "train_number_note": "tn",
                "stops_note": "stops",
                "edition_name": "edition",
                "service_id": "fujikawa",
                "train_number": "4010M",
                "public_number": "10",
                "origin_station_id": "jp.n02.003867",
                "destination_station_id": "jp.n02.006128",
                "summary_suffix": ": 2 calls",
            }
            args = dict(
                base=base, suffix=suffix, trip_id="trip.1", service_date="2026-09-30",
                valid_until="2026-10-01", source_id="src", weekdays=WEEKDAY, stops=stops,
                station_additions=lambda: [], copy=copy,
            )
            with self.assertRaises(ValueError):
                staging.stage_odekake_single_trip(validate=lambda candidate, source: (_ for _ in ()).throw(ValueError("bad")), **args)
            self.assertFalse((base / "normalized").exists())
            staging.stage_odekake_single_trip(validate=lambda candidate, source: None, **args)
            written = read_jsonl(base / f"normalized/stop-times/{suffix}/seeds.jsonl")
            self.assertEqual([row["day_offset"] for row in written], [0, 0])
            self.assertEqual(written[1]["arrival_time"], "00:10")
            trip = read_jsonl(base / f"normalized/trips/{suffix}/seeds.jsonl")[0]
            self.assertEqual(trip["notes"], "Exact date only; operator and route lines unknown.")
            facts = {row["dimension"]: row["status"] for row in read_jsonl(base / f"normalized/fact-completeness-{suffix}.jsonl")}
            self.assertEqual(facts["operator"], "unknown")
            self.assertEqual(facts["route_lines"], "unknown")
            self.assertFalse(list((base / "normalized").rglob("*equipment*")))
            self.assertFalse(list((base / "normalized").rglob("*formation*")))

    def test_jr_east_stage_forces_station_ids_and_keeps_flat_clocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "root"
            base = Path(tmp) / "base"
            (root / "app/public/rail").mkdir(parents=True)
            names = {"東京", "武蔵小杉", "成田空港", "空港第２ビル"}
            aliases = {"空港第２ビル": "空港第2ビル"}
            (root / "app/public/rail/jp-2025.json").write_text(
                json.dumps(east_package(names, aliases), ensure_ascii=False), encoding="utf-8")
            candidate = {
                "source_locator": "locator",
                "trips": [{
                    "trip_id": "t1",
                    "train_number": "2001M",
                    "origin": "東京",
                    "destination": "成田空港",
                    "stops": [
                        ["東京", None, "23:50", "４", "origin"],
                        ["武蔵小杉", "00:10", "00:12", None, "passenger_stop"],
                        ["空港第２ビル", None, None, None, "pass"],
                        ["成田空港", "00:40", None, None, "destination"],
                    ],
                }],
            }
            path = base / "candidate.json"
            path.parent.mkdir(parents=True)
            path.write_text(json.dumps(candidate, ensure_ascii=False), encoding="utf-8")
            copy = {
                "edition_prefix": "ed ",
                "public_number": "1",
                "coupling_note": "coupled ",
                "incomplete_note": "incomplete",
                "identity_note": "id",
                "partial_stops_note": "partial stops",
                "partial_times_note": "partial times",
                "title": "title",
                "summary": "Staged scratch",
                "relations": [{
                    "trip_id": "t1", "related_trip_id": "t1", "relation_type": "couples_with",
                    "from_sequence": 1, "to_sequence": 4, "source_id": "src",
                }],
            }
            args = dict(
                base=base, root=root, candidate_path=path, suffix="scratch-nex",
                day="2026-09-30", next_day="2026-10-01", source_id="src", url="https://example.test",
                service="narita-express", aliases=aliases, weekdays=WEEKDAY, copy=copy,
            )
            with self.assertRaises(ValueError):
                staging.stage_jr_east_coupled_columns(pinned={"changed": True}, **args)
            self.assertFalse((base / "normalized").exists())
            staging.stage_jr_east_coupled_columns(pinned=candidate, **args)
            stops = read_jsonl(base / "normalized/stop-times/scratch-nex/seeds.jsonl")
            self.assertEqual(stops[0]["station_id"], "jp.n02.003766")
            self.assertEqual(stops[1]["station_id"], "jp.n02.004301")
            self.assertEqual(stops[2]["station_id"], "jp.n02." + [
                code for code, directory in east_package(names, aliases)["lines"][0]["stations"]
                if directory == "空港第2ビル"
            ][0])
            self.assertEqual([row["day_offset"] for row in stops], [0, 0, 0, 0])
            self.assertEqual(stops[1]["arrival_time"], "00:10")
            self.assertEqual(stops[2]["time_accuracy"], "unknown")
            self.assertEqual(stops[0]["time_accuracy"], "minute")
            facts = {row["dimension"]: row["status"] for row in read_jsonl(base / "normalized/fact-completeness-scratch-nex.jsonl")}
            self.assertEqual(facts["operator"], "unknown")
            self.assertEqual(facts["route_lines"], "unknown")
            self.assertNotIn("equipment", read_jsonl(base / "normalized/trips/scratch-nex/seeds.jsonl")[0])

    def test_shinano_stage_keeps_direction_origin_and_rejects_first(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            suffix = "scratch-shinano"
            candidate = {
                "candidate_status": "reviewed_official_html",
                "database_as_of_date": "2026-09-30",
                "official_english_name": {"name": "Shinano", "source_id": "en", "url_or_locator": "http://en"},
                "trip": {
                    "trip_id": "jr-central.shinano.11.2026-09-30",
                    "service_id": "shinano",
                    "service_name": "しなの",
                    "public_number": "11",
                    "train_number": "1011M",
                    "service_date": "2026-09-30",
                    "direction": "down",
                    "equipment": ["グリーン車指定席", "普通車一部指定席"],
                    "calendar_observation": {
                        "month": "2026年9月", "day": 30, "cell_class": "ok", "variant_url": "http://src",
                    },
                    "source": {
                        "source_id": "src", "url_or_locator": "http://src",
                        "automated_extraction_allowed": False,
                    },
                    "stop_times": [
                        {"stop_sequence": 1, "name_snapshot": "名古屋", "arrival_time": None,
                         "departure_time": "23:40", "platform": "１０", "call_type": "origin"},
                        {"stop_sequence": 2, "name_snapshot": "長野", "arrival_time": "00:05",
                         "departure_time": None, "platform": "２", "call_type": "destination"},
                    ],
                },
            }
            path = base / "candidate.json"
            (base).mkdir(parents=True, exist_ok=True)
            (base / "manifest.json").write_text(json.dumps({"as_of_date": "2026-09-30"}), encoding="utf-8")
            path.write_text(json.dumps(candidate, ensure_ascii=False), encoding="utf-8")
            copy = {
                "identity_note": "id", "train_number_note": "tn", "calendar_note": "cal",
                "stops_note": "stops", "edition_name": "ed", "exception_reason": "reason",
                "train_number": "1011M", "public_number": "11",
                "origin_name": "名古屋", "destination_name": "長野",
                "trip_notes": "Equipment: グリーン車指定席; 普通車一部指定席. Exact-date.",
                "summary_prefix": "Normalized ",
                "status_error": "status", "cutoff_error": "cutoff", "date_error": "date",
                "pinned_trip_id": "jr-central.shinano.11.2026-09-30",
                "pinned_public_number": "11", "pinned_train_number": "1011M",
                "identity_error": "identity", "source_error": "source", "direction": "down",
                "stops_error": "stops", "stop_sequence_end": 3, "sequence_error": "sequence",
            }
            expected_stops = [
                ("名古屋", "005451", None, "23:40", "１０", "origin"),
                ("長野", "002031", "00:05", None, "２", "destination"),
            ]
            stations = {
                "名古屋": {"station_id": "jp.n02.005451", "name_snapshot": "名古屋"},
                "長野": {"station_id": "jp.n02.002031", "name_snapshot": "長野"},
            }
            args = dict(
                base=base, candidate_path=path, suffix=suffix, service_date="2026-09-30",
                valid_until="2026-10-01", source_id="src", weekdays=WEEKDAY,
                station_source_id="jtm-current-station-directory", copy=copy,
                verify_existing_service_and_english_name=lambda: None,
                resolve_stations=lambda: (stations, []),
            )
            with self.assertRaises(ValueError):
                staging.stage_shinano_exact_date(
                    validate_candidate=lambda candidate: (_ for _ in ()).throw(ValueError("bad")), **args)
            self.assertFalse((base / "normalized").exists())

            def accept(candidate_row):
                staging.validate_shinano_candidate(
                    candidate_row, base=base, service_date="2026-09-30", source_id="src",
                    source_url="http://src", expected_stops=expected_stops,
                    english_source_id="en", english_source_url="http://en", copy=copy)

            staging.stage_shinano_exact_date(validate_candidate=accept, **args)
            trip = read_jsonl(base / f"normalized/trips/{suffix}/seeds.jsonl")[0]
            self.assertEqual(trip["direction"], "down")
            self.assertEqual(trip["origin_station_id"], "jp.n02.005451")
            self.assertEqual(trip["destination_station_id"], "jp.n02.002031")
            self.assertIn("Equipment:", trip["notes"])
            written = read_jsonl(base / f"normalized/stop-times/{suffix}/seeds.jsonl")
            self.assertEqual([row["day_offset"] for row in written], [0, 0])
            self.assertEqual(written[1]["arrival_time"], "00:05")
            facts = {row["dimension"]: row["status"] for row in read_jsonl(base / f"normalized/fact-completeness-{suffix}.jsonl")}
            self.assertEqual(facts["operator"], "unknown")
            self.assertEqual(facts["route_lines"], "unknown")

    def test_rewritten_mains_honor_live_base_root_and_candidate(self):
        self._run_odekake_main()
        self._run_nex_main()
        self._run_shinano_main()

    def _run_odekake_main(self):
        module = load("normalize-reviewed-central-fujikawa10-20260930.py")
        original = (module.BASE, module.validate, module.station_additions)
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            (base / "candidates").mkdir()
            (base / "sources").mkdir()
            (base / module.STAGING_FACTS["candidate_path"]).write_text("{}", encoding="utf-8")
            (base / f"sources/source-registry-{module.SUFFIX}.jsonl").write_text("{}", encoding="utf-8")
            module.BASE = base
            try:
                module.validate = lambda candidate, source: (_ for _ in ()).throw(ValueError("reject"))
                module.station_additions = lambda: []
                with self.assertRaises(ValueError):
                    module.main()
                self.assertFalse((base / "normalized").exists())
                module.validate = lambda candidate, source: None
                module.main()
                stops = read_jsonl(base / f"normalized/stop-times/{module.SUFFIX}/seeds.jsonl")
                self.assertTrue(stops)
                self.assertTrue(all(row["day_offset"] == 0 for row in stops))
                trip = read_jsonl(base / f"normalized/trips/{module.SUFFIX}/seeds.jsonl")[0]
                self.assertIn("operator and route lines unknown", trip["notes"])
            finally:
                module.BASE, module.validate, module.station_additions = original

    def _run_nex_main(self):
        module = load("normalize-reviewed-east-narita-express1-20260930.py")
        original = (module.BASE, module.ROOT, module.CANDIDATE)
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp) / "base"
            root = Path(tmp) / "root"
            (root / "app/public/rail").mkdir(parents=True)
            names = {stop[0] for trip in module.PINNED["trips"] for stop in trip["stops"]}
            (root / "app/public/rail/jp-2025.json").write_text(
                json.dumps(east_package(names, module.STATION_NAME_ALIASES), ensure_ascii=False),
                encoding="utf-8")
            candidate_path = base / "candidate.json"
            candidate_path.parent.mkdir(parents=True)
            module.BASE = base
            module.ROOT = root
            module.CANDIDATE = candidate_path
            try:
                candidate_path.write_text("{}", encoding="utf-8")
                with self.assertRaises(ValueError):
                    module.main()
                self.assertFalse((base / "normalized").exists())
                self.assertFalse((base / "sources").exists())
                candidate_path.write_text(json.dumps(module.PINNED, ensure_ascii=False), encoding="utf-8")
                forced = module.station_ids(module.PINNED["trips"])
                self.assertEqual(forced["東京"], "jp.n02.003766")
                self.assertEqual(forced["武蔵小杉"], "jp.n02.004301")
                module.main()
                stops = read_jsonl(base / f"normalized/stop-times/{module.SUFFIX}/seeds.jsonl")
                self.assertTrue(all(row["day_offset"] == 0 for row in stops))
                self.assertTrue(any(row["time_accuracy"] == "unknown" for row in stops))
                self.assertTrue(any(row["station_id"] == "jp.n02.003766" for row in stops))
                self.assertTrue(any(row["station_id"] == "jp.n02.004301" for row in stops))
                facts = read_jsonl(base / f"normalized/fact-completeness-{module.SUFFIX}.jsonl")
                self.assertTrue(any(row["dimension"] == "operator" and row["status"] == "unknown" for row in facts))
                self.assertTrue(any(row["dimension"] == "route_lines" and row["status"] == "unknown" for row in facts))
            finally:
                module.BASE, module.ROOT, module.CANDIDATE = original

    def _run_shinano_main(self):
        module = load("normalize-reviewed-central-shinano11-20260930.py")
        original = (
            module.BASE, module.CANDIDATE, module.validate_candidate,
            module.verify_existing_service_and_english_name, module.resolve_stations,
        )
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            candidate_path = base / "candidate.json"
            candidate_path.write_text(module.CANDIDATE.read_text(encoding="utf-8"), encoding="utf-8")
            candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
            names = {row["name_snapshot"] for row in candidate["trip"]["stop_times"]}
            stations = {
                name: {"station_id": f"jp.n02.{index:06d}", "name_snapshot": name}
                for index, name in enumerate(sorted(names), 1)
            }
            module.BASE = base
            module.CANDIDATE = candidate_path
            try:
                module.validate_candidate = lambda candidate_row: (_ for _ in ()).throw(ValueError("reject"))
                module.verify_existing_service_and_english_name = lambda: None
                module.resolve_stations = lambda: (stations, [])
                with self.assertRaises(ValueError):
                    module.main()
                self.assertFalse((base / "normalized").exists())
                module.validate_candidate = lambda candidate_row: None
                module.main()
                trip = read_jsonl(base / f"normalized/trips/{module.SUFFIX}/seeds.jsonl")[0]
                self.assertEqual(trip["direction"], candidate["trip"]["direction"])
                self.assertEqual(trip["origin_station_id"], stations[module.STAGING_FACTS["origin_name"]]["station_id"])
                self.assertEqual(trip["notes"], module.STAGING_FACTS["trip_notes"])
                stops = read_jsonl(base / f"normalized/stop-times/{module.SUFFIX}/seeds.jsonl")
                self.assertTrue(all(row["day_offset"] == 0 for row in stops))
            finally:
                (
                    module.BASE, module.CANDIDATE, module.validate_candidate,
                    module.verify_existing_service_and_english_name, module.resolve_stations,
                ) = original


if __name__ == "__main__":
    unittest.main()
