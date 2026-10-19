# Mita whole-line native review — north half

Date reviewed: 2026-10-12  
Scope: intervals 0–12 inclusive, 57/57 manifest viewpoints, package `2025.5.2`, line `jp-東京都-6号線三田線`  
Evidence contract: z17, about 0.966 m/pt, isolated zero-lane Inspector centreline. `basemap` is Apple only, `display` is the package DisplayParts in teal, and `smooth` is the native smoothed centreline in pink. This review does not cover production lanes, station circles, follows, joins or ridden-route composition.

## Result

The north half does show a real, repeated package-versus-Apple positional disagreement. It is already present in the teal DisplayParts and remains in the pink smoothed path, so smoothing is not the source of the large offset. With no Mita display override in the reviewed state, the owning candidate is the source/display geometry feeding DisplayParts.

The disagreement is **not well described by one whole-line translation**. There is a dominant visual bias: on the elevated east–west portion the package tends to sit on the south/southeast side of Apple's railway centre, and on the following north–south/diagonal portion it usually sits on the east side of Apple's blue Mita depiction. At the common z17 camera this is usually about one to several rendered stroke widths, visually roughly 5–12 m, with local separations approaching about 15 m. Those are visual estimates from the ~0.966 m/pt captures, not measured Apple-pixel residuals.

The bias changes magnitude through curves and changes side locally. The strongest shape evidence is around intervals 3–5, 8 and 10–12: the package and Apple paths use different bend radii or cross one another rather than maintaining a fixed parallel separation. A global correction alone would leave those local disagreements. The evidence therefore supports **a broad directional source bias plus localized source coarseness/shape differences**, not a single global shift.

## Surface, transition and underground evidence

- **Intervals 0–4 (surface/elevated):** Apple draws explicit parallel railway strands, station/platform areas and the elevated corridor. Roads and building footprints remain internally aligned with that structure. The teal/pink centreline repeatedly occupies the south or southeast side of Apple's depicted passenger corridor. This is the strongest evidence of a source-side positional problem, although Apple's multiple strands still do not by themselves select an exact passenger representative track.
- **Interval 5 (transition):** the view moves from the visible elevated alignment into the road-following section around the Shimura transition. Ordinals 2–3 are the key boundary views. The package remains offset while the basemap's physical-track evidence gives way to a blue transit route under the arterial. This boundary should not be repaired by extending an elevated-track snap blindly into the tunnel.
- **Intervals 6–12 (underground):** Apple chiefly supplies the blue Mita route, station blue areas and road/intersection context, not observable tunnel rails. The package commonly lies east of the blue route, but Apple's underground line may itself be schematic. Roads, intersections and buildings establish the corridor and make the consistent side bias visible; they do not prove the tunnel's precise physical centre. The blue station polygons and labels are supporting context only.
- **Display versus smooth:** every reviewed display/smooth pair preserves the same material offset. Smoothing changes only small local curvature and does not explain the package-to-Apple separation.

## Candidate intervals and ordinals

These are review candidates for the source worker, not accepted replacement coordinates.

| Priority | Interval / ordinal | Visual reason |
| --- | --- | --- |
| High | 2/3, 2/4 | Elevated station/rail-fan context; source stays on one side of Apple's explicit rail corridor. |
| High | 3/1, 3/2, 3/3 | First large surface bend; differing bend radius and separation through the curve. |
| High | 4/2, 4/3, 4/4 | Curved approach; directional residual changes through the bend rather than remaining a rigid translation. |
| High | 5/2, 5/3 | Last surface/transition context; separates evidence from visible structure from the later underground schematic. |
| Medium | 6/1, 6/2, 6/3 | Long arterial run; repeated east-side displacement, useful for testing the dominant bias. |
| Medium | 8/3, 8/4 | Major road bend; source and Apple use visibly different curvature. |
| Medium | 10/1, 10/2, 10/3, 10/4 | Multi-view diagonal/curve sequence; separation changes through the interval. |
| Medium | 11/3, 11/4 | The two paths converge/change side approaching the station complex, contradicting a uniform shift. |
| Medium | 12/0, 12/1, 12/2, 12/3 | Entire short final interval including its endpoint/tail; the local side relationship changes and the station area is schematic. |

Intervals 0/0–3, 1/0–2, 2/0–2, 3/0, 4/0–1, 5/0–1, 6/0 and 6/4, 7/0–3, 8/0–2, 9/0–3, 10/0 and 11/0–2 were also visually inspected. They support continuity of the broad bias but are less discriminating than the candidates above.

## Coverage note

Manifest coverage was read from `coverage.json`: the complete batch contains 26 intervals and 115 viewpoints; this north review covers all 57 viewpoints assigned to intervals 0–12. The per-interval ordinal coverage was:

`0: 0–3; 1: 0–2; 2: 0–4; 3: 0–3; 4: 0–4; 5: 0–3; 6: 0–4; 7: 0–3; 8: 0–4; 9: 0–3; 10: 0–4; 11: 0–4; 12: 0–3`.

Every basemap/display/smooth panel in these contact sheets was visually inspected:

- `interval-00-page-1.jpg`, `interval-00-page-2.jpg`
- `interval-01-page-1.jpg`
- `interval-02-page-1.jpg`, `interval-02-page-2.jpg`
- `interval-03-page-1.jpg`, `interval-03-page-2.jpg`
- `interval-04-page-1.jpg`, `interval-04-page-2.jpg`
- `interval-05-page-1.jpg`, `interval-05-page-2.jpg`
- `interval-06-page-1.jpg`, `interval-06-page-2.jpg`
- `interval-07-page-1.jpg`, `interval-07-page-2.jpg`
- `interval-08-page-1.jpg`, `interval-08-page-2.jpg`
- `interval-09-page-1.jpg`, `interval-09-page-2.jpg`
- `interval-10-page-1.jpg`, `interval-10-page-2.jpg`
- `interval-11-page-1.jpg`, `interval-11-page-2.jpg`
- `interval-12-page-1.jpg`, `interval-12-page-2.jpg`

For closer confirmation at native resolution, the smooth captures for candidates 5/3, 6/2, 8/3, 10/3, 11/3 and 12/3 were also inspected directly. Inspector counters, receipt reuse and smooth-to-display distance summaries were not used as geographic acceptance.

## Remaining uncertainty

The surface views establish a source/Apple disagreement but do not independently prove which Apple parallel track is the correct passenger representative centre. The underground views establish a stable corridor-side mismatch, not the tunnel's surveyed position. External track/source evidence should arbitrate the exact replacement geometry, particularly across interval 5 and the local shape candidates in intervals 8 and 10–12.
