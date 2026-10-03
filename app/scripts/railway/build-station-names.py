#!/usr/bin/env python3
"""Project retained readings and English identities into the tables the UI reads.

JP bare keys remain platform codes; map keys are line:group, never bare group
aliases. US/CA resources are frozen and are neither read nor written here.
"""
import argparse
from collections import defaultdict
import copy
import hashlib
import json
from pathlib import Path
import re
import unicodedata

APP = Path(__file__).resolve().parents[2]
REGIONS = ("jp", "tw", "hk", "mo", "kr")
FIELDS = ("name", "zh_Hant", "zh_Hans", "en", "ja", "kana", "katakana", "romaji")


def normalize(name):
    value = re.sub(r"\s+", "", unicodedata.normalize("NFKC", name).strip())
    return value.translate(str.maketrans({"ヶ": "ケ", "ヵ": "カ", "ゖ": "け", "ゕ": "か"}))


def resource(family, region):
    return f"{family}{'-' + region if region != 'jp' else ''}.json"


def chinese_rendering(name, variants):
    # Orthography only. Kana/Latin/ambiguous shinjitai require a station-specific
    # translation, so they stay blank rather than turning into invented names.
    if not re.fullmatch(r"[\u3400-\u9fff々]+", name):
        return None
    if any(c in name for c in variants.get("ambiguousJapaneseCharacters", [])):
        return None
    hant = "".join(variants.get("jpToTraditional", {}).get(c, c) for c in name)
    hans = "".join(variants.get("traditionalToSimplified", {}).get(c, c) for c in hant)
    return hant, hans


def common_row(rows):
    """Retain only fields shared by every identity behind an alias."""
    return {field: rows[0][field] if len({r[field] for r in rows}) == 1 else ""
            for field in FIELDS}


def build_region(region, package, readings, english, stations, kana=None, variants=None):
    kana, variants = kana or {}, variants or {}
    old_code = readings.get("byCode", {})
    old_name = {normalize(k): v for k, v in readings.get("byName", {}).items()}
    name_groups = defaultdict(set)
    features_by_group = defaultdict(list)
    for feature in stations["features"]:
        props = feature["properties"]
        features_by_group[props["n02_group_code"]].append(props)
    for line in package["lines"]:
        for group, name, *_ in line["stations"]:
            name_groups[normalize(name)].add(group)
    by_code = {}
    aliases = defaultdict(list)
    name_rows = defaultdict(list)
    details = []
    for line in package["lines"]:
        for seq, station in enumerate(line["stations"]):
            group, name = station[:2]
            key = f"{line['id']}:{group}"
            members = english["byCode"][group]["memberships"]
            member = next(m for m in members if m["lineId"] == line["id"] and m["seq"] == seq)
            if member["name"] != name:
                raise ValueError(f"stale English identity: {key}")
            props = [p for p in features_by_group[group]
                     if p["operator"] == line["operator"] and normalize(p["station_name"]) == normalize(name)]
            exact = [p for p in props if p["line_name"] == line["name"]]
            if exact:
                props = exact
            codes = sorted({p["n02_station_code"] for p in props})
            if region == "jp":
                candidates = [old_code[c] for c in codes if c in old_code
                              and normalize(old_code[c].get("name", "")) == normalize(name)]
                original = common_row([{f: r.get(f, "") for f in FIELDS} for r in candidates]) if candidates else None
                if key in old_code:
                    original = old_code[key]
                if original is None and len(name_groups[normalize(name)]) == 1:
                    original = old_name.get(normalize(name))
            else:
                original = old_code.get(key)
                if original is None:
                    candidates = [old_code[c] for c in codes if c in old_code]
                    original = common_row([{f: r.get(f, "") for f in FIELDS} for r in candidates]) if candidates else None
                if original is None and len(name_groups[normalize(name)]) == 1:
                    original = old_name.get(normalize(name))
            row = {f: (original or {}).get(f, "") for f in FIELDS}
            row["name"] = name
            row["en"] = member["en"] or ""
            provenance = {"key": key, "group": group, "name": name,
                          "platformCodes": codes, "englishSource": member["source"],
                          "englishStatus": member["status"]}
            if region == "jp":
                row["ja"] = name
                # Keep pronunciation and the operator's English translation
                # separately queryable (Fukudai-Mae / Fukuoka University).
                row["romaji"] = row["romaji"] or (station[4] if len(station) > 4 else "") or row["en"]
                explicit = kana.get(key)
                if explicit:
                    if normalize(explicit["name"]) != normalize(name):
                        raise ValueError(f"stale kana identity: {key}")
                    row["kana"], row["katakana"] = explicit["kana"], explicit["katakana"]
                    provenance["kanaEvidence"] = "data/station-name-sources/jp-kana-evidence.json#byLineStation/" + key
                rendering = chinese_rendering(name, variants)
                if rendering and (not row["zh_Hant"] or not row["zh_Hans"]):
                    row["zh_Hant"] = row["zh_Hant"] or rendering[0]
                    row["zh_Hans"] = row["zh_Hans"] or rendering[1]
                    provenance["chineseSource"] = "OpenCC character rendering; not official translation"
            by_code[key] = row
            for code in codes:
                aliases[code].append(row)
            name_rows[normalize(name)].append(row)
            details.append(provenance)
    # Unmapped historical platform aliases stay readable, but group summaries
    # must never overwrite a platform code that happens to have the same digits.
    for code, row in old_code.items():
        if ":" not in code:
            by_code[code] = {f: row.get(f, "") for f in FIELDS}
    for code, rows in aliases.items():
        by_code[code] = common_row(rows)
    by_name = {}
    for name, rows in name_rows.items():
        if len(name_groups[name]) == 1:
            by_name[name] = common_row(rows)
    output = {k: copy.deepcopy(v) for k, v in readings.items()
              if k not in ("byCode", "byName", "note", "stats")}
    output.update(schema="station-readings/1", country=region.upper(), packageVersion=package["version"],
                  note="Derived UI names. Exact line:group keys precede platform/name aliases. English review status and kana evidence are retained in station-names-coverage.json. Missing readings remain blank.",
                  byCode=dict(sorted(by_code.items())), byName=dict(sorted(by_name.items())))
    map_rows = [by_code[d["key"]] for d in details]
    stats = {"groups": len(english["byCode"]), "memberships": len(map_rows),
             "withEnglish": sum(bool(r["en"]) for r in map_rows),
             "withKana": sum(bool(r["kana"]) for r in map_rows),
             "withTraditionalChinese": sum(bool(r["zh_Hant"]) for r in map_rows),
             "withSimplifiedChinese": sum(bool(r["zh_Hans"]) for r in map_rows)}
    return output, {"stats": stats, "memberships": details,
                    "missingKana": [d["key"] for d in details if not by_code[d["key"]]["kana"]] if region == "jp" else []}


def build(app=APP):
    inputs = {}
    def read(relative):
        path = app / relative
        inputs[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        return json.loads(path.read_text(encoding="utf-8"))
    catalog = read("data/station-english.json")
    variants = read("data/station-name-sources/opencc/script-variants.json")
    kana_evidence = read("data/station-name-sources/jp-kana-evidence.json")
    kana = kana_evidence["byLineStation"]
    output, report = {}, {"schema": "station-names-coverage/1", "regions": {}}
    for region in REGIONS:
        readings = read("data/" + resource("station-readings", region))
        package = read(f"public/rail/{region}-2025.json")
        stations = read("data/" + resource("stations", region))
        output[resource("station-names", region)], report["regions"][region] = build_region(
            region, package, readings, catalog["byCountry"][region], stations, kana if region == "jp" else {}, variants)
    report["inputSha256"] = dict(sorted(inputs.items()))
    return output, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--rebuild-kana", action="store_true", help="re-extract the curated snapshot from retained raw operator archives")
    parser.add_argument("--check-kana-sources", action="store_true", help="verify the curated snapshot against retained raw archives (requires local sources)")
    args = parser.parse_args()
    if args.rebuild_kana or args.check_kana_sources:
        from lib.jp_station_kana import build_kana_evidence
        snapshot = json.dumps(build_kana_evidence(APP), ensure_ascii=False, indent=2) + "\n"
        path = APP / "data/station-name-sources/jp-kana-evidence.json"
        if args.check_kana_sources:
            if not path.exists() or path.read_text(encoding="utf-8") != snapshot:
                raise SystemExit("curated kana differs from retained raw sources")
        else:
            path.write_text(snapshot, encoding="utf-8")
    tables, report = build()
    tables["station-names-coverage.json"] = report
    for name, data in tables.items():
        text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        path = APP / "data" / name
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                raise SystemExit(f"{name} is stale; run build-station-names.py")
        else:
            path.write_text(text, encoding="utf-8")
    for region, data in report["regions"].items():
        print(region, data["stats"])


if __name__ == "__main__":
    main()
