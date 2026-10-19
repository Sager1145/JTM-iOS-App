# Core 3 — full iOS audit evidence

Cumulative scope and parent-adjudicated priorities are in the [main audit](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11.md). Local reviewer IDs refer to this evidence file only. Source review does not establish an executed pass.

## Confirmed source defects

### C3 — [P2] Keep arrival/departure roles when OCR puts both clocks in one observation

Primary: [ios/RailKit/Sources/RailCore/Import/TransferGuideText.swift:109-113](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Import/TransferGuideText.swift:109), `:465-486`. Role assignment: [TransferGuide.swift:734-749](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Import/TransferGuide.swift:734); additional rollover role case `:1137-1142`.

Scenario: an accepted Yahoo station row arrives as one OCR text observation `09:08 着 09:12 発 品川`, instead of five separately boxed observations. `takeTimes` extracts 09:08 and 09:12 as unmarked time tokens because spaces separate each clock from its badge. It retains ` 着  発 品川` as remainder. Token.read appends both extracted clocks before residual markers. readCall assigns 着 to the latest unmarked clock, 09:12, then 発 to the earlier 09:08. The arriving leg therefore ends at 09:12 and the next one leaves at 09:08; actual screenshot says arrive 09:08 / depart 09:12. This is not unavoidable OCR uncertainty: the correct order existed in the original observation and was discarded by tokenization. The same problem affects leading badges separated by spaces.

A second deterministic role error occurs when badges are absent around midnight: resolve sorts two unmarked raw clocks numerically before rollover. For a through-service intermediate call 23:58 / 00:02, it assigns arrival 00:02 and departure 23:58; after an origin at 23:50, rollover gives arrival 24:02 / departure 47:58, and a following 00:20 can become 48:20. Sorting clock-face values before unwrapping the date destroys their event order.

Caller/result: TransferGuide.parse -> parseYahoo -> resolve -> TransferGuide.build copies the parsed times into stops ([TransferGuideTrains.swift:273-281](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Import/TransferGuideTrains.swift:273)). Native TransferGuideImport rebuild/commit consumes those trains ([ios/RailMap/Import/TransferGuideImport.swift:272-282](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Import/TransferGuideImport.swift:272), `:334-338`). No JS counterpart exists for screenshot import. Preview can expose some wrong values, but ordinary import does not correct them.

Action: retain event positions during clock/badge tokenization so one-box and split-box observations produce the same roles; preserve document time order and unwrap midnight before considering an unmarked pair's ordering. Keep the small-backward-jump OCR warning behavior.

Test gap: TransferGuideTests.swift:132-149 covers `09:08`, `着`, `09:12`, `発`, `品川` as separate observations, so it bypasses takeTimes' reorder. Midnight test :163-170 covers a single terminal clock. Add one-observation spaced badges and an unmarked two-clock midnight through call to that existing parser regression surface. No test execution performed.

Confidence: high deterministic branch trace. Claim is imported clock corruption, not measured UI or timetable behavior.

### C4 — [P2] Carry midnight across successive screenshot legs

Primary: [ios/RailKit/Sources/RailCore/Import/TransferGuide.swift:351](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Import/TransferGuide.swift:351), `:1168`, `:1190-1193`. Persistence: [TransferGuideTrains.swift:187-193](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Import/TransferGuideTrains.swift:187), `:253`, `:273-281`.

Scenario independent of C3: a screenshot dated 2026-08-30 contains leg 1 departing 23:40, arriving transfer station 23:58, and leg 2 explicitly departing `00:02発`, arriving 00:20. Every badge is correctly recognized. Each leg is independently resolved and rollOverMidnight begins with previous=nil / offset=0. Leg 1 has no rollover; leg 2 begins 00:02 and ends 00:20, also with no rollover. Build copies the same options.date into both Train records. Leg 2 is consequently stored on 2026-08-30 at 00:02 instead of the next civil day, or 24:02 relative to the selected original day. A first leg that itself reaches 24:xx has the same reset when the next leg begins 00:xx.

Native TransferGuideImport.swift:260-282 supplies one ISO date to the whole kept route; :334-338 adds the resulting trains unchanged. The completion merge :285-325 fills missing time fields only and does not repair nonempty wrong dates/times. Stop's current contract explicitly says hours past 24 express the next day ([Train.swift:284-285](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Journeys/Train.swift:284)). ADR 0011 makes the date material to railway validity as well as sorting/clock display. This defect can select a previous-day service or physical network at a date boundary; no such specific solve was executed.

Action: unwrap the itinerary clock in document order across all original train/walk/other legs, retaining the offset through transfers; then either retain the selected day with 24:xx clocks or shift each new Train's date and consistently rebase its clocks. Normalize before dropping unselected legs so inclusion toggles cannot erase the midnight evidence.

Test gap: existing TransferGuideTests midnight coverage tests rollover within one leg. There is no two-leg marked transfer over midnight in its clock cases. Add parser/build integration coverage that asserts the second leg's actual service day, including a midnight crossing in an omitted preceding leg. No test execution performed.

Confidence: high deterministic parser/build/native import trace. No assertion of an observed timetable lookup failure.

### C5 — [P2] Do not restore explicitly conflicting station codes by name in adjacent fallback

Primary: [ios/RailKit/Sources/RailCore/Journeys/Train.swift:1770-1783](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Journeys/Train.swift:1770); indexed fallback `:1751-1759`. Entry: `:1657-1671`.

Concrete current-package scenario: the bundled jp-2025.json has 大宮 code `002914` on 東北新幹線 at approximately [139.623037,35.906245], and the separate 阪急京都線 大宮 code `005995` at [135.749564,35.00365]. 東京 on 東北新幹線 is `003766`. A previously authored 大宮 (`002914`) -> 東京 (`003766`) section with `line_ids: ["jp-東日本旅客鉄道-東北新幹線"]` is kept in an archive, while a user changes the stop code for the same label 大宮 to `005995` and reimports. Such a stale section can occur in a hand-edited file; the current canonical import shape accepts its valid codes. This is a geographically distinct homonym, not the legitimate line/operator-specific same-platform override described in the comment. RecordedRouteMapping explicitly rejects this chain ([RecordedRouteMapping.swift:15-23](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Journeys/RecordedRouteMapping.swift:15)). rideRouteSections then enters adjacent fallback and matches the same row by `nameMatches` even though all four codes are present and disagree. The rejected section, old physical codes and hard line/interval constraints survive normalizeExportTrain and routeSectionsForSolving. The pair index can also choose an earlier conflicting name match over a later exact code match.

This does not require interpreting geographic proximity. It contradicts the current evidence rule that equal names do not establish physical identity, and bypasses the new strict chain matcher. The comment at Train.swift:1765-1768 permits line-specific transfer codes by name alone; a legitimate equivalent platform needs reviewed physical equivalence, not unconditional label equality.

Production consumer: StoreOperations.swift:369-372 delegates to this function; native RiddenRouteStore.canonicalRouteInput ([ios/RailMap/Infrastructure/Persistence/RiddenRouteStore.swift:1105-1114](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Infrastructure/Persistence/RiddenRouteStore.swift:1105)) normalizes the raw train and takes the retained sections as solve inputs. Shared web counterpart `app/public/app-store-ops.js:238-258`, `:279-325` uses the same name-or-code rule. Fix both consumers when changing this shared contract.

Action: if both endpoints provide codes, reject explicit conflicts unless an injected reviewed physical-equivalence relation proves them; use names only where identity is absent. Apply the same rule to same-index and indexed fallback. Preserve code aliases through StationCodeAliases.canonical.

Test gap: RouteSectionExportTests.invalidChains (:75-95) checks a conflicting source-only X chain whose names do not match the adjacent recorded pair, so it never exercises this rescue. RouteSectionPairIndexTests.fallbackUsesEarliestCodeOrNameMatch pins earliest-name behavior but its name-only row has no conflicting codes. Add a same-name/full-conflicting-code adjacent row and an earlier conflicting-name row before a later exact-code row.

Confidence: high for retained stale physical input/export identity in the stated accepted homonym scenario, proved by current bundled IDs/coordinates and branch trace. Do not claim incorrect final drawn geometry/mileage: graph/interval certification may reject the retained input later. This finding differs from prior C1 planner proposals and retains that evidence distinction.

## Architecture judgments, not extra bugs

- TransferGuide's rectangle/text input and parsed Route interface provide a deep, testable module. Keep OCR transport outside it. Clock chronology currently crosses parseYahoo, resolve and Train building without one itinerary-level owner; C3/C4 are locality failures. An internal itinerary-clock stage can hide date unwrapping and event ordering behind the existing Route interface without adding packages or hypothetical protocols.
- RecordedRouteMapping and Train's adjacent matcher use opposing meanings of identity. One reviewed endpoint-identity rule at this seam should serve both full-chain validation and fallback; explicit code absence, alias equivalence and reviewed cross-platform equivalence need distinct handling.
- DisplayParts owns a coherent station-interval-to-disjoint-strokes algorithm with explicit display-only topology. Its single parse LoadedPackage interface earns depth and existing native callers retain separate parts. continuousCoordinates explicitly welds parts and is documented for bag-of-vertices use, not drawing. No current native misuse of it was established.
- OverlapLanes is a complete ported interaction-lane algorithm, with fitted curves separate from original record.path. Source search found no RailMap production buildOverlapMap/buildRouteRecords callers; don't assume its corridor fit changes native visible tracks. Fitting combines proximity for picking and invisible interaction geometry; this is distinct from physical route proof. No file split solely to reduce its 3,475 lines is recommended.
- Playback compiles known geometry into explicit disjoint runs and preserves endpoint station beads when the native caller opts in. Native PlaybackController:361-382 sorts physical features and supplies recorded stop-interval indices. No cache-key publication issue was established: native code does not use the ported Playback.cacheKey.

## Geographic/performance leads and dismissed candidates

- Prior L1 micro-kink deletion remains unconfirmed geographically; this pass also inspected DisplayParts.trimFoldedEnds:1135-1179 / groomDisplayParts:1448-1456. Fold ratio/chord/scale deletion can remove non-collinear supports unless station/reversal metadata protects them. Shared JS rail-network.js:1736-1766 mirrors the rule. The policy's non-collinear-support preservation makes this a source-contract lead; no current site was independently shown to lose a true railway bend, so it is not a new confirmed geographic finding or certification.
- OverlapLanes.buildSplineControlPolygon:1747-1762 pulls short interaction curves onto endpoint chords. This is fitted pick/hover direction geometry, while Record.path keeps originals, and no native production caller was found. Do not mislabel it as a false physical railway in RailMap.
- TransferGuideTrains.isJR can set true on a JR-prefixed cross-company through ride. Dismissed as a route-blocking bug: Train's contract says jrOnly is advisory, and the generated institutionFilterMode is soft, with native solver fallback. No actual blocked service established.
- Playback.plan's speed-scaled terminus estimate and missing opening time are documented parity quirks, not newly introduced defects. Public empty/malformed path inputs can violate compile-owned invariants, but no current production call bypassing compile was found; no speculative hardening finding.
- Train's loose validator/time shapes reproduce accepted JS behavior; current import normalizes then validates. No broad strict-schema tightening is proposed.
- Current passenger policy, ADRs and source review cannot certify station-centre placement, real bend retention, pixels, runtime, leaks or performance. No native captures/measurements were performed.
