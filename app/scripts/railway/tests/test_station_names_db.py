"""Scoped name synchronization must preserve the frozen North American rows."""
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("sync_names", Path(__file__).resolve().parents[1] / "sync-station-names-db.py")
sync_names = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync_names)


class StationNamesDatabaseTests(unittest.TestCase):
    def test_scoped_update_preserves_na_and_requires_exact_station_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            (app / "data").mkdir()
            for region in sync_names.names.REGIONS:
                row = {f: "" for f in sync_names.names.FIELDS}
                row.update(name="上道", en="Agari-michi", kana="あがりみち")
                table = {"byCode": {"jp-line:100": row} if region == "jp" else {}, "byName": {}}
                (app / "data" / sync_names.names.resource("station-names", region)).write_text(json.dumps(table))
            path = app / "rail.db"
            db = sqlite3.connect(path)
            db.executescript("""
                CREATE TABLE country(code PRIMARY KEY,readings_file);
                CREATE TABLE line(id PRIMARY KEY,country_code);
                CREATE TABLE station(id PRIMARY KEY,code,country_code);
                CREATE TABLE line_station(line_id,seq,station_id,name,name_roma);
                CREATE TABLE station_name(id INTEGER PRIMARY KEY,country_code,key_type,key,key_norm,field,value,
                    UNIQUE(country_code,key_type,key,field));
                CREATE TABLE line_station_name(line_id,seq,field,value,source,PRIMARY KEY(line_id,seq,field));
                CREATE TABLE meta(key PRIMARY KEY,value);
                INSERT INTO country VALUES('JP','data/station-readings.json'),('US','data/station-readings-us.json'),
                    ('TW','data/station-readings-tw.json'),('HK','data/station-readings-hk.json'),
                    ('MO','data/station-readings-mo.json'),('KR','data/station-readings-kr.json');
                INSERT INTO line VALUES('jp-line','JP'),('us-line','US');
                INSERT INTO station VALUES(1,'100','JP'),(2,'us-station','US');
                INSERT INTO line_station VALUES('jp-line',0,1,'上道','Old'),('us-line',0,2,'Frozen','Frozen');
                INSERT INTO station_name VALUES(1,'US','code','us-station','us-station','en','Frozen');
                INSERT INTO line_station_name VALUES('us-line',0,'en','Frozen','old-source');
            """)
            db.commit()
            frozen = db.execute("SELECT * FROM station_name WHERE country_code='US'").fetchall()
            with self.assertRaisesRegex(ValueError, 'stale name rows'):
                sync_names.sync(path, app, check=True)
            self.assertGreater(sync_names.sync(path, app), 0)
            self.assertEqual(sync_names.sync(path, app, check=True), 0)
            self.assertEqual(db.execute("SELECT * FROM station_name WHERE country_code='US'").fetchall(), frozen)
            self.assertEqual(db.execute("SELECT * FROM line_station_name WHERE line_id='us-line'").fetchall(),
                             [('us-line', 0, 'en', 'Frozen', 'old-source')])
            self.assertEqual(db.execute("SELECT value FROM line_station_name WHERE line_id='jp-line' AND field='kana'").fetchone(),
                             ('あがりみち',))
            db.execute("UPDATE line_station SET name='Wrong station' WHERE line_id='jp-line'")
            db.commit()
            with self.assertRaisesRegex(ValueError, 'identity is stale'):
                sync_names.sync(path, app)
            db.close()


if __name__ == '__main__':
    unittest.main()
