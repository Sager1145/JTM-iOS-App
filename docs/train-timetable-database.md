# JR historical timetable database

This implementation is an evidence-backed foundation, **not a completed six-JR
historical inventory**. Scope is 1912-06-15 through 2026-09-28. Coverage must be
read from `app/data/train-service-history/audits/train-timetable-coverage.json`;
neither a successful build nor 298 legacy patterns establishes completeness.

`perOperatorDailyEvidence` reports the distinct Japanese service dates on which
at least one represented planned trip has calendar evidence. Its compact date
ranges use `[validFrom, validUntil)`. Multiple trains on the same day increase
the occurrence count but count as one evidence date. These dates do not certify
a complete daily inventory or actual operation. `firstCoveredDate` and
`lastCoveredDate` now use actual calendar dates; the edition envelope remains
available as `firstTimetableEffectiveDate` and `lastCoveredUntil`.

## Fact ownership

`app/data/train-service-history/manifest.json` selects canonical JSONL inputs.
`schema.sql` defines the indexed SQLite artifact. Sources, normalized facts,
research candidates, derived outputs and audits are separate. A parser writes
candidates; a reviewed normalization step writes facts; validation precedes
building. SQLite and compatibility projections are generated, not independently
edited. Existing legacy data remains available until its replacement has
certified daily coverage.

The schema models operators, service generations and dated names, timetable
versions, trip templates, calendars and exceptions, historical holidays,
stop times and one-date overrides, number/operator/ordered-line segments,
split/join relations, field provenance and completeness, coverage declarations,
zero-service intervals, research tasks and actual operation events.

All validity intervals are `[from, until)`. Dates are Japanese service dates;
times are seconds since that service day's start. `24:12` is part of the
previous day's trip. Arrival and departure have separate optional day offsets,
falling back to the original shared `day_offset`. A stop can arrive at `23:42`
on day zero and depart at source clock `0:30` on day one. Dated overrides
inherit the corresponding side's offset unless they explicitly replace it. Actual disruption events do not overwrite the published
schedule. No source-listed pass mark is invented where a source omits it.

Station identities refer either to the shipped compact directory `sourceCode`
or to an existing historical overlay `history_id`. Current topology is not
proof of historical applicability. A source name by itself cannot establish a
verified station reference. The root seed normalizer selects the main Tokyo
group `003766`, distinct from the Keiyo group `003785`.

## Runtime and compatibility

`TrainTimetableDatabase` opens SQLite read-only and materializes a requested
day lazily. It does not decode a century's trip arrays at startup. Trip/date is
the occurrence identity; train number is not a global primary key. Queries
retain stop times, station identities, line/operator order and completeness.

Exact trips enter the existing route editor only with verified calendar,
operator, stops, route lines and station references. Reversing the stop list of
a scheduled train would create a fictitious timetable and is not offered for
exact trip rows. The legacy pattern picker retains its existing direction
behavior. Date changes retain user edits and disclose that the selected
occurrence requires resolution for the new date.

Historical-only stations are queryable but cannot yet be applied through the
legacy editor's current-station reference contract. This is a remaining
integration gap, not an alias to a modern same-name station.

The original 298 patterns and 221 branding identities are preserved. The
generated migration map accounts for every legacy ID. Signature matches are
research candidates; they cannot certify a decades-long validity interval.
The new projection is kept separate until sufficient verified facts exist.
This means the requested full replacement of the legacy source of truth is
still pending.

## Evidence seeds and research

`normalize-reviewed-timetable-seeds.py` promotes reviewed official candidates
for Kamui 93, Lilac 95, Shinano 1, Hitachi 26 and Yufuin no Mori 1–6.
Together with the reviewed Shiokaze, 2013 JR Central, Hokkaido summer and
WEST EXPRESS Ginga announcements, Azusa/Tokiwa date variants and
Ibusuki no Tamatebako summer dates they represent
95 templates and 1577 explicitly attested service-date occurrences;
these small samples do not establish any company’s complete daily inventory. The special Hokkaido trips exercise explicit dates and overnight
arrival; two JR East HTML tables exercise full passenger arrival/departure
times. Unknown internal numbers, intermediate times and routes stay unknown.
JR East calendar cells marked `ok` attest the displayed schedule; other cells
may contain different schedules and are excluded by the parser.

The JR East parser has a reduced official fixture with independently pinned
train number, selected times and stop count. It rejects ambiguous backward
clocks and non-limited-express classification. Original source pages/PDFs are
not republished in the bundle. The source registry records publisher, locator,
access date and extraction/redistribution limitations.

Public viewing is not a bulk-data redistribution grant. Operator portals using
licensed timetable providers are recorded as verification sources; missing
permission remains a source/license blocker. NDL catalog/guide records locate
historical issues but do not attest their unseen trip contents. Three archival sources support a conservative national zero-service interval
`[1944-05-01, 1949-09-01)`. Exact abolition/restoration days remain research tasks.
The 1912-06-15 first special-express identity is supported by the Railway Museum;
its original stop-by-stop timetable is not yet transcribed.

## Remaining completion gates

* Six-JR current inventory, all train numbers and exact operating calendars.
* Full timetable revision inventories and original evidence for 1987–2026.
* Ancestral service inventory and available original timetable transcription.
* Verified historical holiday years before holiday-dependent rule expansion.
* Ordered route/operator evidence and dated solver audits for every trip leg.
* Historical-only station application and split/join golden source cases.
* Fully migrated compatibility catalog and user-flow simulator regression.
* Authorization for redistribution of licensed timetable data where required.

The coverage report must leave every unproven company/year/dimension missing,
partial, source-gap or license-blocked. Database integrity tests use synthetic
fixtures to prove semantics; those fixtures are not production timetable facts.

## Reproduce

```sh
python3 ios/tools/rebuild-reviewed-train-timetable.py
python3 -m unittest discover -s ios/tools/tests -v
python3 ios/tools/test_jreast_trip_parser.py
```

The rebuild entry point runs reviewed normalizers in dependency order, then
validates, refreshes the source inventory, builds, checks the snapshot and regenerates audits. It does not fetch
new facts from the web. The reviewed normalizers are intentional input-generation steps, not automatic
web fact promotion. Source discovery currently indexes reviewed search results;
it does not claim exhaustive crawling or an all-services inventory.

## Timetable / historical-map alignment

The selected trip's Japanese **service date** is the historical-network date.
The map's journey-list date filter is a separate scope and must not replace it.
An arrival at `25:03` belongs to the original service-date occurrence; its civil
arrival date is the following day. Preserve both meanings instead of changing
the occurrence or silently applying today's network.

Station and rail-service validity use inclusive opening and exclusive ending
boundaries, `[valid_from, valid_until)`, like `RouteGraph.RailValidity`. A
`service` interval takes precedence over infrastructure existence. Infrastructure
may remain after passenger service ends. Timetable operating calendars are
independent evidence; an open line does not prove a train ran that day.

`verify-train-timetable-artifact.py` checks the canonical fingerprint, historical
network revision **and content hash**, current station-package hash, solver
version, Japan timezone, service-day semantics, scope dates, SQLite integrity,
and the bundled resource copy. It is also part of the Swift verification gate.
Rebuild after a historical network update; do not manually alter metadata to
make a stale artifact pass. A matching snapshot certifies compatibility of
inputs, not complete timetable coverage or the surveyed route of a train.

The editor now publishes its draft service date together with draft map pins,
including date-only edits and removing a date. Cancelling returns the map to
the saved selection. Exact timetable application preserves explicit line and
operator constraints per passenger-stop pair; pairs with hidden intermediate
junctions remain read-only because `RouteSection` cannot express ordered vias.

Native persistent route keys now include the history content hash. Bundled
precomputed routes must attest `history_hashes` as well as revision and solve
context when a historical overlay exists. Older parts lacking that attestation
are solved on demand. A separate history task refreshed the shared generator and 201 sample parts
in the current worktree. Their revisions, history hashes and solve contexts
were independently checked against 2026-09-28.1. These changes are not part of
the timetable commit. Do not add a hash to old geometry without rerunning its
solve against the attested snapshot.

## Direct route references and details

Line segments now carry `reference_kind`, `current_n02_line_id` and
`rail_history_id`. Historical references must identify an existing dated
feature; name matching alone cannot establish identity. Current N02 references
remain unverified without a credible package validity interval. A claimed
`route_lines=verified` blocks the build unless the entire ordered chain and
every actual operating date pass the direct-reference audit. Runtime rejects
older SQLite shapes missing these columns; rebuild the artifact.

Read-only trip details list source arrival/departure strings, explicitly mark
missing values, explain partial station lists, and expose deduplicated source
titles, publishers and URLs. Overnight civil dates are derived without changing
the original service date or clock string.

Latest evidence, counts and validation: [East/Kyushu and historical report](train-timetable-next-report.md).
