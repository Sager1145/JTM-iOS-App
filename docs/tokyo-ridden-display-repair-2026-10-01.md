# Tokyo ridden display repair — 2026-10-01

## Root causes and scope

Akabanebashi–Daimon already has a surveyed curved Oedo interval in the compact
package. The cached 20260704 ride carries 15 source vertices, including an
approximately 490 m connector chord; native dataset loading used it directly
for drawing. Native loading now canonicalizes current cached geometry against
the same complete displayed railway as the cold solve, while retaining every
original source coordinate for mileage/export. Both directions produce the
same 29-vertex curve as Web, including [139.74885,35.65384]. The original
feature is retained in `app/tests/fixtures/tokyo-oedo-cached-route.json` so
regression tests do not require ignored generated sample parts. Historical geometry
bypasses this current-network replacement. The portable helper is
`PrecomputedRouteDisplay.swift`; `RiddenRouteStore` calls it before assigning
part indices. Drawn cache is 26; solver cache stays 25.

The user specified JR Sobu/Yokosuka ridden Shimbashi and then requested an
explicit common map corridor: join south of Yurakucho without a Yurakucho stop,
one conventional Shimbashi circle west of Shinkansen, and one conventional
stroke to Shinagawa. Optional display anchor/interval metadata applies this
convention in Web, Swift display parts, coded interval projection and the
Python native display derivative. Raw Sobu stations/segments/km remain physical
inputs. Render grouping and regenerated follows collapse the shared corridor;
Shimbashi and Shinagawa circle ownership belongs to the surface line. Exact
physical codes select Sobu in both directions. Parent-owned
`TokyoConventionalRouteInference` supplies these identities to eligible old
records before cache digest/solve; `normalizedTrain` calls that helper.

## Southern topology

The existing N02 drawing shares the corridor south of Shinagawa, splitting
Tokaido at [139.73762,35.62049], then Yamanote vs Hinkaku at
[139.7328,35.61677]. The missing Osaki–Nishi-Oi edge is supplemented using two
independent directional OSM surveys (2.521/2.509 km; 97/95 interval vertices),
with exact station projection anchors. No via-Shinagawa triangle or invented
passenger junction is used. Source sections/station memberships receive only
2/4 new rows, idempotently. See `tokyo-southern-branch-audit-2026-10-01.md` for
provenance and freight north-junction coverage. Station-free surveyed display
parts remain independent of route/mileage edges. The full 99-vertex / 3.360 km freight main remains in the evidence. Its
previously uncovered display portion uses 41 vertices / 1.465 km, joining the
reviewed N02 Megurogawa fork [139.7328,35.61677] by a 3.881 m display alias and
the existing Gotanda/Yamanote vertex [139.72321,35.62672] by a 13.012 m alias.
Both surveyed north fork coordinates remain exact vertices. The display part
stays entirely south of Shinagawa and does not create a second conventional
stroke to Shimbashi, Osaki passenger membership or any physical routing edge.

## Verification

- `node --test app/tests/tokyo-platform-approaches.test.mjs`: 10 pass, including
  exact NEX both directions, single conventional circle west of Shinkansen,
  physical source preservation, cached Oedo source preservation and branch
  lead-in continuity.
- `python3 -m unittest discover -s app/scripts/railway/tests -p test_tokyo_southern_branches.py -v`:
  5 pass, source gap rejection and independently directed evidence included.
- `swift test --build-system native --package-path ios/RailKit --filter 'PrecomputedRouteDisplayTests|RailIntervalCodeTests|RailValidityTests|StationDisplayParityTests'`:
  28 Swift Testing cases plus 14 XCTest cases pass. Final StrokeRide matching
  against all displayed chains and Shimbashi approach angle below 2° pass in
  both directions. Core tests use no Simulator or full app build.
- `python3 -m unittest discover -s app/scripts/railway/tests -p test_display_network.py -v`: 69 pass.
- `node app/scripts/build/build-port-fixtures.mjs --only=station-display.json --check`: passes.
- `node app/scripts/railway/build-display-lanes.mjs`: succeeds. Existing six
  unresolved landlord span warnings remain outside Tokyo; 11 service-status
  exclusions remain intentional.
- `python3 /tmp/jtm-build-final-jp.py` (imports the production builder and temporarily sets `REGIONS=("jp",)` before `build(..., history_dir=app/data)`; production builder is unchanged):
  succeeds, Japan only. This temporary validation derivative is a snapshot;
  the final bundle derivative must use the final frozen canonical inputs. A prior package snapshot hash differed; this does not identify a writer or prove it was still active.
- `python3 ios/tools/verify-train-timetable-artifact.py`: initially snapshotAligned
  true (database hash 897061be75c20cf9e5a1739455440383daf831dc7996559f0ff25a789f3805fb),
  but a subsequent verification found source_hash stale against the then-current inputs.
  The unified data writer must rebuild after freezing the final source inputs.

Station circle aliases remain logical popup/route members. Swift now suppresses
same-display-anchor aliases during label election, matching Web for all regions
and allowing independently authored alias policies such as Tobu.

## Resource refresh and incomplete gates

`ios/copy-rail-packages.sh` regenerates `rail-display-network`, copies current
source files, checks/rebuilds the timetable database, and generates
`rail-resource-revisions.json`. Exact timetable regeneration commands are
`python3 ios/tools/build-train-timetable-db.py` and
`python3 ios/tools/verify-train-timetable-artifact.py`; canonical DB is
`app/data/train-service-history/derived/train-service-timetable.sqlite`, mirrored
at `ios/RailKit/Sources/RailCore/Resources/train-service-timetable.sqlite`.

Package/sections/stations source hashes changed. Existing progressive samples
must be re-solved with `cd app && node scripts/build/precompute-train-parts.mjs`
and the Tokyo special sample environment from package.json. Old geometry must
never be restamped to current source hashes. Native source-hash attestation
rejects stale precomputes and cold solves. Resource fingerprints retire old
runtime routes; the drawn cache change also retires old drawn geometry.

No App/Simulator build or visual acceptance was performed here. The unified
native validation chat owns that slot. It must check network and ridden routes
at Tokyo, Yurakucho south, Shimbashi, Shinagawa, Osaki and Hebikubo/Nishi-Oi;
ordinary legacy no-codes rides and NEX, forward/reverse, cold and cached.
MapKit final simplification/lane placement remains INCOMPLETE until inspected.

## Frozen input hashes

- `app/public/rail/jp-2025.json`: `64d81583f3b690e2b3a13685ebfaf59aa52ea646f9f2e1a80e6c5062b921a27a`
- `app/public/rail/display-lanes.json`: `20800986effcf11ea63784a3da910538fa20ee57aeab746ef7cfdcd778e7a562`
- `app/public/rail/jp-render-groups.json`: `24207b838923480095f8fa57f93af215ef1cebb18d250922aa91defc5d4d11e1`
- `app/data/rail-sections.json`: `88bb7fa1fb4c90c5618bce0349fa97cb54a3eba7f2a641108f24d064adde659b`
- `app/data/stations.json`: `ed699b044ad53327c080d862a40c256a84256e104a5dd8274a209ff575b75dd5`
- `app/scripts/railway/repair-tokyo-platform-approaches.py`: `b87c05502103a4f3f78eabddf0c86b6cd6552b664a67d230255ee7cd87f0ffdd`
- `app/scripts/railway/repair-tokyo-southern-branches.py`: `71aa528c601d0b9f9d2194514c5938897d543d3a6c505e8072c2ef4e49124f91`
- `app/scripts/railway/tokyo-southern-branches-overrides.json`: `9aa04bb9da09c04296ba1dd22f94ecea824aa9919516433969d5b59b6d6da45b`

Physical stations/segments snapshot SHA256 (display-only final alias integration before/after equal): `7e7067561aabcbf587f201e97bfc78307df92df562b655cf9e719566031cba5a`.

Final Japan-only derivative `/tmp/jtm-final-jp-display/manifest.json` matches frozen
JP package SHA256 `64d81583f3b690e2b3a13685ebfaf59aa52ea646f9f2e1a80e6c5062b921a27a` (657 line rows / 10,222 displayed circles).

## File ownership handoff

This geometry task changed these files (including the bounded southern worker):

- Runtime/display: `ios/RailMap/RiddenRouteStore.swift`,
  `ios/RailKit/Sources/RailCore/PrecomputedRouteDisplay.swift`, `CompactPackage.swift`,
  `DisplayParts.swift`, `RouteFeature.swift`, `RouteGraph.swift`, `StationDisplay.swift`,
  `app/public/rail-network.js`.
- Compact/source/metadata: `app/public/rail/jp-2025.json`, `display-lanes.json`,
  `jp-render-groups.json`, `jp-2025.sources.md`, `app/data/rail-sections.json`,
  `app/data/stations.json`. Existing source objects outside the 2 sections /
  4 memberships are preserved by the supplement; no English catalog edits.
- Repeatable transformations/evidence: `app/scripts/railway/build-display-network.py`,
  `repair-tokyo-platform-approaches.py`, `repair-tokyo-southern-branches.py`,
  `tokyo-southern-branches-overrides.json`.
- Regression: `app/tests/tokyo-platform-approaches.test.mjs`,
  `app/tests/fixtures/tokyo-oedo-cached-route.json`,
  `app/scripts/railway/tests/test_tokyo_southern_branches.py`,
  `ios/RailKit/Tests/RailCoreTests/PrecomputedRouteDisplayTests.swift`,
  `RailIntervalCodeTests.swift`, `RailValidityTests.swift`, `StationDisplayParityTests.swift`,
  `port-fixtures/station-display.json`.
- Reports: this file and `docs/tokyo-southern-branch-audit-2026-10-01.md`.

`build-display-lanes.mjs`, timetable facts/databases, other country packages,
English catalogs and parent-owned automatic-inference/editor files were not
edited by this geometry task. Existing work in the dirty tree is retained.
The lane builder was run against the current tree; this is regeneration of the
shared derived artifact, not ownership of unrelated builder changes.
