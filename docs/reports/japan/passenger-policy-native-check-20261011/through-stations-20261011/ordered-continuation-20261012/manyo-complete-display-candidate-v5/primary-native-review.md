# Manyo V5 primary Inspector native review receipt

Reviewed: 2026-10-13
Evidence: `docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/manyo-complete-display-candidate-v5/native-candidate/primary`

## Coverage

All actual captures were opened: 23 viewpoints × basemap/display/smooth = 69 panels, all 1024×768 and visibly loaded. No blank/loading-grid panel was present. Every `view.json` has line ID `jp-万葉線-高岡軌道線` and whole-line render dependency `114cbbc6f6271f6da6d730288dfb502ef621b1fea727a153663b08bfc777adc7`.

- #5: 2 views, `captures/000435/000000..000001`
- #6: 3 views, `captures/000436/000000..000002`
- #7: 3 views, `captures/000437/000000..000002`
- #8: 2 views, `captures/000438/000000..000001`
- #10: 3 views, `captures/000425/000000..000002`
- #11: 3 views, `captures/000426/000000..000002`
- #12: 2 views, `captures/000427/000000..000001` (actual V5 plan count; supersedes the old three-view expectation)
- #13: 3 views, `captures/000428/000000..000002`
- #14: 2 views, `captures/000429/000000..000001`

## Result

ACCEPT for the primary Inspector native candidate scope.

Across all nine complete intervals, display and smooth remain on the visible Manyo tram/rail corridor. Endpoints and short tails are present, interval seams are continuous, and no new zero edge, disconnected fragment, foldback, road-block shortcut, or smoothing chord across a local bend is visible.

The five V5 own-frame station seams were checked in the corresponding native frames:

- 001826: #5 view 1 (`000435/000001`) into #6 view 0 (`000436/000000`): the endpoint lies on the named corridor and the smooth continuation has no cusp or lateral hook.
- 001834: #7 view 2 (`000437/000002`) into #8 view 0 (`000438/000000`): both sides meet on the same diagonal corridor without a gap or return.
- 001845: #10 view 2 (`000425/000002`) into #11 view 0 (`000426/000000`): the local curve remains continuous through the stop marker.
- 001851: #11 view 2 (`000426/000002`) into #12 view 0 (`000427/000000`): the V4 road-gap placement is absent; the route and smooth line remain on the visible corridor through the own-frame stop.
- 001861: #13 view 2 (`000428/000002`) into #14 view 0 (`000429/000000`): the bend and seam are continuous with no corner spike or short cap.

WARNING: Apple renders much of this street-running railway as a thin shared street/transit symbol rather than surveyed rails or distinct platform footprints. These panels support the selected cartographic corridor, own-frame stop placement, and continuity, but do not establish physical platform-centre or metre-level survey accuracy. This receipt is Inspector-only and makes no Main endpoint-dot claim.
