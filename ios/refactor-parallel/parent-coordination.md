# Parent coordination: lightweight verification proposal

## 2026-10-10 — verification pause

The coordinating chat requested that JTM verification/build/test/benchmark pipelines and automatic verification-to-delivery loops stop, with scripts removed by that coordinator and their purposes retained in prose. This chat does not own that removal or ios/VERIFICATION.md and will not modify/recreate those files. No commit, push or publication accompanies this proposal.

Read-only process inspection found no active matches for this chat's historical Main37 Statistics extent runner, network exact-reuse/composite runners, kernel-counter runners, isolated package runner or Phase38 delivery scripts. The current root subagent inventory has three completed workers and no active child. No unrelated chat, CLI, simulator or process was terminated. This chat will start no further verification pipeline or delivery loop under this instruction.

## What the earlier checks did

- Frozen resource and source comparisons tied evidence to a particular implementation and prevented concurrent CLI bytes from being mistaken for accepted main. The repeated full-tree inventories were expensive; retain the existing receipts as historical evidence.
- Isolated package tests separated suites to limit process memory and collected LLVM coverage. The last audited complete-package report was incomplete; selected-suite success did not establish full coverage.
- Original UI gestures/assertions checked camera, keyboard, accessibility bounds, editing and footer visibility. Dedicated devices prevented interruption of other CLI work. Failures and infrastructure problems were recorded separately.
- Footprint/kernel samplers guarded exact owned App processes against the memory budget. Paired runs attempted to distinguish stable/peak changes from sampling noise; a single budget pass never established strict reduction.
- VM/Instruments and native-overlay diagnostics investigated allocation ownership, rendered geometry and pixels. Native texture stack attribution was limited to the observed population; scalar renderer readiness was insufficient to prove presented pixels.
- Alternate-index delivery scripts preserved unrelated staged/working changes and pushed only frozen validated blobs under a shared lock. They are not to run automatically now.

Existing production work, recordings, logs, JSON receipts, old failure evidence and audit prose are retained. Evidence is not relabelled as complete merely because its scripts are removed.

## Proposed verification for this chat's scope

1. Start with a chat-led review of the actual changed code/data and directly affected dependencies. Confirm scope, file ownership, geometry/date/pending semantics and concurrency/lifetime reasoning. Review worker conclusions against the changed lines, rather than dispatching another blanket verification campaign.
2. Reuse applicable prior results when relevant implementation, inputs and assumptions remain unchanged. Identify their source snapshot and limitations in prose; do not rescan or hash the full repository by default.
3. For an unresolved substantive change, name the concrete uncertainty. Run one focused existing regression test OR one incremental build only if it can answer that uncertainty and execution is subsequently requested/necessary. Do not run either for this documentation-only proposal.
4. Do not default to complete before/after suites, repeated synthetic harness qualification, full source/product hash trees, multi-platform matrices, profiling or performance loops. Do not recreate removed scripts to obtain equivalent expensive checks indirectly.
5. State what review establishes and what still needs observation. Chat review can support structural reasoning; it cannot prove runtime success, physical memory reduction, leak freedom, rendered pixels, frame timing, launch performance or a complete platform matrix. Those requirements remain open until appropriately scoped evidence exists. No assertion, fixture count or product gate is weakened to hide uncertainty.

This is a bounded proposal, not a rewritten implementation or new acceptance receipt. The chat stops after recording it; further verification and delivery are paused.


## Standalone scratch automation cleanup — 2026-10-10

The coordinator requested removal of this chat's own scratch verification automation. The following explicit 33 regular Python files belong to parent Main34–37 experiments and Phases31–38 delivery work; only these named paths are removed, without recursive or broad-pattern deletion.

Purposes: keyboard/editor/iPad and accessibility/clearance runners drove original UI gestures and sampled owned App memory; Statistics runners tested footer visibility and collected native scroll diagnostics; normal-map and exact-reuse/composite runners tested original regional toggles with memory stops; kernel-counter and current-VM runners collected public memory evidence; serial wrappers enforced stop-on-failure; phase scripts checked scoped receipts and performed alternate-index delivery. Their previous pass/fail limits remain in the existing ledger and recorded results.

Directory: /private/tmp/jtm-refactor-resume-20261009

Removed standalone files:

- commit-phase33.py
- commit-phase34.py
- commit-phase35.py
- commit-phase36.py
- commit-phase37.py
- commit-phase38-handoff.py
- commit-phase38-transfer.py
- prepare-commit-phase31.py
- run-layout-scroll-probe-main35.py
- run-network-composite-prototype-main37-1.py
- run-network-composite-prototype-main37-2.py
- run-network-exact-reuse-main37-1.py
- run-network-exact-reuse-main37-2.py
- run-network-exact-reuse-main37-3.py
- run-network-exact-reuse-main37-serial.py
- run-statistics-fixed-extent-main37.py
- run-statistics-footer-reveal-main36.py
- run-statistics-footer-scroll-probe-main36.py
- run-statistics-footer-scroll-probe-with-collector.py
- run-workspace-accessibility-shape-main35-drag.py
- run-workspace-accessibility-shape-main35.py
- run-workspace-clearance-main34-1.py
- run-workspace-clearance-main34-2.py
- run-workspace-clearance-main34-3.py
- run-workspace-clearance-main34-serial.py
- run-workspace-stable-keyboard-main34-1.py
- run-workspace-stable-keyboard-main34-2.py
- run-workspace-stable-keyboard-main34-3.py
- run-workspace-stable-keyboard-main34-date-repeat.py
- run-workspace-stable-keyboard-main34-editor.py
- run-workspace-stable-keyboard-main34-ipad.py
- run-workspace-stable-keyboard-main34-remaining-layout.py
- run-workspace-stable-keyboard-main34-serial.py

Production and diagnostic source (including Swift fixtures and C counter source), logs/results/recordings/captures, data inputs, frozen sources/products and other chats' scripts remain untouched. No replacement automation, build, test, benchmark, commit or push was started.
## 2026-10-10 — resumed bounded repair

### Follow-up state-owner review while the route chat owns the heavy-job window

### Ready handoff under task-ownership-20261010.md

UI lane owns only the allocated UI interaction files and this ledger. No routine peer messages, shared resource edits, automatic delivery or heavy job were started. The integration owner schedules the next observation after both the route batch and its restored external job are accounted for.

- Existing test: `RailMapUITests/WorkspaceEditingTests/testDetailEditsSurviveVisibilityChange`. Its own launch fixture requests expanded Search with the exact journey ID, edits/saves, presses `journeyBackToList`, then long-presses the returned row. Keep that flow and its deadlines unchanged. Run this single case first; the separate Undo test is not evidence for the returned-list issue.
- Required product: an iPhone Simulator Debug build from the current `ios/RailMap.xcodeproj`, scheme `RailMap Debug`, containing `RailMap.app` (bundle ID `com.JRM.RailMap`) and the `RailMapUITests` runner (test bundle ID `com.japantrainmap.RailMapUITests`). Historical frozen candidate binaries cannot answer the current combined-source question. Use one UI-lane-only DerivedData/results directory and one explicitly assigned idle simulator. Reuse an incremental product only if it includes the actual current UI changes and required dependencies; do not build while another heavy job is active. Simulator availability and scheduling are prerequisites, not observed here.
- Temporary observation stays within owned `BottomChrome.swift` and `WorkspacePanelPage.swift`: at suspension reset, visible-detent writes, and each height decision, record ordered timestamp, `isSuspended`, requested `detent`, incoming and retained height, `restingHeight`, `previousRestingHeight`, elapsed time since rest, and outcome (`belowCompact`, `unchanged`, `continuous`, `bounceRejected`, `accepted`). At the returned viewport, record `morph.stage` and `showsContent`. Read `ResidentMapChrome`, `ContentView` and `WorkspacePresentations` as dependencies; editing these unlisted shared files requires an integration assignment first. A DEBUG-only opt-in print/trace at these existing boundaries is sufficient; no new runner or logging framework.
- Decisive outcomes: a visible expanded sheet with compact morph after a rejected restored height demonstrates the stale-height route; suspension still true after Back points to the outer presentation lifecycle; neither means the bounce hypothesis is unsupported and another UI input/presentation path needs inspection. Capture the final failed interaction as well as the restoration events. Remove temporary observation after resolving that specific uncertainty.
- Current evidence: syntax parsing and diff whitespace checks passed for the adopted Undo header clipping; no focused UI runtime pass, production list fix, memory improvement, or full-plan completion is claimed. No integration action is requested yet beyond scheduling that one observation.

No build or runtime job was launched. RouteWorkbench/solver/source relocation, alignment/branch geometry, and ThroughWorkbench/history remain with their respective chats; their source and staged changes were not touched.

The earlier expanded→compact→expanded explanation needs an additional condition. `BottomChrome.settle(reporting:)` exits when the reported height is within 0.5 points of `liveHeight`, before updating resting history. After the current suspension-edge reset, if retained `liveHeight` already equals expanded, the first expanded sample changes no history; compact then sets previous=0/resting=compact, and final expanded is accepted. That sequence alone cannot explain the failure. If the initial retained height differs, the first expanded sample can establish resting=expanded; compact sets previous=expanded, and expanded within 150 ms can then be rejected. Callback ordering relative to the reset is another unobserved dependency. The reset already present in the shared source is preserved; no speculative restoration state was added.

State owners: `ContentView.hidesWorkspaceMenu` combines the suspension flag and child sheet kind; actual `WorkspacePresentations.onDismiss` clears suspension. The resident modifier ignores height preferences while suspended. `ResidentSheetMeasurements.height` is retained across that period, `ResidentMapChrome.syncMeasurements` maps accepted height to `PanelMorph.stage`, and `WorkspacePanelViewport` disables its content only for compact. The selected detent is separately backed by `ContentView.stageSelection`; restoring journey selection does not explicitly collapse it. This separates the possible stale-height path from the independent outer hit-testing suspension path.

Minimum remaining observation: run only the existing `testDetailEditsSurviveVisibilityChange` once when the shared heavy-job window is free, with temporary bounded DEBUG output at the suspension change, detent setter and height acceptance/rejection. Capture event order, suspension value, requested stage, incoming/retained height, resting/previous heights, bounce elapsed time and resulting morph stage around Back. At the failed row interaction, distinguish compact-disabled content from an uncleared outer suspension. No new runner, full matrix, full-tree hashes or logging framework is needed. Without those values, native failure attribution and a production fix remain unproven. The Undo repair's parse/diff success remains syntax-only evidence.

The user requested fixing to resume. Adopted only the previously diagnosed Origin-row clipping correction into the live `WorkspaceEditingTests.swift`. After Undo, the test now measures Edit's navigation header and opts into excluding that covered area from reveal/tap bounds. The original queries, eight-drag budgets, endpoint-role checks, and final Undo/region checks remain; other helper callers keep their existing bounds. No production objects or memory allocations are introduced by this test-only repair.

Focused diff whitespace checks and Swift frontend parsing passed. The original UI case previously failed before its final assertions; a fresh runtime result is still required before claiming that case passes. No broad matrix, verification runner, build, commit or push was started.

Independent read-only review of the disabled returned list found a possible restored expanded→compact→expanded sequence rejected by the drag-bounce filter. The shared BottomChrome suspension-history reset was already present and was preserved. Actual height sequence remains unobserved, so this review does not establish the production root cause or justify claiming that failure repaired. Strict whole-app footprint and remaining original-plan goals stay open.
