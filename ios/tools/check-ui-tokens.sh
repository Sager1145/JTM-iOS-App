#!/usr/bin/env bash
# Static check: no NEW literal spacing/radius/touch/font/button values or text
# dismiss buttons in ios/RailMap (spec §6.4-6.5, decision D9). Existing debt is
# frozen in ios/tools/ui-token-baseline.txt, which only ever shrinks.
#
#   check-ui-tokens.sh                 check (exit 1 on growth or new entries)
#   check-ui-tokens.sh --update        regenerate the whole baseline
#   check-ui-tokens.sh --update PATH.. rewrite entries for those paths only;
#                                      refuses (exit 1) if any count would grow
# Paths are relative to ios/ (e.g. RailMap/Foo/Bar.swift).
# Silence one deliberate line with a trailing `// ui-token-ok: reason`.
set -euo pipefail
IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -I - "$IOS_DIR" "$@" <<'PY'
import os, re, sys
ios = sys.argv[1]
args = sys.argv[2:]
APP = os.path.join(ios, "RailMap")
BASE = os.path.join(ios, "tools", "ui-token-baseline.txt")
EXCL_DIRS = {"Diagnostics", "Design"}
EXCL_FILES = {"Sharing/ShareCard.swift", "Sharing/StatsWidgetView.swift",
              "Statistics/PassportTicketFace.swift", "Statistics/TicketJimon.swift",
              "Playback/PlaybackVideoExporter.swift"}

def num_ok(m):  # allowed small numbers
    return m in ("0", "1", "2")

HINT = {
 "padding-literal": "use RailSpacing.* (s4/s8/s12/s16/...) instead of a numeric padding",
 "spacing-literal": "use RailSpacing.* instead of a numeric spacing",
 "radius-literal": "use RailRadius.control/.card/.sheet instead of a numeric corner radius",
 "touch-literal": "use RailSize.touch or .railMinimumTouchTarget() (or .railPrimary/.railSecondary styles)",
 "stock-bordered": "use .buttonStyle(.railPrimary) / .railSecondary",
 "fixed-font": "use railText/railGlyph or a @ScaledMetric size",
 "dismiss-text": "view-only dismiss must use .railSheetClose(...)",
}
R_PAD = re.compile(r'\.padding\(\s*(?:\.[a-zA-Z]+\s*,\s*)?(\d+(?:\.\d+)?)')
R_SPC = re.compile(r'spacing:\s*(\d+(?:\.\d+)?)')
R_RAD = re.compile(r'cornerRadius:\s*(\d+(?:\.\d+)?)')
R_TOUCH = re.compile(r'\.frame\([^)]*\b(?:min)?(?:Width|Height|width|height):\s*44\b')
R_BORD = re.compile(r'\.buttonStyle\(\.bordered(?:Prominent)?\)')
R_FONT = re.compile(r'\.font\(\.system\(size:\s*\d')
R_TB = re.compile(r'ToolbarItem\(placement:\s*\.(?:cancellationAction|confirmationAction)')
R_DISMISS = re.compile(r'"(?:ios\.done|ios\.close|utility\.close|researchClose)"')

def files():
    for d, ds, fs in os.walk(APP):
        rel_d = os.path.relpath(d, APP)
        ds[:] = sorted(x for x in ds if not (rel_d == "." and x in EXCL_DIRS))
        for f in sorted(fs):
            if not f.endswith(".swift") or " 2" in f:
                continue
            rel = os.path.normpath(os.path.join(rel_d, f))
            if rel in EXCL_FILES:
                continue
            yield "RailMap/" + rel, os.path.join(d, f)

def scan():
    found = {}  # (rel, rule) -> [(lineno, text)]
    for rel, path in files():
        lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
        def add(rule, i):
            found.setdefault((rel, rule), []).append(i + 1)
        for i, line in enumerate(lines):
            st = line.strip()
            if st.startswith("//") or "// ui-token-ok:" in line:
                continue
            for m in R_PAD.finditer(line):
                if not num_ok(m.group(1)): add("padding-literal", i)
            for m in R_SPC.finditer(line):
                if not num_ok(m.group(1)): add("spacing-literal", i)
            for m in R_RAD.finditer(line):
                if m.group(1) != "0": add("radius-literal", i)
            if R_TOUCH.search(line): add("touch-literal", i)
            if R_BORD.search(line): add("stock-bordered", i)
            if R_FONT.search(line): add("fixed-font", i)
            if R_TB.search(line):
                nxt = "\n".join(lines[i + 1:i + 4])
                if R_DISMISS.search(nxt): add("dismiss-text", i)
    return found

def load():
    base = {}
    if os.path.exists(BASE):
        for line in open(BASE, encoding="utf-8"):
            if not line.strip() or line.startswith("#"): continue
            p, r, c = line.rstrip("\n").split("\t")
            base[(p, r)] = int(c)
    return base

HEADER = """# UI token baseline for ios/tools/check-ui-tokens.sh (spec §6.4-6.5, D9).
# Format: relpath<TAB>rule<TAB>count -- existing literal debt per file per rule.
# This file only ever SHRINKS: fix literals, then run
#   bash ios/tools/check-ui-tokens.sh --update PATH...
# which refuses to raise a count. New code uses RailSpacing/RailRadius/RailSize,
# .railPrimary/.railSecondary, railText/railGlyph and railSheetClose.
"""

def write(base):
    with open(BASE, "w", encoding="utf-8") as f:
        f.write(HEADER)
        for (p, r), c in sorted(base.items()):
            if c > 0: f.write(f"{p}\t{r}\t{c}\n")

found = scan()
counts = {k: len(v) for k, v in found.items()}

if args and args[0] == "--update":
    paths = args[1:]
    if not paths:
        write(counts)
        print(f"baseline regenerated: {len(counts)} entries")
        sys.exit(0)
    base = load()
    grow = []
    for p in paths:
        for k in {k for k in list(base) + list(counts) if k[0] == p}:
            new = counts.get(k, 0)
            if new > base.get(k, 0):
                grow.append(f"{k[0]}: {k[1]} {base.get(k, 0)} -> {new}")
    if grow:
        print("refusing --update: counts would grow:\n  " + "\n  ".join(grow))
        sys.exit(1)
    for p in paths:
        for k in [k for k in base if k[0] == p]: del base[k]
        for k, c in counts.items():
            if k[0] == p: base[k] = c
    write(base)
    print("baseline updated for: " + ", ".join(paths))
    sys.exit(0)
if args:
    print("usage: check-ui-tokens.sh [--update [PATH...]]"); sys.exit(2)

base = load()
bad = False
for k in sorted(counts):
    if counts[k] > base.get(k, 0):
        bad = True
        for ln in found[k]:
            print(f"{k[0]}:{ln}: {k[1]}: {HINT[k[1]]}")
        print(f"  ^ {k[0]} {k[1]}: {counts[k]} found, baseline {base.get(k, 0)}")
shrunk = [k for k in base if counts.get(k, 0) < base[k]]
if shrunk:
    print(f"note: {len(shrunk)} baseline entries are above current counts; "
          "run `bash ios/tools/check-ui-tokens.sh --update PATH...` to lock in the improvement.")
if bad:
    print("FAIL: new UI token violations (see above)")
    sys.exit(1)
print("ui tokens: ok")
PY
