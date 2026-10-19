# Japan Railway Inspection Workbench Implementation Plan

> **For agentic workers:** Use executing-plans or bounded subagent development. Existing user authorization covers implementation and local fixes; no commits, publishing or recurring automation. Repository verification policy overrides historical full runners.

**Goal:** Upgrade the existing independent Swift/Mac Catalyst inspector so every Japan station interval appears in a persistent, evidence-driven checking plan; prioritize risks, capture comparable basemap evidence, and repair only confirmed defects at the owning layer.

**Architecture:** A small Foundation-only `InspectionKit` plans intervals and validates saved reviews. The existing app adapts RailCore decoded/display inputs, owns navigation/persistence, and renders actual ContinuousStroke geometry with production tokens. One MapKit map keeps a fixed camera during mode changes. Local reference GeoJSON is optional evidence and never creates topology. Generated risk signals remain candidates, not alignment verdicts.

**Design choices made by Codex:** Chinese controls, a searchable risk queue plus line browser, explicit pending/aligned/needs repair/no basemap evidence/repaired states, notes, exact per-reviewed-interval geometry invalidation, paired basemap/display/smoothed snapshot exports with camera metadata. A railway-curve plus inspection-lens logo supplies the app icon and header identity. All intervals remain pending until evidence is reviewed; existing Tabata repair is a known reference case, not automatic national coverage.

## Files and ownership

- `ios/auxiliary/RailAlignmentInspector/InspectionKit`: pure planning/review models and focused tests (bounded Sol worker).
- `Sources/InspectorModel.swift`: package adapter, plan selection and progress, review persistence, imports/exports.
- `Sources/InspectorMap.swift`: display-versus-smooth comparison, interval focus, reference overlays, deferred observable publication and evidence capture.
- `Sources/InspectorApp.swift` plus small focused views: queue/review controls and existing map/line controls.
- `Sources/InspectionEvidence.swift`: paired camera snapshot evidence and local GeoJSON reader.
- `Assets.xcassets`/`project.yml`: logo/icon resources and local package integration.
- Existing `docs/reports/japan/rail-alignment-repair-2026-10-10.md`: findings/results ledger; this plan records execution progress.

## Delivery tasks

- [x] Build and test cheap deterministic interval planning, risk metrics and geometry-bound review status. Preserve full coverage; never infer pass from absence of signals.
- [x] Integrate full plan into the app with queue, progress, selection, notes, verdicts, saving and JSON export. Handle loops, empty geometry and display overrides.
- [x] Improve comparison: show display input plus smoothed centreline, fixed detailed camera controls, selected interval metrics and optional imported reference geometry.
- [x] Export paired MapKit basemap/display/smoothed images and JSON from one captured camera. State reference, camera and geometry scope; avoid pixel-accuracy claims.
- [x] Generate and integrate the logo, app icon and header branding. Inspect source asset and native icon output.
- [x] Review current source/callers, run only focused tests plus one incremental Catalyst build/native observation. Record real output and limitations.
- [x] Use the new queue to choose a bounded first batch, inspect at detailed zoom against actual drawn tracks and available surveyed evidence, fix confirmed issues with replayable overrides and update affected native cache entries. Keep unknowns visible.

## Complete Japan checking plan

1. **Coverage:** one record for each compact station interval (including loop closing rows), grouped by operator/line. Display branches and source intervals stay separate. Extra physical edges must be separately enumerated if present.
2. **Prioritization:** invalid/missing geometry first; reversal/large turn and sparse bend candidates next; display overrides and station seams next; otherwise systematic line order. Long straight track is a review candidate, never an error.
3. **For every item:** inspect source, effective display and real smoothing with the same camera; review station approach and both interval seams; zoom to detailed track depiction. Record absent/tunnel/ambiguous track as insufficient evidence.
4. **Reference:** Apple drawn track is visual evidence. OSM/official source coordinates provide independent geometric comparisons only when identity and continuous surveyed endpoints agree. Multiple directional tracks are not silently blended.
5. **Verdict:** explicit human/agent review with note, evidence paths and exact inspected input geometry. Input changes invalidate previous status back to pending. No background national pass or automatic snapping.
6. **Repair:** source/override or renderer owning the observed defect; preserve station identity, physical routing/mileage, loops, shared corridors and source attribution. Patch bounded window, refresh affected part/cache dependencies; concrete measure dependencies may require broader derivation.
7. **Close each finding:** targeted regression/query, one reusable incremental build, focused native visual check, before/after source evidence and scoped result note. Repaired state means reviewed evidence, not merely code edited.
8. **Coverage report:** counts of pending/aligned/needs repair/insufficient evidence/repaired per line and nationally, with unresolved findings. Do not claim all Japan aligned while pending or insufficient entries remain.

No retired umbrella verification pipeline, synthetic evaluator campaign, full-tree custody hash, autonomous delivery loop or recurring scheduled task is introduced. Plan generation is a product feature requested here; expensive smoothing/snapshot work stays selected-item-only.

## Execution result

Completed the workbench, logo, complete interval queue and a bounded first batch. The final Catalyst build succeeded; 10 focused planning/persistence tests and four existing Tabata repair tests passed. Native export produced the complete 657-line / 9,579-interval plan at `docs/reports/integration/japan-rail-inspection-plan-2026-10-10.json`, including per-line summaries and observation history. No extra-edge fields occur in this Japan package.

The first batch recorded Tokyo–Yurakucho as a scoped corridor-alignment observation (the turn candidate alone did not justify a data edit), and rechecked the earlier Tabata correction against a scoped OSM reference. The latter remains a repaired bend viewport, not a completed whole interval. Two current viewport conclusions and one detailed spatially covered interval are recorded; the remaining queue is pending. No new railway-data patch was justified by these two observations. Actual tool defects—camera override, incomplete review dependencies, capture camera race, partial-reference distance inflation and z17 roundoff—were fixed from review/native findings. Long-interval 350m inspection targets and cumulative history now support systematic coverage.

The checkboxes above describe implementation and first-batch execution. They do not mark the complete national review plan as executed. See the owning result ledger for scope, real evidence and unresolved coverage.

## Automatic execution follow-up

User requested automatic completion of every step. The remaining national scope is explicit: 9,579 intervals across 657 lines still need detailed basemap observations. Add a resumable native product collector (not a retired verification runner) with deterministic 350m camera targets, serial frozen MapKit snapshots, input/render/reference-bound checkpoints, saved failures and separate capture/review status. Reuse each saved view after checking its actual dependencies and files. A geometry candidate cannot set an aligned verdict or snap a track.

- [x] Add deterministic full-viewpoint planning and focused persistence regressions.
- [x] Integrate a native serial capture controller, pause/resume/retry, report and fixed output folders.
- [ ] Review/build the new controller and observe capture, pause/resume with the actual Japan package.
- [ ] Execute the nationwide evidence queue; review geographic findings and record unresolved/absent basemap tracks.
- [ ] Repair confirmed findings with source evidence and bounded dependent cache updates.

New first finding: Nihongi's genuine switchback exists in source intervals but `trimFoldedEnds` shortens a 535m outgoing run into a 130m diagonal across the neighborhood. A sampled smoothing→DisplayParts diagnostic alone misses this defect. Add a separate DisplayParts→effective decoded interval diagnostic and protect the source's real switchback extent using existing topology metadata. Independent operator description and retained named OSM main-track ways support the topology; do not infer a new connection from proximity. Full Japan verdicts remain pending.

Coordination: route-resolution chat owns raw-source consolidation and `.gitignore`; through-services chat owns `JapanThroughServices`/ThroughWorkbench. Alignment chat owns this auxiliary app and the bounded Nihongi/Tabata display changes. Heavy-job order agreed route → alignment → through; no simultaneous builds/full tests.

## Physical branch ink correction and current checkpoint

The user clarified that one main and one spur must meet at the actual switch,
without overlapping station-order legs or artificial180-degree bends. Exact
shared survey spurs now draw once, main continuity is limited to shallow
continuations, and all three offset fork endpoints meet at the surveyed point.
Station anchoring preserves genuine exact return tracks. Physical source station
intervals and service/date identities remain unchanged.

- [x] Identify the28 exact retrace cases in27 Japan lines and remove the observed
  cross-part exact repeated edges in production geometry.
- [x] Integrate22 published lines /63 display parts, lane/follow/reference remaps,
  sharp-main boundary metadata, targeted display fixtures and inspector parity.
- [x] Focused Node regressions (13 passed), production computation of19 physical
  fork junctions (zero endpoint gap), and targeted native-chain input queries.
- [ ] Scheduled focused Swift execution, incremental main/Inspector Catalyst
  builds and one native branch observation. Parser success is not typechecking.

The current ownership ledger supersedes the earlier informal heavy-job order.
Alignment owns its generated display artifacts and Inspector wiring end to end;
shared integration schedules the heavy window while the restored external job
runs. No routine peer status messaging or simultaneous heavy work. Exact files,
results and remaining national coverage are recorded in the alignment result
ledger. All nationwide visual verdicts remain separate from these source repairs.
