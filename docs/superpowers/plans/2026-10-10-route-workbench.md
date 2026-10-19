# Route Workbench Implementation Plan

> For agentic workers: use executing-plans; repository verification policy and existing user authorization supersede automatic commits, wrapper scripts and full suites.

Goal: Local Mac Catalyst batch workspace reusing production route resolution and exporting supported physical interval selections.
Architecture: Separate app bundle compiles the production app sources with ROUTE_WORKBENCH, selecting a dedicated SwiftUI shell. RailCore provides a pure export projection; the workbench preserves canonical inputs and takes result snapshots for cancellation/export.
Tech stack: Swift 6, SwiftUI, Observation, existing RailKit, Xcode Mac Catalyst.
Spec: docs/superpowers/specs/2026-10-10-route-workbench-design.md

## Constraints and review focus

No second solver, no retired verifiers or broad test/build campaigns, no publishing/commits, no edits to input files or iOS app container. .xSmall ... .xLarge typography. Export requires complete nonhistorical physical interval selections, preserves explicit choices and repeated ordered intervals. Raw input indexes must never index normalized solver sections. Cancel retains a workbench snapshot before clearing the route store. One heavy job at a time.

## Tasks

- [x] Pure RailCore ResolvedRouteExport and focused regression cases written (not executed): complete selections materialize missing IDs; explicit IDs survive; partial/invalid/missing selections keep original; repeat intervals stay ordered.
- [x] Independent Catalyst Xcode project/scheme, production entry compile condition and resource build repair for retired verifier reference.
- [x] Workbench model/UI: background import preserving imported records; production batch progress; cancellation snapshot; result selection/detail; export and report via document picker.
- [ ] Inspect relevant Swift/JS import/section formats; run focused export regression when no other heavy task is active; one incremental Catalyst build then launch and observe one small existing input. Record limits and result in design document. No measured speedup claim.

Pre-flight: project includes parent UI via ROUTE_WORKBENCH; UI consumes ResolvedRouteExport.Selection; model retains imported records, production store normalizes solving inputs, and export uses a compatible section template without introducing unproved inferred choices. Project worker owns only new project/scheme; parent owns Swift, test and resource script dependency.

2026-10-10 result: User explicitly requested source completion without running. Build, test execution and launch remain deferred, not failures. Source review corrected premature inferred-ID export, per-row linear status lookup, and interleaved-scope network loading. Independent read-only follow-up confirmed these fixes and found no further source-level blockers; it does not establish compilation or runtime correctness. The workbench stores imported records; RiddenRouteStore owns solving normalization; only proved export selections are projected into compatible sections. See design document for limits.
