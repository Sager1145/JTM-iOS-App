# Keiyo eastern shared passenger representative — 2026-10-11

The visible parallel red strokes came from `jp-東日本旅客鉄道-京葉線#0`
and `jp-東日本旅客鉄道-京葉線-2#0`. Both had zero lane and no follows or
family ownership. The eastern arm used the reviewed midcurve/tail OSM display
survey, while mainline interval 7 retained the earlier sparse N02 survey.

The shared window starts at the actual east fork `[139.9611,35.69164]`
and ends at Minami-Funabashi 003761 `[139.9957,35.681665]`. The independent
northern/eastern approach before that fork remains. The source is stronger
than proximity: raw N02 feature 14135 supplies exactly the same ordered
canonical coordinates on both legs, reversed, and feature 14127 supplies
the same station-clipped final edge. Both records name Keiyo/JR East.
The retained passenger-arm evidence separately records JR East services and
the two passenger arms; sharing display ink adds no physical connection.

`repair-keiyo-midcurve.mjs` now copies the already reviewed arm display tail,
reversed, onto mainline display interval 7, retaining the mainline's remaining
fork-to-Futamata supports. Physical stations, segments and kilometres stay
unchanged. Its exported `repairParts` updates only the mainline/eastern-arm
native rows and installs an eastern-arm follow onto the mainline plus one
landlord/one tenant family window. Existing tail replay preserves this later
reviewed stage. Unknown competing geometry/native rows/follows remain review
errors rather than being overwritten.

The mainline part changes from 390 vertices/42965.9 m to
408 vertices/42977.7 m; these are display rulers, not physical mileage.
Eastern arm remains 83 vertices/5418.9 m. Exact follow:

```json
["jp-東日本旅客鉄道-京葉線-2",0,2068.8259884191734,5418.882256176728,"jp-東日本旅客鉄道-京葉線",0,20262.55021173014,16912.493943972582]
```

Derived landlord mainline window is 16912.5–19962.6 m; tenant eastern-arm
window is 2368.8–5418.9 m, group `東日本旅客鉄道:京葉線`. The 300 m handoff
blend remains outside suppression, with both members using the same reviewed
coordinates there. One representative continues into the common station.
Native `MapLineGeometry` partitions family ownership; `RailMapCoordinator`
maps selected landlord ink back to the tenant ruler and restores missing
tenant coverage. Web `rail-network.js` reads the same landlord/tenant rows;
`railmap.js` slices base/family coverage. No renderer changes were needed.

Integration uses current objects, preserving other agents' changes:

```js
import { repairPackage, repairParts } from './app/scripts/railway/repair-keiyo-midcurve.mjs';
const evidence = JSON.parse(fs.readFileSync('app/scripts/railway/keiyo-midcurve-evidence.json'));
const cache = JSON.parse(fs.readFileSync(evidence.source.cacheAbsolutePath));
const candidatePackage = repairPackage(currentPackage, evidence, cache);
const candidateLanes = repairParts(candidatePackage, currentLanes, evidence);
```

Explicit standalone regeneration, when integrating only this repair:
`node app/scripts/railway/repair-keiyo-midcurve.mjs --apply`.
Root owns published JSON integration and shared dependency-reference refresh.
This subtask did not mutate published data, run a build or operate native UI.

Focused verification:
`node --test app/scripts/railway/tests/keiyo-shared-corridor.test.mjs app/scripts/railway/tests/keiyo-display-curves.test.mjs`.
RED confirmed the missing mainline display override. Independent review found
that an early shared-stage return skipped the independent western tail repair;
a second RED reproduced the legal 74-point western baseline surviving instead
of the reviewed 75-point tail. The tail builder now composes the shared stage
with the western tail repair and retains its measured-reference guards.
Final GREEN: 10 tests passed, 0 failed. This covers same-feature evidence,
curve reuse, physical preservation, fork survival, single family owner,
unrelated data preservation and replay idempotence/compatibility. The older
tail native regression locally reconstructs its retained historical baseline;
the shipped 83-point later cache is not its historical tail-stage ruler.

Read-only neighboring risk: western arm `-3#0` also has no follows/family rows.
It shares mainline supports from `[139.95346,35.68953]` through Ichikawa-Shiohama
003870, but its later display tail diverges from the sparse mainline survey.
That is a similar candidate for future bounded ownership review; no western
geometry or ownership was changed here. The even earlier passenger-arm replay
still expects its historical 65/74-point caches and no later follows; it is not
a current-stage replay and was not broadened in this repair.

This evidence establishes the bounded data/ownership correction. It does not
certify Apple pixel alignment, precise track-group centring, runtime drawing,
performance or a nationwide result. Root's native review remains separate.
