# Ride overlay batching and the road to a segment graph (2026-11-05)

Branch `claude/map-overlay-batching-556ec2`. Stays on MapKit (ADR 0002 rejected
MapLibre; ADR 0006 rejected per-interval SwiftUI `MapPolyline`).

## What landed

- **Tap index kept across rebuilds.** `RideTapIndex` is invalidated only when the
  tap geometry signature moves (network frame key plus the stroke generation of
  every ride-referenced, stroke-resident chain), or at the existing ride,
  category, index, stroke-ref and line-input sites. It is prebuilt 300 ms after
  invalidation, never during a gesture. The snapshot is taken on main and the
  chunk index is built off main. A tap that beats the prebuild still builds
  synchronously (`map.tapIndex.build`; the prebuild is `map.tapIndex.prebuild`).
- **Withheld-run polylines cached per frame**, so `network-withheld|*` batches
  keep their identity and stop cross-fading on every rebuild.
- **Ride overlays batched.** Non-selected rides share one `MKMultiPolyline` per
  `rides|<kind>|<in|off>|<#COLOUR>|c<cell>`. `cell` is a stable 16×16
  world-grid shard of the ride's full bounds, so a pan or one ride change only
  re-forms its own shard. The selected ride keeps its per-ride cores and
  casings on top. Coordinates, chunking and dash phase are unchanged.
  Hit-testing stays per ride (`RideTapIndex`), independent of overlays.
  The planner is `RideOverlayBatching`, and it takes the visible ride set as
  input, so it is agnostic to the display cap and the hide filters.
- **Rebuild trigger signposts** (`map.rebuild.trigger` codes 1–7, `map.matching`)
  to measure why a cold load rebuilds.

Accepted visual changes are documented on `RideOverlayBatching`:
- Overlapping dimmed rides in one batch no longer compound alpha.
- Stacking is by kind, scope, colour and cell rather than deck order.
- A new pick stays dimmed with its batch until its full rebuild.

## Not done

- **NetworkLOD clip-before-decimate.** Skipped. It would make line builds
  depend on the build rect, so every pan would re-prepare and re-identify every
  network batch and break ride stroke slicing. The 38,698 / 40,000 worst case
  predates per-interval and per-chunk culling. Re-measure first. If the budget
  is tight, shrink the unpatterned `mapCoordinateChunks` stride instead.
- **Rides-only update path for partial publishes.** Designed but not built.
  Each publish costs 2–3 full rebuilds: the immediate one, stroke-ref match
  completion, and geometry-prep completion. A rides-only pass would still run
  `buildMarkers` over every ride, so read the phase split from the new trigger
  signposts before building it. Marker-phase caches keyed by `linesGeneration`
  (audit item 4) are the likely bigger lever.

## Option 2, later: deduplicated segment graph with count encoding

Batching groups ride polylines but still draws each ride's copy of shared
track. On a corridor ridden 40 times that is 40 identical slices of the same
frame stroke. A segment graph would build on this branch as follows:

1. **Key.** Every drawn ride slice is already a range on a frame stroke
   (`StrokeRef` chain id plus measures) or a fallback raw polyline. Normalise
   the stroke ranges into atomic intervals per chain (split at every ride's
   endpoints on that chain) and key each interval by
   `(chainID, from, to, kind, scopeClass)`.
2. **Count.** For each interval, count the visible rides covering it and keep
   their ids. Draw one polyline per interval, not per ride, and encode the count
   in style. The batch key then becomes `colour × kind × scope × count-bucket`
   (for example 1, 2–3, 4–7, 8+) with a width or alpha ramp, replacing today's
   `cell` shard. This also restores a controlled form of the lost alpha
   compounding.
3. **Colour.** Shared intervals ridden in different ride colours need a rule:
   majority colour, the network line's colour, or a neutral "ridden" colour.
   That is a product decision and the main blocker.
4. **Hit-testing.** It stays on `RideTapIndex` (per ride). The interval-to-ride
   ids map can later back a "rides on this segment" list.
5. **Cost.** Vertex count scales with distinct track ridden, not with rides.
   Rebuild work moves to an interval build keyed by the ride set's stroke refs
   and the frame key, which can live in `MapNetworkGeometryCache` beside the
   ride polylines.
6. **Unchanged.** Fallback (non-stroke) segments, the selected ride's own
   overlay and casing, and playback (`MapPlaybackLayer`).
