#!/usr/bin/env python3
"""Print the exact extent of a shipped package, in the form the app stores it.

    python3 scripts/railway/print-network-bounds.py public/rail/us-2025.json

`Region.networkBounds` in `ios/RailMap/RegionCatalog.swift` is a written-down
constant rather than a measurement, and its own documentation says why: the
packages decode at wildly different speeds, so a camera that waits for lines
before framing a country is a camera that moves seconds after launch, over
whatever the reader has pinched to by then.

Written down still has to be RIGHT, so this is what writes it. It measures
every coordinate of every segment — not just the stations, which stop short of
the ends of the network — and prints the Swift tuple to paste in.
"""
from __future__ import annotations

import json
import sys


def bounds(path):
    with open(path) as fh:
        package = json.load(fh)
    south, west, north, east = 90.0, 180.0, -90.0, -180.0
    for line in package['lines']:
        for segment in line['segments']:
            for lon, lat in segment[2]:
                south = min(south, lat)
                north = max(north, lat)
                west = min(west, lon)
                east = max(east, lon)
    return package['country'].lower(), south, west, north, east


def main():
    for path in sys.argv[1:]:
        code, south, west, north, east = bounds(path)
        print(f'        case .{code}: ({south:.6f}, {west:.6f}, '
              f'{north:.6f}, {east:.6f})')


if __name__ == '__main__':
    main()
