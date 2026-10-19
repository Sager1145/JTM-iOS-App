# Jounan west frames: independent z18 review

Reviewed 2026-10-13 from the original 999 × 654 Apple basemap PNGs and each
capture's `analysis.json`. This is display-cartography evidence only. No source,
candidate, legal route, station identity, or physical record was changed.

## Reprojection

Pixels use the PNG's top-left origin. Coordinates below are deterministic
reprojections of the listed visual picks through that capture's exact
`nativeMapRect`:

```text
mapX = rect.x + pixelX / imageWidth  * rect.width
mapY = rect.y + pixelY / imageHeight * rect.height
longitude = mapX / 268435456 * 360 - 180
latitude  = atan(sinh(pi * (1 - 2 * mapY / 268435456)))
```

The visible edges are antialiased and some are covered by shields or labels, so
the visual endpoint precision is about ±1–2 px (about ±0.5–1.0 m). The
reprojected digits do not imply surveyed precision.

## Honmachi 1-chōme (`honmachi1-z18-before`)

The own north–south platform frame is the blue vertical rectangle beside the
black tram glyph. Its upper edge is partly covered by the `196` shield.

| Pick | Pixel | Reprojected coordinate |
|---|---:|---:|
| north longitudinal endpoint | `(519, 370)` | `[132.75875461, 33.84056341]` |
| frame midpoint | `(519, 400)` | `[132.75875461, 33.84042974]` |
| south longitudinal endpoint | `(519, 432)` | `[132.75875461, 33.84028716]` |

The current station source `[132.75865,33.840755]` projects to
`(499.5,327.0)`. It is about 75.6 px / 37.4 m from the visible frame midpoint,
including a roughly 19.5 px east component and a 73 px south component. This
confirms the apparent station-frame drift rather than a choice between two
nearby platform rectangles.

## Nishihoribata west arm (`nishihoribata-west-z18-before`)

The own east–west platform is the blue horizontal rectangle centered on the
west arm's black tram glyph. The route/station shield obscures its western
outline but the longitudinal axis remains visible.

| Pick | Pixel | Reprojected coordinate |
|---|---:|---:|
| west longitudinal endpoint | `(522, 370)` | `[132.75820570, 33.84010841]` |
| frame midpoint | `(545, 370)` | `[132.75832908, 33.84010841]` |
| east longitudinal endpoint | `(568, 370)` | `[132.75845246, 33.84010841]` |

The current Nishihoribata source `[132.758085,33.8403]` projects to
`(499.5,327.0)`, about 63.3 px / 31.3 m from this frame midpoint.

The pixel `(623,370)` is only the intersection of extended straight tangents;
no rail junction exists there. The actual black west arm curves through about
`(592,371)`, `(610,380)`, and `(621,398)` before joining the north–south rail
near `(622,410) = [132.75874214,33.83993018]`. That literal join is the
non-station display vertex. It must not be substituted for either Honmachi
1-chōme or Nishihoribata, and a candidate must not introduce a right-angle turn
at the virtual tangent intersection.

## Continuous Nishihoribata–Minamihoribata glyph

In `nishihoribata-minami-middle-z18-before`, the black tram glyph leaves the
west junction southbound and bends continuously east. Representative visible
centreline supports are:

| Feature | Pixel | Reprojected coordinate |
|---|---:|---:|
| literal west/NS join (west raw) | `(622, 410)` | `[132.75874214, 33.83993018]` |
| straight south support (west raw) | `(622, 455)` | `[132.75874214, 33.83972968]` |
| lower straight support (west raw) | `(624, 477)` | `[132.75875287, 33.83963165]` |
| curve support (west raw) | `(640, 511)` | `[132.75883870, 33.83948016]` |
| curve support (west raw) | `(678, 535)` | `[132.75904255, 33.83937322]` |
| east tangent support (west raw) | `(710, 541)` | `[132.75921421, 33.83934649]` |
| Minamihoribata crossing junction | `(645.5, 349.5)` | `[132.76179973, 33.83934666]` |

The `56` shield briefly covers the centreline between the straight and curve;
the visible glyph enters and exits it with matching position and tangent. There
is no visible reverse U or turnback in this interval.

## Minamihoribata (`minamihoribata-z18-before`)

Apple labels the whole crossing and draws three distinct platform frames. The
west frame is the interval-#1 arrival-arm evidence. The east and south frames
are recorded separately so a later owner does not collapse a multi-arm stop to
one unrelated platform.

| Frame / pick | Pixel | Reprojected coordinate |
|---|---:|---:|
| west frame, west endpoint | `(478, 348)` | `[132.76113967, 33.83934643]` |
| west frame midpoint | `(490.5, 348)` | `[132.76120672, 33.83934643]` |
| west frame, east endpoint | `(503, 348)` | `[132.76127378, 33.83934643]` |
| crossing rail junction | `(601, 348)` | `[132.76179949, 33.83934643]` |
| east frame midpoint | `(677.5, 349)` | `[132.76220987, 33.83934197]` |
| south frame, north endpoint | `(600, 377)` | `[132.76179412, 33.83921722]` |
| south frame midpoint | `(600, 408)` | `[132.76179412, 33.83907909]` |
| south frame, south endpoint | `(600, 439)` | `[132.76179412, 33.83894096]` |

The east frame's visible longitudinal endpoints are `(661,349)` and
`(694,349)`, reprojecting to `[132.76212135,33.83934197]` and
`[132.76229838,33.83934197]`. The current Minamihoribata station source
`[132.761255,33.83944]` projects to `(499.5,327.0)` and lies about 22.8 px /
11.3 m from the west-frame midpoint. Frame choice remains an arm-specific
display decision; the raw does not justify replacing the serialized legal
multi-arm representation with one station-centre point.

## Finding

The four raws support three separate facts: Honmachi 1-chōme and Nishihoribata
are materially displaced from their own visible platform frames; the west
junction is a separate, consistently reprojected rail vertex; and the physical
glyph proceeds from that junction through a south-to-east curve to the
Minamihoribata west arm without a reversal. Minamihoribata's three platform
frames must remain arm-distinguished in any later display proposal.

## Otemachi-line guard extension

All seven supplied Otemachi raws were inspected. Interval 0 view 0 repeats the
Nishihoribata frame above; interval 0 view 1 and interval 1 view 0 are the same
Otemachi map rectangle; interval 1 view 1 and interval 2 view 0 are the same JR
Matsuyama map rectangle; interval 2 views 1 and 2 overlap at Miyatacho. The
overlaps give independent registration checks rather than additional station
choices.

### Otemachi Sta. (`otemachi-interval0-view1-z18-before`)

The own tram frame is the horizontal blue rectangle on the black east–west tram
glyph. It overlaps the diagonal Yosan railway crossing at its west end; the
diagonal railway is a guard feature, not an alternative tram frame.

| Pick | Pixel | Reprojected coordinate |
|---|---:|---:|
| west longitudinal endpoint | `(464, 360)` | `[132.75527956, 33.84016796]` |
| frame midpoint | `(487, 360)` | `[132.75540294, 33.84016796]` |
| east longitudinal endpoint | `(510, 360)` | `[132.75552633, 33.84016796]` |
| tram/Yosan crossing pixel | `(460, 360)` | `[132.75525811, 33.84016796]` |

The current Otemachi source `[132.75547,33.840315]` projects to
`(499.5,327.0)`, 35.3 px / 17.4 m from the visible frame midpoint. The interval
0/1 duplicate raw has the same map rectangle and reproduces these pixels
exactly.

### JR Matsuyama Station-mae (`otemachi-interval1-view1-z18-before`)

The own tram frame is the long north–south blue rectangle on the single black
tram glyph. It is distinct from the Yosan railway corridor farther west and the
Iyotetsu Takahama railway farther east.

| Pick | Pixel | Reprojected coordinate |
|---|---:|---:|
| north longitudinal endpoint | `(502, 166)` | `[132.75235341, 33.84144235]` |
| frame midpoint | `(502, 243)` | `[132.75235341, 33.84109927]` |
| south longitudinal endpoint | `(502, 320)` | `[132.75235341, 33.84075619]` |

The current source `[132.75234,33.840725]` projects to `(499.5,327.0)`, about
84.0 px / 41.5 m south of the frame midpoint. The black tram glyph continues
south of the frame and turns east without reversal; visible centreline guards
are `(503,386)`, `(520,415)`, `(560,439)`, and the east tangent `(620,450)`.
Their respective reprojections are `[132.75235878,33.84046212]`,
`[132.75244997,33.84033290]`, `[132.75266455,33.84022597]`, and
`[132.75298641,33.84017696]`. Interval 2 view 0 repeats this exact frame.

### Miyatacho (`otemachi-interval2-view2-z18-before`)

The own tram glyph is the southwest-to-northeast diagonal marked `Iyotetsu Loop
Line`. Apple draws two staggered opposing platform frames. Their outer blue
bodies merge into shield/crossing fill, so the following endpoints use the
unambiguous light longitudinal highlights inside each frame. They are more
repeatable than guessed outer corners.

| Platform / pick | Pixel | Reprojected coordinate |
|---|---:|---:|
| southwest frame, southwest highlight end | `(448, 350)` | `[132.75233373, 33.84381752]` |
| southwest frame highlight midpoint | `(474, 330.5)` | `[132.75247321, 33.84390441]` |
| southwest frame, northeast highlight end | `(500, 311)` | `[132.75261268, 33.84399129]` |
| northeast frame, southwest highlight end | `(505, 299)` | `[132.75263950, 33.84404475]` |
| northeast frame highlight midpoint | `(540, 274)` | `[132.75282726, 33.84415614]` |
| northeast frame, northeast highlight end | `(575, 249)` | `[132.75301501, 33.84426753]` |
| south-to-diagonal rail join guard | `(448, 359)` | `[132.75233373, 33.84377743]` |

The current Miyatacho source `[132.75261,33.84392]` projects to `(499.5,327.0)`.
It lies beside the northeast end of the southwest frame rather than at either
frame midpoint. Interval 2 view 1 reprojects the same highlighted axes to the
same coordinates (the pixel translation between views is approximately
`(+25.2,-23.6)`), confirming their identity. The Yosan line at the far west and
Iyotetsu Takahama line at the far east are parallel guard corridors and were
excluded from the tram picks.

Across intervals 0–2, the own tram glyph is continuous through the Otemachi
rail crossing, the JR Station-mae north–east bend, and the Miyatacho diagonal
transition. These guard points identify visible topology only; they do not
authorize changing the serialized legal route or choosing one opposing
platform as a global station alias.

### Komachi (`otemachi-interval3-view2-z18-before`)

The continuous incoming Loop tram glyph reaches the diagonal station area at
the same longitudinal chainage as the shorter southeast platform body. The
rail-supported point is `(529.18,272.01)`, reprojected to
`[132.75516422,33.84721501]`. The body-axis midpoint `(543.19,277.37)` is about
14 px normal to that glyph; it is useful platform-cartography evidence but is
not a supported rail point. A longer parallel platform body and the nearby
Takahama/Johoku corridors are distinct guard features and were excluded.

### Honmachi 1-chōme identity ambiguity

The three interval-3 Honmachi raws show two distinct north–south platform
frames. The northern frame runs approximately `(519,294)` to `(519,361)` with
midpoint `(519,327) = [132.75876207,33.84197774]`. The southern frame is the
one documented above at `[132.75875461,33.84042974]`. Their approximately
172 m separation is too large to treat them as an ordinary opposing-platform
pair from these images alone. The current Honmachi 1-chōme source is much
closer to the southern frame and west junction. The raws do not establish the
northern frame's stop identity, so it must remain separate and must not replace
or be merged with the southern Honmachi representative without independent
identity evidence.

## Hanazono-line guard extension

All three Hanazono interval-0 raws were inspected. At Matsuyamashi, two
east–west platform frames are visible. The upper frame midpoint is
`(503.00,289.25) = [132.76235879,33.83619620]`; the lower body midpoint is
`(502.02,312.86) = [132.76235349,33.83609101]`. The incoming curved tram glyph
meets the lower frame at its longitudinal chainage near `(503,302) =
[132.76235878,33.83613940]`. This rail-supported point is the usable Hanazono
terminal representative; the lower body midpoint is about 11 px normal to the
rail and would create a visible hook. The private/other station tracks remain
separate. The visible own-glyph bend is supported by `(434,299)`, `(405,280)`,
`(387,250)`, and `(386,218)` before continuing north.

At Minamihoribata, the Hanazono glyph arrives on the distinct south arm. Its
visible frame runs from `(501,227)` to `(501,289)` in the interval-0 view-1
raw; the midpoint is `(501,258) = [132.76179275,33.83907901]`. The crossing
junction is separately visible at `(502,198) = [132.76179812,33.83934635]`.
This south-arm evidence must not be collapsed to the west or east platform
frames documented above.

## Jounan City Hall and Prefectural Office extension

Jounan intervals 2 and 3 add a continuous own tram glyph from the
Minamihoribata south arm, around the City Hall curve, and east along route 11.
The duplicate interval-2 view-2 / interval-3 view-0 map rectangle reproduces
the curve exactly.

At Matsuyama City Hall, the visible blue body's extracted longitudinal
chainage is `y ≈ 334.5` in interval-2 view 1. Its body axis is offset from the
black rail glyph, so the supported own-rail point at that chainage is
`(545,334.5) = [132.76486012,33.83983411]`. The duplicate rectangle gives
`(543.3,352.5) = [132.76485996,33.83983638]`, within the visual pick tolerance.
The current serialized source projects to about `(499.5,327)`, confirming the
broad lateral display offset. No platform end guards are asserted because the
body edges and traffic-light symbol overlap.

At Ehime Prefectural Office, the own horizontal tram frame is partly obscured
by route shields. The rail/frame longitudinal midpoint is approximately
`(502,350) = [132.76635841,33.84106752]` in interval-3 view 1 (visual precision
about ±2 px). The visible own rectangle spans approximately `x=461…543` and
`y=334…362`; the route-11 shield produces a separate blue bulge near
`(520,350)`. The prior `y=313` reading and the shield-centred `x≈520` pick are
not the own frame midpoint. The black glyph is continuous through the corrected
point.

## Jounan Ōkaido–Police Station extension

Intervals 4–6 continue on the same black tram glyph from Prefectural Office
east to Ōkaido, through the Katsuyamachō curve, and north toward Police
Station. The interval-boundary raws repeat the same map rectangles, providing
direct registration checks.

At Ōkaido, the long blue frame and its two pale longitudinal highlights sit
on the route-11 tram glyph. The supported frame/rail centre is approximately
`(596,334) = [132.77018267,33.84121881]` in interval-4 view 1. The current
serialized source projects to `(499.5,327)`, about 48 m west along the same
guide. The road and tram glyph remain continuous through the label and traffic
light; the evidence does not indicate a turnback.

At Katsuyamachō, two transverse platform highlights belong to the same
longitudinal blue frame around the curving black tram glyph. Their extracted
body midpoints are `(506.70,327.09)` and `(510.02,342.10)` in interval-5 view
2. The chosen representative uses the first identified face's longitudinal
chainage and projects it normally onto the own black rail, approximately
`[132.77486560,33.84171436]`. Its pixel is numerically close to the midpoint
between the two body centroids because of the rail's local angle; this is not a
face-gap average.

At Police Station, the light north–south platform highlight is partly obscured
by the route-20 shield. Its extracted body-axis midpoint is approximately
`(497.31,379.90)`; the own black rail at the same chainage is approximately
`(500,380) = [132.77536768,33.84438386]` in interval-6 view 1. The current
serialized source is at the image centre near `(499.5,327)`, about 26 m north
along the same guide. Shield overlap prevents a defensible endpoint pick, so
only the midpoint chainage is recorded.

## Jounan Kamiichiman–Dogo extension

At Kamiichiman, the Jounan and Renraku endpoint is the same north–south
frame. In their exact shared interval-7/interval-0 view-1 native map rectangle,
its own-rail longitudinal midpoint is `(500,365) =
[132.77543768,33.84664070]`. The earlier `(501,365)` coordinate transcription
used latitude `33.84660060`, which actually reprojects to `(500,374)`, nine
pixels south along the frame. The diagonal frame at `(321,153)` is not
Kamiichiman: it belongs to Heiwadori 1-chome on the Renraku line.

The identity is independently fixed by the serialized physical rows in the
same raw: Heiwadori 1-chome projects to `(315.88,123.87)`, adjacent to the
diagonal frame, while Kamiichiman projects to `(499.5,327)`, adjacent to the
north–south frame. The Renraku rail follows a continuous southeast curve from
the diagonal Heiwadori frame, then turns south and enters the Kamiichiman
north–south frame without a reversal or U bypass. The Jounan east arm merges
onto that same southbound guide upstream of the frame.

Heiwadori 1-chome is one shared diagonal own-rail frame for Renraku and
Johoku. The blue platform body's cartographic midpoint is approximately
`(320.26,152.36)`. Normal projection of that body chainage onto the dark rail
centreline gives `(326.24,148.59) = [132.77450559,33.84760487]`; using the body
centre itself would introduce a visible 7 px off-rail hook. Johoku interval 0
leaves this same point northwest through serialized supports
`[132.77445,33.847715]`, `[132.77431,33.84791]`,
`[132.77406,33.84805]`, and `[132.77391,33.84807]`, while Renraku leaves it
southeast toward Kamiichiman. These are traversable halves of the same
diagonal station approach, with no reversal.

The thin blue east–west bands around `x=158…196` and `x=245…290` in Johoku
interval-0 view 0 are line/transit casing, not separate Heiwadori platform
frames. The `x≈300…335` extraction also overlaps label casing. Neither is a
station anchor, and shifting the Johoku endpoint roughly 100 m west to one of
those bands would break the shared legal boundary.

At Minamimachi, no defensible platform rectangle is drawn in the supplied raw.
The Apple station POI `[132.7800447,33.847446]` lies directly on the continuous
own black tram glyph and is the bounded display representative. This is a
cartographic fallback with an explicit warning, not a surveyed platform-centre
claim and not permission to use the old off-rail source coordinate.

At Dogo Park, the frame nearest the current representative projects to the own
rail at `[132.78491513,33.84833946]`. The interval-9 approach is not a translated
copy of the compact source: literal supports in view 2 include `(100,518)`,
`(200,503)`, `(300,470)`, `(400,424)`, and `(480,349.5)`. The label-contaminated
pixel around `x=450` was excluded as an anchor.

At Dogo Onsen, the own terminal frame midpoint on the rail is approximately
`[132.78500477,33.85034163]`. Interval 10 follows the unique black arc rather
than a constant shift. In view 1, unambiguous dark-glyph supports include
`(530.5,400)`, `(536,430)`, `(536,470)`, `(535,500)`, `(527,540)`, `(515,580)`,
and `(505,620)`. The terminal approach was independently refined through
`(536,430)`, `(535,420)`, `(533,410)`, `(530.5,400)`, `(527,390)`, `(522,380)`,
`(516,370)`, `(508,358)`, and `(500,345)` before reaching the own-frame midpoint.
In the exact view-1 projection, its largest local deflection from `y=430` to the
terminal is 7.28 degrees at `(527,390)`; the sequence turns progressively into
the frame and has no residual corner near `(516,380)`. No competing rail exists
within the reviewed `x=480…550` corridor.

## Honmachi complete-frame extension

All nine Honmachi raws covering all four intervals were inspected. The bounded
display representatives on each own rail are:

| Stop | Raw pixel | Reprojected coordinate | Selection |
|---|---:|---:|---|
| Honmachi 6 | interval 0 view 0 `(502,308)` | `[132.75885341,33.85321464]` | independent north–south terminal below the Loop crossing |
| Honmachi 5 | interval 0 view 1 `(514,368)` | `[132.75882778,33.85062234]` | nearest identified platform face |
| Honmachi 4 | interval 1 view 1 `(523,334)` | `[132.75885606,33.84802381]` | north/nearest of the staggered faces, projected to the own rail |
| Honmachi 3 | interval 2 view 1 `(516,316)` | `[132.75878351,33.84517401]` | paired-face chainage on the own rail |
| Honmachi 1 | interval 3 view 2 `(519,400)` | `[132.75875461,33.84042974]` | southern own frame nearest the west junction |

Honmachi 6 remains a dead-end below the east–west Loop glyph; extending it to
the crossing would create a false through connection. The visible intermediate
frame at interval-3 view-1 `(519,327) = [132.75876207,33.84197774]` is the
unserialized Honmachi 2 chainage. It is useful as a pass-through rail guide but
must not receive a station dot or alter the serialized station list. Honmachi 1
uses the same southern own-frame point in the Honmachi and Jounan display
proposals.

Compact `segments[*][2]` arrays omit decoded welded station starts in some
intervals. They are provenance only; baseline and parity review must use
`network.decodeIntervals`. None of these frame findings changes physical
registry records, route serialization, station IDs, or kilometre measures.

## Johoku complete-frame extension

All 19 Johoku raws were inspected across the complete eight intervals; view
counts were `[2,2,3,3,2,2,2,3]`. They show one continuous Loop Line guide from
the shared diagonal Heiwadori boundary through the Furumachi approach, with no
reverse, U turn, chord, or competing road capture. The bounded display
representatives used in the complete temporary proposal are:

| Stop | Representative | Raw basis |
|---|---:|---|
| Heiwadori 1 (`008736`) | `[132.77450559,33.84760487]` | exact shared Renraku/Johoku diagonal body chainage normally projected to the own rail |
| Red Cross Hospital (`008734`) | `[132.77271998,33.84804914]` | nearest visible staggered body chainage projected to the own band; body edges are weak |
| Teppocho (`008733`) | `[132.76926637,33.84811570]` | nearest of two staggered body chainages projected to the own band |
| Shimizumachi (`008730`) | `[132.76500316,33.84917511]` | no defensible body; Apple stop POI chainage projected to the unique own guide |
| Takasagocho (`008726`) | `[132.76243642,33.85139591]` | visible north–south body chainage projected to the own band |
| Kiyacho (`008720`) | `[132.76062595,33.85355865]` | common longitudinal chainage of paired opposite bodies, projected between them onto the own band |
| Honmachi 6 (`008719`) | `[132.75860819,33.85348227]` | nearest identified east–west Loop body; label interruption limits exact outline precision |
| Kayamachi 6 (`008725`) | `[132.75622000,33.85178000]` | no separate body; retained serialized chainage on the visible north–south own guide |
| Furumachi (`008739`) | `[132.75516422,33.84721501]` | exact shared Otemachi/Johoku own-tram rail chainage; adjacent Takahama bodies excluded |

The Heiwadori and Furumachi tuples are exact cross-line display aliases. The
Johoku Honmachi 6 point is line-scoped: the perpendicular Honmachi-line
north–south dead-end frame remains separate. Red Cross, Shimizumachi,
Honmachi 6, and Kayamachi remain explicit raw-cartography warnings rather than
surveyed platform-centre claims. The complete temporary V1 uses literal guide
supports throughout all eight intervals and has 19 matching raw
reprojections; it changes no source or physical data.
