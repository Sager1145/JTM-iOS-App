# Ui 3 — full iOS audit evidence

Cumulative scope and parent-adjudicated priorities are in the [main audit](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11.md). Local reviewer IDs refer to this evidence file only. Source review does not establish an executed pass.

## Findings

### P2 — Card route Repair and Undo never save the canonical changes

Primary location: [/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Workspace/RailWorkspaceView.swift:2539](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Workspace/RailWorkspaceView.swift:2539).
Related: initial rebuild at 2495, guide continuation at 2577, Undo at 2644.

Scenario: open a journey whose route needs repair, run the selected card's Repair action, accept a suggested corridor (or let the unique repair apply), then relaunch without performing some unrelated later save. The card can show the repaired geometry in memory, but the original route/stop data reloads from disk. Undo has the same missing durability edge; if an unrelated write already saved the repair, Undo can appear successful yet the repaired record returns after relaunch.

Evidence: `repairReviewedRoute` calls `ItineraryStore.rebuildRoute`, and all three repair mutations call `itineraries.replace` directly. `ItineraryStore.replace` (144–178) publishes the working set, record index and date regrouping only. `rebuildRoute` (260–267) calls that same in-memory replacement and `resolveAgain`; it never writes the library. The app has no automatic save for arbitrary working-set changes. In contrast, `JourneyEditing.replace`/`rebuildRouteSections` pair mutations with `RideLibrary.save`, and the embedded editor waits for its exact persistence result. Route solving/cache publication is not canonical journey persistence.

Recommendation: route the card's initial rebuild, successful repair application and Undo through the existing durable mutation owner. Report/refuse an unsuccessful mutation or write instead of publishing a successful repair summary. Do not turn route cache writes into a substitute for journey-store writes.

Test gap: `OrdinaryPhysicalRouteUITests` checks editor repair followed by an explicit Save and relaunch. It does not cover card Repair/Undo without a later explicit save. A focused regression should start from a saved journey, perform this card action, relaunch, and compare its edited physical sections/visit identities; repeat after Undo.

Confidence: high; source/caller trace, independently checked by parent. No native reproduction claimed.

### P2 — Journey-menu editor closes before its save succeeds

Primary location: [/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Journeys/JourneyMenuView.swift:75](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Journeys/JourneyMenuView.swift:75).
Related: `save` at 157–167; [/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Workspace/RailWorkspaceView.swift:759](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Workspace/RailWorkspaceView.swift:759).

Scenario: edit an existing journey from its opened menu and tap Save when the local store write fails (for example an I/O failure). `save(edited)` returns true as soon as the in-memory replacement succeeds, so `showsEditor` becomes false and the local editor draft disappears. The disk still holds the previous record. The menu supplies no persistence-failure alert and can appear saved until relaunch.

Evidence: `WorkspaceSheetContent` (151–155) constructs `WorkspaceJourneyMenu` with `onSaveDetail`. The workspace callback calls `editing.replace`, which starts `library.save` but discards its task. The menu's Bool merely interprets `.saved`/`.savedKeepingID` from `ItineraryStore`, not the disk result. `RideLibrary.saveResult` (262–303) explicitly returns `.saved == false` on a write error. `RailWorkspaceView.commitJourneyEditor` (945–997) already has the correct exact-write wait, rollback and kept-open failure path for the embedded editor, but this modal editor does not use it.

Recommendation: share the existing editor save lifecycle through an interface that carries the exact async persistence outcome; keep the modal editor/draft open until its write succeeds and surface the actual failure. Preserve the ID-collision outcome semantics.

Test gap: existing save/relaunch cases exercise the success path and embedded editor; no write-failure regression covers the menu's nested editor. Use a failing storage adapter rather than assuming a successful in-memory mutation establishes durability.

Confidence: high source trace. Disk error scenario is supported by the production error branch, but no error was induced during this audit.

### P2 — Draft map labels bypass the permanent typography ceiling

Primary location: [/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Map/JourneyLabelAnnotationViews.swift:265](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Map/JourneyLabelAnnotationViews.swift:265).

Scenario: launch with the system at an accessibility text category, then edit a journey whose stops produce draft map pins. `DraftStopAnnotationView` takes `.preferredFont(forTextStyle: .caption1)` directly, so its UIKit text and `sizeThatFits` measurement follow a category above `.xLarge`, contrary to the permanent app requirement.

Evidence: the production `AppTypographyPolicy.preferredFont` (8–14) explicitly clamps UIKit requested fonts using `.extraSmall` and `.extraLarge`; `BottomChromeMetrics.subtitleRow` correctly uses it. The draft annotation instead calls bare `UIFont.preferredFont` during construction and sizes its bubble using that font (280–283). The coordinator's mount/configure path (4190–4199) supplies no font clamp. SwiftUI's dynamic-type range is not the explicit UIKit font measurement policy this code implements.

Recommendation: use `AppTypographyPolicy.preferredFont(forTextStyle: .caption1)` at the draft annotation's measurement/configuration seam and keep measurements in sync when an allowed text category changes.

Test gap: `AppTypographyPolicyTests` measures the SwiftUI environment and the bottom-header subtitle row; it does not inspect draft map annotation fonts/bounds. Add the draft pin to the existing targeted typography case at AX5 and assert the font/measurement ceiling.

Confidence: high; independently checked by parent. No screenshot/pixel conclusion.

### P2 — Line-detail widgets duplicate Japanese lines and SwiftUI identities

Primary location: [/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Statistics/StatisticsDashboardContent.swift:531](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Statistics/StatisticsDashboardContent.swift:531).
Related: widget IDs at 538; [/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailPresentation/Statistics/StatisticsLineCoverage.swift:15](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailPresentation/Statistics/StatisticsLineCoverage.swift:15); widget consumer [/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Sharing/StatsWidgetView.swift:284](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Sharing/StatsWidgetView.swift:284).

Scenario: display a Japanese line-detail statistics widget after riding a JR conventional line. The producer flattens every category's rows into one collection. JR conventional lines belong to both CONV and JR, so the same physical line appears twice with the same `operatorName + lineName` ID. The widget's hero count includes both occurrences, the two entries are indistinguishable, and `ForEach(rows)` receives duplicate IDs. The same problem applies to ridden JR high-speed lines through HSR and JR. Ranking can put duplicate high-percentage entries next to each other and consume multiple visible slots.

Evidence: `Statistics.categories(country: jp)` includes HSR, CONV and JR, and the source explicitly documents overlapping category masks at 99–100. `finalizedEdgeIndex` (1115–1122) places each line total in every matching line mask. `StatisticsLineCoverage.Row.id` has no category. Dashboard widgetData's `.lineDetail` (530–542) flattens category rows, sorts them by percent, copies `line.id`, and uses the flattened count as its hero. The detailed card is safe because its categories retain separate `ForEach` collections. Existing `StatisticsLineCoverageTests` (106–113) explicitly show the same five ridden line names in both CONV and JR but test each category separately.

Recommendation: decide whether this widget lists physical lines or line/category entries. For physical lines, deduplicate by line identity before counting/ranking and use a defined total/coverage measure. For line/category entries, include the category in ID and visible label, and label the count accordingly. Preserve the detailed card's intentional overlapping coverage categories.

Test gap: category-row tests do not exercise the flattened widget data. Add a producer-level regression with one ridden conventional JR line and one JR high-speed line; assert unique IDs and an accurate hero count. No rendering failure was observed or claimed.

Confidence: high source proof; independently check by parent before final integration.

### P3 — Average duration can format as 60 minutes

Primary location: [/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Statistics/StatisticsFormatting.swift:78](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Statistics/StatisticsFormatting.swift:78).

Scenario: ten timed journeys total 597 minutes, making the average 59.7 minutes. `hoursMinutes` floors hours first (0) and rounds the remainder separately (60), so the time widget/detail displays `60 min` rather than `1 h 0 min`. An average 179.7 becomes `2 h 60 min` instead of `3 h 0 min`.

Evidence: hours are computed from the unrounded input at 78, then remainder rounding at 79 can carry to 60 without incrementing the hour. `PassportStatistics.averageMinutes` (123) divides total minutes by timed journey count, so fractional inputs are reachable without unusual data. Dashboard callers at 456 and 1564 pass that average through `StatisticsFormat.duration`. This is a display-normalization defect, not mileage/time data corruption.

Recommendation: round the total minute count once, then split into quotient/remainder using the same rounding rule.

Test gap: no formatting rollover case found. Cover values immediately below/on the rounding rollover and a fractional average produced from integer journey durations.

Confidence: high arithmetic/source proof; independently checked by parent. No tests executed.

## Architecture judgments (separate from correctness findings)

- **JourneyEditing earns depth, but callers can bypass its interface.** Its small mutation interface hides working-set changes, selection behavior, queued writes and conditional rollback. The modal editor/card-repair findings demonstrate poor locality at the persistence seam: views still know when to pair `ItineraryStore` and `RideLibrary`, and some forget. Deepen the existing module around a concrete commit result rather than adding a second persistence abstraction. The canonical mutation/write ordering should be knowledge held once.
- **RailWorkspaceView contains several genuine ownership clusters.** Presentation detents, command installation, scope/playback selection, durable editor commits and multi-step repair now share one view implementation. Length alone is not a defect; the concrete issue is that repair's lifetime/snapshot/mutation knowledge is private to the view while durable editing lives in another module. Moving a complete repair owner behind a small repair/choose/undo interface would improve locality and make the existing conflict guards and persistence behavior exerciseable through one seam. Do not expose individual helpers just to shorten the file.
- **MileageStatisticsStore is a useful deep module.** Fingerprints, per-entry cache reuse, exact publication ownership and passport-only refresh sit behind selection/load operations. The source review found explicit guards for canceled/superseded result publication. Its dependency reads and aggregation are separated from UI snapshots. Keep those invariants internal; do not suggest replacing this with ad hoc `@State` caches.
- **DisplayNetworkCache and EdgeIndexCache provide real leverage.** They join country builds, serialize allocation admission and retain a bounded completed result while active consumers own immutable values. Their seams exist because map/route/statistics consumers genuinely share expensive values. The display seed caller preserves line/part count ordering. No additional hypothetical adapters or cache layers are warranted from this review.
- **Widget data construction has weak locality.** Its category flattening and pending-distance presentation rules are reconstructed inside a large view while related detailed-card rules are elsewhere in the same implementation. The concrete identity defect justifies moving widget-data projection into a pure module with the same interface for UI and focused tests; this does not justify moving all dashboard layout code or claiming a measured performance improvement.

## Reviewed constraints and limits

The slice's live Region switches contain only jp/tw/hk/mo/kr. Line previews explicitly remain display-only and do not create physical graph connectivity. Shared drawing geometry and solver truth remain distinct at cache/preview interfaces. Permanent typography found one direct UIKit gap above. Phone orientation configuration and full-viewport basemap compositing are chiefly owned outside this slice and should be concluded from the other workers, not inferred from these views. Historical docs mentioning North America or retired full runners were not treated as active requirements.

Many UI computations run during SwiftUI body evaluation, but code alone does not establish jank, frame cost, memory growth or leaks. This audit makes no such measured claims and did not run diagnostics or a full matrix. There are no unread assigned executable-source ranges.
