# Johoku Nakaotai display candidate implementation — 2026-10-18

Candidate only; no production apply, native capture or build. One authority `app/scripts/railway/repair-johoku-nakaotai-display.mjs`, one evidence file `johoku-nakaotai-display-evidence.json`, and one focused regression file `tests/johoku-nakaotai-display.test.mjs` implement the approved decoded26..33 window. No generic stage, additional builder or neighboring rail selection was introduced.

The authority recreates paired supports from the two frozen full OSM way responses and their explicit opposite passenger-route memberships:58218285v8/11728676v2 and768955042v7/11728762v3. It requires own operator/name/rail/branch/viaduct/layer1/sourceKSJ2, no service tag, exact route names/versions/member indices, and all referenced versioned node coordinates. Both entire retained source files and their memberships have exact UTF-8 byte guards. Union-longitude interpolation between these two positively identified tracks reproduces the frozen pair supports exactly. Original26/33 are retained; the projection only selects interior supports, so no short transverse boundary connector is inserted. Source KSJ2 ancestry and reverse-route malformed/missing tags remain explicit limitations.

Only own display interval1 is installed. Physical stations/segments/km, station IDs005319/005303, exact original boundaries26/33, outside25/34, other intervals and other lines are retained. No station display alias is created. The 8 old window controls become38 controls,36 interior pair supports. The existing source concern outside the window and other whole-line lateral/terminal leads remain pending.

## Native/dependency audit

Actual current native cache contains one plain own part `[lineID,0,0,4,119,11264.3,null,null,[]]`. Existing `partRowsForLine(line, network.displayPartsForLine(line))` regenerates it as one embedded `complex` fallback part: **149 controls,11,267.7m**, withheld spans[]. Rounded native ruler increases3.4m. No groomed geometry was hand-cloned or separately reconstructed.

The targeted full-lane-record query found no own byRegion/follows/family/released/loop/reversed-loop/stroke-exclusion/chain-boundary/hub member. Accordingly only partsByRegion is changed; there is no measured lane/follow/hub reference to remap. Guards preserve that concrete absence, including follower leader field4, loops objects `.lineIds`, reversed-loop string keys, and hub `.members[].lineId`. External `shared-corridors.json`, `jp-render-groups.json`, `display-chain-boundaries.json`, `display-hubs.json` also contain no own reference; CLI snapshots their exact bytes and refuses a new own dependency without review. No unrelated rulers are changed.

JS `rail-network.js` displayLineForCoordinates consumes only the display interval override. Swift `CompactPackage.decodeDisplayIntervals` consumes the same override then welds original station endpoints. No shared schema/identity change is needed. The production resource copy/native final lane/station-circle result is not measured here. Existing dependency-reference refresh prepares the established package-name reference files through the same CLI, without a new reference scheme.

CLI preparation freezes exact package/lanes/dependency/evidence/source/external bytes and checks them before candidate writes. The existing `applyPreparedWrites` helper handles the same snapshots if parent later authorizes application; it was not invoked here.

## Focused evidence

Initial TDD run failed because the new authority did not exist, recorded in `/private/tmp/jtm-johoku-nakaotai-red.log`. After implementation **5/5 focused tests pass,0 failures,86.399ms**, `/private/tmp/jtm-johoku-nakaotai-green.log`:

`node --test app/scripts/railway/tests/johoku-nakaotai-display.test.mjs`

Tests assert exact frozen supports,26/33 and physical/station/source/km preservation, idempotence, byte/route refusal, removal of the northward chord control, bounded joins under2.21°, native149/11267.7 through existing generator, unchanged native prefix/suffix outside Owari-Hoshinomiya→Otai, unrelated row retention and measured-dependency refusal. This is source/derived-data correctness evidence, not visual acceptance.

Candidate export succeeded via this same authority:

`node app/scripts/railway/repair-johoku-nakaotai-display.mjs --candidate-root /private/tmp/jtm-johoku-nakaotai-candidate-20261018`

Export log: `/private/tmp/jtm-johoku-nakaotai-export.log`. Candidate package and lanes are in that directory. No apply/native/build occurred. Parent original candidate review remains required; other sustained-offset and station/terminal leads are not marked resolved.
