# 0012: Own per-ride resolution and catalog eligibility in RailCore

- Status: Accepted
- Date: 2026-10-12
- Decision owners: Project maintainers
- Extends: 0001, 0007, 0010, 0011

## Context

RiddenRouteStore formerly ordered interval inference, selected-source materialization, official/graph solves, independent-leg retry and physical continuity proof inside the native target. Core tests could exercise constituent solver steps but could not exercise the actual per-ride policy through the same interface as the app. Coupled physical-path walk state was also distributed through several private inout helpers. Three AI-completion views prepared station eligibility differently.

## Decision

RideRouteResolution in RailCore owns the per-ride policy. A sequential worker consumes immutable source inputs and cached network/official-interval owners, then resolves a request retaining raw/canonical train and timetable provenance. Results carry source/drawn WGS84 geometry, dated provenance, physical selections/gaps and disposition. RiddenRouteStore retains resource IO, immutable/derived caches, worker admission, native datum/MKMapRect adaptation, route-cache storage and publication.

A failed continuity-constrained solve may retry an independent supported leg; that leg never establishes a through connection without the dated boundary proof. An authored interval is not silently replaced. Historical geometry retains the existing dated solver rules. Seven solver implementation methods and two implementation carriers become internal after native callers move; independent core topology tests retain access through @testable.

Official-interval construction remains lazy inside a lock-protected value owner retained by the app's bounded revision-keyed cache. A worker alone owns its mutable graph. PhysicalPathWalk is a private value owner for its coupled frontier/pending/anchor state and unchanged proof rules.

JourneyCompletion.requestEligibility owns unique name/alias resolution, scoped catalog-code ownership and station/time eligibility, returning a resolved train and denial/full eligibility. Existing compatibility methods delegate to this rule. Screenshot import still supplies Japan's catalog: the documented Yahoo/JR East source grammar and Japanese OCR scope do not become multi-region.

## Consequences

- Production and package tests cross the same per-ride and catalog-aware interfaces.
- Source versus display geometry, timetable ownership, date, ambiguity and independent physical gaps remain explicit outcomes.
- No new package, MapKit dependency, remote port, graph Sendable wrapper or fabricated cross-track permission is introduced.
- Actual typed station ambiguity is denied rather than resolved by arbitrary dictionary order.

## Alternatives considered

- Move only low-level solver calls: leaves the per-ride ordering and failure policy untestable in the native target.
- Put the sequence in RailApplication while retaining all solver internals public: adds a seam without removing the unnecessary lower-level interface.
- Inject fake solver operations: tests a reconstructed strategy rather than the actual surveyed source/graph policy.
- Build all indexes eagerly: makes recorded-interval rides pay the unrelated legacy-index cost.
- Expand screenshot geography during eligibility consolidation: changes a documented product decision and is outside the approved scope.

## Validation

Follow ios/VERIFICATION.md, which supersedes historical runner/full-matrix text in older ADRs. Use the small RideRouteResolution interface fixtures, selected synthetic physical-walk cases and affected JourneyCompletion eligibility tests; one incremental native compile establishes app adaptation. Preserve independent existing topology tests. No full resource census, source hashes, national rebuild, pixel/geographic/performance/leak certification or automatic pipeline is implied. Actual command results and limits belong in the scope ledger.
