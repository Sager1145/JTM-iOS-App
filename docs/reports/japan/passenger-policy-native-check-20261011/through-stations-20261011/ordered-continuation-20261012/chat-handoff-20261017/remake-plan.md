# Diagnostics remake — active user priority, 2026-10-17

Railway analysis is paused until this work is usable. User requested Matt skill workflow, one app doing all diagnostic functions, removal of duplicates, and automatic screenshots from one request containing exact line, scale and other requirements.

## Intended result

One RailDiagnostics application/launch target, with alignment, physical routes, through history, evidence/reviewer workspaces and existing extraction/manual inspection capabilities. One request interface owns exact scope, capture settings and durable results. Native capture plans and operates the entire requested line without per-frame UI commands. No change to railway production geometry/topology. Saved audit captures and their historical metadata remain intact.

Matt codebase-design: deepen the request-to-result module; keep camera planning, capture admission, snapshotting, receipts and resume behind one interface. Existing workspaces become implementation, not separate applications users must coordinate. Matt implement/TDD: test the specified request interface and camera-coverage plan, then integrate one focused native nondefault-scale capture. Current repository verification policy supersedes full suites and automatic commits in upstream skills. No commits/pushes.

## Existing work to preserve

Integration chat owns and is validating current unified host. Current UI/heavy slot remains with it. Audit chat reads only implementation until explicit file-protocol handback. Avoid competing builds/edits. Existing unified source/session results and saved observations are user changes and must be integrated, not replaced.

## Remaining concrete changes

1. Capture request/settings: exact line, optional interval/station scope; one explicit zoom per request initially, viewport width/height, appearance and requested output modes. A new request/session can choose another scale. Unsupported fields/values fail visibly. Defaults remain documented. Bound output/session identity to the settings and actual camera. Reject incompatible saved captures without deleting them.
2. Capture coverage: choose overlap/spacing appropriate to zoom, viewport and latitude; retain both interval endpoints and short tails. Use owning-line geometry for camera targets. Full-line smoothing precedes clipping. Neighboring railways cannot redirect own station approaches.
3. Single app: remove standalone app targets/projects/workspace entries and old standalone launch paths while preserving Alignment/Route/Through source functionality and portable package tests as internal modules. Update live build/launch helpers and docs together. Preserve historical reports, references and snapshots.
4. Installed duplicates: after current operation settles, identify exact old diagnostic .app copies before retiring only those redundant app bundles. Preserve Main and evidence directories. Prefer recoverable relocation when removing old local copies; host permissions still apply.
5. Focused validation: request validation and nondefault-scale coverage/resume behavior through the portable interface; one incremental unified build at a time; actual automatic native capture at a requested nondefault zoom/viewport and evidence receipt inspection. Reuse integration's unchanged route/history evidence. Capture completion remains distinct from pixel/physical acceptance.

## Ownership checkpoint

Audit wrote latest user requirements in audit-status.md. Integration should finish its current bounded native operation, record the request acknowledgement/current edits and hand back or explicitly continue ownership of the remake before audit edits shared source. Until then audit only prepares this plan and read-only inventory. Next railway line request is drafted but must not launch.
