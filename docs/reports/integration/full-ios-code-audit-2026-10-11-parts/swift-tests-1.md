# Swift Tests 1 — full iOS audit evidence

Cumulative scope and parent-adjudicated priorities are in the [main audit](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11.md). Local reviewer IDs refer to this evidence file only. Source review does not establish an executed pass.

## Findings

### T1 — P2: Concurrent Swift tests read and write unsynchronized fixture caches

Locations: ios/RailKit/Tests/RailCoreTests/FixtureParityTests.swift:308-323 (especially 309 and 315); ios/RailKit/Tests/RailCoreTests/PlaybackParityTests.swift:213-230.

Failure scenario: Swift Testing discovers independent methods in these suites concurrently. FixtureParityTests.intervals and visibilityGrouping both enter package(country:) on a cold or warm cache; one writes Dictionary storage while the other reads it. PlaybackParityTests has many methods calling fixture()/train()/store(), with unsynchronized writes to large optional fixture/store structs while another task loads or reads them. nonisolated(unsafe) removes compiler isolation diagnostics but does not synchronize the operations. The result can be a test-process crash or corrupted state, rather than a trustworthy regression failure.

Evidence: FixtureParityTests has no suite serialization or global actor; intervals() at 215 and visibilityGrouping() at 285 both call Self.package. PlaybackParityTests has no serialization/actor and calls Self.fixture at 391, 428, 521, 591, 670, 703 etc. PortFixtures.swift:77-85 explicitly documents a previous unguarded Dictionary crash under parallel Swift Testing and already supplies a locked package cache; StatisticsParityTests.swift:407-427 separately guards equivalent caches. Playback file was reviewed only through its cache/helpers plus method call inventory, so this finding is scoped to the cache and does not certify its remaining assertions.

Action: Reuse PortFixtures.package for FixtureParityTests; protect Playback fixture/store publication and reads with one lock or use immutable static initialization. Retain production parallelism. No new test suite or broad execution is required to make the defect concrete.

### T2 — P2: Required family-window parity disappears when its fixture is missing

Location: ios/RailKit/Tests/RailCoreTests/FamilyWindowParityTests.swift:123-126.

Failure scenario: A packaging/fixture-maintenance change deletes or relocates port-fixtures/family-windows.json. The only fixture parity method disables itself before loading, and the focused test command succeeds with no partition parity evidence instead of diagnosing the missing required input.

Evidence: The fixture is currently committed and exists (7,222 bytes). The disable reason still says it is awaiting registration by the web agent. This is an old bring-up exception surviving after registration; the normal shared PortFixtures.data helper records a missing-fixture issue and throws. The test otherwise correctly calls production ContinuousStroke.familyPartition and ContinuousStroke.slice, and compares to independent web-generated emittedPieces. Other synthetic family tests do not restore this exact web parity coverage.

Action: Remove the conditional disable and let the existing loading path fail for a missing fixture. This preserves the focused existing parity test without reinstating any retired runner.

### T3 — P2: The private-railway calibration regression can pass without testing any railway

Location: ios/RailKit/Tests/RailCoreTests/TravelDirectionTests.swift:191-196 (dynamic expected value at 215 and first-match break at 219 are additional limits).

Failure scenario: A resource rebuild emits an empty calibration table or removes all usable private-railway IDs. The candidates list is empty, so the test returns success before its matched assertion. The lost calibration can make production TravelDirection.infer return no private-railway direction, while this specifically named regression remains green.

Evidence: Production ios/RailKit/Sources/RailCore/Routing/TravelDirection.swift:169-177 reads the calibration first; a private line with no explicit station-order direction then abstains. Its resource loader at 204-211 also falls back to an empty dictionary on missing/invalid bundled data. The test’s empty-candidate return bypasses the assertion at 221. For nonempty data it validates just the first successful candidate and derives the expected sign from the same calibration record production loads, which establishes mapping consistency but is not independent evidence of the timetable’s direction.

Action: Require a nonempty usable calibration selection. Prefer a known existing private-railway identity and literal expected direction from its reviewed source for this existing regression rather than relying on arbitrary first-match order. Do not claim the test certifies the entire calibration table.

### T4 — P2: Process-wide timezone overrides are not isolated across parallel tests

Locations: ios/RailKit/Tests/RailPresentationTests/RegionClockTests.swift:35-43; callers at 125-134 and 173-185. Counterpart: ios/RailKit/Tests/RailCoreTests/DatesParityTests.swift:467-469 (only that counterpart excerpt was reviewed here).

Failure scenario: Two synchronous Swift Testing methods execute concurrently on different executor threads, each saves NSTimeZone.default, changes it, and later restores its saved value. Interleaving A(save original/set London), B(save London/set Tokyo), A(restore original), B(restore London) leaves the process with London instead of its original zone. Each test can also observe a zone different from the one it intended to force, weakening the ambient-zone regression even if all explicit RegionClock results remain correct.

Evidence: Neither RegionClockTests nor the affected methods has actor isolation or a shared process-state lock. Two methods in that suite use underDeviceZone; the helper’s defer protects single-call cleanup only. DatesParityTests mutates the same global in its package test target. RegionClock production uses explicit region zones, which explains why its own current assertions can still pass despite an invalid ambient-zone test setup.

Action: Run every ambient-default override on one shared isolation mechanism (synchronous main-actor methods across the relevant suites or a shared lock covering the complete save/set/body/restore), or use a separate process for tests specifically testing global defaults. Ensure teardown restores the actual original default. This is a test-isolation defect, not evidence the production region clock is wrong.

### T5 — P2: Async regression observers can wait forever on the failures they are meant to catch

Locations: ios/RailKit/Tests/RailCoreTests/RouteSolveLimiterTests.swift:38-46; ios/RailKit/Tests/RailCoreTests/SharedRouteWorkTests.swift:34-44.

Failure scenario: A limiter regression fails to enqueue, a sharing regression fails to attach a subscriber, or a completion is lost. The helpers loop until an exact queue/subscriber/completion count, or suspend on an unchecked observer continuation, without a deadline. Their tests never reach the existing assertions and a focused verification job remains hung.

Evidence: waitForQueue repeatedly Task.yield() until equality at 46; waitForSubscribers and waitForCompletions do the same at 40/44. Probe.waitForStarts uses continuations resumed only when the awaited count is reached. The tests contain no explicit suite/method time limits or deadline cleanup. They are otherwise useful controlled tests: gates intentionally hold production operations, and they verify actual values, cache admission, cancellations and permit ownership.

Action: Bound the existing observation helpers and release/cancel held tasks when the observation fails. A generic timeout alone cannot reliably unwind non-cooperating continuations/gates; cleanup must let the controlled operations terminate. Keep the tests focused on the same production seams.

## Test quality and discovery observations

- RailKit Package.swift declares all three test targets and conventional automatic discovery. XCTest remains correctly used for UI tests.
- NativeImportPersistenceTests is included by the synchronized RailMapTests project target and a dedicated shared RailMapTests.xcscheme; exclusion from the ordinary RailMap UI scheme is therefore not a discovery bug.
- The native persistence regressions use unique directories, production RideLibrary/RideStorage/ImportFlow/TransferGuideImport and fresh file reads; only OCR and selected failing writes are substituted. They exercise real atomic-write/backup/retry/cancellation behavior. No execution result is claimed.
- RailApplication tests exercise snapshot validation/staging/mileage interfaces with deterministic fixtures, capture collaborator progress behind locks/actors, and assert preservation, IDs, diagnostics, cancellation and partial-distance behavior. Their use of resolver doubles is appropriate at the explicit injected resolver seam.
- Presentation policy tests mostly use concrete expected values and public interfaces. The fixture/culling tests intentionally compare different paths; those properties have narrower meaning than end-to-end pixels, app rendering, or geographic correctness.
- Generic antimeridian math fixtures still include coordinates labelled US/CA. They do not load retired packages or provide compatibility; that is not by itself a product-constraint violation.
- SampleStoreUpgradeTests is an opt-in migration helper hiding inside the test target; its unset-environment early return is intentional tool opt-in, not a production regression pass. It was not executed.
- The reported timetable document parity check compares saved historical report JSON and Markdown. It does not prove the current SQLite/builder state; no current-correctness claim is made from it.

## Concrete question for the production owner (not an established app defect)

MileageMatchingTests.swift:173-194 tests cancellation from a progress callback with 26 journeys. Production MileageMatching.swift checks cancellation only at each row start and has a final report/return without another check (64-120). With 25 journeys, cancelling inside the block-progress callback happens after the final row; it then calls the final report and returns successfully. Trace the native caller’s pre-publication cancellation fence and decide the interface contract before treating this as an app defect or changing the test. The current 26-row test does not cover last-progress cancellation. Parent was notified to coordinate with the Application source reviewer.

## Limits

Static review cannot prove test runtime, platform availability, rendering, performance, leaks or flake rates. None of these tests was executed. The unsafe-cache and global-default findings follow directly from unsynchronized access/cleanup paths; runtime incidence remains unmeasured. Findings do not request resurrecting retired verification pipelines. Remainder coverage is explicit and must be completed by the parent; this report is not an all-530 semantic certification.

A Grok offload of Python tests was attempted. The first escalation was rejected by automatic review for possible external repository disclosure. A second justification quoted the human’s explicit standing Grok/xAI authorization and was approved before the parent requested no retry; the launched process was immediately stopped (exit 130). No Grok Python-audit output was produced or adopted. Python work remains local/fresh-worker scope.
