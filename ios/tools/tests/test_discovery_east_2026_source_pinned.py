"""Source-pinned checks for the independent JR East 2026 discovery batch."""
import json
from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "app/data/train-service-history"
SUFFIX = "discovery-east-2026"


def load_jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


class EastDiscoverySourcePinnedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(
            [sys.executable, str(ROOT / "ios/tools/normalize-reviewed-east-shiosai6-discovery.py")],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        cls.registry = load_jsonl(BASE / "sources/source-registry-discovery-east-2026.jsonl")
        cls.candidate = json.loads(
            (BASE / "candidates/jr-east-shiosai6-20260930-discovery.json").read_text()
        )
        cls.trips = load_jsonl(BASE / f"normalized/trips/{SUFFIX}/seeds.jsonl")
        cls.stops = load_jsonl(BASE / f"normalized/stop-times/{SUFFIX}/seeds.jsonl")
        cls.exceptions = load_jsonl(BASE / f"normalized/calendar-exceptions/{SUFFIX}/seeds.jsonl")
        cls.service_names = load_jsonl(BASE / f"normalized/service-name-periods-{SUFFIX}.jsonl")
        cls.completeness = load_jsonl(BASE / f"normalized/fact-completeness-{SUFFIX}.jsonl")

    def test_discovery_registry_has_many_official_sources_and_candid_limitations(self):
        self.assertGreaterEqual(len(self.registry), 20)
        self.assertTrue(all(row["publisher"].startswith("東日本旅客鉄道") for row in self.registry))
        self.assertTrue(all(row["automated_extraction_allowed"] is False for row in self.registry))
        inventory_notes = " ".join(row["notes"] for row in self.registry if row["source_type"] == "official_service_catalog")
        for name in [
            "成田エクスプレス", "しおさい", "ひたち", "ときわ", "草津・四万", "あかぎ",
            "日光", "きぬがわ", "あずさ", "かいじ", "富士回遊", "踊り子", "湘南",
            "わかしお", "さざなみ", "つがる", "スーパーつがる", "いなほ", "しらゆき",
            "サフィール踊り子",
        ]:
            self.assertIn(name, inventory_notes)
        unresolved = [row for row in self.registry if "remain" in row["notes"] or "未" in row["notes"]]
        self.assertGreaterEqual(len(unresolved), 8)

    def test_shiosai_source_url_hash_and_exact_date_are_pinned(self):
        source = next(row for row in self.registry if row["source_id"] == "jr-east-shiosai6-20260930-discovery")
        self.assertEqual(source["url_or_locator"], "https://timetables.jreast.co.jp/2610/train/095/098821.html")
        self.assertEqual(source["content_hash"], "sha256:2401bb8205ced0e15787bcf1139e0bfbee3ae7cbb8d45679c9660d778cc4eab8")
        self.assertEqual(self.candidate["trip"]["operating_dates"], ["2026-09-30"])
        self.assertEqual(self.exceptions, [{
            "calendar_id": "jr-east.shiosai.6.exact-2026-09-30.calendar",
            "exception_type": "add",
            "reason": "Exact calendar date marked td.ok on this schedule-variant page",
            "service_date": "2026-09-30",
            "source_id": "jr-east-shiosai6-20260930-discovery",
        }])

    def test_official_english_name_is_source_pinned_to_exact_period(self):
        source = next(row for row in self.registry if row["source_id"] == "jr-east-shiosai-official-english-20260929")
        self.assertEqual(
            source["url_or_locator"],
            "https://traininfo.jreast.co.jp/train_info/e/express.aspx?group=shiosai",
        )
        self.assertIn("labels the service as Shiosai", source["notes"])
        english = next(row for row in self.service_names if row["language"] == "en")
        self.assertEqual(english, {
            "language": "en",
            "name": "Shiosai",
            "name_type": "official_english",
            "service_id": "shiosai",
            "source_id": "jr-east-shiosai-official-english-20260929",
            "valid_from": "2026-09-30",
            "valid_until": "2026-10-01",
        })

    def test_shiosai_trip_preserves_complete_official_stop_table(self):
        self.assertEqual(len(self.trips), 1)
        trip = self.trips[0]
        self.assertEqual((trip["service_id"], trip["public_number"], trip["train_number"]), ("shiosai", "6", "4006M"))
        station_names = {}
        for path in (BASE / "normalized").glob("station-identities*.jsonl"):
            for row in load_jsonl(path):
                station_names[row["station_id"]] = row["name_snapshot"]
        ordered = sorted(self.stops, key=lambda row: row["stop_sequence"])
        self.assertEqual(
            [station_names[row["station_id"]] for row in ordered],
            ["佐倉", "四街道", "千葉", "船橋", "錦糸町", "東京"],
        )
        self.assertEqual((ordered[0]["departure_time"], ordered[-1]["arrival_time"]), ("07:04", "07:59"))
        status = {(row["entity_id"], row["dimension"]): row["status"] for row in self.completeness}
        for dimension in ("identity", "train_number", "validity_calendar", "origin_destination", "stops", "times", "station_refs"):
            self.assertEqual(status[(trip["trip_id"], dimension)], "verified")
        self.assertEqual(status[(trip["trip_id"], "operator")], "unknown")
        self.assertEqual(status[(trip["trip_id"], "route_lines")], "unknown")


if __name__ == "__main__":
    unittest.main()
