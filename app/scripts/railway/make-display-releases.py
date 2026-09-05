#!/usr/bin/env python3
"""Write the reviewed alignment-release table from an OSM measurement run.

The package alignment gate withholds a station interval whose geometry
deviates from an independent reference by more than the limit for its kind.
That verdict is fail-closed on purpose, and it stays that way: this table
does not lower a limit. It records intervals that were measured AGAIN, vertex
by vertex, against the nearest active OpenStreetMap railway of the line's
own type, and found consistent with it (A: median well inside the limit and
no localised excursion) or found to disagree only where OSM is the coarse
one (C: a tunnel approximation). Each row carries the numbers that justify
it. An interval measured and found wrong (B) or not measured (D) is never
written here.

    python3 app/scripts/railway/make-display-releases.py results.json

The display-lane builder copies the table into `display-lanes.json`, and both
renderers release exactly these intervals for display. Routing, mileage and
the package's own audit are untouched.
"""
import json
import sys
from datetime import date
from pathlib import Path

RAIL = Path(__file__).resolve().parents[2] / "public" / "rail"


def main(results_path: str) -> None:
    rows = json.loads(Path(results_path).read_text())
    releases = []
    withheld = []
    not_measured = []
    for row in rows:
        region = row["package"].split("-")[0]
        if row.get("verdict") == "B":
            withheld.append({
                "region": region, "lineId": row["lineId"], "interval": int(row["index"]),
                "stations": row.get("stations"), "verdict": "B",
                "limitMetres": row.get("limitM"), "osmMedianMetres": row.get("medianM"),
                "osmMaxMetres": row.get("maxM"), "osmMaxAt": row.get("maxAt"),
                "note": row.get("note"),
            })
            continue
        if row.get("verdict") not in ("A", "C"):
            not_measured.append([region, row["lineId"], int(row["index"])])
            continue
        releases.append({
            "region": region,
            "lineId": row["lineId"],
            "interval": int(row["index"]),
            "stations": row.get("stations"),
            "verdict": row["verdict"],
            "limitMetres": row.get("limitM"),
            "packageMaxDeviationMetres": row.get("packageMaxDeviationM"),
            "osmMedianMetres": row.get("medianM"),
            "osmP95Metres": row.get("p95M"),
            "osmMaxMetres": row.get("maxM"),
            "osmMaxAt": row.get("maxAt"),
            "note": row.get("note"),
        })
    releases.sort(key=lambda r: (r["region"], r["lineId"], r["interval"]))
    out = {
        "format": "jtm-display-releases-v1",
        "reviewedAt": date.today().isoformat(),
        "method": (
            "Interval geometry rebuilt with the compact-v1 chain rule and measured "
            "against the nearest active OpenStreetMap railway way of the line's own "
            "type (service tracks excluded) via Overpass; long intervals sampled at "
            "20 points plus every vertex within 150 m of a sample. A = consistent "
            "(median well inside the kind limit, no localised excursion); C = only "
            "OSM's tunnel approximation disagrees. B (package wrong) and D (not "
            "measured) are never released."
        ),
        "releases": releases,
        # Measured and found wrong: kept withheld, with the numbers, so the
        # gate's verdict is confirmed rather than merely repeated.
        "withheldAfterMeasurement": withheld,
        "notMeasured": not_measured,
    }
    (RAIL / "display-releases.json").write_text(
        json.dumps(out, ensure_ascii=False, indent=2) + "\n")
    print(f"{len(releases)} released intervals")


if __name__ == "__main__":
    main(sys.argv[1])
