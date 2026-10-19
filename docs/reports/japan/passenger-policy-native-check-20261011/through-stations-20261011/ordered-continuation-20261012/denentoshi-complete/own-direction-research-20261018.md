# 田園都市線 own-direction research — 2026-10-18

Scope: `jp-東急電鉄-田園都市線`, own interval #3 駒沢大学→桜新町, disputed control `[139.65374,35.63029]`. Read-only production research. Applied the railway audit and Matt research practices; no nested workers, app operations, builds, tests or production data edits.

## Decision supported by the evidence

A real own-line compound turn exists at the 新町 old/new-road fork. The visible sharp low point is an under-resolved representation question, not sufficient evidence that the whole turn is false. Preserve the genuine heading change. Exact own-direction OSM references can support a bounded display proposal with explicit attribution; neither these references nor Apple cartography establish surveyed tunnel coordinates. No geometry was applied or accepted here.

## Primary Tokyu engineering source

Tokyu's [新玉川線建設史 publication index](https://www.tokyu.co.jp/history/shintamasen/) identifies its August 1980 construction history. In [土木編](https://www.tokyu.co.jp/history/shintamasen/pdf/shintamasen_chapter06.pdf), printed p171 (PDF page13) describes the 新町新旧道分岐点 (5K600m)→用賀専用道入口 (7K100m) section, stacked tunnels and entry from Route246 into the ward road. It specifies compound radii300m/750m for both directions. The horizontal-curve rows of 新玉川線線路縦断図(2), PDF page10, distinguish R300/750 and R315/750, with labelled intersection angles43°56′13″ and44°25′14″. These are substantial rounded bends, not zero-radius corners. The profile is useful engineering evidence but contains no recovered WGS84 control points; its drawn chainage positions were not digitized as exact tangent limits. This is historical construction evidence, not a current track survey. See retained full page010, printed-page171 image and readable chainage crop in the sources directory.

The route-map chapter and first eight pages of the track chapter were also inspected. They did not supply the needed georeferenced horizontal controls; no precision is inferred from their diagram strokes.

## Current own N02 source, independently downloaded

The [official N02-2025 data page](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html) identifies the2025-12-31 snapshot, JGD2011 geographic coordinates and CC BY4.0 terms. The [original archive](https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-25/N02-25_GML.zip) was freshly downloaded. Its `UTF-8/N02-25_RailroadSection.geojson` contains exactly one own feature through this control, selected by explicit `N02_004=東急電鉄`, `N02_003=田園都市線`, never nearest geometry. All19 feature controls exactly equal one current feature in `app/data/rail-sections.json`.

The local triple is `[139.65464,35.63056]`, `[139.65374,35.63029]`, `[139.65329,35.63035]`. A local equirectangular calculation gives29.5750° deflection and86.8015m/41.2601m incident edges. The archived own `view.json` repeats the control. Thus the sparse angular control is already present in the official source; source equality does not prove its physical accuracy. Fragment/capture index numbers are array-local (official feature index8, clipped captured source array index7) and do not redefine the parent's full-interval vertex numbering.

Saved: `mlit-N02-25-own-interval03-fragment.json`, `own-source-comparison.json`. The original legacy images reviewed were `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004299/000002/smooth.png` and its associated metadata. No current-render acceptance is inferred from this historical zero-lane image.

## Own-direction OSM reference controls

The [OSM original map API response](https://api.openstreetmap.org/api/0.6/map?bbox=139.651,35.629,139.657,35.632) contains two own tunnel ways with `name=東急田園都市線`, `operator=東急電鉄`, `ref=DT`, `railway=rail`, `tunnel=yes`, `oneway=yes`. Their identity is independently explicit; their geometry has **KSJ2 ancestry**, so it is not an independent survey. © OpenStreetMap contributors, [ODbL attribution/licence](https://www.openstreetmap.org/copyright).

| Direction established by actual relation membership | Own way/version | Local reference result |
| --- | --- | --- |
| [relation9341815](https://www.openstreetmap.org/relation/9341815), 渋谷→中央林間 | [169057662](https://www.openstreetmap.org/way/169057662), v25 | Ten copied east→west controls; largest local discrete turn8.1048° |
| [relation404834](https://www.openstreetmap.org/relation/404834), 中央林間→渋谷 | [671715587](https://www.openstreetmap.org/way/671715587), v21 | Ten copied controls, reversed only for comparison; largest local discrete turn10.5415° |

Both way versions are dated2026-10-05. Way169057662 additionally says National-Land Numerical Information2007. Each has `tracks=2` alongside `oneway=yes`; do not infer a surveyed individual rail from these tags. The route membership establishes passenger direction, not geometric accuracy.

For the interval's westbound direction, exact way169057662 controls around the apex are:

```json
[[139.6543078,35.630447],[139.653931,35.6304014],
 [139.653755,35.6303862],[139.6534793,35.6303874],
 [139.6533169,35.6303966],[139.653081,35.630412]]
```

The full bounded fragment runs `[139.6561896,35.6309022]`→`[139.6513427,35.6308359]`. Its lowest latitude is about10.7m north of the old N02 apex's latitude at a nearby longitude; this is a latitude difference, not a proved normal error. The opposite direction is separate, with its own controls, and was not averaged into this one.

Saved `osm-own-direction-reference-fragments.json` preserves every copied nodeID, coordinate, source tag and relevant relation membership. It is an actionable attributed reference input for the parent's candidate work, not an integrated repair. `osm-local-railways-extracted.json` retains full own ways; original `osm-api-local-map.xml` is preserved. Overpass returned HTTP406; the official OSM API succeeded. No OSM write occurred.

## Candidate boundary and remaining question

A local rounded display proposal can use the identified westbound reference while preserving the real compound turn, own station endpoints, IDs, mileage and topology. It still needs explicit joining choices and parent review of the complete affected interval/current renderer. Do not describe the OSM geometry as independent surveyed corroboration, blend the two directions silently, or use the nearest Apple-blue stroke as tunnel authority. The engineering source constrains the bend's existence and scale; the exact contemporary centreline remains reference-assisted.

Downloads and derivatives are listed in `own-direction-sources-20261018/sources.json`. Original downloads total about420MB, mostly the359,960,528-byte civil chapter. Original PDFs/ZIPs are preserved in /private/tmp/jtm-denentoshi-own-direction-originals-20261018/ (sources.json records exact paths); relevant page images/XML/controls remain here. They are preserved research evidence; no commit/push was performed. Validation consisted of relevant original-page/image review, exact named source-feature comparison and focused local geometry calculations only.
