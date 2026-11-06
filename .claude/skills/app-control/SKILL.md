---
name: app-control
description: Drive the DEBUG RailMap app (com.JRM.RailMap) on the iOS simulator, on this Mac (Mac Catalyst) or on the connected iPhone without computer use. Read app state, load samples, add/edit/save/delete trips through the real editor, open Stats, hide filters, take screenshots and time each step. Use for bug and performance passes on the main app, especially on the real device.
---

# App control (test-only channel)

`python3 -I ios/tools/app-control.py --target sim|mac|device [--device UDID] ACTION [key=value ...]`

The DEBUG app has a control channel (`ios/RailMap/Diagnostics/AppControl/`, protocol in `RailPresentation/Workspace/AppControlProtocol.swift`). Every command runs through the app's own code: the workspace's `pick`/`presentJourneyEditor`, and the editor's station assignment, planner, section choice and `commit`. It is compiled out of Release (`#if DEBUG`). The `railmap-test` URL scheme is only in the Debug Info.plist (`ios/tools/app-control/RailMap-Debug-Info.plist`, set as `INFOPLIST_FILE` for Debug only). There is no socket.

Transport: the CLI opens `railmap-test://run?json=<base64url request>` (large requests go to `inbox/<id>.json` with `?request=<id>`). The app writes `results/result-<id>.json` under `Library/Application Support/RailMapAppControl/` in its container: first `running`, then final. The CLI waits for the result matching its request ID and prints one JSON line. Exit codes: **0** ok, **2** rejected, **3** timeout, **4** failed, **1** tool/usage error.

| Target | Send | Read results |
|---|---|---|
| `sim` (default; iPhone 17 `0DBE2488-…`) | `simctl openurl` | `simctl get_app_container … data` |
| `mac` | `open -g -a RailMap.app URL` | `~/Library/Application Support/RailMapAppControl` (the app is unsandboxed; the CLI also checks the sandbox container) |
| `device` (default iPhone 16 Pro `00008140-000575142288801C`) | `devicectl device process openURL` | `devicectl device copy from --domain-type appDataContainer --domain-identifier com.JRM.RailMap`, about 1 s per poll |

`--transport poll` writes only the inbox file. The app's poller picks it up (it runs when the app was started with `launch`) without opening a URL, so the app is not brought to the front.

## Safety rules

- **Isolated storage only.** `launch` always passes `RAILMAP_UI_TEST_STORAGE_ID=<UUID>` (new by default, or `--storage UUID`). The app refuses every store-writing command (`loadSamples`, `reloadAll`, `saveEditor`, `deleteTrip`, `setHideFilter`, and `addTrip`/`editTrip` with `save=true`) with status `rejected` when it runs on the shared store. Never write to the real `com.JRM.RailMap` store. Do not launch the app any other way before sending write commands.
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

Products go to `~/Library/Caches/jtm-railmap-app-control/DerivedData/Build/Products/Debug-{iphonesimulator,maccatalyst,iphoneos}/RailMap.app`. Use `--app PATH` to drive a build made elsewhere. `launch --env KEY=VALUE` adds other `RAILMAP_UI_TEST_*` hooks. The last storage and pid per target are kept in `~/Library/Caches/jtm-railmap-app-control/<target>-<device>.json`.

## Commands

Values parse as JSON when they can, so `save=true`, `timeoutMs=5000`, `via='["名古屋","京都"]'` work. A comma list also works (`via=名古屋,京都`). `--json '{…}'` adds args as an object. `--data-only` prints only `data` on success. Every result carries `elapsedMs` (in-app), `roundTripMs` (CLI) and, where relevant, `data.timings` / `data.ms`.

| Command | Args | Returns |
|---|---|---|
| `state` | `trips=false` to omit the trip list | storageID, inventory (registered, route phase, rides, drawable, reloadProgress), map (ready, `railMapRenderStatus` text, render stats), selectedTrip, sheet, stage, tab, hidden filter, editor (+draft), memory (footprint/resident/peak MB), trips[≤500]. `signposts` is null because RailSignpost intervals only reach Instruments |
| `loadSamples` | `samples=train-store,train-store-tw` (default `train-store`; names are `RideLibrary.Sample.all` resources) | merged count and ms per sample |
| `useStorage` | `id=UUID` | ok if the app runs on that store, else `rejected` with `relaunchRequired` (then `launch --storage UUID`) |
| `reloadAll` | `wait=true`, `timeoutMs` | ms, rides |
| `selectTrip` / `focusTrip` | `id=` | the same `pick` / auto-focus request a tap makes |
| `openEditor` | `id=` | editor snapshot, mount/ready ms |
| `addTrip` | `from= to=` (station source code or exact name), `region=jp`, `date=YYYY-MM-DD`, `via=`, `sectionChoices=[id0,…]` or `{"1":"id"}`, `save=true`, `confirmRemoval=true`, `timeoutMs` | editor snapshot: sections (outcome, candidates with lines/operators/km/junctions/proven/historical, chosen, historicalNotice/probe), pendingSections, selectedCorridorID, passStations, conflicts, notices, saveIssues, canSave; timings (mountMs, readyMs, planMs, applyMs); `save` result if requested |
| `editTrip` | `id=` plus the same fields as `addTrip` (flat or under `changes`) | same |
| `saveEditor` | `confirmRemoval=true`, `timeoutMs` | `{saved, recordID, ms}`, or `{saved:false, reason: validation\|removal needs confirmRemoval\|persistence\|editor cannot save yet}` |
| `cancelEditor` | | |
| `deleteTrip` | `id=` | the store's delete plus its save |
| `openStats` | | switches to the Stats tab |
| `setHideFilter` | `mode=set\|add\|remove\|showAll`, `regions=tw,hk`, `years=2023`, `months=2024-05` | hidden sets |
| `screenshot` | `name=` (default: request id) | PNG at `screenshots/<name>.png` (key window, `drawHierarchy`) |
| `wait` | `condition=mapReady\|routesLoaded\|editorReady\|editorPlanned\|editorClosed\|idle\|trips>=N`, `timeoutMs` | waitedMs |

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

## Troubleshooting

- `timeout` with `pickedUp:false`: the app isn't running a DEBUG build with the scheme. Re-`install` and `launch`. On Mac, `install` registers the build with LaunchServices.
- `rejected` with `refused: … shared ride store`: the app was opened without `launch`. Relaunch with `launch`.
- `unavailable: workspace not mounted`: send `wait condition=mapReady` first.
- Smoke test: `RailMapUITests/AppControlSmokeUITests` (state, loadSamples and wait via `XCUIApplication.open`). Unit tests: `swift test --package-path ios/RailKit --filter AppControlProtocolTests`.
