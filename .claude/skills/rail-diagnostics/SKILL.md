---
name: rail-diagnostics
description: Drive the Rail Diagnostics Mac Catalyst app (com.JRM.RailDiagnostics) to capture and review railway alignment evidence, and run the Main cold ON/OFF final check. Use when a request asks for native alignment captures, a diagnostic session, station or interval placement evidence, or Main (com.JRM.RailMap) composition proof.
---

# Rail Diagnostics

Use for native alignment evidence on a railway line (basemap/display/smooth captures) and for the Main final check. Follow `AGENTS.md` and `ios/VERIFICATION.md`; do not build here (build only through `ios/verify.sh build --target diagnostics` when the app is stale).

## CLI (`python3 -I ios/tools/verification/diagnostic-run.py`)

```sh
# plan + capture a scope; writes railway-evidence/local/requests/<name>.json, opens the app, waits
diagnostic-run.py capture --line 'jp-伊予鉄道-横河原線' --intervals 10,11 --stations 008791 \
  --viewpoints 'jp-伊予鉄道-横河原線#10#point-0' --zoom 19 --size 2400x2000 \
  --appearance light --basemap standard --modes basemap,smooth \
  --input /abs/candidate-package.json --name my-slug --timeout 900
diagnostic-run.py capture --line ID --intervals 1 --dry-run      # print request only
diagnostic-run.py send /abs/request.json                          # existing request
diagnostic-run.py status <session-dir-or-name>
diagnostic-run.py views  <session-dir-or-name> --interval 11
```

Output is one compact JSON: `{requestID,state,message,capturedCount,failedCount,pendingCount,invocationID,processID,sessionDirectory,views:[{viewpointID,directory}]}`, or `{rejected:true,reason}`. Exit 0 ok, 2 rejected, 3 timeout, 4 failed/partial/paused. Default app: `~/Library/Caches/jtm-rail-diagnostics/Build/Products/Debug-maccatalyst/RailDiagnostics.app` (`--app` overrides). Evidence root honors `RAILWAY_EVIDENCE_ROOT`.

## Rules

- One fresh session directory per request. `action` and `requestID` are part of request identity; a changed request on an existing session is refused (`changedRequest`). Use a new `--name`. The CLI refuses an existing session dir.
- `capture` plans by itself; do not run a separate `prepare` first.
- One native app job at a time across all chats. Check `status` of recent sessions (`active:true`) and the process list before sending.
- `open` success is not capture success. Trust only the `run-status.json` / `result.json` whose `requestID` matches yours (they also carry `invocationID` and `processID`).
- Pre-admission rejections write no run-status. They are appended to `railway-evidence/local/diagnostics/inbox/rejections.jsonl` (timestamp, requestPath, requestID, sessionDirectory, reason, processID) and, when the session directory is known, to `<session>/last-rejection.json`.
- Captured is not reviewed is not accepted. `result.json` leaves verdict `pendingReview` and Main final check pending. Read `candidate-tasks.json`, record `review-notes.json`, keep original screenshots, and see `ios/auxiliary/RailDiagnostics/README.md` ("Shared evidence and recovery") and `DESIGN.md` for the review checklist.

## Background UI control (computer-use `app_menu`)

Prefer `app_menu` over clicks/keys so the app need not be frontmost. Bundle id `com.JRM.RailDiagnostics`. Paths:
`["Diagnostics","New diagnostic task"]`, `["Diagnostics","Open task request…"]`, `["Diagnostics","Run / resume task"]`, `["Diagnostics","Pause current operation"]`, `["Diagnostics","Previous captured view"]`, `["Diagnostics","Next captured view"]`, `["Diagnostics","Tasks & evidence"]`, `["Diagnostics","Alignment"]`, `["Diagnostics","Physical routes"]`, `["Diagnostics","Through history"]` (workspace switch; titles confirmed live 2026-10-20). Workspace-specific items (viewpoint/station navigation, capture, export) are added to the same Diagnostics menu only while that inspection workspace has focus; otherwise the menu shows "Select an inspection workspace". List the menu first with `app_menu {list:"Diagnostics"}` and press only titles it returns.

| Shortcut | Command |
|---|---|
| ⌃⌘N | New diagnostic task |
| ⇧⌘O | Open task request… |
| ⌘↩ | Run / resume task |
| Esc | Pause current operation |
| ⌃⌘1…4 | Tasks / Alignment / Physical routes / Through history |
| ⌃⌘J / ⌃⌘K | Previous / Next captured view |
| ⌘F / ⇧⌘G | Search / Go to coordinates |
| ⌘1… | Comparison modes (in order) |
| ⌘7 / ⌘8 / ⇧⌘8 | Detail z17 / z18 / z19 |
| ⌘Home | First detailed viewpoint |
| ⌘9 / ⌘0 / ⇧⌘0 | Frame station / next interval / full line |
| ⌘B | Toggle basemap peek |
| ⌥⌘← / ⌥⌘→ | Previous / Next viewpoint |
| ⌥⇧⌘← / ⌥⇧⌘→ | Previous / Next station |
| ⇧⌘P / ⇧⌘N | Previous / Next pending interval |
| ⌥⌘S | Export same-view evidence |
| ⇧⌘C | Capture current interval |
| ⌥⇧⌘C | Capture current line |
| ⌘O | Import journeys JSON / working document (route, through workspaces) |

Pause waits for the active capture lease; the workspace switcher is disabled while work is active.

## Main final check

`bash ios/tools/verification/main-cold-pair.sh OUTDIR STATIONID LAT LON SPAN STORAGEID [RailMap.app]` (bundle `com.JRM.RailMap`). Cold-launches Main with the network layer ON, then OFF (unknown layer key), screenshots after the window frame is stable, and counts cyan overlay pixels in the ON frame (exit 2 if the overlay did not render; the guard is skipped with a warning when PIL is missing). This is separate evidence from Diagnostics captures; one case at the affected spot, not one per interval.

## Online sources when placement is undetermined

OSM Overpass for track/station geometry; GSI tiles georeferenced with `app/scripts/railway/lib/gsi_tile_georeference.py`; the `chatgpt-web` skill for a second opinion on ambiguous imagery. Record each source in the evidence notes; none of them accepts a placement by itself.
