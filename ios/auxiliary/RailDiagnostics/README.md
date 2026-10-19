# Rail Diagnostics

One Mac Catalyst application hosts the existing alignment inspector, production physical route workbench and historical through-service workbench. Models survive workspace changes. One contextual Diagnostics menu shares the original workspace action views and keyboard shortcuts. Opening an already-loaded through workspace reuses its dated snapshot; the historical range plan remains explicit. Alignment, route and through-history implementations are internal workspaces; saved documents and captured evidence remain available. The standalone app targets have been retired. Main is used for a final production composition check after inspector review identifies the necessary case.

Open `ios/JTM.xcworkspace`, scheme **RailDiagnostics**, destination **My Mac (Mac Catalyst)**. The distinct bundle ID is `com.JRM.RailDiagnostics`. Build serially with other chats:

```sh
xcodebuild -project ios/auxiliary/RailDiagnostics/RailDiagnostics.xcodeproj \
  -scheme RailDiagnostics -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  -derivedDataPath /private/tmp/jtm-rail-diagnostics -jobs 2 CODE_SIGN_IDENTITY=- build
```

`project.yml` defines the source list and generates this target's own `Info.plist`, including alternate JSON viewer registration; regenerate with `xcodegen generate --spec ios/auxiliary/RailDiagnostics/project.yml` after changing membership or plist properties. The target has its own app entry point and reuses the internal workspace source files. Standalone Through and Inspector entry points are retired; the production app entry point is excluded by the diagnostic compilation condition. The production entry file and topology are unchanged. All typography is clamped to xSmall…xLarge; iPhone is portrait.

## Agent requests

Prepare a UTF-8 JSON request and send the file to the app using the `open -a APP REQUEST` command below, or the existing `bash ios/verify.sh diagnostic --request /absolute/request.json` module. The same file-open path works for a new or already-running app and directly executes the requested action. Native evidence and results stay local for the agent to read. Only one invocation may own a session/evidence directory at a time; coordinate with the audit status files before launching work.

```json
{
  "schemaVersion": 1,
  "requestID": "sotetsu-interval-0-review",
  "workspace": "alignment",
  "action": "prepare",
  "sessionDirectory": "/private/tmp/sotetsu-diagnostic-session",
  "lineID": "jp-相模鉄道-相鉄本線",
  "intervalIndices": [0],
  "evidencePaths": ["/absolute/path/to/retained/observations.md"]
}
```

- `alignment`: optional `inputPath` is an absolute Japan compact JSON path (country `jp`/`JP`); omission uses bundled `jp-2025.json`. A supplied package is read through the same loader and capture implementation; missing/invalid input fails visibly without bundle fallback. One exact `lineID` is required; optional zero-based `intervalIndices` and `stationIDs` intersect. Unknown IDs and empty intersections fail. Actions: `prepare`, `capture`, `retryFailures`. `viewpointIDs` optionally selects a nonempty, unique list of exact IDs from the scoped `capture-index.json`/plan (for example `line-id#3#point-2`); unknown or out-of-scope IDs fail before capture, with no wider fallback. Omission keeps all viewpoints. The New task form exposes the same comma-separated Viewpoint IDs field. Progress, retries and exported capture-index/result counts retain this selection; result/index `selectedViewpointIDs` is null for all viewpoints. `captureLimit` applies after viewpoint selection and bounds one invocation to 1…1000 views; omitted means all pending views in the explicit scope. An optional `alignmentEvidenceDirectory` reuses an existing dependency-matching receipt directory. Omitted uses the session's `alignment/`. Retained failed views require `retryFailures`; it selects only originally failed views in the scope and retains their previous files under `retry-history/`. One snapshot runs at a time.
- `route`: `inputPath` points to a scoped canonical journey JSON. Actions: `prepare` or `solve`. Existing production solve/consistency checks and partial-result handling are used. Input file stays unchanged; `route-report.json` retains detailed segment/provenance evidence. Scope is exactly the input's journey IDs.
- `through`: exact `patternID` plus Gregorian `reviewDay` (`YYYY-MM-DD`); `inputPath` is rejected. Actions: `prepare` or `inspect`. Exports that pattern/date and applicable record/global limitations. Full historical boundary plan remains an explicit action in the workspace, not a launch side effect for scoped requests. Through-service display is independent of physical connectivity.

Send one request to the single app, whether it is already running or needs launching:

```sh
open -a /private/tmp/jtm-rail-diagnostics/Build/Products/Debug-maccatalyst/RailDiagnostics.app /absolute/request.json
```

File opens and **Open task ⇧⌘O** use the same strict `DiagnosticRequest` decoder/validator and start the explicit action through `start`/`DiagnosticSession`. A second Run step is unnecessary. Only local `.json` files are accepted. Busy operations or an open dialog reject the incoming request without replacing the current task or cancelling work. The existing notice appears across workspaces; a system sheet may cover it until dismissed. Close the dialog or wait for the operation to finish, then open the file again. Rail Diagnostics registers as an alternate JSON viewer for explicit **Open With** use, without requesting default JSON ownership. Verify request ID, process identity and actual result counts; open success is not capture success. Native direct dispatch is verified in `Evidence/20261018-direct-dispatch`: the latest Debug app ran the Miyazu request without another Run action and completed 28/28 views, 0 failed. Saved result/run status identify PID 52148 and invocation `A0B99B1B-9B1E-4639-B349-CC356793051A`; the parent inspected the completed UI. Earlier hot-open evidence records the previous preview step.

The workspace switcher is disabled while native work is active; Pause requests cancellation and waits for the active capture lease to settle.

## Shared evidence and recovery

`request.json` is the immutable session identity. Read `run-status.json` for the latest valid invocation ID, preparing/running/final state and `active` flag; this is written separately so a resumed preparation can preserve the preceding `result.json`. A crash may leave an active last-known status; confirm the app is idle/quit before resuming. There is no background watcher. A different decoded request requires a new session directory. `result.json` atomically records `preparing/running/prepared/partial/evidenceReady/paused/failed`, exact item IDs, relevant dependencies, counts and evidence paths. `dependenciesVerified` distinguishes a completed dependency comparison from an initial preparation failure, so fixing missing evidence can resume. A previously retained result survives changed-input rejection, with the error in `last-error.json`. Prior result/report files are archived under `attempts/` before compatible resumption. Relaunch the same request to resume pending captures; retained receipt sizes/digests and full-line/reference dependencies are validated. Incompatible selected capture evidence is rejected so original files can be preserved in the old directory.

`result.json` and `alignment-geometry.json` expose the actual alignment `packageInputPath` and `packageInputSource` (`bundle` or `request`). `alignment-geometry.json` also exposes selected raw/display intervals and complete-line DisplayParts for breakpoint and approach queries. `capture-index.json` lists only selected views in numeric interval/viewpoint order, their exact directories, statuses and dependency identities; it also lists unavailable interval IDs. Agents can locate `view.json`, native `basemap.png`, `display.png`, `smooth.png` and receipts directly. Long intervals keep all viewpoints. Existing overlapping viewpoints stay distinct camera records.

`candidate-tasks.json` supplies stable IDs for station offsets, line offsets, disconnected parts, station approaches/intended connections/false joins adjacent interval seams, and `sharpTurn` candidates for display deflections of at least 20°. Each sharp-turn candidate carries its zero-based own display vertex index, exact coordinate, angle and incoming/outgoing lengths in `corner`; the same candidate note appears in the human task list. Only the explicitly selected intervals are examined. A turn is a review lead, not an automatic repair decision. A seam's endpoint separation is a geometric candidate, never physical connection proof. Zero separation does not establish rendered continuity. Blue passenger platforms define own-line station extent; purple transfer passages and yards are excluded. Unexamined tasks remain pending.

Use the task dashboard to save observations in `review-notes.json`, separate from generated candidate tasks. It records candidate ID, dependencies, conclusion, note and SHA-256 identities of the supplied evidence files. Agents can also supply the same `DiagnosticReviewLedger` format. Reopening validates evidence identities and dependencies; stale notes stay on disk and are not counted as current. Earlier note files are retained in `review-note-history/` before a save. Keep original screenshots. `result.json` leaves its acceptance verdict and Main final check pending: capture/solve completion cannot accept station alignment, track identity, physical connectivity or production multi-line drawing. Do not recapture three copies of the same scope or run a Main case for every interval by default.

## Validation

See [the final remake evidence](Evidence/20261017-remake/README.md), `DESIGN.md` and the owning audit status for actual checks and remaining limitations. Native UI, pixels and routing claims require their corresponding observed evidence; compilation and focused scope tests alone do not establish them.

## Human tasks and keyboard control (remake)

The task dashboard now creates the same immutable request used by agents. **New task ⌃⌘N** offers alignment capture, physical route solve and through-history inspection. For alignment, optionally enter an absolute candidate compact JSON path or choose its JSON file, then search/select the exact owning railway from that package, choose complete-line coverage or an interval/station intersection, set zoom/viewport/appearance and image modes, then **Start task ⌘↩**. The app plans and captures all pending views in that scope automatically; no per-frame controls are required. A capture limit is optional and leaves an explicit partial result.

Picker-selected package/journey bytes are retained under app-owned input storage with their original filename while security scope is active. Workspace/action switching and Start are disabled during the copy; a copy failure blocks submission until an explicit edit or new choice. The task card shows the package path or bundled source. Capture from the alignment workspace preserves the active candidate input path. Candidate changes affecting full-own-line dependencies cannot reuse incompatible evidence in the old session. See [the bounded input-interface evidence](Evidence/20261017-remake/candidate-package-input-20261018/README.md); prepare results do not establish geometry repair.

**Open task ⇧⌘O** starts the action in a validated request JSON. **Run / resume ⌘↩** resumes the current task or runs a selected recent task; recent tasks retain their original output directories. **Pause Esc** cancels supported capture/route/extraction work and waits for the active capture lease to settle. For an operation without a cancellation interface, the control says it is finishing and does not advertise an active Escape action. **⌃⌘1…4** switch Tasks, Alignment, Physical routes and Through history when idle. Existing workspace shortcuts remain labelled beside controls and in their persistent workspace reference.

The captured-view gallery uses the exact zero-based interval and view numbers from `capture-index.json`. **Previous view ⌃⌘J** and **Next view ⌃⌘K**, their Diagnostics menu commands and the viewpoint picker share one selection. Navigation stops at the first/last capture and is disabled during work or a root modal. Actual button, keyboard, boundary and modal evidence is retained in `../../../docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/oito-west-complete/gallery-navigation/README.md`.

### Requested snapshot settings

```json
"captureSettings": {
  "zoom": 18,
  "width": 800,
  "height": 600,
  "appearance": "dark",
  "basemapStyle": "imagery",
  "outputModes": ["basemap", "smooth"]
}
```

`zoom` uses 256-point tiles and accepts 10…20, including fractional zoom. Viewport dimensions are logical points at 1×, each 256…4096 and at most 8,388,608 pixels. Appearance is `light` or `dark`; basemapStyle is `standard` (default) or `imagery` using the same native snapshotter, with separate receipt contracts; modes are a nonempty unique subset of `basemap`, `display`, `smooth`. Omitted settings use z17, 1024×768, light and all three modes. Unsupported root/settings keys, invalid values and explicit null settings values fail visibly. Requested settings bind the request, camera plan, render contract, receipts and evidence index. Changed settings require a new session. Old fixed-z17 evidence is retained under its original contract; it is never silently treated as a new-scale capture.

Camera spacing becomes smaller for higher zoom, smaller viewports or higher latitude, keeping overlap and both complete interval endpoints. Targets follow the owning line's effective display path; other railways do not choose its station approach direction. Each view records the requested camera and returned native snapshot projection witnesses, including image dimensions and x/y scale, to distinguish a requested camera from observed output. Image dimensions are checked before receipts are admitted.

Compatible narrower reuse keeps the original broader plan and folder identities, with separate scoped checkpoint/report names. Existing valid screenshots are reused. Missing, failed or incompatible evidence remains explicit, and geographic/physical conclusions stay pending.

The sole local helper is `bash ios/verify.sh diagnostic --request /absolute/request.json`; build with `bash ios/verify.sh build --target diagnostics`. The old standalone launch helpers and app targets are retired. Alignment/Route/Through source directories are internal implementations and their packages remain available for focused tests. Main and saved audit evidence are preserved.

The six interface/data-flow simplifications are implemented and validated in the final remake evidence above. Old route/inspector launch flags are removed. Workspace capture and solve actions create the same immutable task as the form and agent; picker inputs are retained while their security scope is active. Progress status is separate from receipt-driven evidence exports. Three known duplicate installed inspector bundles were recoverably retired; exact paths are in the evidence manifest.

Technical task inputs and reviewer evidence paths disable automatic spelling correction and capitalization so literal paths and IDs survive human entry. The actual lowercase-path save and candidate-package observations are retained with the input-interface evidence.

Exact-viewpoint native request, labelled composer, keyboard capture and human button resume proof: `Evidence/20261018-exact-viewpoints/README.md` (2 exact views out of a13-view plan; unselected views not captured).

The Catalyst app declares `LSMultipleInstancesProhibited` to keep Launch Services opens in one process ([Apple launch-services contract](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html)). `run-status.json` and `result.json` export `processID`, `executablePath` and `invocationID` to identify the actual invocation; process command-line arguments may describe an older request after hot-open. Native observation is saved in `Evidence/20261018-direct-dispatch`: one authorized `open -n` returned 0 and subsequent `pgrep` showed only the existing Debug PID 52148 for the same executable, with no second instance. This was single-process retention, not a rejected-launch error. An earlier sandboxed open error -10827 was a restricted attempt and does not establish the native single-instance outcome. Existing active status from an interrupted process is retained evidence, not proof that it is still executing.
