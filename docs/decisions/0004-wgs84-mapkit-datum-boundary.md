# 0004: Keep shared coordinates in WGS84

- Status: Accepted
- Date: 2026-09-01
- Decision owners: Project maintainers
- Supersedes: None

## Context

Railway packages, routing, statistics, exports, caches, and the WebUI need one
canonical coordinate system. Apple Maps presentation in selected regions needs
a display correction, but applying it to shared data would make values
client-specific and could shift cached coordinates more than once.

## Decision

Store and exchange longitude-first WGS84 coordinates everywhere. Apply the
audited display transform exactly once at the MapKit boundary for Taiwan, Hong
Kong, Macao, and Korea. Preserve source coordinates beside transformed display
coordinates wherever both drawing and statistics need the same route.

## Consequences

- Shared packages and exported journeys remain portable and comparable.
- MapKit presentation has a deliberate platform-only path.
- Every MapKit subject—network, stations, rides, and playback—must use the same
  boundary, while statistics and caches must never use display coordinates.
- Adding or removing a region from the transform requires multi-location evidence.

## Alternatives considered

- Rewrite package coordinates for Apple Maps: rejected because it would corrupt
  Web rendering, routing, exports, and provenance.
- Transform all regions: rejected because North America uses WGS84 in MapKit and
  a global rule is not supported by evidence.
- Infer a transform per point at runtime: rejected as unstable and unauditable.

## Validation

The datum assertions in `ios/verify.sh` must pass. Package preflight must continue
to report canonical WGS84, and visual datum audits must sample multiple cities
before the scope changes.
