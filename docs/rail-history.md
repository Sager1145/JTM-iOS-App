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
        "N02_001": "11", "N02_002": "1",
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
- Every entry has `valid_from` and/or `valid_to` (`YYYY-MM-DD`). Interval is
  half-open: valid on `valid_from`, no longer valid on `valid_to`.
- `retirements[].match` selects current-package features (sections and
  stations alike) whose `line_name` and `operator` match exactly and whose
  every coordinate lies inside `bbox`. Matching features receive the entry's
  `valid_from`/`valid_to`. A retirement that matches nothing is a data error
  the loader reports.
- `revision` is folded into the route cache key. Bump it whenever the file
  changes.
- Ride date rule: dated ride uses edges valid on that date; undated ride uses
  only edges with no `valid_to`.
- Sources: N02 releases as permitted by their licence, and official abolition
  notices. N05 derivatives need a separate licence check before shipping.

## Known gaps (accepted 2026-09-23, from the independent review)

- **Station snapping ignores validity.** Only rail edges and transfer
  connectors are dated. Once an overlay ships retired stations that share a
  name with active ones, `collectStationCandidateGraphNodes` can fill its
  candidate cap with dead nodes. Filter candidates by ride date before adding
  such stations.
- **Connector validity comes from the nearest station feature.** At a junction
  where a retired line's platform is nearer to a node than the active line's,
  active-to-active transfers inherit the retired `valid_to`. Safe for the seed
  (函館線 precedes 留萌線 at 深川 with identical geometry).
- **Cross-border cache keys use the home region's revision only.** A change to
  a neighbouring region's overlay does not invalidate cached cross-border
  rides. No us/ca overlay exists yet.
- **Web app and precompute do not load the overlay.** `app-rail-history.js` is
  not in `index.html`; precomputed dataset parts are solved without
  retirements and are accepted by iOS because both digests are Swift-side.
- **A broken overlay fails open.** Decode errors are logged and the region
  solves on the undated network under `history:none`. Surface this in the UI
  before shipping a second overlay.
- **Statistics** still index only `rail-sections*.json`; mileage on retired
  segments and the historical/active coverage split are not implemented.
