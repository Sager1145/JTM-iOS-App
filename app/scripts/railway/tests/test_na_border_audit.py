import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('border_audit', Path(__file__).parents[1] / 'audit-na-package.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class BorderOwnershipAuditTests(unittest.TestCase):
    def line(self):
        return {'id': 'service-border1', 'name': 'Service', 'operator': 'Rail',
                'geometrySource': 'survey', 'smoothingProfile': 'regional',
                'colorReference': '#123456', 'colorSource': 'official palette',
                'stations': [['us-a', 'A', -73, 45], ['ca-b', 'B', -73, 45.01]],
                'segments': [[1.111, 0, [[-73, 45], [-73, 45.005], [-73, 45.01]]]],
                'borderConnector': {'sourceLineId': 'service', 'sourceInterval': 0,
                                    'stationCountries': ['us', 'ca'], 'evidence': 'original surveyed interval'}}

    def errors(self, line):
        result = audit.Findings()
        audit.audit_line(line, 'US', result, {'survey'})
        return [r['check'] for r in result.rows if r['severity'] == 'ERROR' and r['check'].startswith('station.')]

    def test_explicit_connector_preserves_foreign_canonical_identity(self):
        self.assertEqual(self.errors(self.line()), [])

    def test_plain_domestic_line_cannot_claim_foreign_station(self):
        line = self.line()
        del line['borderConnector']
        self.assertIn('station.prefix', self.errors(line))

    def test_border_metadata_does_not_excuse_wrong_country_prefix(self):
        line = self.line()
        line['stations'][1][0] = 'us-b'
        self.assertIn('station.prefix', self.errors(line))

    def test_invalid_connector_is_not_a_general_country_exception(self):
        line = self.line()
        line['borderConnector']['sourceInterval'] = -1
        self.assertIn('station.borderContract', self.errors(line))


if __name__ == '__main__':
    unittest.main()
