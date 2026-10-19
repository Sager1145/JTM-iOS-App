# Swift Tests 4 — full iOS audit evidence

Cumulative scope and parent-adjudicated priorities are in the [main audit](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11.md). Local reviewer IDs refer to this evidence file only. Source review does not establish an executed pass.

## Findings

### T4.1 — P2: The byte-parity helper silently accepts changed Unicode encodings

Locations: [ios/RailKit/Tests/RailCoreTests/StoreOperationsParityTests.swift:204-205](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Tests/RailCoreTests/StoreOperationsParityTests.swift:204); related helper `:226-227`.

Failure scenario: a serializer or import/export refactor changes a string value from decomposed `e` + U+0301 to precomposed U+00E9 (or a compatibility ideograph to its canonically equivalent ordinary ideograph). The JSON strings have different UTF-8 bytes and UTF-16 code units, but Swift String equality considers them equal. `expectSameBytes` returns at line 205 before comparing its UTF-16 arrays or recording an issue. `firstDifference` similarly returns nil. Thus a regression in the exact archive spelling can remain green in the tests explicitly named byte parity.

Evidence: the helper's early guard is `guard actual != expected else { return }`; the UTF-16 arrays are created only afterwards. Calls include stringify cases (259), committed files (311-318), canonical exports (336-337), blank trains (406), route-section output (567) and appended imports (669). `app/scripts/build/port-fixtures/store-ops.mjs:7-16` explicitly defines canonical export as a byte format. The repository itself demonstrates the String-versus-code-unit distinction in [StationsParityTests.swift:289-301](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Tests/RailCoreTests/StationsParityTests.swift:289), asserting that two canonical-equivalent spellings compare equal as String while their UTF-16 spellings differ. This defect follows from the comparison used, not a measured serializer corruption. The current 32 stringify fixtures were not executed.

Action: make the guard compare UTF-8 bytes or UTF-16 code units directly, and use the same criterion in firstDifference. Preserve the existing byte-parity seam; a compact literal canonical-equivalence probe would exercise the helper's previously invisible distinction if this test code is later fixed.

### T4.2 — P2: A lost conventional-service branding match removes the sample from conformance coverage

Location: [ios/RailKit/Tests/RailCoreTests/SampleServiceConformanceTests.swift:91-98](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Tests/RailCoreTests/SampleServiceConformanceTests.swift:91) (especially 97); coverage summary at `:120`.

Failure scenario: a caption-normalization/matching regression stops recognizing the composite recorded caption of one named conventional service. For example the committed Haruka sample `20260703_01_haruka` has number `はるか38号（Haruka 38）（1038M）` and type `特急`. If production service(for:) returns nil for that caption, the guard at line 97 skips it because its type does not contain `新幹線`. The missing identity, patterns and stop-conformance checks are never reached. A defect limited to compound sample captions need not fail TrainServiceCatalogChecklistTests, which supplies the catalog's plain name and simple name-plus-1 captions.

Evidence: [TrainServiceBranding.swift:144-154](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Identity/TrainServiceBranding.swift:144) resolves directly from normalized native/Latin captions. The test uses that production result to decide membership, increments checked only after the guard, and never checks an independent expected inventory of named sample services. Its existing classOnly exemptions apply to two different IDs and do not protect Haruka or other named conventional samples. This is a confirmed testing selection defect; no current branding failure is claimed.

Action: declare the expected named-sample inventory independently (ride IDs and expected service IDs, retaining the explicit class-only exemptions), require each expected lookup, and then perform the existing conformance checks. A minimum checked count alone would still allow individual services to disappear.

### T4.3 — P2: The new-trip cancellation regression can pass before the saved library has loaded

Location: [ios/RailMapUITests/NewTripUITests.swift:300-305](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMapUITests/NewTripUITests.swift:300).

Failure scenario: Cancel mistakenly persists a draft, then relaunch takes longer than eight seconds to load the library or finish the requested search. The search field is already present, but the row is not yet published. The final `XCTAssertFalse(row.waitForExistence(timeout: 8))` passes, incorrectly certifying that cancellation wrote nothing. A failed load or a query that was never applied can also supply the same absence result.

Evidence: the test checks field existence only, without verifying its value or a completed empty search. [RailWorkspaceView.swift:2173-2175](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Workspace/RailWorkspaceView.swift:2173) mounts JourneySearchField outside the state-dependent list. `:2206-2207` renders loading before records are available; the DEBUG query is applied in a separate task at `:564-569`. The adjacent existing dirty-discard regression already supplies the necessary distinction: [JourneySaveUITests.swift:159-166](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMapUITests/JourneySaveUITests.swift:159) requires the intended query value and a completed `No matching journeys`/`No journeys yet` state before asserting absence. Runtime incidence was not measured.

Action: apply the same loaded-search/query readiness fence to this existing cancellation test, then assert the unwanted row is absent. Keep the isolated storage ID and process relaunch.

## Review observations and limits

- The route/history/identity tests usually supply exact station and line IDs, explicit valid-day boundaries, source geometry, and concrete expectations. Direction tests exercise both directions; repeated-visit, ambiguity and uncertain timetable evidence receive substantive coverage through production interfaces.
- Memo tests use the injected operation seam and validate cache identity, retention bounds, nil/throw retries and cancellation in production memo operations. Their Task handles are awaited. Statistics and Stations cache publication/read paths are locked; no new unsafe-cache finding is made here.
- DatesParityTests' process-wide timezone override confirms the previously reported T4; it is not duplicated. RouteStressTests' missing-metric -1 upper-bound false pass was already assigned/reported elsewhere and is not duplicated.
- Some fixture categories still rely on a loop without their own independent nonempty/inventory check, but many companion tests require country coverage, minimum totals or named cases. No broad claim that every fixture can disappear unnoticed is made.
- RouteFeatureParityTests.swift:323-356 explicitly records narrower coverage for continueFrom, replacement-distance thresholds, hint-order and metre constants. `interiorVerticesComeFromTheNetwork` inspects fixture-expected geometry; its earlier drawnGeometry test independently compares the production result. This is a documented coverage limit, not a demonstrated current product bug.
- UI share/video tests check accessibility content, visible controls and ready states; screenshots are retained evidence. This static review does not establish raster accuracy, exported-file playability, performance, leak behavior or flake rates. No runtime pass is claimed.
- RefactorReleaseMemoryUITests assumes provisioned real-region records and uses ordinary app state; these tests do not themselves measure memory. Their readiness assertions must not be interpreted as a current footprint measurement.
- UI target discovery is enabled and nonparallel in the shared RailMap scheme. Platform-dependent skip conditions are explicit. Missing retired scripts in historical diagnostic text were not treated as instructions to run or recreate them.

Coverage: `/private/tmp/jtm-audit-tests4-coverage.json`; all 46 entries have full static-review status and explicit read ranges. Remaining assigned files: none.
