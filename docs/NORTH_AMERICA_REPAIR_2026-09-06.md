# North America repair — 2026-09-06

This repair addresses the pasted North America repair board against the current
checkout. The starting packages contained 357 US and 83 Canadian lines, rather
than the board's historical 423 total. Existing iOS work and unrelated railway
data changes were retained.

## Implemented

- Rebuilt Houston METRO, NCTD and SEPTA using the existing reviewed station
  identity groups. Removed `houston-metro-700-b1`,
  `north-county-transit-distric-498-b1`, `septa-m1-b1` and `septa-m1-b2`, which
  duplicated their trunks.
- Rebuilt GO Transit, Ottawa and UP Express against the current normalized
  official networks, replacing ten outdated source digests.
- Rebuilt Amtrak candidates, then merged only Crescent, Southwest Chief and
  Lincoln Service from NARN. Empire Builder already used the reviewed official
  NTAD network in the starting checkout and was retained. Intervals exceeding
  the existing display tolerances remain withheld. The whole-feed candidate
  was rejected after new reversal/overlap warnings and a Pennsylvanian shared
  corridor failure; unrelated Amtrak geometry remains unchanged.
- Added reviewed official colour citations for 16 OSM relations. Explicit
  GTFS route identities resolve STM's missing operator tags and fold REM's
  opposite directions into two route candidates.
- Moved OSM duplicate suppression after the complete feed publication gate.
  Kenosha's rejected GTFS candidate can no longer suppress its OSM fallback.
  An operator with one published railway can still contribute another railway.
- Fixed OSM station parsing: proximity within 400 metres no longer merges
  differently named stops. WVU retains Towers and Engineering separately and
  now has all five stations. Its existing feed grouping reduces the twenty
  origin–destination routes to one physical system.
- Scoped feed merges now filter stations and sections as well as lines.
  Full replacement removes obsolete station aliases owned by that feed;
  unrelated feeds retain their records.
- Added cooperative reader/writer locks around package and solver-data
  operations, with inherited locks for child audits. Isolated builds use
  unique temporary cache filenames.
- Builds record SHA-256 input manifests and their actual generation time,
  invalidate caches when code/source/options change, and reject publication
  when the recorded inputs change during a build. Scoped merges retain
  provenance per feed, or per line for partial feed replacement; untouched
  legacy lines receive no fresh certificate. Partial replacement also checks
  each station feature's line name, retaining sibling routes' rows at a shared
  station.

NARN is a primary government survey. Missing independent OSM coverage is now a
warning only when a NARN-built line records the survey inputs, whose hashes are
checked separately. Measured deviations still use the unchanged error/display
gates. This is not evidence that every point matches the basemap.

## Candidates deliberately not promoted

The detailed candidate build and decisions are recorded in
[the candidate report](NORTH_AMERICA_REPAIR_CANDIDATES_2026-09-06.json).

- Kenosha, WVU PRT, Milwaukee Hop and STM Yellow: every candidate interval
  exceeds the independent alignment gate. Correct colour or station identity
  does not make that geometry publishable.
- STM Green/Orange/Blue and QLINE: detected station-to-station chords remain.
- San Diego Silver Line: the attempted routing contains an implausible detour.
- REM and PATH Newark–WTC: only part of each candidate passes the alignment
  checks; the candidates remain outside the shipped packages pending the
  remaining survey and inventory review.
- Shore Line East: the downloaded relation includes South Norwalk. The
  [official timetable effective March 29, 2026](https://shorelineeast.com/wp-content/uploads/2026/03/SLE-3_29-MNR-Schedule-Change.pdf)
  confirms weekday through service to Stamford, but shows no South Norwalk
  stop in the SLE THRU 1633/1638 columns. The relation was therefore not
  promoted. The shorter cached GTFS stop list alone was insufficient evidence
  to reject the Stamford extension.

The [official WVU station inventory](https://prt.wvu.edu/stations) confirms the
five-station system. Remaining source files and build manifests preserve the
specific inputs tested; colour citations in `na-feeds.json` are not geometry
approval.

## Verification scope

The Python regression suite passed 532 tests, including final-publication
deduplication, adjacent named stations, scoped merge isolation, input freshness
and inter-process locking. The build used isolated candidate/data directories;
package promotion is limited to the six rebuilt feeds and three Amtrak lines,
with concurrent-edit checks.

The JavaScript fixtures were regenerated successfully. `ios/verify.sh --core`
passed all 310 tests in 36 suites, including display-part and route-graph parity,
and its source/import/datum contracts. iOS resource packaging also passed;
the bundled US/CA packages and all six solver-data files match the published
files byte for byte. Only US/CA portions of the display-lane derivative changed.
All unrelated station and section feature rows were verified unchanged.

The final packages contain 353 US and 83 Canadian lines (436 total), four fewer
than the baseline. The complete NA audit reports 0 errors, 373 warnings and 190
notes, including 56 freshness warnings for legacy/unavailable input records.
There are no source hash mismatches. Structural preflight reports 0 errors and
the same three warning candidates as the baseline: Ethan Allen Express and
Keystone self-overlap, and Brightline's geographic outlier. Those unchanged
warnings remain open. Older cross-city station-code collisions, such as
Fullerton, also remain in the audit ledger; zero errors does not resolve them.

Verification commands (repository root):

```sh
python3 -m unittest discover -s app/scripts/railway/tests
python3 app/scripts/railway/audit-na-package.py \
  --package app/public/rail/us-2025.json --package app/public/rail/ca-2025.json \
  --registry app/scripts/railway/na-feeds.json \
  --official-networks app/data/raw/na-rail/official-networks \
  --shared-corridors app/public/rail/shared-corridors.json
node app/scripts/railway/build-display-lanes.mjs
node app/scripts/build/build-port-fixtures.mjs --stats
SCRATCH=/tmp/jtm-na-repair-swift ./ios/verify.sh --core
./ios/copy-rail-packages.sh /tmp/jtm-na-repair-bundle
```

Raw downloads are local inputs and are not newly committed. The reviewed OSM
candidate set is retained under `app/data/raw/na-rail/osm-reviewed-repair-20260906`;
it was passed explicitly to the candidate builder and was not promoted into
the default shipped route inventory.

Final web and iOS visual alignment review is **INCOMPLETE**. Format, audit and
cross-platform parity checks do not establish final basemap alignment. The
remaining warning ledger is retained rather than described as a clean railway
inventory.
