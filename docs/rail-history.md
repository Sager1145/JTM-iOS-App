# Rail history overlay

Per-region file `app/data/rail-history.json` (jp) or
`app/data/rail-history-<cc>.json`. Optional: a region without one behaves as
before. Copied into the app bundle by `ios/copy-rail-packages.sh` alongside
`rail-sections*.json`. See ADR 0011.

```json
{
  "schema_version": "1",
  "revision": "2026-09-23.1",
  "sections": [
    {
      "type": "Feature",
      "properties": {
        "history_id": "jp.rumoi.rumoi-mashike",
        "N02_001": "11", "N02_002": "2",
        "N02_003": "留萌線", "N02_004": "北海道旅客鉄道",
        "valid_to": "2016-12-05",
        "source": "N02-16; MLIT 鉄軌道の廃止実績"
      },
      "geometry": { "type": "LineString", "coordinates": [[lon, lat], ...] }
    }
  ],
  "stations": [
    {
      "type": "Feature",
      "properties": {
        "history_id": "jp.rumoi.mashike",
        "station_name": "増毛", "line_name": "留萌線", "operator": "北海道旅客鉄道",
        "railway_class_code": "11", "institution_type_code": "1",
        "n02_station_code": "...", "n02_group_code": "...",
        "valid_to": "2016-12-05",
        "source": "N02-16"
      },
      "geometry": { "type": "LineString", "coordinates": [[lon, lat], [lon, lat]] }
    }
  ],
  "retirements": [
    {
      "history_id": "jp.rumoi.fukagawa-ishikarinumata",
      "match": {
        "line_name": "留萌線", "operator": "北海道旅客鉄道",
        "bbox": [minLon, minLat, maxLon, maxLat]
      },
      "valid_to": "2026-04-01",
      "source": "MLIT 鉄軌道の廃止実績; JR北海道 2026-03-31 最終運行"
    }
  ]
}
```

Rules:

- `sections` and `stations` use the same property spellings the current files
  use (raw `N02_00x` or spelled-out); both are accepted. They are historical service or identity variants. Their coordinates may
  overlap the current package; service periods and identities remain distinct.
- Every entry has a service interval: `valid_from` and/or `valid_to`
  (`YYYY-MM-DD`), or a domain pair below. Interval is half-open: valid on
  the start, no longer valid on the end.
- Optional `service_validity` and `infrastructure_validity`, each
  `[from, to]` with the same half-open rule (`null` is unbounded on that
  side). The ride solver reads the service interval only. A feature that
  has only `valid_from`/`valid_to` already is that interval — those are the
  strings the solver copies onto edges, and they do not change when the
  domain keys are absent. `infrastructure_validity` does not admit or
  exclude a ride. When both domains are present they may differ (suspended
  track can outlive its service). When only one domain pair is present, it
  is the service interval.
- Optional `kind`: `opening`, `closure`, `relocation`, `station_opening`,
  `station_closure`, `suspension`, `resumption`, `operator_transfer`.
  Omitted kind is `closure`. The shipped jp overlay does not set it.
- `retirements[].match` selects current-package features whose `line_name`
  and `operator` match exactly and whose every coordinate lies inside
  `bbox`. Matching features receive the entry's service interval. Optional
  `match.targets` (`["sections"]`, `["stations"]`, or both) limits which
  collection is stamped; omitted means both. New source events emit separate station and section
  stamps where required. A retirement that matches nothing is a data error the
  loader reports.
- `revision` is folded into the route cache key. Bump it whenever the file
  changes.
- Ride date rule: dated ride uses edges valid on that date; undated ride uses
  only edges with no `valid_to`.
- Sources: N02 releases as permitted by their licence, and official abolition
  notices. N05 derivatives need a separate licence check before shipping.

## Building the jp overlay

`app/data/rail-history.json` is generated; do not hand-edit it. Edit
`app/scripts/railway/jp-rail-history-events.json` and rerun:

```sh
python3 app/scripts/railway/build-jp-rail-history.py --revision YYYY-MM-DD.N
```

Inputs: `app/data/rail-sections.json` / `stations.json` (the current package)
and the MLIT releases N02-05 … N02-24, which are local-only like the rest of
the railway sources. By default they are read from
`~/Documents/GitHub/Japan-Train-Map/app/data/raw/railway/jp/history/`
(`--source-dir` to override); fetch a missing one from
`https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-YY/N02-YY_GML.zip`
(N02-13 is `N02-13.zip`; there are no 09/10 releases).

Each event names the N02 spelling of the line and operator, the last
release that still carried the section (`year`), the official date
(`valid_to`) and its `source`. The builder takes that release's geometry
wherever it lies more than 40 m from current track (and from retired track a
later event already emitted) and drops digitising noise. Loose ends are then
tied in, because the graph joins lines only where 5-decimal coordinates are
equal: two ends of one event within 120 m are bridged to each other (a line
cut where it crossed another on a bridge); an end is walked along the old
line through any corridor it shared with open track (≤ 3 km) to the
platform of a junction station, so a ride naming the retired line has an
edge of it at 屋代 or 木古内; finally it is joined to an exact vertex of
non-新幹線 track within 200 m. `--report` lists the line each join lands on
— check it after every rebuild. Options:
`bbox` (restrict/split an event), `station_year` (a release that still lists
the stations when the last one with track already dropped them), `join:
false` (stand-alone systems such as monorails, whose ends must not be tied
to a neighbouring railway), `min_maxd_m`, and `kind`. Omitted kind is
`closure`. `kind: "relocation"` also stamps `valid_from` onto the new
alignment through a `retirements` entry (only when a bbox selects exactly
the new features and no unmoved station) and joins the old alignment only
to track valid before the switch. `opening`, `suspension` and `resumption`
stamp the current line when it is still in the package, or copy the named
release when it is not. `station_closure` copies named stations from that
release; `station_opening` stamps `match.targets: ["stations"]` so the open
line is not dated. `operator_transfer` needs `to_operator` and copies the
old operator's release even where it lies on the successor. Optional
`service_validity` / `infrastructure_validity` (`[from, to]`) are written
through only when the event states them; a closure that states neither
keeps today's `valid_to` key alone.
Stations of an event's line within 2 km of its emitted track go into the
overlay unless the same station on the same line is still within 300 m;
junction platforms of the retired line (屋代 on 屋代線) are kept, without
the group code, so a ride naming the line finds an endpoint and the open
lines' transfer group is untouched. A station shared by two events keeps
the later date.

## H1 source database and review pipeline

The source ledger now has `source_schema_version: "2"` and a `temporal_events`
collection. Runtime output remains schema v1. New source events carry stable
corridor, alignment and service identity IDs, an exact-day precision marker,
primary evidence, verified review status and a geometry licence decision.
`before`/`after` describe identity changes. `service_periods` can contain several
disjoint half-open intervals; the compiler emits one feature variant per period.
Station and section dates are compiled together. Partial openings require an
isolated selector; whole-current-line stamps require explicit `whole_identity`.

Geometry can reference an old N02 release with a historical identity and selector.
The compiler preserves that surveyed geometry instead of presenting today's
alignment as an older survey. Historical station names can be selected separately.
An identity transfer with an earlier relocation can use
`geometry.historical_periods`. Each entry supplies its own `service_period`,
N02 release, historical identity, isolated selector, alignment ID, licence
decision and exact-day evidence. The periods must cover the entire predecessor
interval contiguously, ending on the transfer day. The compiler preserves each
surveyed alignment and station name, while stamping the current successor once.
Shared boundary stations are explicitly referenced rather than emitted twice.
Same-alignment identity events bypass geometric novelty filtering. Split/merge
memberships must each have explicit identities and selectors. Relocated stations
require explicit old geometry. Conflicting current-feature stamps fail compilation;
compatible stamps are ordered so the v1 loader produces their interval intersection.

The official source inventory retains all 121 opening rows and 78 closure rows
from MLIT's 2026-04-01 tables. A source row remains unresolved until its geometry,
station scope and applicability are reviewed; having an exact official date alone
is not coverage. Reviewed identity-event seeds are a separate queue. Snapshot
inventory, differences and event matches are discovery artifacts, never exact-day
evidence or automatic approval.

```sh
python3 app/scripts/railway/history/import-mlit-history.py --check
python3 -m unittest discover -s app/scripts/railway/tests -p 'test_jp*.py'
python3 app/scripts/railway/build-jp-rail-history.py --revision 2026-09-28.3
python3 app/scripts/railway/history/audit-jp-history-coverage.py \
  --official-inventory app/data/jp-history-sources \
  --json-report app/data/generated/jp-history-coverage-report.json
node app/scripts/railway/history/verify-jp-history-boundaries.mjs
```

The strict milestone audit adds `--require-official-inventory --strict` and
intentionally fails while national coverage remains unresolved. Normal CI checks
shipped-source integrity and boundary regressions without claiming H1 completion.
See [the full H1 plan](jp-history-h1-plan.md).

Station entities and their dated name/operator/line memberships are generated by
`history/build-jp-history-stations.py` into
`app/data/generated/jp-history-stations.json`. Explicit reviewed identities take
precedence over observed N02 group codes. Uncoded observations retain provisional
geometry identities; equal names alone never merge stations.

To refresh all annual discovery queues from private downloaded N02 archives:

```sh
python3 app/scripts/railway/history/build-jp-history-review-queue.py \
  --source-dir /path/to/private/n02-archives \
  --extra-snapshot /path/to/private/N02-25_GML.zip \
  --events app/scripts/railway/jp-rail-history-events.json \
  --provenance app/data/jp-history-sources/n02-provenance.json \
  --output app/data/generated/jp-history-annual-review-report.json \
  --queue-dir /path/to/private/review-queues
node app/scripts/build/build-port-fixtures.mjs --only=historical-routes.json
swift test --package-path ios/RailKit --filter RailHistoryPackageTests
```

Route fixture generation uses a separate process per route to bound memory. It
compares the Web and offline solvers independently and checks availability before
and on every reviewed whole-identity opening; Swift consumes the same fixtures.
Opening endpoints pin the surveyed N02 station membership codes, so another line
in the same station group cannot substitute for the unopened membership. Where an
official boundary is a track junction rather than a station (富山駅南北接続線),
the regression uses the nearest real passenger station on the connecting branch.
These checks validate the shipped events, not the unmatched nationwide inventory.

The 1996 unified-text adapter preserves missing operator fields and source
anomalies. Its normalized geometry remains private until the legacy download's
redistribution terms are established. It cannot establish the 1993–1996 railway
network by extrapolation. N05 geometry is not shipped under its noncommercial terms.

Legal closure and last rail service are distinct. Ueno monorail, Iwaizumi, Hidaka
and coastal Ofunato retain legal dates in the source but compile dated rail-service
periods. Ofunato uses a pre-BRT survey. Hidaka's January–February 2015 southern
resumption is selected from the surveyed alignment at 静内. Where a disruption
began during a day, the date-only interval ends on the first wholly unserved day;
this policy is recorded explicitly. No legal closure date is treated as proof of
physical demolition.

## Known gaps (accepted 2026-09-23, from the independent review)

- **Station snapping** (closed 2026-09-23): endpoint station candidates are
  filtered by ride date with the same half-open rule as edges, in both
  solvers (`filterStationCandidatesByRideDate`).
- **Both solvers keep every equal-distance platform membership and emit one connector per pair, with validity the intersection of the two memberships.**
- **Cross-border cache keys include every region the journey names.** The Web
  and iOS derive that scope from the declared region, stop codes and route
  section endpoint codes, then canonicalize the revision token in sorted
  region-code order. A domestic North American ride keys on one region; a
  cross-border ride keys on both. An absent optional overlay is written as
  `none`.
- **The Web app and offline precompute load history before solver install.**
  Station additions and retirement dates are present before station indexing;
  section additions and the strict unmatched-retirement check run before the
  route graph sees the collection. Precomputed route parts carry
  `solver_context` (`solver_version`, route-cache digest, normalized ride date
  and per-region history revisions), and the manifest records the common
  solver version and revisions.
- **A promised overlay fails closed.** Schema corruption, invalid dates or
  bounds, duplicate/colliding ids and unmatched retirements abort Web boot or
  offline precompute. Regions with no listed overlay continue with a `none`
  revision.
- **Statistics** already index temporal geometry in both ports, distinguish
  retired and relocated mileage, and keep historical variants out of the current
  network denominator. Source coverage and route/display acceptance remain
  separate checks; the generated audit does not claim end-to-end coverage from
  feature availability alone.

Partial openings use `isolated_current_segment` with complete surveyed section
features and a new-station allow-list. A declared `predecessor_event_ids` dependency
limits equal-geometry old identity variants to the opening interval. Dependencies
are explicit and fail compilation if the identity or geometry cannot be matched.
An existing shared boundary platform retains its earlier service interval.

Dated name-only endpoints with explicit line and operator constraints cannot fall
back to another operator’s same-name station when every membership of the requested
identity is unavailable on that date. Explicit station codes retain their existing
physical-identity behavior. Web and native solvers apply the same rule.

For a dated endpoint carrying a stable station code and a known written name,
if the same-name members are all unavailable, the solver can use date-valid
aliases from that same code. This permits current catalog names such as
大阪梅田 and 京都河原町 to reference their verified pre-rename platform identities.
Unknown name/code combinations keep the existing name fallback; undated
resolution keeps its existing name preference.
