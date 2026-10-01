import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'history'))
import temporal_source as source


def event():
    return {'id': 'jp.test', 'kind': 'suspension', 'line': 'L', 'operator': 'O',
            'date_precision': 'exact_day', 'review': {'status': 'verified'},
            'corridor_id': 'c', 'alignment_id': 'a', 'service_identity_id': 's',
            'evidence': [{'authority': 'operator', 'reference': 'https://example.test/history',
                          'date_precision': 'exact_day'}],
            'geometry': {'source': 'N02', 'licence_status': 'redistributable'},
            'service_periods': [['1980-01-01', '2011-03-11'], ['2014-04-01', '2016-08-01'],
                                ['2020-03-14', None]],
            'infrastructure_periods': [['1980-01-01', None]]}


def fixtures():
    return ([{'type': 'Feature', 'properties': {'N02_003': 'L', 'N02_004': 'O'},
              'geometry': {'type': 'LineString', 'coordinates': [[139, 35], [139.1, 35]]}}],
            [{'type': 'Feature', 'properties': {'line_name': 'L', 'operator': 'O', 'station_name': 'S'},
             'geometry': {'type': 'Point', 'coordinates': [139, 35]}}])


def historical_transfer_event():
    e = event()
    e.update(kind='operator_transfer', date='2015-03-14',
             before={'line': 'Old L', 'operator': 'JR'},
             after={'line': 'L', 'operator': 'O'})
    e.pop('service_periods')
    e.pop('infrastructure_periods')
    proof = {'authority': 'city', 'reference': 'https://example.test/relocation',
             'date_precision': 'exact_day'}
    e['geometry']['selector'] = {'scope': 'whole_identity'}
    e['geometry']['historical_periods'] = [
        {'service_period': [None, '2014-10-19'], 'source': 'N02', 'release': 'N02-13',
         'licence_status': 'redistributable', 'alignment_id': 'old-site',
         'historical_identity': {'line': 'Old L', 'operator': 'JR'},
         'selector': {'historical_bbox': [138, 36, 139, 37]}, 'evidence': [proof]},
        {'service_period': ['2014-10-19', '2015-03-14'], 'source': 'N02', 'release': 'N02-14',
         'licence_status': 'redistributable', 'alignment_id': 'new-site',
         'historical_identity': {'line': 'Old L', 'operator': 'JR'},
         'selector': {'historical_bbox': [138, 36, 139, 37]}, 'evidence': [proof]},
    ]
    return e


class SourceTests(unittest.TestCase):
    def test_surveyed_predecessor_periods_cover_relocation_then_transfer(self):
        e = historical_transfer_event()
        old_section = {'type': 'Feature', 'properties': {'N02_003': 'Old L', 'N02_004': 'JR'},
                       'geometry': {'type': 'LineString', 'coordinates': [[138.1, 36.1], [138.2, 36.2]]}}
        stable_station = {'type': 'Feature', 'properties': {
            'line_name': 'Old L', 'operator': 'JR', 'station_name': 'Stable',
            'n02_station_code': '000001'}, 'geometry': {'type': 'Point', 'coordinates': [138.1, 36.1]}}
        moved_station = copy.deepcopy(stable_station)
        moved_station['properties'].update(station_name='Moved', n02_station_code='000002')
        moved_station['geometry']['coordinates'] = [138.15, 36.15]
        new_section = copy.deepcopy(old_section)
        new_section['geometry']['coordinates'][1] = [138.21, 36.21]
        new_moved_station = copy.deepcopy(moved_station)
        new_moved_station['geometry']['coordinates'] = [138.16, 36.16]
        e['geometry']['historical_periods'][0].update(
            historical_sections=[old_section],
            historical_stations=[stable_station, moved_station])
        e['geometry']['historical_periods'][1].update(
            historical_sections=[new_section],
            historical_stations=[copy.deepcopy(stable_station), new_moved_station])

        compiled = source.compile_event(e, *fixtures())
        self.assertEqual([f['properties']['service_validity'] for f in compiled['sections']],
                         [[None, '2014-10-19'], ['2014-10-19', '2015-03-14']])
        self.assertEqual(compiled['sections'][0]['geometry'], old_section['geometry'])
        self.assertEqual(compiled['sections'][1]['geometry'], new_section['geometry'])
        self.assertEqual(len(compiled['retirements']), 2)
        self.assertTrue(all(r['valid_from'] == '2015-03-14' for r in compiled['retirements']))
        by_name = {}
        for feature in compiled['stations']:
            by_name.setdefault(feature['properties']['station_name'], []).append(feature)
        stable_ids = [f['properties']['history_id'] for f in by_name['Stable']]
        self.assertEqual(stable_ids[0].rsplit('.period', 1)[0], stable_ids[1].rsplit('.period', 1)[0])
        moved_ids = [f['properties']['history_id'] for f in by_name['Moved']]
        self.assertNotEqual(moved_ids[0].rsplit('.period', 1)[0], moved_ids[1].rsplit('.period', 1)[0])
        self.assertEqual({f['properties']['n02_station_code'] for f in compiled['stations']},
                         {'000001', '000002'})
        self.assertTrue(compiled['stations'][0]['properties']['source'].startswith('N02-13; '))

    def test_historical_periods_must_exactly_partition_predecessor_service(self):
        changes = [
            (0, [None, '2014-10-18']),
            (1, ['2014-10-18', '2015-03-14']),
            (1, ['2014-10-19', '2015-03-15']),
            (0, ['2010-01-01', '2014-10-19']),
        ]
        for index, pair in changes:
            with self.subTest(index=index, pair=pair):
                e = historical_transfer_event()
                e['geometry']['historical_periods'][index]['service_period'] = pair
                with self.assertRaises(ValueError):
                    source.validate(e)

    def test_historical_period_requires_its_own_exact_day_evidence(self):
        e = historical_transfer_event()
        e['geometry']['historical_periods'][0].pop('evidence')
        with self.assertRaisesRegex(ValueError, 'exact-day evidence'):
            source.validate(e)

    def test_surveyed_period_inherits_code_before_stable_id_hash(self):
        e = historical_transfer_event()
        old_section = {'type': 'Feature', 'properties': {'N02_003': 'Old L', 'N02_004': 'JR'},
                       'geometry': {'type': 'LineString', 'coordinates': [[139, 35], [139.1, 35]]}}
        old_station = {'type': 'Feature', 'properties': {
            'line_name': 'Old L', 'operator': 'JR', 'station_name': 'S'},
            'geometry': {'type': 'Point', 'coordinates': [139, 35]}}
        for period in e['geometry']['historical_periods']:
            period['historical_sections'] = [copy.deepcopy(old_section)]
            period['historical_stations'] = [copy.deepcopy(old_station)]
        sections, stations = fixtures()
        stations[0]['properties']['n02_station_code'] = '001602'
        stations[0]['properties']['n02_group_code'] = '001602'
        compiled = source.compile_event(e, sections, stations)
        self.assertEqual([f['properties']['n02_station_code'] for f in compiled['stations']],
                         ['001602', '001602'])
        self.assertTrue(all(f['properties']['station_code_basis'] == 'exact_current_geometry_identity'
                            for f in compiled['stations']))
        bases = [f['properties']['history_id'].rsplit('.period', 1)[0]
                 for f in compiled['stations']]
        self.assertEqual(bases[0], bases[1])

    def test_nonperiod_station_history_id_keeps_legacy_full_feature_hash(self):
        e = event()
        e.update(kind='operator_transfer', date='2015-01-01', valid_from='1980-01-01',
                 before={'line': 'Old', 'operator': 'Old O'},
                 after={'line': 'L', 'operator': 'O'})
        feature = fixtures()[1][0]
        expected = source.variant(e, feature, ['1980-01-01', '2015-01-01'],
                                  'stations', 0, e['before'])
        stripped = copy.deepcopy(feature)
        token = source.hashlib.sha256(source.json.dumps(
            stripped, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]
        self.assertEqual(expected['properties']['history_id'],
                         f"{e['id']}.period0.stations.{token}")

    def test_historical_periods_are_identity_only_and_not_mixed_with_flat_geometry(self):
        e = historical_transfer_event()
        e['geometry']['historical_sections'] = []
        with self.assertRaisesRegex(ValueError, 'flat historical geometry'):
            source.validate(e)
        e = historical_transfer_event()
        e['kind'] = 'closure'
        with self.assertRaisesRegex(ValueError, 'only identity events'):
            source.validate(e)

    def test_periods_compile_stations_and_sections_without_current_leak(self):
        sections, stations = fixtures()
        compiled = source.compile_event(event(), sections, stations)
        self.assertEqual(len(compiled['sections']), 2)
        self.assertEqual(len(compiled['stations']), 2)
        self.assertEqual(len(compiled['retirements']), 2)
        self.assertEqual(len({f['properties']['history_id'] for f in compiled['sections']}), 1)
        for stamp in compiled['retirements']:
            self.assertEqual(stamp['valid_from'], '2020-03-14')
        pairs = [f['properties']['service_validity'] for f in compiled['sections']] + [['2020-03-14', None]]
        for date, expected in [('2011-03-10', True), ('2011-03-11', False),
                               ('2014-03-31', False), ('2014-04-01', True),
                               ('2016-08-01', False), ('2020-03-14', True)]:
            self.assertEqual(any((a is None or a <= date) and (b is None or date < b)
                                 for a, b in pairs), expected)
        self.assertNotIn('valid_from', sections[0]['properties'])

    def test_imprecise_unreviewed_unlicensed_and_overlap_rejected(self):
        for change in [{'kind': 'unknown'}, {'date_precision': 'year'}, {'review': {'status': 'candidate'}},
                       {'geometry': {'source': 'N05', 'licence_status': 'redistributable'}},
                       {'service_periods': [['2000-01-01', '2010-01-01'], ['2009-01-01', None]]}]:
            e = event()
            e.update(change)
            with self.assertRaises(ValueError):
                source.validate(e)

    def test_station_rename_changes_name_only_at_transition(self):
        e = event()
        e.update(kind='station_rename', date='2010-04-01', valid_from='1980-01-01',
                 before={'line': 'L', 'operator': 'O', 'station': 'Old'},
                 after={'line': 'L', 'operator': 'O', 'station': 'S'})
        sections, stations = fixtures()
        result = source.compile_event(e, sections, stations)
        self.assertEqual(result['sections'], [])
        self.assertEqual(result['stations'][0]['properties']['station_name'], 'Old')
        self.assertEqual(result['stations'][0]['properties']['valid_to'], '2010-04-01')
        self.assertEqual(result['retirements'][0]['match']['targets'], ['stations'])

    def test_transfer_clones_old_identity_on_same_geometry(self):
        e = event()
        e.update(kind='operator_rename', date='2015-03-14', valid_from='1980-01-01',
                 before={'line': 'Old L', 'operator': 'JR'}, after={'line': 'L', 'operator': 'O'})
        result = source.compile_event(e, *fixtures())
        self.assertEqual(result['sections'][0]['properties']['N02_004'], 'JR')
        self.assertEqual(result['stations'][0]['properties']['line_name'], 'Old L')
        self.assertEqual(result['retirements'][0]['valid_from'], '2015-03-14')

    def test_ambiguous_station_selector_fails_instead_of_dating_neighbor(self):
        e = event()
        e.update(kind='station_opening', service_periods=[['2010-01-01', None]])
        e['geometry']['selector'] = {'stations': ['S']}
        sections, stations = fixtures()
        neighbor = copy.deepcopy(stations[0])
        neighbor['properties']['station_name'] = 'Neighbor'
        stations.append(neighbor)
        with self.assertRaisesRegex(ValueError, 'unrelated'):
            source.compile_event(e, sections, stations)

    def test_stamps_are_intersections_not_order_dependent_overwrites(self):
        sections, stations = fixtures()
        e = event()
        stamps = [source.stamp(e, sections, sections, {'line': 'L', 'operator': 'O'},
                              pair, 'sections', str(i))
                  for i, pair in enumerate([['2015-01-01', '2030-01-01'], ['2000-01-01', '2020-01-01']])]
        normalized = source.normalize_stamps(stamps, sections, stations)
        p = {}
        for s in normalized:
            p.update({k: s[k] for k in ('valid_from', 'valid_to') if k in s})
        self.assertEqual(p, {'valid_from': '2015-01-01', 'valid_to': '2020-01-01'})
        stamps.append(source.stamp(e, sections, sections, {'line': 'L', 'operator': 'O'},
                                   ['2025-01-01', None], 'sections', 'bad'))
        with self.assertRaisesRegex(ValueError, 'empty'):
            source.normalize_stamps(stamps, sections, stations)

    def test_partial_opening_cannot_silently_stamp_whole_line(self):
        e = event()
        e.update(kind='opening', segment={'from_station': 'A', 'to_station': 'B'})
        with self.assertRaisesRegex(ValueError, 'isolated selector'):
            source.compile_event(e, *fixtures())

    def test_split_stamp_id_cannot_collide_with_another_source_stamp(self):
        sections, stations = fixtures()
        e = event()
        first = source.stamp(e, sections, sections, {'line': 'L', 'operator': 'O'},
                             ['2000-01-01', '2020-01-01'], 'sections', '.both')
        second = copy.deepcopy(first)
        second['history_id'] += '.from'
        second.pop('valid_to')
        with self.assertRaisesRegex(ValueError, 'collide'):
            source.normalize_stamps([first, second], sections, stations)

    def test_exact_station_geometry_identity_supplies_current_lookup_code(self):
        sections, stations = fixtures()
        stations[0]['properties']['n02_station_code'] = 'C'
        old = copy.deepcopy(stations[0])
        old['properties'].pop('n02_station_code')
        e = event()
        e.update(kind='operator_transfer', date='2015-01-01', valid_from='1980-01-01',
                 before={'line': 'Old', 'operator': 'Old O'},
                 after={'line': 'L', 'operator': 'O'})
        e['geometry']['historical_stations'] = [old]
        compiled = source.compile_event(e, sections, stations)
        self.assertEqual(compiled['stations'][0]['properties']['n02_station_code'], 'C')
        old['geometry']['coordinates'][0] += 0.001
        compiled = source.compile_event(e, sections, stations)
        self.assertNotIn('n02_station_code', compiled['stations'][0]['properties'])

    def test_partition_retains_measured_vertices_and_shared_cut(self):
        points = [[140, 35], [141, 36], [143, 38]]
        pieces = source.split_longitude(points, 142)
        self.assertEqual(pieces, [('lower', [[140, 35], [141, 36], [142, 37]]),
                                  ('upper', [[142, 37], [143, 38]])])

    def test_retired_station_closure_accepts_reviewed_historical_geometry(self):
        sections, stations = fixtures()
        e = event()
        e.update(kind='station_closure', service_periods=[[None, '2010-01-01']])
        e.pop('infrastructure_periods')
        e['geometry']['historical_stations'] = stations
        result = source.compile_event(e, sections, [])
        self.assertEqual(result['retirements'], [])
        self.assertEqual(result['stations'][0]['properties']['valid_to'], '2010-01-01')


if __name__ == '__main__':
    unittest.main()
