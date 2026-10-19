# Build and release runbook

Reviewed against repository configuration on 2026-10-10. Commands below are
procedure examples; they were not executed during this documentation review.

## Workspace and prerequisites

Open `ios/JTM.xcworkspace`. It contains the main `RailMap.xcodeproj` and the
RouteWorkbench, ThroughWorkbench and RailAlignmentInspector diagnostic projects
under `ios/auxiliary/`. Use the shared `RailMap` scheme for the shipping app;
diagnostic schemes serve their own investigations.

Use macOS, Xcode with Swift 6 support, and an installed simulator compatible with
the deployment target. Read `.node-version` when a JavaScript builder is needed.
Signed releases require the appropriate Apple Developer account, certificates,
profiles and entitlements. Confirm current bundle ID, version, build number,
deployment target and signing team in `ios/RailMap.xcodeproj/project.pbxproj` and
Xcode's target settings; do not infer the main app's identity from the UI-test target.

Record the candidate commit and intentional local changes. Preserve unrelated
work. Keep derived data and archives outside iCloud-backed repository paths,
using a reusable build location under `/tmp` when necessary.

## Review and focused evidence

Follow [the current verification policy](../../ios/VERIFICATION.md). Begin with the
actual diff, affected callers, data records and existing regression tests. Review
Swift/JavaScript counterparts and bundled ID references when shared behavior or
identities change. Check documentation impact in the user guide, feature ledger,
API reference and relevant ADRs.

Reuse applicable results after checking their relevant source, input, toolchain
and configuration dependencies. Execute only the existing focused test, targeted
data query or incremental build needed to answer a specific correctness question.
Coordinate one heavy job at a time across chats and reuse its build products.
Broaden only for an observed failure or concrete dependency. Record scope,
evidence, outcome and remaining uncertainty in the existing owning ledger.

Standalone verification scripts and their CI pipelines were retired. There is no
replacement umbrella gate, full device matrix, cold baseline/candidate campaign
or full-tree hash workflow. Historical reports do not certify new changes. Chat
review does not establish pixel, performance, leak or runtime claims.

When compilation is needed, this is an example from the repository root; choose
an installed simulator and the coordinated derived-data location:

```bash
xcodebuild build \
  -workspace ios/JTM.xcworkspace \
  -scheme RailMap \
  -destination 'platform=iOS Simulator,id=<installed-simulator-UDID>' \
  -derivedDataPath /tmp/jtm-derived-data
```

For an existing UI regression that needs execution, use the same workspace,
scheme and build products with `test` and `-only-testing:<target>/<class>/<method>`.
Select the actual identifier from `ios/RailMapUITests`; avoid running all UI tests
as a routine documentation or release-step check. Package parity guidance lives
in [the porting guide](../../ios/docs/porting.md).

## Archive and distribute

Review Release signing and capabilities in Xcode and update the intended version
and build number through the normal review process. Once a release is authorized,
create an archive with the main scheme, for example:

```bash
xcodebuild archive \
  -workspace ios/JTM.xcworkspace \
  -scheme RailMap \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/JTM-RailMap.xcarchive
```

A successful archive command establishes archive creation only. Open it in Xcode
Organizer, validate signing and App Store requirements, then upload when submission
is authorized. Resolve account or provisioning problems with the account holder;
do not weaken signing to bypass them. Any provisioning updates require the
appropriate account access.

Choose release observations based on the changed scope and still-applicable
evidence. For storage changes, exercise import/export and relaunch using disposable
journeys and preserve a backup. For route changes, check the affected journey and
its failure state. For UI or playback changes, observe the affected flow on a
relevant device. Check the processed TestFlight build where processing or release
configuration creates a concrete uncertainty. Preserve typography bounds, iPhone
portrait orientation, physical railway topology and full-viewport basemap dimming
from [the product constraints](../../ios/AGENTS.md).

Record the commit, version/build, toolchain, archive, focused evidence, device/OS
observations and any App Store Connect build identifier. Do not label unperformed
smoke tests or unmeasured behavior as passing.

## Recovery and troubleshooting

- Before upload, correct the candidate and create a new archive. Reuse evidence
  whose dependencies still apply; repeat affected checks only.
- For an affected TestFlight build, stop its testing or promotion through the
  authorized release process and upload a corrected build with a higher number.
- For a phased App Store release, use App Store Connect to pause promotion when
  authorized. App Store distribution cannot instantly replace an installed binary;
  recovery requires a corrected reviewed build.
- Preserve user data. App deletion can remove the local journey library; prefer an
  explicit JSON export when the app is usable. A recovery backup is not a substitute
  for a user-owned export.

| Problem | Response |
| --- | --- |
| Codesign rejects Finder metadata | Move build output outside the iCloud-backed path and rebuild the affected product |
| Build processes contend | Coordinate a single heavy job and its reusable build location |
| Fixture differs | Review the real JavaScript and changed inputs; regenerate only the affected fixture intentionally |
| Portable module imports platform UI | Move the platform integration into RailMap and pass domain values across the boundary |
| Simulator is unavailable | Select an installed compatible simulator in Xcode or `xcrun simctl list devices available` |
| Signing fails | Check main-target team, profiles, certificates and entitlements with the account holder |
| Route cannot be proven | Preserve the unresolved state; do not substitute a straight line |
| Data loss or processed-build crash | Stop promotion and retain reproduction steps, commit/build and crash or storage evidence |

Update this procedure when workspace structure, signing or evidence policy changes.
