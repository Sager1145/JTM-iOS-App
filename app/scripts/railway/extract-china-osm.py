#!/usr/bin/env python3
"""Retain original railway topology from a pinned China OSM PBF as SQLite.

Native object filters avoid decoding the national road network in Python.
Node IDs, ordered way nodes, relation members, tags and source versions stay
intact. This source builder does not infer connections or publish a rail map.
"""
import argparse
import json
from pathlib import Path
import sqlite3
import time

import osmium


MODES = {"rail", "subway", "light_rail", "tram", "monorail", "narrow_gauge", "funicular"}


def extract(source, output):
    if Path(output).exists():
        raise ValueError("Output already exists; preserve the previous topology snapshot")
    connection = sqlite3.connect(output)
    connection.executescript("""
        PRAGMA journal_mode=OFF;
        CREATE TABLE nodes(id INTEGER PRIMARY KEY,lon REAL,lat REAL,tags TEXT,version INTEGER);
        CREATE TABLE ways(id INTEGER PRIMARY KEY,nodes TEXT,tags TEXT,version INTEGER);
        CREATE TABLE relations(id INTEGER PRIMARY KEY,members TEXT,tags TEXT,version INTEGER);
        CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT);
    """)
    required = set()
    started = time.monotonic()

    class WaysAndRelations(osmium.SimpleHandler):
        def way(self, way):
            tags = dict(way.tags)
            if tags.get("railway") not in MODES:
                return
            nodes = [node.ref for node in way.nodes]
            required.update(nodes)
            connection.execute("INSERT INTO ways VALUES(?,?,?,?)",
                               (way.id, json.dumps(nodes), json.dumps(tags, ensure_ascii=False), way.version))

        def relation(self, relation):
            tags = dict(relation.tags)
            if (tags.get("route") not in MODES | {"train", "railway", "tracks"}
                    and tags.get("route_master") not in MODES | {"train"}
                    and tags.get("public_transport") not in {"stop_area", "stop_area_group"}):
                return
            members = [(m.type, m.ref, m.role) for m in relation.members]
            required.update(ref for kind, ref, role in members if kind == "n")
            connection.execute("INSERT INTO relations VALUES(?,?,?,?)",
                               (relation.id, json.dumps(members), json.dumps(tags, ensure_ascii=False), relation.version))

    first = WaysAndRelations()
    with osmium.io.Reader(str(source), osmium.osm.WAY | osmium.osm.RELATION) as reader:
        osmium.apply(reader, osmium.filter.KeyFilter("railway", "route", "route_master", "public_transport"), first)
    connection.commit()
    print(f"ways/relations retained; {len(required):,} referenced nodes; reading coordinates", flush=True)

    class Nodes(osmium.SimpleHandler):
        count = 0

        def node(self, node):
            tags = dict(node.tags) if node.tags else {}
            if (node.id not in required and tags.get("railway") not in {"station", "halt", "stop"}
                    and tags.get("public_transport") not in {"station", "stop_position", "platform"}):
                return
            if not node.location.valid():
                return
            connection.execute("INSERT OR IGNORE INTO nodes VALUES(?,?,?,?,?)",
                               (node.id, node.location.lon, node.location.lat,
                                json.dumps(tags, ensure_ascii=False), node.version))
            self.count += 1
            if self.count % 100000 == 0:
                connection.commit()

    second = Nodes()
    with osmium.io.Reader(str(source), osmium.osm.NODE) as reader:
        osmium.apply(reader, osmium.filter.IdFilter(required), second)
    connection.commit()
    print("referenced coordinates retained; reading named station markers", flush=True)
    # Station markers can sit off track and outside route member lists. Keep
    # their source identity too, without invoking Python for every road node.
    with osmium.io.Reader(str(source), osmium.osm.NODE) as reader:
        osmium.apply(reader, osmium.filter.KeyFilter("railway", "public_transport"), second)
    counts = {name: connection.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0]
              for name in ("nodes", "ways", "relations")}
    connection.execute("INSERT INTO metadata VALUES('source',?)", (str(source),))
    connection.execute("INSERT INTO metadata VALUES('counts',?)", (json.dumps(counts),))
    connection.execute("INSERT INTO metadata VALUES('crs','WGS84')")
    connection.commit()
    connection.close()
    print(json.dumps({"counts": counts, "seconds": round(time.monotonic() - started, 1)}), flush=True)
    return counts


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pbf", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    extract(arguments.pbf, arguments.output)
