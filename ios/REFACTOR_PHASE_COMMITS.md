# Refactor phase delivery ledger

User instruction: complete the refactor and commit/push each validated phase to `main`.
Only the phase's reviewed files enter its commit; unrelated staged work remains intact.

## Phase 1: deterministic iOS resource packaging

Status: validated; commit/push this phase independently.

`copy-rail-packages.sh` moves generated timestamps and build timings from bundled
manifest/report JSON into build diagnostics. Geometry, content hashes and input
identity remain unchanged. The existing App decoder does not consume these fields.
The railway generator and user datasets are unchanged by this phase.

Validation on the frozen data snapshot: clean and incremental outputs match all
1,086 files byte for byte; baseline, candidate and final Release bundles match
those hashes. Latest integrated Release builds and the public statistics workflow
pass. These receipts describe the frozen snapshot, not every possible dataset.
Local receipts: `outputs/refactor-20261009-resume/resource-clean-incremental-final.json`,
`release-bundle-resource-identity.json`, `release-final-resource-identity.json`.

## Remaining delivery phases

- Recover the large historical graph's memory acceptance without changing physical
  connectivity, surveyed geometry, expected routes or mileage assertions.
- Integrate validated statistics/route/display cache and lifecycle changes as
  independently buildable commits; include and verify required prerequisites.
- Add coverage export/reporting and version-pinned advisory lint/format CI, then
  meet and enforce the original coverage/quality goals using complete evidence.
- Complete remaining UI/platform, launch/render/stall/build/leak measurements.
- Finish responsibility/directory migration where needed, and resolve the map
  full-viewport dimming requirement under the public API/performance constraints.
- Close the complete regression matrix and release acceptance.

The roadmap is not complete. Existing full-suite/data failures and the historical
national graph's 2 GiB operational test stop remain recorded, not waived.
