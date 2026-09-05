# 0005: Persist journeys as atomic local JSON

- Status: Accepted
- Date: 2026-09-01
- Decision owners: Project maintainers
- Supersedes: None

## Context

Journey data is user-owned, local-first, importable, exportable, and compatible
with the existing JSON store. The app does not require an account or application
server. Writes must not leave a partial file, and destructive operations need a
bounded recovery path.

## Decision

Persist the canonical journey store as local JSON using ordered, atomic writes.
Serialize writes through one storage owner. Before destructive replacement,
keep one validated recovery backup and its metadata; expose import and export as
the interoperability boundary.

## Consequences

- The app works offline and does not require a database migration system.
- Users can inspect and transfer their data through the shared JSON format.
- Large queries are in-memory and the app owns backup validation and ordering.
- This is recovery from the latest destructive action, not indefinite versioning.

## Alternatives considered

- SwiftData/Core Data: provides queries and migrations, but breaks direct store
  compatibility and adds complexity the current dataset does not require.
- Cloud-only storage: enables sync but adds accounts, networking, privacy, and
  failure modes outside the product's local-first requirements.
- Non-atomic file writes: simpler, but risks destroying the only user copy.

## Validation

Store round-trip and canonical-byte tests must pass. The app gate must continue
to verify ordered, atomic writes and a single writer; recovery must decode the
backup before replacing the active store.
