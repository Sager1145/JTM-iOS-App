#!/usr/bin/env bash
# Static check: every accessibility identifier referenced by ios/RailMapUITests
# must exist as a string literal (or interpolated template) in ios/RailMap sources.
# No simulator/xcodebuild needed. Exit 1 if any identifier is missing.
#
# How it works
#  - UI-test side: element-type subscripts (app.buttons["x"]), matching/containing(identifier:),
#    NSPredicate "identifier == 'x'", element("x", ...)/revealSwitch("x"...) helpers, named
#    *ID:/identifier: arguments, and `for identifier in ["a","b"]` lists.
#  - Strings with spaces or a leading capital are treated as labels (system buttons like
#    "Done"), not identifiers, and skipped. Strings with "\(" are dynamic: reported as
#    "unchecked (dynamic)" (their literal prefix is only sanity-checked, as a warning).
#  - Ids used only inside XCTAssertFalse/XCTAssertNil are expected to be absent: reported, not required.
#  - App side: any Swift string literal in ios/RailMap (identifiers are usually passed to
#    helpers as parameters, so .accessibilityIdentifier("x") alone would miss most of them).
#    Literals containing "\(...)" act as templates ("rideEditorStop-\(i)" matches "rideEditorStop-0");
#    a template that starts with an interpolation ("\(prefix)-x") only matches when the id's leading part
#    is itself a literal in the app (e.g. "statisticsYear" passed as accessibilityPrefix).
set -euo pipefail
IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -I - "$IOS_DIR" <<'PY'
import os, re, sys
ios = sys.argv[1]
APP, UI = os.path.join(ios, "RailMap"), os.path.join(ios, "RailMapUITests")

def swift_files(root):
    for d, _, fs in os.walk(root):
        for f in sorted(fs):
            if f.endswith(".swift"):
                yield os.path.join(d, f)

# ---- app side
INTERP = r'\\\((?:[^()"]|"(?:[^"\\]|\\.)*"|\((?:[^()]|\([^()]*\))*\))*\)'
LIT = re.compile(r'"((?:[^"\\\n]|' + INTERP + r'|\\.)*)"')
exact, templates, lead_templates = set(), [], []
for p in swift_files(APP):
    for line in open(p, encoding="utf-8", errors="replace"):
        for m in LIT.finditer(line):
            s = m.group(1)
            if "\\(" in s:
                parts = re.split(INTERP, s)
                body = ".+".join(map(re.escape, parts[1:])) if not parts[0] else None
                if parts[0]:
                    templates.append((re.compile("^" + ".+".join(map(re.escape, parts)) + "$"), parts[0]))
                else:  # "\(prefixVar)-x": only matches when the id's leading part is itself an app literal
                    lead_templates.append((re.compile("^(.+?)" + body + "$"), parts[0]))
            else:
                exact.add(s)
def in_app(s):
    if s in exact or any(r.match(s) for r, _ in templates): return True
    for r, _ in lead_templates:
        m = r.match(s)
        if m and len(m.group(1)) >= 6 and m.group(1) in exact: return True
    return False
def prefix_in_app(pref):
    return any(e.startswith(pref) for e in exact) or any(t.startswith(pref) or pref.startswith(t) for _, t in templates)

# ---- test side
TYPES = r'(?:buttons|otherElements|staticTexts|textFields|secureTextFields|switches|cells|scrollViews|images|sheets|alerts|segmentedControls|tables|collectionViews|navigationBars|tabBars|textViews|searchFields|pickers|pickerWheels|sliders|toggles|links|menuItems|menus|windows|webViews|maps|steppers|datePickers|progressIndicators|activityIndicators|popovers|toolbars|outlines|groups|any)'
S = r'"((?:[^"\\\n]|\\.)*)"'
PATS = [
    re.compile(r'\.' + TYPES + r'\[' + S + r'\]'),
    re.compile(r'(?:matching|containing)\((?:[^()"]*,\s*)?identifier:\s*' + S),
    re.compile(r"identifier\s*==\s*'([^']*)'"),
    re.compile(r'\b(?:element|revealSwitch|revealRideRow|revealButton)\(' + S),
    re.compile(r'\b\w*(?:ID|Id|Identifier|identifier):\s*' + S),
]
FOR = re.compile(r'for\s+\w*(?:identifier|Identifier|id|ID)\w*\s+in\s+\[([^\]]*)\]')
IDSHAPE = re.compile(r'^[a-z][A-Za-z0-9_.\-]*$')
DATA = re.compile(r'^(journey_|\d{8}_|com\.|return$|delete$)|\.json$')  # fixture ids, bundle ids, keys, files: not UI identifiers

refs = {}  # id -> [(rel, line)]
neg = {}   # ids asserted ABSENT (XCTAssertFalse/Nil): must not be required to exist
labels = 0
for p in swift_files(UI):
    rel = os.path.relpath(p, ios)
    prev = ""
    for n, line in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
        was_prev, prev = prev, line
        if line.lstrip().startswith("//"): continue
        negative = bool(re.search(r'XCTAssert(?:False|Nil)\(', line) or re.search(r'XCTAssert(?:False|Nil)\(\s*$', was_prev))
        found = []
        for pat in PATS: found += [m.group(1) for m in pat.finditer(line)]
        for m in FOR.finditer(line): found += re.findall(S, m.group(1))
        for s in found:
            if "\\(" not in s and (not IDSHAPE.match(s) or DATA.search(s)): labels += 1; continue
            (neg if negative else refs).setdefault(s, []).append((rel, n))

missing, dynamic, ok = [], [], 0
for s, locs in sorted(refs.items()):
    if "\\(" in s:
        pref = s.split("\\(")[0]
        dynamic.append((s, locs, bool(pref) and prefix_in_app(pref)))
    elif in_app(s): ok += 1
    else: missing.append((s, locs))

for s, locs in sorted(neg.items()):
    if s not in refs:
        print(f"unchecked (asserted absent): '{s}' at {locs[0][0]}:{locs[0][1]}")
for s, locs, pok in dynamic:
    print(f"unchecked (dynamic): '{s}' at {locs[0][0]}:{locs[0][1]}" + ("" if pok else "  [WARN: literal prefix not found in ios/RailMap]"))
for s, locs in missing:
    for rel, n in locs:
        print(f"MISSING: identifier '{s}' used at {rel}:{n} is not set anywhere in ios/RailMap; "
              f"restore .accessibilityIdentifier(\"{s}\") or update the test")
print(f"identifiers checked: {ok + len(missing)}, found: {ok}, missing: {len(missing)}, "
      f"unchecked (dynamic): {len(dynamic)}, skipped labels/data ids: {labels}")
sys.exit(1 if missing else 0)
PY
