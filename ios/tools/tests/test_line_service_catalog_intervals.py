"""Catalog corridor selection is reproducible at its recorded observation day."""
import importlib.util
import json
from pathlib import Path
import shutil
import sqlite3
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class ServiceCatalogObservationTests(unittest.TestCase):
    def test_future_exclusive_end_is_included_at_observation_and_end_is_excluded(self):
        spec = importlib.util.spec_from_file_location('catalog', ROOT / 'ios/tools/build-line-service-catalog.py')
        catalog = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(catalog)
        with tempfile.TemporaryDirectory() as scratch:
            catalog.ROOT = Path(scratch)
            package = catalog.ROOT / 'app/public/rail/jp-2025.json'
            package.parent.mkdir(parents=True)
            shutil.copy2(ROOT / package.relative_to(catalog.ROOT), package)
            resources = catalog.ROOT / 'ios/RailKit/Sources/RailCore/Resources'
            resources.mkdir(parents=True)
            source = ROOT / 'ios/RailKit/Sources/RailCore/Resources/japan-through-services.json'
            corridors = json.loads(source.read_text())
            jk = next(row for row in corridors['patterns'] if row['id'] == 'JK')
            jk['validFrom'] = '2026-10-01'
            jk['validTo'] = '2026-10-03'
            for leg in jk['legs']:
                leg['validFrom'] = '2026-10-01'
                leg['validTo'] = '2026-10-03'
            (resources / source.name).write_text(json.dumps(corridors))
            connection = sqlite3.connect(resources / 'train-service-timetable.sqlite')
            connection.executescript('''
                CREATE TABLE trip_line_segments(trip_id,source_id,current_n02_line_id,line_name,from_station_id,to_station_id,confidence,reference_kind);
                CREATE TABLE trips(trip_id,service_class,timetable_version_id);
                CREATE TABLE timetable_versions(timetable_version_id,effective_from,effective_until);
                CREATE TABLE source_documents(source_id,url_or_locator);
            ''')
            connection.close()
            def jk_kinds():
                return [kind for line in catalog.build()['lines'] for kind in line['kinds']
                        if kind['scope'].startswith(jk['name'] + ':')]
            catalog.OBSERVED = '2026-10-02'
            self.assertTrue(jk_kinds(), 'Future-ended corridor and legs must apply on observed day')
            catalog.OBSERVED = '2026-10-03'
            self.assertEqual(jk_kinds(), [])
            catalog.OBSERVED = '2026-09-30'
            self.assertEqual(jk_kinds(), [])


if __name__ == '__main__':
    unittest.main()
