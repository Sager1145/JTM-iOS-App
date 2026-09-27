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
  use (raw `N02_00x` or spelled-out); both are accepted. They are features that
  are **absent** from the current package.
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
  collection is stamped; omitted means both, which is every retirement
  shipped today. A retirement that matches nothing is a data error the
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

Not recoverable from N02: lines closed before N02-05 (名鉄岐阜600V線区,
日立電鉄線, のと鉄道能登線 穴水—蛸島, …). N02 has no dates, so the builder
emits `opening`, `station_opening`, `station_closure`, `suspension`,
`resumption` and `operator_transfer` only when the event states an explicit
date and names a release the script already reads. None of those events are
in the curated list yet, so the shipped overlay is still closures,
relocations and the 2026 retirement. BRT has no rail geometry here.
`ios/RailKit/Tests/RailCoreTests/RailHistoryPackageTests.swift` solves dated
rides on the real package (retired lines, a relocation, the 2026 retirement).

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
- **Statistics** still index only `rail-sections*.json`; mileage on retired
  segments and the historical/active coverage split are not implemented.
