# Full iOS audit remediation — 2026-10-12

This records fixes to the confirmed findings in [the full audit](full-ios-code-audit-2026-10-11.md), including production, auxiliary apps, builders and testing software. Current verification follows `ios/VERIFICATION.md`: scoped source/dependency review, reusable evidence, focused existing tests and sequential incremental builds. No commits or pushes, national rebuild, retired runner, complete matrix or corpus fingerprint campaign.

## Implemented scope

| IDs | Resulting behavior |
| --- | --- |
| A01 | Import refuses an unloaded baseline; staged import/preflight cannot overwrite a newer store revision. Saved startup data remains the baseline. |
| A02 | Regrouping cannot restore selection after newer navigation. |
| A03 | Share statistics use map cards actually placed in the layout. |
| A04 | Saved-file deletion throws real errors and refreshes metadata from the actual disk outcome. |
| A05 | Route repair, continuation and Undo await durable persistence; failure is reported and rollback/Undo ownership retained. |
| A06 | Menu editors, including details → Edit, stay open until persistence succeeds; errors remain visible. |
| A07 | UIKit draft-pin fonts obey the existing typography ceiling and remeasure after trait changes. |
| A08 | Widget counts each physical line once and uses one consistent denominator/numerator category, including foreign lines in all-region scope. |
| A09 | Detail endpoints take name/code/time/platform from the same full recorded first/last stop. |
| A10 | Guide vertices/stations use the existing Apple-map datum display conversion once. |
| A11 | Future offline and timetable journeys follow the visible rider choice; explicit override remains stable. |
| A12 | Same kind/operator/name, transfer groups and through-service display no longer grant cross-row physical connectivity. A reviewed continuation callback is the existing proof seam. |
| A13 | Undated records cannot appear in Upcoming. |
| A14 | Inserted calls inherit effective interval rider state, including pass-through semantics. |
| A15 | Clock-role badges within one OCR observation retain arrival/departure order. |
| A16 | Midnight offsets normalize across all original legs before inclusion filtering. |
| A17 | Explicit conflicting station codes cannot be rescued by a homonym; mixed code/name fallback must retain earliest matching section metadata. Swift and JavaScript contracts reviewed together. |
| A18 | Standalone pasted clocks have one adjacent owner. |
| A19 | Timetable picker and detail controls/evidence/accessibility use all four interface languages. Official source names/symbols remain verbatim. |
| A20 | Rounded total minutes carry into hours. |
| X01 | Report paths reject normalized, symlink and hardlink aliases of the input, both at admission and before writing. |
| X02 | Manual, batch and analysis snapshots share one owner lease through completion/cancellation cleanup. |
| S01–S02 | Fixture caches use locking; required family fixtures fail instead of disabling coverage. |
| S03 | Dead private-calibration coverage replaced by a meaningful real recorded-calibration precedence regression. See adjudication below. |
| S04–S05 | Ambient timezone changes share a synchronous main-actor boundary; controlled async observations and cleanup have bounded completion. |
| S06–S07 | Native metrics require real finite samples; share ratios compare actual exports against the requested independent specification. |
| S08–S10 | Required parity populations cannot be empty; byte parity compares UTF-8; named conventional sample membership is independently pinned. |
| S11–S12 | Cancellation assertions wait for loaded/query readiness; native drag coordinates subtract application origin. |
| P01–P02 | Writing-normalizer tests use private temporary roots; unsupported-route checks inspect the actual manifest directory. |
| P03–P04 | Western source tests preserve station identity; platform count assertions require the literal expected count. |
| P05–P06 | NEX assertions inspect actual output or remove redundant literals; missing required Yufuin seeds fail. |
| B01–B02 | Non-passenger defaults remain non-boardable; malformed access dates become collected errors. |
| B03–B05 | Badge metadata updates only successfully written rows; catalog uses recorded day/exclusive bounds; generation requires an exact integer. |
| B06–B07 | NEX rejection names Narita Express; launch benchmark comment describes the five supported regions. |
| B08–B09 | Normalizers validate proposed shared-service/completeness/queue inputs before committing output; rejection preserves existing files. |
| Fujikawa attribution | Seven generator/version edition labels and bundled SQLite rows agree with their pinned JR East publisher URLs; opaque legacy IDs and clock/station evidence retained. |

## Audit adjudications and product boundaries

S03 originally implied missing private calibration evidence. Inspection of the resource and its initial version showed it has always contained four JR-only rows. The repair requires real existing recorded calibration precedence (久大線) and retains private explicit/unknown-order cases; it invents no private calibration.

A12 intentionally stops automatic inference at a surveyed-row boundary when there is no reviewed cross-row connection. Some legitimate multi-row routes formerly accepted by heuristics remain pending until physical evidence is supplied. Passenger through-service display remains available. This preserves the user’s physical-topology requirement.

The seven Fujikawa edition edits do not change service/station/source identities, URLs, clock pins or timetable validity. The bundled SQLite `build_id` and `source_hash` remain historical generator receipts, unchanged. They do not certify a fresh full-corpus rebuild after this targeted metadata repair; the next explicitly requested normal builder can refresh them. No shipped Swift consumer of those receipts was found.

## Verification and review

Executed evidence so far (only affected selections):

- RailKit focused core/test-owner selection: 171 tests in 20 suites passed, log `/private/tmp/jtm-fixes-swift-focused.log`. The first compile found an actual Stop type mismatch; the correction projects canonical fields. Five old local-search fixtures assumed the retired heuristic topology; they now supply explicit reviewed fixture continuations or assert disconnection. No broad rerun was used.
- Final widget/sample selection: 7 StatisticsLineCoverage tests passed; SampleServiceConformance checked 83/83 samples, one test passed. Log `/private/tmp/jtm-fixes-swift-widget-sample.log`.
- Final mixed-identity index selection: 11 RouteSectionPairIndex tests passed, log `/private/tmp/jtm-fixes-a17-focused.log`. This supersedes earlier evidence for that changed index.
- InspectionKit shared-admission selection: 2 tests passed, log `/private/tmp/jtm-fixes-inspection-focused.log`.
- Incremental Catalyst builds succeeded for RailAlignmentInspector and RouteWorkbench, logs `/private/tmp/jtm-fixes-alignment-build.log` and `/private/tmp/jtm-fixes-route-build.log`. Reused DerivedData; separate product directories preserve the paused default inspector executable/debug library. Compiler reports inspector trait-construction deprecation, draft-pin trait-change deprecation and optional AppIntents metadata warnings; no zero-warning claim.
- Python 7 focused rejection/catalog/default-validator tests passed; 28 source-pinned selected tests passed with reusable unchanged inputs; the 4 Hida/Nanki source tests passed after isolated fixture metadata matched their declared historical package pin. Logs `/private/tmp/jtm-python-green.log`, `/private/tmp/jtm-source-tests-green.log`, `/private/tmp/jtm-hida-green.log`. Red reproduction is recorded for affected builder rejection/interval/default defects. The original live package pins were not rewritten to make tests pass.
- Exact-production Foundation badge helper passed retained/skipped/failed row metadata, successful replacement, repeatability and no-write cases, log `/private/tmp/jtm-badge-green.log`. Full AppKit rendering/PNG failure injection remains unmeasured.
- Exact-production report-path helper rejected equal/lexical/symlink/hardlink aliases and admitted a distinct output; input bytes unchanged. Log `/private/tmp/jtm-fixes-report-alias.log`; scoped shell before/after alias cases and syntax also passed.
- Changed Swift/Python syntax and added four-language keys/placeholders inspected; counterpart station IDs, JSONL/SQLite rows and applicable JavaScript identity behavior reviewed. Syntax alone is not a native runtime pass.

Main-app shared native checks completed:

- Catalyst `RailMapTests` build-for-testing succeeded with the existing DerivedData and two jobs, log `/private/tmp/jtm-fixes-native-build.log`. The hosted test app skips AppShell; the existing DEBUG UUID storage branch also injects isolated preferences. Test owners each use unique preference suites.
- First NativeImportPersistenceTests selection executed 15 methods: 13 passed, including both startup import modes, preflight refusal, staged baseline change, newer navigation, preferences-domain isolation, OCR cancellation awaiting the actual owner, import cancellation, real write failure/retry, screenshot retry, backup publication failures and restore retry. Two newly added tests reported three oracle issues. The save result's completion Date differed from file modification time; canonical serialization/decoding does not preserve every in-memory optional default. These were test assertions, not demonstrated failed persistence.
- Corrected deletion test first reads actual filesystem metadata, then requires real deletion failure, preserved date and byte-identical file. Corrected Undo test establishes original durable canonical bytes, verifies repaired notes after saving, then requires exact original bytes and notes after persisted Undo. Independent review confirmed that the assertions retain and strengthen their intended guarantees. Production source did not change because of those failures.
- Incremental test recompile succeeded, log `/private/tmp/jtm-fixes-native-rebuild.log`. Exact Swift Testing function identifiers with `()` selected only the two corrected methods; **2/2 passed**, exit 0, log `/private/tmp/jtm-fixes-native-two-selected.log`, result `/private/tmp/jtm-fixes-native-two-selected.xcresult`. The other 13 methods retain applicable evidence because their relevant sources and inputs did not change. An intervening filter without `()` executed zero tests; `/private/tmp/jtm-fixes-native-two.log` is retained but establishes no pass.
- Ten changed UI XCTest source files plus their actual EditorLaunchSupport dependency passed direct Swift 6 typechecking against the iOS Simulator SDK, log `/private/tmp/jtm-fixes-ui-typecheck.log`. This required no simulator launch or additional app build. The existing LongJourneyDetail setUp orientation statements produce actor-isolation warnings; no zero-warning claim.

Integration review also identified shared preferences leakage in native tests, late deletion completion clearing newer save errors/sample metadata, and a cancellation assertion that did not join the real owner. Coordinated fixes inject preferences with production `.standard` defaults, guard deletion completion by captured revision/sequence, and return/join the existing OCR operation task. All five affected paths received independent final source review. These changes retain startup/baseline/navigation fixes.

All required focused checks are complete under the current policy. The railway capture owner confirmed resuming the same paused PID/plan/output after release; its captured count advanced from 73834 to at least 73875, with six existing failures preserved. Separate inspector products preserved its executable/debug library; that resumed process retains old loaded code and is not evidence of the new admission behavior. UI tests, pixel/performance/leak/geographic measurements and full matrices are not claimed. Swift tests added before source fixes did not receive native RED execution while the capture slot was unavailable; passing GREEN plus source/review evidence is reported accurately.

Independent reviewers inspected app/UI fixes, core/Swift-test/auxiliary fixes, and Python/Grok fixes. Initial review identified the details editor lifetime, untranslated detail controls and mixed code/name index mismatch; these were addressed and receive focused follow-up. Review is source evidence, not a pixel/performance/leak/geographic measurement.

Preexisting user source moves and other-chat changes were preserved. Exact per-worker pre-task copies in `/private/tmp/jtm-fix-*-before` supplied scoped diffs, rather than treating Git HEAD as the audited baseline. Grok 4.7 xhigh performed the 22 NEX diagnostics and benchmark comment; its CLI reached its turn cap (exit 1) after edits, so the parent independently compared every diagnostic and the unchanged benchmark function body. No CLI completion claim is made.

New regression files: `ios/tools/tests/test_line_service_catalog_intervals.py` and `ios/tools/tests/test_normalizer_rejection_preservation.py`. Existing native, package, Python and UI regression files were extended. UI test source corrections do not constitute executed UI regressions.
