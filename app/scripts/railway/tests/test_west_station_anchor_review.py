import importlib.util
import json
import os
import unittest


HERE = os.path.dirname(__file__)
REGISTRY = os.path.abspath(os.path.join(HERE, '..', 'na-feeds.json'))
AUDIT_PATH = os.path.abspath(os.path.join(
    HERE, '..', 'audit-na-package.py'))
SPEC = importlib.util.spec_from_file_location('west_station_audit', AUDIT_PATH)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


class WestStationAnchorReviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(REGISTRY, encoding='utf-8') as source:
            cls.registry = json.load(source)
        cls.feeds = {row['slug']: row for row in cls.registry['feeds']}

    def test_real_interchange_spans_have_exact_evidenced_limits(self):
        records = self.registry['stationSplitExceptions']
        expected = {
            'us-official-oceanside': (300, {'27000', '28000', '28100', '144'}),
            'us-official-jefferson-park': (190, {'41280', 'JEFFERSONP'}),
            'us-official-capitol-hill': (140, {'11175', 'N03', '99603', '99610'}),
            'us-official-5th-jackson': (140, {'1-1651', '1-1652', 'C09'}),
            'us-official-balboa-park': (
                130, {'BALB', 'M80-1', 'M80-2', '4803', '4805', '5418', '5781'}),
            'us-official-milpitas': (
                180, {'MLPT', 'S40-1', 'S40-2', 'PS_MILP', '5236', '5249'}),
        }
        for station_id, (limit, stop_ids) in expected.items():
            row = records[station_id]
            self.assertEqual(row['maxMeters'], limit)
            self.assertEqual(set(row['stopIds']), stop_ids)
            self.assertTrue(row['evidenceUrl'].startswith('https://'))
            hashes = row['sourceSha256']
            hashes = hashes if isinstance(hashes, list) else [hashes]
            self.assertTrue(all(len(value) == 64 for value in hashes))

    def test_reviewed_span_is_a_note_but_larger_drift_still_warns(self):
        findings = audit.Findings()
        exceptions = audit.read_station_split_exceptions(REGISTRY, findings)
        package = {'country': 'US', 'lines': [
            {'id': 'nctd', 'stations': [
                ['us-official-oceanside', 'Oceanside', -117.37827, 33.190515],
            ]},
            {'id': 'metrolink', 'stations': [
                ['us-official-oceanside', 'Oceanside', -117.379947, 33.192492],
            ]},
        ]}
        audit.audit_package(package, findings,
                            {'nctd': 'commuter', 'metrolink': 'commuter'},
                            exceptions)
        self.assertTrue(any(row['check'] == 'station.split.reviewed'
                            for row in findings.rows))
        reviewed = next(row for row in findings.rows
                        if row['check'] == 'station.split.reviewed')
        self.assertEqual(reviewed['sourceSha256'],
                         exceptions['us-official-oceanside']['sourceSha256'])
        self.assertFalse(any(row['check'] == 'station.split'
                             for row in findings.rows))

        package['lines'][1]['stations'][0][3] = 33.1940
        findings = audit.Findings()
        audit.audit_package(package, findings,
                            {'nctd': 'commuter', 'metrolink': 'commuter'},
                            exceptions)
        self.assertTrue(any(row['check'] == 'station.split'
                            for row in findings.rows))

    def test_canada_exact_gtfs_station_ids_have_individual_limits(self):
        records = self.registry['stationSplitExceptions']
        expected = {
            'ca-official-south-keys': (235, '3038_stn'),
            'ca-official-waterfront': (175, '12034'),
            'ca-official-commercial-broadway': (45, '99917'),
            'ca-official-dufferin-gate-loop': (55, '2032'),
            'ca-official-queens-quay-loop-at-lower-spadina-ave':
                (35, '10927'),
            'ca-official-exhibition-loop': (40, '12584'),
        }
        for station_id, (limit, stop_id) in expected.items():
            row = records[station_id]
            self.assertEqual(row['maxMeters'], limit)
            self.assertEqual(row['stopIds'], [stop_id])
            self.assertEqual(len(row['sourceSha256']), 64)

        findings = audit.Findings()
        accepted = audit.read_station_split_exceptions(REGISTRY, findings)
        self.assertFalse(any(row['severity'] == 'ERROR'
                             for row in findings.rows))
        self.assertTrue(set(expected).issubset(accepted))

    def test_sfmta_direction_split_replaces_the_former_defect_entries(self):
        # N, PH and PM used to be `officialNetworkDefectByRouteId` entries --
        # their inbound and outbound alignments genuinely diverge near
        # Embarcadero and Jackson/Washington, and folding both into one
        # route network produced an orphan branch and a split stop. Naming
        # direction 0 and direction 1 separately resolves that (direction 1
        # is compared against direction 0 and shipped as `extraSegments`
        # wherever it disagrees; see `attach_direction_extra_segments` in
        # build-north-america-rail-package.py), so the routes ship instead
        # of being withheld and the defect entries are gone, not merely
        # reworded.
        sfmta = self.feeds['san-francisco-municipal-tran']
        self.assertNotIn('officialNetworkDefectByRouteId', sfmta)
        for route in ('N', 'PH', 'PM'):
            mapping = sfmta['officialNetworkByRouteId'][route]
            self.assertIsInstance(mapping, dict, route)
            self.assertEqual(set(mapping), {'0', '1'}, route)

    def test_directional_or_misrouted_spikes_fail_closed(self):
        marta = self.feeds['metropolitan-atlanta-rapid-t']
        self.assertEqual(set(marta['officialNetworkDefectByRouteId']), {'ATLSC'})
        self.assertIn('211753', marta['officialNetworkDefectByRouteId']['ATLSC'])
        self.assertIn('216 m', marta['officialNetworkDefectByRouteId']['ATLSC'])


if __name__ == '__main__':
    unittest.main()
