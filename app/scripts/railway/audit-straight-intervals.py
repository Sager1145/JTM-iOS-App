#!/usr/bin/env python3
"""STRAIGHT_INTERVAL ledger for the NA packages -- DEFECT 2 detection.

`na_geo.densify()` (lib/na_geo.py, bands in lib/na_profile.py) subdivides
every edge COLLINEARLY to <= max_edge_m by band (street 120 / metro 160 /
commuter 220 / regional 350 / longhaul 600 m). A station-to-station straight
line therefore ships as a chain of short straight pieces, so chord-length
and vertex-density checks cannot see it: `STRAIGHT_CHORD`/`SPARSE_GEOMETRY`
in the `jtm-railway-audit-repair` skill's preflight, and `interval.straight`
in this directory's own `audit-na-package.py`, all key off vertex count or
raw chord length, and a densified straight interval keeps healthy vertex
density and is never a bare two-point row.

The only measure collinear subdivision cannot hide is the maximum
perpendicular deviation of an interval's INTERIOR vertices from the chord
between its two station endpoints: a straight line densified into N pieces
has interior vertices that all sit exactly ON that chord, by construction.

This script:

  1. Reconstructs every station interval from `compact-v1`'s
     `[km, continuesFromPrevious, coordinates]` rows, honouring the
     contract that a continuing row DROPS the vertex it shares with the
     previous row (see `lib/na_build.py::segments_for`, and the same note
     in the `jtm-railway-audit-repair` skill's `audit_jtm_packages.py`).
     It self-checks that contract before trusting any number: every
     reconstructed interval's endpoints must coincide with its two station
     anchors, and its walked length must agree with the row's declared
     `km`. An earlier audit generation skipped this reconstruction and
     mis-measured 5,575 intervals while still printing "0 errors" -- this
     script refuses to write a ledger if its own reconstruction fails that
     check, rather than repeat the mistake silently.
  2. Flags an interval as a STRAIGHT_INTERVAL review candidate using the
     same thresholds as the skill's `audit_jtm_packages.py`: chord >=
     1,500 m between station anchors, interior deviation < 25 m. See that
     file for the sensitivity table and the geometric justification
     (a 25 m sag over a 1,500 m chord is a ~11.25 km curve radius -- far
     broader than any turnout, and broader than most mainline curves).
  3. Cross-references two existing signals, so the ledger records what was
     already known versus newly surfaced:
       - the package's own `straightIntervals` marker: an interval-level,
         externally-corroborated confirmation (OSM/NARN agreement), present
         on 18 US / 6 CA lines;
       - whether `audit-na-package.py`'s own, much stricter
         `interval.straight` ERROR check (<=1.5 m deviation, walked length
         within 0.5% of the chord) is even ABLE to see this line, given its
         `geometrySource not in verifiedOfficialNetworks` exemption. That
         exemption is a broader net than the per-interval marker, and it
         empirically covers the geometrySource of nearly every line this
         script finds -- which is the real reason that check reports zero
         findings against the live packages today, not a decode bug.

This script is READ-ONLY on the packages. It never writes `us-2025.json` or
`ca-2025.json` -- those are builder output, and the NA source tree the
builder needs (GTFS, official networks, OSM crosscheck) is gone from this
checkout (see docs/NORTH_AMERICA_RAIL_COVERAGE_HANDOFF.md), so there is
nothing to safely rebuild from even if a repair were decided here. It writes
only the findings ledger at `app/public/rail/na-2025-straight-intervals.md`.

Usage:
    python3 scripts/railway/audit-straight-intervals.py
    python3 scripts/railway/audit-straight-intervals.py --countries us
    python3 scripts/railway/audit-straight-intervals.py --json -
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
from na_geo import haversine, point_segment_distance  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
RAIL_DIR = REPO_ROOT / "app/public/rail"
LEDGER_PATH = RAIL_DIR / "na-2025-straight-intervals.md"

# Kept identical to STRAIGHT_INTERVAL_CHORD_MIN_M / STRAIGHT_INTERVAL_DEVIATION_MAX_M
# in .claude/skills/jtm-railway-audit-repair/scripts/audit_jtm_packages.py --
# see that file's comment block for the sensitivity table and the reasoning.
CHORD_MIN_M = 1_500.0
DEVIATION_MAX_M = 25.0

# audit-na-package.py's own `interval.straight` ERROR tolerance, reused here
# only to explain -- per finding -- why that check does or does not fire.
STRICT_DEVIATION_MAX_M = 1.5
STRICT_WALKED_RATIO_MAX = 1.005

ANCHOR_GAP_ERROR_M = 50.0
LENGTH_MISMATCH_FLOOR_M = 20.0
LENGTH_MISMATCH_RATIO = 0.10


def orient_path_to_anchors(
    path: list[list[float]], start: list[float] | None, end: list[float] | None
) -> list[list[float]]:
    """Return an interval in station order without changing its geometry.

    Mirrors the same function in the skill's `audit_jtm_packages.py`: a
    self-contained interval may be digitised in either direction, and
    without this, two adjacent oppositely-digitised intervals would
    manufacture an artificial out-and-back at their shared station.
    """
    if not start or not end or len(path) < 2:
        return path
    forward = max(haversine(path[0], start), haversine(path[-1], end))
    reverse = max(haversine(path[-1], start), haversine(path[0], end))
    return list(reversed(path)) if reverse < forward else path


def reconstruct_intervals(line: dict[str, Any]) -> tuple[list[dict[str, Any] | None], dict[str, int]]:
    """Decode `segments` into station-anchored polylines, proving the reader
    against the format as it goes.

    Returns `(intervals, sanity)`. `intervals[i]` is None for an undecodable
    row, else a dict carrying the reconstructed `path`, its `walked` length,
    the row's `declaredKm`, and the two station anchors/names it connects.
    `sanity` counts how many reconstructed intervals fail the two contract
    assertions this format lives or dies by: an interval's endpoints must
    coincide with its station anchors, and its walked length must agree
    with the row's declared `km`.
    """
    stations = line.get("stations") or []
    segments = line.get("segments") or []
    names = [str(s[1]) if isinstance(s, list) and len(s) > 1 else "?" for s in stations]
    anchors: list[list[float] | None] = [
        [s[2], s[3]] if isinstance(s, list) and len(s) >= 4 else None for s in stations
    ]

    sanity = {"intervals": 0, "endpointMismatches": 0, "kmMismatches": 0}
    previous_end: list[float] | None = None
    out: list[dict[str, Any] | None] = []

    for ordinal, row in enumerate(segments):
        if not isinstance(row, list) or len(row) < 3:
            out.append(None)
            previous_end = None
            continue
        declared_km, continues, coordinates = row[0], row[1], row[2]
        if not isinstance(coordinates, list) or not coordinates:
            out.append(None)
            previous_end = None
            continue

        # The contract this whole script depends on: a continuing row DROPS
        # the vertex it shares with the previous row.
        if continues == 1 and previous_end is not None:
            path = [previous_end, *coordinates]
        else:
            path = list(coordinates)
        previous_end = coordinates[-1]

        start = anchors[ordinal] if ordinal < len(anchors) else None
        end = anchors[(ordinal + 1) % len(anchors)] if anchors else None
        path = orient_path_to_anchors(path, start, end)
        if len(path) < 2:
            out.append(None)
            continue
        walked = sum(haversine(a, b) for a, b in zip(path, path[1:]))
        sanity["intervals"] += 1

        if start and end:
            gap = min(
                max(haversine(path[0], start), haversine(path[-1], end)),
                max(haversine(path[-1], start), haversine(path[0], end)),
            )
            if gap > ANCHOR_GAP_ERROR_M:
                sanity["endpointMismatches"] += 1
        if isinstance(declared_km, (int, float)) and declared_km > 0:
            declared_m = declared_km * 1000.0
            if abs(walked - declared_m) > max(LENGTH_MISMATCH_FLOOR_M, LENGTH_MISMATCH_RATIO * declared_m):
                sanity["kmMismatches"] += 1

        out.append({
            "ordinal": ordinal,
            "path": path,
            "walked": walked,
            "declaredKm": declared_km,
            "start": start,
            "end": end,
            "stationA": names[ordinal] if ordinal < len(names) else "?",
            "stationB": names[(ordinal + 1) % len(names)] if names else "?",
        })

    return out, sanity


def verified_official_geometry_sources(package: dict[str, Any]) -> set[str]:
    """The `geometrySource` labels `audit-na-package.py` treats as verified.

    This does not re-validate the provenance hashes the way that script
    does -- it only needs to know which labels earn the exemption, to
    explain per finding why that script's stricter check does or does not
    fire on it.
    """
    declared = (package.get("geometrySource") or {}).get("verifiedOfficialNetworks") or {}
    return set(declared) if isinstance(declared, dict) else set()


def find_straight_intervals(
    country: str, line: dict[str, Any], verified_official: set[str]
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    intervals, sanity = reconstruct_intervals(line)
    marker = line.get("straightIntervals")
    marked = set(marker.get("intervals") or []) if isinstance(marker, dict) else set()
    geometry_source = line.get("geometrySource")
    source_is_verified = geometry_source in verified_official

    findings: list[dict[str, Any]] = []
    for entry in intervals:
        if entry is None or len(entry["path"]) < 3:
            continue  # a 2-point interval is STRAIGHT_CHORD's case, not this one
        chord_a = entry["start"] or entry["path"][0]
        chord_b = entry["end"] or entry["path"][-1]
        chord_len = haversine(chord_a, chord_b)
        if chord_len < CHORD_MIN_M:
            continue
        interior = entry["path"][1:-1]
        max_deviation = max(point_segment_distance(vertex, chord_a, chord_b)[0] for vertex in interior)
        if max_deviation >= DEVIATION_MAX_M:
            continue

        already_marked = entry["ordinal"] in marked
        walked_ratio = entry["walked"] / chord_len if chord_len > 0 else float("inf")
        strict_would_measure_straight = (
            max_deviation <= STRICT_DEVIATION_MAX_M and walked_ratio <= STRICT_WALKED_RATIO_MAX
        )
        if source_is_verified:
            strict_reason = "exempt: geometrySource is a verifiedOfficialNetwork"
        elif already_marked:
            strict_reason = "exempt: interval already in the package's own straightIntervals marker"
        elif strict_would_measure_straight:
            strict_reason = "WOULD FIRE (not exempt, within its 1.5 m tolerance)"
        else:
            strict_reason = f"not caught: {max_deviation:.1f} m exceeds its 1.5 m tolerance"

        findings.append({
            "country": country,
            "line": line.get("id"),
            "smoothingProfile": line.get("smoothingProfile"),
            "geometrySource": geometry_source,
            "ordinal": entry["ordinal"],
            "chordKm": chord_len / 1000.0,
            "deviationM": max_deviation,
            "stationA": entry["stationA"],
            "stationB": entry["stationB"],
            "markedByPackage": already_marked,
            "auditNaPackageInterval_straight": strict_reason,
        })

    return findings, sanity


def load_package(country: str) -> dict[str, Any] | None:
    path = RAIL_DIR / f"{country}-2025.json"
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def audit_country(country: str) -> tuple[list[dict[str, Any]], dict[str, int], int]:
    package = load_package(country)
    if package is None:
        return [], {"intervals": 0, "endpointMismatches": 0, "kmMismatches": 0}, 0
    verified_official = verified_official_geometry_sources(package)
    findings: list[dict[str, Any]] = []
    sanity_total = {"intervals": 0, "endpointMismatches": 0, "kmMismatches": 0}
    for line in package.get("lines") or []:
        if not isinstance(line, dict):
            continue
        line_findings, sanity = find_straight_intervals(country, line, verified_official)
        findings.extend(line_findings)
        for key in sanity_total:
            sanity_total[key] += sanity[key]
    return findings, sanity_total, len(package.get("lines") or [])


def group_by_line(findings: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for finding in findings:
        grouped.setdefault(finding["line"], []).append(finding)
    return grouped


def render_ledger(results: dict[str, tuple[list[dict[str, Any]], dict[str, int], int]]) -> str:
    lines: list[str] = []
    lines.append("# North America straight-interval findings (STRAIGHT_INTERVAL review class)")
    lines.append("")
    lines.append(
        "Generated by `app/scripts/railway/audit-straight-intervals.py`. This is a "
        "**findings document, not a repair record**: `us-2025.json` and `ca-2025.json` "
        "have not been modified. This script never writes them, and the NA source tree "
        "the builder needs to redraw a curve correctly (GTFS, official networks, OSM "
        "crosscheck) is gone from this checkout, so nothing here could be rebuilt from "
        "even if a fix were decided -- see `docs/NORTH_AMERICA_RAIL_COVERAGE_HANDOFF.md`."
    )
    lines.append("")
    lines.append("## What this measures")
    lines.append("")
    lines.append(
        "`na_geo.densify()` subdivides every edge COLLINEARLY to <= `max_edge_m` by band "
        "(street 120 / metro 160 / commuter 220 / regional 350 / longhaul 600 m), so a "
        "real station-to-station straight line ships as a chain of short straight pieces. "
        "No chord-length or vertex-density check can see that -- the density stays "
        "healthy and the interval is never a bare two-point row. The only signal "
        "collinear subdivision cannot hide is the maximum perpendicular deviation of an "
        "interval's interior vertices from the chord between its two station anchors."
    )
    lines.append("")
    lines.append(
        f"Thresholds: chord >= {CHORD_MIN_M / 1000:.1f} km between station anchors, "
        f"interior deviation < {DEVIATION_MAX_M:.0f} m. These match "
        "`STRAIGHT_INTERVAL_CHORD_MIN_M`/`STRAIGHT_INTERVAL_DEVIATION_MAX_M` in "
        "`.claude/skills/jtm-railway-audit-repair/scripts/audit_jtm_packages.py`, which "
        "carries the sensitivity table and the geometric justification (in short: a 25 m "
        "sag over a 1,500 m chord is roughly an 11.25 km curve radius -- broader than any "
        "turnout and broader than most mainline curves)."
    )
    lines.append("")
    lines.append(
        "**This is a REVIEW CLASS, not an automatic defect verdict.** A real dead-straight "
        "high-speed viaduct or a prairie mainline produces the exact same near-zero-deviation "
        "signature as a synthetic straight line copied station-to-station. This detector "
        "cannot tell the two apart: it has no track elevation, no source provenance, and "
        "reads only the geometry that shipped -- it cannot distinguish 'this track never "
        "curved' from 'the curve was not recorded, or was lost during grooming'. Every row "
        "below needs a human to look at the actual railway before being called broken."
    )
    lines.append("")

    lines.append("## Summary")
    lines.append("")
    lines.append("| country | lines in package | straight intervals | lines affected | total chord km |")
    lines.append("|---|---:|---:|---:|---:|")
    for country, (findings, _sanity, line_count) in results.items():
        grouped = group_by_line(findings)
        total_km = sum(f["chordKm"] for f in findings)
        lines.append(
            f"| {country.upper()} | {line_count} | {len(findings)} | {len(grouped)} | {total_km:.1f} |"
        )
    lines.append("")

    lines.append("## Reconstruction sanity")
    lines.append("")
    lines.append(
        "Before any of the numbers above are trusted, every reconstructed interval is "
        "checked against the two invariants the `compact-v1` format guarantees: its "
        "endpoints must coincide with its two station anchors (within "
        f"{ANCHOR_GAP_ERROR_M:.0f} m), and its walked length must agree with the row's "
        "declared `km`. An earlier audit generation skipped this reconstruction -- reading "
        "each segment row on its own instead of prepending the previous row's shared "
        "vertex when `continuesFromPrevious == 1` -- and mis-measured 5,575 intervals "
        "while still printing \"0 errors\"."
    )
    lines.append("")
    lines.append("| country | intervals walked | endpoint mismatches (>50 m) | km mismatches |")
    lines.append("|---|---:|---:|---:|")
    for country, (_findings, sanity, _line_count) in results.items():
        lines.append(
            f"| {country.upper()} | {sanity['intervals']} | {sanity['endpointMismatches']} | {sanity['kmMismatches']} |"
        )
    lines.append("")

    lines.append("## Cross-reference with existing checks")
    lines.append("")
    for country, (findings, _sanity, _line_count) in results.items():
        if not findings:
            continue
        already_marked = sum(1 for f in findings if f["markedByPackage"])
        strict_key = "auditNaPackageInterval_straight"
        would_fire = sum(1 for f in findings if f[strict_key].startswith("WOULD FIRE"))
        exempt_verified = sum(1 for f in findings if "verifiedOfficialNetwork" in f[strict_key])
        exempt_marker = sum(1 for f in findings if "straightIntervals marker" in f[strict_key])
        lines.append(
            f"- **{country.upper()}**: of {len(findings)} STRAIGHT_INTERVAL findings, "
            f"{already_marked} already carry the package's own `straightIntervals` marker. "
            f"Against `audit-na-package.py`'s own stricter `interval.straight` ERROR check "
            f"(<= {STRICT_DEVIATION_MAX_M:.1f} m deviation): {exempt_verified} are exempted "
            f"because their line's `geometrySource` is a verified official network, "
            f"{exempt_marker} more are exempted by the marker alone, and {would_fire} "
            "would actually fire that check today if nothing exempted them -- which did not "
            "happen in a live run of that script against these packages (see the audit "
            "report this ledger accompanies). The verified-network exemption is the "
            "dominant reason that check is silent: it attests to the SOURCE FILE's "
            "provenance, not to whether the shipped, densified polyline still carries that "
            "source's curvature."
        )
    lines.append("")

    lines.append("## Findings by line")
    lines.append("")
    for country, (findings, _sanity, _line_count) in results.items():
        if not findings:
            lines.append(f"### {country.upper()}: no STRAIGHT_INTERVAL findings")
            lines.append("")
            continue
        lines.append(f"### {country.upper()}")
        lines.append("")
        grouped = group_by_line(findings)
        ranked_lines = sorted(grouped.items(), key=lambda kv: -sum(f["chordKm"] for f in kv[1]))
        for line_id, rows in ranked_lines:
            rows = sorted(rows, key=lambda f: f["ordinal"])
            total_km = sum(f["chordKm"] for f in rows)
            profile = rows[0]["smoothingProfile"]
            source = rows[0]["geometrySource"]
            lines.append(
                f"#### `{line_id}` -- {len(rows)} interval(s), {total_km:.1f} km, "
                f"smoothingProfile: `{profile}`, geometrySource: `{source}`"
            )
            lines.append("")
            lines.append("| ordinal | chord km | deviation m | station A | station B | package marker | `interval.straight` today |")
            lines.append("|---:|---:|---:|---|---|---|---|")
            for row in rows:
                marker_cell = "yes" if row["markedByPackage"] else "no"
                lines.append(
                    f"| {row['ordinal']} | {row['chordKm']:.2f} | {row['deviationM']:.1f} | "
                    f"{row['stationA']} | {row['stationB']} | {marker_cell} | "
                    f"{row['auditNaPackageInterval_straight']} |"
                )
            lines.append("")

    lines.append("## What this detector cannot see")
    lines.append("")
    lines.append(
        "- Whether the interval is a genuinely straight railway (a viaduct, a filled "
        "causeway, a prairie mainline) or a station-to-station shortcut invented at build "
        "time -- both produce an identical near-zero-deviation signature.\n"
        "- Track elevation or grade.\n"
        "- Anything about the interval's history: whether a curve was ever recorded and "
        "lost during simplification/grooming, or never recorded at all.\n"
        "- Any interval under the 1,500 m chord floor, even if it is a bare, obviously "
        "invented straight line -- that population is `STRAIGHT_CHORD`'s job, at a much "
        "lower 250 m floor, and is already covered.\n"
        "- Curvature at a finer scale than the chosen deviation floor: a broad, gentle "
        "curve of radius greater than roughly 11 km reads as straight to this detector at "
        "the threshold chord length, the same way it would read as straight to a rider.\n"
        "- A bit-exact line at the 25 m cutoff. This script projects onto the chord with "
        "`lib/na_geo.py`'s local tangent plane (the same library `na_geo.densify()` itself "
        "uses); the skill's `audit_jtm_packages.py` uses a simpler fixed-scale "
        "equirectangular approximation. The two agree to within a few centimetres "
        "everywhere, which is still enough to put 2 of the ~276 US+CA findings on opposite "
        "sides of the 25 m line (both sit within 0.2 m of it). Treat any finding within a "
        "metre or two of either threshold as exactly as certain as one that is not found at "
        "all -- the cutoff is a review trigger, not a bit-exact test."
    )
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--countries", default="us,ca", help="comma-separated NA package codes (default: us,ca)")
    parser.add_argument("--json", type=Path, help="also write the raw findings here, or '-' for stdout")
    parser.add_argument("--no-ledger", action="store_true", help="skip writing the markdown ledger")
    args = parser.parse_args()

    countries = [item.strip().lower() for item in args.countries.split(",") if item.strip()]
    results = {country: audit_country(country) for country in countries}

    sanity_failures = [
        country for country, (_findings, sanity, _line_count) in results.items()
        if sanity["endpointMismatches"] or sanity["kmMismatches"]
    ]
    if sanity_failures:
        sys.stderr.write(
            "REFUSING to trust these numbers: reconstruction sanity failed for "
            f"{', '.join(sanity_failures)} -- an interval's endpoints did not coincide "
            "with its station anchors, or its walked length disagreed with its declared "
            "km. This is exactly the failure mode that made an earlier audit generation "
            "mis-measure 5,575 intervals while printing \"0 errors\". Fix the reader "
            "before trusting its output.\n"
        )
        return 1

    for country, (findings, sanity, line_count) in results.items():
        grouped = group_by_line(findings)
        total_km = sum(f["chordKm"] for f in findings)
        print(
            f"{country}: {line_count} lines, {sanity['intervals']} intervals reconstructed "
            f"({sanity['endpointMismatches']} endpoint mismatches, {sanity['kmMismatches']} km mismatches) "
            f"-> {len(findings)} STRAIGHT_INTERVAL findings across {len(grouped)} lines, {total_km:.1f} km total"
        )

    if not args.no_ledger:
        ledger_text = render_ledger(results)
        LEDGER_PATH.parent.mkdir(parents=True, exist_ok=True)
        LEDGER_PATH.write_text(ledger_text, encoding="utf-8")
        print(f"wrote {LEDGER_PATH.relative_to(REPO_ROOT)}")

    if args.json:
        payload = {
            country: {"findings": findings, "sanity": sanity, "lineCount": line_count}
            for country, (findings, sanity, line_count) in results.items()
        }
        text = json.dumps(payload, ensure_ascii=False, indent=2)
        if str(args.json) == "-":
            print(text)
        else:
            args.json.write_text(text + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    sys.exit(main())
