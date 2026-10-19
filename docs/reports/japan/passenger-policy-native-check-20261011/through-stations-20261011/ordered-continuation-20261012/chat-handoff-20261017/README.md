# Two-chat handoff — 2026-10-17

> Historical handoff. For the 2026-10-19 done / partial / rejected / not-started inventory, read [work-inventory-20261019.md](work-inventory-20261019.md), then the current [audit-status.md](audit-status.md). Later explicit apply and Main evidence supersede older pending notes here. The former three-App routine and old installed bundle paths below are historical. Data-structure overhaul preparation is linked from the inventory; no schema migration has been performed by this documentation task.

Repository: /Users/sager/Documents/GitHub/JTM-iOS-App

## Latest user instructions (authoritative)

Continue the ordered line audit and record candidates. Check both station/line offsets AND disconnected lines/breakpoints, interval seams, station approaches, intended connections and false joins. Blue passenger platforms define station extent; purple transfer passages are excluded. User reports Namboku, Marunouchi and Chiyoda line station/line offsets; retain these candidates without abandoning ordered review.

Use inspector apps for most work. Integrate them better with ChatGPT for efficient checking. Unify the diagnostic apps. Main is only the final check. The previous three-app-plus-every-interval-Main routine is historical evidence, not a mandatory future matrix. Do not repeat it mechanically.

User explicitly requested two new chats to finish the work and document progress/tasks. This supersedes earlier instructions forbidding new chats. Root stopped native operations after quitting Main. No production code/data changes, builds, or tests were performed in the root's latest audit session; only scoped audit evidence/reports/helpers were written. No commits/pushes authorized.

## Evidence and progress

Base directory (relative to repo): docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012

- Read continuation-handoff-20261015.md for older context, results.md for completed baselines, and ../repair-lessons-20261012.md for retained lessons. Baseline complete does not mean geometry repaired or platform midpoint accepted.
- #31 Tokaido (jp-東日本旅客鉄道-東海道線): baseline complete. tokaido-complete/complete-analysis.md, interval-review.json, review-progress.json. Three apps each 348 effective views, all root-reviewed (third had one failed capture with scoped retry retained); Main 32 valid ON/OFF pairs reviewed. Existing interval #6 Shinagawa→Oimachi display repair preserved. Station own-platform longitudinal centres remain open.
- #32 Sotetsu Main (jp-相模鉄道-相鉄本線), 横浜→海老名: sotetsu-main-complete/. 18 stations, 17 intervals, 93 views per inspector. All THREE apps captured 93/93 with zero failures, idle confirmed, and root personally viewed sheets 00–23 in EACH app: 279 views total. Read primary-observations.md, secondary-observations.md, third-observations.md and native/{primary,secondary,third}/capture-index.json. Do not recapture unchanged evidence without a concrete need.
- Sotetsu interval counts: [3,4,3,4,4,3,7,6,7,7,5,7,7,7,5,5,9]. The historical plan was lexicographically ordered (#10 before #2); corrected contact sheets use numeric interval order. Discarded initial primary sheet layout is retained separately and was not reviewed.
- Sotetsu has no displayIntervalCoordinates. dependency-review.json: owning line data equal across source package, three installed inspectors, original Main at capture start. Recheck relevant dependencies if source changes; avoid full-tree hash custody.
- Sotetsu Main case 00 (横浜→平沼橋) ON/OFF saved and root reviewed. Cases 01–16 NOT captured/reviewed. Last attempt was interrupted by lockscreen; after user returned, Main camera was manually/off-plan at center 36.395395,122.196790, distance 9806696.3, network off. Root quit Main; do not reuse that state. review-progress.json still describes earlier lock limitation; this handoff records subsequent quit. Fresh launch is needed if a final Main check is warranted under updated workflow.
- Main case 00 was captured with proper planned center 35.4621345,139.6184925 and distance 2321.5. Main original screenshots dark mode; inspector basemap light mode. Case 00 does NOT accept platform alignment.
- User offset reports: user-offset-candidates-20261016.md. Include Namboku, Marunouchi, Chiyoda and blue-vs-purple interpretation.
- Sotetsu candidates: 横浜 shared-anchor acute hook vs own Sotetsu terminal; 平沼橋→西横浜 local fork/cut bend; varying southern offsets through corridor; 大和 platform identity distinct from crossing Odakyu Enoshima; 相模大塚 and かしわ台 broad yards not platform extent; 海老名 endpoint distinct from Odakyu/JR. Read detailed notes rather than inferring accepted fixes.
- Breakpoints are now explicit scope. Existing continuity observations are useful, but were not a systematic breakpoint verdict. Mark unexamined joins pending, distinguish visual gaps from physical connectivity and cartographic/layer clipping.

## Ordered continuation

Unique lineID first appearances in ios/refactor-parallel/alignment-passenger-local-recheck-20261010.json, ordinal = unique index + 2; total 658. Finish #32 Sotetsu scoped baseline note, then #33 jp-西日本旅客鉄道-北陸線-p1, #34 jp-西日本旅客鉄道-大糸線. Confirm order from source. No claiming nationwide completion.

## Task ownership / coordination

1. Diagnostic integration chat owns auxiliary app implementation and its own integration-status.md. Inventory RailAlignmentInspector, RouteWorkbench, ThroughWorkbench and shared dependencies, choose a cohesive diagnostic app with shared state/evidence identity. Improve agent-readable scoped commands/results/resume and focused breakpoint/offset evidence. Preserve useful capabilities and existing reports. Start by source review and a concrete plan; progress with authorized implementation, without routine approval gates.
2. Audit chat owns audit reports/candidates and audit-status.md; it is initially the ONLY native UI owner. Most work stays in inspector app(s); Main final check only. Continue Sotetsu breakpoints using existing captures/data first. Before starting native work, record active capture/solve in audit-status.md, then record idle after actual confirmation. Integration chat does not touch UI or replace installed apps during audit's active native operations.

Only ONE heavy build/solve/capture at a time across chats. Integration chat may read/edit source while audit reviews evidence. Before first build/install/runtime validation, request a handover in integration-status.md; audit chat checks it between bounded operations, finishes current operation and marks audit-status.md idle/released. Audit then continues report/data review while integration validates and publishes available build/bundle paths in integration-status.md. Never edit each other's status files; read them to coordinate. Do not run concurrent builds or manipulate the same app. No new umbrella runners, automatic matrices, or national campaigns. Root no longer operates UI.

Read AGENTS.md, ios/AGENTS.md, current ios/VERIFICATION.md and applicable skills. Preserve other chats' changes. Verification is focused, one heavy job at a time, no automatic pipelines. No commits/pushes/merge/publish/transcript sharing.

## Installed apps and UI

Inspector bundle directory: /Users/sager/.codex/visualizations/2026/10/11/01a12c88-e8a9-7741-9046-e94472852230/rail-inspector-apps/
- RailAlignmentInspector.app
- Kisuki Keiyo Inspector.app
- Hakone Inspector.app
All idle at last confirmation. A getApp can bind an existing old instance despite open -n; verify actual output path in AX. Quit old instance before relaunching with a different --batch-output path if necessary. Never press global Retry Failures or batch-all for a scoped line.

Original Main: /Users/sager/Library/Developer/Xcode/DerivedData/RailMap-cysvihgspfvwbzatdiakpqjbxkno/Build/Products/Debug-maccatalyst/RailMap.app (com.JRM.RailMap). Currently quit. getAX after quit may relaunch an unconfigured default instance; avoid it.

Native UI only via mcp__cua_repl. Read its docs initially; snapshots/action freshness required. No AppleScript/osascript or alternate UI automation. Manual unlock required if Mac locked; do not bypass lock. Do not infer captures from launch success. Snapshot counts are not alignment verdicts.

Inspector: Lines tab→exact lineID search→select result→fresh AX confirm ID/start station/point count/output directory→Cmd+Alt+Shift+C current-line capture. Cmd+Shift+C current interval. Cmd+Alt+S export same view. Cmd1..6 modes; Cmd7/8 zoom17/18, CmdShift8 zoom19. Long interval complete coverage matters; preserve failed/partial captures.

Main final check must verify actual network rendered/off, camera, viewport, loaded basemap; exclude blank grids and camera mismatches. ON/OFF metadata/frames retained. Single-line inspector rendering does not prove production multi-line joins, offsets, collapse or dates.

Scratch helpers for Sotetsu (existing only, not required runners): /private/tmp/jtm-sotetsu-sheets.py; jtm-sotetsu-plan.cjs; jtm-sotetsu-launch-one.py; jtm-sotetsu-pair-sheet.py. Source evidence is in repo reports. Do not depend on ephemeral CUA variables from root. Main plan in sotetsu-main-complete/main-original/camera-plan.json. Helpers create derived sheets or launch existing app; no production changes.

Source entry points: ios/auxiliary/RailAlignmentInspector/Sources/{InspectorApp,InspectorModel,InspectorMap,BatchCaptureController,BatchCaptureGeometry,InspectionEvidence,InspectionViewpoints,AppleMapAnalysisService}.swift; ios/auxiliary/README.md; ios/auxiliary/ThroughWorkbench/; locate RouteWorkbench with rg. Do not assume app clone names correspond to separate implementations.
