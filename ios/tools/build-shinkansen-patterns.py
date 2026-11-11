#!/usr/bin/env python3
"""Generate and validate the `variants` block of Shinkansen stop-pattern records.

Source of truth for train-number tables: one authored JSON file per timetable
revision and line group (format: ios/tools/shinkansen-patterns.md). This script
turns them into the `variants` key of the base records in
ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json and, with
--check, validates everything and writes nothing.

    python3 -I ios/tools/build-shinkansen-patterns.py            # rewrite variants
    python3 -I ios/tools/build-shinkansen-patterns.py --check    # regression-guard mode
    python3 -I ios/tools/build-shinkansen-patterns.py --check --strict

With no source files the generator changes nothing. Generation is deterministic:
the same inputs give the same bytes (records keep their order; `variants` is the
record's last key; the file keeps the layout of build-train-service-station-refs.py).

Ground rule (user requirement): no rule maps a train number to a stop pattern.
Every number is listed explicitly under its pattern, per direction. A range
("101-105") is shorthand for consecutive numbers that were each checked and is
expanded to explicit numbers in the bundled file. The odd/even convention is only
ever a warning here; lookup (in RailCore) never uses it.

Rule groups
  new-key rules (always errors): everything about `allStations`, `variants`,
    `coupled` and the source files. These fail --check.
  base-data rules (errors only with --strict, otherwise reported as notes): about
    the existing stop lists of Shinkansen base records (every stop is a station of
    its Shinkansen row, in monotonic order along the corridor, always-served and
    optional stops disjoint). Another branch is correcting that data; switch the
    guard to --strict once it has landed.
"""

import argparse
import json
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATTERNS = ROOT / "ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json"
PACKAGE = ROOT / "app/public/rail/jp-2025.json"
THROUGH = ROOT / "ios/RailKit/Sources/RailCore/Resources/japan-through-services.json"
SOURCES = ROOT / "app/data/shinkansen-patterns"

SCHEMA = 1
MAX_RANGE = 1000
RUNS = ("daily", "weekdays", "holidays", "extra")
DIRECTIONS = ("down", "up")
SOURCE_TYPES = ("operator_timetable", "printed_timetable")  # may be verified
SOURCE_FIELDS = ("type", "publisher", "title", "locator", "accessedAt")


class Findings:
    """Collects errors (new-key rules), notes (base-data rules) and warnings."""

    def __init__(self):
        self.errors, self.base, self.warnings = [], [], []
        self.checked = 0

    def error(self, rule, where, message):
        self.errors.append((rule, where, message))

    def base_issue(self, rule, where, message):
        self.base.append((rule, where, message))

    def warn(self, rule, where, message):
        self.warnings.append((rule, where, message))


# ---------------------------------------------------------------- dates

def parse_day(text):
    if not isinstance(text, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        return None
    try:
        return date.fromisoformat(text)
    except ValueError:
        return None


# ---------------------------------------------------------------- corridors

class Rail:
    """Station order of the rail package rows and the through-service legs."""

    def __init__(self, package, through):
        self.rows = {}
        self.names = {}
        for line in package["lines"]:
            self.rows[line["id"]] = line
            self.names.setdefault(line["name"], []).append(line["id"])
        self.through = [
            record for record in (through or {}).get("patterns", [])
            if any("新幹線" in self.rows.get(leg["lineID"], {}).get("name", "") for leg in record["legs"])
        ]

    def kind(self, row_id):
        return self.rows[row_id].get("kind")

    def leg_stations(self, leg):
        """Stations of a through leg, from its from-station to its to-station."""
        stations = self.rows[leg["lineID"]]["stations"]
        codes = [s[0] for s in stations]
        if leg["fromStationCode"] not in codes or leg["toStationCode"] not in codes:
            return None
        i, j = codes.index(leg["fromStationCode"]), codes.index(leg["toStationCode"])
        piece = stations[i:j + 1] if i <= j else stations[j:i + 1][::-1]
        return [(s[0], s[1], leg["lineID"]) for s in piece]

    def through_corridor(self, record):
        chain = []
        for leg in record["legs"]:
            piece = self.leg_stations(leg)
            if piece is None:
                return None
            if chain and chain[-1][0] == piece[0][0]:
                piece = piece[1:]
            chain.extend(piece)
        return chain

    def corridor_for(self, base):
        """Ordered (code, name, rowID) stations of a base record, origin to destination.

        A record's `lines` are matched, in order, against the line names of a
        through-service record containing them; the record's own origin and
        destination (resolved by station name on the Shinkansen rows, so a
        same-name conventional station is never picked) cut the chain. A single
        line with no through record uses its one row.
        """
        wanted = collapse(base["lines"])

        def cut(chain):
            names = [n for _, n, _ in chain]
            if names.count(base["origin"]) != 1 or names.count(base["destination"]) != 1:
                return None
            i, j = names.index(base["origin"]), names.index(base["destination"])
            return chain[i:j + 1] if i < j else None

        for record in self.through:
            chain = self.through_corridor(record)
            if chain is None:
                continue
            names = collapse([self.rows[leg["lineID"]]["name"] for leg in record["legs"]])
            if contains_run(names, wanted) and cut(chain):
                return cut(chain), None
        if len(wanted) == 1 and len(self.names.get(wanted[0], [])) == 1:
            row_id = self.names[wanted[0]][0]
            row = self.rows[row_id]["stations"]
            chain = [(st[0], st[1], row_id) for st in row]
            piece = cut(chain) or (cut(chain[::-1]))
            if piece:
                return piece, None
        return None, "no corridor found for lines " + "/".join(base["lines"])


def collapse(names):
    out = []
    for name in names:
        if not out or out[-1] != name:
            out.append(name)
    return out


def contains_run(haystack, needle):
    return any(haystack[i:i + len(needle)] == needle for i in range(len(haystack) - len(needle) + 1))


# ---------------------------------------------------------------- numbers

def expand_numbers(items, where, findings):
    """Explicit numbers from `numbers`: ints, "23", or consecutive "101-105"."""
    out = []
    if not isinstance(items, list) or not items:
        findings.error("emptyNumbers", where, "a group lists no train numbers")
        return out
    for item in items:
        if isinstance(item, int) and not isinstance(item, bool):
            out.append(item)
            continue
        match = re.fullmatch(r"\s*(\d+)\s*(?:-\s*(\d+)\s*)?", item) if isinstance(item, str) else None
        if not match:
            findings.error("badNumber", where, f"{item!r} is not a number or a range of consecutive numbers")
            continue
        low = int(match.group(1))
        high = int(match.group(2)) if match.group(2) else low
        if low > high or high - low >= MAX_RANGE:
            findings.error("badNumber", where, f"range {item!r} runs backwards or is longer than {MAX_RANGE}")
            continue
        out.extend(range(low, high + 1))
    if any(n <= 0 for n in out):
        findings.error("nonPositiveNumber", where, "train numbers must be positive")
    if len(set(out)) != len(out):
        findings.error("duplicateNumber", where, "a number is listed twice in one group")
    return out


# ---------------------------------------------------------------- building

def generate_revision(source, base, corridor, findings, label):
    """One generated revision dict for `base`, or None when the source is unusable."""
    pat = base["patternId"]
    codes = [c for c, _, _ in corridor]
    index = {c: i for i, c in enumerate(codes)}
    required = [s["sourceCode"] for s in base["stops"]]
    optional = [s["sourceCode"] for s in base["optionalStops"]]
    by_name = {}
    for code, name, _row in corridor:
        by_name.setdefault(name, []).append(code)
    patterns = []
    seen_ids = set()
    ok = True
    for spec in source["patterns"]:
        where = f"{label} {pat} pattern {spec.get('id')!r}"
        pid = spec.get("id")
        if not isinstance(pid, str) or not pid or pid in seen_ids:
            findings.error("duplicatePatternID", where, "pattern id missing or repeated in the revision")
            ok = False
            continue
        seen_ids.add(pid)
        names = spec.get("stops")
        if not isinstance(names, list) or len(names) < 2:
            findings.error("stopListShort", where, "a stop list needs at least two stations")
            ok = False
            continue
        stop_codes = []
        for name in names:
            found = by_name.get(name, [])
            if len(found) != 1:
                findings.error(
                    "stopNotInCorridor", where,
                    f"{name!r} is " + ("not a station" if not found else "ambiguous") + " of this record's Shinkansen corridor")
                ok = False
            else:
                stop_codes.append(found[0])
        if len(stop_codes) != len(names):
            continue
        positions = [index[c] for c in stop_codes]
        if any(b <= a for a, b in zip(positions, positions[1:])):
            findings.error("stopsNotMonotonic", where, "stop list is not strictly increasing in corridor order")
            ok = False
            continue
        first, last = stop_codes[0], stop_codes[-1]
        listed = set(stop_codes)
        for code in required:
            if code in index and index[first] <= index[code] <= index[last] and code not in listed:
                name = next(n for c, n, _ in corridor if c == code)
                findings.error("alwaysServedOmitted", where, f"always-served stop {name!r} is missing between the ends")
                ok = False
        extras = [c for c in stop_codes if c not in required and c not in optional]
        for code in extras:
            name = next(n for c, n, _ in corridor if c == code)
            findings.error("callNotOptional", where, f"{name!r} is neither an always-served nor an optional stop of the record")
            ok = False
        entry = {"id": pid}
        origin_code = by_name.get(base["origin"], [None])[0]
        dest_code = by_name.get(base["destination"], [None])[0]
        if first != origin_code:
            entry["from"] = first
        if last != dest_code:
            entry["to"] = last
        entry["calls"] = [c for c in stop_codes if c in optional]
        entry["trains"] = build_groups(spec.get("trains"), source, where, findings)
        if "coupled" in spec:
            entry["coupled"] = spec["coupled"]
        patterns.append(entry)
    if not ok:
        return None
    citation = citation_text(source["source"])
    revision = {
        "revision": source["revision"],
        "validFrom": source["validFrom"],
        "validUntil": source.get("validUntil"),
        "checkedOn": source.get("checkedOn"),
        "status": source["status"],
        "citation": citation,
        "patterns": patterns,
    }
    return revision


def build_groups(groups, source, where, findings):
    out = []
    if not isinstance(groups, list) or not groups:
        findings.error("emptyNumbers", where, "pattern has no train groups")
        return out
    for group in groups:
        direction = group.get("direction")
        if direction not in DIRECTIONS:
            findings.error("badDirection", where, f"direction must be one of {DIRECTIONS}, stored explicitly per group")
        runs = group.get("runs", "daily")
        if runs not in RUNS:
            findings.error("badRuns", where, f"runs must be one of {RUNS}")
        entry = {"direction": direction, "numbers": expand_numbers(group.get("numbers"), where, findings)}
        if runs != "daily":
            entry["runs"] = runs
        for key in ("validFrom", "validUntil"):
            if key in group:
                entry[key] = group[key]
        out.append(entry)
    return out


def citation_text(src):
    if not isinstance(src, dict):
        return ""
    parts = [src.get(k, "") for k in ("publisher", "title", "locator")]
    text = ", ".join(p for p in parts if p)
    if src.get("accessedAt"):
        text += f" (accessed {src['accessedAt']})"
    return text


# ---------------------------------------------------------------- source files

def load_sources(directory, findings):
    out = []
    if not directory.is_dir():
        return out
    for path in sorted(directory.glob("*.json")):
        try:
            out.append((path.name, json.loads(path.read_text(encoding="utf-8"))))
        except (OSError, ValueError) as error:
            findings.error("sourceUnreadable", path.name, str(error))
    return out


def check_source_header(name, source, findings):
    ok = True
    if source.get("schema") != SCHEMA:
        findings.error("sourceSchema", name, f"schema must be {SCHEMA}")
        ok = False
    start, end = parse_day(source.get("validFrom")), None
    if start is None:
        findings.error("invalidDate", name, "validFrom is not a real YYYY-MM-DD date")
        ok = False
    if source.get("validUntil") is not None:
        end = parse_day(source["validUntil"])
        if end is None or (start and end <= start):
            findings.error("invalidDate", name, "validUntil is not a real date after validFrom")
            ok = False
    if source.get("checkedOn") is not None and parse_day(source["checkedOn"]) is None:
        findings.error("invalidDate", name, "checkedOn is not a real date")
        ok = False
    if not isinstance(source.get("revision"), str) or not source["revision"]:
        findings.error("missingRevision", name, "revision id missing")
        ok = False
    src = source.get("source")
    if not isinstance(src, dict) or any(not str(src.get(f, "")).strip() for f in SOURCE_FIELDS):
        findings.error("missingCitation", name, f"source needs {', '.join(SOURCE_FIELDS)}")
        ok = False
    status = source.get("status")
    if status not in ("verified", "unverified"):
        findings.error("missingStatus", name, "status must be 'verified' or 'unverified'")
        ok = False
    elif status == "verified":
        if not isinstance(src, dict) or src.get("type") not in SOURCE_TYPES:
            findings.error("verifiedWithoutOfficialSource", name,
                           f"verified needs source.type in {SOURCE_TYPES}")
            ok = False
        if not str(source.get("verifiedBy", "")).strip():
            findings.error("verifiedWithoutSecondReader", name, "verified needs a verifiedBy second reader")
            ok = False
    if not isinstance(source.get("services"), list):
        findings.error("sourceSchema", name, "services must be a list")
        ok = False
    return ok


def generate(bundled, sources, rail, findings):
    """New records list: every base record named in a source gets `variants` rebuilt."""
    by_id = {r["patternId"]: r for r in bundled}
    revisions = {}
    for name, source in sources:
        if not check_source_header(name, source, findings):
            continue
        for service in source["services"]:
            pid = service.get("pattern")
            base = by_id.get(pid)
            if base is None:
                findings.error("unknownBaseRecord", name, f"no base record {pid!r} in the bundled file")
                continue
            corridor, why = rail.corridor_for(base)
            if corridor is None:
                findings.error("corridorUnresolved", f"{name} {pid}", why)
                continue
            revision = generate_revision(
                {**source, "patterns": service.get("patterns", [])}, base, corridor, findings, name)
            if revision is not None:
                revisions.setdefault(pid, []).append((name, revision, corridor))
    out = []
    for record in bundled:
        built = revisions.get(record["patternId"])
        if built:
            record = {k: v for k, v in record.items() if k != "variants"}
            built.sort(key=lambda item: (item[1]["validFrom"], item[1]["revision"]))
            corridor = built[0][2]
            allowed = {s["sourceCode"] for s in record["stops"] + record["optionalStops"]}
            record["variants"] = {
                "schema": SCHEMA,
                "order": [c for c, _, _ in corridor if c in allowed],
                "revisions": [item[1] for item in built],
            }
        out.append(record)
    return out, set(revisions)


# ---------------------------------------------------------------- validation of the bundled file

def validate_bundled(bundled, rail, findings):
    """All checks on the bundled records: new keys (errors) and base data (notes)."""
    services = {}
    for record in bundled:
        services.setdefault(record["serviceId"], []).append(record)
    for record in bundled:
        pid = record["patternId"]
        shinkansen = any("新幹線" in line for line in record["lines"])
        corridor, why = (None, None)
        needs_corridor = shinkansen or record.get("allStations") or "variants" in record
        if needs_corridor:
            corridor, why = rail.corridor_for(record)
        if corridor is None and needs_corridor:
            kind = findings.error if (record.get("allStations") or "variants" in record) else findings.base_issue
            kind("corridorUnresolved", pid, why)
        if shinkansen and corridor is not None:
            findings.checked += 1
            check_base_data(record, corridor, rail, findings)
            if (not record.get("allStations") and not record["optionalStops"]
                    and [s["sourceCode"] for s in record["stops"]] == [c for c, _, _ in corridor]):
                findings.warn("allStationsCandidate", pid,
                              "lists every corridor station as always served; allStations needs a cited source before it is set")
        if record.get("allStations") is not None and not isinstance(record.get("allStations"), bool):
            findings.error("allStationsNotBoolean", pid, "allStations must be true or false")
        if record.get("allStations"):
            check_all_stations(record, corridor, findings)
        if "variants" in record:
            check_variants(record, corridor, services, findings)
    check_number_conflicts(bundled, findings)


def corridor_info(corridor):
    codes = [c for c, _, _ in corridor]
    return codes, {c: i for i, c in enumerate(codes)}


def check_base_data(record, corridor, rail, findings):
    pid = record["patternId"]
    codes, index = corridor_info(corridor)
    names = {c: n for c, n, _ in corridor}
    required = [s["sourceCode"] for s in record["stops"]]
    optional = [s["sourceCode"] for s in record["optionalStops"]]
    for field, items in (("stops", record["stops"]), ("optionalStops", record["optionalStops"])):
        last = -1
        for stop in items:
            code, name = stop["sourceCode"], stop["name"]
            if code not in index:
                findings.base_issue(
                    "stopNotOnShinkansenLine", pid,
                    f"{field}: {name} ({code}) is not a station of the record's Shinkansen corridor")
                continue
            if names[code] != name:
                findings.base_issue("stopNameMismatch", pid, f"{field}: {name} ({code}) is {names[code]} on the line")
            if index[code] <= last:
                findings.base_issue("stopsNotMonotonic", pid, f"{field}: {name} is out of corridor order")
            last = max(last, index[code])
    if set(required) & set(optional):
        findings.base_issue("optionalOverlapsRequired", pid, "a station is both always served and optional")


def check_all_stations(record, corridor, findings):
    pid = record["patternId"]
    if record["optionalStops"]:
        findings.error("allStationsWithOptionalStops", pid, "allStations record has optional stops")
    if "variants" in record:
        findings.error("allStationsWithVariants", pid, "allStations record has variants")
    if corridor is None:
        return
    codes = [c for c, _, _ in corridor]
    if [s["sourceCode"] for s in record["stops"]] != codes:
        findings.error("allStationsIncomplete", pid, "stops are not every corridor station between the ends, in order")


def check_variants(record, corridor, services, findings):
    pid = record["patternId"]
    variants = record["variants"]
    if variants.get("schema") != SCHEMA:
        findings.error("variantsSchema", pid, f"variants.schema must be {SCHEMA}")
        return
    required = [s["sourceCode"] for s in record["stops"]]
    optional = [s["sourceCode"] for s in record["optionalStops"]]
    order = variants.get("order", [])
    if sorted(order) != sorted(required + optional):
        findings.error("orderMismatch", pid, "order must hold exactly the always-served and optional stops, once each")
    elif corridor is not None:
        _, index = corridor_info(corridor)
        if any(c not in index for c in order) or any(index[b] <= index[a] for a, b in zip(order, order[1:])):
            findings.error("orderMismatch", pid, "order is not in corridor order")
    rec_from, rec_until = parse_day(record.get("validFrom")), parse_day(record.get("validUntil"))
    windows = []
    for rev in variants.get("revisions", []):
        label = f"{pid} revision {rev.get('revision')}"
        if not str(rev.get("citation", "")).strip():
            findings.error("missingCitation", label, "revision has no citation")
        if rev.get("status") not in ("verified", "unverified"):
            findings.error("missingStatus", label, "status must be 'verified' or 'unverified'")
        start, end = parse_day(rev.get("validFrom")), parse_day(rev.get("validUntil"))
        bad_end = rev.get("validUntil") is not None and end is None
        bad_checked = rev.get("checkedOn") is not None and parse_day(rev["checkedOn"]) is None
        if start is None or bad_end or bad_checked or (end and end <= start):
            findings.error("invalidDate", label, "malformed date or empty validity interval")
            continue
        windows.append((start, end, rev.get("revision")))
        if rec_from and start < rec_from:
            findings.error("revisionOutsideRecordDates", label, "starts before the record")
        if rec_until and (end is None or end > rec_until):
            findings.error("revisionOutsideRecordDates", label, "runs past the record")
        seen = set()
        for pat in rev.get("patterns", []):
            check_pattern(record, rev, pat, order, required, optional, corridor, services, seen, findings, label)
    windows.sort(key=lambda w: w[0])
    for (s1, e1, n1), (s2, _e2, n2) in zip(windows, windows[1:]):
        if e1 is None:
            findings.error("openEndedRevisionNotLast", pid, f"revision {n1} is open-ended but not the last")
        elif s2 < e1:
            findings.error("revisionOverlap", pid, f"revisions {n1} and {n2} overlap")


def check_pattern(record, rev, pat, order, required, optional, corridor, services, seen, findings, label):
    where = f"{label} pattern {pat.get('id')}"
    if pat.get("id") in seen:
        findings.error("duplicatePatternID", where, "id repeats inside the revision")
    seen.add(pat.get("id"))
    ends = [pat.get(k) for k in ("from", "to")]
    for end in ends:
        if end is not None and end not in order:
            findings.error("endNotInOrder", where, f"end {end} is not in order")
    if all(e is None or e in order for e in ends):
        first = pat.get("from") or order_end(record, order, "origin")
        last = pat.get("to") or order_end(record, order, "destination")
        if first in order and last in order and order.index(first) > order.index(last):
            findings.error("endsOutOfOrder", where, "ends run against corridor order")
    for call in pat.get("calls", []):
        if call not in optional:
            findings.error("callNotOptional", where, f"call {call} is not an optional stop of the record")
    groups = pat.get("trains", [])
    if not groups:
        findings.error("emptyNumbers", where, "pattern lists no train numbers")
    for group in groups:
        numbers = group.get("numbers", [])
        if not numbers:
            findings.error("emptyNumbers", where, "a group lists no train numbers")
        if any(not isinstance(n, int) or n <= 0 for n in numbers):
            findings.error("nonPositiveNumber", where, "train numbers must be positive integers")
        if len(set(numbers)) != len(numbers):
            findings.error("duplicateNumber", where, "a number is listed twice in one group")
        if group.get("direction") not in DIRECTIONS:
            findings.error("badDirection", where, "direction is stored explicitly: down or up")
        if group.get("runs", "daily") not in RUNS:
            findings.error("badRuns", where, f"runs must be one of {RUNS}")
        rs, re_ = parse_day(rev.get("validFrom")), parse_day(rev.get("validUntil"))
        gs, ge = parse_day(group.get("validFrom")), parse_day(group.get("validUntil"))
        if (group.get("validFrom") and gs is None) or (group.get("validUntil") and ge is None):
            findings.error("invalidDate", where, "group has a malformed date")
        else:
            if gs and rs and gs < rs:
                findings.error("groupOutsideRevision", where, "a group starts before its revision")
            if ge and re_ and ge > re_:
                findings.error("groupOutsideRevision", where, "a group runs past its revision")
        # Convention only, never an error, never used for lookup.
        want_odd = group.get("direction") == "down"
        if any(isinstance(n, int) and (n % 2 == 1) != want_odd for n in numbers):
            findings.warn("parityConvention", where,
                          f"some {group.get('direction')} numbers break the odd/even convention (warning only)")
    coupled = pat.get("coupled")
    if coupled:
        partners = services.get(coupled.get("service"), [])
        codes = {s["sourceCode"] for p in partners for s in p["stops"] + p["optionalStops"]}
        if not partners or coupled.get("from") not in codes or coupled.get("to") not in codes:
            findings.error("coupledPartnerMissing", where,
                           f"coupled partner {coupled.get('service')!r} or its stations do not exist")
        elif not any(c.get("coupled", {}).get("service") == record["serviceId"]
                     for p in partners for r in p.get("variants", {}).get("revisions", [])
                     for c in r.get("patterns", []) if c.get("coupled")):
            findings.warn("coupledNotReciprocal", where, f"{coupled['service']} does not couple back")


def order_end(record, order, which):
    refs = {s["name"]: s["sourceCode"] for s in record["stops"] + record["optionalStops"]}
    return refs.get(record[which], order[0] if which == "origin" and order else order[-1] if order else None)


def day_interval(rev, group):
    start = max(parse_day(rev["validFrom"]), parse_day(group.get("validFrom")) or date.min)
    ends = [d for d in (parse_day(rev.get("validUntil")), parse_day(group.get("validUntil"))) if d]
    return start, (min(ends) if ends else None)


def disjoint(rev_a, grp_a, rev_b, grp_b):
    if {grp_a.get("runs", "daily"), grp_b.get("runs", "daily")} == {"weekdays", "holidays"}:
        return True
    if parse_day(rev_a.get("validFrom")) is None or parse_day(rev_b.get("validFrom")) is None:
        return False
    (sa, ea), (sb, eb) = day_interval(rev_a, grp_a), day_interval(rev_b, grp_b)
    return (ea is not None and ea <= sb) or (eb is not None and eb <= sa)


def check_number_conflicts(bundled, findings):
    """The same number in two patterns of a service is legal only on provably disjoint days."""
    entries = {}
    for record in bundled:
        for rev in record.get("variants", {}).get("revisions", []):
            for pat in rev.get("patterns", []):
                for group in pat.get("trains", []):
                    for number in set(group.get("numbers", [])):
                        entries.setdefault((record["name"], number), []).append(
                            (record["patternId"], rev, pat.get("id"), group))
    for (name, number), items in sorted(entries.items()):
        for i, a in enumerate(items):
            for b in items[i + 1:]:
                if not disjoint(a[1], a[3], b[1], b[3]):
                    findings.error(
                        "numberInTwoPatterns", f"{a[0]}",
                        f"{name} {number} is in {a[0]}/{a[1].get('revision')}/{a[2]} and "
                        f"{b[0]}/{b[1].get('revision')}/{b[2]} on overlapping days")


# ---------------------------------------------------------------- main

def serialize(records):
    return json.dumps(records, ensure_ascii=False, indent=1) + "\n"


def analyse(patterns_path, package_path, through_path, sources_dir, check):
    """Everything --check does, without printing: (findings, generated records, new text, raw text)."""
    raw = patterns_path.read_text(encoding="utf-8")
    bundled = json.loads(raw)
    package = json.loads(package_path.read_text(encoding="utf-8"))
    through = json.loads(through_path.read_text(encoding="utf-8")) if through_path.exists() else {}
    rail = Rail(package, through)
    findings = Findings()
    sources = load_sources(sources_dir, findings)
    generated, rebuilt = generate(bundled, sources, rail, findings)
    new_text = serialize(generated)
    if not findings.errors:
        validate_bundled(generated, rail, findings)
    if not sources and not any("variants" in r for r in bundled) and new_text != raw:
        findings.error("layoutDrift", patterns_path.name, "the file is not in the generator's byte layout")
    if check and sources and new_text != raw:
        findings.error("bundledOutOfDate", patterns_path.name,
                       "the bundled variants differ from what the source files generate; run the script without --check")
    for record in bundled:
        if "variants" in record and record["patternId"] not in rebuilt:
            findings.error("variantsWithoutSource", record["patternId"],
                           "record carries variants but no source file builds them (variants are generated, never typed)")
    return findings, generated, new_text, raw


def run(patterns_path, package_path, through_path, sources_dir, check, strict, out):
    findings, generated, new_text, raw = analyse(patterns_path, package_path, through_path, sources_dir, check)
    report(findings, strict, out)
    if findings.errors or (strict and findings.base):
        return 1
    if not check and new_text != raw:
        patterns_path.write_text(new_text, encoding="utf-8")
        print(f"Wrote variants for {sum(1 for r in generated if 'variants' in r)} record(s).", file=out)
    return 0


def report(findings, strict, out):
    def show(label, items):
        for rule, where, message in items:
            print(f"  {label} {rule} {where}: {message}", file=out)
    print(f"Shinkansen base records checked: {findings.checked}", file=out)
    print(f"new-key rules: {len(findings.errors)} error(s), {len(findings.warnings)} warning(s)", file=out)
    show("ERROR", findings.errors)
    show("warn ", findings.warnings)
    mode = "ERRORS (--strict)" if strict else "notes (not failing; pass --strict to fail)"
    print(f"base-data rules: {len(findings.base)} finding(s) as {mode}", file=out)
    show("ERROR" if strict else "note ", findings.base)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="validate only; write nothing")
    parser.add_argument("--strict", action="store_true", help="base-data findings fail too")
    parser.add_argument("--patterns", type=Path, default=PATTERNS)
    parser.add_argument("--package", type=Path, default=PACKAGE)
    parser.add_argument("--through", type=Path, default=THROUGH)
    parser.add_argument("--sources", type=Path, default=SOURCES)
    args = parser.parse_args(argv)
    return run(args.patterns, args.package, args.through, args.sources, args.check, args.strict, sys.stdout)


if __name__ == "__main__":
    sys.exit(main())
