#!/usr/bin/env python3
"""Generate importable large journey stores from the app's actual itineraries.

Examples:
  python3 ios/tools/generate-route-stress-data.py --count 10000 --output-dir /tmp/jtm-stress
  python3 ios/tools/generate-route-stress-data.py --count 50000 --regions jp tw --scenario dense --output-dir /tmp/jtm-dense
  python3 ios/tools/generate-route-stress-data.py --id-mode colliding --output-dir /tmp/jtm-collisions

Journeys are synthetic repetitions. Station identities, route constraints,
original travel dates, and clocks remain those of the source itineraries. The
generator does not invent historical routes or claim these are new timetables.
"""

import argparse
import copy
import json
import sys
from collections import Counter
from pathlib import Path

REGIONS = ("jp", "tw", "hk", "kr", "mo", "ca", "us")
APP_FILE_LIMIT = 64 * 1024 * 1024


def generate(count, regions, scenario, id_mode):
    repository = Path(__file__).resolve().parents[2]
    seeds = {}
    for region in regions:
        suffix = "" if region == "jp" else f"-{region}"
        source = repository / "app" / "data" / f"train-store{suffix}.json"
        archive = json.loads(source.read_text(encoding="utf-8"))
        rows = archive["trains"]
        if not rows:
            raise ValueError(f"{source} has no journeys")
        if scenario == "dense":
            # Pick an existing busy day per country, preserving route validity.
            busiest = Counter(row.get("date", "undated") for row in rows).most_common(1)[0][0]
            rows = [row for row in rows if row.get("date", "undated") == busiest]
        seeds[region] = rows

    trains = []
    sources = Counter()
    for index in range(count):
        region = regions[index % len(regions)]
        candidates = seeds[region]
        source = candidates[(index // len(regions)) % len(candidates)]
        train = copy.deepcopy(source)
        train["id"] = f"stress_{region}_{index:08d}" if id_mode == "unique" else f"stress_{region}_collision"
        train["region"] = region
        trains.append(train)
        sources[f"{region}:{source['id']}"] += 1
    return trains, sources


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--count", type=int, default=10000, help="Total journeys across selected regions (default: 10000)")
    parser.add_argument("--regions", nargs="+", choices=REGIONS, default=list(REGIONS))
    parser.add_argument("--scenario", choices=("varied", "dense"), default="varied", help="All real source routes/dates, or an existing busy date per region")
    parser.add_argument("--id-mode", choices=("unique", "colliding"), default="unique", help="Colliding IDs deliberately exercise importer renaming")
    parser.add_argument("--part-size", type=int, default=0, help="Also write stores of at most this many journeys for sequential append imports")
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    regions = list(dict.fromkeys(args.regions))
    if args.count < len(regions):
        parser.error("--count must include at least one journey per selected region")
    if args.part_size < 0:
        parser.error("--part-size must be zero or a positive journey count")

    trains, sources = generate(args.count, regions, args.scenario, args.id_mode)
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    mixed_path = output / "stress-all.json"
    write_json(mixed_path, {"schema_version": "1.3", "trains": trains})
    files = {"all": str(mixed_path)}
    for region in regions:
        path = output / f"stress-{region}.json"
        write_json(path, {"schema_version": "1.3", "trains": [train for train in trains if train["region"] == region]})
        files[region] = str(path)
    if args.part_size:
        for part, start in enumerate(range(0, len(trains), args.part_size)):
            path = output / f"stress-part-{part:04d}.json"
            write_json(path, {"schema_version": "1.3", "trains": trains[start:start + args.part_size]})
            files[f"part-{part:04d}"] = str(path)

    report = {
        "synthetic_repetitions": True,
        "route_ground_truth": "Copied source itineraries; no additional route solve or timetable verification is implied",
        "count": len(trains),
        "scenario": args.scenario,
        "id_mode": args.id_mode,
        "regions": dict(Counter(train["region"] for train in trains)),
        "dates": dict(sorted(Counter(train.get("date", "undated") for train in trains).items())),
        "source_itineraries": dict(sorted(sources.items())),
        "stop_count": sum(len(train["stops"]) for train in trains),
        "route_section_count": sum(len(train.get("route_sections") or []) for train in trains),
        "files": files,
        "bytes": {key: Path(value).stat().st_size for key, value in files.items()},
    }
    write_json(output / "stress-manifest.json", report)
    oversized = [key for key, size in report["bytes"].items() if size > APP_FILE_LIMIT]
    if oversized:
        print(f"Files above the app's 64 MiB import limit: {', '.join(oversized)}. Use --part-size to create smaller stores for sequential append imports.", file=sys.stderr)
    print(json.dumps({key: report[key] for key in ("count", "regions", "stop_count", "route_section_count", "bytes")}, indent=2))
    print(f"Import {mixed_path} in the app; individual region stores are alongside it.")


if __name__ == "__main__":
    main()
