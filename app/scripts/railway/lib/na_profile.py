"""How hard one line is groomed, and how finely it is kept.

The single policy file behind the request this package family was built for:
*long lines and short lines need not be drawn to the same precision, nor
smoothed with the same strength.* Everything that decides "how many metres of
error may this line carry" is here, with the reasoning, rather than scattered
through the builder as constants.

## Why a line's own scale has to decide

``rail-network.js`` already argues the case for the draw-time pass, and the
argument is the same at build time: on a 3,900 km transcontinental route a
15 m wobble is invisible at every zoom the line is drawn at, while on a
streetcar that turns a city block in forty metres the same 15 m is the corner
itself. One tolerance for both either leaves the trunk carrying a million
vertices nobody can see, or files the streetcar's corners off.

Two facts about a line decide its band:

* **median station spacing** — what kind of railway it is. A tram stops every
  300 m; an intercity route every 60 km. This is the same signal
  ``Grooming.microKinkLimits`` uses at draw time, so the build and the
  renderer agree about what they are looking at.
* **total length** — how far it is drawn zoomed out. A 3,000 km route is
  almost never on screen at a zoom where 20 m is a pixel, so it is allowed a
  coarser record than a 40 km commuter line of the same station spacing.

The length term is a multiplier rather than a second table because it is a
*correction* to the kind of railway, not a different kind: a long streetcar
network is still a streetcar network.

## What the numbers mean

``tolerance_m``      simplifier budget: no vertex the simplifier drops may lie
                     further than this from the line that replaces it.
``spike_*``          the sawtooth relaxation limits, in the shape
                     ``rail-network.js`` states them.
``corner_offset_m``  how far back along each edge a corner fillet is cut.
``min_radius_m`` /   the floor an ordinary corner's radius is held to, measured
``radius_window_m``  over an arc-length window rather than between neighbours.
``anchor_m``         how far the radius pass may move a vertex from where the
                     rest of the grooming left it.
``max_edge_m``       the longest chord the output may contain. Not a smoothing
                     control: it stops a two-coordinate straight line being
                     drawn across country where the railway curves.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Profile:
    name: str
    max_spacing_m: float
    tolerance_m: float
    spike_edge_m: float
    spike_turn_deg: float
    spike_deviation_m: float
    corner_offset_m: float
    min_radius_m: float
    radius_window_m: float
    anchor_m: float
    max_edge_m: float


#: The bands, in the order the lookup walks them: the first band whose ceiling
#: the line's median station spacing fits under wins, so the order is the rule.
BANDS = (
    # Streetcars, people movers, funiculars, cable cars. Stops every few
    # hundred metres, curve radii in the tens of metres, and always looked at
    # from close in — the one band where sub-metre fidelity is worth its bytes.
    Profile('street', 700, 0.8, 6, 80, 0.6, 12, 15, 30, 3, 120),
    # Rapid transit and light rail on reserved track.
    Profile('metro', 1_800, 1.6, 12, 70, 1.2, 25, 30, 70, 5, 160),
    # Commuter rail and the outer ends of light-rail systems.
    Profile('commuter', 6_000, 4.0, 24, 60, 2.5, 60, 80, 180, 10, 220),
    # Regional intercity: corridor services, most of Amtrak's day trains.
    Profile('regional', 25_000, 9.0, 40, 55, 4.0, 140, 200, 450, 20, 350),
    # Long-distance: the transcontinental routes, and VIA's Canadian.
    Profile('longhaul', float('inf'), 16.0, 60, 55, 6.0, 260, 400, 900, 35, 600),
)

#: Length multipliers applied on top of the band. A line that runs a long way
#: is drawn zoomed further out, so its record may be coarser — but only up to
#: a point: past ~2,000 km the multiplier stops growing, because beyond that
#: the limit on what is visible is the screen, not the tolerance.
LENGTH_STEPS = (
    (200_000, 1.0),
    (600_000, 1.25),
    (1_500_000, 1.6),
    (float('inf'), 2.0),
)


def length_factor(length_m: float) -> float:
    for ceiling, factor in LENGTH_STEPS:
        if length_m <= ceiling:
            return factor
    return LENGTH_STEPS[-1][1]


def band_for(median_spacing_m: float) -> Profile:
    if not (median_spacing_m > 0):
        return BANDS[2]
    for band in BANDS:
        if median_spacing_m <= band.max_spacing_m:
            return band
    return BANDS[-1]


def profile_for(median_spacing_m: float, length_m: float) -> Profile:
    """The grooming policy for one line, band times length correction.

    ``max_edge_m`` is deliberately NOT scaled: the chord cap answers a question
    about the projection ("how long may a straight line be before it stops
    being where the railway is"), and that question has the same answer on a
    tram and on a transcontinental route.
    """
    band = band_for(median_spacing_m)
    k = length_factor(length_m)
    if k == 1.0:
        return band
    return Profile(
        name=band.name,
        max_spacing_m=band.max_spacing_m,
        tolerance_m=band.tolerance_m * k,
        spike_edge_m=band.spike_edge_m * k,
        spike_turn_deg=band.spike_turn_deg,
        spike_deviation_m=band.spike_deviation_m * k,
        corner_offset_m=band.corner_offset_m * k,
        min_radius_m=band.min_radius_m * k,
        radius_window_m=band.radius_window_m * k,
        anchor_m=band.anchor_m * k,
        max_edge_m=band.max_edge_m,
    )


def median_spacing_m(interval_lengths_m):
    """A line's characteristic scale.

    The median of its station-to-station lengths, taken exactly as
    ``RailCore.Grooming.medianSpacingMeters`` takes it so that the build and
    the renderer classify a line the same way: non-finite and non-positive
    lengths are dropped before the median rather than sorted to the front, and
    the median of an even count is the UPPER of the two middles.
    """
    values = sorted(v for v in interval_lengths_m if v and v > 0)
    if not values:
        return 0.0
    return values[len(values) // 2]


#: The deviation a built line may carry from the reference geometry that is
#: allowed to say where the railway is, before the build refuses to ship it.
#: Scaled by band for the same reason the tolerances are: a 20 m disagreement
#: about a streetcar's alignment is a different street, and about a prairie
#: main line is the other track of the same double-track railway.
CROSSCHECK_TOLERANCE_M = {
    'street': 25.0,
    'metro': 40.0,
    'commuter': 90.0,
    'regional': 200.0,
    'longhaul': 400.0,
}
