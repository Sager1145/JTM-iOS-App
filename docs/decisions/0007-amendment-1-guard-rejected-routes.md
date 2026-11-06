# 0007 amendment 1: A guard-rejected route is unproven, not a route

- Status: **Accepted**, option B (2026-11-05). The maintainer chose to keep
  drawing a guard-rejected route but mark it unproven, over the recommended
  option A. See "Decision" below; the original proposal text is kept for the
  record.
- Date: 2026-11-05
- Amends: 0007
- Related: 0012 (ambiguity is denied, not resolved arbitrarily); audit item A4
  in `docs/architecture/feature-interface-audit.md`

## Context

ADR 0007 forbids inventing station-to-station geometry. It does not say what
happens when the solver finds real track but one of its own plausibility guards
rejects that track. The solver now has two kinds of fallback, and the audit (A4)
flags one of them as a fail-closed violation.

1. **Guard-rejected last resort (`guardedFallback`).**
   - Where: `RouteSolver.orderedSectionRouteChoice`
     (`ios/RailKit/Sources/RailCore/Routing/RouteSolver.swift`, the
     "Last resort" branch at the end of that function).
   - What it keeps: the first candidate that `endpointIsImplausible` rejected.
     That guard fires only when all of the following hold:
     - the section names an endpoint without an N02 code;
     - the straight-line distance is over 20 km;
     - the chosen endpoint is more than 2× as far as another station with the
       same name.
   - When it returns that candidate: if no attempt, including the soft
     fallback, finds anything else.
   - Why it exists: the doc comment on `endpointAmbiguityDistanceFactor` says
     the guard was added later, and a section that solved before it "never
     becomes nil".
   - Example (from that comment): 糸魚川→泊 snaps to the 泊 on the 山陰線
     instead of the nearby one.
   - What goes wrong: the result is real track, so it is not a straight chord.
     But it runs to a station the rider almost certainly did not mean.
     `SectionRouteChoice` carries no flag, so downstream it cannot be told
     apart from a proven solve:
     - `RideRouteResolution` draws it and records the far station's code;
     - its distance feeds mileage, coverage and the passport.
   - The JS twin (`app/public/app-route-solver.js`, `guardedFallback`) does
     the same.
2. **Soft preference fallbacks.** These are the solve modes
   `no_common_line_soft_fallback`, `soft_fallback_after_home_attempts`,
   `institution_only_unbiased_fallback` and
   `institution_unpenalised_soft_fallback`.
   - What they relax: only *inferred* line, operator and institution
     preferences.
   - What they keep: explicit per-section constraints, the detour guard, the
     endpoint guard, and the physical-continuity proof.
   - They choose between proven paths. They do not accept a path a guard
     rejected.

Under ADR 0012, "actual typed station ambiguity is denied rather than resolved
by arbitrary dictionary order". `guardedFallback` resolves exactly that kind of
ambiguity by taking the first rejected candidate.

## Decision (accepted, option B)

Add to ADR 0007's Decision section:

> Relaxing an inferred preference (line, operator, institution) is permitted
> when the result still passes every plausibility, identity and continuity
> guard. A candidate that a plausibility guard rejected is not a proven route.
> The solver may still return it as a last resort, but only with the explicit
> outcome `unproven`. An unproven section may be drawn, with a distinct mark.
> It must not be counted in mileage, coverage, the passport or statistics, it
> must not record its solver-chosen endpoint station code, and it must be
> offered for route repair.

Implementation:

- **Solver.** `RouteSolver.SectionOutcome` (`proven`/`unproven`) is one field
  on `SectionRouteChoice` and `SolvedSection`. `orderedSectionRouteChoice`
  tags `guardedFallback` `.unproven`. `solveSectionOnDemand` never stops
  widening on an unproven regional result, and prefers any proven result.
- **Resolution.** `RideRouteResolution` records an unproven section as one
  non-boundary `PhysicalGap` with `isUnproven = true`. It draws the solver's
  own coordinates, with no display canonicalization and no
  `physicalRoute`/station codes. It records no certified path keys and does
  not continue into the next section.
- **Consumers.** Mileage and passport already drop non-boundary gap sections.
  Area coverage and traversed-line detection skip unproven sections too. The
  map draws them in a separate `ride-unproven` stroke with the existing
  dotted pattern. The gap reaches `RouteRepair` as a section span and the
  journey notice text says the route is unproven (en/ja/zh-Hant/zh-Hans).
- **Cache.** `RouteGraph.routeDrawnCacheVersion` is bumped (32→33) so
  persisted native solves are re-resolved with the flag.
  `routeSolverCacheVersion` stays 28: it keys JS precomputes, which cannot
  carry the flag, so its bump waits until the website repo's JS solver
  mirrors this outcome (follow-up).
- **Web parity.** `app/public/app-route-solver.js` still returns
  `guardedFallback` untagged. The JS twin diverges until the website repo
  mirrors this outcome (code comment at the Swift solver).
- **Measured exposure.** None of the 2,225 sections in the 287 bundled sample
  rides (plus 406 special/default-train sections) can reach the guard: every
  endpoint carries an N02 code, and the guard only fires for name-only
  endpoints.

## Original proposal (option A, not chosen)

Add to ADR 0007's Decision section:

> Relaxing an inferred preference (line, operator, institution) is permitted
> when the result still passes every plausibility, identity and continuity
> guard. A candidate that any such guard rejected is not a route. The section
> resolves as unavailable, exactly as if no track had been found. It must not
> be drawn, counted in mileage, or used to record an endpoint station code.

Code follow-up, if accepted (separate change):

- Delete `guardedFallback` from `orderedSectionRouteChoice`, so it returns
  `nil`.
- Rewrite the doc comment on `endpointAmbiguityDistanceFactor` to match.
- Keep every soft-fallback mode.

## Options considered

| Option | User-visible effect | Cost | Fits 0007/0012 |
|---|---|---|---|
| **A. Delete, return nil (recommended)** | A name-only section whose only reachable same-name endpoint is far away shows the existing unavailable/gap state, drops out of km, and is offered route repair (`RouteRepair.Gap`). Previously it drew a confident but probably wrong route with inflated km. | Small: one function in RailCore plus a new test | Yes |
| B. Keep, but report it as an explicit `.unproven` outcome | The route still draws but is marked. If it is mapped onto the existing physical-gap state, km drop but the wrong endpoint code is still recorded. | Medium: a new field on `SolvedSection`, mapping in `RideRouteResolution`, status and UI wiring through `RiddenRouteStore` and the editor | Only partly: still resolves ambiguity arbitrarily |
| C. Amend 0007 to allow it | None. Wrong-station routes stay indistinguishable from proven ones. | None | Contradicts 0012 |

## Consequences of option A

- Some rides that draw today will show a gap on that leg after re-solving. How
  many is unmeasured. Before merging, count name-only sections in real stores
  that hit the guard (one RailDiagnostics route-solve request or a local query
  is enough).
- **Cache.** Persisted solves and JS-precomputed parts keep their old guarded
  results until `RouteGraph.routeSolverCacheVersion` and
  `routeDrawnCacheVersion` are bumped (`RouteGraph.swift`). Bump them in the
  same change, or the fix reaches fresh solves only. `RouteGraph.swift` is in
  an in-flight branch's diff today, so schedule the bump after that branch
  merges.
- **Web parity.**
  - `app/public/app-route-solver.js` keeps its `guardedFallback` until the
    website repo mirrors the change.
  - The port fixture `route-section-solve.json` uses only coded endpoints. The
    guard does not fire for those, so
    `node app/scripts/build/build-port-fixtures.mjs --check` is unaffected.
  - Record the divergence in the code comment until the JS side follows.
- **Soft fallbacks keep working.** The 糸魚川→魚津 through-running case
  that motivated them is unaffected.

## Validation (proposal for option A; see the change for option B's tests)

- New `RouteSolverEndpointGuardTests` (RailCore), built the way
  `PhysicalSectionContinuityTests` builds its synthetic graph:
  - a name-only section O→T;
  - rail from O to a far T about 45 km away;
  - a second station named T about 9 km from O on isolated track.
- Assertions:
  - `RouteSolver.solveSection` returns `nil` (it returns the far path today);
  - control case: the same layout with an N02 code on T still solves.
- Re-run the existing focused suites: `PhysicalSectionContinuityTests`,
  `RideRouteResolutionTests`, `RouteSectionSolveParityTests`,
  `DatedEndpointNameShadowTests` and `RouteSolverEndpointPreflightTests`.
- No existing test covers the guard today.
