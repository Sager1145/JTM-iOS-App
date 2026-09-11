import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from fetch_networks import build_query, relation_to_line, route_is_eligible


class FetchNetworksTests(unittest.TestCase):
    def test_query_covers_every_extent_and_requests_full_geometry(self):
        query = build_query([[1, 2, 3, 4], [5, 6, 7, 8]])
        self.assertIn("(1,2,3,4)", query)
        self.assertIn("(5,6,7,8)", query)
        self.assertIn("out body geom", query)

    def test_train_filter_keeps_commuter_and_rejects_intercity(self):
        self.assertTrue(route_is_eligible({"route": "train", "service": "commuter", "name": "Northstar"}, []))
        self.assertTrue(route_is_eligible({"route": "train", "name": "Union Pearson Express"}, []))
        self.assertTrue(route_is_eligible({"route": "train", "network": "REM"}, []))
        self.assertFalse(route_is_eligible({"route": "train", "service": "long_distance", "operator": "Amtrak"}, []))
        self.assertTrue(route_is_eligible({"route": "tram", "name": "MAX"}, []))

    def test_inactive_route_relations_are_rejected_but_service_suspension_is_not_geometry_state(self):
        self.assertFalse(route_is_eligible({"route": "light_rail", "state": "proposed"}, []))
        self.assertFalse(route_is_eligible({"route": "tram", "construction": "yes"}, []))
        self.assertFalse(route_is_eligible({"route": "train", "disused": "yes", "service": "commuter"}, []))
        self.assertTrue(route_is_eligible({"route": "tram", "service": "suspended"}, []))

    def test_relation_geometry_becomes_compact_segments(self):
        relation = {
            "type": "relation", "id": 42,
            "tags": {"type": "route", "route": "light_rail", "name": "Blue", "operator": "Transit"},
            "members": [
                {"type": "node", "role": "stop", "lat": 1, "lon": 2},
                {"type": "way", "role": "", "geometry": [
                    {"lat": 1, "lon": 2}, {"lat": 3, "lon": 4}, None,
                    {"lat": 5, "lon": 6}, {"lat": 7, "lon": 8},
                ]},
            ],
        }
        line = relation_to_line(relation, "city", ["Transit"])
        self.assertEqual(line["id"], "osm-route-42")
        self.assertEqual(line["kind"], "lightrail")
        self.assertEqual(line["segments"], [
            [0, 0, [[2, 1], [4, 3]]],
            [0, 0, [[6, 5], [8, 7]]],
        ])


if __name__ == "__main__":
    unittest.main()

class TransportTests(unittest.TestCase):
    def test_unreachable_primary_uses_public_mirror_and_records_source(self):
        import json
        import urllib.error
        from unittest.mock import MagicMock,patch
        import fetch_networks as fetcher
        response=MagicMock()
        response.__enter__.return_value.read.return_value=json.dumps({'elements':[]}).encode()
        with patch.object(fetcher,'_preferred_endpoint',fetcher.DEFAULT_ENDPOINT),patch.object(fetcher.urllib.request,'urlopen',side_effect=[urllib.error.URLError('connection refused'),response]) as request,patch.object(fetcher.time,'sleep'):
            result=fetcher.fetch_overpass('[out:json];rel(1);out;',retries=1)
        self.assertEqual(result['_fetchEndpoint'],fetcher.FALLBACK_ENDPOINT)
        self.assertEqual(request.call_args_list[1][0][0].full_url,fetcher.FALLBACK_ENDPOINT)

    def test_http_success_with_timeout_remark_is_not_accepted(self):
        import json
        from unittest.mock import MagicMock,patch
        import fetch_networks as fetcher
        response=MagicMock()
        response.__enter__.return_value.read.return_value=json.dumps({'elements':[], 'remark':'runtime error: timeout'}).encode()
        with patch.object(fetcher.urllib.request,'urlopen',return_value=response):
            with self.assertRaisesRegex(RuntimeError,'incomplete result'):
                fetcher.fetch_overpass('query',retries=0)
