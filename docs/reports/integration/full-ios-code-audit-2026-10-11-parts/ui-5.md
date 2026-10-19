# Ui 5 — full iOS audit evidence

Cumulative scope and parent-adjudicated priorities are in the [main audit](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11.md). Local reviewer IDs refer to this evidence file only. Source review does not establish an executed pass.

## Confirmed correctness finding

### U5-1 — [P2] Saving an offline future plan silently marks it ridden

Primary: [/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/JourneyEditor/NewTripView.swift:1074](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/JourneyEditor/NewTripView.swift:1074) (second endpoint at `:1079`).

Scenario: from Upcoming's `+`, create a planned Osaka–Tennoji corridor for a later date, enter departure/arrival, choose a corridor and Save, without confirming that travel has occurred. This form exposes stations, service, times, route and Save; it exposes no ridden/not-ridden control or confirmation summary. Both newly built endpoint flags are nevertheless `rideSegment: true`. Generated through visits inherit the first endpoint's flag. The saved plan therefore reads as fully ridden and immediately enters Passport journey counts, date distributions, station rankings and recorded ride time. A reader must subsequently unmark it in another surface.

This is not a claim that every future-dated record must be unridden: [RideLedgerTests.swift:105–117](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Tests/RailPresentationTests/RideLedgerTests.swift:105) deliberately allows a reader-confirmed future-dated ride. The defect is the hidden unconditional confirmation in a form used for creating plans, and its mismatch with the same form's timetable branch and documented visible prefill/override contract.

Trace:

- [RailWorkspaceView.swift:1233–1238](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Workspace/RailWorkspaceView.swift:1233) supplies New Journey to every journey tab, including Upcoming; `:873–885` dispatches a new launch to `NewTripView`. The seed at `:2912–2920` is initially true, but the actual saved corridor replaces its endpoints at NewTrip `:1069–1079` with another unconditional true pair.
- [NewTripView.swift:423–427](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/JourneyEditor/NewTripView.swift:423) already defines a date-sensitive prefill. Timetable `applyTimetableTrip`/`applyPattern` at `:437–452` use it, producing false for future plans. The offline `draft(for:)` path does not. [LocalJourneyAutofill.swift:13–59](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Editor/LocalJourneyAutofill.swift:13) delegates to `RailwayRouteEditing`; generated calls at [RailwayRouteEditing.swift:200–203](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Editor/RailwayRouteEditing.swift:200) copy the origin flag.
- NewTrip `:1047–1060` validates and passes this draft directly to its save callback; no rider-state decision occurs. The route-confirmation pending state at `:1086–1087` is a separate physical proof gate, not rider confirmation.
- [AppShell.swift:187–188](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/App/AppShell.swift:187) filters Passport input through `RideLedger.hasBeenRidden`. [StatisticsDashboardContent.swift:1959–1960](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Statistics/StatisticsDashboardContent.swift:1959) uses the same reader-fact predicate. It has no date exclusion by design. [PassportStatistics.swift:177–241](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Statistics/PassportStatistics.swift:177) counts every supplied entry, records positive ride time and date/region/operator counts, then appends ridden endpoint journeys. Pending physical confirmation excludes mileage at `:180–187`, but does not suppress journey counts or time.
- [RideEditorView.swift:2135–2168](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/JourneyEditor/RideEditorView.swift:2135) documents the intended form contract: date prefill is permissible only in a visible switch the reader can move, and follows date changes until that switch is touched. `docs/reports/integration/feature-parity-ledger.md:319–321` retains only-reader-confirmed statistics and new-journey visible prefill/override behavior. NewTrip has no such switch.

Action: let NewTrip own one explicit rider-state choice, visibly prefilled from the selected date until the reader changes it, and use that same choice for offline and timetable drafts. Preserve RideLedger's stored-fact rule; do not fix the output by filtering future records out of statistics. A narrowly scoped first repair can at least apply the existing date prefill to offline endpoint creation; the reader's visible confirmation/override affordance remains the product contract.

Test gap: current [NewTripUITests.swift:79–113](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMapUITests/NewTripUITests.swift:79) checks a corridor saves and appears in a journey row, and other methods check station choice, multiple corridors, chronology, rotation and cancellation. None asserts rider flags/Passport exclusion for an untouched future plan or reader override. `RideLedgerTests` pins downstream interpretation but cannot detect a form inventing the input fact. Add a future offline create/save/readback case and compare the same future timetable draft; assert no Passport contribution before explicit rider confirmation, then confirm it and assert inclusion. No test/UI execution was performed.

Confidence: high, from complete form read and current save/aggregate caller trace. Counts/time inclusion is a deterministic source conclusion; no measured numeric mileage, rendered pixel or device observation is claimed. This is distinct from core2 C3, where timetable completion invents intermediate rider intervals inside an existing unmarked gap.

## Unresolved source lead

### L5-1 — NewTrip civil time preservation depends on the device's DST

Primary: [NewTripView.swift:153–157](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/JourneyEditor/NewTripView.swift:153); related conversion `:542–558`, `:1181–1207`.

The form represents printed regional times as device-calendar `Date` values and moves arrival by the absolute interval between old/new departure. A source-level example to investigate is a Toronto device with a Japanese 01:30–03:00 journey: changing only its civil departure date across the spring DST transition can turn the carried arrival into 04:00 in the device calendar, then save that wall time as Japan's. `timetableDate` likewise asks the device calendar to represent a regional printed 02:xx during a device DST gap. The regional record contract says printed service times are not converted (`feature-parity-ledger.md:75–79`; RegionClock header).

This remains a lead, not a confirmed observed defect: no focused Foundation/native observation was authorized in this tranche, and no affected shipped timetable/date was established. Inspect one civil-date transition or a gap-time source before asserting exact saved output. If established, use a representation/picker calendar that preserves the selected region's civil fields and shift arrival by the intended civil service interval, while keeping `RailCore.Dates` timezone-free. Do not combine this unresolved lead with U5-1's proved hidden rider-state input.

## Architecture judgments — separate from defects

### A5-1 — NewTrip and retained editor split ownership of the same rider-state interface

`NewTripView` has date/timetable/corridor state and a save callback; `RideEditorView` has its own date-prefill, visible rider switch, stop identity, route inference/repair, validation and save callback. These are two real callers of journey draft policy, not a hypothetical adapter opportunity. U5-1 demonstrates a locality failure: the same semantic fact is manufactured differently by two form paths, and an internal timetable branch has yet another policy.

A deep module at the draft rider-state seam should own the prefill-until-reader-choice invariant and produce the flags used by both forms and their offline/timetable adapters. Keep the interface small (draft inputs/current date/reader choice and resulting rider state), with existing save callbacks retaining persistence ownership. Tests should exercise the visible invariant through this seam, not private booleans. Do not introduce a universal protocol, additional package or mirrored implementation tests solely because either view is large.

### A5-2 — RiddenRouteStore earns depth by hiding physical evidence and cache identity

The store's external load/resolve/availability interface concentrates source coordinates, displayed coordinates, dated physical continuity, route outcomes/gaps, resource/history/timetable revisions, cache admission, partial publication and task revision ownership. Deleting this module would redistribute that knowledge among map, statistics, editors and diagnostic callers. Internal SolverInputCache/shared-work/publication seams are justified by actual lifecycle variation. This is useful depth despite the implementation's size.

Keep selected/display line identity and certified physical intervals explicit. `solveMissingSequentialWithPermit` does not promote coordinate coincidence to physical connectivity: it certifies source paths and adjoining section boundaries and persists unresolved physical gaps. NewTrip's probe-only `.confirmed` override is local to `TripRouteValidation`, and its regression explicitly preserves caller pending state. No current false cache reuse, graph race, memory leak or measured latency defect was established here. The generic candidate-permission issue in prior core C1 remains separate from final graph certification.

### A5-3 — Small lifecycle owners generally provide clean seams

JourneySearch accepts an immutable request and publishes only after cancellation checks. MapSelectedStationSnapshotController caches by country, cancels/re-tickets replacement requests and gates publication on current mount. TimetableQuickMatchView hands request ownership to its controller and leaves draft application to the editor. These modules provide leverage/locality through narrow interfaces. No extra protocol or test double is needed solely to satisfy a pattern; existing injectable loaders/resolvers are the real seams.

PassportStatistics is pure given aligned ridden trains/entries. TicketFace isolates fixed printed typography/artboard geometry; its explicit fixed-size fonts are not evidence that Dynamic Type exceeded xLarge. Pixel clipping, font fit and stock contrast remain unmeasured.

## Dismissed leads, constraints and evidence limits

- The initial apparent NewTrip historical-probe pending guard was dismissed: [TripRouteValidation.swift:44–47](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailApplication/Routing/TripRouteValidation.swift:44) promotes a local probe copy; [TripRouteValidationTests.swift:40–51](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Tests/RailApplicationTests/TripRouteValidationTests.swift:40) pins this. Current/future bypass remains explicitly documented, so bypassed candidates save pending and suppress precise kilometres by design.
- StationCard's place await lacks its own publication ticket, but StationPlaceStore itself returns nil to a cancelled waiter, and workspace presentation is keyed by station identity. No proven wrong-station link or stale result scenario was established. Its source/display coordinate convention was traced through its place-store contract; no geographic residual was measured.
- `RideStatusCenter.clear` leaves trainIDs, but ItineraryStore publishes the working set IDs independently (`:273`); no actual stale-validation caller was established.
- Catalogue resources and Region enum/scope cover only jp/tw/hk/mo/kr. North America is absent from this assigned production scope. Historical seven-region mentions in older ledgers/ADRs are not app inputs.
- App typography bounds at `RailMapApp.swift:16,:26`, UIKit clamp helper and existing typography regression were inspected. The known draft-label UIKit bypass belongs to prior UI3. No additional direct preferred-font bypass was found in these assigned files. Phone portrait is covered by the existing NewTrip rotation regression; its execution was not repeated.
- MapOverlayStyles animates railway renderer alpha, not a basemap tile/dimming layer. No reintroduced per-tile dimming or additional dimming animation was found in this assigned scope; full viewport layering is owned by the coordinator reviewed elsewhere.
- Existing reports/C1/C2/C3, metric semantics L2 and UI findings are correlated rather than duplicated. No full national geography, Apple alignment, runtime performance, leak, race, accessibility-pixel, or full-suite pass is claimed.

Result: full 28/28 assigned source coverage; one new confirmed P2; one unproved civil-time lead; architecture judgments separated. No assigned file remains unread. Parent should integrate with other tranches and preserve these evidence limitations.
