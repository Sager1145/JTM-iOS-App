# Sukaguchi independent rail and station-face adjudication

2026-10-13. Read-only source/image adjudication. Production data, physical IDs, interval mileage, physical edges, prior proposals and scope ledgers were not edited. This is a root-reviewable proposal, not native candidate acceptance.

The exact original 999×654 z18 Sukaguchi basemap identifies two distinct northwest approaches converging into one thin black railway glyph through the station. The source's reverse-shared three points encode the existing represented connection, but start the shared display span before the Apple glyphs converge. The narrow blue platform faces extend southeast across the transverse station building: stopping their length at that building's northwest side truncates the faces. Their longitudinal midpoint projects near **(592,378)** on the common railway, approximately **[136.84625120866804,35.198706437899155]**. The midpoint railway is hidden by the building; this coordinate retains a warning and requires root/native review.

## Railway identity and the actual visible fork

The northwest Main glyph and west Tsushima glyph are distinct thin black strokes with transverse sleepers. These are not two edges of one broad corridor. At the following columns, the Main glyph is above the Tsushima glyph:

| Original pixel x | Main northwest own glyph y | Tsushima west own glyph y |
| --- | --- | --- |
| 300 | 168 | 197 |
| 340 | 198 | 214 |
| 360 | 214 | 223 |
| 370 | 221 | 228 |
| 380 | 229 | 232 |

They converge around x385–410, y232–252. Safe downstream common glyph supports include **(400,245), (410,251)**; station flanks include **(555,351), (630,404), (640,412)**. The JSON preserves each sampled original RGB and mapRect-derived coordinate. A single antialiased pixel or sleeper arm is not an exact axis measurement; use the visible stroke and neighbouring tangent. The cartographic merge does not locate a surveyed physical switch.

The source shared point **[136.84472,35.19948] → (306.56,201.53)** lies near the Tsushima branch while the Main glyph is still substantially north. Therefore a display repair must move the start of its exact reverse-shared support into the actual common glyph. It must not force Main #17 through this old Tsushima-branch point. Physical connectivity and source mileage remain unchanged.

The physical package directly confirms the station row shared by both lines, the 0.695 km Main #17, 0.746 km Main #18 and 1.935 km Tsushima #0, and exact reverse equality of Main #17's final three points and Tsushima #0's first three. Nagoya/Shinkawabashi → Sukaguchi → Jimokuji uses **reverse Main #18, then forward Tsushima #0**. Its source station tangents are in the same direction, so a reversal or fake U is unsupported. This establishes existing represented connectivity, not individual operational track numbers.

## Complete narrow faces and normal projection

The raw station frame has narrow rounded north/south fills flanking the same glyph. Both extend through/behind the broad transverse blue building to visible southeast rounded ends. They are distinguishable from ordinary blue casing and the building footprint. The old physical point (499.5,327) falls inside the narrow southern fill; RGB at (500,327) is **104,128,178**. It is not a literal black railway sample.

Manual visual identity was established first. A bounded query then enumerated this fill colour within the identified face strips; connected colour components alone were not used to establish physical platform identity. The local interpolation axis uses the label-free railway flanks (555,351) and (640,412). Because it is a straight local approximation across a hidden middle, retain a few pixels of uncertainty.

| Identified cartographic face | NW extreme actual fill pixel | SE extreme actual fill pixel | Long midpoint normally projected to interpolated railway |
| --- | --- | --- | --- |
| North | (466,271) | (732,462) | (591.385,377.111) |
| South | (451,294) | (720,483) | (592.895,378.195) |

These are extreme fill pixels along the axis, not centreline endpoints. The JSON separately records both longitudinal endpoints projected onto the rail axis, so root can recompute the midpoint without averaging arbitrary frame corners. The two longitudinal midpoints differ by under two pixels on this axis. A practical review bound is **x588–596, y374–381**. The short former interpretation ending near x570 is incomplete; the wider station-building centroid is also unsuitable.

**WARNING:** Apple cartography does not expose the physical directional platform numbers here, and the building masks the railway at the derived midpoint. The narrow opposing faces support a cartographic station chainage candidate on the existing common glyph. They do not certify an individual operational platform group or native final dot. The same-camera Main candidate should determine whether this level of cartographic group identity satisfies the requested own-frame convention.

## Complete intervals and additional bounded controls

Visual identity was checked in seven Tsushima #0 raw viewpoints: Sukaguchi plus interval0 views 1–6, through the west curve, Shōnai River crossing, east–west corridor and Jimokuji approach. Three Main #17 raw viewpoints include Marunouchi, middle approach and Sukaguchi; four Main #18 viewpoints include Sukaguchi, southeast yard edge, river crossing and Shinkawabashi. These checks establish corridor continuity and reject competing glyphs; they are not whole-interval pixel residual acceptance.

Eleven additional label-free Tsushima controls from views 1–6 are frozen in the JSON with their own camera conversion. They follow the single black sleeper glyph, with no casing-edge averaging. Root can use them as provisional supports for the complete #0 fit; they are not a complete interpolated route.

## Requested related station normals

| Station | Previous pixel | Independent root-review normal candidate | Candidate coordinate |
| --- | --- | --- | --- |
| Marunouchi | (474,231) | **(471,231)** | [136.84198711408624,35.204625793777495] |
| Shinkawabashi | (454,269) | **(454,280)**, bounded near y277–281 | [136.85237591897993,35.195456036607474] |
| Futatsuiri | (482,309) | **(482,309)**, plausible within about1px | [136.8596121226845,35.19473890827177] |

Marunouchi's previous pick is light label ink, and label-free upper/lower railway supports place the stroke about3px west at that chainage. Shinkawabashi's previous pick is casing (65,89,136); its visible curved railway flanks support a lower normal projection. Futatsuiri's middle is labelled, but the clearly visible glyph on both flanks supports the existing near-horizontal normal. None of these candidates alone certifies longitudinal frame chainage or actual native output. JSON includes original RGB and flank supports.

Shinkawabashi's named station raw and Main #18 view3 have identical camera dictionaries but different basemap pixels. Their own captures must be used when comparing coordinates; same camera does not guarantee identical cartography.

## Files and limits

- `adjudication.json`: exact capture/camera records, physical source facts, RGB samples, identified face extrema, projected midpoint candidates, additional Tsushima controls and related normals.
- Original images remain under `../tsushima-complete-native/`.
- No UI operation, build, production mutation, acceptance flag or claim of measured final native alignment was performed.
