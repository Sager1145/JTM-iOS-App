import importlib.util
import gzip
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path


SCRIPT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
LIB_DIR = os.path.join(SCRIPT_DIR, 'lib')
sys.path.insert(0, LIB_DIR)
import na_osm  # noqa: E402


def load_script(name):
    path = os.path.join(SCRIPT_DIR, name)
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), path)
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, SCRIPT_DIR)
    try:
        spec.loader.exec_module(module)
    finally:
        sys.path.pop(0)
    return module


SUCCESS = b'{"elements":[]}' + b' ' * 200


class Responses:
    def __init__(self, responses):
        self.responses = iter(responses)
        self.calls = 0

    def get(self, *args, **kwargs):
        self.calls += 1
        return next(self.responses)


class OsmTileCompletionTests(unittest.TestCase):
    def test_complete_parent_cache_is_reused_by_its_exact_bounds(self):
        for name in (
                'download-north-america-osm-inventory.py',
                'download-north-america-osm-crosscheck.py'):
            with self.subTest(script=name), tempfile.TemporaryDirectory() as directory:
                module = load_script(name)
                tile = (0, 0, 1, 1)
                self.assertNotEqual(module.tile_name(tile),
                                    module.tile_name(module.quarters(tile)[0]))
                client = Responses([SUCCESS])
                self.assertEqual(module.fetch_tile(client, tile, directory, max_depth=1), 1)
                self.assertEqual(client.calls, 1)
                cached = Responses([])
                self.assertEqual(module.fetch_tile(cached, tile, directory, max_depth=1), 1)
                self.assertEqual(cached.calls, 0, "A complete parent should be reused.")

    def test_retry_does_not_treat_a_cached_quarter_as_its_parent(self):
        for name in (
                'download-north-america-osm-inventory.py',
                'download-north-america-osm-crosscheck.py'):
            with self.subTest(script=name), tempfile.TemporaryDirectory() as directory:
                module = load_script(name)
                tile = (0, 0, 1, 1)
                partial = Responses([None, SUCCESS, None, SUCCESS, SUCCESS])
                self.assertEqual(module.fetch_tile(partial, tile, directory, max_depth=1), 0)
                self.assertEqual(partial.calls, 5)

                retry = Responses([None, SUCCESS])
                self.assertEqual(module.fetch_tile(retry, tile, directory, max_depth=1), 1)
                self.assertEqual(
                    retry.calls, 2,
                    "Retry must request the parent and the missing quarter.")

                complete_quarters = Responses([None])
                self.assertEqual(module.fetch_tile(
                    complete_quarters, tile, directory, max_depth=1), 1)
                self.assertEqual(
                    complete_quarters.calls, 1,
                    "Completed child caches should be reused after the parent retry fails.")

    def test_parent_is_incomplete_when_any_quarter_fails(self):
        for name in (
                'download-north-america-osm-inventory.py',
                'download-north-america-osm-crosscheck.py'):
            with self.subTest(script=name), tempfile.TemporaryDirectory() as directory:
                module = load_script(name)
                client = Responses([None, SUCCESS, None, None, None])
                self.assertEqual(module.fetch_tile(client, (0, 0, 1, 1), directory,
                                      max_depth=1), 0)
                self.assertEqual(client.calls, 5)


def write_tile(directory, name, ways):
    path = Path(directory) / name
    body = json.dumps({'elements': ways}).encode()
    if name.endswith('.gz'):
        path.write_bytes(gzip.compress(body))
    else:
        path.write_bytes(body)
    return path


def way(way_id, kind, y=0.0):
    return {
        'type': 'way', 'id': way_id, 'tags': {'railway': kind},
        'geometry': [{'lon': 0.0, 'lat': y}, {'lon': 1.0, 'lat': y}],
    }


class OsmTileSelectionTests(unittest.TestCase):
    def setUp(self):
        self.measure = load_script('measure-display-blocked-intervals.py')

    def test_legacy_only_cache_remains_readable(self):
        with tempfile.TemporaryDirectory() as directory:
            write_tile(directory, 'tile-+000.000+0000.000.json.gz',
                       [way(1, 'rail')])

            track = na_osm.Track().load_dir(directory)
            measured, tiles = self.measure.load_osm_ways(Path(directory))

            self.assertEqual((track.tiles, track.way_count, track.kinds),
                             (1, 1, ['rail']))
            self.assertEqual((tiles, [item['id'] for item in measured]),
                             (1, [1]))

    def test_current_cache_generation_excludes_legacy_files(self):
        with tempfile.TemporaryDirectory() as directory:
            write_tile(directory, 'tile-+000.000+0000.000.json.gz',
                       [way(1, 'rail', 0.0)])
            write_tile(
                directory,
                'tile-+000.00000_+0000.00000_+001.00000_+0001.00000.json.gz',
                [way(2, 'light_rail', 1.0)])

            track = na_osm.Track().load_dir(directory)
            measured, tiles = self.measure.load_osm_ways(Path(directory))

            self.assertEqual((track.tiles, track.way_count, track.kinds),
                             (1, 1, ['light_rail']))
            self.assertEqual((tiles, [item['id'] for item in measured]),
                             (1, [2]))

    def test_split_children_are_used_until_complete_parent_exists(self):
        with tempfile.TemporaryDirectory() as directory:
            module = load_script('download-north-america-osm-crosscheck.py')
            parent = (0, 0, 1, 1)
            for index, child in enumerate(module.quarters(parent), start=1):
                write_tile(directory, module.tile_name(child),
                           [way(index, 'rail', index / 10)])

            split = na_osm.Track().load_dir(directory)
            self.assertEqual((split.tiles, split.way_count), (4, 4))
            split_measured, split_tiles = self.measure.load_osm_ways(
                Path(directory))
            self.assertEqual((split_tiles, len(split_measured)), (4, 4))

            write_tile(directory, module.tile_name(parent),
                       [way(99, 'subway', 0.5)])
            complete = na_osm.Track().load_dir(directory)
            self.assertEqual((complete.tiles, complete.way_count, complete.kinds),
                             (1, 1, ['subway']))
            complete_measured, complete_tiles = self.measure.load_osm_ways(
                Path(directory))
            self.assertEqual(
                (complete_tiles, [item['id'] for item in complete_measured]),
                (1, [99]))

    def test_newest_copy_of_same_way_wins_across_effective_tiles(self):
        with tempfile.TemporaryDirectory() as directory:
            first = write_tile(
                directory,
                'tile-+000.00000_+0000.00000_+001.00000_+0001.00000.json.gz',
                [way(7, 'rail', 0.0)])
            second = write_tile(
                directory,
                'tile-+000.00000_+0001.00000_+001.00000_+0002.00000.json.gz',
                [way(7, 'tram', 2.0)])
            now = time.time_ns()
            os.utime(first, ns=(now - 2_000_000, now - 2_000_000))
            os.utime(second, ns=(now, now))

            track = na_osm.Track().load_dir(directory)
            measured, tiles = self.measure.load_osm_ways(Path(directory))

            self.assertEqual((track.tiles, track.way_count, track.kinds),
                             (2, 1, ['tram']))
            self.assertEqual((tiles, len(measured), measured[0]['id']),
                             (2, 1, 7))
            self.assertEqual(measured[0]['coords'][0], (0.0, 2.0))


if __name__ == '__main__':
    unittest.main()
