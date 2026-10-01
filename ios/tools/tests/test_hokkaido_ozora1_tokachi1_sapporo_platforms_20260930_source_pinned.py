"""Exact-date Sapporo platforms in the first two official s=130 columns."""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
sys.path.insert(0, str(ROOT / "ios/tools"))
import train_timetable as timetable

DAY = "2026-09-30"
URL = "https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=130"
SUFFIX = "reviewed-hokkaido-ozora1-tokachi1-platforms-20260930"
EXPECTED = (
    ("jr-hokkaido.ozora.1.2026-09-30", "4001D", "6:48", "(6)",
     "jr-hokkaido-ozora1-20260930-timetable"),
    ("jr-hokkaido.tokachi.1.2026-09-29-30", "31D", "7:58", "(8)",
     "jr-hokkaido-tokachi1-20260930-timetable"),
)


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()]


class HokkaidoFirstS130PlatformsTests(unittest.TestCase):
    def test_official_source_and_platform_only_overrides(self):
        candidate = json.loads((BASE / "candidates/jr-hokkaido-ozora1-tokachi1-sapporo-platforms-20260930.json")
                               .read_text(encoding="utf-8"))
        overrides = rows(BASE / f"normalized/trip-stop-time-overrides/{SUFFIX}/seeds.jsonl")
        facts = rows(BASE / f"normalized/fact-sources-{SUFFIX}.jsonl")
        self.assertEqual((candidate["candidate_status"], candidate["canonical"],
                          candidate["service_date"], candidate["source_url"]),
                         ("visually_reviewed_official_exact_date", False, DAY, URL))
        self.assertEqual(len(candidate["platforms"]), len(overrides), 2)
        self.assertEqual(len(facts), 2)
        for reviewed, override, fact, expected in zip(candidate["platforms"], overrides,
                                                      facts, EXPECTED):
            trip_id, train_number, departure, platform, source_id = expected
            self.assertEqual((reviewed["trip_id"], reviewed["train_number"],
                              reviewed["station_name"], reviewed["stop_sequence"],
                              reviewed["departure_time"], reviewed["platform"],
                              reviewed["source_id"]),
                             (trip_id, train_number, "札幌", 1, departure, platform, source_id))
            self.assertEqual(override,
                             {"trip_id": trip_id, "service_date": DAY, "stop_sequence": 1,
                              "platform_override_present": 1, "platform_override": platform,
                              "source_id": source_id})
            self.assertEqual((fact["entity_type"], fact["entity_id"], fact["field_name"],
                              fact["source_id"], fact["confidence"],
                              fact["verification_status"]),
                             ("stop_time", f"{trip_id}:1", "platform", source_id, "high",
                              "verified"))
            self.assertIn(f"{train_number} 番線 row / 札幌 {departure}発: {platform}",
                          fact["page_or_locator"])

    def test_materialized_date_keeps_existing_clocks(self):
        manifest = timetable.load_manifest(BASE)
        data, origins = timetable.load_dataset(BASE, manifest)
        self.assertFalse(timetable.validate_dataset(data, origins, manifest))
        sources = {row["source_id"]: row for row in data["source_documents"]}
        selected = {row["trip_id"]: row for row in timetable.materialize(data, DAY)}
        previous = {row["trip_id"]: row for row in timetable.materialize(data, "2026-09-29")}
        station_names = {row["station_id"]: row["name_snapshot"]
                         for row in data["station_identities"]}
        for trip_id, train_number, departure, platform, source_id in EXPECTED:
            with self.subTest(train=train_number):
                source = sources[source_id]
                self.assertEqual((source["url_or_locator"], source["effective_date"]),
                                 (URL, DAY))
                trip = selected[trip_id]
                stop = trip["stop_times"][0]
                self.assertEqual((trip["train_number"], station_names[stop["station_id"]],
                                  stop["arrival_time"], stop["departure_time"],
                                  stop["platform"]),
                                 (train_number, "札幌", None, departure, platform))
        self.assertNotIn(EXPECTED[0][0], previous)
        previous_tokachi = previous[EXPECTED[1][0]]["stop_times"][0]
        self.assertEqual((previous_tokachi["departure_time"], previous_tokachi.get("platform")),
                         ("7:58", None))


if __name__ == "__main__":
    unittest.main()
