# Application organization review — 2026-10-10

Grok 4.7 at xhigh performed a declaration/inventory scan across the app's Swift tree and focused reads of mixed-responsibility files. The first bounded session reached its turn limit before producing a final answer; the exact session was resumed only to conclude the existing findings, with no further reads or edits. Codex checked the cited symbols locally and owns the resulting changes. This is structure evidence, not a full body-by-body correctness audit.

## Applied findings

- Split timetable detail and train research screens from ServicePatternPickerView.
- Separate StatisticsStrings from StatisticsFormat and align the former with Localization.
- Centralize four optional-text and two comma-list adapters without changing empty-string, trimming or list-order semantics. Endpoint clearing and direction-edit tracking remain specialized.
- Move the station-alias loader with its private cache out of catalog loading.
- Separate JourneyBranding and RouteBadgeIndex from RouteLogoSquare.
- Separate route correction and local line-service browsing from route guide/fill views.
- Keep draft-stop annotation views with the other journey label views.
- Move PrimaryTab and two diagnostic probes to their own responsibility files.
- Separate bundled display-network format types from file-loading operations.
- Correct old ContentView owner references, rename the shell AppShell and remove obsolete flight-app section labels from railway statistics.

## Boundaries retained after review

The map coordinator, workspace, editor wizard and statistics cards still contain private owner state and coherent lifecycle/action sections. Splitting those methods across files would require broader state access or a new lifecycle design; the organization work keeps their private boundaries. The same applies to RiddenRouteStore's solver actors and cache decoder and subscription-auth private wire records. Two route-search continuation closures have separate request-local memo lifetime and remain locally scoped; no shared global cache was introduced merely to remove a small duplicate.

RailKit's domain algorithms retain their public identities, private accumulators and Resources paths. Further extraction suggestions are in source-structure-railkit-review.md; they are optional organization alternatives, not unresolved correctness defects.
