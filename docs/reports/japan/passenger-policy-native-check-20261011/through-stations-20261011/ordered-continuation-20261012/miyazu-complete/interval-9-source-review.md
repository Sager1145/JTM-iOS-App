# Miyazu #9 false dip: explicit own passenger source

2026-10-18. Source-only bounded research of 与謝野004390→京丹後大宮004291, decoded4 [135.12226,35.54194]. No builder, app/native, tests, capture or production/code edit. Other leads remain pending. Existing237 valid retained receipts are unaffected; no full recapture proposed.

## Exact source ownership

Current physical source is app/data/rail-sections.json zero-based feature19817, LineString135 controls, N02_00112/N02_0025/N02_003宮津線/N02_004WILLER　TRAINS (U+3000). Feature-coordinate3 is decoded4; source135 interior controls plus two station endpoints produce decoded137. The false dip includes decoded4→5, a very short east/west edge, then supports6..8 returning through the real broader curve. Physical source, station IDs/coordinates, stored mileage and route topology are retained.

Cache: railway-sources/local/osm/degree-cells/E135N35.json, fetched2026-08-18T10:31:02.971Z. Exact own cached way32052922 has KSJ2:LIN宮津線, name京都丹後鉄道宮豊線, operator京都丹後鉄道, gauge1067, usage main, railway rail and no service tag. It runs east→west from[135.1254822,35.5430149] to[135.114724,35.5402475], entirely spanning the local window. Station sidings/yard ways were excluded. No nearest-glyph/nearest-unrelated-track selection or averaging was used.

Fresh exact-object API evidence: [way32052922/full](https://api.openstreetmap.org/api/0.6/way/32052922/full.json) is version10, timestamp2023-02-28T14:26:49Z; live node geometry exactly matches the cached way. [Its route memberships](https://api.openstreetmap.org/api/0.6/way/32052922/relations.json) establish explicit passenger ownership:

- Train route6015174 v45,2025-05-02T20:59:10Z, 宮津→豊岡, name京都丹後鉄道宮豊線, own way at member47 (zero-based), local chain32052917→32052922→1044465731.
- Complete train route19072502 v3,2026-08-25T15:32:32Z, 西舞鶴→豊岡, own way member117, same local sequence.
- Reverse train memberships12030454 and19072511 also include this exact way. Railway relation1867927 additionally identifies the physical line.

The [operator's current timetable](https://trains.willer.co.jp/timetable/) and [official2026 Miyamai/Miyatoyo timetable](https://trains.willer.co.jp/wp-content/uploads/2026/03/7eb4a7127d6f3457a77f651ae1fcc433.pdf) identify the passenger corridor including adjacent 与謝野 and京丹後大宮. Miyatoyo is the branded western portion of the package's legal宮津線; Miyafuku is a different branch and is not used here. This source has KSJ2 ancestry, so it is an explicit own passenger display reference, not independent surveyed centre proof.

## Frozen candidate fragment

interval-9-candidate-fragment.json contains the exact old compact row, full old137 decoded coordinates, N02 feature, versioned own reference and candidate141 coordinates. Replace decoded3..9 inclusive (7 old controls) with11 own-way controls; retain raw decoded2 [135.12482,35.54285] and10 [135.11942,35.54168] as outer guards and preserve every outside support. Do not reverse way32052922.

Boundaries are frozen using jp-manual-corrections/geo.mjs projectPointOntoPolyline against this identified way only:

- Original3 [135.12334,35.54232]→[135.12336036546765,35.542281276792316],4.6835m.
- Original9 [135.12024,35.54184]→[135.12024906069036,35.541795576634925],5.0072m.

The source supports between these projections follow the real gradual curve and remove the locally reversed/shallow dip; no station/platform face is approached. Outer joins span146.59m and76.19m. Entry/exit/next-guard heading changes are2.42°,0.30°,3.37°; maximum local candidate heading change4.67°, versus23.38° at the old dip. The closer-ending3..7 alternative creates9.36°/11.90° join bends, so3..9 is the smallest evaluated coherent window that avoids shifting the dip into the western splice. The window remains localized to this one curve; station departure and broader neighboring alignment are retained.

These values describe coordinates, not pixel residuals or acceptance. Candidate rendering must inspect the curve body and both joins before application. No builder or native part/ruler computation is done in this research phase.

## Retained evidence and limits

Original pixel finding is captured in BatchEvidence/captures/000040/000001/{basemap.png,smooth.png}, already actually reviewed. The native/map scene shows a shallow red trough against a gentle blue curve. Matching retained receipts support the old inputs only; no proposed pixels exist yet. Versioned identified API JSON, the exact own cached way and calculation are retained under interval-9-source/. No other local lead or Miyafuku worker report was changed.

## Source implementation and bounded verification

Implemented one local authority app/scripts/railway/repair-miyazu-yosano-display.mjs with its evidence JSON and focused Node test file. The own OSM response bytes, way/node geometry, both train-route memberships, raw N02 feature, exact physical baseline, projections and one fragment are frozen. No production apply.

Actual native dependency is one plain interval-backed row: [lineID,0,0,17,1565,83949.8,null,null,[]]→[lineID,0,0,17,1569,83947,null,null,[]]. Miyazu has no lane, follow, family or hub measure to update. Only partsByRegion changes in the lanes document. Existing partRowsForLine computes the row with the same display intervals; no independent native geometry builder was introduced.

Focused TDD observed initial failures, then3/3 passing (136ms): physical/outer/unrelated preservation and idempotence, native part and empty-reference behavior, and rejection of changed source bytes/route/projection/baseline/follow/hub dependencies. Command: `node --test app/scripts/railway/tests/miyazu-yosano-display.test.mjs`.

Candidate export passed: `node app/scripts/railway/repair-miyazu-yosano-display.mjs --candidate-root /private/tmp/jtm-miyazu9-candidate-20261018`. Exported package changes only the own line, physical stations/segments stay exact, and all other lane-document keys remain exact. Existing dependency-reference helper refreshes its four established station-name input references.

Python counterpart reviewed at build-display-network.py3071/3083/3159: source intervals remain separate, explicit displayIntervalCoordinates populate intervals_by_line, and those display intervals feed the native plain-row decoder. A focused own-line query of the existing decoded_intervals/_retain_source_interval/chains_from_parts_rows functions confirmed null embedded geometry still yields the new141-control interval and1569-point/83947m native chain exactly. See interval-9-native-decoder-query.json. No native build or runtime/pixel acceptance is implied; candidate images remain pending.

Follow-up replay review froze the four already-audited empty loop/reverse/stroke/boundary categories. Guards use actual existing shapes: loop objects lineIds, reversed-loop strings lineID#part, and owner-slot0 stroke/boundary rows. The existing stale-reference regression now exercises all four; observed failure before the fix, then affected test1/1 pass147ms. Geometry/ruler/export unchanged; no native/build/apply rerun.
