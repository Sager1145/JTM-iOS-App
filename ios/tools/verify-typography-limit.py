#!/usr/bin/env python3
"""Prevent removal or widening of the user's permanent app text-size bounds."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
source = (root / "RailMap" / "RailMapApp.swift").read_text()
assert re.search(
    r"supportedSizes:\s*ClosedRange<DynamicTypeSize>\s*=\s*\.xSmall\s*\.\.\.\s*\.xLarge",
    source,
), "AppTypographyPolicy must retain the exact xSmall...xLarge range."
window = source.split("WindowGroup {", 1)[1].split("// There is no", 1)[0]
clamp = ".dynamicTypeSize(AppTypographyPolicy.supportedSizes)"
assert clamp in window, "Every WindowGroup content path must apply the permanent bounds."
assert window.index(clamp) > window.rfind("#endif"), "The bounds must also apply in Release."
roles = (root / "RailMap" / "RailType.swift").read_text()
assert re.search(r"static func range\(_ role: Role\).*?\{\s*AppTypographyPolicy.supportedSizes\s*\}", roles, re.S), \
    "Every role, including captions and subtitles, must use the permanent app bounds."
for file in (root / "RailMap").rglob("*.swift"):
    code = file.read_text()
    assert not re.search(r"\.environment\(\s*\\\.dynamicTypeSize\s*,", code), \
        f"{file.name} bypasses the permanent typography policy."
    assert not re.search(r"\.dynamicTypeSize\(\s*\.(xxLarge|xxxLarge|accessibility[1-5])\s*\)", code), \
        f"{file.name} forces a text size above the permanent ceiling."
print("[PASS] permanent xSmall...xLarge app typography bounds (Debug and Release)")
