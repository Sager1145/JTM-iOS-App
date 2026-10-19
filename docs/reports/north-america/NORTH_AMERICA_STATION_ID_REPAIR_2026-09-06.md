# North America station identity repair — 2026-09-06

This repair separates 61 United States station group IDs that represented
multiple geographically disjoint places. It changes 88 line memberships and
adds 64 distinct group IDs: 3,720 → 3,784 US station groups. It retains the
353 US and 83 Canadian lines, all station coordinates, station order, interval
geometry, distances, line identities, colours, and source attribution.

## Evidence and implementation

The reviewed catalog is `app/scripts/railway/na-station-id-repairs.json`.
It pins each old ID, replacement ID, line membership, observed WGS84 anchor,
source feed, and geometry source. Its source-package SHA-256 identifies the
snapshot reviewed in `NORTH_AMERICA_FOLLOWUP_ANALYSIS_2026-09-06.json`.
This is an identity migration over existing surveyed anchors; it introduces
no new coordinate source or alignment claim. Existing package source and
licence records continue to apply.

The catalog keeps one existing ID at its original recorded place and assigns
stable, feed-qualified IDs to other places. It preserves local interchange
memberships. The closest split is Amtrak versus Brightline at Fort Lauderdale
(about 2.5 km); other examples include Manhattan/Brooklyn 86 St, Newark/New York
Penn, Chicago/California Fullerton, and Alaska/Chicago Healy.

`repair-na-station-ids.py` applies the catalog to a staging tree. It validates
all recorded line anchors and solver features, rejects conflicting replacement
IDs, regenerates station readings, and records its input hashes under
`stationIdentityRepair`. Rerunning an applied catalog is a no-op. Historical
geometry build fingerprints are retained, not replaced with current hashes.

The scoped merger now checks the final identity-map target against every
retained member, including sibling lines of the same operator. A nearby
member cannot hide another member in a remote city. The package auditor
checks the furthest pair in each group and raises `station.identityCollision`
as ERROR above 2 km unless an exact reviewed complex exception applies.
It previously stopped at the first drifting pair and could report Forest
Hills as 166 m while hiding a member 406 km away.

## Verification

- All 61 reviewed cross-place collisions eliminated; 88 row-ID changes.
  Restoring just those ID fields makes every US line object exactly equal
  to its baseline. Rail-section files and the Canadian package are unchanged.
- The strengthened identity audit finds **61 collisions before and 0 after**
  against the same baseline and staged package.
- Six new migration/auditor tests cover idempotency, preserved local transfers,
  moved anchors, missing solver features, occupied replacement IDs, and the
  furthest-pair audit. Merger regressions cover nearby-plus-remote groups,
  identity-map target collisions, and retained same-operator siblings.
- Python suite: **546 tests passed**. The initial run caught a syntax error
  in the new test fixture; the fixture was corrected and the entire suite rerun.
- Real Web popup model: Chicago Fullerton lists only CTA Brown/Purple/Red;
  Alaska Healy lists Aurora Winter; BART Concord lists only BART Yellow.
  California Fullerton still shares Amtrak and Metrolink memberships.
- Structural preflight: **0 ERROR, 3 unchanged WARNING** (Ethan Allen and
  Keystone self-overlap; Brightline geographic outlier). No coordinate,
  anchor, seam, interval-length, or new geometry regression.
- Display lanes and display network regenerated from the staged package.
  Existing Japanese unresolved display-landlord windows remain unchanged.
  The display-lane diff is limited to DART Green: two span boundaries move
  by 0.1 m and its derived part records 491 instead of 473 vertices; source
  interval geometry and total length remain unchanged.

- All JavaScript port fixtures regenerated successfully. Only
  `station-display.json` and `stations.json` changed relative to the baseline.
- `SCRATCH=/private/tmp/jtm-station-id-repair-20260906/swift ./ios/verify.sh --core`:
  **310 tests in 36 suites passed**, along with the core warning/import and
  renderer contract checks.
- `./ios/copy-rail-packages.sh /private/tmp/jtm-station-id-repair-20260906/bundle`:
  **passed**. Bundled US and CA packages match the staged files byte for byte.
- **13 generated artifacts published** after baseline hash comparisons;
  verification held the release lock until **10:36 EDT**. The lock is released
  and the Hoboken task can now merge against these IDs. The source migration,
  guard changes, catalog, tests and this report remain in the shared worktree.

## Remaining audit findings

The migration baseline already had **18 build-input fingerprint errors**:
current builder and registry edits differ from the inputs of earlier scoped
builds. The same 18 errors remain; only US package generation timestamps in
those findings changed. No new error category was introduced by the migration.
The repair does not certify unrelated geometry as freshly rebuilt.

Combined NA audit: **18 ERROR, 321 WARN, 151 NOTE**, compared with
18 ERROR, 373 WARN, 189 NOTE before migration. US: 12/258/135; CA: 6/63/16.
The US audit Markdown lead itemizes a narrower historical category set;
its appended migration note gives complete totals. Full findings remain in
`app/public/rail/na-2025.audit.json` and the regional audit JSON files.

Inventory gaps, geometry evidence, stale city-ledger classifications, and old
colour-blocker aliases identified by the preceding analysis remain separate
follow-up work. Final Web and iOS visual alignment review is **INCOMPLETE**;
this repair verifies station identities and cross-platform data consumption,
not basemap alignment.

## Reproduction

```sh
python3 app/scripts/railway/repair-na-station-ids.py --app-root /tmp/staging/app
python3 -m unittest discover app/scripts/railway/tests
python3 app/scripts/railway/audit-na-package.py \
  --package /tmp/staging/app/public/rail/us-2025.json \
  --package /tmp/staging/app/public/rail/ca-2025.json \
  --registry app/scripts/railway/na-feeds.json \
  --official-networks app/data/raw/na-rail/official-networks \
  --shared-corridors /tmp/staging/app/public/rail/shared-corridors.json
# Run the display/fixture generators from the staged app tree, then publish
# only after comparing original-file hashes to exclude concurrent changes.
node /tmp/staging/app/scripts/railway/build-display-lanes.mjs
node /tmp/staging/app/scripts/build/build-port-fixtures.mjs --stats
SCRATCH=/tmp/jtm-station-id-swift ./ios/verify.sh --core
./ios/copy-rail-packages.sh /tmp/jtm-station-id-bundle
```

Local audit, popup results, baseline snapshots, generated artifacts and the
publication manifest are retained in `/private/tmp/jtm-station-id-repair-20260906`.
The simultaneous Hoboken task preserves this migration and will rebase its
three PATH route repairs on the published IDs, including the common Manhattan
9th Street ID shared with retained PATH sibling routes.
