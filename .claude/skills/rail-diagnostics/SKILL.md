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
`["Diagnostics","New diagnostic task"]`, `["Diagnostics","Open task request…"]`, `["Diagnostics","Run / resume task"]`, `["Diagnostics","Pause current operation"]`, `["Diagnostics","Previous captured view"]`, `["Diagnostics","Next captured view"]`, `["Diagnostics","Tasks & evidence"]`, `["Diagnostics","Alignment"]`, `["Diagnostics","Physical routes"]`, `["Diagnostics","Through history"]`, `["Diagnostics","Area repair"]` (workspace switch; titles confirmed live 2026-10-20). Workspace-specific items (viewpoint/station navigation, capture, export) are added to the same Diagnostics menu only while that inspection workspace has focus; otherwise the menu shows "Select an inspection workspace". List the menu first with `app_menu {list:"Diagnostics"}` and press only titles it returns.

| Shortcut | Command |
|---|---|
| ⌃⌘N | New diagnostic task |
| ⇧⌘O | Open task request… |
| ⌘↩ | Run / resume task |
| Esc | Pause current operation |
| ⌃⌘1…5 | Tasks / Alignment / Physical routes / Through history / Area repair |
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
| (menu only) | Area repair workspace: Resolve area / Preview patch / Undo last fix / Export patch for guarded write… |

Pause waits for the active capture lease; the workspace switcher is disabled while work is active.

## Small-area capture and repair

Capture one small area (stationPair, lineSection, rect or centre+radius; margin default 500 m), list detected problems, draft and preview a patch, write it behind `--confirm`. Full docs: `ios/auxiliary/RailDiagnostics/Modules/AreaRepair/README.md`.

```sh
# app capture: views + area-evidence.json (jtm-area-evidence-v1) in the session dir; exit codes as capture
python3 -I ios/tools/verification/diagnostic-run.py area capture --stations 'LINE:A-B' [--margin M] [--zoom 17] --name my-area
#   selectors: --stations LINE:A-B | --line L --intervals a-b | --rect minLon,minLat,maxLon,maxLat | --centre lon,lat --radius M
# headless (no app): same selectors; every verb prints one JSON; --help per verb
bash ios/verify.sh area capture-data <selector> --out DIR
bash ios/verify.sh area problems <selector> --out DIR --propose DIR/patch.json
bash ios/verify.sh area apply --patch P --scratch DIR            # scratch overlay, repo untouched
bash ios/verify.sh area preview --patch P --out DIR              # baseline vs patched rides/problems
bash ios/verify.sh area write --patch P                          # dry-run plan, exit 2, writes nothing
bash ios/verify.sh area write --patch P --confirm                # real write
bash ios/verify.sh area undo --receipt R --confirm
```

Flow: capture, `problems --propose`, fill every op's `reason` and at least one `source` (the draft is blanked and fails validation until you do), `apply` to scratch, `preview`, `write` dry-run, show the user, then `--confirm` only on their explicit go-ahead. Selector/data options: `--margin`, `--repo`, `--overlay`, `--journeys FILE` (repeatable), `--no-default-rides`, `--thresholds JSON|FILE`, `--zoom`. Detectors: missingJunction, lostHistoryStamp, uncertifiedPairedTrack, stationDotOffLine, overRoundedCorner, pairedDirectionSide (thresholds 300/25/15/500 m configurable).

Exit codes (jtm-area): 0 ok, 2 invalid input or refused (also dry-run write), 4 error/warning problems found or guard failure, 1 internal. Patch format `jtm-area-patch-v1`; ops carry reason + source. Patches live in `<evidence root>/area-repairs/<id>/` (`RAILWAY_EVIDENCE_ROOT` or the mounted archive, else pass `--patch-dir`); `write --confirm` saves backups and an inverse receipt in `receipts/<timestamp>/`, regenerates `physical-rail-topology.json` when junctions change, runs the per-class guards (`bash ios/verify.sh swift --filter ...`) and auto-reverts on failure. `guard --patch P --dry-run` lists the guards.

Example (立石–西屋敷):

```sh
python3 -I ios/tools/verification/diagnostic-run.py area capture --stations 'jp-九州旅客鉄道-日豊線:西屋敷-立石' --name tateishi-nishiyashiki
bash ios/verify.sh area problems --stations 'jp-九州旅客鉄道-日豊線:西屋敷-立石' --out "$D" --propose "$D/patch.json"
```

Rules:
- Never pass `--confirm` (write or undo) without the user's explicit go-ahead in chat.
- Writable by default: `app/data/physical-rail-junctions.json` only. `rail-history.json` ops are report-only unless `--allow-generated --confirm`, then mirror the change into `app/scripts/railway/jp-rail-history-events.json` (code's reported mirror). `jp-2025.json` ops are always refused; report them as mirrors into `app/scripts/railway/jp-directional-alignment-overrides.json` / the builder (website pipeline owns it) and stop.
- The app cannot run guards: its Export writes `patch.json` and shows the `write --patch ... --confirm` command; run it from the shell. The main app never reads overlays.
- Reuse guards; no broad tests. Heavy jobs (build, swift, write) run one at a time machine-wide via the lock.
- The app reads the repo root from `--repo-root PATH`, `JTM_REPO_ROOT`, else the source path; macOS may prompt for Documents access.

## Main final check

`bash ios/tools/verification/main-cold-pair.sh OUTDIR STATIONID LAT LON SPAN STORAGEID [RailMap.app]` (bundle `com.JRM.RailMap`). Cold-launches Main with the network layer ON, then OFF (unknown layer key), screenshots after the window frame is stable, and counts cyan overlay pixels in the ON frame (exit 2 if the overlay did not render; the guard is skipped with a warning when PIL is missing). This is separate evidence from Diagnostics captures; one case at the affected spot, not one per interval.

## Online sources when placement is undetermined

OSM Overpass for track/station geometry; GSI tiles georeferenced with `app/scripts/railway/lib/gsi_tile_georeference.py`; the `chatgpt-web` skill for a second opinion on ambiguous imagery. Record each source in the evidence notes; none of them accepts a placement by itself.
