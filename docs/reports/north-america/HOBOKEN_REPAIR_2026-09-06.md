# Hoboken station and approach repair — 2026-09-06

The shipped NJT and PATH Hoboken memberships now share `us-official-hoboken`.
All 11 memberships (eight NJT and three PATH) remain present. Only the three
Hoboken-serving PATH lines change; the other 350 US lines and their solver
features are identical to the preceding station-ID migration release.

## Cause and changes

Station grouping previously measured groomed route anchors against a frozen
anchor seed. The local Hoboken–33rd Street anchor was 417.76 m from the NJT
seed, outside the unchanged 400 m name-match radius; published stop positions
are 150.24 m apart. The builder now uses published stop positions for both
its spatial grid and group-distance checks, independently of display anchors.
The parent identity pin therefore preserves the correct initial grouping.

The misplaced anchor came from a 0.0166 m seam between two disconnected
components of the original NJ Transit PATH GIS Hoboken–33rd Street feature 10.
PATH now opts into the existing graph repair with a 0.1 m limit, joining only
degree-one endpoints of different components. The original GIS coordinates
are preserved. A fixture retains the original geometry and verifies that
joining this centimetre seam reaches the Hoboken approach.

The scoped merger uses unchanged NJT station memberships as evidence of the
correct shared identity, so preserving historical PATH IDs cannot restore the
old split. It also remaps compact station time-zone indices into the output
package's table. Existing independently migrated station IDs, including PATH
9th Street, are retained.

## Published geometry and evidence

- All three PATH Hoboken anchors: `[-74.029208, 40.735451]`, 45.5 m from PATH
  GTFS parent 26730, instead of approximately 500 m away.
- Hoboken–33rd Street: 4.632 → 5.737 km. Only the Christopher Street–Hoboken
  interval changes, restoring 1.105 km of omitted approach track.
- Hoboken–WTC and JSQ–33rd Street via Hoboken: geometry and lengths unchanged;
  only their Hoboken identity changes.
- Independent reference comparison for the rebuilt line: 76 matched vertices,
  zero unmatched, maximum deviation 22.67 m, below the 25 m metro threshold.
- Source: NJ Transit GIS PATH layer, original edit timestamp 2021-06-21;
  normalized source raw SHA-256
  `9382638edebbbf3c2345d0804088667ed6d5aafcea2bd83f058e17ee540ec724`.
  Detailed source attribution is appended to `app/public/rail/us-2025.sources.md`.

## Verification

- 546 Python tests passed, including published-coordinate grouping, all PATH
  sibling entry permutations, the actual GIS seam, scoped cross-feed identity,
  unrelated station preservation, and time-zone remapping regressions.
- Structural package preflight: zero errors; three pre-existing warnings.
- Exact comparisons confirm all non-Hoboken station rows and time zones,
  unselected lines, and unrelated solver features remain unchanged.
- Display lanes and native display network regenerated. Debug iOS Simulator
  build and resource copy passed. Web and native Hoboken screenshots inspected:
  the three PATH approaches reach the station and Hoboken is labelled once.
- The North America audit retains 18 `package.stale` errors for unrelated
  historical build fingerprints (12 US, six CA); no current geometry or
  station-identity errors were hidden or waived.

The seven US-dependent fixture files were regenerated from the repaired package.
Unchanged import and playback fixtures, which use Japanese/Taiwanese inputs,
were retained from the preceding fully verified station-ID migration.
The scoped fixture run used the existing production builders without changes
to their calculations.

Swift core regression: Test run with 310 tests in 36 suites passed after 196.849 seconds.
Swift presentation regression: 194 tests in 17 suites passed.
