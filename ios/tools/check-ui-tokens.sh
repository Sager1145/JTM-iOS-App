#!/usr/bin/env bash
# Static check: no NEW literal spacing/radius/touch/font/button values or text
# dismiss buttons in ios/RailMap (spec §6.4-6.5, decision D9). Existing debt is
# frozen in ios/tools/ui-token-baseline.txt, which only ever shrinks.
#
#   check-ui-tokens.sh                 check (exit 1 on growth or new entries)
#   check-ui-tokens.sh --update        regenerate the whole baseline (refuses growth;
#                                      --force only for a reviewed reset)
#   check-ui-tokens.sh --self-test    synthetic positive/negative case for every rule
#                                      (also runs before every normal check)
#   check-ui-tokens.sh --update PATH.. rewrite entries for those paths only;
#                                      refuses (exit 1) if any count would grow
# Paths are relative to ios/ (e.g. RailMap/Foo/Bar.swift).
# Silence one deliberate line with a trailing `// ui-token-ok: reason`.
# Rule status-color: an orange or red foreground style outside Design/ is a
# warning/error message in the wrong style (audit H4): use RailStatusLabel. It is
# NOT silenced by ui-token-ok. A legitimate non-message use (a destructive glyph,
# a record dot) carries `// status-color-ok: reason` on the same line; a file
# owned by another unmerged branch is listed in STATUS_COLOR_FILES below.
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

# Files not yet converted because another branch owns them. Each entry names the
# branch; delete the entry when that branch has merged and the file is converted.
STATUS_COLOR_FILES = {
 # TODO(branch claude/journey-editor-time): journey editor time fields.
 "JourneyEditor/EditorDateTimeFields.swift",
 "JourneyEditor/EditorTimeSection.swift",
 # TODO(branch claude/trip-notes): trip-note pick overlay.
 "Map/TripNotePickOverlay.swift",
 # TODO(branch claude/station-search): line/station search screens.
 "JourneyEditor/EditorLineSearchView.swift",
}

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
 "edgeinsets-literal": "use RailSpacing.* for EdgeInsets values",
 "small-touch": "minHeight/minWidth below 44 pt: use RailSize.touch or .railMinimumTouchTarget()",
 "raw-detents": "use railSheet(.half/.full); a deliberate exception carries // ui-token-ok: reason",
 "footnote-font": "use railText(.secondary/.tertiary), or mark the deliberate case // ui-token-ok: reason",
 "direct-capsule": "use .railPrimary / .railSecondary statics instead of constructing RailCapsuleButtonStyle",
 "status-color": "orange/red text is a message: use RailStatusLabel(kind:text:); a non-message glyph carries // status-color-ok: reason",
 "feature-dismiss-key": "use the shared ios.cancel / ios.close / ios.done strings instead of a per-feature dismiss string",
}
# A bare numeric literal: not preceded by a letter, digit, '.' or '_' (so RailSpacing.s12 is a token).
LIT = re.compile(r'(?<![A-Za-z0-9_.])(\d+(?:\.\d+)?)(?![A-Za-z0-9_])')
R_OK = re.compile(r'//\s*ui-token-ok:\s*\S')
R_PAD = re.compile(r'\.padding\(')
R_SPC = re.compile(r'\bspacing:\s*')
R_EDGE = re.compile(r'(?<![A-Za-z0-9_])EdgeInsets\(')
R_MIN = re.compile(r'\b(?:minHeight|minWidth):\s*(\d+(?:\.\d+)?)(?![A-Za-z0-9_.])')
R_RAD = re.compile(r'(?:cornerRadius:\s*|\.cornerRadius\(\s*)(\d+(?:\.\d+)?)')
R_TOUCH = re.compile(r'\.frame\([^)]*\b(?:min)?(?:Width|Height|width|height):\s*44\b')
R_BORD = re.compile(r'\.buttonStyle\(\.bordered(?:Prominent)?\)')
R_FONT = re.compile(r'\.system\(size:\s*\d')
R_FOOT = re.compile(r'\.font\(\s*\.footnote\b|\bFont\.footnote\b')
R_DET = re.compile(r'\.presentationDetents\(')
R_CAPS = re.compile(r'\bRailCapsuleButtonStyle\(')
R_TB = re.compile(r'ToolbarItem\(placement:\s*\.(?:cancellationAction|confirmationAction|topBarTrailing|topBarLeading)')
R_DISMISS = re.compile(r'"(?:ios\.done|ios\.close|utility\.close)"')
R_STATUS = re.compile(
    r'\.foreground(?:Style|Color)\(.*(?:\bColor\.(?:orange|red)\b|(?<![A-Za-z0-9_])\.(?:orange|red)\b'
    r'|\bsystem(?:Orange|Red)\b)')
R_STATUS_OK = re.compile(r'//\s*status-color-ok:\s*\S')
R_KEYDEF = re.compile(r'^\s*"([^"]+)"\s*:\s*\[')
R_KEYUSE = re.compile(r'\b(?:text|countryText)\(\s*"([^"]+)"')
SHARED_KEYS = {"ios.cancel", "ios.close", "ios.done"}

def dismiss_key(key):
    if key in SHARED_KEYS:
        return False
    seg = key.rsplit(".", 1)[-1]
    return seg.lower() in ("cancel", "close", "done") or \
        re.search(r'[a-z0-9](?:Cancel|Close|Done)$', seg) is not None

def inner(line, start, stop_at_comma=False):
    """Text from `start` to the matching close paren (or a depth-0 comma) on the same line."""
    depth = 0
    for j in range(start, len(line)):
        c = line[j]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return line[start:j]
            depth -= 1
        elif c == "," and depth == 0 and stop_at_comma:
            return line[start:j]
    return line[start:]

def has_big(expr):
    return any(not num_ok(m.group(1)) for m in LIT.finditer(expr))

def files(app=None):
    app = app or APP
    for d, ds, fs in os.walk(app):
        rel_d = os.path.relpath(d, app)
        ds[:] = sorted(x for x in ds if not (rel_d == "." and x in EXCL_DIRS))
        for f in sorted(fs):
            if not f.endswith(".swift") or " 2" in f:
                continue
            rel = os.path.normpath(os.path.join(rel_d, f))
            if rel in EXCL_FILES:
                continue
            yield "RailMap/" + rel, os.path.join(d, f)

def scan(app=None):
    found = {}  # (rel, rule) -> [lineno]
    for rel, path in files(app):
        lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
        def add(rule, i):
            found.setdefault((rel, rule), []).append(i + 1)
        for i, line in enumerate(lines):
            st = line.strip()
            if st.startswith("//"):
                continue
            if (R_STATUS.search(line) and not R_STATUS_OK.search(line)
                    and rel[len("RailMap/"):] not in STATUS_COLOR_FILES):
                add("status-color", i)
            # An opt-out must say why: `// ui-token-ok:` with no reason does not count.
            if R_OK.search(line):
                continue
            for m in R_PAD.finditer(line):
                if has_big(inner(line, m.end())): add("padding-literal", i)
            for m in R_SPC.finditer(line):
                if has_big(inner(line, m.end(), True)): add("spacing-literal", i)
            for m in R_EDGE.finditer(line):
                if has_big(inner(line, m.end())): add("edgeinsets-literal", i)
            for m in R_MIN.finditer(line):
                if 20 <= float(m.group(1)) < 44: add("small-touch", i)
            for m in R_RAD.finditer(line):
                if m.group(1) != "0": add("radius-literal", i)
            if R_TOUCH.search(line): add("touch-literal", i)
            if R_BORD.search(line): add("stock-bordered", i)
            if R_FONT.search(line): add("fixed-font", i)
            if R_FOOT.search(line): add("footnote-font", i)
            if R_DET.search(line): add("raw-detents", i)
            if R_CAPS.search(line): add("direct-capsule", i)
            if R_TB.search(line):
                nxt = "\n".join(lines[i + 1:i + 4])
                if R_DISMISS.search(nxt) and "RailSheetCloseButton" not in nxt:
                    add("dismiss-text", i)
            km = R_KEYDEF.match(line)
            if km and dismiss_key(km.group(1)): add("feature-dismiss-key", i)
            for m in R_KEYUSE.finditer(line):
                if dismiss_key(m.group(1)): add("feature-dismiss-key", i)
    return found

def self_test():
    import tempfile
    # (swift line, expected rules on that line)
    cases = [
     ('.padding(.horizontal, 6)', ["padding-literal"]),
     ('.padding(.horizontal, compact ? 6 : 7)', ["padding-literal"]),
     ('.padding(x + 4)', ["padding-literal"]),
     ('.padding(.top, isOn ? RailSpacing.s4 : 10)', ["padding-literal"]),
     ('.padding(.horizontal, compact ? RailSpacing.s4 : RailSpacing.s8)', []),
     ('.padding(RailSpacing.s12)', []),
     ('.padding(.horizontal, 2)', []),
     ('.padding()', []),
     ('.padding(.top, 6) // ui-token-ok: legacy', []),
     ('.padding(.top, 6) // ui-token-ok:', ["padding-literal"]),
     ('.padding(.top, 6) // ui-token-ok:   ', ["padding-literal"]),
     ('// .padding(.top, 6)', []),
     ('VStack(spacing: 6) {', ["spacing-literal"]),
     ('VStack(spacing: base * 3) {', ["spacing-literal"]),
     ('VStack(spacing: RailSpacing.s12) {', []),
     ('VStack(alignment: .leading, spacing: 0) {', []),
     ('HStack(spacing: RailSpacing.s4, content: 9) {', []),
     ('let e = EdgeInsets(top: 8, leading: RailSpacing.s4, bottom: 0, trailing: 0)', ["edgeinsets-literal"]),
     ('let e = EdgeInsets(top: RailSpacing.s4, leading: 2, bottom: 0, trailing: 1)', []),
     ('let e = UIEdgeInsets(top: 56, left: 0, bottom: 0, right: 0)', []),
     ('let e = NSDirectionalEdgeInsets(top: 56, leading: 0, bottom: 0, trailing: 0)', []),
     ('.frame(minHeight: 32)', ["small-touch"]),
     ('.frame(minWidth: 20, minHeight: 43)', ["small-touch", "small-touch"]),
     ('.frame(minHeight: 44)', ["touch-literal"]),
     ('.frame(minHeight: 19)', []),
     ('.frame(minHeight: RailSize.touch)', []),
     ('.frame(height: 32)', []),
     ('.frame(minHeight: 32) // ui-token-ok: decorative', []),
     ('.presentationDetents([.medium])', ["raw-detents"]),
     ('.presentationDetents([.medium]) // ui-token-ok: map sheet', []),
     ('.railSheet(.half)', []),
     ('.font(.system(size: 14))', ["fixed-font"]),
     ('let f = Font.system(size: 12, weight: .bold)', ["fixed-font"]),
     ('let f = .system(size: 12)', ["fixed-font"]),
     ('.font(.system(size: size))', []),
     ('.font(.system(.body))', []),
     ('.font(.footnote)', ["footnote-font"]),
     ('.font(.footnote.weight(.bold))', ["footnote-font"]),
     ('let f = Font.footnote', ["footnote-font"]),
     ('UIFont.preferredFont(forTextStyle: .footnote)', []),
     ('.font(.footnote) // ui-token-ok: system label', []),
     ('.font(.footnoteLike)', []),
     ('.buttonStyle(RailCapsuleButtonStyle(kind: .primary))', ["direct-capsule"]),
     ('.buttonStyle(.railPrimary)', []),
     ('.cornerRadius(8)', ["radius-literal"]),
     ('.cornerRadius(0)', []),
     ('.frame(width: 44, height: 44)', ["touch-literal"]),
     ('.frame(width: RailSize.touch, height: RailSize.touch)', []),
     ('.buttonStyle(.bordered)', ["stock-bordered"]),
     ('"feature.cancel": [.en: "Cancel"],', ["feature-dismiss-key"]),
     ('"ios.guide.done": [', ["feature-dismiss-key"]),
     ('"data.importDone": [', ["feature-dismiss-key"]),
     ('"video.Close": [', ["feature-dismiss-key"]),
     ('"ios.cancel": [.en: "Cancel"],', []),
     ('"ios.close": [', []),
     ('"ios.done": [', []),
     ('"ios.guide.undone": [', []),
     ('"ios.guide.abandoned": [', []),
     ('"ios.guide.title": [', []),
     ('"feature.close": [', ["feature-dismiss-key"]),
     ('"feature.cancel": [ // ui-token-ok: legacy', []),
     ('Text(text("data.done"))', ["feature-dismiss-key"]),
     ('Text(countryText("video.cancel", region))', ["feature-dismiss-key"]),
     ('Text(text("ios.done"))', []),
     ('Text(m).foregroundStyle(.orange)', ["status-color"]),
     ('Text(m).foregroundStyle(.red)', ["status-color"]),
     ('.foregroundStyle(ok ? Color.secondary : Color.orange)', ["status-color"]),
     ('.foregroundColor(Color.red)', ["status-color"]),
     ('.foregroundStyle(Color(.systemOrange))', ["status-color"]),
     ('.foregroundStyle(.red) // ui-token-ok: error text', ["status-color"]),
     ('.foregroundStyle(.red) // status-color-ok: record dot', []),
     ('.foregroundStyle(.red) // status-color-ok:', ["status-color"]),
     ('.foregroundStyle(.secondary)', []),
     ('.foregroundStyle(.reddish)', []),
     ('.foregroundStyle(tint)', []),
     ('.background(Color.orange.opacity(0.2))', []),
     ('.tint(.orange)', []),
     ('Text(text("ios.guide.title"))', []),
    ]
    with tempfile.TemporaryDirectory() as tmp:
        app = os.path.join(tmp, "RailMap")
        os.makedirs(os.path.join(app, "Feature"))
        os.makedirs(os.path.join(app, "Localization"))
        os.makedirs(os.path.join(app, "Design"))
        os.makedirs(os.path.join(app, "Diagnostics"))
        body = [c[0] for c in cases]
        # multi-line dismiss-text cases appended after the single-line ones
        extra = [
         ('ToolbarItem(placement: .cancellationAction) {', "dismiss-text"),
         ('    Button(text("ios.close")) { dismiss() }', None),
         ('}', None),
         ('ToolbarItem(placement: .cancellationAction) {', None),
         ('    RailSheetCloseButton(text("ios.close")) { dismiss() }', None),
         ('}', None),
        ]
        expected = []
        for n, (line, rules) in enumerate(cases, 1):
            expected += [("Feature/Main.swift", n, r) for r in rules]
        for k, (line, rule) in enumerate(extra):
            body.append(line)
            if rule: expected.append(("Feature/Main.swift", len(cases) + k + 1, rule))
        open(os.path.join(app, "Feature", "Main.swift"), "w").write("\n".join(body) + "\n")
        # same string-table line must also be scanned under Localization/
        open(os.path.join(app, "Localization", "XStrings.swift"), "w").write(
            '        "x.cancel": [.en: "Cancel"],\n        "x.ok": [.en: "OK"],\n')
        expected.append(("Localization/XStrings.swift", 1, "feature-dismiss-key"))
        # a file named in STATUS_COLOR_FILES is exempt from status-color only
        os.makedirs(os.path.join(app, "JourneyEditor"))
        open(os.path.join(app, "JourneyEditor", "EditorTimeSection.swift"), "w").write(
            'Text(m).foregroundStyle(.red)\n.padding(.top, 9)\n')
        expected.append(("JourneyEditor/EditorTimeSection.swift", 2, "padding-literal"))
        # Design/ and Diagnostics/ are excluded entirely
        for d in ("Design", "Diagnostics"):
            open(os.path.join(app, d, "Z.swift"), "w").write(
                '.presentationDetents([.medium])\n.buttonStyle(RailCapsuleButtonStyle(kind: .primary))\n.padding(.top, 9)\n')
        got = []
        for (rel, rule), lns in scan(app).items():
            got += [(rel[len("RailMap/"):], ln, rule) for ln in lns]
        if sorted(got) != sorted(expected):
            print("self-test FAILED")
            for t in sorted(set(expected) - set(got)):
                print("  missing :", t, (body[t[1] - 1] if t[0].endswith("Main.swift") else ""))
            for t in sorted(set(got) - set(expected)):
                print("  spurious:", t, (body[t[1] - 1] if t[0].endswith("Main.swift") else ""))
            if len(got) != len(expected):
                print(f"  (counts: got {len(got)}, expected {len(expected)})")
            sys.exit(1)
    return len(cases) + len(extra)

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

if args and args[0] == "--self-test":
    print(f"ui tokens self-test: ok ({self_test()} cases)")
    sys.exit(0)
self_test()  # the guard must not rot silently; stays well under a second

found = scan()
counts = {k: len(v) for k, v in found.items()}

if args and args[0] == "--update":
    paths = [a for a in args[1:] if a != "--force"]
    if not paths:
        # A whole-file rewrite must not be a way to raise counts silently.
        grow = [f"{k[0]}: {k[1]} {c0} -> {counts.get(k, 0)}" for k, c0 in
                ((k, load().get(k, 0)) for k in set(load()) | set(counts))
                if counts.get(k, 0) > c0]
        if grow and "--force" not in args:
            print("refusing --update: counts would grow (pass --force only for a reviewed reset):\n  "
                  + "\n  ".join(sorted(grow)))
            sys.exit(1)
        write(counts)
        print(f"baseline regenerated: {len(counts)} entries")
        sys.exit(0)
    # Baseline keys are relative to ios/. Accept repo-relative ("ios/RailMap/…"),
    # ios-relative ("RailMap/…") and absolute paths; refuse anything else, so a
    # mistyped path can never "succeed" while lowering nothing.
    norm = []
    for p in paths:
        a = os.path.realpath(p)
        if a.startswith(os.path.realpath(ios) + os.sep):
            q = os.path.relpath(a, os.path.realpath(ios))
        elif p.startswith("ios/"):
            q = p[4:]
        else:
            q = p
        q = os.path.normpath(q)
        if not os.path.isfile(os.path.join(ios, q)):
            print(f"refusing --update: not a file under ios/: {p}")
            sys.exit(2)
        norm.append(q)
    paths = norm
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
    print("usage: check-ui-tokens.sh [--self-test | --update [PATH...]]"); sys.exit(2)

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
