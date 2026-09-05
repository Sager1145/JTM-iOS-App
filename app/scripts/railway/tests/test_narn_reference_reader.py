import gzip
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "measure-display-blocked-intervals.py"
SPEC = importlib.util.spec_from_file_location("measure_display_blocked_intervals", SCRIPT)
measure = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(measure)


def write_page(root: Path, name: str, records: list) -> None:
    """Write a synthetic NARN page: a bare gzipped JSON LIST of records,
    not a GeoJSON FeatureCollection — the exact on-disk shape this
    project's staged NARN uses."""
    path = root / name
    with gzip.open(path, "wt", encoding="utf-8") as fh:
        json.dump(records, fh)


class NarnReferenceReaderTests(unittest.TestCase):
    def test_reads_main_track_and_drops_service_track(self):
        """A synthetic 2-record page: one NET=M (main) arc that should
        become a reference way, and one NET=S (siding) arc that should be
        dropped the same way `load_osm_ways` drops EXCLUDE_SERVICE ways."""
        records = [
            {
                "p": {
                    "FRAARCID": 1, "STATEAB": "CA", "COUNTRY": "US",
                    "RROWNER1": "UP", "SUBDIV": "TESTSUB", "NET": "M",
                },
                "c": [[-121.5, 38.5], [-121.4, 38.6], [-121.3, 38.7]],
            },
            {
                "p": {
                    "FRAARCID": 2, "STATEAB": "CA", "COUNTRY": "US",
                    "RROWNER1": "UP", "SUBDIV": "YARDLEAD", "NET": "S",
                },
                "c": [[-121.5, 38.5], [-121.51, 38.51]],
            },
        ]
        with tempfile.TemporaryDirectory() as root:
            root_path = Path(root)
            write_page(root_path, "page-0000000.json.gz", records)

            ways, page_count = measure.load_narn_ways(root_path)

        self.assertEqual(page_count, 1)
        self.assertEqual(len(ways), 1, "the NET=S siding record must be dropped")
        way = ways[0]
        self.assertEqual(way["id"], 1)
        self.assertEqual(way["tags"]["NET"], "M")
        self.assertEqual(
            way["coords"],
            [(-121.5, 38.5), (-121.4, 38.6), (-121.3, 38.7)])
        self.assertEqual(
            way["bbox"], (-121.5, 38.5, -121.3, 38.7))

    def test_keeps_record_with_no_net_field(self):
        """A record with no NET key at all is kept — there is nothing to
        filter on, so it is not treated as service track."""
        records = [
            {
                "p": {"FRAARCID": 7, "STATEAB": "NY", "COUNTRY": "US"},
                "c": [[-73.9, 42.6], [-73.8, 42.7]],
            },
        ]
        with tempfile.TemporaryDirectory() as root:
            root_path = Path(root)
            write_page(root_path, "page-0000000.json.gz", records)

            ways, _ = measure.load_narn_ways(root_path)

        self.assertEqual(len(ways), 1)

    def test_handles_nested_coordinate_lists(self):
        """`c` is documented as a coordinate list OR a list of coordinate
        lists. A nested record must split into one way per sub-line rather
        than being silently dropped or mis-parsed as flat coordinates."""
        records = [
            {
                "p": {"FRAARCID": 3, "NET": "M"},
                "c": [
                    [[-100.0, 40.0], [-100.1, 40.1]],
                    [[-100.2, 40.2], [-100.3, 40.3], [-100.4, 40.4]],
                ],
            },
        ]
        with tempfile.TemporaryDirectory() as root:
            root_path = Path(root)
            write_page(root_path, "page-0000000.json.gz", records)

            ways, _ = measure.load_narn_ways(root_path)

        self.assertEqual(len(ways), 2)
        self.assertEqual(ways[0]["id"], "3#0")
        self.assertEqual(ways[1]["id"], "3#1")
        self.assertEqual(len(ways[1]["coords"]), 3)

    def test_narn_ways_feed_measure_against_like_osm_ways(self):
        """The whole point of matching load_osm_ways's return shape: a
        NARN way set must work with the same measure_against() the OSM
        path uses, with no reference-specific branching in the metric."""
        records = [
            {"p": {"FRAARCID": i, "NET": "M"},
             "c": [[-100.0, 40.0 + i * 0.001], [-100.0, 40.001 + i * 0.001]]}
            for i in range(4)
        ]
        with tempfile.TemporaryDirectory() as root:
            root_path = Path(root)
            write_page(root_path, "page-0000000.json.gz", records)
            ways, _ = measure.load_narn_ways(root_path)

        coords = [(-100.0, 40.0), (-100.0, 40.002)]
        result, relevant = measure.measure_against(coords, ways, limit_m=50.0)
        self.assertIsNotNone(result, "4 candidate ways should clear MIN_WAYS_FOR_D")
        self.assertGreaterEqual(result["wayCount"], measure.MIN_WAYS_FOR_D)


if __name__ == "__main__":
    unittest.main()
