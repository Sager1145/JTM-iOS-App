#!/usr/bin/env bash
# Static check: every string key the app looks up exists, in all four languages
# (en, ja, zh-Hans, zh-Hant), in the app's string tables (audit H2,
# docs/maintenance/2026-11-11-ui-audit.md).
#
# The real lookup (RailMap/Localization/AppLocalization.swift `text`):
#   1. the shipped catalog ios/Resources/Localizable.xcstrings (bundled as Localizable.json),
#   2. the merged native tables (RailMap/Localization/*Strings.swift, `"key": [.en: ..., .ja: ...]`),
#   3. the caller's `fallback:`, else the key itself -- which is English text in every language.
# A key in neither 1 nor 2, or present in only some languages, ships English (or a
# fallback chain guess) to Japanese and Chinese readers. This guard fails on that.
#
# Call sites checked: a string literal as the first argument of `text(`, `countryText(`
# or `journeyText(` (multi-line calls included). Not checked: keys passed as variables.
# A literal that continues dynamically (`"ios.ai." + key`, `"ios.x.\(n)"`) is a dynamic
# key; its prefix must be listed in DYNAMIC_PREFIXES below, and some table key must
# start with that prefix. Files that define their own `func text(_ key` wrapper (the
# wrapper adds a prefix) are skipped for bare `text(` calls.
#
#   check-string-keys.sh              check (exit 1 on any missing key or unlisted dynamic key)
#   check-string-keys.sh --self-test  synthetic positive/negative cases (also runs before every check)
set -euo pipefail
IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -I - "$IOS_DIR" "$@" <<'PY'
import json, os, re, sys, tempfile
ios = sys.argv[1]
args = sys.argv[2:]

LANGS = ("en", "ja", "zh-Hans", "zh-Hant")
SWIFT_LANG = {"en": "en", "ja": "ja", "zhHans": "zh-Hans", "zhHant": "zh-Hant"}

# Dynamic key prefixes that are allowed. Each is a literal prefix followed by a
# runtime value; the guard cannot check the full key, so it checks the prefix is
# real and leaves the suffixes to review. Add a prefix here only with a comment.
DYNAMIC_PREFIXES = {
    # Suffix is an enum raw value or a small fixed set chosen at runtime.
    "ios.newTrip.fillSource.": "editor fill-source badge",
    "ios.editor.serviceType.": "service type picker",
    "ios.ticket.kind.": "ticket kind picker",
    "stoptype.": "stop type name (web catalog)",
    "ios.tripNotes.category.default.": "built-in trip-note categories",
    "ios.station.": "station card facts and statuses",
    "ios.editor.pattern.": "service pattern picker, incl. fact./detail. wrappers",
}

USE = re.compile(r'(?<![A-Za-z0-9_])(text|countryText|journeyText)\(\s*"((?:[^"\\]|\\.)*)"(\s*\+)?')
# `func text(_ key: String ...)` wrappers: each prepends its own prefix to the key.
WRAPPER = re.compile(r'(?:\b(private|fileprivate)\s+)?func\s+text\(\s*_\s+\w+\s*:\s*String')
KEYDEF = re.compile(r'^[ \t]*"([A-Za-z0-9_.\-]+)"\s*:\s*\[', re.M)
LANGREF = re.compile(r'\.(en|ja|zhHans|zhHant)\s*:')

def swift_files(root):
    for d, ds, fs in os.walk(root):
        ds[:] = sorted(ds)
        for f in sorted(fs):
            if f.endswith(".swift") and " 2" not in f:
                yield os.path.join(d, f)

def skip_string(s, i):
    """s[i] is a quote; return the index just past the closing quote."""
    i += 1
    while i < len(s):
        if s[i] == "\\": i += 2; continue
        if s[i] == '"': return i + 1
        i += 1
    return i

def table_keys(app):
    """{key: set(languages)} from every `"key": [ .en: ..., ... ]` entry in any RailMap Swift file."""
    out = {}
    for path in swift_files(app):
        s = open(path, encoding="utf-8", errors="replace").read()
        for m in KEYDEF.finditer(s):
            i, depth, langs = m.end(), 1, set()
            while i < len(s) and depth:
                c = s[i]
                if c == '"': i = skip_string(s, i); continue
                if c == "[": depth += 1
                elif c == "]": depth -= 1
                elif c == "." and depth == 1:
                    lm = LANGREF.match(s, i)
                    if lm: langs.add(SWIFT_LANG[lm.group(1)])
                i += 1
            if langs:
                out.setdefault(m.group(1), set()).update(langs)
    return out

def catalog_keys(path):
    if not os.path.exists(path): return {}
    data = json.load(open(path, encoding="utf-8"))
    out = {}
    for key, entry in data.get("strings", {}).items():
        locs = entry.get("localizations", {}) or {}
        out[key] = {l for l, v in locs.items() if (v.get("stringUnit") or {}).get("value")}
    return out

def wrappers(s):
    """(is_private, prefix, own_call_offsets) for every `func text(_ key: String ...)` in s."""
    found = []
    for m in WRAPPER.finditer(s):
        i = s.find("{", m.end())
        if i < 0: continue
        start, depth = i, 0
        while i < len(s):
            c = s[i]
            if c == '"': i = skip_string(s, i); continue
            if c == "{": depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0: break
            i += 1
        prefix, own = "", set()
        for u in USE.finditer(s, start, i):
            if u.group(3) or "\\(" in u.group(2):
                prefix = u.group(2).split("\\(")[0]
                own.add(u.start())
        found.append((m.group(1) is not None, prefix, own))
    return found

def check(ios_dir):
    app = os.path.join(ios_dir, "RailMap")
    known = {}
    for src in (catalog_keys(os.path.join(ios_dir, "Resources", "Localizable.xcstrings")),
                table_keys(app)):
        for k, langs in src.items():
            known.setdefault(k, set()).update(langs)
    sources = {path: open(path, encoding="utf-8", errors="replace").read() for path in swift_files(app)}
    wrap = {path: wrappers(s) for path, s in sources.items()}
    global_prefixes = sorted({pre for ws in wrap.values() for priv, pre, _ in ws if not priv and pre})
    problems, seen = [], set()
    for path, s in sources.items():
        rel = os.path.relpath(path, ios_dir)
        own = set().union(*[o for _, _, o in wrap[path]]) if wrap[path] else set()
        local = sorted({pre for priv, pre, _ in wrap[path] if priv})
        for m in USE.finditer(s):
            if m.start() in own: continue
            fn, key, plus = m.group(1), m.group(2), m.group(3)
            dot = s[m.start() - 1] == "." if m.start() else False
            line = s.count("\n", 0, m.start()) + 1
            if "\\(" in key or plus:
                prefix = key.split("\\(")[0]
                if not any(prefix.startswith(p) for p in DYNAMIC_PREFIXES):
                    problems.append(f'{rel}:{line}: dynamic key "{prefix}..." is not in DYNAMIC_PREFIXES')
                continue
            if fn == "text" and not dot:
                if local: cands = [pre + key for pre in local]
                elif "." not in key and global_prefixes: cands = [pre + key for pre in global_prefixes]
                else: cands = [key]
            else:
                cands = [key]
            seen.update(cands)
            if any(known.get(c) is not None and all(l in known[c] for l in LANGS) for c in cands):
                continue
            c = cands[0]
            have = known.get(c)
            if have is None:
                problems.append(f'{rel}:{line}: key "{c}" is in no strings table')
            else:
                gone = ", ".join(l for l in LANGS if l not in have)
                problems.append(f'{rel}:{line}: key "{c}" lacks {gone}')
    for p in DYNAMIC_PREFIXES:
        if not any(k.startswith(p) for k in known):
            problems.append(f'DYNAMIC_PREFIXES entry "{p}" matches no table key')
    return problems, len(seen)

def self_test():
    with tempfile.TemporaryDirectory() as tmp:
        for d in ("RailMap/Feature", "RailMap/Localization", "Resources"):
            os.makedirs(os.path.join(tmp, d))
        full = '[.en: "A", .ja: "あ", .zhHans: "甲", .zhHant: "甲"]'
        open(os.path.join(tmp, "RailMap/Localization/XStrings.swift"), "w").write(
            'enum XStrings { static let table = [\n'
            f'  "x.ok": {full},\n'
            '  "x.partial": [.en: "P", .ja: "ぷ", .zhHans: "p [x]"],\n'
            '  "x.multi": [\n    .en: "M \\" ] quote",\n    .ja: "m",\n    .zhHans: "m",\n    .zhHant: "m",\n  ],\n'
            f'  "x.dyn.one": {full},\n]}}\n')
        json.dump({"strings": {"cat.ok": {"localizations": {
            l: {"stringUnit": {"value": "v"}} for l in LANGS}},
            "cat.part": {"localizations": {"en": {"stringUnit": {"value": "v"}}}}}},
            open(os.path.join(tmp, "Resources/Localizable.xcstrings"), "w"))
        good = ('Text(text("x.ok"))\nText(localization.countryText("cat.ok"))\n'
                'Text(journeyText(\n    "x.multi",\n    fallback: "M"))\n'
                'Text(l.text("x.ok", params: [:], fallback: "Fine"))\n'
                'Text(text(key))\nTextField(text: $t)\n')
        open(os.path.join(tmp, "RailMap/Feature/Good.swift"), "w").write(good)
        # a file with its own private text(_ key:) wrapper: bare text("one") means x.dyn.one;
        # the wrapper's own prefixed call is its definition, not a dynamic use
        open(os.path.join(tmp, "RailMap/Feature/Wrap.swift"), "w").write(
            'private func text(_ key: String) -> String { l.text("x.dyn." + key) }\n'
            'Text(text("one"))\nText(l.text("x.ok"))\nText(text("nope"))\n')
        probs, _ = check(tmp)
        assert not [p for p in probs if "Good.swift" in p or "Wrap.swift:2" in p or "Wrap.swift:3" in p], probs
        assert any("Wrap.swift:4" in p and "x.dyn.nope" in p for p in probs), probs
        os.remove(os.path.join(tmp, "RailMap/Feature/Wrap.swift"))
        bad = ('Text(text("x.missing"))\n'          # in no table
               'Text(text("x.partial"))\n'          # lacks zh-Hant
               'Text(countryText("cat.part"))\n'    # catalog entry with one language
               'Text(journeyText(\n  "x.gone"))\n'  # multi-line missing
               'Text(text("x.ok.\\(n)"))\n')        # dynamic, unlisted
        open(os.path.join(tmp, "RailMap/Feature/Bad.swift"), "w").write(bad)
        probs, _ = check(tmp)
        bp = [p for p in probs if "Bad.swift" in p]
        want = ["Bad.swift:1:", "Bad.swift:2:", "Bad.swift:3:", "Bad.swift:4:", "Bad.swift:6:"]
        for w in want:
            assert any(w in p for p in bp), (w, bp)
        assert len(bp) == len(want), bp
        assert any("x.partial" in p and "zh-Hant" in p for p in bp), bp
    return 10

if args and args[0] == "--self-test":
    try:
        n = self_test()
    except AssertionError as e:
        print(f"string keys self-test FAILED: {e}")
        sys.exit(1)
    print(f"string keys self-test: ok ({n} checks)")
    sys.exit(0)
try:
    self_test()
except AssertionError as e:
    print(f"string keys self-test FAILED: {e}")
    sys.exit(1)

problems, n = check(ios)
if problems:
    print("string keys: missing or incomplete translations (add the key, in all four languages, to a\n"
          "RailMap/Localization/*Strings.swift table or ios/Resources/Localizable.xcstrings;\n"
          "reuse an existing key when one already means the same thing):")
    for p in problems: print("  " + p)
    sys.exit(1)
print(f"string keys: ok ({n} distinct literal keys, all present in en/ja/zh-Hans/zh-Hant)")
PY
