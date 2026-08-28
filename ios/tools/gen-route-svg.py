#!/usr/bin/env python3
"""Generate the route layer of the app icon.

The icon is an Icon Composer document, `ios/RailMap/AppIcon.icon`. Its other
layer, the dot lattice, is plain circles anybody can edit by hand. This one is
not: it is the outline of a three-segment polyline with filleted bends, plus a
station ring at either end, which is a few hundred points of offset geometry.
This script is where that geometry is described, and `Assets/Route.svg` is its
committed output.

    python3 ios/tools/gen-route-svg.py            # write the SVG
    python3 ios/tools/gen-route-svg.py --check    # fail if it is stale

Why an outline and not a stroked path. A `stroke-width` polyline is the obvious
way to draw this, and it is what the design deck used, but a stroked corner is
only round on the outside - the inside is a sharp miter, and the icon's glass
pass renders that miter as a spike with a bright specular sliver down it. So
the bends are filleted on the centreline instead, which makes both sides of
every corner an arc.

Why one path and not several shapes. The station centres are holes, not fill:
what shows through them is the icon's own background, so they track the
gradient for free and cannot drift from it the way a hardcoded colour would.
A hole needs winding, and winding is per-path, so the whole layer - route,
station discs, and the two holes wound the other way - is emitted as a single
`d`. The route is trimmed short of each station centre for the same reason: a
line running into the hole would wind it back to filled.

The stations are discs wider than the line, so each end reads as a clean T
instead of tapering into the ring.

Two lattice dots in `Assets/Grid.svg` were removed by hand because they sat
inside these holes and would show through them. If you move the stations, check
that again - nothing here enforces it.

Nothing in the build runs this; the SVG it writes is committed. `verify.sh`
checks that every layer named by `icon.json` is on disk, not that it is fresh,
so run `--check` by hand if you have touched the numbers below.
"""

import math
import sys
from pathlib import Path

# The route, in the icon's 1024×1024 space. Two stations, two bends.
POINTS = [(247.0, 781.0), (382.0, 547.0), (643.0, 477.0), (778.0, 243.0)]
HALF_WIDTH = 48.0      # the line is 96 wide, as the design deck drew it
FILLET = 100.0         # centreline bend radius; must exceed HALF_WIDTH
STATION_RADIUS = 95.0  # outer edge of the station ring
STATION_HOLE = 49.0    # inner edge, leaving the 46-wide ring the deck drew
TRIM = 60.0            # where the line stops short of a station centre
ARC_STEPS = 24         # segments per fillet; 24 is under a tenth of a unit off

OUTPUT = Path(__file__).resolve().parents[1] / "RailMap/AppIcon.icon/Assets/Route.svg"

# TRIM has to clear the hole, or the line winds the hole back to filled, and it
# has to stay inside the disc, or the flat end of the line pokes out of it.
assert STATION_HOLE < TRIM, "the line would reach into the station hole"
assert math.hypot(TRIM, HALF_WIDTH) < STATION_RADIUS, "the line end escapes the disc"


def add(a, b): return (a[0] + b[0], a[1] + b[1])
def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def mul(a, s): return (a[0] * s, a[1] * s)
def perp(u): return (-u[1], u[0])


def unit(a):
    length = math.hypot(*a)
    return (a[0] / length, a[1] / length)


def centreline():
    """The route, pulled back from both station centres by TRIM."""
    points = list(POINTS)
    points[0] = add(points[0], mul(unit(sub(points[1], points[0])), TRIM))
    points[-1] = add(points[-1], mul(unit(sub(points[-2], points[-1])), TRIM))
    return points


def fillets(points):
    """Tangent points and arc centre for each interior vertex."""
    for i in range(1, len(points) - 1):
        before = unit(sub(points[i], points[i - 1]))
        after = unit(sub(points[i + 1], points[i]))
        cross = before[0] * after[1] - before[1] * after[0]
        dot = max(-1.0, min(1.0, before[0] * after[0] + before[1] * after[1]))
        tangent = FILLET * math.tan(math.acos(dot) / 2)
        start = sub(points[i], mul(before, tangent))
        # The centre sits on the inside of the turn, which is the side `cross`
        # names — and therefore the side whose offset arc is the tighter one.
        turn = 1.0 if cross > 0 else -1.0
        yield dict(before=before, after=after, start=start,
                   end=add(points[i], mul(after, tangent)),
                   centre=add(start, mul(perp(before), FILLET * turn)),
                   turn=turn)


def offset(points, side):
    """One side of the outline, walking the route from first station to last.

    `side` is +1 for the `perp` side of travel and -1 for the other.
    """
    bends = list(fillets(points))
    walk = [add(points[0], mul(perp(bends[0]["before"]), HALF_WIDTH * side))]
    for bend in bends:
        walk.append(add(bend["start"], mul(perp(bend["before"]), HALF_WIDTH * side)))
        radius = FILLET - HALF_WIDTH * side * bend["turn"]
        centre = bend["centre"]
        finish = add(bend["end"], mul(perp(bend["after"]), HALF_WIDTH * side))
        first = math.atan2(walk[-1][1] - centre[1], walk[-1][0] - centre[0])
        last = math.atan2(finish[1] - centre[1], finish[0] - centre[0])
        sweep = (last - first + math.pi) % (2 * math.pi) - math.pi
        for step in range(1, ARC_STEPS + 1):
            angle = first + sweep * step / ARC_STEPS
            walk.append((centre[0] + radius * math.cos(angle),
                         centre[1] + radius * math.sin(angle)))
    walk.append(add(points[-1], mul(perp(bends[-1]["after"]), HALF_WIDTH * side)))
    return walk


def clockwise(ring):
    """Shoelace sign. With y down, a positive area is clockwise on screen."""
    return sum(a[0] * b[1] - b[0] * a[1]
               for a, b in zip(ring, ring[1:] + ring[:1])) > 0


def subpath(ring):
    return "M " + " L ".join(f"{x:.2f} {y:.2f}" for x, y in ring) + " Z"


def circle(centre, radius, sweep):
    """A full circle as two arcs. `sweep` 1 is clockwise on screen, and so
    winds the same way as a clockwise ring."""
    cx, cy = centre
    return (f"M {cx - radius:g} {cy:g} "
            f"A {radius:g} {radius:g} 0 1 {sweep} {cx + radius:g} {cy:g} "
            f"A {radius:g} {radius:g} 0 1 {sweep} {cx - radius:g} {cy:g} Z")


def svg():
    points = centreline()
    outline = offset(points, 1) + list(reversed(offset(points, -1)))
    # Everything filled has to wind one way and the holes the other, or the
    # default nonzero rule will not cut them out.
    if not clockwise(outline):
        outline.reverse()
    first, last = POINTS[0], POINTS[-1]
    path = " ".join([
        subpath(outline),
        circle(first, STATION_RADIUS, 1),
        circle(last, STATION_RADIUS, 1),
        circle(first, STATION_HOLE, 0),
        circle(last, STATION_HOLE, 0),
    ])
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <!-- Ridden route: three segments, two bends, two station rings, one path.
       Written by ios/tools/gen-route-svg.py - edit the numbers there, not the
       path here. The bends are filleted on the centreline so both sides of
       every corner are an arc; a stroked polyline leaves a sharp inner miter
       that the icon's glass pass renders as a spike. The station centres are
       holes wound against the rest of the path, so what shows through them is
       the icon's own background. -->
  <path fill="#FFFFFF" d="{path}"/>
</svg>
"""


def main():
    drawn = svg()
    if "--check" in sys.argv[1:]:
        on_disk = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if on_disk != drawn:
            sys.stderr.write(f"gen-route-svg --check: {OUTPUT.name} is stale — "
                             "rerun without --check\n")
            return 1
        print(f"gen-route-svg: {OUTPUT.name} matches its source")
        return 0
    OUTPUT.write_text(drawn, encoding="utf-8")
    print(f"gen-route-svg: wrote {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
