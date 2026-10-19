# Rail Diagnostics — one app, one task interface

Active remake, 2026-10-17. Railway analysis pauses until the requested app refinement has a verified build and native observation. The user requires automatic exact-line screenshots at specified scale/requirements, one app with all diagnostic functions, human and agent control, and visibly labelled keyboard controls.

## Experience

Use the standard native SwiftUI profile: clear hierarchy, system colors and controls, semantic status and a large map canvas. Retain the compact top workspace selector instead of adding an outer sidebar beside the alignment/route workspaces' existing sidebars. A task-first dashboard is the entry point; the specialist workspaces remain available for map inspection, physical solving, history and patch work.

The dashboard creates/opens/resumes tasks, shows exact scope/settings, live counts, screenshot previews/full-size Quick Look, evidence paths and evidence-bound review notes. Recent tasks preserve their session directories. A form produces the same request used by agents; there is no second human capture engine. Blank/error/loading/partial/completed-evidence states are explicit. Every assigned shortcut is labelled in the active UI; contextual menus use the same live state and actions. Uncancellable work says it is finishing rather than offering an ineffective Pause.

## Module design (Matt codebase-design)

The deep module is request-to-evidence. Its interface is an immutable DiagnosticRequest and durable status/result/index/receipt files. Implementation owns exact line/station/interval selection, camera coverage planning, full-line smoothing, snapshot admission, native rendering, evidence identities and resume. Callers do not manually select each camera or trigger each screenshot.

InspectionKit owns portable request/settings/coverage/scoped-resume behavior and tests. RailDiagnostics owns the session and all long-lived workspace models. Injected workspace state is keyed to the owning session, so switching workspaces preserves work and a new task cannot silently retain the old model. Focused command bridges publish availability and action closures for the current scene. Workspace capture changes update the same durable agent result.

The old Alignment/Route/Through directories remain internal implementations and portable packages, not independent app targets. Only RailDiagnostics is in the diagnostics workspace and current launch helpers. The production Main app stays separate; its entry point is excluded only in the diagnostic compilation condition. Production geometry/topology is unchanged.

## Capture contract

One explicit line, optional interval/station intersection, zoom10…20, bounded viewport at1×, light/dark and selected native image modes. Unknown fields or unsupported requirements fail before capture. At higher zoom/smaller viewport, camera spacing contracts to retain overlapping complete-interval coverage and endpoint tails. Camera targets use owning-line display geometry, independent of neighboring/crossing lines. Full-line smoothing precedes clipping. Snapshot projection witnesses distinguish requested camera parameters from the returned native mapping.

Alignment optionally reads a requested absolute Japan compact JSON through existing `inputPath`, using the same loader, full-own-line rendering and capture implementation as bundled input. A supplied missing/invalid file fails without a bundled fallback. The human form retains picker bytes under their original basename before releasing security scope; while copying, workspace/action changes and submission are disabled. Task cards expose the source, workspace capture retains it, and result/geometry files record the actual package path and source. Route keeps its required journey input; through rejects inputPath.

Requests and receipts bind all settings and relevant geometry/render inputs. Compatible subset reuse preserves broader-plan numeric folders and original files, while returning only the requested scope. Incompatible inputs/settings remain explicit, with original evidence retained. A single capture lease settles before another snapshot starts. Partial/failed views remain resumable; no automatic geographic/physical acceptance or national/multiple-app matrix.

## Agent interface and validation

`--diagnostic-request /absolute/request.json` is the launch interface; the human form/import uses the same request. `run-status.json` exposes active preparation/running state; `result.json`, `capture-index.json`, view metadata, candidate tasks and reviewer notes remain local durable results. Invalid requests report an error in the UI and `last-error.json` where a valid output directory was supplied, without replacing prior accepted result files.

Focused portable tests cover exact scope, unknown/invalid settings, high-zoom coverage/endpoints and subset evidence identity. One coordinated incremental Catalyst build and bounded native automatic request check establish runtime behavior. Existing unchanged route/history integration evidence is reused. UI keyboard/focus, task form, screenshot preview and nondefault scale are observed directly; no pixel/performance/accessibility-wide claims are inferred from compilation. No full suite, benchmark, national runner, commit or push.

## Six simplifications implemented in source (2026-10-17)

The route workspace no longer reads its retired launch flags or owns automatic report destinations. Its manual solve action creates a DiagnosticRequest through the shell; the session invokes the same production solver used by agent requests. Alignment also has no legacy batch flags or local orchestration fallback: one admitted input scope feeds candidates and capture configuration.

BatchCaptureController owns the scoped completion summary and a revision for successfully persisted capture changes. Session polling writes only the small run status when receipts have not changed; candidate tasks are written once per admitted session, and index/gallery refresh follows actual evidence changes. Final state and review updates still persist the result. The gallery remains a read adapter over the durable agent index, rather than a second editable evidence store.

Requested image modes enter the native capture implementation before PNG encoding; native snapshot dimensions are checked before encoding. Unrequested images are not generated or decoded back for dimension checks. Through dependency hashes are calculated alongside the actor-owned document using the same canonical bytes, returning only digest strings to the main actor. Final build and bounded native observations remain required; these source changes do not establish a performance measurement.

## Candidate input evidence (2026-10-18)

[The bounded input-interface evidence](Evidence/20261017-remake/candidate-package-input-20261018/README.md) retains the incremental build and agent/human prepared requests plus a missing-input failure. The focused inputPath contract test passed in the parent tool record. These checks establish input plumbing only; changed-geometry resume, repaired-corner pixels and Main composition are separate evidence.
