"""Exact-date, source-pinned checks for Inaho 9 and Shirayuki 1."""

import json
import sys
import unittest
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import train_timetable as timetable


BASE = TOOLS.parents[1] / "app/data/train-service-history"
SUFFIX = "east-inaho9-shirayuki1-20260930"
EXPECTED = {
    "jr-east.inaho.9.exact-2026-09-30": {
        "number": "9M",
        "equipment": ["グリーン車指定席", "普通車一部指定席"],
        "stops": [
            ("新潟", None, "17:58", "５"), ("豊栄", "18:11", "18:11", None),
            ("新発田", "18:21", "18:22", "１"), ("中条", "18:31", "18:31", None),
            ("坂町", "18:37", "18:38", "３"), ("村上", "18:46", "18:47", "３"),
            ("府屋", "19:18", "19:19", None), ("あつみ温泉", "19:30", "19:31", None),
            ("鶴岡", "19:51", "19:51", None), ("余目", "20:01", "20:02", "２"),
            ("酒田", "20:10", None, "１"),
        ],
        "formation": (False, True),
    },
    "jr-east.shirayuki.1.exact-2026-09-30": {
        "number": "51M",
        "equipment": ["普通車一部指定席"],
        "stops": [
            ("新井", None, "10:23", None), ("上越妙高", "10:30", "10:31", None),
            ("高田", "10:35", "10:36", None), ("春日山", "10:40", "10:40", None),
            ("直江津", "10:46", "10:48", "６"), ("柿崎", "10:59", "11:00", None),
            ("柏崎", "11:14", "11:15", "２"), ("長岡", "11:39", "11:40", "２"),
            ("見附", "11:49", "11:49", None), ("東三条", "11:57", "11:58", "１"),
            ("加茂", "12:04", "12:05", None), ("新津", "12:18", "12:18", "４"),
            ("新潟", "12:30", None, "３"),
        ],
        "formation": (False, None),
    },
}


def rows(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


class ExactDateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = json.loads((BASE / "candidates/jr-east-inaho9-shirayuki1-20260930.json").read_text())
        cls.data, _ = timetable.load_dataset(BASE, timetable.load_manifest(BASE))
        cls.day = {trip["trip_id"]: trip for trip in timetable.materialize(cls.data, "2026-09-30")}
        cls.names = {row["station_id"]: row["name_snapshot"] for row in cls.data["station_identities"]}

    def test_published_calls_clocks_platforms_and_numbers(self):
        candidates = {trip["trip_id"]: trip for trip in self.candidate["trips"]}
        for trip_id, expected in EXPECTED.items():
            candidate = candidates[trip_id]
            trip = self.day[trip_id]
            self.assertEqual(trip["train_number"], expected["number"])
            self.assertEqual(candidate["printed_equipment"], expected["equipment"])
            self.assertEqual(candidate["calendar_observation"], {"month": "2026年9月", "day": 30, "cell_class": "ok"})
            actual = [
                (self.names[stop["station_id"]], stop["arrival_time"], stop["departure_time"], stop["platform"])
                for stop in trip["stop_times"]
            ]
            self.assertEqual(actual, expected["stops"])

    def test_source_hashes_are_registry_pinned(self):
        sources = {row["source_id"]: row for row in rows(BASE / "sources/source-registry-national-family-gap-audit-20260930.jsonl")}
        for candidate in self.candidate["trips"]:
            source = sources[candidate["source_id"]]
            self.assertEqual(source["url_or_locator"], candidate["source_url"])
            self.assertEqual(source["content_hash"], "sha256:" + candidate["source_sha256"])

    def test_formation_is_planned_printed_equipment_only(self):
        for trip_id, expected in EXPECTED.items():
            formation = next(row for row in self.data["trip_formations"] if row["trip_id"] == trip_id)
            self.assertEqual(formation["evidence_kind"], "planned")
            self.assertEqual((formation["all_reserved"], formation["green_car_available"]), expected["formation"])
            self.assertIsNone(formation["car_count"])
            self.assertIsNone(formation["vehicle_series"])
            self.assertIsNone(formation["reserved_seat_capacity"])
            self.assertIn("actual dispatch unknown", formation["notes"])

    def test_route_operator_and_actual_dispatch_remain_unknown(self):
        candidates = {trip["trip_id"]: trip for trip in self.candidate["trips"]}
        for trip_id in EXPECTED:
            self.assertIsNone(candidates[trip_id]["actual_dispatch"])
            self.assertFalse([row for row in self.data["trip_line_segments"] if row["trip_id"] == trip_id])
            self.assertFalse([row for row in self.data["trip_operator_segments"] if row["trip_id"] == trip_id])
            states = {
                row["dimension"]: row["status"]
                for row in self.data["fact_completeness"]
                if row["entity_id"] == trip_id
            }
            self.assertEqual(states["route_lines"], "unknown")
            self.assertEqual(states["operator"], "unknown")

    def test_shirayuki_printed_remark_is_retained_without_segment_inference(self):
        remark = "えちごトキめき鉄道線内相互間のみの指定席特急券は発売いたしません"
        candidate = next(trip for trip in self.candidate["trips"] if trip["service_id"] == "shirayuki")
        self.assertEqual(candidate["printed_remarks"], remark)
        normalized = next(trip for trip in self.data["trips"] if trip["trip_id"] == candidate["trip_id"])
        self.assertIn(remark, normalized["notes"])

    def test_exact_service_day_only(self):
        trip_ids = set(EXPECTED)
        for service_date in ["2026-09-29", "2026-10-01"]:
            materialized = {trip["trip_id"] for trip in timetable.materialize(self.data, service_date)}
            self.assertFalse(trip_ids & materialized)


if __name__ == "__main__":
    unittest.main()
