# Original CRTrainRoute comparative replay

Source: [Laide140/CRTrainRoute, pinned commit d75307d](https://github.com/Laide140/CRTrainRoute/tree/d75307df9c812abf1259b86b75202ba7b0048679).
The local checkout is `/tmp/jtm-crtrainroute`. Its committed `server.py`,
`build_graph.py`, graph artifact, station JSON inputs and license match the pinned
Git blobs; SHA-256 fingerprints and sizes are retained in
`baseline-acquisition.json`. Reproduce acquisition with a checkout of that exact
commit, including its committed `data/rail_graph.pkl`; a new graph build is not
needed and would be a distinct baseline.

The bounded replay interface is
`app/scripts/railway/compare-crtrainroute-baseline.py`. It imports the exact original
server module and calls its original `RailService.route` implementation. Original
station input resolution, snapping to the largest graph component, CSR search,
geometry reconstruction, nearby-station inference, cache, warnings and ferry
annotations remain in use. There are no distance targets or route repairs.

The graph transport is changed only for safe comparative reading: an opcode
preflight permits primitive containers/scalars and rejects object construction,
globals, reductions, extensions and persistent references. A restricted unpickler
additionally forbids every global and persistent lookup. This isolated original
artifact is not production input. The original graph constructor and index builder
then run unchanged against the primitive data.

The default station transport is explicitly **offline retained station JSON**.
The original API normally POSTs to the 12306 station address endpoint at query time;
the replay returns the unchanged raw latitude/longitude from the same commit's
`data/stations.json`, mapping its `addr` field to the API's `address` field. It does
not relabel that result as a current live API observation. No coordinate conversion
is performed. Upstream's declared station GCJ02 / railway WGS84 discrepancy is
retained as part of the baseline. Missing coordinates are failures, not filled from
Railmap or a different source. The live request details and a bounded connectivity
probe are retained separately in `baseline-live-probe.json`.

Each input case has `id`, `from`, `to`, optional `knownStops` (ordered station codes
or original station names), and any train/source metadata the collector needs to
retain. The comparator preserves that full input and every full original response,
including geometry, inferred intermediate stations, snap offsets, warnings, ferry
segments, distances and elapsed time. Results are written after each completed
case so an interrupted batch retains explicit partial evidence.

Two modes are deliberately distinct:

- `endpoint-only`: one original API call from the real train's first to last station.
- `forced-known-stops`: one original API call for each consecutive pair of the
  supplied actual stops, including endpoints. This is a comparable stop-constrained
  diagnostic, not an upstream through-train service API. Its distance summary is
  only the sum of successful legs; all-leg success is explicit and partial totals
  are not complete journey distances.

Use Railmap endpoint-only input for the first comparison and the same known stops
for the second. Published service stops establish train identity/order but may not
uniquely identify every parallel physical track. Neither an original successful
shortest path nor proximity-derived stations prove an actual train follows it.
Upstream automatic island links and ferry guesses remain visible in results; they
are not independently verified railway connections. In particular, do not suppress
the upstream ferry label to improve agreement with real railway evidence.

Example invocation (one manually selected research batch, not an automatic gate):

```sh
python3 app/scripts/railway/compare-crtrainroute-baseline.py \
  --original-source /tmp/jtm-crtrainroute \
  --input /absolute/path/to/real-train-cases.json \
  --output railway-sources/local/china/comparisons/real-trains-20261018/original-results.json
```

The `--inspect-only` option verifies acquisition fingerprints without loading the
graph. `--load-only` runs original graph loading/indexing once and records graph
counts without running any station pairs. Coordinate/station cardinalities are
observations of the committed graph artifact, not README estimates.

Focused loader verification: a primitive protocol-4 structure round-tripped; a
GLOBAL/REDUCE payload and trailing pickle data were rejected before deserialization.
Original graph loading/indexing succeeded on 2026-10-18. Route outcomes belong to
the later actual-case batch and are not implied by successful graph loading.
An adapter-only stub also checked one endpoint call versus two consecutive-stop
calls, summed successful-leg distances and exact warning retention; that check is
not counted as a real-train case. A network-enabled original coordinate request for
IZQ returned HTTP 502 Bad Gateway, so the probe acquired no live coordinates and
does not establish permanent endpoint availability or unavailability.
