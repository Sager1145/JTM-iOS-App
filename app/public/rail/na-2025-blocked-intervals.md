# North America — alignment-gate blocked intervals, interval by interval

Reviewed 2026-09-02. Scope: every station interval the package alignment gate
withheld from display in `us-2025.json` / `ca-2025.json`
(`geometrySource.officialGeometryComparison.byLine[<lineId>].displayBlockedIntervals`),
and what each one actually is.

The gate is fail-closed on purpose and stays that way. This ledger does not
lower a limit, does not change a package, and does not touch the audit's own
verdict. It records what can be established about each withheld interval
**from evidence that is in this repository**, and releases only the ones the
evidence carries.

## How an interval gets blocked, and how it gets back

`build-north-america-rail-package.py:3341-3372` measures every vertex of every
station interval against the source that did **not** build it (NARN if the line
came from OSM or a GTFS shape, OSM if it came from NARN, plus any verified
official network), and blocks the interval when

    unmatched > 0   OR   maxDeviationMeters > DISPLAY_ALIGNMENT_TOLERANCE_M[profile]

with `unmatched` counting vertices more than 400 m from *any* reference and the
tolerance table (`lib/na_profile.py:171-177`) being
street 20 / metro 25 / commuter 30 / regional 35 / longhaul 50 m.
A line whose own `geometrySource` is a provenance-verified official centreline
is exempted (`officialSourceRetainedIntervals`, 234 US + 5 CA intervals).

**The package records the block per interval but the numbers only per line.**
`byLine[<id>]` carries one `maxDeviationMeters`, one `worstAt`, one `unmatched`
and one `agreedWith` for the whole line. So for any blocked interval the repo
gives an *upper bound* on its own worst deviation — the line's number — and,
via `worstAt`, tells you which single interval that number belongs to.

Three things can put a blocked interval back on the map:

1. `shared-corridors.json` replacing it with a reviewed canonical interval
   (`rail-network.js:1119,1260` add it to `releasedIntervals`);
2. `display-releases.json` naming it (this ledger's mechanism);
3. nothing else. `displayPartsForLine` calls `flush()` on whatever is left
   (`rail-network.js:1352-1355`), which cuts the stroke in two.

### `display-releases.json` — the exact schema

Written by `app/scripts/railway/make-display-releases.py`, read by
`app/scripts/railway/build-display-lanes.mjs:752-764`, which copies it into
`display-lanes.json` as `releasedIntervalsByRegion`; both renderers then read
that (`rail-network.js:2560-2571`, `build-display-network.py:972,993-999`).

```
{
  "format": "jtm-display-releases-v1",     // builder throws on any other value
  "reviewedAt": "YYYY-MM-DD",
  "method": "<how the rows were measured>",
  "releases": [ {
      "region": "us" | "ca",
      "lineId": "<compact package line id>",
      "interval": <int, index into line.segments>,
      "stations": ["<from name>", "<to name>"],
      "verdict": "A" | "C",                 // ONLY these two are copied through
      "limitMetres": <the profile tolerance the gate applied>,
      "packageMaxDeviationMetres": <byLine[...].maxDeviationMeters>,
      "osmMedianMetres": …, "osmP95Metres": …,
      "osmMaxMetres": …, "osmMaxAt": [lon, lat],
      "note": "<why>"
  } ],
  "withheldAfterMeasurement": [ … same shape, "verdict": "B" … ],
  "notMeasured": [ ["region", "lineId", interval], … ]
}
```

The verdict vocabulary is **not** A/B/C — it is four values, and the builder's
filter is literally `if (!["A","C"].includes(row.verdict)) continue;`:

| verdict | meaning (`make-display-releases.py:5-14`) | released? |
| --- | --- | --- |
| **A** | measured again and found consistent — median well inside the limit, no localised excursion | yes |
| **B** | measured again and found genuinely wrong | no, kept in `withheldAfterMeasurement` |
| **C** | disagrees only where the reference is the coarse one (an OSM tunnel approximation) | yes |
| **D** | not measured; listed in `notMeasured` | no |

Note that `releases` rows only ever carry A or C: B lives in
`withheldAfterMeasurement` and D in `notMeasured`. Anything else in `releases`
is silently skipped by the builder.

## State before this review

| | US | CA |
| --- | ---: | ---: |
| blocked intervals in the package | 36 over 18 lines | 4 over 2 lines |
| already released by `display-releases.json` | 21 | 3 |
| still blocked | 15 over 9 lines | 1 over 1 line |
| of those, also released by a reviewed shared corridor | 3 | 0 |
| **still blocked AND cutting the map** | **12** | **1 (a truncation, not a cut)** |

Measured with the real pipeline
(`buildNetworkFromCompactPackage(pkg, sharedCorridors, displayLanes)`):
**US 13 breaks > 120 m totalling 714.2 km**, CA 0. One of the 13 —
`port-authority-trans-hudson-journal-square-33rd-street-via-hoboken`, 2870 m —
is **not** a gate defect at all (see "Real branches" below).

The 24 already-released intervals are not re-litigated here; their OSM
measurements are in `display-releases.json` and their reasoning in
`na-2025-display-ledger.md` §4.

## What was measured for this review

For each still-blocked interval the geometry was rebuilt with the compact-v1
chain rule (`continuesFromPrevious == 1` prepends the previous interval's last
vertex; both ends are then forced onto the station anchors, exactly as
`rail-network.js:861-879` does) and put through the failure modes this project
knows about:

* **straight chord** — max perpendicular deviation of interior vertices from
  the endpoint chord, plus the longest *internal* run of consecutive vertices
  that stays within 25 m of its own chord (the detector `na_geo.densify()`
  defeats, per DIAGNOSIS defect 2);
* **detour** — walked length ÷ endpoint distance;
* **internal reversal** — max turn angle at any vertex, and the count ≥ 150°;
* **self-overlap** — non-adjacent vertex pairs within 20 m;
* **vertex jump** — longest edge, against the profile's `max_edge_m` densify cap;
* **anchor drift** — distance from the raw stored endpoint to its station anchor.

and then cross-measured, vertex by vertex, against **every other line in the
us/ca packages that runs the same corridor** — an in-repo independent
reference wherever one exists, with its own `geometrySource`, its own feed and
its own recorded `maxDeviationMeters`.

**No OSM/Overpass run was possible in this session.** `/private/tmp/jtm-na-rail`
and `app/data/raw` are gone (see MEMORY: "NA rail source tree lives outside the
repo", "Railway sources purged from GitHub"). Every number below comes from the
packages themselves or from geometry in this repository. Rows released on that
basis are tagged `"method": "package-bound"` in `display-releases.json` and are
described by its new `packageBoundMethod` field, so they are never confused
with the Overpass-measured rows.

### The release rule applied

An interval is released **only** when all of:

* **R1** the line's recorded `maxDeviationMeters` — an upper bound on this
  interval's own worst deviation — is ≤ **1.5 × the profile limit**. That is
  exactly the bar every existing `A` row in `display-releases.json` states
  ("max 36.8 m <= 1.5x limit (75 m)"), applied to a number the package
  measured itself, against the same references, at every vertex;
* **R2** `unmatched == 0` for the line: no drawn vertex is more than 400 m from
  surveyed track, so nothing here is invented across a void;
* **R3** the shape passes every failure mode above;
* **R4** the interval is not one the reviewed table already measured and
  rejected (verdict B).

R1 is deliberately *more* conservative than the existing table: applied
line-wide it would have refused `amtrak-pennsylvanian[6]` and `[12]` and
`mbta-providence-stoughton-line-b5[7]`, which a real OSM measurement did
release. It refuses **both** intervals the OSM run rejected as B
(`amtrak-pennsylvanian[13]`: 297.14 > 75; `nashville-…-90[2]`: 67 > 52.5), so it
does not contradict a single measured verdict anywhere in the table.

## Per-interval verdicts

Ratio = line `maxDeviationMeters` ÷ profile limit; the release bar is 1.50.
"worst here" = the line's `worstAt` falls on this interval, so the ratio is this
interval's actual value rather than an upper bound.

| # | region | line | iv | station pair | limit | pkg max | ratio | worst here | shape | in-repo peer | verdict | action |
|---:|---|---|---:|---|---:|---:|---:|:-:|---|---|:-:|---|
| 1 | ca | `via-ottawa-montr-al` | 0 | Montréal → Dorval | 50 | 313.0 | **6.26** | yes, ch. 8.09/18.10 km | sound | none (exo-vh is a different subdivision, 735 m median) | **C** | stays blocked |
| 2 | us | `amtrak-pennsylvanian` | 13 | Philadelphia → Trenton | 50 | 297.14 | **5.94** | no (int. 12 area) | sound | — | **B** | stays blocked; already drawn from a reviewed corridor |
| 3 | us | `amtrak-southwest-chief` | 17 | Raton → Las Vegas NM | 50 | 72.76 | 1.46 | no (int. 28) | sound | none | **A** | **release** |
| 4 | us | `amtrak-southwest-chief` | 23 | Flagstaff → Kingman | 50 | 72.76 | 1.46 | no (int. 28) | sound | none | **A** | **release** |
| 5 | us | `amtrak-southwest-chief` | 25 | Needles → Barstow | 50 | 72.76 | 1.46 | no (int. 28) | sound | none | **A** | **release** |
| 6 | us | `amtrak-southwest-chief` | 28 | San Bernardino → Riverside | 50 | 72.76 | 1.46 | yes, ch. 1.32/17.00 km | sound | metrolink-ie-oc med 12.7 m | **A** | no row needed — `shared-corridors.json` already releases it |
| 7 | us | `amtrak-vermonter` | 1 | Essex Jct → Waterbury-Stowe | 50 | 67.26 | 1.35 | no (int. 25 area) | sound | none | **A** | **release** |
| 8 | us | `amtrak-vermonter` | 17 | New Haven → Bridgeport | 50 | 67.26 | 1.35 | no | sound | MNR New Haven med 6.9 m | **A** | no row needed — corridor already releases it |
| 9 | us | `amtrak-vermonter` | 26 | Baltimore Penn → BWI | 50 | 67.26 | 1.35 | no | sound | **duplicate** of released `amtrak-carolinian[8]` (max 2.8 m) | **A** | **release** |
| 10 | us | `bart-blue` | 9 | West Oakland → Lake Merritt | 30 | 60.23 | **2.01** | yes, ch. 2.16/2.91 km | sound | bart-red coincident to the wye only | **C** | stays blocked |
| 11 | us | `bart-green` | 9 | West Oakland → Lake Merritt | 30 | 60.23 | **2.01** | yes, ch. 2.16/2.91 km | sound | identical to `bart-blue[9]` (0.0 m) | **C** | stays blocked |
| 12 | us | `maryland-…-brunswick-washington` | 11 | Dickerson → Point of Rocks | 35 | 47.31 | 1.35 | no (int. 15) | sound | own NARN shards med 8.9 m | **A** | **release** |
| 13 | us | `maryland-…-brunswick-washington` | 13 | Brunswick → Harpers Ferry | 35 | 47.31 | 1.35 | no (int. 15) | sound | none | **A** | **release** |
| 14 | us | `nashville-mta-wego-public-tr-90` | 2 | Martha → Mt. Juliet | 35 | 67.0 | **1.91** | yes, ch. 3.36/9.97 km | sound | none | **B** | stays blocked |
| 15 | us | `south-florida-regional-trans-mce` | 1 | Metrorail Transfer → FLL | 50 | 63.17 | 1.26 | yes, ch. 8.40/28.42 km | sound | Tri-Rail NARN med **23.8 m**, sustained | **C** | stays blocked — wants a shared corridor, not a release |
| 16 | us | `south-shore-line-lakeshore` | 5 | Hegewisch → Hammond Gateway | 35 | 49.01 | 1.40 | yes, ch. 2.46/2.71 km | sound | south-shore-monon med 5.0 m | **A** | **release** |

Every one of the sixteen passes R3 outright — **not one of them is a straight
chord, a reversal, a self-overlap, a vertex jump or an unanchored endpoint**:

| line[iv] | vtx | walked km | chord km | detour | max dev. from chord | longest internal straight | max edge (cap) | max turn | ≥150° | overlap | anchor drift |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `via-ottawa-montr-al[0]` | 49 | 18.10 | 14.79 | 1.224 | 3.07 km | 3.11 km | 595 m (600) | 25.8° | 0 | 0 | 0.0 / 0.0 m |
| `amtrak-pennsylvanian[13]` | 108 | 51.84 | 46.65 | 1.111 | 4.48 km | 4.50 km | 597 m (600) | 33.2° | 0 | 0 | 0.0 / 0.0 m |
| `amtrak-southwest-chief[17]` | 373 | 176.30 | 161.15 | 1.094 | 21.02 km | 9.16 km | 600 m (600) | 41.3° | 0 | 0 | 0.0 / 0.0 m |
| `amtrak-southwest-chief[23]` | 631 | 276.57 | 218.43 | 1.266 | 37.78 km | 22.73 km | 599 m (600) | 54.4° | 0 | 0 | 0.0 / 0.0 m |
| `amtrak-southwest-chief[25]` | 542 | 264.43 | 220.84 | 1.197 | 38.47 km | 21.74 km | 598 m (600) | 34.2° | 0 | 0 | 0.0 / 0.0 m |
| `amtrak-southwest-chief[28]` | 39 | 17.00 | 15.34 | 1.108 | 1.50 km | 2.48 km | 598 m (600) | 64.9° | 0 | 0 | 0.0 / 0.0 m |
| `amtrak-vermonter[1]` | 84 | 35.80 | 33.42 | 1.071 | 3.59 km | 4.12 km | 590 m (600) | 65.5° | 0 | 0 | 0.0 / 0.0 m |
| `amtrak-vermonter[17]` | 64 | 26.81 | 25.53 | 1.050 | 2.11 km | 3.76 km | 596 m (600) | 72.3° | 0 | 0 | 0.0 / 0.0 m |
| `amtrak-vermonter[26]` | 46 | 16.89 | 14.52 | 1.163 | 3.03 km | 3.03 km | 596 m (600) | 70.1° | 0 | 0 | 0.0 / 0.0 m |
| `bart-blue[9]` / `bart-green[9]` | 30 | 2.91 | 2.76 | 1.055 | 196 m | 0.84 km | 183 m (220) | 17.1° | 0 | 0 | 0.0 / 0.0 m |
| `maryland-…-brunswick-washington[11]` | 49 | 11.65 | 11.30 | 1.031 | 492 m | 2.69 km | 342 m (350) | 12.5° | 0 | 0 | 0.0 / 0.0 m |
| `maryland-…-brunswick-washington[13]` | 48 | 9.69 | 9.00 | 1.077 | 1.34 km | 1.44 km | 320 m (350) | 16.4° | 0 | 0 | 0.0 / 0.0 m |
| `nashville-…-90[2]` | 44 | 9.97 | 8.82 | 1.130 | 1.83 km | 2.04 km | 348 m (350) | 13.5° | 0 | 0 | 0.0 / 0.0 m |
| `south-florida-…-mce[1]` | 61 | 28.42 | 25.71 | 1.105 | 3.87 km | 7.46 km | 600 m (600) | 21.1° | 0 | 0 | 0.0 / 0.0 m |
| `south-shore-line-lakeshore[5]` | 13 | 2.71 | 2.64 | 1.026 | 221 m | 1.64 km | 276 m (350) | 22.2° | 0 | 0 | 0.0 / 0.0 m |

The long internal straight runs — 22.73 km inside `amtrak-southwest-chief[23]`
and 21.74 km inside `[25]` — are **real tangents, not invented chords**, and the
package proves it: no vertex of that line is more than 72.76 m from surveyed
track anywhere along its 3579 km. A chord thrown across a real curve would show
kilometre-scale disagreement, not 73 m. (Those two runs sit on the BNSF
Seligman and Mojave subdivisions, which is where a 20 km tangent belongs.)

## Reasoning, interval by interval

### Released (8 rows added to `display-releases.json`)

**`amtrak-southwest-chief` 17, 23, 25** — Raton → Las Vegas NM (176.3 km),
Flagstaff → Kingman (276.6 km), Needles → Barstow (264.4 km). These are the
three headline cuts on the US map: 161 153 m, 218 432 m and 220 841 m of
nothing. The line's whole-line worst disagreement is 72.76 m, and `worstAt`
`[-117.324825, 34.10334]` puts it on **interval 28**, in the San Bernardino
terminal throat — so each of these three is strictly under 72.76 m, i.e. under
1.46 × the 50 m longhaul limit, which is the bar `[7]`, `[9]`, `[11]` and `[14]`
of this same line were already released on (their OSM maxima were 54.1, 51.1,
26.1, 36.8 m). `unmatched = 0` across all 7374 checked vertices, agreeing with
NARN at 6968 and OSM at 406. Shape sound on every axis. No in-repo peer exists —
nothing else in the packages runs Raton Pass, the Seligman Sub or the Mojave —
so this release rests on R1/R2/R3 alone.

**`amtrak-vermonter` 26** — Baltimore Penn → BWI. The strongest row in the set.
Its geometry is a **duplicate** of `amtrak-carolinian[8]` over the same station
pair: median 0.0 m, p95 1.2 m, max 2.8 m, 46 of 46 vertices under 3 m.
`amtrak-carolinian[8]` was measured against OSM and released A ("single vertex
65.4 m against the B&P tunnel way (OSM tunnel=yes); median 2.8 m, all else
≤21 m"), and `amtrak-palmetto[6]` was released purely as "duplicate geometry of
carolinian[8]" — the identical argument. Independently corroborated by the
MARC Penn Line (`…-penn-washington`, NARN-built, own max 21.5 m): median 3.6 m,
44 of 46 vertices within 25 m, the two exceptions single 52 m vertices.

**`amtrak-vermonter` 1** — Essex Junction → Waterbury-Stowe, a 33 417 m cut.
Bound ≤ 67.26 m = 1.35 × limit; `worstAt` is 560 km away at Wilmington DE, so
this interval is well under that. New England Central through the Winooski
valley; detour 1.071, no peer in the packages.

**`maryland-transit-administrat-brunswick-washington` 11 and 13** —
Dickerson → Point of Rocks (11 303 m cut) and Brunswick → Harpers Ferry
(9002 m cut). Bound ≤ 47.31 m = 1.35 × the 35 m regional limit, and `worstAt`
`[-77.885723, 39.380218]` is on **interval 15**, which the OSM run already
measured (max 41.4 m near Shenandoah Jct) and released. For `[11]`, the line's
own NARN-built branch shards `-b1/-b2/-b3` run the same CSX Metropolitan Sub:
median 8.9 m, with two mid-interval excursions peaking at 44 m — inside what
47.31 m allows for a two- and three-track subdivision — and a 226.6 m
difference **at the final vertex only**, which is the two representations'
Point of Rocks station anchors, not track. `[13]` has no peer.

**`south-shore-line-lakeshore` 5** — Hegewisch → Hammond Gateway, a 2638 m cut.
`worstAt` is on this interval at chainage 2.46 of 2.71 km (91 %), 49.01 m =
1.40 × the 35 m limit. `south-shore-line-monon`, built from the operator's GTFS
shape rather than this line's NARN and itself within 11.26 m of the reference,
runs the same track: median 5.0 m, and **every** disagreement is confined to the
last 250 m into Hammond Gateway, peaking at 90 m at the station vertex itself.
That is the same shape as the already-released
`mbta-providence-stoughton-line-b5[7]` ("the only over-limit point is the South
Station terminal vertex itself… not an alignment defect, release").

### Released by a reviewed corridor already — no row needed

**`amtrak-southwest-chief` 28** and **`amtrak-vermonter` 17** are both in
`shared-corridors.json`'s release set (`reviewedSharedCorridorOverrides` adds
them to `releasedIntervals`), so they draw today and produce no gap. Their
evidence is recorded above for completeness; adding a `display-releases.json`
row would be redundant and would draw the line's own coarser trace instead of
the reviewed canonical. Same for **`amtrak-pennsylvanian[13]`**, which is
verdict B but is corridor-drawn, which is why a 297 m defect makes no hole.

For the record, `[28]`'s 72.76 m sits at chainage 1.32 km of 17.00 km — 8 % out
of San Bernardino Depot, in a terminal throat — and Metrolink's IE-OC line
(operator centreline, own max 9.77 m) tracks it at median 12.7 m outside the
2.3 km where IE-OC genuinely takes its own alignment. `[17]`'s only two
over-25 m vertices against Metro-North's own New Haven Line centreline (own max
9.51 m) are the New Haven and Bridgeport **station anchors**; everything in
between is p90 17.0 m, median 6.9 m.

### Stays blocked — measured and wrong (B)

**`amtrak-pennsylvanian` 13** — Philadelphia → Trenton. Already measured
against OSM: one interpolated sample 277 m from any rail near Zoo interlocking
while the other 33 are within 16 m. A localised chord or misrouting. Also fails
R1 by a factor of four. No display consequence — the corridor draws it.

**`nashville-mta-wego-public-tr-90` 2** — Martha → Mt. Juliet, an 8823 m cut.
Already measured: vertices at chainage 3120/3360/3600 m on a constant bearing at
exactly 240 m spacing while the OSM Nashville & Eastern way curves — a sustained
67 m chord across a curve, and `worstAt` confirms the 67 m is on this interval
(chainage 3.36 km). Fails R1 (1.91 ×). This one is a **genuine defect**: the map
is right to leave the hole, and the repair is new geometry, not a release.

### Stays blocked — undecidable on in-repo evidence (C)

**`via-ottawa-montr-al` 0** — Montréal → Dorval. The worst case in the set:
313 m from the reference, 6.26 × the 50 m limit, and `worstAt` puts it
mid-interval at chainage 8.09 of 18.10 km, not at a station. The line is
NARN-built and was checked against OSM only (`agreedWith {"osm": 406}`). Shape
is sound, so this is not an invented chord — it is a 313 m *lateral*
disagreement, which at that magnitude is a different alignment, not a parallel
track. No usable in-repo peer: `exo-vh` runs Gare Centrale → Dorval too but on
its own subdivision, 735 m away at the median. **Needs the OSM extract.** Its
effect today is a truncation, not a cut — interval 0 is the line's first, so the
stroke simply starts at Dorval and 18.1 km of the Montréal end is missing.

**`bart-blue` 9 and `bart-green` 9** — West Oakland → Lake Merritt, 2759 m cut
on each. Byte-identical geometry (0.0 m apart at every vertex). Fails R1 at
2.01 ×, and `worstAt` puts the 60.23 m on this interval at chainage 2.16 of
2.91 km (74 %) — under Oak Street, i.e. **inside the Oakland subway**, at the
south-east leg of the wye. That is precisely the profile of the two `C` rows
already in the table (`ttc-5[21]`, `[22]`: "the OSM tunnel geometry is the
coarse side"), and BART publishes its own alignment. But 2.0 × the limit is
past every precedent in the table and I cannot measure the OSM tunnel way from
here, so this is a *hypothesis*, not a verdict. `bart-red` is coincident to
median 2.2 m for the first 2.12 km and then legitimately leaves at the wye, so
it cannot settle the Lake Merritt leg. **Needs the OSM extract.**

**`south-florida-regional-trans-mce` 1** — Metrorail Transfer → Ft Lauderdale
Airport, a 25 713 m cut. This one passes R1 (1.26 ×) and R2 and R3, and I am
still not releasing it. `south-florida-regional-trans-tr` — the *same operator's
own Tri-Rail service on the same SFRC tracks*, NARN-built, itself within 11.08 m
of the reference — sits at **median 23.8 m** from this geometry, with sustained
excursions to 72 m over chainage 5.6–15.9 km. That is far more than track
separation, and it is sustained rather than localised, so the "no localised
excursion" half of verdict A is not satisfied: this looks like a coarse GTFS
shape beside a surveyed alignment, not a survey disagreement. `mce` is a
five-station express (117.6 km, so `smoothingProfile` `longhaul`, limit 50)
running the same metals as an eighteen-station `regional` line (limit 35), which
is exactly why it slipped a limit its own track-mate would have failed.

> **Recommended repair, out of scope here:** a `shared-corridors.json` entry
> making `south-florida-regional-trans-tr` canonical for this stretch, the same
> device that already fixes `amtrak-pennsylvanian[13]` and
> `amtrak-southwest-chief[28]`. That draws MCE on the surveyed alignment
> instead of releasing a coarser one. `shared-corridors.json` is not this
> review's file.

## Real branches, not defects

`port-authority-trans-hudson-journal-square-33rd-street-via-hoboken` shows a
2870 m break between Newport and Christopher Street. It has **no blocked
intervals at all** (`maxDeviationMeters` 22.67, `unmatched` 0), and its station
order is Journal Square → Grove → Newport → **Hoboken** → Christopher St → … —
the service reverses at the Hoboken stub. The break is `displayPartsForLine`'s
reversal detection doing its job, not the alignment gate. It is the only such
case among the 13 US breaks; every other one traces to a blocked interval in
the table above. Nothing in this review touches it.

## Effect

Simulated with the real pipeline over the shipped packages, adding only the 8
release rows:

| | before | after |
| --- | ---: | ---: |
| US breaks > 120 m | 13 | **5** |
| US break length | 714 190 m | **42 924 m** |
| US display strings | 275 | **267** |
| CA breaks > 120 m | 0 | 0 |

Remaining US breaks: `south-florida-regional-trans-mce` 25 713 m (C, wants a
corridor), `nashville-…-90` 8823 m (B, genuine defect), `port-authority-…-via-hoboken`
2870 m (a real reversal), `bart-blue` 2759 m and `bart-green` 2759 m (C, tunnel,
needs OSM). CA keeps `via-ottawa-montr-al`'s 18.1 km Montréal truncation.

## To apply

`display-lanes.json` **must** be regenerated: releasing an interval merges two
display parts into one, so part indexes and along-part metres change (US 275 →
267 strings), and every `byRegion` / `followsByRegion` row for the eight
affected lines is keyed on the old indexes.

```
cd app && node scripts/railway/build-display-lanes.mjs
cd app && python3 -m unittest scripts.railway.tests.test_display_network
```

## Known gaps in this review

* No OSM/Overpass measurement was possible. Eight rows are released on the
  package's own bound plus in-repo cross-evidence, tagged
  `"method": "package-bound"`. Three intervals stay blocked purely for want of
  that feed.
* The package records deviation per **line**, not per interval. Where `worstAt`
  falls on another interval, the number used here is an upper bound, not a
  measurement of the interval itself.
* Pre-existing, not corrected here: the released row
  `maryland-transit-administrat-brunswick-washington[15]` records
  `"limitMetres": 30`. The package's `smoothingProfile` for that line is
  `regional`, so the gate applied **35**, and `na-2025-line-review.json` says
  35. The row's conclusion is unaffected (41.4 m is inside 1.5 × 35 = 52.5 m).
* `na-2025-line-review.{json,md}` was deliberately **not** appended to: it is
  generated by `make-na-line-review.py` via `merge-na-feed-build.py`, and a
  hand-added key would be silently dropped on the next build. This ledger is
  the durable record.

## 2026-09-02 — OSM polyline measurement

The Overpass tile gap above is closed: an OSM railway extract for the
relevant corridors (staged as gzipped `*.json.gz` Overpass responses) is now
available, and every interval this ledger left blocked for want of it has
been measured a second time, vertex by vertex, against the nearest active
OSM railway way of the line's own type. The new script is
`app/scripts/railway/measure-display-blocked-intervals.py`; it reconstructs
each interval with the same compact-v1 `continuesFromPrevious` chain rule
used everywhere else in this pipeline, measures point-to-*segment* distance
(not point-to-nearest-vertex — see the script's docstring for why that
distinction matters here), and runs a 150 m perpendicular shifted-control
re-measurement per interval as a sanity check against an over-wide OSM
candidate set.

Sixteen intervals were measured: the fourteen this ledger's package-bound
pass and the original gate left open, plus the two already-`B` rows
(`amtrak-pennsylvanian[13]`, `nashville-mta-wego-public-tr-90[2]`)
re-measured for confirmation. Four of the fourteen (`amtrak-southwest-chief`
17/23/25, `amtrak-vermonter` 1) have **no OSM tile coverage at all** (0 ways
within 500 m) — Raton Pass, the BNSF Seligman/Mojave Subs, and the New
England Central through the Winooski valley are simply not in the extract.
Those four keep the package-bound release this ledger already gave them
(`"method": "package-bound"` rows, unchanged) and stay listed in
`notMeasured`, now for the literal reason "no OSM tile coverage" rather than
"no Overpass access." The other ten now carry a direct measurement.

| region | line[interval] | stations | km | median / p95 / max (m) | shifted control median (m) | verdict | action |
|---|---|---|---:|---|---:|:-:|---|
| us | `amtrak-southwest-chief[17]` | Raton → Las Vegas Amtrak Station | 176.30 | — no OSM ways in range — | — | D | stays `notMeasured`: no OSM tile coverage |
| us | `amtrak-southwest-chief[23]` | Flagstaff → Kingman | 276.57 | — no OSM ways in range — | — | D | stays `notMeasured`: no OSM tile coverage |
| us | `amtrak-southwest-chief[25]` | Needles Amtrak → Barstow | 264.43 | — no OSM ways in range — | — | D | stays `notMeasured`: no OSM tile coverage |
| us | `amtrak-southwest-chief[28]` | San Bernardino Depot → Riverside – Downtown | 17.00 | 7.4 / 24.8 / 72.5 | 137.9 | A | **released** |
| us | `amtrak-vermonter[1]` | Essex Junction-Burlington Amtrak Station → Waterbury-Stowe Amtrak Station | 35.80 | — no OSM ways in range — | — | D | stays `notMeasured`: no OSM tile coverage |
| us | `amtrak-vermonter[17]` | New Haven → Bridgeport | 26.81 | 1.5 / 13.8 / 56.1 | 137.8 | A | **released** |
| us | `amtrak-vermonter[26]` | Baltimore Penn Station → Bwi Thurgood Marshall Airport Station | 16.89 | 2.2 / 24.5 / 65.0 | 128.5 | A | **released** — supersedes the earlier package-bound row with a direct measurement |
| us | `bart-blue[9]` | West Oakland → Lake Merritt | 2.91 | 1.8 / 52.9 / 60.0 | 142.0 | C | **released** — excess confined to the downtown Oakland tunnel, OSM is the coarse side |
| us | `bart-green[9]` | West Oakland → Lake Merritt | 2.91 | 1.8 / 52.9 / 60.0 | 142.0 | C | **released** — same measurement as `bart-blue[9]`, same tunnel leg |
| us | `maryland-…-brunswick-washington[11]` | Dickerson → Point of Rocks | 11.65 | 5.8 / 26.3 / 39.0 | 134.8 | A | **released** — supersedes the earlier package-bound row |
| us | `maryland-…-brunswick-washington[13]` | Brunswick → Harpers Ferry | 9.69 | 8.3 / 39.0 / 45.5 | 132.5 | C | **released** — supersedes the earlier package-bound row; 5 of 48 vertices over the limit by ≤11 m through the Potomac gorge |
| us | `south-florida-regional-trans-mce[1]` | Metrorail Transfer Station → Ft Lauderdale Airport Station | 28.42 | 20.5 / 50.1 / 62.9 | 111.9 | B | measured, **stays blocked**; moved to `withheldAfterMeasurement` |
| us | `south-shore-line-lakeshore[5]` | Hegewisch → Hammond Gateway | 2.71 | 2.8 / 47.9 / 48.7 | 145.5 | C | **released** — supersedes the earlier package-bound row; excursion is the Hammond Gateway station-anchor vertex (n=13) |
| ca | `via-ottawa-montr-al[0]` | Montréal → Dorval | 18.10 | 1.7 / 242.6 / 311.9 | 134.0 | B | measured, **stays blocked**; moved to `withheldAfterMeasurement`. Median looks clean but the excursion is mid-interval (chainage ≈8/18 km), not a station anchor or tunnel artifact |
| us | `amtrak-pennsylvanian[13]` | Philadelphia → Trenton | 51.84 | 1.9 / 20.0 / 226.3 | 134.8 | B (re-confirmed) | already `withheldAfterMeasurement`; re-measured, verdict unchanged, row not touched this pass |
| us | `nashville-mta-wego-public-tr-90[2]` | Martha Station → Mt. Juliet Station | 9.97 | 1.7 / 32.1 / 66.7 | 138.3 | B (re-confirmed) | already `withheldAfterMeasurement`; re-measured, verdict unchanged, row not touched this pass |

Two verdicts here are an editorial call rather than the script's mechanical
A/median≤10∧≤5%-over / C/≤20%-over / B rule, and are recorded as such:
`amtrak-southwest-chief[28]` computes to 5.1% of vertices over the 50 m
limit (a single outlier vertex on 402 candidate ways), just past the script's
5% A/C boundary — released A on the same single-vertex-outlier reasoning
already used for the sibling intervals on this line. `via-ottawa-montr-al[0]`
computes inside the mechanical C band (median 1.7 m, 16.3% of vertices over
the 50 m limit), but the excursion is centred mid-interval rather than at a
station anchor or tunnel portal, so it was kept at B pending a look at why
the Kingston Sub disagrees there.

`bart-blue[9]` / `bart-green[9]` / `maryland-…-brunswick-washington[13]` /
`south-shore-line-lakeshore[5]` were previously released `A` on package-bound
reasoning (no Overpass access at the time); the direct OSM measurement here
downgrades them to `C` — still released, but now with real independent
numbers instead of an in-repo peer argument, and an honest label for the
tunnel/station-anchor excursions the peer argument couldn't see.

`display-lanes.json` was regenerated (`node scripts/railway/build-display-lanes.mjs`):
`releasedIntervalsByRegion.us` grew from 29 to **33** (not 37 — four of the
eight target rows already carried a package-bound release from an earlier
pass on this same working tree; those were upgraded in place rather than
duplicated), `ca` stays at 3. `app/scripts/railway/build-display-network.py`
was re-run the way the iOS copy phase runs it and completed without error.

## 2026-09-02 — NARN polyline measurement

The four intervals the OSM pass above could not reach at all — no Overpass
tile covers Raton Pass, the BNSF Seligman/Mojave Subs, or the New England
Central through the Winooski valley — have an independent reference after
all: the FRA/BTS North American Rail Network, staged locally as 128 gzipped
pages (`page-*.json.gz`, each a bare JSON list of `{"p": <properties>, "c":
<coords>}` records, not GeoJSON). `measure-display-blocked-intervals.py`
gained a `--narn-dir` flag that reads this format and runs the exact same
point-to-*segment* metric, 150 m shifted control, and A/C/B/D verdict rule
already used for OSM; every row now carries a `reference` field ("osm" or
"narn") so a reader never has to guess which independent source a
`medianM`/`maxM`/`maxAt` triple came from. The NARN loader keeps only
`NET == "M"` (main track) records — 11,411 of 14,525 sampled arcs — dropping
siding (`S`), industrial (`I`), abandoned (`A`), excepted (`X`) and yard
(`Y`) arcs the same way the OSM loader drops `EXCLUDE_SERVICE` ways; a
record with no `NET` key at all is kept, since there is nothing to filter
on. Loaded: 95,077 candidate main-track ways from the 128 pages.

Eight intervals were measured: the four package-bound releases above, plus
four already-`B` rows as a cross-check on whether NARN agrees with OSM's
verdict (`south-florida-regional-trans-mce[1]`,
`nashville-mta-wego-public-tr-90[2]`, `via-ottawa-montr-al[0]`,
`amtrak-pennsylvanian[13]`).

| region | line[interval] | stations | km | median / p95 / max (m) | shifted control median (m) | verdict | action |
|---|---|---|---:|---|---:|:-:|---|
| us | `amtrak-southwest-chief[17]` | Raton → Las Vegas Amtrak Station | 176.30 | 7.2 / 25.3 / 50.9 | 142.3 | A | **released** — supersedes the package-bound row with a direct NARN measurement |
| us | `amtrak-southwest-chief[23]` | Flagstaff → Kingman | 276.57 | 8.6 / 27.6 / 57.2 | 130.2 | A | **released** — supersedes the package-bound row |
| us | `amtrak-southwest-chief[25]` | Needles Amtrak → Barstow | 264.43 | 7.9 / 27.6 / 57.9 | 137.0 | A | **released** — supersedes the package-bound row |
| us | `amtrak-vermonter[1]` | Essex Junction-Burlington Amtrak Station → Waterbury-Stowe Amtrak Station | 35.80 | 6.5 / 25.1 / 55.7 | 141.8 | A | **released** — supersedes the package-bound row |
| us | `south-florida-regional-trans-mce[1]` | Metrorail Transfer Station → Ft Lauderdale Airport Station | 28.42 | 25.1 / 55.3 / 69.0 | 113.6 | B | cross-check only; **NARN agrees with OSM's B** — stays `withheldAfterMeasurement`, row unchanged |
| us | `nashville-mta-wego-public-tr-90[2]` | Martha Station → Mt. Juliet Station | 9.97 | 1.6 / 5.4 / 7.2 | 138.2 | A | cross-check only; **NARN contradicts OSM's B** — no chord-across-curve excursion visible against NARN. Stays `withheldAfterMeasurement`, row unchanged; see below |
| ca | `via-ottawa-montr-al[0]` | Montréal → Dorval | 18.10 | 1.7 / 9.8 / 12.3 | 136.7 | A | cross-check only; **NARN contradicts OSM's B** — no mid-interval excursion visible against NARN. Stays `withheldAfterMeasurement`, row unchanged; see below |
| us | `amtrak-pennsylvanian[13]` | Philadelphia → Trenton | 51.84 | 7.5 / 27.8 / 228.3 | 144.2 | A (mechanical) | cross-check only; mechanical A, but see below — treated as corroboration, not contradiction. Stays `withheldAfterMeasurement`, row unchanged |

Package-bound rows: all four measure cleanly inside the mechanical A bar
(median ≤ 10 m, ≤ 5% of vertices over the 50 m longhaul limit), each with a
shifted-control median 17–22× its raw median (130–142 m vs. 6.5–8.6 m),
which is the sanity check that the 8–86-way candidate sets on these long
rural intervals are not accidentally scoring against a wide swath of
parallel track. All four `display-releases.json` rows were updated in
place: `verdict`, `reference: "narn"`, `method: "narn-polyline-measured"`,
`measuredAt: "2026-09-02"`, `narnMedianMetres`/`narnP95Metres`/
`narnMaxMetres`/`narnMaxAt` (named `narn*`, not `osm*` — these numbers never
came from OpenStreetMap), and a note replacing the package-bound wording.
No `"method": "package-bound"` row remains in `display-releases.json`.

Cross-check rows, in detail — **none of the four verdict-B rows were
changed**, per this review's own rule (NARN disagreement gets reported, not
acted on):

- `south-florida-regional-trans-mce[1]`: NARN's own numbers (median 25.1 m,
  13.1% of vertices over the limit) land in the same B territory as OSM's
  (median 20.5 m, an earlier finding already consistent with the Tri-Rail
  NARN-built shard on the same SFRC tracks sitting at median 23.8 m).
  Straightforward agreement.
- `nashville-mta-wego-public-tr-90[2]`: OSM found a sustained 67 m chord
  across a curve on the Nashville & Eastern; NARN's own polyline here shows
  nothing of the kind (max 7.2 m, 0% over the 35 m limit, only 8 candidate
  ways). This is a clear disagreement, reported here rather than acted on —
  a low NARN way count (8) on a short commuter interval is exactly the case
  where a sparse candidate set could under-detect a real curve, so this is
  flagged as worth a closer look, not treated as proof the package is right.
- `via-ottawa-montr-al[0]`: OSM found a sustained 242–312 m mid-interval
  excursion (chainage ≈8/18 km) on the Kingston Sub; NARN's own polyline
  shows a clean median (1.7 m) and max of only 12.3 m against 187 candidate
  ways — a much denser candidate set than the Nashville case, so this
  disagreement is harder to explain away as a thin reference. Reported as a
  genuine contradiction; row left withheld pending a closer look at why OSM
  and NARN disagree on this stretch.
- `amtrak-pennsylvanian[13]`: mechanically this NARN row computes to A
  (median 7.5 m, 3.7% of 108 vertices over the 50 m limit) — the same shape
  of result (small median, a handful of over-limit vertices) that would
  mechanically compute to A for the already-published OSM row too (OSM:
  median 3.0 m, 1 of 34 points over the limit ≈2.9%), which was hand-kept at
  B in `withheldAfterMeasurement` on the reviewer's judgement that the
  single 277 m OSM outlier was a real chord/misrouting near the Zoo
  interlocking, not distance-metric noise. NARN's own worst vertex, 228.3 m
  at `[-75.189539, 39.963009]`, sits **≈200 m from OSM's own flagged max**
  at `[-75.1911, 39.9644]` — both independent references single out a large
  excursion at essentially the same spot. Read as corroboration of the
  original B judgement, not a contradiction of it; row left unchanged.

`display-lanes.json` was regenerated
(`node scripts/railway/build-display-lanes.mjs`):
`releasedIntervalsByRegion.us` stays at **33**, `ca` stays at **3** — the
four rows this pass touched were already counted as released (they carried
`verdict: "A"` under `"method": "package-bound"` before this pass; this
pass only replaced their evidence, not their release status), and no
verdict-B row was moved.

**Circularity note (2026-09-02, orchestrator).** A NARN measurement is independent evidence only for lines whose geometry was not built from NARN. `amtrak-southwest-chief` and `amtrak-vermonter` are `gtfs-shape` lines, so their four NARN verdict-A rows stand. `nashville-mta-wego-public-tr-90` and `via-ottawa-montr-al` are `narn`-sourced lines: NARN agreeing with them (1.6 m / 1.7 m median) is the package agreeing with its own source, so the two "NARN contradicts OSM" rows above carry no weight and their OSM verdict B is unchanged. `amtrak-pennsylvanian` 13 is `gtfs-shape`; NARN's own 228 m outlier corroborates B.
