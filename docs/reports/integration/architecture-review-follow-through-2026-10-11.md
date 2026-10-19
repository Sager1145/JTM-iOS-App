# Architecture review audit and fixes — 2026-10-11

Source: the user-supplied `architecture-review-20261011-223832.html`. Current working code, not the historical commit, was the audit baseline. Existing source moves, data repairs and uncommitted work were preserved. The prior route-resolution/catalog-eligibility deepening in `architecture-deepening-2026-10-12.md` was checked before changing those areas.

## Confirmed recommendations

| Finding | Result |
|---|---|
| Recorded-route admission | `RecordedRouteAdmission` owns apply/guide/corridor-preference outcomes. Machine origin survives native/web import/export and semantic route/playback caches. Legacy origin-absent interval choices remain authored. Automatic materialization cannot downgrade them. Inferred failures may retry physical solving; authored/database choices cannot silently change. |
| Corridor tests through worker | Six Reviewed corridor suites use ordinary `import RailCore`, a shared resource snapshot and `RideRouteResolution`. Independent physical registry/edge/date/source-arm assertions remain. Physical source path keys are dated inspection evidence, not drawing coordinates or persisted identity. |
| Reviewed timetable staging | 161 normalizers now use five shared staging profiles: Odekake single trips (35), JR East coupled columns (29), Shinano exact-date trips (23), JR East single columns (51), and West EXPECTED batches (23). Printed facts, provider validation, equipment and forced-code differences remain explicit; CLI filenames remain compatible. No filesystem adapter was added. |
| Route-repair session | `RouteRepairSession` owns alias loading, off-actor repair, accumulated progress and localized summary; results carry the original baseline and reject changed/deleted records. Editor and workspace retain their draft/persistence adapters. The failing-span algorithm is in RailCore. |
| Statistics membership | `StatisticsMembership` owns ridden/region/year/group/date/area-candidate filtering and available years/dates. `WorkspaceDerived` remains and now keys actual candidate IDs. Map overnight-span dates and passport record-date buckets intentionally differ. AppShell, dashboard, passport, sharing and mileage adapters use the policy. |
| UI-test launch | `UITestLaunchConfiguration` owns 36 stable external keys, shared by app and runner; `UITestLaunchSupport` prepares/launches cases. Existing locale, scenario and relaunch values remain. Externally seeded memory cases explicitly retain their existing container. The UI target links RailPresentation. |
| Map/picker rules | `StationBeadPolicy`, `RiddenCategoryVisibility` and `ServicePatternBrowsePolicy` own prior policy. Native adapters retain viewport/LOD, cache lifetimes and async-generation admission. Bead sibling facts and zero-distance source category lines remain lazy. |
| Station joins | `OverlapLanes.buildRouteRecords` owns the join and retained source fit lines. `StationJoinSmoothing` is an internal implementation stage. JP/TW curated end-to-end parity calls the record builder; 24 meaningful primitive/rejection cases remain. Source paths and physical topology are unchanged. |

## Smaller findings and audit disposition

| Finding | Disposition and evidence |
|---|---|
| EditorAIEligibility parallel stops | Fixed: removed the projection and unused occurrence UUID. JourneyCompletion checks native stops through the production eligibility interface. A pass-through arrival alone no longer unlocks completion; its departure can. Busy/provider priority and editor unconfirmed-time semantics remain. |
| JourneyRouteState store-wide derivation | Fixed: removed the test-only resolver; tests now drive per-record RouteStatusResolver and its presentation bridge. The gap list remains at the rich status interface; presentation intentionally carries localized text. |
| MapDrawChanges flags | Retained: it owns actual redraw precedence and the hidden-network geometry-arrival exception. Inlining it would move policy back into the coordinator. The flag carrier remains a possible future deepening opportunity, not a demonstrated correctness defect. |
| Two draft sessions / RecordDate | Removed NewTripView's duplicate civil-date spelling through RecordDate. Draft session differences remain: new-trip staging and editing a persisted journey have distinct persistence/time behavior. |
| ContinuousStroke internal tests | Retained meaningful geometric/radius invariants. Public built-stroke tests already exist; deleting internal invariants without restating them would weaken coverage. |
| RailwayDirection step | Queries retain distinct exclusions, occurrence and date-completeness semantics. No query merge performed. Shared step construction remains an optional future refactor. |
| OperatorIdentity branding fallback | Existing uncoded-name fallback remains; no observed wrong company membership justifies a naming-policy change in this audit. |
| Three civil-date predicates | Retained deliberately distinct contracts; no universal boolean introduced. |
| Recorded section guards | Retained separate route editing and label editing fallbacks. No observed defect requires collapsing them. |
| Trip applying / compatibilityPattern | Two required projections remain; no new conversion or persistence model introduced. |
| CanonicalTrainStoreJSON.quote | Cross-runtime parity behavior retained. No replacement quoting algorithm introduced without a concrete failing parity case. |
| ImportStaging / ImportPreflight | Both use ImportEngine.Session for distinct staging/preflight entry points; no filesystem adapter or extra engine added. |
| StationLabelVisibility dummy Train | Fixed with type/region limited-express classification. Full-Train catalog-name recognition remains. Distinct zoom admission and priority role switches retained. |
| TripStationIndex | Existing private UI matcher remains; no observed search mismatch justifies moving its distinct company-filter/index behavior in this pass. |
| labelMergeMeters | Fixed: one public StationDisplay 600m constant is used by map coordinator and ride station importance. |
| InspectorStrokeGeometry | Distinct isolated zero-lane inspection contract remains; map drawing uses family/adjacent seams and lane profile. Inspector source is owned by the concurrent Mac-tools chat. |
| WorkbenchCore seam decoder | Survey inspection and CompactPackage interval decoding have different contracts; retained. |
| Inspector distance radius | Independent 6,371,008.8m inspection measure differs from production 6,371,000m. No measured alignment defect; no numerical standard changed. |
| TransferGuide name tests | Existing parser-name invariants remain; no parser rewrite justified by the architecture report alone. |
| Python source pins | Shared staging behavior has 9 public scratch regressions. Existing per-train data/provenance assertions remain, including 13 selected tests. The new source-presence pin was removed; distinct evidence/update verbs are retained by audited scope rather than a file-text test. |
| Timetable wrappers / badge renderer | Report marked speculative or intentionally standalone. Retained. |

## Review and verification

Applied the Matt Pocock selector and relevant architecture, codebase-design, implementation, TDD, domain-modeling and code-review practices together with Superpowers and the project policy. No issue tracker, external tickets, recurring gate, commits or publishing were introduced. A small project glossary records passenger choice, corridor preference, package inference and physical/display geometry terms.

Independent Standards review found no actionable map-policy defect. Independent Spec review found a native/web inferred-fallback mismatch and automatic re-admission of authored choices; both were corrected. Independent launch review found Debug seeded-memory cases changing containers; corrected with `existingContainer` and a public regression test.

Heavy checks are serial and reuse existing scratch/DerivedData. No full matrices, nationwide builders, umbrella runners, full-tree hashes, capture campaign or automatic verification loop was used. Compile/runtime evidence is recorded below when completed; syntax parsing and read-only review do not prove pixels, performance, leaks or geography.

- First focused Swift attempt: compile failed at new branding overload's optional region; fixed without changing nil-region semantics.
- Second focused Swift attempt: compile failed because Swift Testing's macro cannot call a mutating policy on its immutable captured value; tests now evaluate the policy before asserting.
- Third focused Swift attempt: 60 presentation tests and 2 application tests passed; core run executed 155 tests, with the Utazu source-arm test failing 24 assertions. Other core cases passed. The failure was stale fixture array positions: RailHistory expands identity-period copies and changes indices. The same reviewed arms are now selected by independent literal surveyed endpoint pairs, company/line/date with a unique-match requirement. Every quantised source vertex, forward/reverse direction and junction/connector proof remains. The focused Utazu rerun passed 1 test covering eight variants (exit 0, `swift-utazu-focused.log`). No worker/data/source change was required; the other 216 tests remain valid.
- Native/web origin roundtrip and physical inferred-fallback tests: 15 JavaScript tests passed. Two expected RED failures reproduced the inferred fallback discrepancy before the web fix.
- Native app and UI-test runner: `xcodebuild` of `RailMap Debug`, Mac Catalyst, reused existing RailMap DerivedData, two jobs, `build-for-testing` succeeded (exit 0, `native-build-for-testing.log`). This compiled both adapters and the linked launch module; it did not execute UI tests. Existing UIKit deprecation, AppIntents metadata and XCTest actor warnings remain; no zero-warning claim.
- Swift total: 217 selected tests across the combined run and focused Utazu correction passed. Logs are `/private/tmp/jtm-architecture-audit/swift-focused3.log` and `swift-utazu-focused.log`. The combined run originally exited 1; it is not described as an all-green invocation.

These checks do not establish strict executed red-green for all refactors: Swift tests were written during the implementation while another chat owned the heavy slot. Existing working code was never removed solely because it preceded a test.

## Timetable consolidation evidence and limits

The inventory contains 354 normalizers and two annotators. The initial remaining-family inventory overcounted the single-column group by three: those scripts contain coupled/create-service behavior. Actual source review corrected the group to 51 rather than forcing all 54 through it.

- Grok 4.7 xhigh implemented the first 87 migrations, shared parser/validation/emission rules and scratch tests. Its recorded terminal output confirms byte-equivalent emitted output for all 87 against exact before copies. Root reviewed the implementation and source facts. The first turn limit ended before edits; the resumed worker was stopped after migration when it entered final-test integration/runtime troubleshooting. Its exit 130 is not a completed-check claim; root owns final verification.
- Sol implemented another 74 callers and supplied the two additional profiles. Ten representative scratch before/after executions had identical files and stdout: Kaiji 10/31/2/59, NEX 12, Yakumo 9–12, Kuroshio 2–5/19–22, Thunderbird 6/9/10 and Haruka/Thunderbird batches. Kaiji 59's existing printed 24-hour clocks and day-offset 1, Kaiji 2 service creation, Thunderbird's extra source/URL verification and Kuroshio equipment annotations are retained.
- Root merged the profiles and explicit forced-code policy, removed duplicate identical definitions created during integration, and reviewed all 161 caller syntax trees. 1,141 shared original literal facts have no differences. This is source review of the changed recipes, not full-tree hash custody.
- `python-shared-final.log`: 9 public shared staging behavioral tests passed, exit 0. They use scratch inputs and known expected clock/offset, unknown-route, coupling/equipment, station-policy and rejection-before-write behavior. They do not require before-copy files or dataset generation.
- `python-existing-focused.log`: 13 existing NEX coupled-column, Kaiji 59, Kuroshio and Yakumo source-fact tests passed, exit 0. They read existing data and exercise preserved per-train validation/materialization; no builder or production staging command ran.
- The 195 remaining scripts include different emitted-entity contracts, equipment/platform adjuncts and operator-history/route-evidence/pass-mark verbs. They were reviewed but not collapsed merely because their filenames match. Smaller potential profile groups remain future architecture opportunities; this is not a claim that all 354 scripts or all historical source-pinned tests were merged.

No railway package, timetable dataset, station ID, source evidence or generated database was changed by this audit. Build resource copies stayed in DerivedData; staging checks emitted only scratch output. No commits, pushes or publication.

Final independent staging review (`review-staging-final.md`) found no actionable standards or concrete preservation defect in the merged five profiles. It reviewed source and existing focused evidence without another test campaign.
