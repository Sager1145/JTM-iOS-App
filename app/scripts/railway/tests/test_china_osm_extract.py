"""Original-node topology must survive source extraction without spatial joins."""
import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest


class OriginalNodeExtractionTests(unittest.TestCase):
    def test_distinct_coincident_node_ids_and_ordered_members_survive(self):
        source = Path(__file__).resolve().parents[1] / "extract-china-osm.py"
        spec = importlib.util.spec_from_file_location("cn_extract", source)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root / "source.osm"
            fixture.write_text('''<osm version="0.6">
<node id="1" version="1" lon="114" lat="22"/>
<node id="2" version="1" lon="114.01" lat="22"/>
<node id="3" version="1" lon="114.01" lat="22"/>
<node id="4" version="1" lon="114.02" lat="22"/>
<node id="5" version="1" lon="115" lat="23"><tag k="railway" v="station"/><tag k="name" v="Station"/></node>
<way id="10" version="2"><nd ref="1"/><nd ref="2"/><tag k="railway" v="rail"/></way>
<way id="11" version="3"><nd ref="3"/><nd ref="4"/><tag k="railway" v="rail"/></way>
<relation id="20" version="4"><member type="way" ref="10" role="forward"/><member type="way" ref="11" role="backward"/><tag k="type" v="route"/><tag k="route" v="railway"/></relation>
<relation id="30" version="5"><member type="relation" ref="20" role=""/><tag k="type" v="route_master"/><tag k="route_master" v="train"/></relation>
</osm>''')
            module.extract(fixture, root / "topology.sqlite3")
            with sqlite3.connect(root / "topology.sqlite3") as database:
                self.assertEqual(database.execute("SELECT id FROM nodes ORDER BY id").fetchall(),
                                 [(1,), (2,), (3,), (4,), (5,)])
                self.assertEqual(database.execute("SELECT nodes,version FROM ways WHERE id=11").fetchone(),
                                 ("[3, 4]", 3))
                self.assertEqual(database.execute("SELECT members,version FROM relations WHERE id=20").fetchone(),
                                 ('[["w", 10, "forward"], ["w", 11, "backward"]]', 4))
                self.assertEqual(database.execute("SELECT members,version FROM relations WHERE id=30").fetchone(),
                                 ('[["r", 20, ""]]', 5))


if __name__ == "__main__":
    unittest.main()
