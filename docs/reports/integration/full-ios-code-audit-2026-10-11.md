# Full iOS code and testing-software audit — 2026-10-11

Remediation follow-up: [all confirmed findings addressed with focused evidence](full-ios-code-audit-fixes-2026-10-12.md). The findings below remain the historical pre-fix audit; S03’s private-calibration assumption is corrected in the remediation receipt.

Completed semantic source review: **1,316/1,316 files; no unreviewed remainder**. Scope comprises **608 Swift, 682 Python, 7 shell, 4 Xcode project files and 15 additional configurations/workspaces/schemes/backup files**; code/project sources total approximately 295,789 physical lines. This is a full current-source audit, not a changed-files review. Production and test code were not edited.

## Scope and method

The scope includes every first-party Swift, Python and shell source under `ios/`, active and inactive code backups, auxiliary inspector applications, benchmark/software tooling, package and app tests, UI tests, Xcode projects/workspaces/schemes, package manifests and relevant build configuration. Generated build products, third-party binaries, media and dataset payloads are not source code; relevant bundled records and JavaScript counterparts were inspected when a finding depended on their identity or shared behavior. The exact per-file ledger is the scope authority.

Applied Matt Pocock's **codebase-design**, **improve-codebase-architecture** and **tdd** test-quality guidance, alongside iOS development, Swift concurrency, Swift Testing, SwiftUI performance review, railway identity/topology, Superpowers review/verification, model-routing and Grok delegation skills. Architecture judgments use depth, interface, seam, locality and the deletion test. TDD was used to assess existing tests, not to create tests or change behavior.

GPT-6.1 Sol subagents reviewed bounded app, core and test tranches; Grok4.7 at xhigh reviewed tooling/test tranches. The parent reconciled overlapping suggestions, read auxiliary code/configuration, checked decisive caller/data contracts, and adjudicated findings. Complete semantic coverage means every executable statement and literal was reviewed. Exact repeated code may inherit a fully read template only after every sibling difference has also been reviewed. Inventory, parsing and searches alone do not count as semantic review. Standalone comments/blank lines could be omitted; relevant contract comments were read. Truncated reads were recovered before completion.

This follows [ios/VERIFICATION.md](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/VERIFICATION.md)'s current policy. No tests, builders, builds, app launches, full matrices, corpus hashes or retired runners were executed for this audit. Evidence is source reasoning and targeted read-only record/query inspection. The audit establishes neither a passing test run nor pixel, leak, performance or geographic alignment correctness. No source snapshot was frozen; the final inventory and modification metadata were reconciled, including inspector files added during review.

## Priority findings — app and core

| ID | Priority | Finding and concrete trigger | Evidence |
|---|---|---|---|
| A01 | P1 | Append import during initial load can replace saved journeys with the import. Staging uses an empty baseline while the saved store is still loading, and publication has no readiness/revision fence. | [ItineraryStore.swift:349](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Journeys/ItineraryStore.swift:349); UI tranche1 |
| A02 | P2 | Regroup restores a selection captured before an await, overwriting a later user selection. | [ItineraryStore.swift:728](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Journeys/ItineraryStore.swift:728); UI tranche1 |
| A03 | P2 | An overflowing map omitted from the exported canvas still restricts exported statistics. Layout placements and effective scope disagree. | [ShareComposerModel.swift:341](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Sharing/ShareComposerModel.swift:341); UI tranche1 |
| A04 | P2 | Failed saved-store deletion is treated as success; metadata disappears while the file survives and reappears after reload. | [RideStorage.swift:158](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Infrastructure/Persistence/RideStorage.swift:158); UI tranche1 |
| A05 | P2 | Card Repair and Undo update the in-memory canonical journey without saving it. Relaunch loses the change. | [RailWorkspaceView.swift:2495](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Workspace/RailWorkspaceView.swift:2495); UI tranche3 |
| A06 | P2 | Journey-menu editor closes on a synchronous mutation result before persistence succeeds, losing the chance to report/rollback a write failure. | [JourneyMenuView.swift:75](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Journeys/JourneyMenuView.swift:75); UI tranche3 |
| A07 | P2 | Draft UIKit map labels bypass the permanent typography ceiling, unlike the shared font policy. | [JourneyLabelAnnotationViews.swift:265](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Map/JourneyLabelAnnotationViews.swift:265); UI tranche3 |
| A08 | P2 | Line-detail widgets flatten overlapping masks and emit duplicate line rows/SwiftUI identities. | [StatisticsDashboardContent.swift:531](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Statistics/StatisticsDashboardContent.swift:531); UI tranche3 |
| A09 | P2 | Partially ridden journey details pair the full origin name with the first ridden stop's clock/platform. | [RideDetailView.swift:359](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Journeys/RideDetailView.swift:359); UI tranche4 |
| A10 | P2 | Railway-guide polylines and station coordinates bypass the selected Apple Map display datum. The coordinate path is inconsistent; actual offset was not measured. | [RailwayRouteGuideView.swift:581](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/JourneyEditor/RailwayRouteGuideView.swift:581); UI tranche4 |
| A11 | P2 | Offline future plans silently set both endpoint rider flags true, without an override, entering Passport ridden totals. Preserve stored rider facts rather than excluding every future date from statistics. | [NewTripView.swift:1074](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/JourneyEditor/NewTripView.swift:1074); UI tranche5 |
| A12 | P2 | Interchange/identical-kind heuristics admit unsupported physical continuations in planning and route inference, including the independent Shinkansen termini at Tokyo. Final route certification can reject them; wrong rendered geometry is not claimed. | [TripConnectivity.swift:27](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Routing/TripConnectivity.swift:27); core tranche1 and UI tranche2 |
| A13 | P2 | Valid `undated` records appear in Upcoming because dates are compared lexicographically. | [WorkspaceJourneyRules.swift:104](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailPresentation/Workspace/WorkspaceJourneyRules.swift:104); core tranche1 |
| A14 | P2 | Timetable completion propagates a preceding rider flag into inserted calls, creating ridden subintervals inside an originally unmarked interval. | [JourneyCompletion.swift:695](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Import/JourneyCompletion.swift:695); core tranche2 |
| A15 | P2 | OCR with arrival and departure in one observation loses the role badges and swaps clocks; unmarked midnight sorting is another manifestation. | [TransferGuideText.swift:109](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Import/TransferGuideText.swift:109); core tranche3 |
| A16 | P2 | Midnight rollover is performed independently per screenshot leg; a next-day connection is saved on the preceding date. | [TransferGuideTrains.swift:187](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Import/TransferGuideTrains.swift:187); core tranche3 |
| A17 | P2 | Adjacent-route fallback rescues an explicit conflicting station code by name, retaining a different city's homonym section. Verified example is two different 大宮 IDs. This is stale physical input, not proof that final certification draws it. | [Train.swift:1770](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Journeys/Train.swift:1770); core tranche3 |
| A18 | P2 | One standalone pasted clock row is attached to both adjacent stations, inventing an arrival for the following station. | [JourneyTextImport.swift:163](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailKit/Sources/RailCore/Import/JourneyTextImport.swift:163); core tranche4 |
| A19 | P3 | Timetable picker controls/evidence statuses stay Japanese despite the chosen English/Chinese interface language. Official station/service names are a separate concern. | UI tranche2, corroborated tranche4 |
| A20 | P3 | Rounding an average duration can display `2h60min` rather than carrying the minute into hours. | [StatisticsFormatting.swift:78](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMap/Statistics/StatisticsFormatting.swift:78); UI tranche3 |

## Auxiliary software

| ID | Priority | Finding | Evidence |
|---|---|---|---|
| X01 | P2 | RouteWorkbench can overwrite its input with a report when the paths are identical or aliases. The shell guard compares strings, so `/tmp/input.json` and `/tmp/./input.json` evade it. | Auxiliary review |
| X02 | P2 | Manual capture and batch capture have independent admission state, allowing overlapping inspector snapshots. Runtime overlap/incidence was not measured. | Auxiliary review |

The refreshed AppleMapRailExtractor, its tests and AppleMapAnalysisService were also reviewed. They explicitly report rendered glyph candidates and unsupported/ambiguous gaps; they do not establish physical identity, surveyed alignment or track count.

## Swift testing-software findings

These are confirmed defects in failure sensitivity or test-state ownership. They do not assert that the currently bundled production data is wrong or that a failure was reproduced.

| ID | Priority | Finding | Evidence |
|---|---|---|---|
| S01 | P2 | Parallel Swift Testing suites read/write unsynchronized static fixture caches. | Swift tests tranche1 |
| S02 | P2 | A required family-window fixture's absence disables its parity test instead of failing required evidence. The fixture exists currently. | Swift tests tranche1 |
| S03 | P2 | Private-railway calibration test returns successfully when no usable calibration remains. | Swift tests tranche1 |
| S04 | P2 | Process-wide default timezone overrides are not isolated across parallel tests. | Swift tests tranche1, corroborated tranche4 |
| S05 | P2 | Controlled async test observers can wait indefinitely on the regression they should report; observation and cleanup need bounded completion. | Swift tests tranche1 |
| S06 | P2 | Map-probe upper-bound assertions accept missing/unparseable `-1` measurements. | Swift tests tranche2 |
| S07 | P2 | Share-ratio matrix checks self-produced pixel dimensions without independently asserting the requested ratio; all requests can silently use the default. | Swift tests tranche2 |
| S08 | P2 | Required route-parity fixture cases can become empty and leave their focused loops green. | Swift tests tranche3 |
| S09 | P2 | Byte-parity helper uses canonically equivalent Swift String equality before comparing code units, accepting changed archive bytes. | Swift tests tranche4 |
| S10 | P2 | Production branding lookup decides whether a conventional sample belongs in conformance coverage; a lost lookup removes the failing sample. | Swift tests tranche4 |
| S11 | P2 | Cancellation absence assertion can pass before library loading and the requested search have completed. An adjacent save test already has the needed readiness fence. | Swift tests tranche4 |
| S12 | P3 | A UI drag helper applies the application's nonzero origin twice. No runtime flake was measured. | Swift tests tranche3 |

## Python testing-software findings

| ID | Priority | Finding | Evidence |
|---|---|---|---|
| P01 | P2 | Discovery and current-N02 tests run writing normalizers against the repository, masking bad stored artifacts and risking changed canonical outputs on failure. | Python tranche2 |
| P02 | P2 | Unknown-route tests check `normalized/trip-line-segments` while the manifest loads `normalized/trip-lines`; unsupported route rows in the real directory escape the assertions. | Python tranche3 |
| P03 | P2 | Several Western source-pinned stop checks discard normalized station identity, preserving clocks/platforms while a station is substituted. | Python tranches1/3, merged |
| P04 | P2 | A two-platform count uses `assertEqual(actualCount, otherCount, 2)`; `2` is the message, and zip silently ignores added matching rows. | Python tranche1 |
| P05 | P3 | Two NEX unknown-formation assertions check literal `None` in their own EXPECTED fixture. A separate observed-equipment test provides real output coverage. | Python tranche3 |
| P06 | P2 | Missing Yufuin normalized seeds skip the formation/direction assertions, leaving required materialized coverage incomplete. The seed exists currently. | [ios/tools/tests/test_kyushu_yufuin_six_20260930_source_pinned.py:94](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/tests/test_kyushu_yufuin_six_20260930_source_pinned.py:94) |

Expectations imported from production normalizer PINS are lower-independence preservation oracles, not automatically tautologies. Comparing candidate data to generated data legitimately checks preservation but does not independently reverify the printed timetable. Those scope limits are recorded in the detailed reviews rather than inflated into separate bugs.

## Tooling/builders — parent-adjudicated findings

| ID | Priority | Finding and scope | Source |
|---|---|---|---|
| B01 | P2 | Validation defaults omitted non-passenger pickup/dropoff permissions to 0, while insertion defaults them to 1. A permitted pass/operational/unknown input can therefore become boardable/alightable. This is a latent accepted-input defect; the current bundled database's 30 pass and 1 operational rows all retain false permissions. | [ios/tools/train_timetable.py:593](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/train_timetable.py:593), `:1002` |
| B02 | P2 | Missing/numeric `accessed_at` raises uncaught TypeError in the validator instead of returning collected field errors. The field-presence phase collects errors but continues into the date match. Current reviewed registries use strings. | [ios/tools/train_timetable.py:314](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/train_timetable.py:314) |
| B03 | P2 | Badge manifest refresh removes cropResolved/badgePixels for every row, then restores only successfully composed rows. A skipped/failed existing badge loses measurements even though its PNG is retained. Replace metadata only for successful corresponding writes. | [ios/tools/rebuild-operator-badges.swift:153](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/rebuild-operator-badges.swift:153), `:832` |
| B04 | P2 | Service-catalog builder excludes any corridor/leg with validTo, even when that exclusive end is still in the future, and uses machine-local today instead of the recorded observation day. Current seven requested corridors have null validTo; this is a latent interval/reproducibility defect. | [ios/tools/build-line-service-catalog.py:62](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/build-line-service-catalog.py:62) |
| B05 | P3 | historical_generation accepts JSON true because isinstance(True,int) succeeds, contrary to the positive-integer field contract. Use the same exact-int rule already used for count fields. No current boolean row was found. | [ios/tools/train_timetable.py:335](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/train_timetable.py:335) |
| B06 | P3 | NEX identity rejection diagnoses a missing Narita Express service as Kaiji; this obscures which reviewed identity failed. | [ios/tools/normalize-reviewed-east-narita-express9-20260930.py:51](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-east-narita-express9-20260930.py:51) and reviewed siblings |
| B07 | P3 | Launch benchmark's comment names the United States while its actual inputs are the five supported regions. This is stale prose; no US data is loaded. | [ios/tools/bench/Sources/RailBench/LaunchBench.swift:12](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/bench/Sources/RailBench/LaunchBench.swift:12) |
| B08 | P2 | Current and priority N02 normalizers publish completeness/research changes before all target and fact validation completes; a rejected input leaves claims ahead of route evidence. Fujikawa2 also writes its shared service before candidate validation. | Normalizer tranches2/3 |
| B09 | P2 | Akagi overwrites native evidence before validating the English source URL; rejection then removes previously valid English evidence. | Normalizer tranche3 |

B01 follows the public canonical-input contract: pickup_allowed/dropoff_allowed are optional stop_times fields, and non-passenger call types are valid. The final database consumer maps nonzero to permission, and boarding eligibility checks that permission. Fix preparation's call-type-aware defaults or require explicit false values for non-passenger calls, preserving origin/destination semantics. The source path was traced; no synthetic builder campaign was run.

B02 is a validator error-reporting defect for malformed external input, not a claim the bundled registry fails. Guard the field's type before regex/timestamp parsing, keeping error collection and order intact.

B03 is a concrete partial-failure preservation problem. The tool has an explicit sourceAsset skip path that promises to keep that badge unchanged; global metadata stripping violates it. Do not replace every builder with a transactional framework on this evidence.

The omission of operator-history from the reviewed-trip rebuild driver remains an ownership/reproducibility observation. Root operator JSONL can be intentionally checked-in input, and no current mismatch or documented full regeneration requirement proved an app defect. Similarly, ODPT kinds with null section endpoints lose machine-readable section detail but are explicitly partial, line-keyed inventory with a textual scope. No caller was shown interpreting them as whole-line certified operation; that proposed geography defect was not promoted.

Fujikawa2/4/6/8/10/12/14 source IDs and edition text say JR West/Odekake while their URLs name JR East. This is a confirmed repository provenance inconsistency, also locked by tests. The official publisher was not externally reverified, so the audit does not choose a replacement source or claim clocks are wrong. Reconcile source_id, publisher/edition metadata and URL using reviewed evidence before repinning tests. See [ios/tools/normalize-reviewed-central-fujikawa2-20260930.py:12](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-central-fujikawa2-20260930.py:12) and [ios/tools/tests/test_central_fujikawa24_20260930_source_pinned.py:37](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/tests/test_central_fujikawa24_20260930_source_pinned.py:37).


## Architecture recommendations

1. **Strong: deepen the journey mutation module.** Initial-load admission, baseline revision, mutation publication and durable outcome currently leak through callers. Concentrate those rules behind the existing production interface/seam. Preserve ADR0005 ordered atomic JSON storage. The deletion test favors concentrating ownership because callers demonstrably coordinate the same rules. Fix startup data loss first; broaden only enough to keep its invariant local.
2. **Worth exploring: make a share-layout plan authoritative.** Placements, overflow, frames and statistics scope should come from one immutable module. Preview/export/drag are real adapters; concentrating interpretation improves locality and lets an overflow test cross one interface.
3. **Worth exploring: one inspector capture admission owner.** Manual and batch capture share the same expensive snapshot resource. Concentrate admission and cancellation behind one seam while retaining separate evidence scopes and human geographic verdicts.

Existing physical graph certification, ordered storage, shared-work cancellation and narrow lifecycle owners often provide useful depth. No broad module/file-length rewrite is recommended. The visual before/after report accompanies these three bounded candidates.

## Rejected suggestions and remaining evidence limits

- Legacy pattern projection intentionally has partial validity; native applicability returns unknown. Lack of calendar expressiveness is recorded as a model limitation, not a demonstrated date-correctness bug.
- Whole-line retirement bounds intentionally replay ordered overlay stamps. Replacing that with an intersection would change the stated contract; no conflicting current record justified it.
- The benchmark percentile calculation can return the maximum for a small sample, which is mathematically consistent with its chosen estimator. The prose explanation is misleading; no measured performance defect follows.
- West/Hokkaido base formation imports deliberately require later enrichment overlays; the rebuild driver explicitly restores Haruka/Thunderbird planned counts/capacity. Standalone invocation losing an overlay is a sequencing limitation, not a confirmed full-rebuild regression. Hokuto evidence bounds are likewise refreshed from exact calendar additions before builds.
- Null-clock Fuji rows carrying minute accuracy have no explicit schema prohibition and native route matching separately checks clock presence; metadata observation only.
- Ambiguous fingerprint concatenation, falsy return-type hypotheticals and blanket transactional builder rewrites were not promoted without a concrete relevant failure contract.
- Grooming still has a source/policy lead involving non-collinear micro-kink support deletion. No specific current corridor/site and native evidence established a geographic defect. Preserve this as unresolved evidence, not an alignment verdict.
- Ride-time first-to-last semantics differ from interval mileage, but the current statistics code expressly defines that span. No automatic rewrite is justified by the difference alone.
- NewTrip civil-time/DST preservation remains an unmeasured lead. No current reproduced failure is claimed.

Prior verification reports remain historical. This audit does not infer a pass from them, and its complete source coverage is separate from runtime test coverage.

## Detailed evidence and coverage

- [Auxiliary](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/auxiliary.md)
- [Core 1](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/core-1.md)
- [Core 2](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/core-2.md)
- [Core 3](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/core-3.md)
- [Core 4](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/core-4.md)
- [Ui 1](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/ui-1.md)
- [Ui 2](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/ui-2.md)
- [Ui 3](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/ui-3.md)
- [Ui 4](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/ui-4.md)
- [Ui 5](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/ui-5.md)
- [Swift Tests 1](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/swift-tests-1.md)
- [Swift Tests 2](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/swift-tests-2.md)
- [Swift Tests 3](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/swift-tests-3.md)
- [Swift Tests 4](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/swift-tests-4.md)
- [Python Tests 1](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/python-tests-1.md)
- [Python Tests 2](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/python-tests-2.md)
- [Python Tests 3](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/python-tests-3.md)
- [Normalizers 1](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/normalizers-1.md)
- [Normalizers 2](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/normalizers-2.md)
- [Normalizers 3](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/normalizers-3.md)
- [Normalizers Parent](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-parts/normalizers-parent.md)

[Exact file-by-file semantic-review ledger](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11-coverage.json). [Architecture before/after diagrams](/private/tmp/architecture-review-20261011-ios.html).

The coverage ledger records source review, not executable line/branch coverage. Overlapping reviewers were merged only when their status represented a complete semantic read. The three inspector files discovered in the final inventory and both workspace descriptors were read by the parent. Source ownership metadata also matched all 335 App/RailKit production source paths uniquely, with no missing/unowned paths in that declared scope.
