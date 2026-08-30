import importlib.util
import json
import os
import sys
import tempfile
import unittest
import zipfile


SCRIPT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), '..',
    'normalize-us-west-official-networks.py'))
sys.path.insert(0, os.path.dirname(SCRIPT))
LIB = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'lib'))
sys.path.insert(0, LIB)
SPEC = importlib.util.spec_from_file_location('west_official', SCRIPT)
west = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(west)
import na_provenance


def geojson_feature(line):
    if line == 'Blue':
        geometry = {'type': 'MultiLineString', 'coordinates': [
            [[-122.0, 37.0], [-121.99, 37.0]],
            [[-121.98, 37.0], [-121.97, 37.0]],
        ]}
    elif line == 'Green':
        geometry = {'type': 'LineString', 'coordinates': [
            [-122.01, 37.0], [-121.96, 37.0],
        ]}
    else:
        geometry = {'type': 'LineString',
                    'coordinates': [[-122.0, 37.0], [-121.9, 37.1]]}
    return {'type': 'Feature', 'properties': {'LineAbbr': line},
            'geometry': geometry}


class WesternOfficialNormalizationTests(unittest.TestCase):
    def test_vta_provenance_is_the_endpoint_that_produced_the_fixture(self):
        self.assertEqual(west.SOURCES['vta']['url'], (
            'https://gis.vta.org/gis/rest/services/LRT_BART/MapServer/6/'
            'query?where=1%3D1&outFields=*&returnGeometry=true&'
            'outSR=4326&f=geojson'))
        self.assertEqual(west.SOURCES['vta'], na_provenance.SOURCES['vta'])

    def make_sound_archive(self, directory):
        import shapefile
        layers = os.path.join(directory, 'layers')
        os.makedirs(layers)

        writer = shapefile.Writer(os.path.join(layers, 'LINKLine'))
        writer.field('OBJECTID', 'N')
        writer.field('LINK_TYPE', 'N')
        writer.field('DESCRIPTIO', 'C', 40)
        writer.field('STATUS', 'C', 30)
        writer.field('Shape_Leng', 'F')
        writer.field('LINE', 'C', 5)
        for index, description, status, line in (
                (1, 'Central Link', 'COMPLETE', '1'),
                (2, 'Federal Way Link', 'UNDER CONSTRUCTION', ''),
                (3, 'Hilltop Tacoma Link', 'COMPLETE', 'T'),
                (4, 'East Link', 'COMPLETE', '2')):
            writer.line([[[1_238_066.0 + index, 91_328.0],
                          [1_238_166.0 + index, 91_428.0]]])
            writer.record(index, index, description, status, 100.0, line)
        writer.close()

        writer = shapefile.Writer(os.path.join(layers, 'SNDRLine'))
        writer.field('OBJECTID', 'N')
        writer.field('STATUS', 'C', 30)
        writer.field('SEGMENT', 'C', 30)
        writer.field('Shape_Leng', 'F')
        for index, segment, status in (
                (1, 'Sounder North', 'OPERATIONAL'),
                (2, 'Sounder South', 'OPERATIONAL'),
                (3, 'Sounder South', 'PLANNED')):
            writer.line([[[1_238_066.0 + index, 91_328.0],
                          [1_238_166.0 + index, 91_428.0]]])
            writer.record(index, status, segment, 100.0)
        writer.close()

        for stem in ('LINKLine', 'SNDRLine'):
            with open(os.path.join(layers, f'{stem}.prj'), 'w') as output:
                output.write('NAD83 StatePlane Washington North')
        archive_path = os.path.join(directory, 'sound.zip')
        with zipfile.ZipFile(archive_path, 'w') as archive:
            for name in os.listdir(layers):
                archive.write(os.path.join(layers, name), name)
        return archive_path

    def test_stateplane_projection_matches_operator_file_control_point(self):
        longitude, latitude = west.washington_stateplane_to_wgs84(
            1_280_444.1539999992, 172_748.36100000143)
        self.assertAlmostEqual(longitude, -122.28868269, places=6)
        self.assertAlmostEqual(latitude, 47.46424879, places=6)

    def test_sound_filters_construction_and_non_operational_records(self):
        with tempfile.TemporaryDirectory() as directory:
            groups = west.sound_groups(self.make_sound_archive(directory))
        self.assertEqual(len(groups['sound-link-1']), 1)
        self.assertEqual(len(groups['sound-link-t']), 1)
        self.assertEqual(len(groups['sound-link-2']), 1)
        self.assertEqual(len(groups['sounder-north']), 1)
        self.assertEqual(len(groups['sounder-south']), 1)

    def test_vta_is_route_specific_and_does_not_import_bart_extension(self):
        raw = json.dumps({'type': 'FeatureCollection', 'features': [
            geojson_feature('Blue'), geojson_feature('Green'),
            geojson_feature('Orange'), geojson_feature('EBRC'),
        ]}).encode()
        groups = west.vta_groups(raw)
        self.assertEqual({key: len(value) for key, value in groups.items()}, {
            'vta-blue': 2, 'vta-green': 1, 'vta-orange': 1,
        })
        self.assertEqual(groups['vta-blue'][1]['properties']['sharedTrackFrom'],
                         'Green')

    def test_vta_refuses_unknown_line_instead_of_guessing(self):
        raw = json.dumps({'type': 'FeatureCollection', 'features': [
            geojson_feature('Blue'), geojson_feature('Green'),
            geojson_feature('Orange'), geojson_feature('Mystery'),
        ]}).encode()
        with self.assertRaisesRegex(SystemExit, 'unknown LineAbbr'):
            west.vta_groups(raw)

    def test_existing_manifest_entries_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = {
                'schemaVersion': 1,
                'sources': {'mta': {'publisher': 'MTA'}},
                'files': {'mta-subway-a': {'file': 'mta-subway-a.geojson'}},
            }
            with open(os.path.join(directory, 'manifest.json'), 'w') as output:
                json.dump(manifest, output)
            loaded = west._load_manifest(directory)
        self.assertIn('mta', loaded['sources'])
        self.assertIn('mta-subway-a', loaded['files'])

    def test_vta_routes_with_directional_detours_fail_closed(self):
        registry_path = os.path.abspath(os.path.join(
            os.path.dirname(__file__), '..', 'na-feeds.json'))
        with open(registry_path) as source:
            feeds = json.load(source)['feeds']
        vta = next(row for row in feeds
                   if row['slug'] == 'santa-clara-valley-transport')
        self.assertTrue({'Blue', 'Green'}.issubset(vta['excludeRoutes']))
        self.assertNotIn('Ornge', vta['excludeRoutes'])

    def test_normalized_routes_pass_shared_provenance_verifier(self):
        with tempfile.TemporaryDirectory() as directory:
            sound = self.make_sound_archive(directory)
            vta = os.path.join(directory, 'vta.geojson')
            with open(vta, 'w') as output:
                json.dump({'type': 'FeatureCollection', 'features': [
                    geojson_feature('Blue'), geojson_feature('Green'),
                    geojson_feature('Orange'), geojson_feature('EBRC'),
                ]}, output)
            output_dir = os.path.join(directory, 'official-networks')
            west.normalize(output_dir, sound, vta)
            keys = set(west.SOUND_KEYS + west.VTA_KEYS)
            verified, diagnostics = na_provenance.verify_route_networks(
                output_dir, keys)
        self.assertEqual(diagnostics, [])
        self.assertEqual(set(verified), keys)


if __name__ == '__main__':
    unittest.main()
