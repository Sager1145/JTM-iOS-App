# Rail Diagnostics

**RailDiagnostics is the only diagnostic application.** Open `../JTM.xcworkspace`, choose **RailDiagnostics**, and run on **My Mac (Mac Catalyst)**. Main remains a separate production application.

| Internal workspace | Implementation | Purpose |
|---|---|---|
| Alignment | `RailAlignmentInspector/Sources`, `InspectionKit` | Native basemap screenshots, display geometry, extraction and scoped observations |
| Physical routes | `RouteWorkbench/App` | Production route solving, journey evidence and consistency review |
| Through history | `ThroughWorkbench/App`, `WorkbenchCore` | Dated service patterns, historical issues and patch documents |
| Tasks & evidence | `RailDiagnostics/Sources` | Human task creation, agent requests, progress, resume and evidence records |

The old directory names identify internal modules and preserved evidence, not independently buildable apps. The three standalone projects and entry points have been retired. Build and launch only [RailDiagnostics](RailDiagnostics/README.md). Historical reports/captures remain usable under their recorded contracts; do not recapture three copies by default.

Humans create/open tasks in the app; agents pass `--diagnostic-request /absolute/request.json`. Both use the same exact scope and capture-settings contract. Every assigned keyboard command is labelled in its workspace. Camera planning, native screenshots and durable results happen inside the app. Main is used only for the final production composition case that evidence review requires.

Follow `../VERIFICATION.md`: one heavy job at a time, focused tests/builds and bounded native observations. Compilation, capture counts and zero consistency failures do not establish geographic or physical acceptance.
