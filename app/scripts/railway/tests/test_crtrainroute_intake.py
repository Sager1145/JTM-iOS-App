"""Regression cases for real source-intake boundaries, without national builds."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "import-crtrainroute.py"


def track(osm_id="10", mode="rail", points=None):
    return {"type": "Feature", "properties": {
        "osm_id": osm_id, "code": 6101, "fclass": mode, "name": "测试线",
        "layer": 0, "bridge": "F", "tunnel": "F"}, "geometry": {
            "type": "MultiLineString", "coordinates": [points or [[116.0, 39.0], [116.1, 39.1]]]}}


class CRTrainRouteIntakeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("crtrainroute_intake", SCRIPT)
        cls.builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.builder)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        (self.source / "data/geojson").mkdir(parents=True)
        self.output = self.root / "candidates"
        self.manifest = self.root / "intake.json"
        self.write("stations.json", {
            "BJP": {"name": "北京站", "lon": 116.4271, "lat": 39.9028, "city": "北京市"},
            "BXP": {"name": "北京西站", "lon": 116.4271, "lat": 39.9028, "city": "北京市"},
            "XJA": {"name": "香港西九龙站", "lon": 114.169663, "lat": 22.301755, "city": "香港特别行政区"}})
        self.write("station_names.json", {"BJP": "北京", "BXP": "北京西", "XJA": "香港西九龙", "ZZZ": "无坐标"})
        self.write("station_lanes.json", {"stations": {"BXP": {"aliasOf": "BJP"}}})

    def write(self, name, data):
        path = self.source / "data" / name
        path.write_text(json.dumps(data, ensure_ascii=False))

    def province(self, code, features):
        self.write(f"geojson/{code}.geojson", {"type": "FeatureCollection", "features": features})

    def run_import(self):
        return self.builder.build(self.source, self.output, self.manifest,
                                  "d75307df9c812abf1259b86b75202ba7b0048679", "2026-10-18")

    def records(self, name):
        return [json.loads(row) for row in (self.output / name).read_text().splitlines()]

    def test_keeps_disconnected_ways_and_source_ids_without_fabricated_edges(self):
        self.province("110000", [track(), track("11", points=[[116.3, 39.1], [116.4, 39.2]])])
        # A malicious/invalid pickle must never be read by source intake.
        (self.source / "data/rail_graph.pkl").write_bytes(b"not a pickle")
        result = self.run_import()
        rows = self.records("tracks-110000.jsonl")
        self.assertEqual([r["properties"]["osm_id"] for r in rows], ["10", "11"])
        self.assertEqual(rows[0]["geometry"]["coordinates"][0][-1], [116.1, 39.1])
        self.assertEqual(rows[1]["geometry"]["coordinates"][0][0], [116.3, 39.1])
        self.assertEqual(result["runtimeRelease"]["eligible"], False)
        self.assertEqual(result["counts"]["syntheticConnections"], 0)

    def test_keeps_transit_and_excludes_existing_hk_mo_packages(self):
        self.province("110000", [track(), track("12", "subway"), track("13", "tram")])
        self.province("810000", [track("14")])
        self.province("820000", [track("15", "light_rail")])
        result = self.run_import()
        self.assertEqual(result["counts"]["mainlandFeatures"], 3)
        self.assertEqual(result["counts"]["excludedRegionalFeatures"], 2)
        self.assertEqual(len(self.records("tracks-110000.jsonl")), 3)
        self.assertFalse((self.output / "tracks-810000.jsonl").exists())

    def test_keeps_colocated_station_codes_and_missing_coordinates_without_datum_mixing(self):
        self.province("110000", [track()])
        self.run_import()
        rows = {r["sourceCode"]: r for r in self.records("stations.jsonl")}
        self.assertEqual(set(rows), {"BJP", "BXP", "XJA", "ZZZ"})
        self.assertNotEqual(rows["BJP"]["id"], rows["BXP"]["id"])
        self.assertEqual(rows["BJP"]["coordinate"]["value"], [116.4271, 39.9028])
        self.assertEqual(rows["BJP"]["coordinate"]["declaredCRS"], "GCJ02")
        self.assertIsNone(rows["BJP"]["canonicalWGS84"])
        self.assertEqual(rows["XJA"]["region"], "cn")
        self.assertIsNone(rows["ZZZ"]["coordinate"])
        self.assertIsNone(rows["BXP"]["physicalTrackID"])
        self.assertEqual(rows["BXP"]["upstreamAliasCandidate"]["aliasOf"], "BJP")

    def test_rejects_invalid_geometry_instead_of_silently_publishing_partial_data(self):
        self.province("110000", [track(points=[[116.0, 39.0], [999.0, 39.1]])])
        with self.assertRaisesRegex(ValueError, "coordinate"):
            self.run_import()
        self.assertFalse(self.manifest.exists())

    def test_source_order_and_same_osm_id_do_not_collapse_distinct_fragments(self):
        self.province("110000", [track(), track(points=[[116.2, 39.0], [116.3, 39.1]])])
        self.province("120000", [track()])
        self.run_import()
        rows = self.records("tracks-110000.jsonl")
        self.assertEqual(len(rows), 2)
        self.assertNotEqual(rows[0]["id"], rows[1]["id"])
        self.assertEqual(rows[0]["properties"]["osm_id"], rows[1]["properties"]["osm_id"])

    def test_incompatible_declared_crs_cannot_be_relabelled_as_wgs84(self):
        self.write("geojson/110000.geojson", {"type": "FeatureCollection", "features": [track()],
                   "crs": {"type": "name", "properties": {"name": "EPSG:3857"}}})
        with self.assertRaisesRegex(ValueError, "CRS"):
            self.run_import()
        self.assertFalse(self.manifest.exists())

    def test_declared_crs84_and_collection_metadata_are_preserved(self):
        self.write("geojson/110000.geojson", {"type": "FeatureCollection", "features": [track()],
                   "name": "railways", "crs": {"type": "name", "properties": {
                       "name": "urn:ogc:def:crs:OGC:1.3:CRS84"}}})
        result = self.run_import()
        self.assertEqual(result["provinces"][0]["collectionMetadata"]["crs"]["properties"]["name"],
                         "urn:ogc:def:crs:OGC:1.3:CRS84")

    def test_mid_stream_failure_does_not_leave_a_success_manifest(self):
        self.province("110000", [track(), track("11", points=[[116.0, 39.0], [999, 40]])])
        with self.assertRaisesRegex(ValueError, "coordinate"):
            self.run_import()
        self.assertFalse(self.manifest.exists())
        self.assertEqual(len(self.records("tracks-110000.jsonl")), 1)
        with self.assertRaisesRegex(ValueError, "empty"):
            self.run_import()


if __name__ == "__main__":
    unittest.main()
