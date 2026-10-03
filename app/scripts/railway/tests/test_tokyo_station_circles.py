"""Reviewed platform aliases retain line identity while electing one circle."""
import json
import tempfile
import unittest
from pathlib import Path
import test_display_network as fixtures


class TokyoStationCirclesTests(unittest.TestCase):
    def test_circle_owner_retains_alias_line_in_popup(self):
        owner = fixtures.DisplayNetworkTests.line('owner', 1, ('shared', 139, 35), [[139, 35], [139.01, 35]])
        alias = fixtures.DisplayNetworkTests.line('alias', 1, ('shared', 139, 35), [[139, 35], [139, 35.01]])
        alias['stationCircleOwnerByCode'] = {'shared': 'owner'}
        package = {'format': 'compact-v1', 'version': 'test', 'country': 'JP', 'lines': [owner, alias]}
        with tempfile.TemporaryDirectory() as temporary:
            rail = Path(temporary) / 'rail'
            out = Path(temporary) / 'out'
            rail.mkdir()
            for region, document in fixtures.DisplayNetworkTests.region_packages(package, 'jp').items():
                (rail / f'{region}-2025.json').write_text(json.dumps(document))
            (rail / 'display-lanes.json').write_text(json.dumps({
                'format': 'jtm-display-lanes-v1', 'partsByRegion': fixtures.DisplayNetworkTests.whole_line_parts_by_region('jp', owner, alias)}))
            fixtures.display_network.build(rail, out)
            payload = fixtures.DisplayNetworkTests.load_region_payload(out, 'jp')
        circles = [row for row in payload['stations'] if row['stationCode'] == 'shared']
        self.assertEqual([row['lineKey'] for row in circles], ['jp|owner'])
        self.assertEqual(circles[0]['groupLineKeys'], ['jp|owner', 'jp|alias'])
        self.assertEqual(len(payload['lines']), 2)


if __name__ == '__main__':
    unittest.main()
