# 0007: Fail closed when a route cannot be proved

- Status: Accepted
- Date: 2026-09-01
- Decision owners: Project maintainers
- Supersedes: None

## Context

A straight line between recorded stations looks plausible while misrepresenting
the railway, distance, coverage, and playback. Missing data, ambiguous topology,
or a solver failure is materially different from a verified path.

## Decision

When the route solver cannot produce supported railway geometry, keep the
journey record and expose an unavailable or failed route state. Do not invent a
station-to-station line. Permit retry or rebuild when inputs improve.

## Consequences

- Drawn routes and mileage remain evidence-backed.
- Some saved journeys can exist without a visible route until data is repaired.
- UI and import flows must communicate failure without deleting the record.
- Data pipelines should suppress unverified coverage instead of filling gaps.

## Alternatives considered

- Draw a straight-line fallback: visually reassuring, but creates false railway
  geometry and corrupts statistics.
- Reject the whole journey: prevents preserving valid user data when only route
  resolution failed.
- Silently omit the line: hides the failure and gives no recovery path.

## Validation

Route solver, presentation-state, import, and UI tests must cover failure and
retry. Package audits must treat direct station chords as errors or explicit
review candidates rather than accepted fallback geometry.
