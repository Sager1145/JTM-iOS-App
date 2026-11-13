---
name: app-control
description: Drive the DEBUG RailMap app (com.JRM.RailMap) on the iOS simulator, on this Mac (Mac Catalyst) or on the connected iPhone without computer use, and use its floating developer ball (performance charts, signposts, triggers, state, tools, logs, diagnostics export). Read app state, load samples, add/edit/save/delete trips through the real editor, open Stats, hide filters, take screenshots and time each step. Use for bug and performance passes on the main app, especially on the real device.
---

# App control (test-only channel)

`python3 -I ios/tools/app-control.py --target sim|mac|device [--device UDID] ACTION [key=value ...]`

The DEBUG app has a control channel (`ios/RailMap/Diagnostics/AppControl/`, protocol in `RailPresentation/Workspace/AppControlProtocol.swift`). Every command runs through the app's own code: the workspace's `pick`/`presentJourneyEditor`, and the editor's station assignment, planner, section choice and `commit`. It is compiled out of Release (`#if DEBUG`). The `railmap-test` URL scheme is only in the Debug Info.plist (`ios/tools/app-control/RailMap-Debug-Info.plist`, set as `INFOPLIST_FILE` for Debug only). There is no socket.

Transport (default `--transport poll`): the CLI writes `inbox/<id>.json` into the app's container, under `Library/Application Support/RailMapAppControl/`. The app's poller (every 0.4 s, running only when the app was started with `launch`, i.e. `RAILMAP_APP_CONTROL=1`) runs the request and writes `results/result-<id>.json`: first `running`, then final. The CLI waits for the result matching its request ID and prints one JSON line. Exit codes: **0** ok, **2** rejected, **3** timeout, **4** failed, **1** tool/usage error.

| Target | Write request / read result |
|---|---|
| `sim` (default; iPhone 17 `0DBE2488-…`) | files in `simctl get_app_container … data` |
| `mac` | `~/Library/Application Support/RailMapAppControl` (the app is unsandboxed; the CLI also checks the sandbox container) |
| `device` (default iPhone 16 Pro `00008140-000575142288801C`) | `devicectl device copy to/from --domain-type appDataContainer --domain-identifier com.JRM.RailMap`, about 1 s per poll. Requests are copied as `inbox/<id>.req`, and the app retries a file that does not decode yet (the copy is not atomic) |

`--transport url|file` also opens `railmap-test://run?json=…` / `?request=<id>` (via `simctl openurl`, `open -g -a`, `devicectl device process openURL`). **iOS 26+ asks "Open in "RailMap"?" for every such URL** (seen on the simulator 2026-11-06), which needs a tap, so the URL is only a fallback for an app not started with `launch`.

## Safety rules

- **Isolated storage only.** `launch` always passes `RAILMAP_UI_TEST_STORAGE_ID=<UUID>` (new by default, or `--storage UUID`). On the real store the app runs only commands that persist nothing: `state`, `screenshot`, `wait`, `useStorage`, `devtools`, `exportDiagnostics`, `memoryWarning`, `clearRouteCaches`, `setLayer`, `focusTrip`, `openStats`, `camera` and `perf`. Everything else, including `selectTrip` (it writes the last-viewed trip) and every editor command, is `rejected`. Never write to the real `com.JRM.RailMap` store. Do not launch the app any other way before sending write commands.
- **One native job at a time, machine-wide.** That covers builds, simulator runs and device runs across all chats. Coordinate before building or launching.
- **A single simulator:** iPhone 17 `0DBE2488-0BEB-4932-9B55-091B3CC793B6`. Don't boot or create others.
- Follow `ios/VERIFICATION.md`: focused, incremental, reuse evidence. One request ID runs once (re-sending a finished ID is ignored).

## Build, install, launch

```sh
python3 -I ios/tools/app-control.py --target sim build            # incremental Debug build, -jobs 2 (--dry-run prints it)
python3 -I ios/tools/app-control.py --target sim install
python3 -I ios/tools/app-control.py --target sim launch           # new isolated UUID; waits for ready.json
python3 -I ios/tools/app-control.py --target sim launch --storage 1B4E28BA-2FA1-11D2-883F-0016D3CCA427
python3 -I ios/tools/app-control.py --target mac build && … --target mac install && … --target mac launch
python3 -I ios/tools/app-control.py --target device build         # automatic signing, -allowProvisioningUpdates
python3 -I ios/tools/app-control.py --target device install && … --target device launch
python3 -I ios/tools/app-control.py --target device ready         # reads ready.json (pid, storageID, root)
```

`launch` also sets `RAILMAP_SIGNPOST_RECORDER=1` (signpost durations in `state`) and `RAILMAP_DEVTOOLS=1` (ball visible). Use `--no-devtools` to hide the ball. The CLI waits per command (`reloadAll` 660 s, `addTrip`/`editTrip` 200 s, `loadSamples` 240 s, otherwise 90 s), at least as long as the app's own default. `--timeout` overrides this.

Products go to `~/Library/Caches/jtm-railmap-app-control/DerivedData/Build/Products/<Debug|Release>-{iphonesimulator,maccatalyst,iphoneos}/RailMap.app`. Use `--app PATH` to drive a build made elsewhere. `launch --env KEY=VALUE` adds other `RAILMAP_UI_TEST_*` hooks. The last storage and pid per target are kept in `~/Library/Caches/jtm-railmap-app-control/<target>-<device>.json`.

## Commands

Values parse as JSON when they can, so `save=true`, `timeoutMs=5000`, `via='["名古屋","京都"]'` work. A comma list also works (`via=名古屋,京都`). `--json '{…}'` adds args as an object. `--data-only` prints only `data` on success. Every result carries `elapsedMs` (in-app), `roundTripMs` (CLI) and, where relevant, `data.timings` / `data.ms`.

| Command | Args | Returns |
|---|---|---|
| `state` | `trips=false` to omit the trip list | storageID, inventory (registered, route phase, rides, drawable, ridesInTabScope, routeCacheHits, routeSolveAttemptsThisLaunch, storedFailures, reloadProgress), map (ready, `railMapRenderStatus` text, render stats, totalOverlays and rideOverlays = every mounted overlay and the trip ones), selectedTrip, sheet, stage, tab, hidden filter, editor (+draft), memory (footprint/resident/peak MB), trips[≤500]. `signposts` is null because RailSignpost intervals only reach Instruments |
| `loadSamples` | `samples=train-store,train-store-tw` (default `train-store`; names are `RideLibrary.Sample.all` resources) | merged count and ms per sample |
| `useStorage` | `id=UUID` | ok if the app runs on that store, else `rejected` with `relaunchRequired` (then `launch --storage UUID`) |
| `reloadAll` | `wait=true`, `timeoutMs`, `force=false` | ms, rides. Default is the user-facing repair (cached routes read back, only missing ones solved, map stays drawn); `force=true` is the old full rebuild (wipes the route cache and every memo, solves every trip) |
| `selectTrip` / `focusTrip` | `id=` | the same `pick` / auto-focus request a tap makes |
| `openEditor` | `id=` | editor snapshot, mount/ready ms |
| `addTrip` | `from= to=` (station source code or exact name), `region=jp`, `date=YYYY-MM-DD`, `via=`, `sectionChoices=[id0,…]` or `{"1":"id"}`, `save=true`, `confirmRemoval=true`, `timeoutMs` | editor snapshot: sections (outcome, candidates with lines/operators/km/junctions/proven/historical, chosen, historicalNotice/probe), pendingSections, selectedCorridorID, passStations, conflicts, notices, saveIssues, canSave; timings (mountMs, readyMs, planMs, applyMs); `save` result if requested |
| `editTrip` | `id=` plus the same fields as `addTrip` (flat or under `changes`) | same |
| `saveEditor` | `confirmRemoval=true`, `timeoutMs` | `{saved, recordID, ms}`. Any non-save is `failed` (exit 4) with the reason: cannot save yet, validation, removal needs `confirmRemoval`, refused by the store, or persistence |
| `cancelEditor` | | |
| `deleteTrip` | `id=` | the store's delete plus its save |
| `openStats` | | switches to the Stats tab |
| `setHideFilter` | `mode=set\|add\|remove\|showAll`, `regions=tw,hk`, `years=2023`, `months=2024-05` | hidden sets |
| `screenshot` | `name=` (default: request id) | PNG at `screenshots/<name>.png` (key window, `drawHierarchy`) |
| `wait` | `condition=mapReady\|routesLoaded\|editorReady\|editorPlanned\|editorClosed\|idle\|trips>=N`, `timeoutMs` | waitedMs |
| `devtools` | `action=show\|hide\|expand\|collapse\|recorderOn\|recorderOff\|resetSignposts\|export` | ball visible/expanded, recorder on |
| `exportDiagnostics` | | `exports/diagnostics-<time>.json` (state, perf samples, signposts, last 1000 log lines, device) |
| `clearRouteCaches` | | removed bytes (`Caches/RailMap/Routes` plus the solver/edge-index memos) |
| `memoryWarning` | | memory before/after the app's memory-warning handler |
| `setLayer` | `name=routes\|stops\|terminals\|pass\|hsr\|jr\|metro\|priv\|network`, `on=true\|false` | all layer flags |
| `camera` | `action=set lat= lon= [zoom=] [animated=false]` (zoom keeps the current one when omitted); `action=pan dLat= dLon= [steps=30] [stepMs=33]` (the total move in degrees, in equal steps); `action=zoom [from=] to= [steps=30] [stepMs=33]`; `action=fit [target=network\|selection]`. Zoom is the map's own scale (`camera:` in `railMapRenderStatus`), 0 to 22, steps 1 to 600 | One measured run, waiting until the camera and rebuild count are quiet for 400 ms (max 8 s): `frames`, `maxGapMs` (largest display-link gap), `hitches` (gap over 1.5 frames), `rebuilds` and `gestureBuilds` (deltas), `buildMs` (`samples`, `p50`, `p95`, `max`, sampled at about 20 Hz whenever the rebuild count moved, so a build between two samples is missed), `overlays`, `vertices` (last `RenderStats`), `geometryWait` (`count` delta, `maxMs` since launch), `footprintMB` (`before`, `after`, `delta`), camera `from`/`to`, `durationMs`, `settleMs`. `set`/`pan`/`zoom` go through `RailMapController.setCameraForUITest` (non-animated except `set animated=true`); `fit` calls `fitToNetwork`/`fitToSelection`. Persists nothing, so it runs on the real store |
| `perf` | `action=start\|stop\|read` | The developer panel's `DevPerfSampler` (1 Hz FPS, hitches, longest frame, footprint, CPU; last 120 s) without opening the panel: `running`, `count`, `summary` and `samples`. `start` clears and restarts; `stop` keeps the samples for `read`. Separate from the panel's own sampler |

```sh
A="python3 -I ios/tools/app-control.py --target sim"
$A state trips=false
$A loadSamples samples=tokyo-limited-express-loop
$A wait condition=routesLoaded timeoutMs=120000
$A addTrip from=東京 to=新大阪 date=2025-01-03
$A addTrip from=東京 to=新大阪 via=名古屋 sectionChoices='["<corridor id>"]' save=true
$A screenshot name=after-add && $A pull-screenshot after-add --out /private/tmp/after-add.png
```

When station names are ambiguous, the first catalog match is used. Pass the source code to be exact. `addTrip` returns once the editor's plan has settled (`planned && !searching`). If a section has several candidates, choose them with `sectionChoices` (or `editTrip id=<draft id> sectionChoices=…`) and then `saveEditor`.

## Sweep (same pass on every target)

`app-control.py --target sim|mac|device sweep [sample]` runs one timed pass over every command family on an app started with `launch`. The steps: wait mapReady, state, loadSamples, wait routesLoaded, select/focus/screenshot/openEditor/cancel on the first trip, addTrip 品川→横浜 (plan only), openStats, hide filter on/off, a layer off/on, reloadAll, clearRouteCaches, memoryWarning, a closing screenshot, state, then exportDiagnostics, pulled to the Mac. It prints `{ok, failedSteps, steps[{status, appMs, roundTripMs, timings…}], export}`, with exit 4 if a required step failed. Compare targets on `appMs`. On a device `roundTripMs` includes about 1 s per `devicectl copy`.

## Developer ball (DEBUG only)

The ball is a draggable button that snaps to the nearer side edge. It lives in its own window above all app UI and sheets, and tapping it expands the panel. Its side, height, expanded state and page persist per device in UserDefaults. Its ring is **red on the real ride store** and green on an isolated one, and the panel shows a matching banner. The ball is hidden by `RAILMAP_DEVTOOLS=0` and, by default, for any UI-test launch (any `RAILMAP_UI_TEST_*` key) unless `RAILMAP_DEVTOOLS=1`. `screenshot` captures only the app's window, never the ball. Collapsed, it costs nothing beyond the ball: sampling and the signpost recorder run only while the Perf page (recorder: Perf or State) is open.

- **Perf:** Swift Charts of FPS, footprint MB, CPU % and hitches per second (CADisplayLink, `task_info`, `task_threads`, 1 Hz, last 120 s). Below them, signposts by name (count, last, mean, max) and the most recent intervals. These come from `SignpostRecorder` (RailCore), which the same `RailSignpost` begin/end pairs and `graph.build` feed, so there is no second timing system.
- **Triggers:** buttons that call `AppControlHost.submit`, so they go through the same queue, dispatcher, storage guard and result files as the URL channel: load samples (on the real store it offers to switch to a fresh UUID store, quit, and load on reopen), rebuild all routes (`reloadAll force=true`), select or focus a random trip, open the editor, add a demo trip (東京 to 新大阪, today, saved), delete the last trip added there, open Stats, toggle the hide filter (the current year), and screenshot.
- **State:** inventory, map render stats and layers, rebuild and tap-index counts (from the recorder), storage ID and source, memory, and cache sizes on disk (on demand).
- **Tools:** switch to a new isolated store or back to the real one. This takes effect on the next launch (`DevStorage`). The launch environment always wins, and the override is ignored for UI-test launches. Also: clear route caches, simulate a memory warning, map layer toggles, export a diagnostics bundle, and hide the ball.
- **Logs:** this process's OSLog entries for subsystems `com.jtm.railmap` and `com.JRM.RailMap` (the display batch log), with a filter. For a zoom sweep, start the perf window at the first step, not before the launch settles.

```sh
python3 -I ios/tools/app-control.py --target device devtools expand
python3 -I ios/tools/app-control.py --target device devtools export --out /private/tmp/diag.json   # writes in the app, then pulls
python3 -I ios/tools/app-control.py --target sim devtools hide
```

## Release check

All of this is `#if DEBUG`. The URL scheme is only in the Debug Info.plist. `RailSignpost` keeps the bare `OSSignpostIntervalState` in Release. The proof is `ios/tools/app-control/check-release-clean.sh RailMap.app`, which runs `strings` and demangled `nm` over the main binary and every embedded Mach-O, and checks the Info.plist, for 16 DEBUG-only markers (type names and literals over 15 bytes; shorter Swift literals are stored inline, where `strings` cannot see them). Its `--debug-sanity` mode fails unless every marker is detected in a Debug build. The Release build is a heavy job, so coordinate it:

```sh
python3 -I ios/tools/app-control.py --target sim --configuration Release build
python3 -I ios/tools/app-control.py --target sim check-release
bash ios/tools/app-control/check-release-clean.sh --debug-sanity ~/Library/Caches/jtm-railmap-app-control/DerivedData/Build/Products/Debug-iphonesimulator/RailMap.app
```

## Troubleshooting

- `timeout` with `pickedUp:false`: the app isn't running a DEBUG build with the scheme. Re-`install` and `launch`. On Mac, `install` registers the build with LaunchServices.
- `rejected` with `refused: … shared ride store`: the app was opened without `launch`. Relaunch with `launch`.
- `unavailable: workspace not mounted`: send `wait condition=mapReady` first.
- Smoke test: `RailMapUITests/AppControlSmokeUITests` (state, loadSamples and wait via `XCUIApplication.open`). Unit tests: `swift test --package-path ios/RailKit --filter 'AppControlProtocolTests|SignpostRecorderTests'`.
