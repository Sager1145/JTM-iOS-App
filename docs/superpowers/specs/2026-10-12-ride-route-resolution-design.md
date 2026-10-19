# Ride route resolution deepening

User-approved scope: architecture recommendation #1, the related physical-path walk in #2, and #3 catalog-aware AI eligibility. No other architecture candidates are implementation scope.

## Resolution seam

Place the pure per-ride resolution sequence in RailCore. A worker-local `RideRouteResolution` accepts immutable `SourceInputs`, cached `NetworkInputs`, country, an optional existing worker graph store and lazy official-interval cache owner. Its `resolve(Request)` returns source/drawn WGS84 parts, physical selections and gaps, expected sections, disposition and precomputed-rejection information. The Request keeps raw versus canonical train and timetable provenance distinct. No MapKit, file/network IO, cache publication, device datum or UI types enter RailCore.

The module owns inferred/explicit interval selection, source certification, official interval then physical graph solving, independent-section retry, dated graph proof, boundary continuity and source/display interval matching. An independent retry keeps a supported leg visible but cannot certify a through connection. Recorded choices are not silently substituted. Historical geometry retains its temporal provenance and avoids today's display canonicalization. Cancellation remains checked between sections and before returning.

RiddenRouteStore loads/enriches inputs, caches immutable snapshots and derived indexes, admits worker execution, maps the returned parts into DrawnSegment (datum and MKMapRect), interprets presentation outcomes and publishes/caches. Pure selection metadata used for precomputed cache hydration uses the same core selection factory. The cache ambiguity query is semantic cache admission, not an exposed solver step.

Official-interval indexes retain lazy construction: selecting explicit intervals must not construct the legacy official index. The app keeps its existing bounded cache ownership; core supplies a thread-safe lazy index value. Mutable graph state remains confined to one sequential worker, with no unchecked Sendable graph wrapper added. Source memo lifetime remains one immutable source snapshot.

## State owner and eligibility

The physical certifier's five coupled fields move into a private value owner; ordering, tolerances, identity, junction and dated validity behavior remain unchanged. No unrelated statistics/rendering stage refactors.

JourneyCompletion owns a catalog-aware request result containing resolved train, denial and full eligibility. Callers supply actual scoped catalogs; they no longer resolve names or reconstruct code lookup. Unknown explicit codes are not rescued by names; ambiguous regional code/name ownership remains unresolved. EditorAIEligibility keeps the existing provider/busy precedence and corresponding-stop time rule. The screenshot adapter supplies Japan's catalog: Yahoo/JR East parsing and Japanese OCR product scope remain unchanged.

## Validation and limits

Follow ios/VERIFICATION.md. Write meaningful resolution-interface regressions and preserve existing independent topology/parser tests. Run only focused interface, walk and eligibility cases after coordinating the one heavy slot; use one relevant incremental native build for adapter types. Do not run national-resource cases merely because they share a suite. Source review and unmoved dependency evidence are reusable. No pixels, geography, performance or leak claims without measurements. No commits/pushes or retired runners.
