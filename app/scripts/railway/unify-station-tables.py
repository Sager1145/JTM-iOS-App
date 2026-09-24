#!/usr/bin/env python3
"""Convert the jp/tw/hk/mo station tables to the ADR 0010 schema (idempotent).

- stations.json: N02_* property keys -> neutral schema keys.
- stations-hk/mo.json, station-readings-hk/mo.json byCode keys, train-store-hk/mo.json:
  platform codes -> {OPERATOR}-{STOP} (see canonical_code).
- stations-tw.json, station-readings-tw.json byCode keys, train-store-tw.json:
  KLRT-NETWORK-{STOP} -> KLRT-{STOP} (see canonical_tw_code).
- all four readings files: one row shape, plus a `schema` member; hk/mo/tw `stats`
  byCode/byName counts refreshed; jp `note` names the neutral key.

See docs/decisions/0010-unified-station-tables.md. Stdlib only.
"""
import json
import os
import re
import sys

DATA = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data"))

N02_RENAME = {
    "N02_001": "railway_class_code",
    "N02_002": "institution_type_code",
    "N02_003": "line_name",
    "N02_004": "operator",
    "N02_005": "station_name",
    "N02_005c": "n02_station_code",
    "N02_005g": "n02_group_code",
}
SCHEMA_ORDER = [
    "railway_class_code", "institution_type_code", "line_name", "operator",
    "station_name", "n02_station_code", "n02_group_code", "display_point",
]
READING_KEYS = ["name", "zh_Hant", "zh_Hans", "en", "ja", "kana", "katakana", "romaji"]
READINGS_SCHEMA = "station-readings/1"
CODE_KEYS = {"n02_station_code", "from_n02_station_code", "to_n02_station_code"}
OPERATOR_SEGMENTS = {"MTR", "LR", "MLM"}


def canonical_code(code):
    """Legacy HK/MO platform code -> canonical {OPERATOR}-{STOP}; anything else unchanged."""
    if not isinstance(code, str):
        return code
    parts = code.split("-")
    if len(parts) >= 3 and parts[-2] in OPERATOR_SEGMENTS:
        return f"{parts[-2]}-{parts[-1]}"
    if len(parts) >= 3 and parts[0] == "TRAM":
        return f"TRAM-{parts[-1]}"
    return code


def canonical_tw_code(code):
    """Taiwan code with a NETWORK segment -> {OPERATOR}-{STOP}; anything else unchanged."""
    if not isinstance(code, str):
        return code
    parts = code.split("-")
    if len(parts) >= 3 and parts[1] == "NETWORK":
        return "-".join(parts[:1] + parts[2:])
    return code


JP_NOTE_OLD = "keyed by N02 station code (N02_005c)"
JP_NOTE_NEW = "keyed by n02_station_code (the N02_005c value)"


# ---------- formatting-preserving IO ----------

def load(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    fmt = {"newline": text.endswith("\n"), "indent": None, "separators": (",", ":")}
    lines = text.split("\n", 2)
    if len(lines) > 1 and lines[1].strip():
        m = re.match(r"^( +|\t+)", lines[1])
        if m:
            ws = m.group(1)
            fmt["indent"] = ws if ws.startswith("\t") else len(ws)
            fmt["separators"] = (",", ": ")
    if fmt["indent"] is None:
        head = text[:4096]
        if '": ' in head or '", "' in head:
            fmt["separators"] = (", ", ": ")
    return json.loads(text), fmt, text


def dump(path, data, fmt, original):
    out = json.dumps(data, ensure_ascii=False, indent=fmt["indent"], separators=fmt["separators"])
    if fmt["newline"]:
        out += "\n"
    if out == original:
        return False
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(out)
    return True


# ---------- converters ----------

def convert_jp_stations(data):
    for feat in data["features"]:
        props = feat["properties"]
        renamed = {}
        for key, value in props.items():
            new = N02_RENAME.get(key, key)
            if new in renamed and renamed[new] != value:
                raise AssertionError(f"stations.json: conflicting {key}/{new} on {props}")
            renamed[new] = value
        ordered = {k: renamed[k] for k in SCHEMA_ORDER if k in renamed}
        for k, v in renamed.items():
            if k not in ordered:
                ordered[k] = v
        feat["properties"] = ordered


def convert_tw_stations(data):
    for feat in data["features"]:
        props = feat["properties"]
        props["n02_station_code"] = canonical_tw_code(props["n02_station_code"])


def convert_codes_stations(data, region, fname):
    prefix = f"{region}-official-"
    for feat in data["features"]:
        props = feat["properties"]
        props["n02_station_code"] = canonical_code(props["n02_station_code"])
        group = props["n02_group_code"]
        assert group.startswith(prefix), f"{fname}: group {group!r} lacks {prefix}"
        expected = group[len(prefix):].upper()
        assert props["n02_station_code"] == expected, (
            f"{fname}: {props['station_name']} code {props['n02_station_code']!r} != group tail {expected!r}")


def rename_bycode(data, fname, rule=None):
    rule = rule or canonical_code
    out = {}
    for key, row in data["byCode"].items():
        new = key if ":" in key else rule(key)
        if new in out:
            assert out[new] == row, f"{fname}: {key!r} -> {new!r} collides with a different row"
            continue
        out[new] = row
    data["byCode"] = out


def normalise_row(row, fallback_name=None):
    for k, v in row.items():
        if k not in READING_KEYS:
            raise AssertionError(f"unexpected readings key {k!r} in {row}")
    new = {k: row.get(k, "") for k in READING_KEYS}
    if not new["name"] and fallback_name is not None and "name" not in row:
        new["name"] = fallback_name
    return new


def normalise_readings(data):
    data["byCode"] = {k: normalise_row(r) for k, r in data["byCode"].items()}
    data["byName"] = {k: normalise_row(r, fallback_name=k) for k, r in data.get("byName", {}).items()}
    rebuilt = {}
    if "note" not in data:
        rebuilt["schema"] = READINGS_SCHEMA
    for k, v in data.items():
        if k == "schema":
            continue
        rebuilt[k] = v
        if k == "note":
            rebuilt["schema"] = READINGS_SCHEMA
    data.clear()
    data.update(rebuilt)


def refresh_stats(data):
    stats = data.get("stats")
    if isinstance(stats, dict):
        if "byCode" in stats:
            stats["byCode"] = len(data["byCode"])
        if "byName" in stats:
            stats["byName"] = len(data.get("byName", {}))


def reword_jp_note(data):
    note = data.get("note")
    if isinstance(note, str) and JP_NOTE_OLD in note:
        data["note"] = note.replace(JP_NOTE_OLD, JP_NOTE_NEW)


def rewrite_codes(node, rule=None):
    rule = rule or canonical_code
    if isinstance(node, dict):
        for k, v in node.items():
            if k in CODE_KEYS and isinstance(v, str):
                node[k] = rule(v)
            else:
                rewrite_codes(v, rule)
    elif isinstance(node, list):
        for item in node:
            rewrite_codes(item, rule)


def assert_tw_unchanged():
    data, _, _ = load(os.path.join(DATA, "stations-tw.json"))
    for feat in data["features"]:
        c = feat["properties"]["n02_station_code"]
        assert canonical_code(c) == c, f"stations-tw.json: rule changes tw code {c!r}"
    readings, _, _ = load(os.path.join(DATA, "station-readings-tw.json"))
    for key in readings["byCode"]:
        if ":" not in key:
            assert canonical_code(key) == key, f"station-readings-tw.json: rule changes tw key {key!r}"


def process(fname, fn):
    path = os.path.join(DATA, fname)
    data, fmt, original = load(path)
    fn(data)
    changed = dump(path, data, fmt, original)
    print(f"{'changed ' if changed else 'unchanged'} {fname}")
    return changed


def main():
    assert_tw_unchanged()
    changed = False
    changed |= process("stations.json", convert_jp_stations)
    for region in ("hk", "mo"):
        changed |= process(f"stations-{region}.json",
                           lambda d, r=region: convert_codes_stations(d, r, f"stations-{r}.json"))
        changed |= process(f"train-store-{region}.json", rewrite_codes)
    # Taiwan: the HK/MO rule is a no-op there (asserted above); the tw rule runs after it.
    changed |= process("stations-tw.json", convert_tw_stations)
    changed |= process("train-store-tw.json", lambda d: rewrite_codes(d, canonical_tw_code))
    changed |= process("station-readings.json", lambda d: (reword_jp_note(d), normalise_readings(d)))
    changed |= process("station-readings-tw.json",
                       lambda d: (rename_bycode(d, "station-readings-tw.json", canonical_tw_code),
                                  normalise_readings(d), refresh_stats(d)))
    for region in ("hk", "mo"):
        fname = f"station-readings-{region}.json"
        changed |= process(fname, lambda d, f=fname: (rename_bycode(d, f), normalise_readings(d),
                                                      refresh_stats(d)))
    print("done:", "files rewritten" if changed else "nothing to change")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as exc:
        print(f"ASSERTION FAILED: {exc}", file=sys.stderr)
        sys.exit(1)
