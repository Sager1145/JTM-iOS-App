# Katsuyama Eiheiji interval6 own-source review — 2026-10-18

**Own corridor attribution and a connected source chain are established; no repair candidate is taken yet.** The raw northern curve and east station controls differ from that own source. The actual Echizen-Shimabashi platform faces and appropriate display endpoint remain unresolved, so a midcurve splice that simply returns to old13/14 would conceal a known station-approach issue. No geometry/source-owner edits, app/native action, build, tests, candidate export or apply were performed.

Source files and scoped calculations are retained in `interval-6-own-source-20261018/`. `own-source-comparison.json` records exact source URLs/byte hashes, node IDs, way versions, route members, all15 old controls and existing-geo-helper projections. This is a source comparison, not an Apple pixel residual or independent survey.

## Current own source and adjacent guards

Own `jp-えちぜん鉄道-勝山永平寺線` interval6 is 東藤島002649 `[136.269855,36.08663]`→越前島橋002642 `[136.277265,36.09012]`, physical0.783km,15 decoded controls. Current6 has no display interval/station override: its observed north offset is already in canonical raw N02, not a new render alias. Feature161 (N02_00112/N02_0025, own line/operator) reversed equals decoded1..13 exactly. East station feature154 is the two-point segment `[136.27684,36.09004]`→`[136.27769,36.0902]`; the exact midpoint is current station14 `[136.277265,36.09012]`. It is an N02 station-segment centre, not a verified platform face.

West station similarly derives from own station feature159 `[136.27019,36.08679]`/`[136.26952,36.08647]`. Adjacent interval5 ends at 東藤島, with last physical supports `[136.26945,36.08644]`, `[136.26952,36.08647]`, then the station midpoint. Interval7 starts at the same 越前島橋 station midpoint, then `[136.27769,36.0902]`, `[136.27788,36.09025]`, continuing to 観音町002639. Own raw features129/154/156/159/161 and compact rows5/6/7 plus station rows5..8 are frozen in `raw-own-interval-input.json`; no physical points, IDs or mileage were changed.

## Positive own identity and exact primary objects

Cached source `railway-sources/local/osm/degree-cells/E136N36.json` was fetched2026-08-18T10:31:59.026Z. Only seven explicitly own nearby objects were selected; no nearest-rail blending. Their scoped cache rows are retained in `cached-own-ways.json`. All seven geometries equal fresh exact-object full-node API responses point-for-point.

| Own object | Version/date | Role in bounded evidence |
|---|---|---|
|24373397|v5,2025-07-05|Own interstation curve through 東藤島;21nodes, reverse its stored east→west order for eastbound geometry.|
|1412418313|v1,2025-07-05|Own bridge link264459006→264458983 eastbound.|
|1412418312|v1,2025-07-05|Own link264458983→264458970 eastbound.|
|1017340560|v1,2022-01-01|Own station track264458970→264458968→264458954; station node264458968 lies on it.|
|1017340561|v1,2022-01-01|Parallel own station track between the same two switches, south of0560. Not silently classified as non-passenger/siding.|
|332270250|v2,2022-01-01|Own eastward continuation264458954→264458956.|
|424071505|v4,2022-01-01|Adjacent own continuation beyond264458956 toward 観音町; retained for adjacent-station identity, not a new repair extent.|

The exact connected eastbound chain24373397(reverse)→1412418313(reverse)→1412418312(reverse)→1017340560(forward)→332270250(reverse) shares actual node IDs at every join. All carry `railway=rail`, gauge1067, own name/operator, usagebranch, no service tag;1412418313 is bridge=yes. Their geometry has KSJ2 ancestry, so live object freshness does not imply independent survey accuracy.

The complete [station-way relations response](https://api.openstreetmap.org/api/0.6/way/1017340560/relations.json) returns own railway relation1871694v23 (2026-07-17), with own station stop nodes264458968/264458989 at zero-based14/15 and ways1017340560/1412418312/1412418313/24373397 at64..67,332270250 at68,424071505 at71. Its tag is `route=railway`, not a directional `route=train`; member order is not used as proof of an ordered train itinerary. Station track1017340561 is absent from that returned relation, but absence does not prove it lacks passenger use. The exact named line/stop membership plus the operator's [東藤島](https://www.echizen-tetudo.co.jp/station/7.html) and [越前島橋](https://www.echizen-tetudo.co.jp/station/8.html) pages establish this passenger corridor: E7/E8 on 勝山永平寺線, with Fukui/Katsuyama passenger timetables. Two official HTML responses are retained; no platform diagram or georeferenced station-face image was accepted here.

Fresh source acquisition was restricted to seven known way/full responses, that one directly necessary way/relations response, and the two official station HTML pages. Full originals preserve OSM attribution/ODbL notices, node versions/coordinates and way metadata. No bbox/whole-line/network acquisition or neighboring JR/Fukutetsu/Mikuni geometry was used.

## Offset witnesses, including east13/14

Projections use existing `jp-manual-corrections/geo.mjs` `projectPointOntoPolyline` onto that positively attributed own chain; distances are equirectangular source comparisons.

| Old control | Own-chain offset | Own projected coordinate |
|---|---:|---|
|5 `[136.27202,36.08785]`|6.239m|`[136.27206284838482,36.08780585030709]`|
|6 `[136.27277,36.08837]`|10.191m|`[136.2728393550264,36.08829748716871]`|
|7 `[136.2733,36.08874]`|13.619m,largest|`[136.27339267893626,36.088643087201675]`|
|8 `[136.27404,36.08919]`|12.580m|`[136.27412504873067,36.08910013821294]`|
|9 `[136.27444,36.08942]`|11.095m|`[136.27451015651232,36.08933788643423]`|
|12 `[136.27591,36.08989]`|6.719m|`[136.27592620849558,36.08983101250351]`|
|13 `[136.27684,36.09004]`|4.602m|`[136.27685151842368,36.08999967236129]`|
|14 station `[136.277265,36.09012]`|4.662m|`[136.27727677991945,36.090079169472524]`|

Actual own OSM station node264458968 is `[136.2771814,36.0900612]`,9.959m from the current N02 midpoint (haversine). This includes along-track displacement; it is not a9.959m lateral error. Projected own-chain location at old14 is a different point again. East adjacent interval7 controls0/1/2 have source offsets4.662/4.654/6.193m: the east approach concern crosses the shared station boundary. Returning unchanged to13/14 or moving only one interval endpoint therefore cannot be assumed coherent. West station node264458989 `[136.2698858,36.0866145]` is3.260m from its N02 midpoint, whose own-chain perpendicular distance is2.750m.

The positively identified source retains the real northeast compound curve; it is not a straight replacement chord. Neither the visible north difference nor these comparisons authorize flattening the bend or snapping to streets, canals, expressway, nearest JR track or another Echizen line.

## Station and candidate limit

Two own station tracks and an OSM railway=station node establish railway identity and plausible station area, not the exact passenger face/cap, stopping track choice or physical display centre. The viewed standard blue station fill also cannot resolve those. Actual own station faces remain **unresolved**, for both endpoints and particularly the eastern paired tracks. No chosen display station coordinate, splice window or candidate fragment is provided.

A later bounded proposal must account for old13/14 and adjacent interval7's shared station approach using attributable own station evidence, while preserving physical station identity/mileage and the genuine compound curve. This source investigation supplies precise own supports and isolates the unresolved station dependency; it does not force a repair or declare whole-line acceptance.
