# Core 2 — full iOS audit evidence

Cumulative scope and parent-adjudicated priorities are in the [main audit](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11.md). Local reviewer IDs refer to this evidence file only. Source review does not establish an executed pass.

## Confirmed correctness finding

### C3 — [P2] Timetable completion invents ridden subintervals inside an unmarked interval

Primary: [ios/RailKit/Sources/RailCore/Import/JourneyCompletion.swift:695-703](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Import/JourneyCompletion.swift:695) (especially `:703`).

Scenario already represented in the existing test: Alpha has rideSegment true, Omega false. [JourneyCompletionTests.swift:25-35](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Tests/RailCoreTests/JourneyCompletionTests.swift:25) constructs those flags. Before expansion, `Statistics.isRideSegment` at [Statistics.swift:1884-1885](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Statistics/Statistics.swift:1884) requires both effectively-ridden endpoints, so Alpha–Omega contributes zero ridden intervals. A sourced completion inserts Beta and Gamma between them. `sourcedIntermediateStops` at [JourneyCompletionTests.swift:150-167](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Tests/RailCoreTests/JourneyCompletionTests.swift:150) supplies ordered valid times and currently pins the new Beta flag to Alpha's true flag.

Trace: insertion reads only the preceding call's flag, then repeats that inheritance for subsequent calls in the same original gap. The resulting flags are [true,true,true,false]. Alpha–Beta and Beta–Gamma now count as two ridden intervals, although no rider confirmed either interval. The original stops remain byte-for-byte value-equal; preserving original flags alone therefore does not preserve rider meaning. This also affects ordinary partial rides: completion can extend a ridden region from its true endpoint into a following false interval.

Contract: [RideLedger.swift:18-24](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailPresentation/Journeys/RideLedger.swift:18) states nothing enters the passport unless the reader said they did it; `:55-64` explicitly defines countable riding over intervals rather than isolated flags. `RideLedger.riddenSegmentCount` at `:90-99` now turns the formerly .notRidden record into .partly. The integration ledger's current Only confirmed rides row (`docs/reports/integration/feature-parity-ledger.md:319-320`) adopts that constraint.

Current user path: [JourneyCompletionView.swift:439-444](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/JourneyEditor/JourneyCompletionView.swift:439) merges this result into the proposal; Apply at `:290-292` returns it to the draft. Preview for inserted calls (`:489-510`) lists station names/times/identity needs but does not disclose a ride-state change. The user approves timetable facts, and later saving the draft also saves inferred riding. A native completed route/station resolution is still necessary for new mileage; this source finding establishes changed rider confirmation and admitted intervals, not a measured numerical mileage/capture result.

Action: derive new call ride flags from the effective original interval's rider state, preserving no-ridden-subintervals for a false original interval; require explicit rider editing to extend that state. Preserve pass-through effective semantics as well as plain stopping calls. Extend the existing completion regression to assert effective interval masks before/after, including true→false, false→true, all-false, all-true and pass-through cases. Existing test :167 currently asserts the problematic implementation rather than the rider invariant.

Confidence: high from current deterministic branches and the existing fixture; no execution.

## Product semantics lead — do not automatically classify as a defect

### L2 — Ride time is a first-to-last span while mileage follows individual intervals

Primary: [Statistics.swift:1894-1907](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Statistics/Statistics.swift:1894); app consumption: [PassportStatistics.swift:200-205](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Statistics/PassportStatistics.swift:200), [MileageStatisticsStore.swift:957-961](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Statistics/MileageStatisticsStore.swift:957). Web counterpart: `app/public/app-stats.js:759-772`.

A valid per-stop edit may produce A/B true, C false, D/E true. If A departure is 09:00, B arrival 09:10, D departure 10:00 and E arrival 10:10, ridden intervals are A–B and D–E (20 minutes between their boundary times), but trainRideMinutes returns 70 minutes. The B–D gap was unmarked; mileage excludes it. StopEditorView:346-351 allows independent flags and Train.validateStop:1020 checks boolean type, not contiguousness.

However, Statistics.swift:1889-1893 and app-stats.js:755-758 explicitly document the first-to-last stopping-call span, including the chosen arithmetic. This is presently the written metric contract. No inspected product requirement explicitly mandates summing durations of separate rider islands or excluding waits. StatisticsParityTests:833-848 checks the same JS-derived values. Do not call this a confirmed P2 merely because elapsed span differs from summed train time. Product decision needed: retain and name elapsed ridden span, or change the metric to summed contiguous ridden stretches. If choosing the latter, exercise a partial multi-island record with exact arithmetic and retain dwell time within each ridden stretch.

## Architecture judgments

### A3 — Route certification provides depth; its evidence level must stay explicit

RouteSolver owns dated endpoint recovery, multiple scoped attempts, source-to-physical graph certification, reviewed junction/OSM chain traversal and provenance. The interface returns supported coordinates/raw physical keys. Physical traversal excludes passenger connector edges by default (`:12-18`, `:3866-3874`), solvedSection rejects any connector (`:3490`), and verifiedSourcePath requires reviewed physicalContinuationPath or surveyed sameIdentitySpanPath between parts (`:2122-2130`). These are useful internal seams. Deleting this proof would redistribute its knowledge to editors, caches and rendering callers. Its size alone is not a refactor finding.

This full review supports the prior C1 distinction: a permissive planner candidate is not a certified route. No incorrect Tokyo solver geometry or mileage was proved here. Keep proposal/display relationships separate from final physical proof rather than spreading special cases into callers. No race, memory or latency assertion follows from source inspection.

### A4 — Completion's small merge interface earns depth, but generated calls need a rider-state invariant

`merge(response:into:)` confines strict JSON keys, evidence format, existing-value conflicts, stop references, chronology and section expansion behind one interface and returns a value without mutating the caller on error. It correctly refuses insertion when existing physical sectionCodes would require an unreviewed split (`:1257-1260`). C3 shows a missing cross-domain invariant: timetable call insertion changes the interval rider facts. Test the merge interface against the effective riding contract, not only copied stop fields or JS parity.

### A5 — StationJoinSmoothing exposes an unfinished port seam, not a current rendering verdict

Its own documentation (`:51-66`) says required sourceLines cannot be recovered from the OverlapLanes result and adding that source owner field was deliberately deferred. A current production-source search found smoothCurveStationJoins only as the definition and OverlapLanes documentation references, not a native production call. The module's tests/public helpers may be useful parity inventory, but neither its radius/deviation counters nor geometric pairing establish how the main app renders. Do not report its 120 m geometric joining or broad smoothing as a demonstrated current native geographical defect without a real caller and evidence.

## Dismissed leads / limits

- `completeRouteEndpointCoordinates` can add a station-display chord within 500 m ([RouteSolver.swift:3986-3987](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Routing/RouteSolver.swift:3986)), but current native production search found no caller outside its definition; JS does call its counterpart. This is not established as a native production bug. Native solvedSection keeps graph coordinates at :3490-3503.
- Public arrays/index arguments could trap under violated preconditions (negative curveIndex, inconsistent EdgeIndex array counts), but no current caller/input was shown to violate them. No speculative hardening finding.
- Statistics' retained in-place .current + validTo denominator behavior is explicitly pinned by TemporalEdgeStatisticsTests:95-116; do not relabel it as a discovered retirement denominator bug.
- SSE completion framing, terminal event handling, key/phase text fallback and model/failure projections were inspected. No evidenced protocol failure in current transport input was established.
- ImportEngine's progressive replacements and final persistence/events were reviewed. Partial replacement behavior and synchronous shell callbacks need caller-specific use before asserting a production loss; none established here.
- No full current resource geographic audit, Apple basemap comparison, runtime, pixel, race/leak or performance measurement was performed.

Result: all seven assigned source reads complete; one additional confirmed rider-state bug C3; L2 retained as a documented metric semantics decision, not a confirmed defect. Parent should integrate with the prior C1/C2/L1 report and other app/core tranches.
