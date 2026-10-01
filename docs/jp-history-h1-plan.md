# Japan temporal railway database: Phase H1

Scope: passenger railways from 1993-04-01 to the present, with exact service
dates where primary evidence establishes them. Runtime remains rail-history v1;
the source database and compiler own historical event semantics. Existing
RailCore, Dijkstra, presentation and statistics architecture is retained.

## Delivery sequence and acceptance

| Workstream | Deliverable | Acceptance |
| --- | --- | --- |
| Official dates | Full MLIT opening/closure inventory, repeatable import, source URLs | Every source row retained; exact dates distinguished from snapshot years |
| Source model | Stable corridor/alignment/service/station identities, before/after identity, evidence and review | Invalid/overlapping periods, imprecise solver dates and unreviewed new source events rejected |
| Compiler | Multiple service periods and identity/name changes compiled to v1 | Current baseline cannot leak through suspension; stations and sections dated together |
| Early geometry | Inventory 1996 and later N02 releases | Dataset fields, CRS and licence verified before use; missing geometry stays unresolved |
| Same corridor | Explicit identity selection independent of distance | Reviewed old identity is retained even within 40 m of present track |
| Events | Openings, transfers, names, station changes, suspensions and resumptions | Exact interval selectors and primary evidence; no whole-line stamp for a partial opening |
| Discovery | Snapshot inventory, geometry/identity/station diff, official evidence matcher | Candidates remain a review queue; snapshot year never becomes an exact day |
| Acceptance | Generated coverage report and transition fixtures | Unmatched events visible; strict H1 gate rejects all unresolved coverage |
| Integration | Rebuild overlay; test Web and Swift history consumers | Same v1 package consumed by both clients; actual route checks distinguished from availability checks |
| Documentation | Source strategy, reproducible commands and residual ledger | Coverage counts derived from artifacts, no claims of nationwide completion from samples |

## Data rules

- Service dates and infrastructure dates are independent half-open intervals.
- A service timeline may have several disjoint periods; each compiles to a
  temporal variant. An undated ride retains the runtime's existing behavior.
- A historical identity is not deduplicated because its geometry overlaps
  another railway. Geometry differences discover candidates; evidence defines
  the event.
- A source event must identify its geometry and stations, date precision,
  evidence and review state. A source list entry is not a verified route.
- 1993–1996 geometry unavailable from compatible sources is a coverage gap.
  N02-1996 cannot establish the earlier geometry by assumption.
- N05 remains conditional: do not ship its geometry or derivatives without
  applicable redistribution/commercial permission. Year-only dates are leads.
- Existing curated legacy events remain accepted inputs but their evidence and
  missing temporal dimensions must be exposed in coverage reports.

## Gates

The normal CI gate checks source/overlay integrity and regression fixtures for
shipped events. The strict milestone gate additionally requires every official
inventory event to be verified or explicitly not applicable. It must fail while
the nationwide inventory remains unresolved; passing the normal gate does not
claim Phase H1 is complete.

## Initial findings

Baseline HEAD: `049bb1e8`. Local N02 snapshots 2005–2008 and 2011–2024 are
available in the older Web checkout. The initial canonical ledger has 34 events
and one current-package retirement; no opening, transfer, station-change or
explicit suspension/resumption events. Runtime statistics already account for
temporal variants; the previous rail-history documentation is stale.

The working tree contains unrelated train-timetable changes. This work does not
take ownership of those changes.

## Implemented delivery (2026-09-28)

All engineering workstreams above now have implementations. The canonical source
contains 106 events and one explicit current-package retirement. It compiles to
runtime v1 revision `2026-09-28.3`: 956 historical sections, 494 historical station
memberships and 124 retirement selectors. The additions include 30 reviewed
whole-identity openings, eleven station-name memberships, operator transfers/renames, station
opening/closure and corrected disaster suspension periods. Stable section history
IDs preserve line statistics across segment and service-period variants.

The additions also include six further operator transfers and three later
station openings, with separate selectors for the two IR transfer phases.

The source compiler rejects unsupported precision, missing evidence/review,
overlapping periods and ambiguous partial-line selectors. Both station indexes
retain service-period variants before date filtering. Production Web boot preserves
current stamped station memberships; display compilation honors section/station
targets and uses measured solver geometry for the current Rumoi closure absent
from its display baseline.

Opening route fixtures pin N02 station memberships instead of accepting a
different line in the same station group. A pinned route must traverse physical
rail; station-transfer connectors alone cannot stand in for an unopened line.

Discovery now covers 19 N02 releases (2005–2008 and 2011–2025), with declared
native CRS and source/licence provenance. The 18 adjacent comparisons contain
72,343 unverified candidates. The station entity artifact contains 9,393 entities
and 10,618 memberships; 321 entities remain provisional geometry identities.
These are discovery outputs, not evidence of exact historical opening dates.

Acceptance artifacts:

- `app/data/generated/jp-history-coverage-report.json`: canonical compilation
  passes; 80 of 217 official inventory/identity rows link to canonical events,
  with 137 unlinked rows. In total, 138 official rows still carry unresolved
  source selectors or review status, including rows linked to shipped events.
- `app/data/generated/jp-history-boundary-report.json`: production loader checks
  2,713 transitions across 2,622 features and 85 dates, including 1,172 interval
  intersections and all 124 retirement selectors.
- `port-fixtures/historical-routes.json`: independently computed Web/precompute
  fixtures cover 93 routes and five pinned dates, including all 30
  whole-identity openings, ten partial openings with ten shared-station controls,
  eight later station openings, both identities for eight transfers, ten dated
  rename routes, Wakinoda relocation/rename and Sassho’s service end; consumed by Swift parity tests.
- The iOS package copy includes all 124 retirement selectors. Display history
  matches 123 directly and uses solver geometry for the remaining Rumoi event;
  no event has incomplete display coverage.

## Remaining data work and completion criterion

H1 nationwide completion still has 138 official rows with unresolved review or
selector status. Of these, 137 inventory rows have no canonical event link.
Annual geometry candidates and older station
identities still need review, alongside unresolved
1996 redistribution terms. The 1993–1996 network cannot be reconstructed by simply
backdating the 1996 snapshot. Legal closure dates also do not establish the last
service day, infrastructure removal or reconstruction date.

For each remaining official row: obtain primary date evidence; identify the
surveyed section and station scope; record separate service/infrastructure periods
and identity changes; review redistribution terms; compile and run loader,
route/display and mileage acceptance. Continue until the strict official-inventory
gate passes with zero unresolved events. Normal CI deliberately accepts the one
declared early-geometry gap and does not certify nationwide completion.

The strict inventory gate is necessary, not sufficient for H1 completion. Each
railway also needs reviewed historical geometry, service and infrastructure
intervals, station/name/operator/line identity timelines, and actual route
regressions at its boundaries. Annual candidates and unknown station identities
remain review work even after an official opening or closure row is linked.

## Final validation

Revision `2026-09-28.1` passes 2,619 production loader boundary checks, all
766 railway Python tests, 16 coverage-audit tests and 80 Web tests. The
canonical baseline gate passes with the one declared early-geometry gap.
The strict official-inventory gate remains incomplete.

All 201 sample routes solve under this overlay. The native precompute gate
accepts their rebuilt contexts using the exact overlay SHA-256; the iOS bundle
contains byte-identical copies of all 201 parts, their manifest and the overlay.
Display history covers all 99 retirement selectors (98 direct matches and one
solver-geometry fallback), with no incomplete event.

The timetable SQLite artifact and its RailCore resource copy were rebuilt from
the canonical timetable inputs. Snapshot verification reports
`snapshotAligned: true` against this overlay; database SHA-256 is
`f5400f2a84f48ab0556017f594dd4c05f9dec948d156452150632a9227a4513a`.
The separate history-alignment audit still reports 10 unverified trains and zero
verified alignments; synchronized artifacts do not establish missing route evidence.

The regenerated fixture contains 62 independently computed Web/precompute
routes, 62 date boundaries and four pinned dates. Boundaries include 47
unavailable-to-available changes, 14 available-to-unavailable changes and the
Wakinoda relocation with both sides available. Its measured route changes from
3,272.57 m on 2014-10-18 to 3,304.80 m on 2014-10-19, with different surveyed
path digests. All fixture contexts use revision `2026-09-28.1`.

Swift acceptance passes all 25 `RailHistoryPackageTests`, including 128 native
before/at/pinned route checks. Availability matches the dual-solver fixture;
successful-route mileage differs by less than 0.1 m, and both surveyed Wakinoda
path digests match exactly. The 25 statistics tests and two bundled-precompute
provenance tests also pass (52 related Swift tests in total).

The final working-tree whitespace check passes. These results establish the
shipped events and generated artifacts; the remaining official inventory and
older geometry gaps keep nationwide H1 incomplete.

## Previous batch (2026-09-27): reviewed transfers and source-row reconciliation

The next data batch adds six operator transfers: North Shinano, Nihonkai Hisui,
Ainokaze Toyama and IR Kurikara–Kanazawa (2015), plus Hapi-line Fukui and IR
Kanazawa–Daishoji (2024). The two IR phases select disjoint surveyed sections
and current station memberships. Current IR Kanazawa starts in 2015; its shared
JR predecessor stays available until 2024. The N02-14 and N02-23 predecessor
station and platform geometries are coordinate-exact, so the shared membership
is explicitly reused without duplicating its features.

Three separate station openings prevent current-only stations from being
backdated to the 2015 transfers: Takaoka Yabunami (2018-03-17), Echigo Oshiage
Hisui Kaigan (2021-03-13), and Shin Toyamaguchi (2022-03-12). Nishimattō opened
with the IR 2024 extension and is included only on that side of its boundary.

A separate review ledger reconciles 37 official rows (30 openings, seven
closures) with reviewed canonical events. PDF imports replay these explicit
decisions; source-cell fingerprints stay unchanged. Ordinary links alone do
not promote a row to reviewed status.

This batch raises the canonical event count to 85 and the runtime overlay to
918 historical section features, 472 station features and 92 current-feature
stamps, revision `2026-09-27.2`. Loader acceptance covers 2,502 transitions,
2,453 features, 68 effective dates and 1,063 interval intersections. That revision
passed 53 dual-solver route fixtures, 50 Swift history/statistics tests and all
201 precompute samples. Nationwide H1 remains incomplete.


## Follow-up: Myoko relocation and later station openings

This batch adds the 妙高はねうまライン operator transfer (2015-03-14) with two
surveyed predecessor periods: N02-13 until 2014-10-19, and N02-14 from that
relocation date until transfer. Both stations are called 脇野田 before the
transfer; the successor is 上越妙高. Each period selects 19 sections and eight
stations. The shared 妙高高原 JR membership comes from North Shinano; the
continuing current JR 直江津 membership remains available on both sides of the
transfer. Neither shared platform is duplicated by the new event. The first
predecessor period has an unknown earlier bound: N02-13 does not establish
older station locations, including 春日山 before its reported 2002 relocation.
That earlier station-geometry gap remains in the review ledger; this batch's
route acceptance covers the 2014 relocation and 2015 transfer.

The compiler validates each period's evidence, licence, alignment, identity and
selectors, and requires contiguous coverage of the predecessor service interval.
Existing station history IDs remain unchanged. Surveyed station variants retain
stable geometry lineage with distinct period suffixes.

Five separate station openings date テクノさかき (1999-04-01), 屋代高校前
(2001-03-22), 信濃国分寺 (2002-03-29), 千曲 (2009-03-14) and IGR 青山
(2006-03-18). Earliest post-opening N02 observations agree with their unique
current geometry. 巣子 is withheld: its opening-era snapshot contains a paired
platform geometry that the current package does not preserve.

Four identity seeds were corrected from promotion-ready to source-only review:
1997 Shinano, 2002 IGR, and the 2001 Nishitetsu line/station renames. Current
whole-line selectors backdate later stations or measured alignments. The
Nishitetsu station geometry is reviewed, but its predecessor 大牟田線 has no
corresponding graph edges, so a hard-constrained historical route cannot solve;
line and station must be promoted together. These corrections explain the
increase in unresolved source-review counts; exact official dates remain retained.

The annual review builder now reads extra snapshots from their actual input
locations, including the 2025 archive outside the historical archive directory.
Snapshot provenance still records portable relative/basename paths.

## Follow-up batch: partial openings, 2019 names and actual service end

Revision `2026-09-28.2` adds five reviewed partial openings and five station-name
memberships, bringing the canonical ledger to 101 events. Complete section bboxes
and explicit new-station allow-lists retain the earlier service of shared boundary
platforms. The Osaka Monorail opening uses an explicit identity dependency: ten
sections and five stations in its old-operator variant begin on 1997-08-22.

The 2019 Hankyu/Hanshin rename records distinguish line memberships, including
two surveyed Kobe-line platform features. Dated name-only queries constrained to
that line and operator cannot substitute Osaka Metro’s remaining 梅田 membership
after the rename. Current shared platforms and fixed station codes retain their
existing resolution behavior.

Sassho passenger service ends on 2020-04-18 after the final train on 2020-04-17;
its infrastructure interval ends on the legal closure date, 2020-05-07. Twenty
closure rows received explicit identity/geometry review. Together with the five
partial openings, the replayable source ledger contains 62 verified official rows.
Nose’s conflicting legal/table dates, the 27.21 km Nemuro geometry difference,
withheld Osaka selectors and unrepresented Hankyu Kyoto-line 梅田 membership
remain documented gaps. No missing geometry or earlier service date is inferred.

Integration also exposed two coded 京とれいん routes whose current names were
being applied before the 2019 rename. Both solvers now recover the date-valid
same-code alias only when the written name is known to that code and its ordinary
candidates are unavailable. Wrong-code fallback and undated resolution remain
unchanged. This is distinct from the constrained name-only namesake guard.

The final batch passes 790 railway Python tests, 17 coverage tests, 84 Web tests
and lint. The production loader checks 2,668 effective transitions across 2,577
features and 80 dates. All 83 route fixtures were recomputed through the Web and
offline solvers independently; their 83 boundaries and five pinned dates yield
171 native boundary/date checks, covered by 25 passing history tests. All fixture
contexts use solver version 24 and history revision `2026-09-28.2`.

All 201 sample routes were recomputed after the endpoint fixes and solve; 201
parts, the manifest and the overlay remain byte-identical to the iOS bundle.
Display coverage has 113 direct matches, one known Rumoi geometry fallback and
no incomplete rule. The timetable task owns its rebuilt SQLite and audits, bound
to the same frozen overlay hash; those artifacts do not certify full historical
JR route applicability.

Final native acceptance also passes all 298 parameterized train-pattern routes,
20 statistics parity tests, five temporal edge-statistics tests, 14 rail-validity
tests, five dated endpoint-name tests and two sample-bundle provenance tests.
The train-pattern reference check accepts a historical name only with an exact
station code, surveyed geometry, line/operator identity and certified current
geometry lineage; date-valid membership filtering remains enforced. The frozen
overlay SHA-256 is
`3fb48e1bbc413af1fcb533ca23eb13e6d9bbcc9c40d6c1d2976210abee8a93f6`.
This batch completes its implementation and validation, while the national H1
inventory still has 143 unresolved official rows and 142 unlinked rows.


## Follow-up batch: Kyoto, Sapporo and Nagoya extensions

Revision `2026-09-28.3` adds five partial openings: Kyoto Karasuma 北山—国際会館
(1997-06-03), Kyoto Tozai 二条—太秦天神川 (2008-01-16), Sapporo Tozai
琴似—宮の沢 (1999-02-25), Sapporo Toho 豊水すすきの—福住 (1994-10-14),
and Nagoya Sakuradori 野並—徳重 (2011-03-27). The new selectors cover 30
complete section features and 15 new station memberships. Five existing-track
controls preserve service at the shared boundary stations before and after each
extension. The canonical source contains 106 events, ten reviewed partial
openings and 67 replayable MLIT row reviews.

The N02-08 Kyoto extension survey labels 西大路御池 as 西大路池 and splits its
platform differently. Its continuous alignment is independently checked against
N02-11, which matches the current geometry exactly; the source anomaly is not
converted into a historical station rename. All snapshot years remain alignment
observations rather than evidence of an exact opening day.

Nagoya's 1994 今池—野並 opening remains withheld. Its 瑞穂運動場 station became
瑞穂運動場西 on 2004-10-06; the available pre-rename 1996 geometry is coarse
and has unresolved legacy redistribution terms. An explicit historical name and
geometry lineage is required before promoting that opening. The 2011 extension
uses unchanged station identities and retains 鶴里—野並 as an existing-track
control, without treating the withheld event as implemented.

Display acceptance for the 28.3 batch covers all 124 rules: 123 direct matches
and the existing Rumoi solver-geometry fallback, with zero incomplete rules.
The five new events add exactly ten rules and 15 station stamps; total display
station stamps are 392. Native statistics pass all 20 parity and five temporal
edge-statistics tests. Railway Python tests pass 791 cases and the coverage
suite passes 17 cases.

The refreshed Web suite passes 84 tests and lint. All 201 sample trains were
actually solved again against 28.3 (465 seconds), with zero unsolvable or
route-less trains; their contexts use solver version 24. The normal canonical
coverage gate reports zero errors and the one declared early-geometry gap.
Official inventory diagnostics retain 138 unresolved rows and 137 unlinked rows
out of 217, with 80 explicit reviewed canonical links.

The iOS resource copy passes exact byte comparison for all 203 history-dependent
objects (201 parts, manifest and overlay), and both native sample-provenance
tests pass. The 28.3 overlay SHA-256 is
`c6feed755ece7a664434592e0b910386493611e62b4d82b5e5aede98c3e99cb3`;
the sample manifest SHA-256 is
`65dd06c2a4e523e7bf3676c824fd1dcc4d4e1f3916f9c3c8405543a281354b13`.

An early production-code dual-solver probe passes all ten new opening/control
cases and their 20 before/at boundary outcomes. Each opening is unavailable
before its official date and solves on that date; all five existing-track
controls solve on both dates with identical physical lengths. This separately
checks the new selectors before the complete historical-route regression.

All 298 parameterized native train-pattern routes pass, with zero failed legs
(803.011 seconds for the parameterized route test; six tests in the complete
TrainServicePatternRouteTests suite pass in 909.835 seconds).

The complete historical-route fixture was regenerated through both production
solvers and passes all 93 route cases, 93 before/at event boundaries and five
pinned dates. All 284 emitted answers carry solver version 24 and history
revision 28.3; the 191 boundary/pinned answers provide the final native
date-and-distance comparison inputs.

Final native acceptance passes all 25 RailHistoryPackageTests in 415.272 seconds,
including all 191 generated boundary/pinned comparisons. Solve outcomes match
Web for every answer, and every solved route differs in physical length by less
than 0.1 metre. This completes implementation and validation of batch 28.3;
the national H1 inventory still retains 138 unresolved official rows and 137
unlinked rows, including the withheld 1994 Nagoya opening described above.
