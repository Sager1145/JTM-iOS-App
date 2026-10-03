import importlib.util
import json
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'verify-na-station-english.py'
SPEC = importlib.util.spec_from_file_location('na_english_verification', SCRIPT)
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


class NorthAmericanEnglishVerificationTests(unittest.TestCase):
    def feature(self, stop_id='Stop-1', feed='test', operator='Operator', point=(-80, 40)):
        return {'properties': {'operator': operator, 'n02_group_code': 'us-official-test',
                'display_point': list(point), 'n02_station_code':
                f'US-{feed.upper()}-{VERIFY.slug(operator).upper()}-{stop_id}-US-OFFICIAL-TEST'}}

    def stop(self, stop_id, name, point=(-80, 40)):
        return {'stop_id': stop_id, 'stop_name': name,
                'stop_lon': str(point[0]), 'stop_lat': str(point[1])}

    def test_raw_capitalization_accents_and_whitespace_are_preserved(self):
        raw = b'stop_id, stop_name, stop_lat, stop_lon\nX,McCORMICK / S\xc3\xa3o  Paulo,40,-80\n'
        self.assertEqual(VERIFY.stop_rows(raw)['X']['stop_name'], 'McCORMICK / São  Paulo')

    def test_stop_id_parser_preserves_case_and_hyphens_and_requires_operator(self):
        props = self.feature()['properties']
        self.assertEqual(VERIFY.source_stop_id(props, 'us', 'test', 'Operator'), 'Stop-1')
        self.assertIsNone(VERIFY.source_stop_id(props, 'us', 'other', 'Operator'))
        self.assertIsNone(VERIFY.source_stop_id(props, 'us', 'test', 'Other'))
        self.assertIsNone(VERIFY.source_stop_id({**props, 'n02_group_code': ''}, 'us', 'test', 'Operator'))

    def test_retained_id_wins_over_nearby_bus_stop_or_display_name(self):
        source = {'Stop-1': self.stop('Stop-1', 'Official McCormick', (-80.001, 40)),
                  'nearby': self.stop('nearby', 'Wrong Nearby Label')}
        found, method, reason = VERIFY.match_stop(['us-official-test', 'Package Name', -80, 40],
            [self.feature()], source, 'us', 'test', 'Operator')
        self.assertEqual(found[0]['stop_name'], 'Official McCormick')
        self.assertEqual(method, 'retained-feed-operator-stop-id')
        self.assertIsNone(reason)

    def test_equal_name_elsewhere_never_matches(self):
        source = {'elsewhere': self.stop('elsewhere', 'Package Name', (-81, 40))}
        found, _, reason = VERIFY.match_stop(['us-official-test', 'Package Name', -80, 40],
            [], source, 'us', 'test', 'Operator')
        self.assertFalse(found)
        self.assertIn('no unique same-feed coordinate', reason)

    def test_ambiguous_coordinate_and_conflicting_source_ids_are_refused(self):
        source = {'a': self.stop('a', 'One'), 'b': self.stop('b', 'Two')}
        station = ['us-official-test', 'Package Name', -80, 40]
        self.assertFalse(VERIFY.match_stop(station, [], source, 'us', 'test', 'Operator')[0])
        found, _, reason = VERIFY.match_stop(station, [self.feature('a'), self.feature('b')],
                                             source, 'us', 'test', 'Operator')
        self.assertFalse(found)
        self.assertIn('conflicting', reason)

    def test_wmata_serialized_source_parser_preserves_id_and_exact_label(self):
        stop = {'__typename': 'Stop', 'gtfsId': 'WMATA_RAIL_BUS_GTFS_STATIC:STN_A01',
                'name': 'McPherson Sq & "Test"', 'lat': 38.9, 'lon': -77.0, 'stops': []}
        frame = [1, 'c:' + json.dumps(stop, separators=(',', ':'))]
        html = '<script nonce="abc">self.__next_f.push(' + json.dumps(frame) + ')</script>'
        row = VERIFY.website_stop_rows(html)['STN_A01']
        self.assertEqual(row['stop_name'], stop['name'])
        self.assertEqual(row['stop_lon'], '-77.0')

    def test_rail_coordinate_fallback_excludes_nearby_bus_platform(self):
        source = {'bus': self.stop('bus', 'Bus Platform'),
                  'rail': self.stop('rail', 'DDTC Rail', (-80.0002, 40))}
        station = ['us-official-test', 'Downtown Denton Transit Center', -80, 40]
        found, method, _ = VERIFY.match_stop(station, [], source, 'us', 'test', 'Operator',
                                           50, ['rail'])
        self.assertEqual(found[0]['stop_id'], 'rail')
        self.assertEqual(method, 'unique-rail-stop-in-same-feed-within-50m')

    def test_smart_evidence_requires_exact_heading_and_retains_map_semantics(self):
        snapshot = VERIFY.read(VERIFY.OUTPUT)
        smart = [row for row in snapshot['byLineStation'].values()
                 if row['lineId'].startswith('smart-')]
        self.assertEqual(len(smart), 14)
        for row in smart:
            for evidence in row['identityEvidence']:
                self.assertEqual(evidence['originalPublishedName'].removeprefix('SMART '), row['en'])
                location = evidence['locationEvidence']
                self.assertIn('viewport', location['semantics'])
                self.assertLessEqual(location['nearestStationMeters'], 500)
                self.assertGreater(location['secondNearestStationMeters'], 500)

    def test_saved_snapshot_covers_every_package_membership_once(self):
        snapshot = VERIFY.read(VERIFY.OUTPUT)
        identities = set(snapshot['byLineStation'])
        pending = {row['lineId'] + ':' + row['stationCode'] for row in snapshot['unresolved']}
        self.assertFalse(identities & pending)
        for country in VERIFY.COUNTRIES:
            package = VERIFY.read(VERIFY.APP / f'public/rail/{country}-2025.json')
            memberships = {line['id'] + ':' + station[0] for line in package['lines']
                           for station in line['stations']}
            self.assertEqual(memberships, {key for key in identities | pending
                if key in memberships})
            for line in package['lines']:
                for station in line['stations']:
                    row = snapshot['byLineStation'].get(line['id'] + ':' + station[0])
                    if row:
                        self.assertEqual(row['operator'], line['operator'])
                        self.assertEqual(row['name'], station[1])
                        self.assertTrue(row['source'].startswith('https://'))
                        for evidence in row['identityEvidence']:
                            self.assertEqual(evidence['publishedName'], row['en'])
                            self.assertEqual(len(evidence['sha256']), 64)
                            self.assertTrue(evidence['retrievedAt'])


if __name__ == '__main__':
    unittest.main()
