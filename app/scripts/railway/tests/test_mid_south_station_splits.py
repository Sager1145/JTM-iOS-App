import importlib.util
import json
import os
import unittest


HERE = os.path.dirname(__file__)
REGISTRY = os.path.abspath(os.path.join(HERE, '..', 'na-feeds.json'))
AUDIT_PATH = os.path.abspath(os.path.join(
    HERE, '..', 'audit-na-package.py'))
SPEC = importlib.util.spec_from_file_location(
    'mid_south_station_audit', AUDIT_PATH)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


class MidSouthStationSplitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(REGISTRY, encoding='utf-8') as source:
            cls.registry = json.load(source)

    def test_exact_official_station_complex_limits(self):
        records = self.registry['stationSplitExceptions']
        expected = {
            'us-official-fairview-heights-metrolink':
                (80, ['10602'], {
                    '4166ed2551eec48789d9e5387057644e108e976cd30995c0e35f6dea648d167f',
                    '63482e125700bf820d2e5a8151a32b294d2dd6e270d4cb65a221bee3313763bd',
                }),
            'us-official-canal-st-at-carondelet-st':
                (35, ['1041', '1965', '1667'], {
                    '3b32471680f5736301fdcaa2ae98bf62ba6e108ea51589febb1d66114ee567f9',
                    'b59d26a9ede987908180886bb1391f0bdaa7a64ef3092594fbd2258807a4ebaf',
                }),
            'us-official-n-carrollton-ave-at-canal-st':
                (40, ['1634', '1635'], {
                    '3b32471680f5736301fdcaa2ae98bf62ba6e108ea51589febb1d66114ee567f9',
                    'b59d26a9ede987908180886bb1391f0bdaa7a64ef3092594fbd2258807a4ebaf',
                }),
        }
        for station_id, (limit, stop_ids, hashes) in expected.items():
            record = records[station_id]
            self.assertEqual(record['maxMeters'], limit)
            self.assertEqual(record['stopIds'], stop_ids)
            self.assertEqual(set(record['sourceSha256']), hashes)
            self.assertTrue(record['evidenceUrl'].startswith('https://'))

    def test_final_package_spans_are_reviewed_without_widening_bands(self):
        findings = audit.Findings()
        exceptions = audit.read_station_split_exceptions(REGISTRY, findings)
        self.assertFalse(any(row['severity'] == 'ERROR'
                             for row in findings.rows))
        package = {'country': 'US', 'lines': [
            {'id': 'new-orleans-rta-12', 'stations': [[
                'us-official-canal-st-at-carondelet-st',
                'Canal St at Carondelet St', -90.070176, 29.953517,
            ]]},
            {'id': 'new-orleans-rta-47', 'stations': [
                ['us-official-canal-st-at-carondelet-st',
                 'Canal St at Carondelet St', -90.070032, 29.953757],
                ['us-official-n-carrollton-ave-at-canal-st',
                 'N. Carrollton Ave. at Canal St.', -90.100736, 29.974609],
            ]},
            {'id': 'new-orleans-rta-48', 'stations': [[
                'us-official-n-carrollton-ave-at-canal-st',
                'N. Carrollton Ave. at Canal St.', -90.100405, 29.974724,
            ]]},
            {'id': 'metro-st-louis-mlb', 'stations': [[
                'us-official-fairview-heights-metrolink',
                'Fairview Heights Metrolink Station', -90.048311, 38.594366,
            ]]},
            {'id': 'metro-st-louis-mlr', 'stations': [[
                'us-official-fairview-heights-metrolink',
                'Fairview Heights Metrolink Station', -90.047930, 38.593813,
            ]]},
        ]}
        bands = {
            'new-orleans-rta-12': 'street',
            'new-orleans-rta-47': 'street',
            'new-orleans-rta-48': 'street',
            'metro-st-louis-mlb': 'metro',
            'metro-st-louis-mlr': 'metro',
        }
        audit.audit_package(package, findings, bands, exceptions)
        reviewed = {
            row['station'] for row in findings.rows
            if row['check'] == 'station.split.reviewed'
        }
        self.assertEqual(reviewed, {
            'us-official-fairview-heights-metrolink',
            'us-official-canal-st-at-carondelet-st',
            'us-official-n-carrollton-ave-at-canal-st',
        })
        self.assertFalse(any(row['check'] == 'station.split'
                             for row in findings.rows))

        # The station-specific ceiling remains fail-closed: moving this one
        # anchor beyond 80 m must warn even though the same route band is used.
        package['lines'][-1]['stations'][0][3] = 38.5929
        over_limit = audit.Findings()
        audit.audit_package(package, over_limit, bands, exceptions)
        self.assertTrue(any(
            row['check'] == 'station.split'
            and row.get('station') ==
            'us-official-fairview-heights-metrolink'
            for row in over_limit.rows))


if __name__ == '__main__':
    unittest.main()
