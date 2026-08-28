# JTM iOS App Build and Release Runbook

| Field | Value |
| --- | --- |
| Purpose | Reproduce, validate, archive, and release the iOS app |
| Primary owner | iOS release engineer |
| Technical authority | `ios/verify.sh`, shared Xcode schemes, and CI |
| Last verified | 2026-08-28 |
| Review cadence | Before every release and after toolchain or signing changes |

## Scope

Use this runbook for local release candidates and App Store submissions. It covers the JavaScript parity fixtures, `RailCore`, `RailPresentation`, the `RailMap` app, UI tests, signing, smoke tests, and recovery. It does not modify production user data or external railway packages.

## Preconditions

- macOS with Xcode 27 or a compatible toolchain that supports Swift 6.
- An iOS 17-or-later simulator and, for release, a physical iPhone or iPad.
- Node.js 26.4.0, matching `.node-version`.
- Access to Apple Developer team `845N4SKYV2` for signed archives.
- A clean, reviewed release commit. Preserve unrelated local changes before starting.
- Enough free space under `/tmp`; build products must stay outside iCloud-backed paths.

The current release identity is:

| Setting | Value |
| --- | --- |
| Scheme | `RailMap` |
| Bundle identifier | `com.japantrainmap.RailMap` |
| Marketing version | `0.1` |
| Build number | `1` |
| Deployment target | iOS 17.0 |

Confirm these values in `ios/RailMap.xcodeproj/project.pbxproj` before a release. Increment the version and build number through the normal project change and review process.

## 1. Record the candidate

From the repository root:

```bash
git status --short
git branch --show-current
git rev-parse HEAD
```

Expected result: the exact commit and any intentional local changes are recorded in the release ticket. Do not archive an unexplained dirty worktree.

## 2. Confirm the toolchain

```bash
node --version
swift --version
xcodebuild -version
```

Expected result: Node reports `v26.4.0`; Xcode and Swift match the release environment or CI. If `/Applications/Xcode-beta.app` exists, `ios/verify.sh` selects it unless `DEVELOPER_DIR` is already set.

To select a specific Xcode for the current shell:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## 3. Run the release gate

```bash
cd ios
SCRATCH=/tmp/jtm-release-verify ./verify.sh
```

Expected result: every section ends successfully. The gate checks:

- JavaScript fixtures still match their generators.
- `RailCore` and `RailPresentation` build and all package tests pass.
- Portable targets have no disallowed platform imports or owned warnings.
- JavaScript and Swift rendering contracts remain synchronized.
- Map datum, annotation, persistence, accessibility, and other app invariants hold.
- The `RailMap` simulator app builds successfully.

Do not bypass a failed invariant. Diagnose the first `FAIL:` line, correct the code or an intentionally changed fixture, and run the full gate again.

### Focused developer loops

These modes shorten investigation but do not replace the full release gate:

| Command | Use |
| --- | --- |
| `SCRATCH=/tmp/jtm-core ./verify.sh --core` | Swift package build/tests and static contract checks; skips the app build |
| `SCRATCH=/tmp/jtm-swift ./verify.sh --swift` | Package tests plus app build |
| `./verify.sh --js` | JavaScript fixture freshness only |

Give parallel workers different `SCRATCH` paths.

## 4. Run UI tests

List available destinations if the preferred simulator is not installed:

```bash
xcrun simctl list devices available
```

Then run the shared scheme, replacing the device name when needed:

```bash
xcodebuild test \
  -project ios/RailMap.xcodeproj \
  -scheme RailMap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/jtm-ui-tests
```

Expected result: `RailMapUITests` completes with `** TEST SUCCEEDED **`. Capture the `.xcresult` path when filing a failure.

## 5. Review the release diff

```bash
git diff --check
git diff --stat
git log -1 --oneline
```

Confirm that:

- A public API change updates `docs/API_REFERENCE.md`.
- A visible workflow change updates `docs/USER_GUIDE.md` and `ios/FEATURES.md`.
- A build, incident, or release change updates this runbook.
- A durable architecture decision has an ADR under `docs/decisions/`.
- Generated fixtures changed only when their generator behavior changed intentionally.

## 6. Archive

First confirm signing in Xcode for the `RailMap` target. Then create a release archive:

```bash
xcodebuild archive \
  -project ios/RailMap.xcodeproj \
  -scheme RailMap \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/JTM-RailMap.xcarchive \
  -allowProvisioningUpdates
```

Expected result: `** ARCHIVE SUCCEEDED **` and `/tmp/JTM-RailMap.xcarchive` exists. Open the archive in Xcode Organizer, validate it, and resolve every signing or validation error before distribution.

## 7. Smoke-test the archive

Test a Release build on a physical device before submission. Use a disposable sample journey and cover this path:

1. Launch with airplane mode enabled and confirm locally available data still opens.
2. Create a journey with at least two stations, edit it, duplicate it, hide it, and show it again.
3. Import valid journey JSON; reject malformed JSON without losing existing journeys.
4. Import one route screenshot after the Japan network has loaded.
5. Open the map, select a journey, inspect a station, and follow an Apple Maps link.
6. Open Statistics and confirm mileage and coverage render.
7. Start playback, seek, pause, and export a short video.
8. Export a backup, delete the disposable journey, and re-import the backup.
9. Relaunch and confirm persisted journeys remain.
10. Switch language and verify the main tabs, utility menu, and empty/error states.

Expected result: no crash, data loss, unexplained straight-line route, frozen loading state, or inaccessible primary action.

## 8. Submit and observe

Use Xcode Organizer to upload the validated archive to App Store Connect. Record:

- Git commit and archive creation time.
- Marketing version and build number.
- Xcode and Swift versions.
- Full gate and UI-test results.
- Tester, device, OS version, and smoke-test result.
- App Store Connect build identifier and phased-release choice.

After TestFlight processing, repeat the critical smoke path on the processed build. Monitor crash reports, launch failures, import failures, route-loading failures, and user reports through the release observation window.

## Rollback and recovery

### Before upload

Discard the archive, fix the candidate, rerun the entire runbook, and create a new archive. Never reuse a failed build number for an uploaded replacement.

### In TestFlight

Remove the affected build from testing, notify testers, and promote the last known-good build if it remains available. Build and upload a corrected binary with a higher build number.

### During phased App Store release

Pause the phased release in App Store Connect. If impact warrants it, remove the version from sale where applicable and submit a corrected build. App Store distribution has no instant binary rollback; recovery is a new reviewed build.

### User-data safety

Do not ask users to delete the app as a first response: that can remove the local journey library. Ask affected users to export JSON if the app remains usable. Destructive in-app operations maintain one recovery backup, but it is not a substitute for an explicit export.

## Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| Codesign reports resource fork or Finder metadata | Build output is on an iCloud-backed path | Use a unique `/tmp` scratch or derived-data path and rebuild |
| Swift workers collide or lock | Shared scratch directory | Give each process a distinct `SCRATCH` path |
| Fixture freshness fails | Generator behavior and checked-in fixture differ | Run the named generator, review the semantic diff, then verify Swift parity |
| Package import boundary fails | Platform framework imported into a portable target | Move the integration to the app target and pass plain values across the boundary |
| Simulator destination is unavailable | Device name/runtime differs | Choose an installed device from `xcrun simctl list devices available` |
| Archive cannot sign | Team, certificate, entitlement, or profile mismatch | Recheck target Signing & Capabilities and Apple Developer access; do not weaken signing |
| Screenshot import finds no route | Japan network not ready or OCR input is poor | Load the Japan network, crop to the route steps, and retry with no more than eight images |
| A journey route fails | Station or route constraints cannot be resolved | Preserve and surface the failure; do not replace it with a straight line |

## Escalation

- Route or parity failure: assign to the `RailCore`/fixture maintainer with the failing command and log.
- Map rendering or datum failure: assign to the MapKit owner with region, journey JSON, and screenshot.
- Persistence or import data-loss risk: stop release immediately and involve the storage owner.
- Signing or App Store validation failure: involve the Apple Developer account holder.
- Crash in the processed/TestFlight build: pause promotion and attach the organizer crash report, commit, build number, and reproduction steps.

## Maintenance record

When this procedure changes, update the “Last verified” date and add the reason to the pull request. Run every pasted command at least once in the supported environment; commands that are merely proposed must be labeled as such rather than presented as verified operations.
