#!/usr/bin/env python3
"""Apply the train-database recheck's confirmed corrections to the bundled master data.

Inputs (all tracked, nothing depends on the untracked docs folder):
  app/data/train-service-history/audits/corrections.json   copy of the recheck's machine-readable list
  app/data/train-service-history/audits/edits/*.json       one authored edit file per audit group

Every entry of `corrections` in the recheck file (two-source confirmed) is classified by the edit files:
  applied            the record fields in `set` / `notesReplace` / `notesAppend` / `split` / ... are written
  variantOnly        same-name variation: the base record is made truthful where the correction names the stops
                     and the service goes on audits/needs-variants.json (no per-number tables are invented)
  skippedHistorical  the correction judges a record whose validUntil is in the past against today's timetable
  notApplied         the evidence does not support a change on its own (reason recorded)
  deferred           the model or an input is missing (reason recorded); also every correction that targets the
                     timed sqlite, the catalog trip excerpts or the through-service file
A correction that no edit file classifies is an error.

Master files written: ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json and its mirror
app/data/train-service-history/derived/train-service-patterns.json (the legacy fallback rows of the derived
copy are replaced by the master rows, the canonical `tt-*` rows are kept untouched).

Every changed record gets a marker in `notes`:
  【2026-11-11 recheck: <ids>; sources: <urls>】
so the source URLs and the date checked stay with the record. The script is idempotent: a second run
changes nothing. `--check` writes nothing and exits 1 when a run would change a file.

Station codes of stops that a record did not have before are resolved by name: first from the record itself,
then from every other pattern, then from the rail package; an ambiguous or unknown name is an error (write
`name:code` in the edit file to force a code).

Usage:
  python3 ios/tools/apply-train-database-corrections.py [--check] [--quiet]
"""

from __future__ import annotations

import argparse
import copy
import glob
import json
import re
import sys
from collections import OrderedDict, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATTERNS = ROOT / "ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json"
DERIVED = ROOT / "app/data/train-service-history/derived/train-service-patterns.json"
PACKAGE = ROOT / "app/public/rail/jp-2025.json"
AUDITS = ROOT / "app/data/train-service-history/audits"
CORRECTIONS = AUDITS / "corrections.json"
EDITS = AUDITS / "edits"
VARIANTS = AUDITS / "needs-variants.json"
CHECKED = "2026-11-11"
MARKER = re.compile(r"\s*【" + CHECKED + r" recheck:[^】]*】")
MAX_URLS = 6
LEGACY = {"status": "legacy_unverified_fallback",
          "reason": "canonical timetable coverage is not yet sufficient for this service"}
AUTO_DEFERRED = (
    ("train-service-timetable.sqlite", "timed-sqlite",
     "row of the timed sqlite; it is built from the canonical JSONL tree, which is not in the repository"),
    ("line-service-catalog.json", "catalog-excerpt",
     "catalog trip excerpt that carries copied times; the stops-only decision removes those excerpts, so the correction is left to that change"),
    ("japan-through-services.json", "through-services",
     "through-service record: legs need station codes and line ids resolved per record, and the recheck gives the change only as free text; not done in this unit"),
)


class Fail(Exception):
    pass


def natural(cid):
    group, _, number = cid.partition("#")
    return (group, int(number))


def expand_ids(raw):
    if not raw:
        return []
    if isinstance(raw, list):
        return list(raw)
    group, _, rest = raw.partition("#")
    ids = []
    for part in rest.split(","):
        part = part.strip()
        if "-" in part:
            a, b = part.split("-")
            ids.extend(f"{group}#{n}" for n in range(int(a), int(b) + 1))
        else:
            ids.append(f"{group}#{part}")
    return ids


class Resolver:
    def __init__(self, patterns):
        self.global_codes = defaultdict(set)
        for record in patterns:
            for stop in record["stops"] + record["optionalStops"]:
                self.global_codes[stop["name"]].add(stop["sourceCode"])
        self.package_codes = defaultdict(lambda: defaultdict(set))
        package = json.loads(PACKAGE.read_text(encoding="utf-8"))
        for line in package["lines"]:
            for station in line["stations"]:
                self.package_codes[station[1]][station[0]].add(line["name"])

    def code(self, name, record):
        if ":" in name:
            name, code = name.split(":", 1)
            return code
        own = {s["name"]: s["sourceCode"] for s in record["stops"] + record["optionalStops"]}
        if name in own:
            return own[name]
        codes = self.global_codes.get(name, set())
        if len(codes) == 1:
            return next(iter(codes))
        wanted = set()
        for line in record["lines"]:
            wanted.add(line)
            wanted.add(line.replace("本線", "線"))
            wanted.add(line.replace("線", "本線"))
        candidates = self.package_codes.get(name, {})
        if len(candidates) == 1:
            return next(iter(candidates))
        on_lines = [c for c, lines in candidates.items() if lines & wanted]
        if len(on_lines) == 1:
            return on_lines[0]
        if len(codes) > 1:
            on_lines = [c for c in codes if c in candidates and candidates[c] & wanted]
            if len(on_lines) == 1:
                return on_lines[0]
        raise Fail(f"cannot resolve station {name!r} for {record['patternId']} "
                   f"(patterns {sorted(codes)}, package {sorted(candidates)})")


def stop_list(names, record, resolver):
    stops, seen = [], set()
    for token in names.split():
        name = token.split(":", 1)[0]
        if name in seen:
            raise Fail(f"duplicate station {name} in a list of {record['patternId']}")
        seen.add(name)
        stops.append(OrderedDict([("name", name), ("sourceCode", resolver.code(token, record))]))
    return stops


def apply_set(record, fields, resolver):
    for key, value in fields.items():
        if key in ("stops", "optionalStops"):
            record[key] = stop_list(value, record, resolver)
        elif key == "lines":
            record["lines"] = value.split()
        elif key == "completeness":
            record["completeness"] = {**record["completeness"], **value}
        elif key == "allStations":
            record["allStations"] = bool(value)
        elif key in ("validFrom", "validUntil", "origin", "destination", "label", "company", "name", "via"):
            record[key] = value
        else:
            raise Fail(f"unsupported set key {key}")
    names = [s["name"] for s in record["stops"]] + [s["name"] for s in record["optionalStops"]]
    if len(names) != len(set(names)):
        raise Fail(f"{record['patternId']}: a station is both always served and optional")


def apply_notes(record, entry):
    notes = record.get("notes") or ""
    for old, new in entry.get("notesReplace", []):
        if old in notes:
            notes = notes.replace(old, new)
        elif new not in notes:
            raise Fail(f"{record['patternId']}: note text {old!r} not found")
    append = entry.get("notesAppend")
    if append and append not in notes:
        notes = (notes + " " + append).strip()
    record["notes"] = notes
    add = entry.get("companyAdd")
    if add and add not in record["company"].split("/"):
        record["company"] = record["company"] + "/" + add


def first_url(corrections, ids, wikipedia=False):
    for cid in ids:
        item = corrections[cid]
        for url in item["verifierSourceURLs"] + item["auditorSourceURLs"]:
            if url.startswith("http") and ("wikipedia" in url) == wikipedia:
                return url
    return None


def urls_for(corrections, ids, extra):
    urls = []
    for cid in ids:
        item = corrections[cid]
        for url in item["verifierSourceURLs"] + item["auditorSourceURLs"]:
            if url.startswith("http") and url not in urls:
                urls.append(url)
    for url in extra:
        if url not in urls:
            urls.append(url)
    return urls[:MAX_URLS]


def short_id(cid):
    group, number = cid.split("#")
    return group + "#" + number


def marker(ids, urls, basis):
    parts = ", ".join(sorted((short_id(i) for i in ids), key=lambda s: natural(s)))
    text = f"【{CHECKED} recheck: {parts or basis}; sources: {' '.join(urls)}】"
    return text


def load_edits():
    entries = []
    for path in sorted(glob.glob(str(EDITS / "*.json"))):
        for index, entry in enumerate(json.loads(Path(path).read_text(encoding="utf-8"))):
            entry["_where"] = f"{Path(path).name}[{index}]"
            entry["ids"] = expand_ids(entry.get("ids"))
            entries.append(entry)
    # a split entry written before the entry that holds the ids of the same record inherits those ids
    for index, entry in enumerate(entries):
        if entry["ids"] or entry.get("basis") or entry.get("status", "applied") != "applied":
            continue
        for later in entries[index + 1:]:
            if later["record"] == entry["record"] and later["ids"]:
                entry["ids"] = list(later["ids"])
                entry["_inherited"] = True
                break
    return entries


def classify(corrections, entries):
    status = {}
    for cid, item in corrections.items():
        for fragment, kind, reason in AUTO_DEFERRED:
            if fragment in item["recordFile"]:
                status[cid] = ("deferred", kind, reason)
    for entry in entries:
        state = entry.get("status", "applied")
        for cid in ([] if entry.get("_inherited") else entry["ids"]):
            if cid not in corrections:
                raise Fail(f"{entry['_where']}: {cid} is not a confirmed correction")
            if cid in status:
                raise Fail(f"{entry['_where']}: {cid} is classified twice")
            status[cid] = (state, entry.get("kind", ""), entry.get("reason", ""))
    missing = sorted((c for c in corrections if c not in status), key=natural)
    if missing:
        raise Fail("corrections without an edit entry: " + ", ".join(missing))
    return status


def run(check, quiet):
    corrections_doc = json.loads(CORRECTIONS.read_text(encoding="utf-8"))
    corrections = OrderedDict((c["id"], c) for c in corrections_doc["corrections"])
    entries = load_edits()
    status = classify(corrections, entries)

    original_text = PATTERNS.read_text(encoding="utf-8")
    patterns = json.loads(original_text, object_pairs_hook=OrderedDict)
    before = {r["patternId"]: copy.deepcopy(r) for r in patterns}
    resolver = Resolver(patterns)
    by_id = {r["patternId"]: r for r in patterns}
    evidence = defaultdict(lambda: {"ids": [], "urls": [], "basis": ""})
    variants = defaultdict(lambda: {"patterns": set(), "distinct": None, "reports": set(), "ids": set()})

    def touch(pid, entry):
        item = evidence[pid]
        for cid in entry["ids"]:
            if cid not in item["ids"]:
                item["ids"].append(cid)
        for url in entry.get("sourceURLs", []):
            if url not in item["urls"]:
                item["urls"].append(url)
        if entry.get("basis"):
            item["basis"] = entry["basis"]

    for entry in entries:
        state = entry.get("status", "applied")
        if state in ("notApplied", "skippedHistorical", "deferred"):
            if entry["record"] not in by_id and "split" not in entry:
                raise Fail(f"{entry['_where']}: unknown record {entry['record']}")
            continue
        pid = entry["record"]
        record = by_id.get(pid)
        if record is None:
            raise Fail(f"{entry['_where']}: unknown record {pid}")
        split = entry.get("split")
        if split:
            clone_id = split["newId"]
            if clone_id not in by_id:
                clone = copy.deepcopy(record)
                clone["patternId"] = clone_id
                clone["validUntil"] = split["at"]
                if split.get("cloneValidFrom"):
                    clone["validFrom"] = split["cloneValidFrom"]
                for name in split.get("dropStops", []):
                    clone["stops"] = [s for s in clone["stops"] if s["name"] != name]
                    clone["optionalStops"] = [s for s in clone["optionalStops"] if s["name"] != name]
                if split.get("setClone"):
                    apply_set(clone, split["setClone"], resolver)
                index = patterns.index(record) + 1
                patterns.insert(index, clone)
                by_id[clone_id] = clone
                before.setdefault(clone_id, None)
            if record.get("validFrom") != split["at"]:
                record["validFrom"] = split["at"]
            if split.get("setBase"):
                apply_set(record, split["setBase"], resolver)
            touch(clone_id, entry)
        if entry.get("set"):
            apply_set(record, entry["set"], resolver)
        if entry.get("citeSource"):
            url = first_url(corrections, entry["ids"]) or first_url(corrections, entry["ids"], wikipedia=True)
            if url:
                record["source"] = url
        apply_notes(record, entry)
        touch(pid, entry)
        spec = entry.get("variants")
        if spec:
            item = variants[spec["service"]]
            item["patterns"].add(pid)
            item["reports"].add(spec["report"])
            item["ids"].update(entry["ids"])
            if spec.get("distinctPatterns"):
                item["distinct"] = max(item["distinct"] or 0, spec["distinctPatterns"])

    # historical guard: a record may not change on a correction that judges it against today's timetable
    for cid, (state, _, _) in status.items():
        if state == "skippedHistorical":
            record = by_id.get(corrections[cid]["recordId"])
            if record is not None and not (record.get("validUntil") and record["validUntil"] < CHECKED):
                raise Fail(f"{cid} is marked historical but {record['patternId']} is current")

    for pid, item in evidence.items():
        record = by_id[pid]
        # the app applies a pattern as a ride from origin to destination, so both must be the first and last
        # always-served stop: a terminal that only some trains reach is optional and the ends move inward
        if len(record["stops"]) < 2:
            raise Fail(f"{pid}: fewer than two always-served stops")
        for key, stop in (("origin", record["stops"][0]), ("destination", record["stops"][-1])):
            if record[key] != stop["name"]:
                record[key] = stop["name"]
        if record.get("unsolvableLegs"):
            pairs = [[a["name"], b["name"]] for a, b in zip(record["stops"], record["stops"][1:])]
            record["unsolvableLegs"] = [leg for leg in record["unsolvableLegs"] if leg in pairs]
            if not record["unsolvableLegs"]:
                del record["unsolvableLegs"]
        notes = MARKER.sub("", record.get("notes") or "").rstrip()
        urls = urls_for(corrections, item["ids"], item["urls"])
        record["notes"] = (notes + " " + marker(item["ids"], urls, item["basis"])).strip()

    out_patterns = json.dumps(patterns, ensure_ascii=False, indent=1) + "\n"

    derived = json.loads(DERIVED.read_text(encoding="utf-8"))
    keep = [r for r in derived if "_derivation" not in r or r["_derivation"] != LEGACY]
    mirrored = [dict(copy.deepcopy(r), _derivation=LEGACY) for r in patterns]
    out_derived = json.dumps(sorted(keep + mirrored, key=lambda r: r["patternId"]),
                             ensure_ascii=False, indent=2, sort_keys=True) + "\n"

    needs = {
        "schema": 1,
        "checkedOn": CHECKED,
        "note": ("Services whose stop pattern differs by train number or date. The base record in train-service-patterns.json "
                 "lists what every train of the name calls at (stops) and what only some call at (optionalStops); "
                 "the per-number tables still have to be authored from dated public timetables "
                 "(ios/tools/shinkansen-patterns.md for the Shinkansen model). No number is inferred."),
        "services": [
            OrderedDict([
                ("service", name),
                ("patterns", sorted(item["patterns"])),
                ("distinctPatterns", item["distinct"]),
                ("source", sorted("docs/maintenance/database-audit/" + r for r in item["reports"])),
                ("corrections", sorted(item["ids"], key=natural)),
            ]) for name, item in sorted(variants.items())
        ],
    }
    out_variants = json.dumps(needs, ensure_ascii=False, indent=1) + "\n"

    changed_records = [pid for pid in by_id if before.get(pid) != by_id[pid]]
    outputs = {PATTERNS: out_patterns, DERIVED: out_derived, VARIANTS: out_variants}
    changes = {p: (p.read_text(encoding="utf-8") if p.exists() else None) != text for p, text in outputs.items()}

    if not quiet:
        for pid in changed_records:
            report(pid, before.get(pid), by_id[pid])
    counts = defaultdict(int)
    for state, _, _ in status.values():
        counts[state] += 1
    print(f"corrections: {len(status)} classified")
    for state in ("applied", "variantOnly", "skippedHistorical", "notApplied", "deferred"):
        print(f"  {state}: {counts[state]}")
    deferred = defaultdict(int)
    for state, kind, _ in status.values():
        if state == "deferred":
            deferred[kind or "other"] += 1
    for kind, number in sorted(deferred.items()):
        print(f"    deferred/{kind}: {number}")
    print(f"records changed in train-service-patterns.json: {len(changed_records)} "
          f"({sum(1 for p in changed_records if before.get(p) is None)} new)")
    print(f"needs-variants services: {len(needs['services'])}")
    for path, flag in changes.items():
        print(f"  {path.relative_to(ROOT)}: {'WOULD CHANGE' if flag else 'unchanged'}")
    if check:
        return 1 if any(changes.values()) else 0
    for path, text in outputs.items():
        if changes[path]:
            path.write_text(text, encoding="utf-8")
    return 0


def describe(record):
    return {
        "stops": [s["name"] for s in record["stops"]],
        "optionalStops": [s["name"] for s in record["optionalStops"]],
    }


def report(pid, old, new):
    if old is None:
        print(f"+ {pid}: new record valid {new['validFrom']}..{new['validUntil']}")
        return
    lines = []
    for key in ("stops", "optionalStops"):
        a, b = describe(old)[key], describe(new)[key]
        gone, added = [n for n in a if n not in b], [n for n in b if n not in a]
        moved = a != b and not gone and not added
        if gone or added or moved:
            lines.append(f"    {key}: -{' '.join(gone) or '0'} +{' '.join(added) or '0'}" + (" (order)" if moved else ""))
    for key in ("validFrom", "validUntil", "origin", "destination", "label", "company", "name", "lines", "allStations", "source"):
        if old.get(key) != new.get(key):
            lines.append(f"    {key}: {old.get(key)!r} -> {new.get(key)!r}")
    if old.get("completeness") != new.get("completeness"):
        lines.append(f"    completeness: {old.get('completeness')} -> {new.get('completeness')}")
    if MARKER.sub("", old.get("notes") or "") != MARKER.sub("", new.get("notes") or ""):
        lines.append("    notes text changed")
    print(f"~ {pid}" + ("" if lines else " (source note only)"))
    for line in lines:
        print(line)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="write nothing; exit 1 if a file would change")
    parser.add_argument("--quiet", action="store_true", help="skip the per-record diff summary")
    args = parser.parse_args(argv)
    try:
        return run(args.check, args.quiet)
    except Fail as error:
        print("error:", error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
