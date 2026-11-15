# Stroke bake fixtures

`stroke-network.json` is a selection of real builder output (all of hk and mo, 43 jp lines chosen for
follows, family windows, lanes, branch boundaries and a Tokyo junction window) plus two synthetic jp
chains that carry what shipped data does not: withheld spans, a landlord and a tenant family window and a
follow. `make-stroke-network-fixture.py` regenerates it from a `build-display-network.py` output
directory.

`stroke-golden*.deflate` is what the engine drew from that fixture BEFORE it left the app target.
It was captured on 2026-11-12 from `ios/RailMap/Map/MapLineGeometry.swift` at commit
`d1d20e8c9` (the verbatim copy is `golden-capture/OldMapLineGeometry.swift.txt`), by the throwaway
package whose sources are the other `golden-capture/*.txt` files (rename and build with
`swift build -c release`, run with the fixture and an output directory). The package stubs only what the
app target supplied around the file (`DrawnLine`, `RailStyle` tokens, `Region`, the signpost); the engine
code itself is not edited.

Recaptured 2026-11-14 (merge of main `1ebca6ee0` into `claude/pack-budget-30`) with the same package, the same
`OldMapLineGeometry.swift` and the same fixture, built against the merged RailKit. The only difference from the
2026-11-12 capture is `ContinuousStroke` itself: main's `bb65bbd8c` decimates curved continuous strokes to the stroke
tolerance (`RailStrokeTokens.simplifyTolerance`, so fewer vertices and fewer 128-vertex chunks), which
changes every curved stroke, runs, chunk and `parallelLaneCoordinates` entry (6,461 entries now, 7,277 before; no key
was added, 816 chunk keys vanished with the decimated vertices). The unmoved app code path is unchanged by that
commit apart from the screen-space thinning the app adds after this engine (`ScreenPolylineThinning`, applied only
through `StrokeBake.prepareLines(thinStepPx:)`, which these goldens do not pass), so the goldens still pin the moved
engine against the app's own engine. This is a deliberate, explained pin, not a regeneration to silence a failure.

Recaptured 2026-11-15 on `StrokeProjection` (the projection RailCore uses) instead of MapKit's. See "Projection" below.

## Projection

The 2026-11-12 and 2026-11-14 captures projected with MapKit (`MKMapPoint`, `MKMetersPerMapPointAtLatitude`), RailCore
projects with `StrokeProjection`. The two agree to under 1e-6 map point, but the stroke decimation is greedy and keeps
or drops a vertex on a threshold, so a vertex that sits on the threshold within that noise is kept by one and dropped by
the other. After main's curved-stroke decimation (`bb65bbd8c`) this showed as 17 drawn chunks, all at z17, picking a
different but equally valid vertex, plus the three fingerprints (runs, points, measures) of one stroke that follow from them. The merge `aedec43fa`
loosened the equality test to accept that; that loosening was rejected and removed.

Proof that projection noise was the whole difference: the capture was run twice from the same sources, once as is
(MapKit) and once with `golden-capture/StrokeProjectionShim.swift.txt` added, which declares `MKMapPoint` and
`MKMetersPerMapPointAtLatitude` in the capture module so the unedited `OldMapLineGeometry.swift` runs on
`StrokeProjection`. The MapKit run reproduced the committed golden byte for byte (so the capture is reproducible), and
against it the unchanged strict test failed 17 z17 chunks (two with a different vertex count) and the fingerprints of
`jp-阪急電鉄-今津線-2#0`. The shim run is what is committed now; against it the strict test (every entry, vertex for vertex
within 1e-4, fingerprints within 1e-9) finds a worst difference of exactly 0.0 over all 6,461 entries. Nothing else in
the capture changed: same `OldMapLineGeometry.swift`, same fixture, same RailKit (`aedec43fa`). The only other edit to the
package is `MapKit.MKMapPoint` in `Stubs.swift.txt`'s off-screen rectangle helper, which stays on MapKit's type because
`MKMapRect` takes it; it does not touch any recorded value.

What independence remains, honestly: the golden pins the moved engine's app-side glue against the app's own pre-move
code, that is what `OldMapLineGeometry.swift` does around the engine (chain joining, windows, chunking, family and
fallback runs, anchors, lane probes, the order of everything). It does NOT pin the projection arithmetic (shared with
the code under test now), and it never pinned `ContinuousStroke` (the capture calls the same RailCore engine, which
is why the 2026-11-14 recapture was needed). Drift relative to MapKit is caught by `StrokeBakeMapKitReferenceTests`
(the engine's own output vertices projected by `MKMapPoint` against `StrokeProjection`, and a lane-0 parallel line's
end vertices against the MapKit projection of the source ends, both within 1e-6 map point) and by
`StrokeProjectionParityTests`. To recapture: put the capture package's `.txt` sources (without the `.txt`) in
`Sources/GoldenCapture`, point its `Package.swift` dependency at the RailKit checkout, `swift build -c release`, run with the
fixture and an output directory, raw-DEFLATE the two outputs.

Format: `stroke-golden-index.json.deflate` is `{entries: [{k, n, o}]}` (key, double count, double offset);
`stroke-golden.f64.deflate` is the little-endian Float64 array those offsets index. Both are raw DEFLATE.
Coordinates are map points (`StrokeProjection` of each coordinate; MapKit's before 2026-11-15). Large arrays (stroke points, measures, solid
runs) are stored as `[count, sum, weighted sum, scaled sum of squares]` fingerprints.

Levels (app zoom, 256-point convention): 5, 8, 10.5, 13, 17 plain; 8 and 13 again with a "dated" part style
(part % 3: 0 solid, 1 historical, 2 hidden). Do NOT regenerate the goldens to make a failing test pass: a
difference is a behaviour change in the engine and has to be explained, then pinned deliberately.
