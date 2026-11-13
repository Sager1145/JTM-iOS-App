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

Format: `stroke-golden-index.json.deflate` is `{entries: [{k, n, o}]}` (key, double count, double offset);
`stroke-golden.f64.deflate` is the little-endian Float64 array those offsets index. Both are raw DEFLATE.
Coordinates are map points (`MKMapPoint` of each coordinate). Large arrays (stroke points, measures, solid
runs) are stored as `[count, sum, weighted sum, scaled sum of squares]` fingerprints.

Levels (app zoom, 256-point convention): 5, 8, 10.5, 13, 17 plain; 8 and 13 again with a "dated" part style
(part % 3: 0 solid, 1 historical, 2 hidden). Do NOT regenerate the goldens to make a failing test pass: a
difference is a behaviour change in the engine and has to be explained, then pinned deliberately.
