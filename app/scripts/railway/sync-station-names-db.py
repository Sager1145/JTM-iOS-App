#!/usr/bin/env python3
"""Update only non-North-American name rows in an existing rail.db.

Station identity, English evidence, geometry, timetable and US/CA rows stay
untouched. Use --check to verify without writing; the full builder uses the
same station-names resources on subsequent coordinated rebuilds.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import sqlite3

APP = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("station_names", Path(__file__).with_name("build-station-names.py"))
names = importlib.util.module_from_spec(spec)
spec.loader.exec_module(names)


def expected_rows(app, db):
    raw, resolved, country_files = {}, {}, {}
    for region in names.REGIONS:
        country = region.upper()
        filename = names.resource("station-names", region)
        table = json.loads((app / "data" / filename).read_text())
        country_files[country] = "data/" + filename
        for section, rows in (("byCode", table["byCode"]), ("byName", table["byName"])):
            for key, row in rows.items():
                kind = "name" if section == "byName" else "line_station" if ":" in key else "code"
                for field, value in row.items():
                    if value:
                        raw[(country, kind, key, field)] = (names.normalize(key), value)
        for line, seq, code, base_name, roma in db.execute("""SELECT ls.line_id,ls.seq,s.code,ls.name,ls.name_roma
            FROM line_station ls JOIN station s ON s.id=ls.station_id WHERE s.country_code=?""", (country,)):
            row = table["byCode"].get(f"{line}:{code}")
            if row is None or row["name"] != base_name:
                raise ValueError(f"database station identity is stale: {line}:{seq}")
            for field, value in row.items():
                if value:
                    resolved[(line, seq, field)] = (value, "readings:line_station")
            if not row["romaji"] and roma:
                resolved[(line, seq, "romaji")] = (roma, "package")
    return raw, resolved, country_files


def sync(path, app=APP, check=False):
    db = sqlite3.connect(path)
    try:
        expected_raw, expected_resolved, files = expected_rows(app, db)
        placeholders = ",".join("?" for _ in names.REGIONS)
        countries = [r.upper() for r in names.REGIONS]
        raw = {(c, t, k, f): (n, v) for c, t, k, f, n, v in db.execute(
            f"SELECT country_code,key_type,key,field,key_norm,value FROM station_name WHERE country_code IN ({placeholders})", countries)}
        resolved = {(l, s, f): (v, src) for l, s, f, v, src in db.execute(
            f"SELECT n.line_id,n.seq,n.field,n.value,n.source FROM line_station_name n JOIN line l ON l.id=n.line_id WHERE l.country_code IN ({placeholders})", countries)}
        current_files = dict(db.execute(f"SELECT code,readings_file FROM country WHERE code IN ({placeholders})", countries))
        changes = sum(raw.get(k) != v for k, v in expected_raw.items()) + len(raw.keys() - expected_raw.keys())
        changes += sum(resolved.get(k) != v for k, v in expected_resolved.items()) + len(resolved.keys() - expected_resolved.keys())
        changes += sum(current_files.get(k) != v for k, v in files.items())
        if check:
            if changes:
                raise ValueError(f"rail.db has {changes} stale name rows; run sync-station-names-db.py")
            return 0
        with db:
            for c, t, k, f in raw.keys() - expected_raw.keys():
                db.execute("DELETE FROM station_name WHERE country_code=? AND key_type=? AND key=? AND field=?", (c, t, k, f))
            for (c, t, k, f), (n, v) in expected_raw.items():
                if raw.get((c, t, k, f)) != (n, v):
                    db.execute("""INSERT INTO station_name(country_code,key_type,key,key_norm,field,value) VALUES(?,?,?,?,?,?)
                        ON CONFLICT(country_code,key_type,key,field) DO UPDATE SET key_norm=excluded.key_norm,value=excluded.value""", (c, t, k, n, f, v))
            for l, s, f in resolved.keys() - expected_resolved.keys():
                db.execute("DELETE FROM line_station_name WHERE line_id=? AND seq=? AND field=?", (l, s, f))
            for (l, s, f), (v, src) in expected_resolved.items():
                if resolved.get((l, s, f)) != (v, src):
                    db.execute("""INSERT INTO line_station_name VALUES(?,?,?,?,?) ON CONFLICT(line_id,seq,field)
                        DO UPDATE SET value=excluded.value,source=excluded.source""", (l, s, f, v, src))
            for c, filename in files.items():
                db.execute("UPDATE country SET readings_file=? WHERE code=?", (filename, c))
            source_meta = db.execute("SELECT value FROM meta WHERE key='sources'").fetchone()
            if source_meta:
                sources = json.loads(source_meta[0])
                for source in sources:
                    if source["country"] in files:
                        source["readings"] = files[source["country"]]
                db.execute("UPDATE meta SET value=? WHERE key='sources'", (json.dumps(sources, separators=(",", ":")),))
        return changes
    finally:
        db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, default=APP / "data/rail.db")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    print("station name rows updated:", sync(args.database, check=args.check))
