# Core 1 — full iOS audit evidence

Cumulative scope and parent-adjudicated priorities are in the [main audit](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11.md). Local reviewer IDs refer to this evidence file only. Source review does not establish an executed pass.

## Confirmed correctness

### C1 — [P2] Interchanges become physical continuations in route proposals

Primary: [ios/RailKit/Sources/RailCore/Routing/TripConnectivity.swift:27-29](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Routing/TripConnectivity.swift:27). Related: [LocalJourneySearch.swift:360-372](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Routing/LocalJourneySearch.swift:360).

Concrete current-resource scenario: request one Shinkansen journey from 品川 (`004095`) to 上野 (`003505`). Shipped `app/public/rail/jp-2025.json` has Tokaido Shinkansen (`jp-東海旅客鉄道-東海道新幹線`) ending `[004501 新横浜, 004095 品川, 003766 東京]` and Tohoku Shinkansen (`jp-東日本旅客鉄道-東北新幹線`) ending `[002914 大宮, 003505 上野, 003766 東京]`. Both have `kind: shinkansen` and no one-way metadata. Their independent Tokyo terminal groups must not connect; the current passenger policy explicitly distinguishes them at `docs/reports/japan/passenger-representative-display-policy-2026-10-11.md:31`.

Trace: `TripConnectivity.link` grants `.network` when either row is terminal and both kinds are Shinkansen, without a physical junction registry or surveyed endpoint proof. [TripRoutePlanner.swift:84-97](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Routing/TripRoutePlanner.swift:84) treats non-`.none` as `verified`; `:133-138` passes that permission to LocalJourneySearch, which joins row occurrences by the shared station code. Current inputs thus admit 品川–東京–上野 as one train corridor rather than a passenger change/disconnection. Targeted catalog reading found no Tokaido-to-Tohoku Tokyo continuation; this permission comes from the generic fallback.

The inference path is broader: [RailwayRouteInference.swift:33-42](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Routing/RailwayRouteInference.swift:33) calls search with no continuation predicate; default [LocalJourneySearch.swift:364-372](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Routing/LocalJourneySearch.swift:364) permits equal kinds or matching operators, including interior crossings. It sets direction known; a sole untruncated result becomes `uniqueChoice`. [RideEditorView.swift:872-876](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/JourneyEditor/RideEditorView.swift:872) can immediately apply a no-conflict result, and [RailwayRouteEditing.swift:170-172](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Editor/RailwayRouteEditing.swift:170) writes `.confirmed` for a whole-span selection, without physical junction evidence. Inspected TripRoutePlannerTests pin generic JR/terminal/same-name permission, so existing regression expectations perpetuate this behavior.

Action: constrain cross-row physical proposals to reviewed physical junction identities/endpoints and dated validity. Preserve transfer/through-service display proposals independently; do not treat them as physical permission or auto-confirmation. Focused cases: 品川–上野 via Tokyo and a same-company interior crossing.

Confidence: high in false permission/candidate from deterministic branches/current records; no planner execution. Do not claim incorrect map geometry/mileage: the additionally inspected [RouteSolver.swift:2082-2140](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Routing/RouteSolver.swift:2082) certification requires graph physical continuation or same-identity surveyed spans and can reject the proposal later. Full RouteGraph/RouteSolver review remains pending.

### C2 — [P2] A valid undated journey appears in Upcoming

Primary: [ios/RailKit/Sources/RailPresentation/Workspace/WorkspaceJourneyRules.swift:104-107](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailPresentation/Workspace/WorkspaceJourneyRules.swift:104). Related: `:73-80`.

Scenario: accepted canonical journey with an ID containing no date, `date: "undated"`, and two valid stops, viewed in Upcoming with All Dates. Lexicographic `"undated" >= "2026-10-12"` is true, so upcomingScope returns future travel. The same comparison in journeyDates puts Undated into the Upcoming date menu.

Trace: [Train.swift:981-984](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Journeys/Train.swift:981) explicitly accepts the sentinel. [Train.swift:1354-1356](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Journeys/Train.swift:1354) imports through Dates.normalizeTrainDate; absent usable date/ID yields Dates.undated ([Dates.swift:272-280](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Utilities/Dates.swift:272)). [RailWorkspaceView.swift:1548-1552](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Workspace/RailWorkspaceView.swift:1548) consumes upcomingScope directly, and its IDs also filter the map. Its product explanation at `:1521-1531` says undated is not upcoming. RegionClock.isUpcoming rejects unnormalizable dates. Existing [WorkspaceJourneyRulesTests.swift:103-121](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Tests/RailPresentationTests/WorkspaceJourneyRulesTests.swift:103) tests nil and deliberately admits a malformed raw string, but omits the schema’s normal sentinel.

Action: require a normalized calendar date before comparing against regional today in both Upcoming predicates, retaining stored-day semantics for valid dates. Add `date: "undated"` to the existing focused test. No record or date-bucket migration needed.

Confidence: high direct model/caller trace; no UI/test execution. Other malformed-date behavior is explicitly pinned and not separately reported.

## Architecture judgments

### A1 — Physical connection knowledge lacks locality

Locations: TripConnectivity:12-35, LocalJourneySearch:360-372, JapanThroughServices:209-215, TripRoutePlanner:128-132, RailwayRouteEditing:170-172 and partially reviewed RouteSolver:2082-2140.

The modules expose physically named choices and confirmations while requiring callers to know which results merely describe passenger/display relationships. JapanThroughServices.Pattern.choices documents display-only slices that must never serve as physical search edges or auto-fill candidates, but shares RailwayRouteChoices.Choice with physical selections; TripRoutePlanner appends these slices to candidates. Different continuation rules precede final graph certification. C1 demonstrates the resulting locality failure; copying Tokyo exceptions into all callers would retain it.

A deeper module at the physical-continuation seam should hide junction identity, surveyed endpoint and date decisions behind a small interface. Its selection should carry the evidence level needed to confirm; a passenger/display adapter should retain through-service presentation. This is an ownership/interface judgment, not a mandate for extra packages or universal protocols. Existing graph certification earns depth: deleting it would redistribute proof complexity to its callers.

### A2 — Shared work/cache modules have useful explicit ownership

SharedRouteWork, RouteSolveLimiter, RouteResolutionMemo and StationIntervalResolver were fully read. Their interfaces document snapshot identity, retention/admission and cancellation. Shared work separates subscriber tickets from producer tokens, detaches abandoned subscribers and guards old completion tokens. Limiter retains permits until operations exit. Immutable-snapshot memos lock storage rather than live graphs. These seams provide leverage for app stores; Task.detached/@unchecked Sendable alone were not reported. This is source review, not a race/leak/performance measurement.

Pure presentation modules concentrate state priorities, occurrence edits, regional clocks and viewport policy behind testable interfaces; do not introduce hypothetical adapters solely for a pattern.

## Source/policy lead — geographic evidence unresolved

### L1 — Micro-kink deletion still permits non-collinear survey supports

Source: [Grooming.swift:211-217](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Rendering/Grooming.swift:211), removal :223-226. Display caller: [DisplayParts.swift:1455](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Rendering/DisplayParts.swift:1455); extra segment caller :1224-1229. JS counterpart: `app/public/rail-network.js:217-228`. Current rule: `docs/reports/japan/passenger-representative-display-policy-2026-10-11.md:44` says preserve non-collinear surveyed supports, reverse curves, true corners, switches and reversal branches; remove only same-direction straight redundancy. Line 46 records a narrower pre-interpolation change and explicitly does not certify all native geometry.

The retained groomer deletes unprotected supports by short-edge length, turn and lateral deviation; turns >=150 degrees bypass lateral deviation. No collinearity or source-error proof is required. Normal display parts protect station/shared vertices and run this rule on remaining supports; extra segments protect endpoints only. A tight reverse bend can become a chord before interpolation. JS parity preserves the same behavior and cannot resolve the product-contract question.

This is a source-level contract lead, not a confirmed geographic defect. No shipped vertex was independently proved to be a true track bend incorrectly deleted, and no native capture was run. Trace one affected line/interval against its surveyed supports before claiming a site defect. If preservation is unconditional at this stage, retain non-collinear supports or repair evidenced survey errors at their reproducible source owner, instead of inferring noise from scale.

## Dismissed leads and limits

- MileageMatching lacks a check after its final progress callback, but actual app caller immediately checks cancellation after await ([MileageStatisticsStore.swift:370-382](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Statistics/MileageStatisticsStore.swift:370)) before publication. No production canceled-publication bug established.
- MileageMatching cached distance-known flags could be sticky under unchanged digest; actual digest includes fullDistanceKnown ([MileageStatisticsStore.swift:925](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Statistics/MileageStatisticsStore.swift:925)). No current cache identity defect established.
- CompactPackage could trap on malformed normalized duplicate interval keys ("1"/"01"); no such current resource/input established, so not a finding.
- StationIndex assumes matching names/hints array lengths; active TransferGuideTrains caller supplies corresponding arrays. No short-hints current case established.
- Current history retirements contain no station-name selectors. One Wakinoda retired-directory entry has multiple locations, but no incorrect current selection/result established. Not elevated.
- Typography bounds, portrait orientation, viewport Apple dimming and runtime/pixel/performance claims require native app review/measurement beyond these portable modules.
