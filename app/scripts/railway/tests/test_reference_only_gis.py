import json
import os
import sys
import unittest


HERE = os.path.dirname(os.path.abspath(__file__))
RAILWAY = os.path.abspath(os.path.join(HERE, '..'))
ROOT = os.path.abspath(os.path.join(RAILWAY, '..', '..', '..'))
sys.path.insert(0, RAILWAY)


class ReferenceOnlyGISTests(unittest.TestCase):
    def test_restricted_cache_is_explicitly_ignored(self):
        with open(os.path.join(ROOT, '.gitignore'), encoding='utf-8') as source:
            ignored = source.read()
        self.assertIn('.local/railway-reference-only/', ignored)

    def test_sound_transit_restricted_gis_cannot_enter_release_manifest(self):
        from lib import na_provenance

        self.assertNotIn('sound-transit', na_provenance.SOURCES)
        self.assertNotIn('sound-transit',
                         set(na_provenance.KEY_SOURCE_PREFIXES.values()))
        self.assertNotIn('sound-transit',
                         set(na_provenance.KEY_SOURCE_EXACT.values()))

    def test_sound_transit_uses_gtfs_or_stays_blocked(self):
        with open(os.path.join(RAILWAY, 'na-feeds.json'),
                  encoding='utf-8') as source:
            feed = next(row for row in json.load(source)['feeds']
                        if row['slug'] == 'sound-transit')
        self.assertNotIn('officialNetworkByRouteId', feed)
        self.assertEqual(set(feed['blockedRouteIds']),
                         {'100479', '2LINE', 'SNDR_TL'})
        self.assertEqual(set(feed['referenceValidatedGeometryByRouteId']),
                         {'SNDR_EV', 'TLINE'})

    def test_reproducible_rebuild_never_downloads_restricted_sound_gis(self):
        with open(os.path.join(RAILWAY, 'rebuild-na-official-networks.sh'),
                  encoding='utf-8') as source:
            script = source.read()
        self.assertNotIn('raw sound-transit', script)
        self.assertNotIn('--sound-input', script)


if __name__ == '__main__':
    unittest.main()
