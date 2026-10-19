# Ui 1 — full iOS audit evidence

Cumulative scope and parent-adjudicated priorities are in the [main audit](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11.md). Local reviewer IDs refer to this evidence file only. Source review does not establish an executed pass.

## Findings

### UI-1 [P1] Append import can overwrite saved journeys before initial loading completes

Primary: ios/RailMap/Journeys/ItineraryStore.swift:349-353.
Related: ImportFlow.swift:281-282, 351-353, 377-391; DataManagerView.swift:289; ItineraryStore.swift:513-550, 395.

The Import section stays enabled while disk loading is in flight (disabled only for isImporting/fileToImport). Preflight captures store?.trains ?? [] and generation. If the user validates and commits before disk loading publishes, generation guards pass and backup is skipped because store is nil. runImport guards only against another import and stages append against [].

The saved-store load suspends several times before publication. If import publishes first, load's generation guard abandons the saved snapshot; ImportFlow saves only imported trains. If the saved load publishes during import staging, runImport has no post-staging generation guard and overwrites that loaded store. Thus an append can erase previously saved journeys without a recovery copy. Parent independently confirmed this trace.

Fix: enforce a non-nil, settled loaded working set / !loadInFlight admission inside ItineraryStore and guard staged snapshots against store changes across suspension. Reflect readiness in import controls and re-check against loaded content before committing.

Test gap: NativeImportPersistenceTests seeds every JSON-import case with baseline() / importJSON. Its cancellation and write-failure tests do not cover startup load interleaving. Add a deterministic held-load append case; original + incoming IDs and recoverability must survive. Web app/public/app-import.js:348+ explicitly appends to existing trainStore.

### UI-2 [P2] Regroup reasserts obsolete selection after a later user selection

Primary: ios/RailMap/Journeys/ItineraryStore.swift:728.
Related: same file:487, 718, 723-726; RailWorkspaceView.swift:3078.

Every mutate schedules regroup(..., reassertingSelection: true), including visibility toggle/move. Regroup captures selectedTrainID, yields and awaits grouping, then writes the captured ID. A plain selection change does not advance groupingTicket.

Scenario: toggle a journey while A is selected, then select B or tap blank map before grouping returns. Publishing the grouping restores A, undoing the newer user intent. Larger stores widen the available interleaving; no measured latency claim is made.

Fix: track selection intent revision separately and reassert only when no later intent occurred, or remove the need to temporarily clear selection while grouping is stale.

Test gap: no model regression for grouping completion versus later selection. A deterministic interleaving should assert newer selection remains.

### UI-3 [P2] Overflow maps still filter exported statistics despite being outside the canvas

Primary: ios/RailMap/Sharing/ShareComposerModel.swift:341-346.
Related: ShareCardRendering.swift:194, 281; ShareComposerView.swift trayCards.

effectiveScope unions every unparked map card, including those returned in layout.overflow. Overflow maps appear in the tray labeled does-not-fit, while preview/export draw only placements.

Scenario: All regions, Taiwan map + ticket fit; add/enlarge Japan map until it overflows. Export contains Taiwan map + ticket but ticket/statistics include Japan and label Japan・Taiwan. Explicitly parking that same omitted card removes Japan from scope. Cards omitted for overflow versus parking have inconsistent filtering behavior.

Fix: derive map-based effective scope from the same placed-card snapshot used by preview/export, retaining the intentional no-map fallback. If overflow intentionally filters data, disclose that active filter explicitly.

Test gap: ShareComposerMatrixTests.swift:78 has stat/stat/ticket overflow, no overflowing map. Add placed Taiwan + overflowing Japan map scope/member assertions.

### UI-4 [P2] Failed saved-store deletion is silently treated as success

Primary: ios/RailMap/Infrastructure/Persistence/RideStorage.swift:158-159.
Related: RideLibrary.swift:375-380; DataManager Delete saved rides action.

removeStore suppresses all FileManager.removeItem errors. Library enqueues it as successful void work and immediately clears saved metadata/sample state. On removal failure (e.g. protected/immutable file), the following reload discovers the old file and restores supposedly deleted journeys without a deletion error.

Fix: missing file can be success; propagate other removal failures through the ordered queue, publish deletion state after success, and have destructive UI await/report its result.

Test gap: native persistence tests cover write/backup/restore faults, not removal failures. A focused failing-removal test should retain saved metadata and publish an error.

## Architecture suggestions — separate from bugs

- Deepen the journey-mutation module at the working-set seam. Existing ImportFlow, sample/delete and screenshot callers must know backup timing, mutation admission, generation fencing and persistence ordering. A small reviewed-mutation interface returning its own durable/recoverable outcome would concentrate those rules in one implementation, improving depth, leverage and locality without prescribing an architecture framework.
- Create one immutable share-layout plan module for placements, frames and effective scope. frames(model:) and frames(cards:grid:canvasSize:) duplicate layout arithmetic; scope is independent. Preview, drag planning and export are real adapters at this seam. One plan removes repeated knowledge of packing, occupied bounds, ticket aspect exceptions and scope.

## No-findings / rejected candidates

Auth generations, shared refresh, redirect rejection and device-only Keychain were reviewed without concrete findings. Playback/export replacement-writer, callback, preparation and partial-file lifecycles were reviewed without runtime claims.

AppleMapDatum is already applied by DrawnSegment.init to segment.coordinates, so StatisticsMapSnapshot has no missing datum conversion. Snapshot failures produce a placeholder, rejecting a nil-map-on-network-failure claim. RecordDate intentionally uses device-zone DatePicker carriers seeded from journey-region today, rejecting a missing-picker-timezone claim. Typography bounds remain xSmall...xLarge; read-only work does not alter orientation, physical topology or full-viewport dimming constraints.

Sample backup/commit interleaving remains an unconfirmed question and is not an additional finding.
