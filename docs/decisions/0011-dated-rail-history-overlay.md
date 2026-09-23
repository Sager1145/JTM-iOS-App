# 0011: Retired railway keeps its geometry; rides are solved for their date

- Status: Accepted
- Date: 2026-09-23
- Decision owners: Project maintainers
- Supersedes: None
- Related: 0007 (fail closed), 0005 (atomic JSON persistence)

## Context

Solved ride geometry lives only in a re-buildable cache
(`Caches/RailMap/Routes/<country>/`, 512 entries per region, invalidated by
solver version) and is deliberately left out of the 1.3 export because it was
96% of the file. Every re-solve uses the current bundled `rail-sections*.json`
and `stations*.json`, and the cache key carries no ride date.

That design assumes any ride can be re-derived from the shipped network. The
assumption breaks the day a package is rebuilt from a newer N02 release: a
railway abolished since the previous release vanishes, and every ride on it
loses its route, its old stations and its mileage. It also already misroutes
old rides over lines that did not exist on the ride date.

Two ways to keep old rides: archive per-ride geometry, or keep retired railway
in the package with validity dates. The first fights the existing storage and
export design; the second restores the invariant the design relies on.

## Decision

1. The solver network is the current package **plus** a per-region history
   overlay (`rail-history[-<cc>].json`). The overlay carries retired sections
   and stations with their own geometry, and `retirements` that stamp an end
   date onto features still present in the current package. Nothing is ever
   dropped from the solver graph; it is dated instead.
2. Validity is a half-open day interval `[valid_from, valid_to)` on ISO
   `YYYY-MM-DD` strings. `valid_to` is the business-abolition effective date.
   A ride dated `d` may use an edge iff `valid_from ≤ d < valid_to`, with a
   missing bound meaning unbounded. An undated ride may use only edges with no
   `valid_to`, which is exactly today's behaviour.
3. The ride date and the overlay revision are part of the route cache key.
   The solver cache version is bumped so every existing entry is re-solved once.
4. Station snapping and station-transfer connectors obey the same validity as
   sections, so an old station name resolves only for rides in its period.
5. Per-ride geometry snapshots are **not** introduced by this decision. They
   remain an option for hand-specified or contested routes and are deferred.
6. Cross-day dashing in `MapDateScope` keeps its meaning. Historical styling
   is a separate, later change and must not reuse the `dashed` boolean.

## Consequences

- Rebuilding a package from a newer N02 release requires producing overlay
  entries for every feature that disappeared, with an abolition date checked
  against an official event, before the package ships.
- Diff between N02 releases proposes candidates; only an event confirms a
  date. Renames, operator transfers and re-segmentation are not retirements.
- Statistics keep matching against the current edge index for now; mileage on
  retired segments and a historical-vs-active coverage split are follow-ups.
- Swift and JavaScript solvers change together and the port fixtures are
  regenerated, so parity tests continue to pin the JavaScript's answers.
- BRT conversions and suspensions are modelled as validity intervals on the
  rail edge; bus rides are a different mode and are out of scope here.
