# 0003: Use one seven-region map workspace

- Status: Accepted
- Date: 2026-09-01
- Decision owners: Project maintainers
- Supersedes: None

## Context

Journey records can span Japan, Taiwan, Hong Kong, Macao, Korea, the United
States, and Canada. A web-style active-region switch would split one personal
ledger into separate application states and prevent cross-region search,
statistics, and playback.

## Decision

Keep all seven regions in one local workspace. Each journey carries its region;
region scope filters the shared ledger rather than unloading another region.
Index compact regions first and the larger Japan/United States datasets second.
Decode detailed map geometry on demand for visible regions.

## Consequences

- Search, import, playback, and the journey library operate across regions.
- Dates must resolve through each journey's regional or station time zone.
- Caches, identifiers, and statistics indexes must remain country-scoped.
- Loading must be tiered so small regions are not blocked by national datasets.

## Alternatives considered

- Keep one active region like the WebUI: simpler state, but fragments the native
  product and makes cross-region records awkward.
- Decode all geometry eagerly: simpler loading, but wastes launch time and memory
  for regions the reader may never view.
- Store one library per country: reduces some scoping logic, but creates merge,
  import, and migration problems for the user-owned ledger.

## Validation

`Region.ordered` and bundle-copy checks must account for all seven region codes.
Tests must cover country-scoped caches, clocks, imports, and parity behavior for
every shipped region.
