# 津島線 #4–#6 display-only proposal V3

Status: **proposal only**. V1 remains rejected and V2 remains an unaccepted proposal. This V3 changes no physical N02 coordinates, station rows, IDs, kilometres, topology, source package, or production resource.

## Actual evidence opened

The complete baseline triples were opened for all three Inspectors:

- Interval #4 青塚→勝幡: 6 viewpoints per app, 18 viewpoints / 54 basemap-display-smooth panels.
- Interval #5 勝幡→藤浪: 5 viewpoints per app, 15 viewpoints / 45 panels.
- Interval #6 藤浪→津島: 6 viewpoints per app, 18 viewpoints / 54 panels because the 藤浪 station midpoint was not valid at the old coordinate.

Total: 51 viewpoints and 153 panels. The immutable source paths, map rectangles, and SHA-256 basemap receipts are in `evidence-receipts-v3.json`. Static inspection found no second concrete excursion in the unchanged body of #4 or #6. Their existing bodies and remote endpoints remain exact.

## 勝幡 005375 frame

In both #4 view 5 and #5 view 0, the own Meitetsu station frame is the broad translucent diagonal group around the same labelled paired railway. Its longitudinal short-edge centres are approximately:

- southwest: pixel `(451,419)`
- northeast: pixel `(627,319)`
- longitudinal midpoint: pixel `(539,369)`

The midpoint projects through the recorded `MKMapRect` to:

```text
[136.75066467857357, 35.19537651279661]
```

The old shared source coordinate is about 30.15 m southwest of this cartographic midpoint. V2's normal projection at `(508,377)` put the point on the rail but did not solve longitudinal station placement. V3 uses the frame midpoint as the exact shared display endpoint of both #4 and #5. Interval #4 preserves source indexes 0–14 and replaces only its endpoint; #5 departs from the same tuple along its already traced own rail, so there is no return to the old anchor.

## 藤浪 005396 frame

In #5 view 4 and #6 view 0, the own station frame is the diagonal translucent group crossing south-west to north-east. Its longitudinal bounds are approximately:

- southwest: pixel `(466,430)`
- northeast: pixel `(580,316)`
- longitudinal midpoint: pixel `(523,373)`

The midpoint projects to:

```text
[136.73903301719668, 35.18892645035355]
```

The old shared coordinate is about 15.18 m southwest of the frame midpoint, so retaining it was not defensible under the station-middle rule. V3 expands through #6: #5 source indexes 8–16 remain exact before ending at the midpoint, while #6 starts at the identical tuple and preserves source indexes 1–20. The following rail direction is continuous and does not bend back to the old point.

## Candidate structure and uncertainty

`candidate-v3.json` contains complete display arrays for intervals #4, #5, and #6 and shared aliases for both stations. `candidate-v3.geojson` contains exactly those three complete candidates. Orange reprojections are provided for every one of the 51 source views; red shows the unchanged physical/source line.

The platform/frame edges are partly covered by the line label and translucent station fill. Each midpoint therefore carries an estimated ±6 px longitudinal uncertainty (about ±5.8 m at the recorded scale). The bridge's label-free lateral controls retain the narrower V2 estimate. These are representative Apple cartographic placements, not surveyed platform or track coordinates. Native grooming, smoothing, endpoint retention, and Main rendering remain unverified.

