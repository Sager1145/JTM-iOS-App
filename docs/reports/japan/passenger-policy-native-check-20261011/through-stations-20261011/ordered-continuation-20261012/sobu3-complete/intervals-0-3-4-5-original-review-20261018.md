# Sobu-3 intervals 0, 3, 4, 5: original-image continuation

2026-10-18. Exact owner: `jp-東日本旅客鉄道-総武線-3`. Read-only continuation of [queue43/44 receipt preparation](../remaining-lines-43-44-20261018.md). No app/UI/native capture, build, tests, external research, national scan or source/data change. Only this report was added.

**One concrete local offset candidate:** interval3 near Nakamagome/Minamimagome. Two shallow display controls pull the red stroke south of the visible labelled Yokosuka rail band and back toward a parallel heading. This needs own-corridor evidence before a repair; the image does not authorize substituting a neighbouring track. No acute/right-angle connection or detached station-approach hook was found in the other sampled originals.

## Evidence actually viewed

The preparation report establishes 52 expected captured views for these four intervals: #0 7, #3 20, #4 9, #5 16, with exact own source/display/from/to station identities matching their named retained immutable plans. This continuation reuses that selected-identity evidence and rereads the current four own display intervals/controls. It does not recompute current whole-line native rendering dependencies or receipt content hashes. Legacy isolated-centreline z17/light/1024×768/1× evidence is not silently admitted under the newer capture contract.

Viewed **20 unmodified original images: ten `smooth.png` / `basemap.png` pairs**, not contact sheets or redrawn crops. Exact absolute capture root:

`/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/`

Every directory in the table contains the two explicitly viewed filenames `smooth.png` and `basemap.png` beneath that root.

| Interval | Exact directory | Scope and original-pixel finding |
| --- | --- | --- |
| #0 | `005751/000000` | Tokyo underground Sobu anchor west of the surface JR platforms. Red starts independently on the west station-side corridor; no visible hook. Do not move it to surface Chuo/Tokaido/Shinkansen bands. Hidden platform extent is unmeasured. |
| #0 | `005751/000003` | Yurakucho/highest own control. The red underground route changes heading gently and crosses relative to the separate surface rail band. No right angle or local break is visible. Surface cartography cannot measure this tunnel's exact axis. |
| #0 | `005751/000006` | Shimbashi endpoint/adjacent own continuation. Red is longitudinal and continuous in the station viewport; no visible endpoint barb. Broad blue/purple shading does not identify the exact underground passenger-platform faces. |
| #3 | `005754/000000` | Nishi-Oi approach. Red remains longitudinal in the labelled Yokosuka corridor with no visible detached station spur. Parallel-track/platform-centre identity remains unresolved at this scale. |
| #3 | `005754/000005` | **Concrete candidate:** a southward dip below the visible Yokosuka corridor near Minamimagome before red returns to a broadly parallel heading. The two shallow controls below identify the local support window; no right-angle connection is present. |
| #3 | `005754/000019` | Musashi-Kosugi approach. Red follows the separate north–south Yokosuka station corridor rather than the crossing Nambu track or western Toyoko corridor. No obvious sharp station hook. Exact own platform midpoint is not certified. |
| #4 | `005755/000000` | Same Musashi-Kosugi own station/approach from the outgoing interval. Red remains longitudinal through the own corridor; no new visible seam or false turn onto Nambu. The image includes clipped complete-own-line geometry, not only the one interval. |
| #4 | `005755/000008` | Shin-Kawasaki endpoint/continuation. Red crosses the station longitudinally without an obvious hook. It stays independent of the eastern Nambu corridor and western yard fan. Broad station/track shading limits precise placement. |
| #5 | `005756/000011` | Motomiya curve approaching the Tsurumi corridor. Red follows the gradual visible curve; no acute turn into the separate diagonal Keihin–Tohoku band is visible. A cartographic convergence does not prove track connectivity or precise source ownership. |
| #5 | `005756/000015` | Named-section endpoint at Tsurumi. Red ends longitudinally within the multi-track station area without an obvious sideways barb. This package section end is not proof of an operating service terminus or of the exact platform pair used by every train. |

These are ten sampled viewports out of 52, not a claim that every pixel of all four intervals was reviewed. Original `view.json` and `capture-state.json` remain beside each pair. Whole-own-line smoothing before clipping can show adjoining intervals in the station viewport; it does not establish production follows/family/parallel lane composition.

## Exact controls behind the concrete candidate

Current expanded **display** interval3, zero-based vertex indexes:

| Vertex | Coordinate [longitude, latitude] | Local deflection | Incoming / outgoing legs |
| --- | --- | ---: | ---: |
| 12, retained outer support | `[139.7116,35.59321]` | — | — |
| 13, suspected local support | `[139.70858,35.59237]` | 16.6153° | 288.9281 / 55.5949 m |
| 14, suspected local support | `[139.70808,35.59208]` | 17.1794° | 55.5949 / 24.7925 m |
| 15, retained outer support | `[139.70782,35.59201]` | — | — |

The numbers are local equirectangular control/leg measurements, not Apple pixel residuals. The matched original pair is `005754/000005/{smooth.png,basemap.png}`. The visible dip warrants a bounded check against the owner's surveyed passenger alignment and neighbouring parallel tracks. No control removal, new coordinate, lane adjustment or geographic repair is authorized solely by these pictures. Preserve station IDs, canonical geometry/km and surrounding supports while researching this candidate.

The highest current interior-display deflection in each queried interval is #0 **10.6709°** at vertex15 `[139.7607037,35.6721994]`; #3 **17.1794°** at vertex14 above; #4 **7.8704°** at vertex13 `[139.66761,35.56174]`; #5 **8.1783°** at vertex31 `[139.68132,35.51959]`. Only this exact owner and these four intervals were queried. The #4 high-control viewport `005755/000004` was not inspected here; its numeric lead alone does not establish a defect.

All four maxima are below the new structured sharp-turn candidate threshold of 20°. The visible #3 offset is therefore an example of why the existing line-offset and station-approach reviews remain necessary alongside sharp-turn candidates. It does not justify changing that threshold or running a national angle campaign.

## Result and limits

Retain the interval3 local offset as a concrete research candidate. The ten viewed originals provide no additional visible wrong acute/right-angle join or station-approach barb. No full-line acceptance, exact underground platform-centre claim, physical track connection, current Main display verdict or source repair was made. The next useful work is bounded own-track source evidence for interval3 vertices12…15, not a fresh national scan or recapture of all retained views.

## Bounded existing-source provenance follow-up

The suspect controls have an exact attributable origin, rather than being generated by smoothing. In `app/data/rail-sections.json`, **feature index16210**, `LineString` with **84 vertices**, carries `N02_001='11'`, `N02_002='2'`, `N02_003='東海道線'`, `N02_004='東日本旅客鉄道'`. Its source field identifies processed MLIT N02 2025 data. Feature vertices9…12 are exactly display interval3 vertices12…15 listed above, including both suspect supports. Feature endpoints `[139.72124,35.60085]` / `[139.66332018,35.57602227]` are the Nishi-Oi–Musashi-Kosugi station-section seams. The corresponding source station features7628/9944 identify station codes004235/004301 as JR East 東海道線 西大井/武蔵小杉. Current package `railwayIdentity='jp-東日本旅客鉄道-総武線'` is the compact display identity; interval3 has **no display override**. Existing Tokyo tunnel/display overrides apply to intervals0/1/2, so they did not manufacture this dip.

The already-retained secondary geometry cache exists at `/Users/sager/Documents/GitHub/Japan-Train-Map/outputs/osm-basemap-cache/E139N35.json`. The existing [southern-branch evidence registry](/Users/sager/Documents/GitHub/JTM-iOS-App/app/scripts/railway/tokyo-southern-branches-overrides.json) records this cache, ODbL attribution and primary operator/JRTT topology references. Its `fetchedAt` is `2026-08-18T10:37:59.411Z`, endpoint `https://maps.mail.ru/osm/tools/overpass/api/interpreter`; this review made no network request and did not recompute the full-cell hash. Only ways intersecting the local control window `[139.707,35.5915]–[139.712,35.5938]` were inspected. The cached way objects carry no version fields; live current revisions were not checked.

In that window, [cached OSM way365183512](https://www.openstreetmap.org/way/365183512) and [way751605913](https://www.openstreetmap.org/way/751605913) both explicitly carry `name='東海道本線（品鶴線）'`, `operator='東日本旅客鉄道'`, `railway='rail'`, `railway:traffic_mode='passenger'`, `usage='main'`, `gauge='1067'`. Thus the reference is identified as the own JR East passenger Hinkaku/Yokosuka corridor, not selected simply because it is near the red line. Way365183512 additionally has `oneway=yes`; this is not converted into a legal railway up/down designation. Neither way has a tunnel tag in the retained response; absence of a tag alone does not establish grade.

Their bounded exact source supports around the suspect controls are:

- way365183512: `[139.7087699,35.5924257]` → `[139.7083831,35.5922928]` → `[139.7080861,35.5921906]` → `[139.7076708,35.5920487]`.
- way751605913, opposite stored order: `[139.7079062,35.5921693]` → `[139.7080646,35.5922179]` → `[139.7083726,35.5923255]` → `[139.7087588,35.5924516]`.

Both describe the gradual same-corridor bend without the N02 v13→v14 southward jog. A bounded point-to-segment comparison against each **separate named own track**, with no averaging or whole-line fit, gives:

| Current display control | Distance to cached own way365183512 | Distance to cached own way751605913 |
| --- | ---: | ---: |
| v13 `[139.70858,35.59237]` | 0.979 m | 2.399 m |
| v14 `[139.70808,35.59208]` | 11.137 m | 14.855 m |
| v15 `[139.70782,35.59201]` | 9.204 m | 13.792 m |

These are local reference residuals, not Apple pixel measurements or accuracy guarantees for OSM. In particular, v15 is only a retained source support, **not** a proven correct replacement seam. Parallel nearby cached ways365183499/500/503 are explicitly JR Central 東海道新幹線, `gauge=1435`, `highspeed=yes`, with bridge/layer metadata; they were distinguished and excluded as replacement geometry. Short own Hinkaku bridge ways365183536/541 east of the immediate controls likewise retain their separate `bridge=yes,layer=1` identity; no junction is inferred from the apparent crossing.

**Interpretation:** the attributable local N02 shape and independent named own passenger-track supports favour a sparse/coarse source offset over an intentional underground detour at v13/v14. This area is not the Tokyo tunnel whose separate geometry must be preserved. The retained evidence does not establish a new physical connection, resolve every grade level, or choose an authoritative replacement track/seam. A repair remains unproposed; any later display correction must retain one attributed own track, review both ends of the bounded support window, preserve canonical/km/identities and then inspect the actual result.
