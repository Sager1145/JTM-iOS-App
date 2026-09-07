# North America warning repairs — 2026-09-06

Four US line objects change: `mbta-d`, `mbta-e-b1`,
`metro-north-railroad-harlem`, and `septa-regional-rail-fox`.
The other 349 US line objects and all 83 Canadian lines are unchanged,
including Toronto's 49 TTC lines. The preceding 61-ID migration and Hoboken
repair remain intact.

## Repairs

- Separate Olney's subway and regional-rail group IDs, and Woodlawn's NYC
  subway and Metro-North group IDs. These places are respectively about
  1,976 m and 1,695 m apart. Only the two regional-rail membership IDs change;
  their station coordinates, intervals, distances and local subway transfers
  are preserved. The reviewed catalog is
  `app/scripts/railway/na-local-station-id-repairs.json`; its agency-map links,
  pinned coordinates and package hash identify the evidence. The migration
  retains the prior `stationIdentityRepair` record as `previousRepair`.
- Regenerate Green D and Green E's Union Square–Lechmere branch from the
  existing MassGIS extracts and MBTA GTFS 437 parent coordinates. Green D's
  Union Square anchor moves about 321 m; the E branch's Lechmere anchor moves
  about 452 m. Their route lengths change from 22.807 to 23.164 km and from
  0.904 to 1.682 km respectively. These are overlapping services, not an
  assertion of 1.135 km of additional unique physical track.
- The router previously reported the nearest possible feature snap even
  when its common-feature choice used an endpoint hundreds of metres farther
  away. `na_official.py` now reports the actual returned interval endpoints,
  retaining the minima separately as `nearestSnapMeters`. Route-specific
  100 m limits prevent the bad endpoint choice while retaining all 25 trunk
  stops on both D and E. A 50 m trial excluded North Station (51.758 m);
  regression coverage now checks the full stop sequences. D and the E branch
  keep their existing station IDs and counts. Their rebuilt timezone indices
  correctly resolve to `America/New_York`.
- Partial feed merges now match each selected station membership and decoded
  interval exactly, including multiplicity. Operator/name matching alone
  conflated Green E's trunk and branch, both named `Green Line`. The stronger
  match preserves same-named siblings and fails if a selected feature is
  missing. Existing synthetic merger fixtures were corrected to use internally
  consistent package/GeoJSON identities and geometry.
- BART Yellow's named source includes OSM relation 2827684 and BART GTFS eBART
  geometry. The cross-check now derives OSM lineage from verified source
  provenance instead of excluding only a source literally called `osm`.
  Both ordinary comparisons and straight-segment certification use the rule.
  Remeasuring this shipped line changes only comparison metadata: the former
  531 OSM matches are excluded; 66/678 vertices match independent NARN within
  400 m, and 612 lack a match. Without per-vertex lineage, excluding OSM for
  the entire composite is conservative. This is an evidence gap, not proof
  that 612 vertices are geographically wrong. Separate reference-input hashes
  do not overwrite historical geometry-build fingerprints.

## Validation

- Python: **550 tests passed**, including four new regression methods for
  the local identity catalog, complete D/E anchor routing, named-source OSM
  exclusion, and exact partial feature matching.
- Exact scope comparison: only the four listed US line objects change;
  unselected station and section GeoJSON features are identical as multisets.
  Canada package, station, section and reading files are byte-identical.
  Display-lane changes are restricted to US entries.
- Structural preflight: **0 ERROR, 3 unchanged WARNING, 6 INFO**. The warnings
  are Ethan Allen/Keystone self-overlap and Brightline's geographic outlier.
- Real Web popup model: Olney subway lists only B1/B2/B3; Woodlawn subway
  lists only NYC 4. Chicago Fullerton and Alaska Healy retain their corrected
  memberships; California Fullerton still shares Amtrak/Metrolink.
- Display lanes and all JavaScript port fixtures regenerated from the staged
  package. Swift core verification passed **310 tests in 36 suites**, with
  no RailCore or RailPresentation warnings; import and renderer contract
  checks also passed. The first Swift attempt preceded fixture completion
  and was stopped; these results are from the subsequent complete run.
- The bundle-copy gate passed into a fresh destination, including generated
  display networks, route data, badges, localization and samples. Bundled US
  and CA packages and solver datasets match staging byte for byte.
- **21 generated artifacts published and verified at 21:42 EDT** after
  baseline comparisons under the release locks. Current build inputs were
  rechecked for both rebuilt MBTA lines; unrelated generated-file edits would
  have aborted publication. Source, tests and generated changes remain in
  the shared worktree; no commit was created by this repair.
- Final Web basemap and iOS MapKit visual alignment inspection is
  **INCOMPLETE**. Data/renderer parity does not replace that visual review.

## Remaining findings

The combined audit changes from **18 ERROR / 321 WARN / 150 NOTE** to
**36 ERROR / 317 WARN / 149 NOTE**. Every ERROR is `package.stale`: the builder,
router library and registry changes differ from recorded inputs of retained
historical builds. Only D and the E branch are certified against this turn's
current inputs. There are no new geometric or station-identity error categories.
The increased stale count must be resolved through scoped rebuilds and review,
not by copying current hashes onto old geometry.

Remaining WARN categories:

| Check | Count |
| --- | ---: |
| Geometry radius | 80 |
| Station split | 67 |
| Missing historical input fingerprint | 56 |
| Official-source deviation retained | 45 |
| Silent registry feed | 35 |
| Official-source reference missing | 14 |
| Geometry spike | 6 |
| Nested operator prefix | 6 |
| OSM-source deviation retained | 2 |
| OSM-source reference missing | 2 |
| Unmerged reviewed station complex | 2 |
| NARN reference missing | 1 |
| Interval detour | 1 |

The combined `na-2025.audit.json` is the count source; regional audit files
are refreshed only for the region being merged and can retain older input
checks. This repair does not claim to clear the remaining source-reference,
feed-inventory, Washington anchor, or geometry-review work.

## Reproduction and artifacts

Use an isolated app tree. Apply the local catalog with
`repair-na-station-ids.py --app-root <staging>/app --catalog
app/scripts/railway/na-local-station-id-repairs.json`, build MBTA with the
current registry, then merge only `mbta-d` and `mbta-e-b1` using
`merge-na-feed-build.py --line-id` twice. Regenerate the audits, display lanes
and JavaScript fixtures before running `ios/verify.sh --core` and
`ios/copy-rail-packages.sh <fresh-destination>`.

The baseline, scoped candidate, BART reference recheck, exact scope comparison,
logs and publication manifest are retained in
`/private/tmp/jtm-warning-fixes-20260906`. Publication compares original file
bytes under the release locks before replacing any generated artifact.
