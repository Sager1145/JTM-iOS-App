#!/usr/bin/env python3
"""Apply the train-database recheck's confirmed corrections to the bundled master data.

Inputs (all tracked, nothing depends on the untracked docs folder):
  app/data/train-service-history/audits/corrections.json   copy of the recheck's machine-readable list
  app/data/train-service-history/audits/edits/*.json       one authored edit file per audit group
  app/data/train-service-history/audits/baseline-patterns.json  the master as it was before any correction

Every run starts from the baseline, applies all edits and compares the result with the current master:
a record the script changes must equal either the baseline or the script's result, otherwise the run stops
and names the record and fields (a hand edit is never overwritten silently; move it into an edit file).
Split records (older eras) are rebuilt from the baseline on every run, so they cannot drift. Records the
script does not touch are taken from the current master.

Period rule: a correction only changes what its evidence covers. A record that ended before the check date
may change only when its entry carries `periodEvidence`; a record in force before 2026-03-14 (ERA, the
timetable the recheck read) that gains an always-served stop, loses a station or gains a line must be split
at that date (`split.at`: the older era keeps its data) or carry `periodEvidence`. The labels of split
records get their period regenerated from the dates; a moved terminal is named in the label.

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
BASELINE = AUDITS / "baseline-patterns.json"
ERA = "2026-03-14"
CHECKED = "2026-11-11"
CLOCK_TEXT = re.compile(r"(?<![0-9A-Za-z:@.+\-])\d{1,2}[:：]\d{2}(?![0-9:])|(?<![0-9-])\d{1,2}時(?:\d{1,2}分|(?=[発着]))")  # same as train_timetable.CLOCK_TEXT
MARKER = re.compile(r"\s*【" + CHECKED + r" recheck:[^】]*】")
MAX_URLS = 6
# Stops-only decision: the bundled data carries no copied clock times. The baseline is the pre-correction
# master and is not tracked, so the removal of the clock times from its notes is recorded here and applied
# to the baseline as it is read (every other record, clone and edit then starts from the scrubbed text).
STOPS_ONLY_NOTE_SCRUBS = {
    "muroto-tokushima-mugi": [("（徳島19:33→牟岐20:58）", "（徳島→牟岐）"), ("（牟岐6:59→徳島8:20）", "（牟岐→徳島）")],
    "ariake-omuta-hakata": [("（大牟田6:43発・久留米7:12発）", "（大牟田発・久留米発）")],
    "kaio-nogata-hakata": [("3号(直方10:00発)に時刻変更", "3号(直方発)に時刻変更")],
    "iyonada-monogatari-matsuyama-iyo-ozu": [("（松山8:28発→", "（松山発→"), ("伊予大洲10:28着）", "伊予大洲着）")],
    "iyonada-monogatari-matsuyama-yawatahama": [
        ("（松山13:38発→", "（松山発→"), ("伊予大洲15:13着→八幡浜15:56着）", "伊予大洲着→八幡浜着）"),
        ("（八幡浜16:27発→", "（八幡浜発→"), ("→松山18:30着）", "→松山着）")],
}
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
    text = f"【{CHECKED} recheck: {parts or basis}" + (f"; sources: {' '.join(urls)}】" if urls else "】")
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


def splits_of(entry):
    split = entry.get("split")
    return split if isinstance(split, list) else ([split] if split else [])


def names_of(items):
    return [s["name"] for s in items]


def period_problems(entries_by_record, pre, post, corrections):
    """Records that a correction changed outside the period its evidence covers (see the module doc)."""
    problems = []
    for pid, items in entries_by_record.items():
        if pid not in pre or any(e.get("periodEvidence") for e in items):
            continue
        a, b = pre[pid], post[pid]
        keys = ("stops", "optionalStops", "lines", "origin", "destination", "validFrom", "validUntil", "allStations")
        if all(a.get(k) == b.get(k) for k in keys):
            continue
        if a.get("validUntil") and a["validUntil"] < CHECKED:
            problems.append(f"{pid}: ended {a['validUntil']} but changed without periodEvidence "
                            f"({', '.join(e['_where'] for e in items)})")
            continue
        in_force_before_era = ((a.get("validFrom") is None or a["validFrom"] < ERA)
                               and (a.get("validUntil") is None or a["validUntil"] >= ERA))
        if not in_force_before_era:
            continue
        added = [n for n in names_of(b["stops"]) if n not in names_of(a["stops"])]
        gone = [n for n in names_of(a["stops"]) + names_of(a["optionalStops"])
                if n not in names_of(b["stops"]) + names_of(b["optionalStops"])]
        lines = [n for n in b["lines"] if n not in a["lines"]]
        if added or gone or lines:
            problems.append(f"{pid}: valid from {a.get('validFrom')}, evidence covers the {ERA} timetable only; "
                            f"adds always {added or '-'}, removes {gone or '-'}, adds lines {lines or '-'} "
                            f"({', '.join(e['_where'] for e in items)}): split at {ERA} (split.at) or give periodEvidence")
    return problems


def new_label(record, pre, explicit):
    """A moved terminal keeps the label honest: the label names the old ends, the ride is origin to destination."""
    if explicit or (record["origin"] == pre["origin"] and record["destination"] == pre["destination"]):
        return record["label"]
    return f"{record['label']}（全列車に共通する区間 {record['origin']}〜{record['destination']}）"


PERIOD_RANGE = re.compile(r"(\d{4})年(\d{1,2})月〜(\d{4})年(\d{1,2})月")
PERIOD_UNTIL = re.compile(r"(\d{4})年(\d{1,2})月まで")
PERIOD_FROM = re.compile(r"(\d{4})年(\d{1,2})月(〜|から|以降)")
PERIOD_YEARS = re.compile(r"\d{4}[–〜]\d{4}")


def year_month(day):
    year, month, _ = day.split("-")
    return f"{int(year)}年{int(month)}月"


def period_label(record):
    """The period named in the label of a split record is regenerated from its own validity dates."""
    label, start, end = record["label"], record.get("validFrom"), record.get("validUntil")
    if PERIOD_RANGE.search(label) and start and end:
        return PERIOD_RANGE.sub(f"{year_month(start)}〜{year_month(end)}", label, count=1)
    if PERIOD_UNTIL.search(label) and end:
        return PERIOD_UNTIL.sub(f"{year_month(end)}まで", label, count=1)
    if PERIOD_FROM.search(label) and start:
        return PERIOD_FROM.sub(lambda m: f"{year_month(start)}{m.group(3)}", label, count=1)
    if PERIOD_YEARS.search(label) or PERIOD_RANGE.search(label) or PERIOD_UNTIL.search(label) or PERIOD_FROM.search(label):
        return label
    if start and end:
        return f"{label}（{year_month(start)}〜{year_month(end)}）"
    if end:
        return f"{label}（{year_month(end)}まで）"
    if start:
        return f"{label}（{year_month(start)}〜）"
    return label


def scrub_baseline_notes(baseline):
    """Apply STOPS_ONLY_NOTE_SCRUBS to the baseline records; an entry that no longer matches is an error."""
    by_id = {r["patternId"]: r for r in baseline}
    for pid, replacements in STOPS_ONLY_NOTE_SCRUBS.items():
        if pid not in by_id:
            raise Fail(f"stops-only scrub: unknown baseline record {pid}")
        notes = by_id[pid].get("notes", "")
        for old, new in replacements:
            if old not in notes:
                raise Fail(f"stops-only scrub: {pid} notes do not contain {old!r}")
            notes = notes.replace(old, new)
        by_id[pid]["notes"] = notes


def run(check, quiet):
    corrections_doc = json.loads(CORRECTIONS.read_text(encoding="utf-8"))
    corrections = OrderedDict((c["id"], c) for c in corrections_doc["corrections"])
    entries = load_edits()
    status = classify(corrections, entries)

    baseline = json.loads(BASELINE.read_text(encoding="utf-8"), object_pairs_hook=OrderedDict)
    raw_baseline = copy.deepcopy(baseline)
    scrub_baseline_notes(baseline)
    master = json.loads(PATTERNS.read_text(encoding="utf-8"), object_pairs_hook=OrderedDict)
    master_by = {r["patternId"]: r for r in master}
    # every run starts from the pre-correction baseline, so clones and edits do not depend on earlier runs
    patterns = copy.deepcopy(baseline)
    before = {r["patternId"]: copy.deepcopy(r) for r in raw_baseline}
    resolver = Resolver(baseline)
    by_id = {r["patternId"]: r for r in patterns}
    evidence = defaultdict(lambda: {"ids": [], "urls": [], "basis": ""})
    variants = defaultdict(lambda: {"patterns": set(), "distinct": None, "ids": set()})
    applied = [e for e in entries if e.get("status", "applied") not in ("notApplied", "skippedHistorical", "deferred")]
    entries_by_record = defaultdict(list)
    for entry in applied:
        entries_by_record[entry["record"]].append(entry)

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
        if entry.get("status", "applied") in ("notApplied", "skippedHistorical", "deferred"):
            if entry["record"] not in by_id and "split" not in entry:
                raise Fail(f"{entry['_where']}: unknown record {entry['record']}")

    split_records, explicit_labels = set(), set()
    for entry in applied:
        if "label" in (entry.get("set") or {}):
            explicit_labels.add(entry["record"])
        for split in splits_of(entry):
            if "label" in (split.get("setClone") or {}):
                explicit_labels.add(split["newId"])
    # phase A: split off the older era from the record as it is before any correction
    for entry in applied:
        record = by_id.get(entry["record"])
        if record is None:
            raise Fail(f"{entry['_where']}: unknown record {entry['record']}")
        for split in splits_of(entry):
            clone_id = split["newId"]
            if clone_id in by_id:
                raise Fail(f"{entry['_where']}: split target {clone_id} already exists")
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
            patterns.insert(patterns.index(record) + 1, clone)
            by_id[clone_id] = clone
            before.setdefault(clone_id, None)
            record["validFrom"] = split["at"]
            if split.get("setBase"):
                apply_set(record, split["setBase"], resolver)
            if any(split.get(k) for k in ("dropStops", "setClone", "cloneValidFrom")):
                touch(clone_id, entry)
            else:
                touch(clone_id, {"ids": [], "basis": f"older era of {entry['record']} (until {split['at']}), kept as it was; "
                                 "the corrections apply to the record from that date"})
            split_records.update((entry["record"], clone_id))
    pre = {pid: copy.deepcopy(r) for pid, r in by_id.items()}

    # phase B: the corrections themselves
    for entry in applied:
        pid = entry["record"]
        record = by_id[pid]
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
            item["ids"].update(entry["ids"])
            if spec.get("distinctPatterns"):
                item["distinct"] = max(item["distinct"] or 0, spec["distinctPatterns"])

    # a historical correction must name an existing record, and that record must really be historical
    for cid, (state, _, _) in status.items():
        if state == "skippedHistorical":
            record = by_id.get(corrections[cid]["recordId"])
            if record is None:
                raise Fail(f"{cid} is marked historical but record {corrections[cid]['recordId']} does not exist")
            if not (record.get("validUntil") and record["validUntil"] < CHECKED):
                raise Fail(f"{cid} is marked historical but {record['patternId']} is current")

    for pid in split_records:
        by_id[pid]["label"] = period_label(by_id[pid])

    for record in patterns:
        if record.get("validFrom") and record.get("validUntil") and not record["validFrom"] < record["validUntil"]:
            raise Fail(f"{record['patternId']}: validity {record['validFrom']}..{record['validUntil']} is empty "
                       f"(the app refuses the whole catalog)")

    problems = period_problems(entries_by_record, pre, by_id, corrections)
    if problems:
        raise Fail("corrections outside the period of their evidence:\n  " + "\n  ".join(problems))

    dropped_legs = []
    for pid, item in evidence.items():
        record = by_id[pid]
        # the app applies a pattern as a ride from origin to destination, so both must be the first and last
        # always-served stop: a terminal that only some trains reach is optional and the ends move inward
        if len(record["stops"]) < 2:
            raise Fail(f"{pid}: fewer than two always-served stops")
        for key, stop in (("origin", record["stops"][0]), ("destination", record["stops"][-1])):
            if record[key] != stop["name"]:
                record[key] = stop["name"]
        record["label"] = new_label(record, pre[pid], pid in explicit_labels)
        if record["completeness"].get("validity") == "missing" and (record.get("validFrom") or record.get("validUntil")):
            record["completeness"]["validity"] = "complete" if record.get("validFrom") and record.get("validUntil") else "partial"
        if record.get("unsolvableLegs"):
            pairs = [[a["name"], b["name"]] for a, b in zip(record["stops"], record["stops"][1:])]
            kept = [leg for leg in record["unsolvableLegs"] if leg in pairs]
            dropped_legs.extend((pid, leg) for leg in record["unsolvableLegs"] if leg not in pairs)
            record["unsolvableLegs"] = kept
            if not kept:
                del record["unsolvableLegs"]
        notes = MARKER.sub("", record.get("notes") or "").rstrip()
        urls = urls_for(corrections, item["ids"], item["urls"])
        record["notes"] = (notes + " " + marker(item["ids"], urls, item["basis"])).strip()

    touched = {pid for pid in by_id if before.get(pid) != by_id[pid]}
    for pid in sorted(touched):
        current = master_by.get(pid)
        if current is not None and current != by_id[pid] and current != before.get(pid):
            fields = sorted(k for k in set(current) | set(by_id[pid]) if current.get(k) != by_id[pid].get(k))
            raise Fail(f"{pid} was edited by hand (fields {', '.join(fields)}); the script would overwrite it. "
                       f"Move the edit into audits/edits and rerun")
    # untouched records come from the current master, so unrelated later edits survive a rerun
    result = []
    for record in patterns:
        pid = record["patternId"]
        if pid in touched:
            result.append(record)
        elif pid in master_by:
            result.append(master_by[pid])
    known = {r["patternId"] for r in result}
    result.extend(r for r in master if r["patternId"] not in known and r["patternId"] not in before)
    leftover = [r["patternId"] for r in result if CLOCK_TEXT.search(r.get("notes") or "")]
    if leftover:
        raise Fail("clock times remain in the notes of " + ", ".join(leftover)
                   + " (stops-only decision); add a STOPS_ONLY_NOTE_SCRUBS entry")
    out_patterns = json.dumps(result, ensure_ascii=False, indent=1) + "\n"

    derived = json.loads(DERIVED.read_text(encoding="utf-8"))
    keep = [r for r in derived if "_derivation" not in r or r["_derivation"] != LEGACY]
    mirrored = [dict(copy.deepcopy(r), _derivation=LEGACY) for r in result]
    out_derived = json.dumps(sorted(keep + mirrored, key=lambda r: r["patternId"]),
                             ensure_ascii=False, indent=2, sort_keys=True) + "\n"

    needs = {
        "schema": 1,
        "checkedOn": CHECKED,
        "note": ("Services whose stop pattern differs by train number or date. The base record in train-service-patterns.json "
                 "lists what every train of the name calls at (stops) and what only some call at (optionalStops); "
                 "the per-number tables still have to be authored from dated public timetables "
                 "(ios/tools/shinkansen-patterns.md for the Shinkansen model). No number is inferred. "
                 "`sources` are the verifier and auditor URLs of the listed corrections."),
        "services": [
            OrderedDict([
                ("service", name),
                ("patterns", sorted(item["patterns"])),
                ("distinctPatterns", item["distinct"]),
                ("sources", urls_for(corrections, sorted(item["ids"], key=natural), [])),
                ("corrections", sorted(item["ids"], key=natural)),
            ]) for name, item in sorted(variants.items())
        ],
    }
    out_variants = json.dumps(needs, ensure_ascii=False, indent=1) + "\n"

    changed_records = [pid for pid in by_id if pid in touched and master_by.get(pid) != by_id[pid]]
    outputs = {PATTERNS: out_patterns, DERIVED: out_derived, VARIANTS: out_variants}
    changes = {p: (p.read_text(encoding="utf-8") if p.exists() else None) != text for p, text in outputs.items()}

    if not quiet:
        for pid in changed_records:
            report(pid, master_by.get(pid) or before.get(pid), by_id[pid])
        for pid, leg in dropped_legs:
            print(f"! {pid}: known unsolvable leg {leg} is no longer a pair of consecutive stops and was dropped")
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
          f"({sum(1 for p in changed_records if p not in master_by)} new)")
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
