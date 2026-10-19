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




if __name__ == '__main__':
    unittest.main()
