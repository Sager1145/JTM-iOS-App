# Verification

On 2026-10-10 the 1,055-line umbrella `ios/verify.sh` and every `ios/tools/verify-*`
harness were retired. The same day a lightweight opt-in dispatcher was kept at
`ios/verify.sh`. That dispatcher is the current entry. It is not the deleted
umbrella. To read a retired script, run `git show 75031837:<path>`.

The remaining standalone data audits, validators, performance and coverage runners,
and their dedicated helper tests were subsequently retired too. Artifact builders,
runtime validation, saved evidence and native production regression tests remain.
Builder `--check` modes are available only when a change specifically requires them;
they are no longer an automatic verification pipeline.

## Current verification policy (2026-10-10)

### Explicit optional modules (user request, 2026-10-10)

The user subsequently requested a lightweight modular `ios/verify.sh` and actual
checks using the two Mac inspector apps. This new entry point is opt-in: no
arguments prints help, and no module invokes another module automatically. It
does not restore the retired pipeline. Run it with `bash ios/verify.sh`.

| Module | Explicit selection | Work performed |
|---|---|---|
| `swift` | `--filter TEST_NAME` | Existing focused RailKit Swift tests (`swift test --package-path ios/RailKit --filter`), two jobs by default, reused scratch products. This module does not run Xcode native tests |
| `build` | `--target diagnostics` | One incremental unified Catalyst build, two jobs by default, reused DerivedData |
| `diagnostic` | `--request /absolute/request.json` | One exact RailDiagnostics task; request selects alignment capture, route solve or through-history inspection |

Every module supports `--dry-run`. Build and Swift modules accept `--jobs` and explicit build/scratch locations. The diagnostic module accepts `--app`; the unified app must already be built. Use a new session directory when task scope/settings change; resume the same immutable request to retain valid evidence. The app captures one requested line automatically at its requested zoom/viewport/appearance. Partial and failed evidence stays explicit; launch/capture completion is not an alignment verdict. The old standalone RouteWorkbench, ThroughWorkbench and RailAlignmentInspector app targets are retired; their implementations remain internal modules of RailDiagnostics.

```sh
bash ios/verify.sh swift --filter TimetablePhysicalRouteMatchTests
bash ios/verify.sh build --target diagnostics
bash ios/verify.sh diagnostic --request /private/tmp/rail-diagnostic-request.json
```

The `RailMap` scheme builds the app and its Test action contains `RailMapUITests`
only. It does not contain `RailMapTests`. Native tests, including
`NativeImportPersistenceTests`, `ShareComposerLayoutTests` and
`ShareComposerScopeTests`, run with `-scheme RailMapTests`:

```sh
xcodebuild test -project ios/RailMap.xcodeproj -scheme RailMapTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:RailMapTests/<Suite>/<case>
```

A RailKit `--filter` that selects zero tests is not a pass. `xcodebuild test`
against the `RailMap` scheme cannot select `RailMapTests`.

Start in chat with the actual diff and its affected callers, state owners and data
records. Explain the expected behavior and examine the likely failure case. Select
the smallest evidence needed to resolve a concrete uncertainty. If a change has a
Swift/JavaScript counterpart or affects a bundled station/line/geometry ID, review
that counterpart and the affected resource references in the same chat. Reuse existing
results when their relevant source, inputs, toolchain and configuration still apply;
do not rehash entire trees to establish this.

- Documentation and mechanical changes: inspect the diff and references.
- Logic and lifecycle changes: trace the changed path and review the relevant
  existing regression test; run that test only when execution is needed.
- Data changes: review changed IDs and source evidence, schema fields, joins and
  validity boundaries (day before/on a changed date). Use targeted reads or queries
  against those records and their immediate neighbors. Expand to dependent records
  when a shared rule changes. Do not regenerate national datasets for a small edit.
- UI changes: review state/layout and existing relevant captures. Use one affected
  device and one case if a native observation is necessary.
- Performance, leak or pixel claims: use an existing applicable measurement or one
  focused native observation. Chat review does not establish those measured claims.

Use one shared incremental build per applicable source state when compilation is
needed. Coordinate the heavy job across chats; reuse its products, and run one heavy
job at a time. No cold baseline/candidate builds, full before/after suites, per-chat
full matrices, corpus-wide hashes, synthetic evaluator test campaigns or new wrapper
scripts by default. Broaden a check only for a concrete dependency or failure. Stop
once the necessary evidence answers the question; an interrupted run proves no pass.

Keep a short result in the owning chat's existing ledger: changed scope, evidence
used, outcome and any remaining uncertainty. Preserve the app's typography bounds,
orientation rules, physical topology requirements and other product constraints.
Do not turn retiring a gate into a claim that its requirements now pass.

The five JTM coordination/refactor chats have been instructed to stop their old
pipelines, explain and delete their owned scratch verification scripts, and record
a lighter process only where their scope needs one. Their proposals live in
`ios/refactor-parallel/`. No replacement umbrella script is introduced here.

## Retired umbrella gate (historical, not the current script)

What follows is the deleted 1,055-line umbrella. `bash ios/verify.sh` does not
run it. The living entry is the opt-in dispatcher above, which forwards one
module to `ios/tools/verification/{swift,build,route,alignment}.sh`. It has no
`native` mode. Do not treat the stages below as a gate that still runs.

Modes the umbrella accepted: everything (default), `--swift`, `--core`, `--js`, `--app`,
`--boundaries`, `--native`. `SCRATCH` set the build directory, which had to be off
the iCloud volume because codesign rejects FinderInfo. `APP_DESTINATION` set the
xcodebuild destination. CI ran `--boundaries` and `--core` in
`.github/workflows/port-parity.yml`.

Stages, in order:

1. **Boundaries**: `verify-typography-limit.py` and `verify-source-ownership.py`
   (with `tools/tests/test_source_ownership.py`).
2. **JavaScript**: `build-port-fixtures.mjs --check` (the fixtures still match the
   JS reference), `validate-station-tables.py` (ADR 0010 schema and code grammar),
   and `build-station-names.py --check`.
3. **Swift**:
   - `verify-train-timetable-artifact.py` (one shared snapshot).
   - `build-train-service-station-refs.py --check`.
   - A cold `swift build` of RailKit, then `swift test`, which summed the Swift
     Testing summaries across targets.
   - The native harnesses listed below.
   - Zero warnings in RailCore, RailPresentation and RailApplication.
   - Import rules: RailCore imports only Foundation, plus SQLite3 confined to the
     timetable DB. RailPresentation imports Foundation and RailCore.
     RailApplication imports Foundation, Observation and RailCore.
   - Detail-ladder constants agree between JS and Swift (390 pt reference).
   - Survey decimation tolerance matches in both renderers.
   - The annotation layer is used only by the map.
   - The tw/hk/mo/kr datum rule: probed per MapKit service, shared data stays WGS84.
   - Every station link goes through `StationPlaceLink`.
4. **App**:
   - `xcodebuild` builds RailMap for the iOS Simulator with zero warnings in
     `/RailMap/`.
   - Every branding badge resolves to an image iOS can decode; the asset-catalog
     icon compiled, checked via `CFBundleIconName` and its renditions.
   - About 30 grep-based source contracts on app behavior:
     - Editors persist; samples load into their own region; edits reload the map.
     - The passport counts only ridden journeys, as a stated fact.
     - Statistics are not recalculated when unchanged and load lazily on Passport.
     - Playback survives a tab switch, keeps overlays, and uses narrow MapKit
       invalidation.
     - Package reads are single-pass; the badge index reads attributes only; region
       weight classes match the packages.
     - Route load publishes cached rides first; datasets are scanned once; the
       route-cache sweep runs once per launch.
     - Stores are written in order and atomically; journeys are grouped in one pass.
     - The working set has a single writer.
     - The video exporter runs on the main actor.
     - The docked card reports the strip it covers.

## `ios/tools/verify-*`: individual harnesses

Most of these extract production Swift unchanged, compile it against small doubles
plus a prebuilt RailKit scratch, and assert on lifecycle, ownership or control flow.
They do not use a simulator unless noted.

| Script | Checked |
|---|---|
| verify-typography-limit.py | The permanent app text-size bounds are not removed or widened |
| verify-source-ownership.py | Every production Swift file is assigned exactly once in `ios/source-ownership.json`; target import boundaries hold |
| verify-train-timetable-artifact.py | Timetable DB, historical map artifact and bundled resource describe the same snapshot (also a step in `rebuild-reviewed-train-timetable.py`) |
| verify-editor-validation.py | The production journey-editor validator against valid and invalid drafts |
| verify-store-ordering.py | Native persistence: ordered, atomic writes in canonical spelling |
| verify-timetable-quick-match-lifecycle.py | Timetable lookup controller: canceled requests can't overwrite newer ones |
| verify-route-caches.py | Route invalidation, line-cache guards, SolverInputCache ownership and order |
| verify-input-plumbing.py | Graph/input lifetime and batch ordering through both solver passes |
| verify-route-availability.py | Batched, read-only, dated physical route availability |
| verify-physical-section-continuity.py | Route outcomes, gap persistence, ridden-mileage scope |
| verify-passport-distance.py | Passport grouping of complete, partial and pending mileage |
| verify-map-endpoint-stations.py | Endpoint station lookup without promoting partial railway paths |
| verify-display-network-cache.py | Display-network cache retention and shared build lifecycle |
| verify-edge-index-cache.py | Statistics-index cache retention and shared build lifecycle |
| verify-selected-station-snapshot.py | Snapshot lifecycle owner with controlled async loads |
| verify-map-label-collision.py | Label collision grid against explicit cases and an oracle |
| verify-map-pan-geometry.py | MapKit chunk geometry and reuse (macOS host) |
| verify-map-worker-lifecycle.py | Render worker admission, publication, route-cache reuse |
| verify-ride-station-layering.py | Ride station renderer in a macOS bitmap context |
| verify-route-resolution-cancellation.py | Route task lifecycle with a cancellable solver double |
| verify-map-detail-fades.py | Map-detail fades rendered with a deterministic clock |
| verify-map-public-projection.py | Projection fit math on holdout positions and degenerate input |
| verify-route-progress.py | Progressive publication by the production decoder |
| verify-playback-lifecycle.py | Playback controller state transitions (display link stubbed) |
| verify-playback-video-lifecycle.py | Video exporter ownership and cleanup (no real encoding) |
| verify-independent-rail-paint.py | Raster check of screen-space rail paint: compositing, alpha and path semantics |
| verify-subscription-auth.py | ChatGPT subscription auth through URLProtocol fixtures |
| verify-subscription-service.py | Subscription HTTP code through URLProtocol fixtures |
| verify-completion-request.py | AI request lifetime with suspended actions |
| verify-share-card-rendering.py | Share-card render and export lifecycle (image order, cancellation) |
| verify-selected-route-readiness.py | Selected-record completion query |
| verify-station-picker-search-lifecycle.py | Station-picker search owner under suspension and replacement |
| verify-station-lookups.py | StationPlaceStore against a fake MapKit transport |
| verify-route-projection-performance.py | Route projection parity and bounded-search timing (diagnostic only) |
| verify-transfer-screenshots.py / .swift | Vision OCR plus the TransferGuide parser on screenshots, printing JSON (a tool, not a gate) |
| verify-layout-ui-smoke.sh | Simulator UI smoke: wide-iPad by default, `iphone` runs the phone workspace regression |
| verify-reduce-motion-ui.sh | UI test under the real Reduce Motion setting, then restores the setting |
| verify-zoom-platforms.py | Railway zoom regressions on explicitly chosen simulators |

These test files were also deleted because they only tested the deleted scripts:
`ios/tools/tests/test_source_ownership.py` and
`ios/tools/tests/test_timetable_artifact_alignment.py`.

## Additional retired scripts and helper tests

These entries preserve purpose, not executable copies. Existing generated reports
and source evidence remain historical evidence. Their presence does not certify
newly changed code or data. The retired CI workflows ran port/fixture parity,
layout simulator smoke tests, Swift lint/debt and instrumented coverage, and Japan
history coverage/boundary checks. They are removed pending the scoped proposals.

| Former path | Purpose |
|---|---|
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/hiroden-m18/verify 3.py` | Standalone verify 3 verification helper. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/hiroden-m18/verify.py` | Standalone verify verification helper. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/hiroshima-tosaden/test_verifier 3.py` | Test cases: exact checkpoint partition, package english never supplies evidence, native mutation rejected, group mutation rejected, operator mutation rejected, cross operator native does not leak, numbered hiroden path identities, tosaden exact owned map paths, no invented published station ids, asakura exact bilingual header, published names new stop and distinct takasu, native full names not silently shortened, source id conflict is explicit, source tamper rejected, frozen checkpoint and package unchanged |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/hiroshima-tosaden/test_verifier.py` | Test cases: exact checkpoint partition, package english never supplies evidence, native mutation rejected, group mutation rejected, operator mutation rejected, cross operator native does not leak, numbered hiroden path identities, tosaden exact owned map paths, no invented published station ids, asakura exact bilingual header, published names new stop and distinct takasu, native full names not silently shortened, source id conflict is explicit, source tamper rejected, frozen checkpoint and package unchanged |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/hiroshima-tosaden/verify 3.py` | Exact unresolved membership delta from official map labels and own route identity. Hiroden station IDs and infrastructure paths are parsed from its own directory; English is hand-transcribed from its paired current numbered EN map. Tosaden's bilingual map has no station numbers: page/route/node locators are audit locators, not invented official station IDs. Explicit native/group/line/operator route bindings identify its colocated native/English map nodes. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/hiroshima-tosaden/verify.py` | Exact unresolved membership delta from official map labels and own route identity. Hiroden station IDs and infrastructure paths are parsed from its own directory; English is hand-transcribed from its paired current numbered EN map. Tosaden's bilingual map has no station numbers: page/route/node locators are audit locators, not invented official station IDs. Explicit native/group/line/operator route bindings identify its colocated native/English map nodes. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/keikyu/test_verify 3.py` | Test cases: cohort partition, english poison, crossoperator, reordered path, group mismatch, airport html linebreaks |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/keikyu/test_verify.py` | Test cases: cohort partition, english poison, crossoperator, reordered path, group mismatch, airport html linebreaks |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/keikyu/verify.py` | Operator-scoped native+number+physical route bindings; English visual transcript. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/korail/test_tail 3.py` | Test cases: checkpoint scope and exhaustive partition, explicit physical service scoped identity, coordinate conflicts and crossoperator not promoted, actual official spelling preserved, rebuild is deterministic and read only |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/korail/test_tail.py` | Test cases: checkpoint scope and exhaustive partition, explicit physical service scoped identity, coordinate conflicts and crossoperator not promoted, actual official spelling preserved, rebuild is deterministic and read only |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/korail/verify_tail 3.py` | Offline narrow Korail physical/service bridge; no canonical file writes. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/korail/verify_tail.py` | Offline narrow Korail physical/service bridge; no canonical file writes. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/kr-operators/second-pass/test_delta.py` | Test cases: every pending membership accounted exactly, frozen operator line and group unchanged, existing coordinate blocks retained, ambiguous operator and adjacent native rejected, operator and line mutations do not verify, verbatim labels namespaces and first delta hash |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/kr-operators/second-pass/verify_delta.py` | Offline second pass; writes only beside this scratch verifier. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/kr-operators/test_tail.py` | Test cases: exact frozen scope, no legal entity alias, coordinate conflicts retained, labels and code namespaces, concrete route mismatch not source absence, source hashes and checkpoint |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/kr-operators/verify_tail.py` | Reproduce a scratch-only, frozen unresolved Korean operator evidence delta. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/matsuura-kotoden/verify_kotoden.py` | Only Kotoden: exact native colocated EN/JA map paths; Matsuura remains pending. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/nishitetsu-iyo/test_verifier.py` | Test cases: expected frozen cohort counts, exact unresolved partition, package english is not evidence, changed group rejected, changed native rejected, changed operator rejected, changed physical line rejected, changed station order rejected, checkpoint native rejected, cross operator lookalike does not leak, exact own published spelling and renames, native alias uses exact published record, distinct rail tram and hommachi nodes, branch membership not inferred from published english, altered raw source rejected, unreviewed transcription reject |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/nishitetsu-iyo/verify.py` | Reproduce unresolved-only evidence; English is own published text, never package English. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/toyama/test_verifier 3.py` | Test cases: exact unresolved partition, package english cannot supply evidence, native mutation rejected, operator mismatch rejected, station group mutation rejected, unrelated operator same native does not leak, numbered map route segments, rail tram identity and published spelling, c21 suffix does not silently normalize, snapshot integrity, frozen inputs unchanged |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/toyama/test_verifier.py` | Test cases: exact unresolved partition, package english cannot supply evidence, native mutation rejected, operator mismatch rejected, station group mutation rejected, unrelated operator same native does not leak, numbered map route segments, rail tram identity and published spelling, c21 suffix does not silently normalize, snapshot integrity, frozen inputs unchanged |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/toyama/verify 3.py` | Build Toyama-only unresolved membership delta from manually reviewed numbered maps. This never reads a package English field. Membership bindings are explicit exact lineId + operator + station group + native, with a T/C mode and map station ID. English comes only from the retained, labeled visual transcription. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/toyama/verify.py` | Build Toyama-only unresolved membership delta from manually reviewed numbered maps. This never reads a package English field. Membership bindings are explicit exact lineId + operator + station group + native, with a T/C mode and map station ID. English comes only from the retained, labeled visual transcription. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/toyama-c21/test_verify.py` | Test cases: exact identity, package english unused, operator mismatch, native mismatch, exact qualifier required, current alias required |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/toyama-c21/verify 3.py` | C21 parenthetical native identity bridge; operator English remains authoritative. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/toyama-c21/verify.py` | C21 parenthetical native identity bridge; operator English remains authoritative. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/us/test_us_tail.py` | Test cases: exact pending membership partition, package english is not proof, ace route reordering rejected, cross operator leak rejected, njf numeric identity rejected, njt location conflict rejected, capture digest is not pdf digest |
| `app/data/station-english-verification-candidates/2026-10-01-tail/sources/us/verify_us_tail.py` | Primary-source delta for the twelve checkpoint-unresolved US memberships. |
| `app/data/station-english-verification-candidates/2026-10-01-tail/validate.py` | Standalone validate verification helper. |
| `app/scripts/railway/audit-na-package.py` | Re-check every line in a built package, against the package's own rules. python3 scripts/railway/audit-na-package.py --package public/rail/us-2025.json --package public/rail/ca-2025.json --out data/raw/na-rail/audit.json The builder decides; this asks, afterwards and from the outside, whether what it shipped is what it said it would ship. That is a different question from "did the build succeed", and it is the one a reader of the data actually has: the builder cannot catch a rule it applied wrongly, because it is the thing applying it. Nothing  |
| `app/scripts/railway/audit-north-america-packages.py` | Fail closed when a North American rail package cannot support its claims. This is the release gate for ``us-2025.json`` and ``ca-2025.json``. Counts are not evidence of completeness, so the gate checks the source registry, build report, geometry comparison, station/segment contract, adaptive grooming metadata and audited branding together. |
| `app/scripts/railway/audit-shared-corridors.py` | Find public railway lines that should reuse one compact-v1 corridor. This audit is deliberately cross-line. The ordinary package audits validate one line at a time and therefore cannot see two service lines that describe the same railway with slightly different vertices. The high-confidence rule is intentionally narrow: * both lines have the same railway type (high-speed, commuter, metro, ...); * both call at the same two grouped stations consecutively; * their surveyed paths stay in the same corridor; and * the paths are not already coincident |
| `app/scripts/railway/audit-straight-intervals.py` | STRAIGHT_INTERVAL ledger for the NA packages -- DEFECT 2 detection. `na_geo.densify()` (lib/na_geo.py, bands in lib/na_profile.py) subdivides every edge COLLINEARLY to <= max_edge_m by band (street 120 / metro 160 / commuter 220 / regional 350 / longhaul 600 m). A station-to-station straight line therefore ships as a chain of short straight pieces, so chord-length and vertex-density checks cannot see it: `STRAIGHT_CHORD`/`SPARSE_GEOMETRY` in the `jtm-railway-audit-repair` skill's preflight, and `interval.straight` in this directory's own `audit |
| `app/scripts/railway/audit-with-hotspots.sh` | Full seven-region structural scan plus required high-error map screenshots.  |
| `app/scripts/railway/check-station-english-sources.py` | Reproduce reviewed evidence from the retained official source snapshots. |
| `app/scripts/railway/crosscheck-na-stations.py` | Measure every station's published position against OpenStreetMap's. python3 scripts/railway/crosscheck-na-stations.py --package public/rail/us-2025.json --package public/rail/ca-2025.json --tile-dir data/raw/na-rail/osm-stations --out data/raw/na-rail/station-crosscheck.json ## Why this exists separately from the line cross-check `download-north-america-osm-crosscheck.py` measures the *alignment* — every vertex of every built line against an independent source. It says nothing at all about the stations, and a package can have both its track in  |
| `app/scripts/railway/history/audit-jp-history-coverage.py` | Report coverage of the canonical Japan rail-history event ledger. This audit compares the curated inputs in ``jp-rail-history-events.json`` with the generated ``rail-history.json`` overlay. An optional official-source inventory may add an independent list of expected historical events. The default mode is diagnostic and prints every gap without turning accepted legacy gaps into a permanently red CI check. ``--baseline-max-unresolved`` is the structural CI gate: generated artefacts must still trace to canonical events, every canonical event must |
| `app/scripts/railway/history/check-overlay-event-coverage.py` | Fail when a rebuilt rail-history overlay drops an event the previous one had. History ids gain compiler suffixes (``.sections``, ``.stations``, ``.identity``, ``.periodN``, ``.current``, and a trailing token). The event id is what remains. An id present in OLD and absent in NEW fails unless ``--allow-superseded`` lists it. |
| `app/scripts/railway/history/verify-jp-history-boundaries.mjs` | Verify every effective validity transition in the compiled Japan history. The verifier evaluates the production Web loader and route-validity helper in a Node VM. It applies every retirement to the current sections/stations, appends the overlay, then generates day-before/day-of fixtures from every actual service-validity boundary in that resulting dataset. This is a loader/availability check. It does not invoke the route solver or either client's final display pipeline. |
| `app/scripts/railway/jp-manual-corrections/verify.mjs` | Structural verification of app/public/rail/jp-2025.json after the jp-manual-corrections batch has been applied. The compact package's stored km is the real (pre-simplification) track length for lines built by the main GTFS/N02 pipeline, while `segments` coordinates are a display-simplified polyline; haversine-of-polyline therefore under-measures curvy pre-existing intervals by a few metres up to ~35m on the longest rural lines. That drift is a pre-existing package characteristic (present on lines this batch never touches), not something introdu |
| `app/scripts/railway/measure-display-blocked-intervals.py` | Measure display-blocked station intervals against OSM railway geometry. The package alignment gate withholds a station interval whose geometry deviates from an independent reference (usually the operator's own GTFS shape or a NARN reconstruction) by more than the profile limit for its kind. This script re-measures a withheld interval a second way: vertex by vertex, against the nearest active OpenStreetMap railway way of the same line type, pulled from Overpass tiles staged on disk as gzipped JSON (`osm-geom/*.json.gz`, the raw `{"elements": [.. |
| `app/scripts/railway/report-na-coverage.py` | Say which passenger railways the packages do NOT contain. python3 scripts/railway/report-na-coverage.py --inventory data/raw/na-rail/osm-inventory.json --package public/rail/us-2025.json --package public/rail/ca-2025.json --out data/raw/na-rail/coverage.json "Every passenger railway" is a claim, and the honest way to make it is to name an independent inventory and say what is in it that is not in the packages. The inventory here is OpenStreetMap's: every route relation in North America tagged `route=train\|subway\|light_rail\|tram\|monorail\|funicul |
| `app/scripts/railway/tests/test_jp_east_station_english_verification.py` | Test cases: table parser retains publisher id and routes, exact station id pairs languages and preserves official spelling, no english name fallback when native identity does not match, homonyms require route identity and ambiguous route is refused, native typography is accepted without phonetic normalization, station detail counterpart requires matching published numeric id, complete snapshot preserves compact codes and operator memberships |
| `app/scripts/railway/tests/test_jp_nankai_station_english_verification.py` | Official bilingual identity and coverage regressions for Nankai. |
| `app/scripts/railway/tests/test_jp_overlay_event_coverage.py` | Test cases: suffixes strip to the event id, dropped event fails unless allow listed, allow file requires a reason |
| `app/scripts/railway/tests/test_jp_private_station_english_verification.py` | Exercise private operator identity matching and retained official snapshots. |
| `app/scripts/railway/tests/test_jp_station_english_verification.py` | Official master identity checks for Hokkaido, Osaka and JR Central. |
| `app/scripts/railway/tests/test_kr_second_pass_station_english.py` | Test cases: original six regressions and partition, current operator mismatch, current native mismatch, current code mismatch, persisted station code mismatch, unknown country, source freshness, stale output check |
| `app/scripts/railway/tests/test_kr_station_english_verification.py` | Test cases: same native name in another city cannot verify, same operator wrong line cannot verify, korail mainline contamination not verified by busans metro, coordinate disagreement cannot verify, exact official parenthetical name is retained, generated package english is never evidence, current official conflict remains unresolved, raw digest and offline rebuild, every membership has exactly one outcome, group coverage requires every membership, incheon seongnam is not guessed seoknam, all verified records have official identity evidence |
| `app/scripts/railway/tests/test_na_border_audit.py` | Test cases: explicit connector preserves foreign canonical identity, plain domestic line cannot claim foreign station, border metadata does not excuse wrong country prefix, invalid connector is not a general country exception |
| `app/scripts/railway/tests/test_na_package_audit.py` | Test cases: verified official straight track is not called a guess, unverified straight track remains an error, colour requires official source, audited relation is a warning not an error, without the evidence chain it is still an error, osm is not promoted to a verified official network, a white railway is refused, yellow is not white, the palest colour the packages ship still passes, each drawn colour is judged against its own theme, a branch that only calls at the other platform, a branch that draws its own railway is left alone, a stop of t |
| `app/scripts/railway/tests/test_na_station_english_verification.py` | Test cases: raw capitalization accents and whitespace are preserved, stop id parser preserves case and hyphens and requires operator, retained id wins over nearby bus stop or display name, equal name elsewhere never matches, ambiguous coordinate and conflicting source ids are refused, wmata serialized source parser preserves id and exact label, rail coordinate fallback excludes nearby bus platform, smart evidence requires exact heading and retains map semantics, saved snapshot covers every package membership once |
| `app/scripts/railway/tests/test_narn_reference_reader.py` | Test cases: reads main track and drops service track, keeps record with no net field, handles nested coordinate lists, narn ways feed measure against like osm ways |
| `app/scripts/railway/tests/test_next_official_station_english.py` | Boundary checks for the portable JP/KR source gate. |
| `app/scripts/railway/tests/test_reviewed_jp_fukuoka_evidence.py` | Test cases: all memberships and shared numbers, package romanization has no effect, wrong native identity is unresolved, comments do not prove native identity, changed source hash is rejected |
| `app/scripts/railway/tests/test_reviewed_jp_shikoku_evidence.py` | Test cases: complete snapshot, package english never evidence, wrong published route fails closed, ambiguous native groups fail closed, source tampering rejected, transcription tampering rejected, branch identity and temporary names |
| `app/scripts/railway/tests/test_reviewed_jp_west_evidence.py` | Test cases: homonyms require published line station ids, prefecture suffix keeps full published label, non prefecture parentheses are not stripped, manifest digest mismatch is rejected, exact package membership coverage, every promoted label is verbatim official sign text |
| `app/scripts/railway/tests/test_shared_corridor_audit.py` | Test cases: proper crossing ignores shared endpoints and collinear track, proper crossing reports interior side swaps |
| `app/scripts/railway/tests/test_straight_intervals.py` | A straight north-south line at 40 degrees latitude. Station spacing here (~1.1 km per 0.01 degree of latitude) keeps every distance well above the 1,500 m STRAIGHT_INTERVAL chord floor with round numbers of stations. |
| `app/scripts/railway/tests/test_tw_afr_transfer_station_english.py` | Operator-scoped proof for the shared TRA/AFR Chiayi station. |
| `app/scripts/railway/tests/test_tw_station_english_verification.py` | Verify official identity admission and every retained Taiwan snapshot. |
| `app/scripts/railway/validate-station-tables.py` | Validate the jp/tw/hk/mo station tables against ADR 0010 (exit 1 on any failure). See docs/decisions/0010-unified-station-tables.md. Stdlib only. |
| `app/scripts/railway/validate-ttc-subway-osm.py` | Measure Toronto's subway geometries against the City's topographic survey. python3 scripts/railway/validate-ttc-subway-osm.py --source-dir /path/to/na-rail Three statements of where TTC Line 1 and Line 2 run are compared here: * the City of Toronto subway route layer, which is byte-for-byte the TTC's own GTFS shape (`official-networks/ttc-subway-{1,2}.geojson`); * the OpenStreetMap route relations the registry accepts for the two lines (`osm-routes/ttc-subway-relations.json`); * the City's topographic mapping of subway track, `COTGEO_TOPO_RAILW |
| `app/scripts/railway/verify-jp-east-station-english.py` | Pair JR East's official bilingual timetable rows by retained station IDs. |
| `app/scripts/railway/verify-jp-fukuoka-station-english.py` | Verify Fukuoka memberships against retained visible native list and reviewed numbered map. No network, package mutation, package romanization, or generated readings are used. The English map has outlined text; map-labels-reviewed.json is a human-readable transcription reviewed against the retained PDF rendering/JPG on 2026-10-01. |
| `app/scripts/railway/verify-jp-nankai-station-english.py` | Verify Nankai English through bilingual official line indices and station IDs. |
| `app/scripts/railway/verify-jp-private-station-english.py` | Build reproducible private-railway English evidence from official snapshots. Bilingual station headers and station master records supply the names. No existing package English field or kana romanization supplies evidence. Japanese native spelling selects an unambiguous identity within the exact operator; line/group keys are retained to prevent interchange labels leaking to others. |
| `app/scripts/railway/verify-jp-shikoku-station-english.py` | Rebuild scratch evidence from retained official PDF visual transcription. No network, package English, or transliteration. Intended for review before integration. |
| `app/scripts/railway/verify-jp-station-english.py` | Verify Hokkaido/Osaka/JR Central names from operator-owned bilingual station identities. |
| `app/scripts/railway/verify-jp-west-station-english.py` | Rebuild JR West evidence from retained operator-published station signs. English is copied verbatim from ekiSignBox__romanization, never transliterated. Native identity is exact within JR West's directory. Duplicate native labels require an explicit directory result line, prefecture, and official station ID. The older nationwide reservation PDF and train-guide masters are retained for source discovery but do not authorize promotion across operators. |
| `app/scripts/railway/verify-kr-second-pass-station-english.py` | Regenerate eleven reviewed KR proofs offline from retained publications. First-pass scope is reproduced from raw publications, never loaded from cached English evidence. Retained coordinate blocks and mismatches remain unresolved. |
| `app/scripts/railway/verify-kr-station-english.py` | Verify Korean memberships against retained official bilingual rows. Offline deterministic rebuild. No package romanization or English values are proof. Operator/line identities are scoped; nationwide native-name matching is prohibited. Sources are raw anonymous data.go.kr downloads. XLSX is read with the stdlib. |
| `app/scripts/railway/verify-na-station-english.py` | Recover exact operator GTFS labels using retained feed/stop identities. The compact packages canonicalize transfer names and uppercase labels. These are display decisions, not evidence of the operator's original spelling. This verifier keeps raw stops.txt bytes and their archive digest. It joins the source station features' feed/operator/stop IDs before considering a tightly bounded coordinate fallback; it never matches names across a country. |
| `app/scripts/railway/verify-next-official-station-english.py` | Offline regeneration from retained operator publications and reviewed transcripts. All runtime paths derive from the app directory. Only the supplied output changes; cohort scripts execute in a private working copy. The reviewed ledger defines the available historical cohort, not a completeness requirement for future packages. Requires pypdf for retained PDF text extraction. No network access is performed. |
| `app/scripts/railway/verify-tw-afr-station-english.py` | Validate AFR's reviewed bilingual excerpts and retain original HTML evidence. No station label is rewritten: a changed official heading or identity rejects the update. Website page IDs remain distinct from AFR dataset station codes. |
| `app/scripts/railway/verify-tw-afr-transfer-station-english.py` | Verify AFR's membership at shared Chiayi separately from TRA's evidence. |
| `app/scripts/railway/verify-tw-station-english.py` | Build Taiwan station English evidence from hashed official PTX snapshots. Only operator-specific bilingual station identities present in an official StationOfLine response are admitted. A package flag or existing English value never supplies evidence. Run offline after fetching the raw files recorded in station-english-sources/tw/manifest.json; --check verifies reproducibility. AFR station-page evidence is maintained separately by the unified catalog. |
| `app/scripts/validation/audit-japan-sample-branding.mjs` | Exhaustive consistency audit for the Japanese sample and its line badges. This deliberately checks the runtime objects rather than the compact rows: compact `logo: 1` is only a download flag, while RailNetwork expands it to the actual parent badge path used by split lines and paired alignments. |
| `app/scripts/validation/check-source.mjs` | Standalone check source verification helper. |
| `app/scripts/validation/check-undefined-globals.mjs` | Classic scripts share one lexical scope in the browser. Check the complete ordered family together so references between files are resolved correctly. IIFE/UMD modules publish browser globals as properties rather than lexical declarations. Only assignments in the loaded scripts define these names. |
| `ios/tools/advisory-swift-quality.sh` | Read-only, advisory Swift checks. Tool exit codes are evidence, not a CI gate. Explicit files avoid traversing generated Swift or tool caches. Neither tool receives an autocorrection flag, and SwiftFormat's cache is disabled. These configurations enable only the named refactor rules. Keep --strict so SwiftLint warnings |
| `ios/tools/audit-apple-map-datums.swift` | A reproducible, geographically distributed station audit against the same MapKit service the iOS app draws over. Run from the repository root: xcrun swift ios/tools/audit-apple-map-datums.swift [jp\|tw\|hk\|mo\|kr] The package side is read from `app/public/rail/*-2025.json`; the Apple side is live `MKLocalSearch`. For interchange complexes the closest combination of package platform and Apple result is used, because both legitimately carry several coordinates under one passenger-facing station name. Japan — Hokkaido to Okinawa, with the three large |
| `ios/tools/audit-reviewed-candidate-identifiers-platforms-20260930.py` | Read-only check of reviewed September 30 train numbers, clocks and platforms. Run after rebuilding train-service-timetable.sqlite. The check requires each candidate's explicit trip ID to materialize on the selected day and verifies the SQLite template plus dated platform override, without mutating either. |
| `ios/tools/audit-station-places.swift` | What fraction of stations the card's 「マップで開く」 can hand to a real Apple Maps place, and which places it picks. Build it against the shipped rule rather than a copy of it, so that a change to `StationPlaceLink` is a change to what this measures: cd ios xcrun swiftc -O -o /tmp/audit-station-places \ tools/audit-station-places.swift \ RailKit/Sources/RailPresentation/StationPlaceLink.swift cd .. && /tmp/audit-station-places [jp tw hk mo kr] [--per-country 40] The package side is read from `app/public/rail/*-2025.json` and `app/data/station-readings |
| `ios/tools/audit-station-readings.mjs` | ========================================================================= audit-station-readings.mjs — does the station-name table still cover the networks the app draws, and the journeys it ships? node ios/tools/audit-station-readings.mjs [--check] [jp tw hk mo kr] The runtime table is `app/data/station-names*.json`, one per region. Two kinds of table live under that one name and they fail differently, so they are measured differently: Taiwan, Hong Kong, Macao, Korea** — the table holds the station's official NAME in each of the four interface |
| `ios/tools/audit-train-service-validity-migration.py` | Audit the v2 validTo -> v3 exclusive validUntil migration. By default the v2 catalog is read from the commit immediately before the v3 migration. A JSON file can be supplied instead for shallow checkouts or an archived baseline. This tool is read-only. |
| `ios/tools/audit-train-timetable-coverage.py` | Standalone audit train timetable coverage verification helper. |
| `ios/tools/audit-train-timetable-history-alignment.py` | Audit timetable service dates against the rail-history service intervals. |
| `ios/tools/audit-train-timetable-migration.py` | Inventory legacy IDs without treating route summaries as timetable evidence. |
| `ios/tools/audit-train-timetable-routes.py` | Report prerequisites for dated route audits; never treat connectivity as via proof. |
| `ios/tools/audit-train-timetable-stop-chronology.py` | Check dated, materialized stop clocks, including exact-date overrides. |
| `ios/tools/audit-zoom-chords.mjs` | Emit the real rail-network.js display inputs for audit-zoom-chords.swift. */ |
| `ios/tools/audit-zoom-chords.py` | Audit zoom-dependent straight chords in every shipped railway region. The extractor calls production rail-network.js. The compiled Swift probe calls production ContinuousStroke.buildStroke and Geometry.douglasPeuckerIndices. Findings are review candidates: the detector measures visible skipped bends; it does not assert that every chord is geographically wrong. |
| `ios/tools/audit-zoom-chords.swift` | Counts final ink, excluding source hard turns by their preserved measure. |
| `ios/tools/coverage-report.py` | Report supplied LLVM LCOV coverage against a frozen candidate diff. Production scope defaults to ios/RailKit/Sources and ios/RailMap. Input paths may use either frozen snapshot prefix; repository-relative source identities are preserved. A missing changed file is unmapped, never an excluded comment. This report describes supplied instrumentation, not test-suite completeness. |
| `ios/tools/evaluate-refactor-performance-20261009.py` | Offline acceptance of a predeclared paired five-real-region experiment. Reads evidence only; never builds, launches, modifies a device, or fills missing baseline samples. See --schema for the collection contract. Exit 0 means these performance gates passed for the declared source/device/cache/workload only; leaks, M, full-map stress, and overall refactor completion remain separate. |
| `ios/tools/export-package-coverage.py` | Export existing instrumented SwiftPM binaries with a supplied merged profile. Runs llvm-cov sequentially; never builds, tests, merges or mutates profiles. Each binary gets a separate LCOV file and an input-identity manifest receipt. Coverage describes supplied instrumentation, not complete package/test coverage. |
| `ios/tools/inspect-independent-rail-raster.py` | Inspect original 3x iPhone raster-probe screenshots against the native rail. Only near-vertical red spans with both native green flanks yield a center. These limited snapshot sections do not establish motion latency, globe behavior, or whole-scene acceptance. The frame code is read from displayed pixels. Requires one or more unmodified screenshots from testNativePolylineRasterFrameProbe. |
| `ios/tools/measure-release-route-memory.py` | Measure the fixed two-region Release route phase with paired fresh processes.  |
| `ios/tools/measure-route-graph-memory.py` | Compare macOS physical footprint for identical small graph-cache workloads.  |
| `ios/tools/persistence-harness/DiskChecks.swift` | Standalone DiskChecks verification helper. |
| `ios/tools/persistence-harness/EditorChecks.swift` | Standalone EditorChecks verification helper. |
| `ios/tools/persistence-harness/QueueChecks.swift` | A controllable collaborator for the production RideLibrary queue. This deliberately has the same surface as RideStorage. The Python driver compiles the unmodified RideLibrary definition above it, then substitutes this actor for the filesystem implementation below it. |
| `ios/tools/quality-debt-report.py` | Compare pinned SwiftLint reports using unchanged source-line identities. |
| `ios/tools/run-independent-rail-prototype-tests.py` | Explicitly opt into experimental map projection UI tests. Writes only a derived .xctestrun copy; the shared Xcode scheme stays unchanged. Accuracy assertions remain frozen and failures represent experiment NO-GO. |
| `ios/tools/tests/test_coverage_report.py` | Small LCOV/diff fixtures; no Swift builds or production data are loaded. |
| `ios/tools/tests/test_evaluate_refactor_performance_20261009.py` | Synthetic evidence exercises evaluator semantics; no product measurements. |
| `ios/tools/tests/test_export_package_coverage.py` | Exercise bundle discovery and LLVM command receipts through a fake runner. |
| `ios/tools/tests/test_measure_release_route_memory.py` | Apple footprint response fixtures; never launch a device or external tool. |
| `ios/tools/tests/test_quality_debt_report.py` | Verify shifted legacy debt, increased metrics and incomplete lint evidence. |
| `ios/tools/train-service-checklist.py` | Generates docs/reference/train-service-database-checklist.md from the bundled train-service catalog (names + stop patterns), plus the optional test reports emitted by TrainServiceCatalogChecklistTests (TRAIN_CATALOG_CHECK_REPORT) and TrainServicePatternRouteTests (TRAIN_PATTERN_ROUTE_REPORT). Python 3 stdlib only. See ios/tools/train-service-checklist.py --help. |
| `ios/tools/validate-train-timetable.py` | Standalone validate train timetable verification helper. |
| `tests/test_jp_history_coverage.py` | Test cases: explicit opening constraint explains predecessor boundary, identity predecessor survey boundaries are official boundaries, real compiled history accounts for every canonical event, event that emits nothing is a real coverage error, service validity takes precedence over legacy bounds, service periods replace legal retirement date and accept suffixes, temporal event can compile only to a current stamp, partition periods are checked per compiled half, suspended old alignment and later replacement have separate boundaries, unreviewed r |
| `tools/apple-maps-rail/audit_coverage.py` | Audit an Apple Maps capture plan against catalog areas and rail inventory. |
| `app/scripts/railway/tests/test_mid_south_station_splits.py:9` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_mid_south_station_splits.py:11` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_mid_south_station_splits.py:13` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_mid_south_station_splits.py:14` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_mid_south_station_splits.py:49` | Retired test_final_package_spans_are_reviewed_without_widening_bands for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_colour_brand_metadata.py:8` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_colour_brand_metadata.py:9` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_colour_brand_metadata.py:10` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_colour_brand_metadata.py:11` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_colour_brand_metadata.py:15` | Retired test_only_gtfs_or_exact_audited_override_sources_are_approved for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_colour_brand_metadata.py:31` | Retired test_mismatched_or_generated_colour_metadata_fails_closed for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_release_repairs.py:26` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_release_repairs.py:79` | Retired test_partial_line_provenance_is_checked_without_certifying_its_siblings for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_release_repairs.py:94` | Retired test_narn_coverage_warning_requires_recorded_survey_and_does_not_excuse_drift for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_release_repairs.py:120` | Retired test_audit_reports_stale_retained_feed_and_uncertified_feed for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_west_station_anchor_review.py:9` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_west_station_anchor_review.py:11` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_west_station_anchor_review.py:12` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_west_station_anchor_review.py:13` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_west_station_anchor_review.py:44` | Retired test_reviewed_span_is_a_note_but_larger_drift_still_warns for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_west_station_anchor_review.py:75` | Retired test_canada_exact_gtfs_station_ids_have_individual_limits for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_east_station_splits.py:11` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_east_station_splits.py:22` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_east_station_splits.py:94` | Retired test_exact_reviewed_complex_span_is_auditable_not_global for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_station_ids.py:10` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_station_ids.py:11` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_station_ids.py:12` | Retired audit module loader for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_station_ids.py:66` | Retired test_audit_finds_worst_pair_even_after_nearby_platform for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_station_ids.py:76` | Retired test_audit_preserves_reviewed_local_complex for the removed standalone audit; other production/builder regression cases remain. |
| `app/scripts/railway/tests/test_na_osm_tile_completion.py:113` | Retired OsmTileSelectionTests for the removed standalone audit; other production/builder regression cases remain. |

Planner regression tests remain; their retired coverage-audit cases checked
rectangle holes, continuous line coverage and city-scoped supplement resolution.

`ios/tools/capture-railway-hotspots.sh` was also retired: it launched a supplied
simulator app at the declared high-error railway viewpoints and saved screenshots
and metadata for manual review. Existing captures and the hotspot data remain.
