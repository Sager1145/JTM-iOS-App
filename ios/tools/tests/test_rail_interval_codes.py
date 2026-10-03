import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from rail_interval_codes import interval_rows, nex_route_sections


class RailIntervalCodeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.package = json.loads((Path(__file__).resolve().parents[3] / 'app/public/rail/jp-2025.json').read_text())

    def test_every_interval_has_unique_identity(self):
        rows = interval_rows(self.package)
        self.assertEqual(len(rows), sum(len(line['segments']) for line in self.package['lines']))
        self.assertEqual(len(rows), len({row['section_code'] for row in rows}))

    def test_nex_tunnel_corridor_both_directions(self):
        calls = [{'current_source_code': code} for code in ['003766', '004095']]
        forward = nex_route_sections(self.package, calls)[0]
        reverse = nex_route_sections(self.package, list(reversed(calls)))[0]
        self.assertEqual(forward['line_ids'], ['jp-東日本旅客鉄道-総武線-3'])
        self.assertEqual(forward['section_codes'], [
            'jp-東日本旅客鉄道-総武線-3@003766:003872',
            'jp-東日本旅客鉄道-総武線-3@003872:004095'])
        self.assertEqual(reverse['section_codes'], list(reversed(forward['section_codes'])))

    def test_nex_excludes_surface_tokaido_parallel(self):
        calls = [{'current_source_code': code} for code in ['003766', '004961']]
        route = nex_route_sections(self.package, calls)[0]
        self.assertIn('jp-東日本旅客鉄道-総武線-3', route['line_ids'])
        self.assertFalse(any(code.startswith('jp-東日本旅客鉄道-東海道線@003') for code in route['section_codes']))

    def test_unknown_endpoint_has_no_guessed_route(self):
        self.assertEqual(nex_route_sections(self.package, [{'current_source_code': 'missing'}, {'current_source_code': '003766'}]), [])
