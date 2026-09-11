#!/usr/bin/env python3
"""Measure display-blocked station intervals against OSM railway geometry.

The package alignment gate withholds a station interval whose geometry
deviates from an independent reference (usually the operator's own GTFS
shape or a NARN reconstruction) by more than the profile limit for its
kind. This script re-measures a withheld interval a second way: vertex by
vertex, against the nearest active OpenStreetMap railway way of the same
line type, pulled from Overpass tiles staged on disk as gzipped JSON
(`osm-geom/*.json.gz`, the raw `{"elements": [...]}` Overpass response
shape). It writes rows in the schema `make-display-releases.py` expects, so
its output can be reviewed and then fed straight into that script — or, as
is more common for a small batch, used as the evidence backing a hand edit
of `display-releases.json`.

    python3 app/scripts/railway/measure-display-blocked-intervals.py \\
        --package app/public/rail/us-2025.json \\
        --package app/public/rail/ca-2025.json \\
        --osm-dir /path/to/osm-geom \\
        --out results.json

With no `--only`, it measures every (lineId, interval) currently sitting in
`display-releases.json`'s `notMeasured` and `withheldAfterMeasurement`
tables, restricted to whichever regions were passed via `--package`. Pass
`--only lineId:interval` (repeatable) to measure a specific subset instead.

NARN as the reference instead of OSM
-------------------------------------
Pass `--narn-dir <dir>` instead of `--osm-dir` to measure against the FRA/BTS
North American Rail Network instead of OpenStreetMap — the reference to use
for an interval OSM has no tile coverage for. `<dir>` holds the NARN staged
as gzipped pages, `page-*.json.gz`, each a bare JSON **list** of up to 1000
records `{"p": <properties>, "c": <coords>}` — NOT a GeoJSON
FeatureCollection. `c` is normally a flat coordinate list (`[[lon, lat],
...]`), the shape every page in this project's staged NARN actually uses,
but is read as a list of coordinate lists too (defensively — a bare `c`
LineString and a `c` holding several sub-lines both become one or more
reference ways). `p` carries the FRA's own attributes for that arc,
including `NET`, a one-letter running-track classification: `M` (main) is
the overwhelming majority; `S` (siding), `I` (industrial), `A` (abandoned),
`X` (excepted) and `Y` (yard) together are under 8% of arcs in this
project's staged pages. `load_narn_ways` keeps only `NET == "M"`, which is
this reference's equivalent of the OSM loader's `EXCLUDE_SERVICE` filter —
without it, a nearby yard lead or an abandoned branch could make a bad
interval look close to *something* and pass the same way a parallel line
would in the OSM case (see trap 2 in `load_osm_ways`'s docstring, above).
Exactly one of `--osm-dir` / `--narn-dir` is required. Every emitted row
carries a `reference` field (`"osm"` or `"narn"`) naming which one produced
it; the metric fields themselves (`medianM`, `p95M`, `maxM`, `maxAt`,
`wayCount`, `overLimitPct`, `shiftedControlMedianM`) are already reference-
neutral in this script's own output — the `osm`-prefixed names only appear
downstream, in `display-releases.json`'s schema as written by
`make-display-releases.py`, and a NARN-sourced row must not be written
there under those names without the `reference` field alongside it saying
where the numbers actually came from.

Compact-v1 interval reconstruction
-----------------------------------
A line's `segments` array is `[[km, continuesFromPrevious, coords], ...]`.
`coords` is the interval's OWN vertices — it does NOT repeat the interval's
start point when that point is shared with the previous interval's end. The
package uses `continuesFromPrevious == 1` to say "my first vertex is the
previous segment's last vertex, splice it back on for anyone walking the
line as a continuous polyline." Any consumer that reconstructs an interval's
geometry — this script, the display-lane builder, the iOS network builder —
must apply that rule before measuring or drawing: for interval `idx` with
`continuesFromPrevious == 1` and `idx > 0`, prepend the last coordinate of
`segments[idx - 1][2]` to `segments[idx][2]`. Skip the splice and the
interval starts one vertex short and the first edge silently vanishes from
both the walked length and the distance sample.

Two measurement traps this script deliberately avoids
-------------------------------------------------------
1. Nearest-vertex distance is not distance-to-track. It is tempting to
   compute, for each package vertex, the distance to the nearest OSM
   *vertex* and stop there. OSM way vertices are unevenly spaced — long
   straight tangents are represented by a handful of points kilometres
   apart — so nearest-vertex distance overstates the true deviation by an
   arbitrary amount that depends only on how OSM happened to digitise that
   stretch, not on how well the package geometry agrees with the track.
   This script measures point-to-*segment* distance against every OSM way
   segment in range (see `point_seg_dist`), which is what "distance from
   the track" actually means.
2. Selecting OSM source vertices by proximity to the interval, without
   also filtering by which route they belong to, pulls in other parts of
   the SAME route (a nearby siding, the opposite direction track a few
   metres over, or — worse — a different interval of the same line curving
   back within pickup range). This script filters OSM ways to running
   track only (`railway` in {rail, light_rail, subway, narrow_gauge,
   monorail, tram, funicular}, `service` not in {yard, siding, spur,
   crossover, industrial}) but does NOT otherwise know which OSM way is
   "the" track for a given line — a way within the interval's padded bbox
   is treated as candidate track regardless of route relation membership.
   That is generally safe for a single-track branch or an isolated
   interval, and it is why every measured row here also runs a shifted
   control (below): if the shifted line still measures suspiciously close
   to *something*, the candidate set is probably too generous (e.g. it has
   swallowed a parallel line the package vertex was never near) and the
   verdict should not be trusted without a closer look.

Shifted control
----------------
For every interval actually measured (wayCount >= 3), the interval's own
polyline is shifted 150 m perpendicular to its own start-to-end bearing and
re-measured against the same candidate way set. A real independent
reference should score much worse against the shifted line than against the
real one; if the shifted median comes back small too, the candidate way set
is too permissive (e.g. it is measuring against a wide swath of parallel
track rather than the one line) and the raw verdict should be distrusted.
The control's median is printed for every interval and carried in the
output row as `shiftedControlMedianM` for the record, but it is NOT itself
part of the A/B/C/D verdict rule below — it is a sanity check a reviewer
reads before trusting the verdict, not an automated gate.

Verdict rule
------------
  D — fewer than 3 OSM ways found within 500 m of the interval's bbox.
      Not measured; there is nothing to measure against.
  A — median <= 10 m AND <= 5% of the interval's vertices are farther than
      the interval's own profile limit from the nearest track.
  C — median <= 10 m AND <= 20% of vertices are farther than the limit.
      (The caller must confirm by inspection that the excess is the
      REFERENCE's coarse digitisation — e.g. a tunnel approximated as a
      straight chord — and not the package's own geometry; this script
      cannot make that call automatically.)
  B — measured, and worse than the C bar. The package disagrees with an
      independently digitised railway by more than the profile allows.

The interval's own profile limit and the package's own worst-vertex
deviation for the WHOLE line (`packageMaxDeviationM`) are read from
`na-2025-line-review.json`'s `geometry-release-blockers` rows, which is the
same table the alignment gate itself used to withhold the interval in the
first place — not re-derived from a kind-to-limit table here, because that
table can and does drift from what actually gated a given line.
"""
import argparse
import glob
import gzip
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from na_osm import load_osm_way_elements  # noqa: E402

APP_DIR = Path(__file__).resolve().parents[2]
RAIL_DIR = APP_DIR / "public" / "rail"

EXCLUDE_SERVICE = {"yard", "siding", "spur", "crossover", "industrial"}
RAIL_TAGS = {"rail", "light_rail", "subway", "narrow_gauge", "monorail", "tram", "funicular"}

# NARN's own running-track filter (see the module docstring's "NARN as the
# reference instead of OSM" section): keep main track only, the same way
# `load_osm_ways` keeps `railway` in RAIL_TAGS and drops EXCLUDE_SERVICE.
NARN_KEEP_NET = {"M"}

MIN_WAYS_FOR_D = 3


# ---------------------------------------------------------------------------
# OSM tile loading
# ---------------------------------------------------------------------------

def load_osm_ways(osm_dir: Path):
    ways = []
    elements, tile_count = load_osm_way_elements(osm_dir)
    for el in elements:
        tags = el.get("tags", {})
        if tags.get("railway") not in RAIL_TAGS:
            continue
        if tags.get("service") in EXCLUDE_SERVICE:
            continue
        geom = el.get("geometry")
        if not geom or len(geom) < 2:
            continue
        coords = [(g["lon"], g["lat"]) for g in geom]
        b = el.get("bounds", {})
        ways.append({
            "id": el.get("id"), "tags": tags, "coords": coords,
            "bbox": (b.get("minlon", min(c[0] for c in coords)),
                     b.get("minlat", min(c[1] for c in coords)),
                     b.get("maxlon", max(c[0] for c in coords)),
                     b.get("maxlat", max(c[1] for c in coords))),
        })
    return ways, tile_count


def _narn_line_to_ways(record_id, coords):
    """One NARN record's `c` becomes one or more ways.

    `c` is normally a flat coordinate list (`[[lon, lat], ...]`) — every
    page in this project's staged NARN uses that shape exclusively. It is
    read defensively as a list of coordinate lists too, since nothing in
    the source guarantees the flat shape forever: if the first element's
    first element is itself a list/tuple rather than a number, `c` is
    treated as several sub-lines sharing the same FRAARCID, and each
    becomes its own way (suffixed `#0`, `#1`, ... so way ids stay unique).
    """
    if not coords:
        return []
    first = coords[0]
    is_multi = bool(first) and not isinstance(first[0], (int, float))
    lines = coords if is_multi else [coords]
    ways = []
    for i, line in enumerate(lines):
        pts = [(float(c[0]), float(c[1])) for c in line]
        if len(pts) < 2:
            continue
        way_id = f"{record_id}#{i}" if is_multi else record_id
        lons = [p[0] for p in pts]
        lats = [p[1] for p in pts]
        ways.append({
            "id": way_id, "coords": pts,
            "bbox": (min(lons), min(lats), max(lons), max(lats)),
        })
    return ways


def load_narn_ways(narn_dir: Path, keep_net=NARN_KEEP_NET):
    """Load the FRA/BTS North American Rail Network as reference ways.

    `narn_dir` holds gzipped pages, `page-*.json.gz`, each a bare JSON list
    of up to 1000 `{"p": <properties>, "c": <coords>}` records — NOT a
    GeoJSON FeatureCollection (see the module docstring). Records whose
    `p.NET` is present and not in `keep_net` are dropped as service track
    (siding/industrial/abandoned/excepted/yard); a record with no `NET`
    key at all is kept, since there is nothing to filter on. Returns
    `(ways, page_count)` in the same shape `load_osm_ways` returns, so
    both feed the same `measure_against` / `shifted_control` machinery.
    """
    ways = []
    pages = sorted(glob.glob(str(narn_dir / "page-*.json.gz")))
    for page_path in pages:
        with gzip.open(page_path) as fh:
            records = json.load(fh)
        for record in records:
            props = record.get("p") or {}
            net = props.get("NET")
            if net is not None and net not in keep_net:
                continue
            record_id = props.get("FRAARCID")
            for way in _narn_line_to_ways(record_id, record.get("c")):
                way["tags"] = props
                ways.append(way)
    return ways, len(pages)


# ---------------------------------------------------------------------------
# Package interval reconstruction (compact-v1)
# ---------------------------------------------------------------------------

def load_package(path: Path):
    return json.loads(path.read_text())


def find_line(pkg, line_id):
    for l in pkg["lines"]:
        if l.get("id") == line_id:
            return l
    return None


def interval_polyline(line, idx):
    seg = line["segments"][idx]
    km, cont, coords = seg[0], seg[1], seg[2]
    coords = [tuple(c) for c in coords]
    if cont == 1 and idx > 0:
        prev = line["segments"][idx - 1][2]
        prev_last = tuple(prev[-1])
        coords = [prev_last] + coords
    return coords, km


def interval_stations(line, idx):
    try:
        return [line["stations"][idx][1], line["stations"][idx + 1][1]]
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

def bbox_of(coords, pad_m=500):
    lons = [c[0] for c in coords]
    lats = [c[1] for c in coords]
    lat0 = sum(lats) / len(lats)
    dlat = pad_m / 110540.0
    dlon = pad_m / (111320.0 * max(0.1, math.cos(math.radians(lat0))))
    return (min(lons) - dlon, min(lats) - dlat, max(lons) + dlon, max(lats) + dlat)


def bbox_intersect(a, b):
    return not (a[2] < b[0] or b[2] < a[0] or a[3] < b[1] or b[3] < a[1])


def project(lon, lat, lon0, lat0):
    x = (lon - lon0) * 111320.0 * math.cos(math.radians(lat0))
    y = (lat - lat0) * 110540.0
    return x, y


def point_seg_dist(px, py, ax, ay, bx, by):
    # Point-to-segment distance, not point-to-nearest-vertex: see trap (1)
    # in the module docstring.
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    if l2 == 0:
        return math.hypot(px - ax, py - ay)
    t = ((px - ax) * dx + (py - ay) * dy) / l2
    t = max(0.0, min(1.0, t))
    cx, cy = ax + t * dx, ay + t * dy
    return math.hypot(px - cx, py - cy)


def nearest_dist(lon, lat, way_segs_local, lon0, lat0):
    px, py = project(lon, lat, lon0, lat0)
    best = float("inf")
    for (ax, ay, bx, by) in way_segs_local:
        d = point_seg_dist(px, py, ax, ay, bx, by)
        if d < best:
            best = d
    return best


def percentile(sorted_vals, p):
    if not sorted_vals:
        return None
    k = (len(sorted_vals) - 1) * p
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return sorted_vals[int(k)]
    return sorted_vals[f] + (sorted_vals[c] - sorted_vals[f]) * (k - f)


def measure_against(coords, ways, limit_m):
    ibbox = bbox_of(coords, pad_m=500)
    relevant = [w for w in ways if bbox_intersect(ibbox, w["bbox"])]
    if len(relevant) < MIN_WAYS_FOR_D:
        return None, relevant
    lats = [c[1] for c in coords]
    lon0 = sum(c[0] for c in coords) / len(coords)
    lat0 = sum(lats) / len(lats)
    way_segs_local = []
    for w in relevant:
        cs = w["coords"]
        for i in range(len(cs) - 1):
            ax, ay = project(cs[i][0], cs[i][1], lon0, lat0)
            bx, by = project(cs[i + 1][0], cs[i + 1][1], lon0, lat0)
            way_segs_local.append((ax, ay, bx, by))
    dists = []
    worst = (None, -1.0)
    over = 0
    for c in coords:
        d = nearest_dist(c[0], c[1], way_segs_local, lon0, lat0)
        dists.append(d)
        if d > worst[1]:
            worst = (list(c), d)
        if limit_m is not None and d > limit_m:
            over += 1
    dists_sorted = sorted(dists)
    result = {
        "n": len(dists),
        "median": percentile(dists_sorted, 0.5),
        "p95": percentile(dists_sorted, 0.95),
        "max": worst[1],
        "maxAt": worst[0],
        "wayCount": len(relevant),
        "overLimitCount": over,
        "overLimitPct": (100.0 * over / len(dists)) if dists else None,
    }
    return result, relevant


def shifted_control(coords, ways, limit_m, shift_m=150.0):
    # Perpendicular shift of the whole polyline by shift_m, then re-measure
    # against the same candidate way set. See "Shifted control" above.
    if len(coords) < 2:
        return None
    lats = [c[1] for c in coords]
    lat0 = sum(lats) / len(lats)
    lon_first = coords[0][0]
    x0, y0 = project(*coords[0], lon_first, lat0)
    x1, y1 = project(*coords[-1], lon_first, lat0)
    dx, dy = x1 - x0, y1 - y0
    norm = math.hypot(dx, dy)
    if norm == 0:
        dx, dy = 1.0, 0.0
        norm = 1.0
    ux, uy = -dy / norm, dx / norm
    shifted = []
    for lon, lat in coords:
        x, y = project(lon, lat, lon_first, lat0)
        x2, y2 = x + ux * shift_m, y + uy * shift_m
        lat2 = lat0 + y2 / 110540.0
        lon2 = lon_first + x2 / (111320.0 * math.cos(math.radians(lat0)))
        shifted.append((lon2, lat2))
    result, _ = measure_against(shifted, ways, limit_m)
    return result


# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------

def compute_verdict(result):
    if result is None:
        return "D"
    median = result["median"]
    over_pct = result["overLimitPct"]
    if median is None or over_pct is None:
        return "D"
    if median <= 10.0 and over_pct <= 5.0:
        return "A"
    if median <= 10.0 and over_pct <= 20.0:
        return "C"
    return "B"


# ---------------------------------------------------------------------------
# Line-review lookup (limitM / packageMaxDeviationM, the gate's own numbers)
# ---------------------------------------------------------------------------

def load_line_review():
    path = RAIL_DIR / "na-2025-line-review.json"
    by_line = {}
    if not path.exists():
        return by_line
    data = json.loads(path.read_text())
    for row in data.get("lines", []):
        if row.get("sourceFeed") != "geometry-release-blockers":
            continue
        for issue in row.get("issues", []):
            if "limitMeters" not in issue:
                continue
            by_line.setdefault(row["lineId"], {
                "limitM": issue.get("limitMeters"),
                "packageMaxDeviationM": issue.get("maxDeviationMeters"),
                "intervals": set(issue.get("intervals") or []),
            })
    return by_line


# ---------------------------------------------------------------------------
# Default target set: whatever display-releases.json still has unreleased
# ---------------------------------------------------------------------------

def default_targets(regions):
    path = RAIL_DIR / "display-releases.json"
    if not path.exists():
        return []
    data = json.loads(path.read_text())
    targets = []
    for entry in data.get("notMeasured", []):
        region, line_id, idx = entry[0], entry[1], entry[2]
        if region in regions:
            targets.append((region, line_id, int(idx)))
    for row in data.get("withheldAfterMeasurement", []):
        if row.get("region") in regions:
            targets.append((row["region"], row["lineId"], int(row["interval"])))
    return targets


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def region_of(package_path: Path):
    return package_path.stem.split("-")[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--package", action="append", required=True,
                     help="path to a compact-v1 package, e.g. app/public/rail/us-2025.json "
                          "(repeatable)")
    ap.add_argument("--osm-dir", default=None,
                     help="directory of gzipped Overpass tiles (*.json.gz)")
    ap.add_argument("--narn-dir", default=None,
                     help="directory of gzipped NARN pages (page-*.json.gz) — "
                          "an alternative reference for intervals OSM has no "
                          "tile coverage for; see the module docstring")
    ap.add_argument("--out", required=True, help="path to write results.json")
    ap.add_argument("--only", action="append", default=[],
                     help="lineId:interval to measure instead of the current "
                          "notMeasured/withheldAfterMeasurement set (repeatable)")
    args = ap.parse_args()

    if bool(args.osm_dir) == bool(args.narn_dir):
        ap.error("pass exactly one of --osm-dir or --narn-dir")

    package_paths = [Path(p) for p in args.package]
    packages = {}
    for p in package_paths:
        packages[region_of(p)] = (p, load_package(p))

    if args.osm_dir:
        reference = "osm"
        source_dir = Path(args.osm_dir)
        ways, source_count = load_osm_ways(source_dir)
        print(f"Loaded {len(ways)} OSM railway ways from {source_count} tiles "
              f"in {source_dir}", file=sys.stderr)
    else:
        reference = "narn"
        source_dir = Path(args.narn_dir)
        ways, source_count = load_narn_ways(source_dir)
        print(f"Loaded {len(ways)} NARN railway ways from {source_count} pages "
              f"in {source_dir}", file=sys.stderr)

    line_review = load_line_review()

    if args.only:
        targets = []
        for spec in args.only:
            line_id, idx = spec.rsplit(":", 1)
            idx = int(idx)
            matched = False
            for region, (_, pkg) in packages.items():
                if find_line(pkg, line_id) is not None:
                    targets.append((region, line_id, idx))
                    matched = True
            if not matched:
                print(f"warning: --only {spec} not found in any --package", file=sys.stderr)
    else:
        targets = default_targets(set(packages.keys()))

    rows = []
    for region, line_id, idx in targets:
        if region not in packages:
            continue
        pkg_path, pkg = packages[region]
        package_name = pkg_path.stem  # e.g. "us-2025"
        line = find_line(pkg, line_id)
        if line is None:
            rows.append({
                "package": package_name, "lineId": line_id, "index": idx,
                "verdict": "D", "reference": reference,
                "note": "line not found in package",
            })
            continue
        try:
            coords, km = interval_polyline(line, idx)
        except (IndexError, KeyError):
            rows.append({
                "package": package_name, "lineId": line_id, "index": idx,
                "verdict": "D", "reference": reference,
                "note": "interval index out of range",
            })
            continue

        review = line_review.get(line_id)
        limit_m = review["limitM"] if review else None
        package_max_dev_m = review["packageMaxDeviationM"] if review else None

        result, relevant = measure_against(coords, ways, limit_m)
        stations = interval_stations(line, idx)

        row = {
            "package": package_name,
            "lineId": line_id,
            "index": idx,
            "reference": reference,
            "stations": stations,
            "kmWalked": round(km, 2),
            "vertices": len(coords),
            "limitM": limit_m,
            "packageMaxDeviationM": package_max_dev_m,
        }

        if result is None:
            verdict = "D"
            row.update({
                "verdict": verdict,
                "medianM": None, "p95M": None, "maxM": None, "maxAt": None,
                "wayCount": len(relevant),
                "shiftedControlMedianM": None,
                "note": f"fewer than {MIN_WAYS_FOR_D} {reference.upper()} ways within "
                        f"500 m of the interval bbox (found {len(relevant)}) — "
                        f"no {reference.upper()} coverage",
            })
            print(f"[{package_name}] {line_id}[{idx}] D — no {reference.upper()} "
                  f"coverage ({len(relevant)} ways)", file=sys.stderr)
        else:
            verdict = compute_verdict(result)
            shifted = shifted_control(coords, ways, limit_m)
            row.update({
                "verdict": verdict,
                "medianM": round(result["median"], 1),
                "p95M": round(result["p95"], 1),
                "maxM": round(result["max"], 1),
                "maxAt": result["maxAt"],
                "wayCount": result["wayCount"],
                "overLimitPct": round(result["overLimitPct"], 1) if result["overLimitPct"] is not None else None,
                "shiftedControlMedianM": round(shifted["median"], 1) if shifted and shifted["median"] is not None else None,
                "note": "",
            })
            shifted_str = row["shiftedControlMedianM"]
            print(f"[{package_name}] {line_id}[{idx}] {verdict} — "
                  f"median {row['medianM']}m p95 {row['p95M']}m max {row['maxM']}m "
                  f"@ {row['maxAt']} (limit {limit_m}m, {row['overLimitPct']}% over, "
                  f"{result['wayCount']} ways) shifted-control median {shifted_str}m",
                  file=sys.stderr)

        rows.append(row)

    out_path = Path(args.out)
    out_path.write_text(json.dumps(rows, indent=2) + "\n")
    print(f"Wrote {len(rows)} rows to {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
