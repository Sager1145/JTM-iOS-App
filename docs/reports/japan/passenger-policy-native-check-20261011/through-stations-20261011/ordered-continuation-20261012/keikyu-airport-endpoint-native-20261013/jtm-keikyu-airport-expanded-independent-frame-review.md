# Keikyu Airport Line — independent focused frame review

Date: 2026-10-13  
Scope: read-only review of Tenkūbashi and Haneda Airport Terminal 3 Apple Maps z18 station frames. This receipt does not accept source guards, candidate geometry, runtime rendering, or underground survey accuracy.

## Evidence reviewed

- `tenkubashi-z18-before/apple-map-extraction/{analysis.json,basemap.png,extracted.geojson}`
- `terminal3-z18-before/apple-map-extraction/{analysis.json,basemap.png,extracted.geojson}`
- adjoining complete interval exports: #3 view 3, #4 views 0 and 4, and #5 view 0
- `airport-tenkubashi-guard-main-{overlay,basemap}.png`
- `airport-terminal3-guard-main-{overlay,basemap}.png`
- `airport-anamori-guard-main-{overlay,basemap}.png` only as a pending guard observation

Both focused images are 999 × 654 at about 0.484 m/pixel. The #3/#4 Tenkūbashi exports and #4/#5 Terminal 3 exports reproduce the same station-frame geometry; small raster differences in some captures do not move the frame edges.

## Tenkūbashi (004373)

The Keikyu frame is the northwest-to-southeast diagonal structure carrying the `Keikyu Kuko Line` label. The steep north-south structure through the interchange is Tokyo Monorail and is excluded.

The full Keikyu frame is mildly curved/overlapped at the interchange, so a straight axis is a chord rather than a surveyed track centerline. The visually supported longitudinal end-centres in focused-image pixels are approximately:

- northwest end: **(228, 174)**
- southeast end: **(584, 421)**
- chord midpoint: **(406, 297.5)**

Inverse projection through the captured native map rect gives:

- northwest: **[139.75306856, 35.54887879]**
- southeast: **[139.75497829, 35.54780072]**
- midpoint: **[139.75402343, 35.54833976]**

Practical visual uncertainty is about ±4 px at the northwest end and ±8 px at the southeast end because the Keikyu frame overlaps the monorail/interchange shading. The midpoint is about 47.6 m from the constructed/source station coordinate `[139.754525, 35.548211]` and 39.7 m from the Apple POI; those POIs are not platform-centre evidence.

The provisional `(235,175) → (585,385)`, midpoint `(410,280)`, follows the diagonal direction but puts the southeast pick about 36 px north of the terminating short-edge centre. If the intended target is the complete own Keikyu frame, use the lower southeast end and midpoint above. Do not use the automatic platform candidates around `(460,272)` or `(491,338)`; they are unresolved interchange/monorail-side rectangles without parallel-rail support.

## Haneda Airport Terminal 3 (004382)

The Keikyu frame is the broad west-to-east, slightly descending platform rectangle above the `Tokyo Monorail Haneda Line`. The narrow lower rail pair and the steep southeast structure belong to the monorail/concourse system and are excluded.

The independently supported longitudinal end-centres are approximately:

- west end: **(296, 270)**
- east end: **(595, 320)**
- midpoint: **(445.5, 295)**

Inverse projection gives:

- west: **[139.76597434, 35.54522879]**
- east: **[139.76757830, 35.54501055]**
- midpoint: **[139.76677632, 35.54511967]**

This independently confirms Mita’s `(295,270) → (595,320)`, midpoint `(445,295)` within one pixel. Visual uncertainty is about ±4 px. The midpoint is about 30.5 m from the constructed/source coordinate `[139.767066, 35.54498]`, while the nearby Apple POI happens to be 3.5 m away; the frame itself, rather than the POI, is the supporting evidence. The automatic candidate near `(670,498)` is monorail-side and must be excluded.

## Boundary

The Anamori Main pair shows station 004364 near the eastern part of its own frame, but this review does not derive an Anamori midpoint or approve a source guard. No Tenkūbashi or Terminal 3 midpoint rule should be generalized to Anamori or the remaining Airport Line stations without their own focused frame evidence.

Root integration and all native candidate acceptance remain required.
