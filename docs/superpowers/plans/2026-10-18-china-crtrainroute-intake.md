# CRTrainRoute China data intake

**Goal:** Study CRTrainRoute and bring its China data into Railmap under the same provenance, coordinate and physical-topology requirements as existing regions.

**Architecture:** Preserve the pinned upstream JSON as the initial, explicitly non-runtime candidate inventory. Continue production work from the independently acquired Geofabrik China 2026-10-17 PBF, retaining original WGS84 node/way/relation identities, versions and member order. Official 12306 names/telecodes/pinyin and the MTR seven-station HSR sequence supplement that source; they do not convert every OSM membership/order into official evidence.

**Scope decision:** OSM geometry is eligible at the same fallback tier as Korea. Importing the upstream pickle, inferred island connections or proximity station assignments would violate existing requirements. No region selector is enabled until usable CN resources actually exist. This is a data-evidence constraint, not an approval gate.

## Initial candidate work and evidence

- [x] Pin and inspect upstream source; inspect Swift/JavaScript graph and resource counterparts.
- [x] Add the candidate importer and focused regression tests: preserve gaps/IDs/modes; separate HK/MO; keep station datum unresolved; never load pickle or merge aliases.
- [x] Import all 31 mainland GeoJSON files and the station directory into the source centre; retain exclusions and source provenance in the repository intake manifest.
- [x] Record comparative findings and exact production blockers in the source study and existing China source ledger.
- [x] Run only the focused importer tests and inspect imported records/counts. No native build is needed without runtime code changes.
- [x] Write the requested production CN runtime resources from the independently acquired original topology and official evidence; the supplied upstream processed graph remains a historical candidate.

The raw download is local-only by repository policy; the importer, source manifest, attribution and research report are reviewable repository artifacts. No commit, push, publication or app release is authorized by this work.

## Production continuation (user instruction, 2026-10-18)

The user explicitly requested completing production CN integration and obtaining
missing evidence. CN/HK/MO are disjoint railway data scopes: Hong Kong HSR,
including West Kowloon, belongs entirely to CN; Macau LRT, including Hengqin,
belongs entirely to MO; other Hong Kong rail stays HK. No cross-region graph
mixing or duplicate identities are introduced to implement that partition.

- [x] Download pinned Geofabrik China 2026-10-17 PBF; retain original WGS84 source topology.
- [x] Obtain current official 12306 national identity/pinyin table and official MTR seven-station HSR order, including Nanshabei rename evidence.
- [x] Extract original source nodes, ordered way node IDs and relation members/roles, preserving object versions, into `railway-sources/local/china/osm/china-261017-rail.sqlite3`; completed source/counts/crs metadata was inspected.
- [x] Build canonical compact CN network, station/section/name resources and coverage from evidenced source topology. Keep unproven intervals explicit; never fill gaps with chords.
- [x] Wire CN through native/Web region, clock, statistics, identities, datum presentation and resource builders.
- [x] Verify CN-only Shenzhen North–West Kowloon routing and disjoint HK/MO ownership; run focused existing tests and one necessary incremental build.

OSM is canonical WGS84 geometry; the freshly fetched 12306 table supplies names,
telecodes and pinyin only. Raw upstream 12306 coordinate guesses are never
promoted into canonical station coordinates, so no GCJ02 reverse approximation
is needed to construct this source model.

### Production evidence references and limits

- [Official identities, MTR station order and reviewed source records](../../reports/sources/china-production-evidence-20261018.md): seven HSR stations include XJA exclusively in CN; QSQ is Nanshabei from 2025-10-11. The original Overpass coordinate sample is dated 2026-07-28 and remains distinct from the production PBF date.
- [Source/algorithm study and current continuation](../../reports/sources/crtrainroute-study-20261018.md): historical intake counts remain initial-phase counts. Original PBF IDs/versions and actual graph continuity supply topology; no synthetic gap chords or cross-region sharing.
- [CN production package source record](../../../app/public/rail/cn-2025.sources.md) and [production source manifest](../../../railway-sources/china-production.json): 3,986 line/branch/path records, 17,515 intervals, 21,489 station memberships and 2,697 official telecodes. National completeness is not claimed.

OSM relation/track membership and order outside the official MTR corridor must
retain OSM provenance; matching a station name to 12306 does not make that line's
entire order official. Passenger service identity, physical topology and train
schedule are separate evidence. No current schedule is inferred from the official
static 2022 train-list file or failed 2026 station-query requests.

Borrowable upstream ideas remain CSR, dense query arrays and identity-preserving
degree-two compression with full geometry. Forced main-component snapping,
automatic island/ferry edges and proximity-only via stations are excluded. No
speed, memory or accuracy advantage has been measured in this continuation.
This documentation update was checked by focused source/text review; no tests or
builds were required for the prose changes.


### User-requested real-train differential batch (2026-10-18)

88 official published train numbers / 87 distinct internal services / 1,098 observed
calls are retained with original 12306 request/response references. The principal
subset excludes one alias and one incomplete stop list (86 complete services).
Original endpoint and consecutive-stop replays completed; original station input
coverage failures are separated from graph errors. Native Debug and bounded-cache partial evidence was retained and excluded from
final statistics. The isolated Release standard-cache run completed all176 entries
(active=false, phase=completed, evidenceReady at2026-10-18T22:11:30Z).
Among86 full unique services, endpoint complete candidates are73 original /12
Railmap; forced-stop complete candidates47 /12, legs717/971 /464/971.
This is returnability, not independent validation of actual track use or performance.
The manually invoked report and source index is
[the real-train ledger](../../reports/sources/china-real-train-paths-20261018/README.md).

Before this batch, source review fixed explicit foreign ownership leaks and twelve
closed-path station representations; CN physical junctions and SQL mirror were
rebuilt from the corrected original topology. Focused builder regressions, runtime
Swift/JavaScript cases and incremental native builds passed; nationwide completeness
is still not established. Independent comparison-method review found one CSV
absence/zero ambiguity, fixed with a focused regression: unperformed screens are
blank and referenced/unreferenced denominators are retained.


### Current serial resource state

2026-10-18: full88-train native comparison finished; isolated PID49830 is idle
with completed status. No CN build/test/native job active. Respect the Japan
chat's current Miyazu/candidate/main-build lease before new native work.
A source-only endpoint metadata fix is ready in RideRouteResolution and a narrow
malformed-cache rejection in RiddenRouteStore; focused resolution/inspection tests
and eight affected real-journey replays are pending the serial window.
The original full176 outputs remain immutable at
railway-sources/local/china/comparisons/real-trains-20261018/native-final-session/.

Read-only final review found two actual subway substitutions in D271/C293
Kunming to KunmingSouth. Source anchors/line IDs exist and source municipal identities
were correctly separate; generic500m runtime snapping ignored their ownership.
A bounded Swift/JavaScript source-anchor fix is being prepared. Because this affects
CN endpoint routing, final rerun must cover the original176 entries after one
focused test/build, rather than only eight metadata cases. Prior full-run counts
remain retained as pre-fix observations, never silently overwritten.

Source-anchor repair is ready (Swift/JS); eighteen focused JS cases passed.
Five new RecordedStationSourceAnchorTests plus existing resolution/inspection
filters are pending the next shared lease. The code binds declared source anchors
to their qualified original node/line; absent anchors stay unresolved. Same-name
expansion retains only explicit identity/group siblings for anchored coded stops.
CN-only source-anchor:1 solve cache keys prevent old CN snapped paths being reused;
other country cache keys/anchor-free behavior remain unchanged. No heavy job active.

Final independent source review found a Web preferred-institution fallback that
bypassed anchored identity filtering. A focused regression reproduced it; the
fallback now returns anchored pools before legacy widening. Fresh Web evidence:
19/19 web-physical-junctions tests passed. Independent rereview reports no remaining
blocking finding; that review was source-only, not a native runtime pass.
Swift/JS CN/cn cache suffixes now agree. Heavy/native validation still waits for
the Japan chat's explicit shared-window release (coordination authorized by its
human user reply and verified in read_thread; no generic app launch performed).

2026-10-18T22:33Z: exact-argument identity of idle comparison PID49830 was
rechecked, then only that completed isolated process received SIGTERM to release
retained graph memory before its next build/replay. Immutable176 result files
remain preserved. Other chat's Debug/Main processes were not operated. Still no
CN heavy job; awaiting explicit lease release.

Shared heavy/native window explicitly released by Japan owner after its completed
four-case Main review; acquiring it now for focused RailKit filters, one arm64
Release diagnostic build, and original176 source-anchor replays. No inputs/data
will change during the native replay. Other owner's direct dispatch, singleton,
process/invocation provenance and viewpoint-ID implementation remain preserved.

Focused Swift run completed:36 tests in4 selected suites passed (nonzero test
count), log /private/tmp/railmap-cn-source-anchor-swift-tests.log. Includes recorded
source anchors, existing station parity, resolution and batch inspection. One
arm64-only Release diagnostic incremental build now active; log
/private/tmp/railmap-cn-source-anchor-release-build.log. No other heavy job.

Arm64-only Release BUILD SUCCEEDED. A new unique source-anchor comparison app was
copied and ad-hoc resigned; compiled UUIDs preserved. Seven CN runtime inputs,
CN display.bin/stations, and all physical junction bytes equal the pre-fix run.
CN asset revision is now5b2ec16d... because shared JP display manifest/input hashes
changed; CN-filtered package/line/region manifest identities are unchanged. Full
context is native-source-anchor-execution-context.json in the real-train ledger.
Launched only the unique app via open -a (no -n), request
/private/tmp/railmap-cn-real-trains-20261018/source-anchor-request.json, standard
cache mode, original unchanged176 input journeys. This is the only heavy job.

### SERIAL WINDOW RELEASE - original176 replay completed

2026-10-18T22:57:35Z native result:active=false,evidenceReady,phase=completed,
176/176 rows,0 structure failures/686 reviews. Full output preserved separately in
native-source-anchor-final-session. Only own idle PID59794 was stopped after exact
argument identity and completed-state checks; all source outputs retained. No CN
build/test/native/solve/capture job remains. Shared heavy/native window returned
to Japan owner; remaining work here is light JSON analysis/documentation only.

### Final real-train result and scope note

Both engines completed88 public numbers x2 modes; native source-anchor repair then
completed the original176 again. Current primary86 full unique services:complete
original73/86 endpoint and47/86 forced; native12/86 both. Comparable forced returned
geometry sections:original717/971 vsnative505/971, with40 native physical gap
entries. All88:original756/1010 vsnative522/1010 geometry,41native gaps. Native
reported481 must not be interpreted as481 comparable API ok legs; its original
525geometry−45gap-bearing sections=480 changes to522−41=481, geometry actually−3.
The existing report generator now separates these fields;7 light metric regressions
pass and currentCSV176rows/21columns matchJSON. No engine rerun was needed for
this reporting-only correction. Historical comparison snapshots remain intact.

Actual known-failure replay:71/71 prior malformed sites still emitgeometry,
142/142 endpoint name/code identities match bundled stations and staymatchedGeometry
without interval proof. Two Kunming metro substitutions are now unresolved; all
new source geometry has0matches against that metro's original5-decimal edges.
91 selected line/branch IDs=54highspeed+37conventional. G101 remains3/4 and retains
all23reviewed Harbin nodes in order. G6045 official first4legs remain4/4 onlyCN-GSH.
Independent actual-output review confirmed these facts and all12 G1 forced endpoint
anchors against source node coordinates/versions. G1 interior sequences remain but
station-end vertices change; no byte-identical-geometry claim afteranchor repair.

Final report:docs/reports/sources/china-real-train-paths-20261018/README.md.
Current raw source-anchor session and pre-fix full session remain separate;
0structure failures/686reviews is not national path acceptance. Remaining work
includes inland connectivity, station/track evidence, actual train-ferry geometry,
and unresolved interval identities. No overall speed/memory/accuracy superiority,
nationwide completeness, actual movement or pixel-alignment claim. No commit/push.


### 2026-10-19 — evidence-only continuation / serial window

User requested further repairs and another large real-train comparison. After explicit release from the Japan audit chat, this chat holds the single heavy/native window. Work is limited to source-qualified station binding repairs, affected original relation paths, derived junction/resource rebuilds and the same frozen 176 real-train inputs. 京沈 and 昆明 cross-corridor paths remain withheld where identity/passenger ownership evidence is insufficient. No speculative bridges or anchor policy relaxation.


### 2026-10-19 — completed evidence repair / window returned

Published five restored source paths plus ENM interval split; original3,388 directed ENM-corridor edge/way triples unchanged. Four scoped station bindings and one184.673m original passenger_lines=2 edge retained strict ownership/adjacency. Forty focused builder tests passed; all3,991 published paths validated during junction build; four ambiguous endpoints withheld;203 peer junction rows identical. Derived CN database counts3991/17594/21573 match package. Single Release arm64 build succeeded. Same frozen176 inputs completed2026-10-19T06:04:24Z with CN-only dependency264ab67d…; source compilation UUID unchanged. Native0 structural failures/701 reviews, forced geometry522→538/1010, full candidates12→13/88, gaps41 unchanged. All534 shared geometry parts identical, no lost request sections. Original baseline dependencies verified unchanged and reused. Exact completed PID91341 stopped, focused process check empty, heavy/native window explicitly returned to Japan audit chat. Remaining 京沈/KMM-KOM/GuangzhouSouth-Jiangmen/ferry gaps are explicit. Owning report: docs/reports/sources/china-real-train-paths-20261018/README.md; topology-repair-result-review.json records exact deltas.


### 2026-10-19 — three connector physical integration

After explicit Japan-chat window release, integrated five stationless original physical paths (348 adjacent edges, four new track identities) via the existing shared N02 contract. Compact passenger catalog and station anchors unchanged. 3697 same-original-node junctions plus two retained reviewed lead-ins; all203 peer rows identical. No GZS cross-platform switch-reversal route admitted. Kunming crossover operating agency is a reviewed inference, not an original operator tag or legal ownership claim. Builder validates manifest before writing base outputs; focused tests16 physical-junction plus26 package pass. Release build and same frozen176 native replay pending.


### 2026-10-19 — final three-connector integration and window returned

The earlier five-path/pending entry is superseded by six stationless physical paths, 378 node entries/372 original adjacent edges, four added physical identities, 3699 same-node junctions plus two retained reviewed lead-ins. Compact passenger records and station anchors remain unchanged. Nine new joins share exact original nodes; 203 peer rows were preserved at publication. Guangzhou South and Shenyang North unproven platform boundaries remain withheld; Kunming crossover agency remains explicitly a reviewed inference.

Observed source_id identity pollution, nearby metro display substitution, and stale CN display cache were corrected using source_review_id provenance, actual source-identity guards in Swift/JS, and a CN-only source-display cache epoch. No graph/anchor/cost relaxation or cache deletion. Focused Python16+26, Swift16+1, JS6+19 tests passed; final Release build succeeded. Same frozen176 inputs completed2026-10-19T07:44:15Z with CN revisioncdd58c633a33a8f246de14ae638895f1b7b4bc5c865ce5fdb6529351c7a6af23 and UUIDB8FD2EEC-47F0-3FB3-AE63-7370C4FC356A. Final complete candidates13→14/88, forced geometry538→542/1010, internal497→499, physical gaps41→43; original baseline remains49/88 and756/1010. C293 is complete; G101/G6045 now have all leg geometry but retain SBT/GZS boundary gaps. Independent review confirmed551 old source-coordinate parts identical, zero lost, zero metro7909742 selection;12 unsupported display assignments withdrawn without changing geometry. Final0 structure failures/704 review entries does not certify national completeness. Exact own completed PID7759 stopped and serial heavy/native window returned. Current report and evidence: docs/reports/sources/china-real-train-paths-20261018/README.md. No commit/push, overall superiority, unique actual track or performance claim.


### 2026-10-19 — GZS/SBT boundary and D271 continuation

User requested strict source evidence for GuangzhouSouth and ShenyangNorth platform boundaries, D271 remaining seven intervals, formal repairs followed by same88x2 replay against unchanged original repository. Three bounded source-only tasks inspect pinned original SQLite and primary documents; no production source relaxation or invented junction. Current native/heavy window belongs to Japan audit chat; no build/native starts until explicit release. Prior176 result14/88 and542/1010 remains baseline for this continuation. Source review distinguishes absent original topology, incomplete source attributes and omitted published original paths. No commit/push.


### 2026-10-19 — boundary/D271 final integration, replay and window returned

Formally added8owned original physical paths/2042adjacentedgeentries, bringing supplement to14paths/2428nodeentries/2414edges and rawsections17608. Added3genuine own-route original stationbindings CNW/PSW/XCE (one newruntimeofficialidentityPSW); all21573oldrawstationfeatures unchanged, compact3991/17594/21573 andrail.db unchanged. Existing1500mownrouteprojection bound unchanged; markers direct originalrelationmembers, exact officialcode/name/source, nodeversions/WGS84 and originalanchorpath validated. New helper/CLI/defaultbuilder wiring focusedtests21 pass; actualJS sourceidentity query3/3. No Swift/JS routing change.19initial+1GPMnew same-nodejunctions yield3719exact+2retainedreviewedCN;203peerrows identical atpublication. GPM619166034v14 ownpassengerprefix3edges is formally restored; sourcefragment/sourceidentity evidence retained.

Final176 samefrozeninput67dd98c… completed2026-10-19T08:50:40Z, CN-only0f6ce85ec6d41ecc9db431a31d8ae04ac907bf89cefb2c5ac86943f9455ce2d6, compiledB8FD2EEC UUID unchanged, standarddiagnosticcache/productbounded100000unchanged. Defaultunneededdualarchbuild interrupted75, correctedarm64incremental succeeds; laterGPMpuredataasset+existingrevisionupdate reusedcompiledbinary. Finalall88 forcedgeometry542→552/1010, internal499→507, gaps43→45, complete14unchanged; main86 geometry525→535/971,internal483→491,gaps42→44. D27114/14geometry13resolvedonePNEboundary; original9/14. D2396/7geometry5resolved,PNEboundary+ChuXiong-LiJiangmissing; original3/7. G101/G6045 originalSBT/GZS boundaries remain. ExpandedSBT519.930km own306handoffto704+75.223km hitsunownedway1067140203; no newevidencecontractor gaprelocation admitted. GZS6sidingsmissingownership/operator remainwithheld.

Final0structfail/714reviews; original176resultfields exactly unchanged,7baselinefilehashesmatch. Independentoutputreview176unique,556→566parts,10added,0lost,554exactunchanged,2oldpartsretainfullcoordinate suffix (D239duplicateoriginal-nodepoint; D271GPMprefix).93selectedIDs unchanged/no7909742; HKfirst4G6045entireparts unchanged, CN-onlyHSR/MOownership retained. ExactcompletedPID18257 stopped,focusedps empty; heavy/nativewindowexplicitlyreturned toJapanchat. OnlylightJSON/docs afterhandoff. Owningreport docs/reports/sources/china-real-train-paths-20261018/README.md. No nationalcompletion/exactactualtrack/overall superiority/pixel/performance claim, no commit/push.


### 2026-10-19 — evidence continuation stopped at overhaul handoff

User changed focus to documenting all completed/incomplete work and preparing the data-structure overhaul. Published resources remain14physical paths/2414edges, final176 replay08:50:40Z, CN0f6ce85e…, complete14/88, forcedgeometry552/1010/internal507/gaps45. No new production candidate build, asset install, database update, native solve or176 rerun this continuation.

Source-only continuation found exactPNE15edge1486.71m chain including omittedoriginalway742037844v20 with directname/ref/operator; retainedGZS/SBT/D239missingagency/passenger limits. Two builder/test files add explicit opt-in original-way-identity ownership,24focusedtests pass. NOT publicationready: officialpassengercontext→directwayname/ref linkage and directmodepassengernegativecoverage incomplete. Productionmanifestdoesnotenablethismode. ProposedPNErow and4originalreferencepaths/7cameras saved under docs/reports/sources/china-real-train-paths-20261018/overhaul-preparation4/.

InspectormanualCNcamerapositiononly; noimport/export/screenshotreview orpixelclaim. ExistingautoalignmentJP-only; metadataJPintervalcannotcertifyCN. OwnisolatedappquitCommandQ,focusedpsempty; native/heavywindowexplicitlyreturnedtoJapanowningchat. New comprehensive handoff docs/reports/sources/china-real-train-paths-20261018/overhaul-handoff-20261019.md maps study/production/results/remainingtargets/sourceartifacts/runtimeparity/cache/persistence/migrationconstraints into existingProposedADR0013. No identityregistry/dataoverhaul implemented, no commit/push.
