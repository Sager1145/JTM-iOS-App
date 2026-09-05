# Railway data and the display network

## Source of truth

The seven `*-2025.json` files plus `shared-corridors.json` are the canonical
railway database.  A regional package owns each public line; the companion
shared-corridor table owns reviewed cross-line topology that cannot be encoded
by compact-v1. Edit or rebuild those sources when a line, station, colour,
name, topology, or surveyed coordinate changes. Do not hand-edit the display
derivative.

The iOS map's `rail-display-network` directory is a disposable build product.
It is generated from the canonical packages by:

```sh
python3 app/scripts/railway/build-display-network.py \
  --rail-dir app/public/rail \
  --output /tmp/rail-display-network
```

The Xcode copy phase runs this command automatically, so a canonical data edit
is reflected in the next app build without a second manual source to maintain.
Route solving, statistics, editing, and package audits continue to read the
canonical packages; the display network is only a MapKit display derivative.

## Integrity contract

The generator decodes the same compact-v1 station-to-station intervals, applies
the reviewed shared corridors and the screen-space lanes, and writes one file
per region — `jp.json`, `tw.json`, … — with the geometry uncut. One part per
station interval, or per lane piece where a reviewed lane cuts one; a railway
crossing the viewport is therefore one continuous stroke rather than a run of
fragments that happen to abut.

North America (`us`, `ca`) and Japan (`jp`) are written differently from the
four older regions, and drawn differently by both clients. A fragment there is one
**continuous chain** of intervals (`continuous: true`, `chain: n`) carrying
its reviewed lane rows in metres from the chain's start (`laneRows:
[[from, to, lane], …]`, `totalMetres`), and each platform carries the vertex
it sits on (`slot: [chain, vertexIndex]`). Neither client cuts such a chain
at a lane change: `rail-stroke.js` on the web and its port
`RailCore.ContinuousStroke` on iOS project the whole chain into the pixel
space of the current zoom, bake the lane offset in through a smoothed lane
profile — a triangular kernel over the plateaus, so every change of lane is
an S-curve and never a step — round every corner that is neither a platform
nor a reversal to `strokeCornerRadiusPx`, and place each platform bead on
the offset of its own vertex. The stroke is therefore ONE polyline at every
zoom, rebuilt when the zoom has moved a quarter of a level, and the two
clients are held to the same answer by `port-fixtures/continuous-stroke.json`.
A withheld interval still breaks the chain: that is the alignment gate's
verdict, not a lane's.

Two more things the engine does on the way. Where a survey seam was welded
sideways — two opposite bends within 60 m, the same heading either side,
the track 8 m or more over — the Z is redrawn as a 150 m taper either side
(`taperJogs`), because no railway turns like that; a street tram's S-bend
of right angles and a real switchback are outside the shape test, and a
platform is never moved or crossed. And over a **corridor follow**
(`follows: [[from, to, canonicalLineKey, canonicalChain, canonicalFrom,
canonicalTo], …]`, from `display-lanes.json`'s `followsByRegion`) the chain
is drawn from the named canonical chain's alignment before it is offset into
its own lane, so every lane of a bundle comes off one centreline and two
digitisations of one corridor cannot weave across each other. Follows are
DERIVED candidates, not reviewed topology: `build-display-lanes.mjs` writes
one where a stroke stays within 25 m (median over a smoothed run of at
least 1 km) of a better-provenanced part of the same rail family — an
operator's own centreline outranks an intercity GTFS shape, a surveyed
source outranks a coarser one, and a metro beside a mainline is never
followed by it. Review them like the lane rows; a wrong follow is fixed in
the derivation or in `na-render-groups.json`, never by hand in the table.

`na-render-groups.json` can also name a `families` entry for a `byLineId`
render group — `{color, colorDark, colorSource, networkId, mode, name, why,
confidence}` — for a family whose lines should draw in ONE colour rather
than each line's own package hex, the operator-level collapse the Apple
Maps rendering audit records for LIRR, Metro-North and Metrolink
(`lirr:trunk`, `metro-north:trunk`, `metrolink:trunk`; MBTA commuter rail's
lines already publish one identical hex, so its family carries that colour
for the record without changing anything). The schema was `groups` (jtm-
na-render-groups-v1: `{color, colorDark, name, evidence, why, confidence}`,
no `networkId`/`mode`, `colorSource` a free-text label) before the
jtm-na-render-groups-v2 rename; both readers still accept `groups` for one
release, with a deprecation warning, so a checkout mid-migration does not
fail closed.
`build-display-lanes.mjs` copies every such colour into `display-lanes.json`
as `colorByRegion[region][lineId] = {color, colorDark}` — deriving
`colorDark` the same way the package build does (hold the hue, only ever
raise the saturation, move along lightness to the dark-theme floor) when a
family gives no `colorDark` of its own — and both renderers apply it before
anything else derives from a line's colour: rail-network.js's
`colorOverrideByLine` wins over `compactLine.color`/`colorDark` at the one
place `buildNetworkFromCompactPackage` reads them, so the drawn stroke, the
station bead `colorKey`, labels, badges and `lineById`'s own colour (read by
popups and statistics) all agree with what the map draws; the iOS build
applies the same table where it writes each fragment's metadata colour in
`build-display-network.py`. A line absent from the table keeps the
package's own colour on both clients. Review a wrong or missing family
colour like the lane rows — fixed in `na-render-groups.json`, never by hand
in `display-lanes.json`.

`na-render-groups.json`'s `byLineId` answers a second, independent question
from the colour override above: which lines are the SAME railway for
interchange purposes, whether or not the family also carries a colour.
`build-display-lanes.mjs`'s `deriveRenderGroupByRegion` copies EVERY line
`byLineId` names — not only the ones `families` also gives a colour — into
`display-lanes.json` as `renderGroupByRegion[region][lineId] = groupId`.
rail-network.js's `renderGroupIdentityByLine` turns that into
`Map(lineId -> "group\0<groupId>")`, and `railwayIdentityFor` returns it for
any line the map names, ahead of the operator+name fallback
(`visibilityGroupKey`) but behind an explicit `railwayId`/`RAILWAY_IDENTITY`
entry — so LIRR's eleven branches collapse onto one railway at Jamaica
(no false interchange ring for a change nobody makes) while a station where
LIRR meets a different railway (NJ Transit's Newark Light Rail at Penn
Station, say) still counts two. `build-display-network.py` copies the same
table into each line's manifest metadata as `renderGroup`, so a future
Swift-side interchange pass can mirror the same collapse instead of
re-deriving it from colour or name. Review a wrong or missing render group
like the lane rows — fixed in `na-render-groups.json`, never by hand in
`display-lanes.json`.

Where a follow row's follower and leader belong to the SAME `byLineId`
render group, `build-display-lanes.mjs`'s `deriveFamilyWindows` (run in
`deriveDisplayRows`, right after the follow chain's re-pointing pass)
turns that overlap into `display-lanes.json`'s `familyWindowsByRegion`: rows
`[lineId, partIndex, fromMetres, toMetres, role, groupId]`, on the part's own
metre ruler, edges snapped to the nearest station measure within 60 m (a
platform's length, tighter than a lane run's own 2000 m station-snap,
because this handoff has to land ON the junction station). The snap runs on
ONE ruler only — the follow's LEADER — and the matching tenant edge is
mapped onto the follower's own ruler through that row's own linear
correspondence, rather than snapped a second time independently on the
follower's own nearest station: snapping each side independently can choose
two different physical points when the two alignments don't share identical
station spacing, leaving the tenant's resumed base stroke and the leader's
family stroke a few metres apart at the handoff (a visible sliver of the
wrong colour). Windows separated by no more than one sample (`SAMPLE_METRES`,
25 m) are unioned together, on both the landlord and the tenant side, so
sampling noise cannot leave two windows that are really one continuous
stretch a sliver apart either. `role 0` (landlord) is the follow's LEADER:
it draws the shared family stroke over the window, in
`families[groupId].color`/`colorDark`. `role 1` (tenant) is the FOLLOWER:
its own stroke is not drawn over the window, because the landlord's stroke
already covers that stretch of the same physical corridor — same corridor,
same RenderKey, one drawn lane. Two different tenants naming the same trunk
stretch are unioned onto one landlord window; a line that is itself a
landlord over part of its length and a tenant over another part (a genuine
second junction, not an unresolved follow chain) has the tenant portion
subtracted from its own landlord windows. A window whose family has no
`families[].color` is a fail-closed build error — see the families-table
check below — never a silently uncoloured stroke. The follow chain's own
re-pointing pass (walking a tenant of a tenant back to its true root) runs
to a fixed point rather than a fixed pass count, bounded at 16 passes and
throwing rather than silently truncating if that bound is somehow not
enough for a chain this data could plausibly contain.

Every `byLineId` render group needs a `families` entry with a colour before
this can run: `build-display-lanes.mjs` checks every family named in
`byLineId` once, at startup, and throws (naming the family and every one of
its member lines) if any has no `families` entry or no `color`. Where a
family's members already publish one identical hex — most of the newer
families (`mbta:green`, the NJ Transit/MARC/Sounder/Seattle-streetcar/SFMTA
pairs, `nyct:l`/`nyct:shuttles`, the nine NYC Subway trunk families and
`septa:trolley-tunnel`) exist for IDENTITY reasons (two railways sharing one
publisher's hex, or one railway's own branches) rather than for an
operator-collapse colour override — that hex is recorded with a
`colorSource` citation (`{url, name}`, or `{name}` alone for a GTFS-derived
citation with no single canonical URL) rather than invented. A family whose
members genuinely disagree with no colour reviewed is a hand fix in
`na-render-groups.json`, same as a wrong lane or follow row — never a
worked-around default in `display-lanes.json`.

`rail-network.js`'s `familyWindowRowsByPart` splits `familyWindowsByRegion`
by role into per-part `familyWindows`/`tenantWindows` arrays
(`{from, to, groupId}`), attached to every `strokeModel.lines[].parts[]`
entry next to `rows`/`follows`/`withheld`. A line with any landlord window
gets a second feature in `network.segments` — `familyFeatureIndex`,
`{...baseProperties, color, colorDark, family: groupId, lane: 0,
continuous: 1}` alongside its ordinary `featureIndex` one, in the SAME
source/layer (`featureLineColor` in `railmap-style.js` reads `["get",
"color"]`, so no new layer is needed). `railmap.js`'s
`_applyContinuousStrokes` slices the just-built pixel stroke three ways at
render time, via the shared `RailStroke.familyPartition`/
`clipRangesToComplement` (rail-stroke.js, answer-identical to RailCore's
`ContinuousStroke` port on iOS): the BASE feature draws the complement of
(tenant ∪ landlord) windows; the FAMILY feature draws the landlord windows,
one piece per window; a tenant window is drawn by neither (`part.strokePx`
stays the full, unsliced stroke regardless, so a ride recorded on a tenant
window still slices cleanly for playback). The withheld dashed overlay
clips itself to the same complement-of-tenant-windows visible range and
then splits each surviving piece again at every landlord-window edge
strictly inside it, so a withheld span can never dash track this line draws
nowhere and a piece never straddles a family/base colour boundary.

A shared platform draws one bead, not one per family member (rules.md
§10.4). `buildNetworkFromCompactPackage`'s station loop suppresses a tenant
line's own station feature at a platform only when BOTH: (a) that station's
own anchor measure falls inside one of the line's own tenant windows, and
(b) a same-render-group sibling holds a LANDLORD window of the SAME groupId
covering the sibling's OWN anchor at the same physical station
(`stationGroupId`) — i.e. the sibling's bead is actually there to stand in
for it. Landlord beads are never suppressed. Where (a) holds but NO sibling
landlord bead exists at that platform (an express landlord that does not
stop there, or a local-only tenant pair) exactly ONE bead survives: the
tenant with the lowest lineId among every same-group tenant stopping at
that physical station — so a shared stop can never be left with zero beads.
The count of features this suppresses is exposed on the built network as
`familySuppressedStationCount`, for callers to report; nothing in either
client reads it. `port-fixtures/family-windows.json` pins real converging
corridors (LIRR's Jamaica/Valley Stream/Port Jefferson throats,
Metro-North's Park Avenue trunk, MBTA's Green Line central subway and
Southwest Corridor commuter trunk, Metrolink's LA Union Station approach,
SFMTA's Market Street throat, and NYCT's Lexington Ave Line — the 5 express
landlord over the 4/6/6x local track, the fixture's own worked example of
the bead rule's two branches) to their derived windows and exactly which
piece is emitted where, in which colour, plus a handful of synthetic
partition-boundary probes (a reversed follow window, two landlord windows
meeting exactly end-to-end, a withheld span straddling a landlord edge),
for the Swift port's own parity test to match.

`display-lanes.json` also carries `partsByRegion`: one row per web display
part (`displayPartsForLine` in `rail-network.js`, which cuts a line's stroke
wherever a branch, a retrace or a reversal makes one drawn part turn into
two), `[lineId, partIndex, firstIntervalIndex, lastIntervalIndex, vertexCount,
totalMetres]` when the part reduces to one plain, unbroken run of whole raw
intervals, or `[lineId, partIndex, -1, -1, vertexCount, totalMetres, kind,
coordinates]` — the part's own final vertices, copied rather than
re-derived — when it does not (a branch's lead-in copied off another part's
tail, an extraSegments row, a loop's wrap seam). `build-display-network.py`
builds each continuous-stroke chain from these rows instead of re-deriving
its own splitting rules from the raw compact-v1 intervals, which is what let
a branching US/CA line's native chain count silently disagree with the web's
own part count before: a lane or follow row keyed to a part number the two
sides had numbered differently was dropped without a trace. A lane or follow
row now naming a part with no matching chain raises instead — see
`partRowsForLine` in `build-display-lanes.mjs` and `chains_from_parts_rows`
in `build-display-network.py`.

A continuous-stroke line can also have NO `partsByRegion` rows at all,
because `rail-network.js`'s own web engine (`drawsContinuousStroke &&
!serviceSplitForLine`) declined to build it into a strokeModel chain — a
bus substitution or suspension covering part or all of the line. Those
lines are named in `strokeExcludedByRegion[region] = [[lineId, reason],
...]` (`reason` is the line's own package `serviceStatus`, e.g.
`"substitute_bus"`, `"partial_service_suspended"` — a whole-line exclusion
need not start with `"partial_"`), and `build-display-network.py` draws
exactly these lines through the ordinary per-lane path tw/hk/mo/kr always
use instead of a continuous chain. Any OTHER continuous-region line missing
`partsByRegion` rows and absent from `strokeExcludedByRegion` is a real gap
— a stale or missing `display-lanes.json`, a checkout mid-migration — and
fails the build.

Nothing bounds the payload by camera position, because nothing needs to: the
native client culls at draw time, by zoom (`NetworkLOD`) and by a per-interval
rectangle test against the padded visible rect, and it reads a region's file
only once the camera has both reached that region's extent and passed the
earliest zoom at which any of its railways can be drawn. Both facts are in the
manifest, measured from the data rather than declared.

It never discovers shared track by distance for the five older regions, and
never rewrites canonical geometry for any: a North American follow changes
the drawn stroke only, and only within the reviewed lane table's own
derivation limits described above. Most lines therefore retain every
canonical vertex and station anchor unchanged.

`shared-corridors.json` is the narrow cross-line topology table for a reviewed
service corridor. A terminal approach names the exact same-kind lines, terminal
station, interval side, and cut vertex. A full shared interval names an exact
station pair plus an ordered list of canonical candidates. Every entry records
at least two evidence sources. The generator reuses one member's existing
station-to-junction arm or complete station interval and may place the members'
display dots at the same station coordinate. It fails closed when
a railway type changes, a reviewed vertex moves, the station separation exceeds
its stated limit, or the branch cuts no longer describe one junction. Regional
packages remain unchanged and continue to own routing and mileage; the
companion table, rather than a runtime proximity guess, owns the fact that the
lines share track.

An interval withheld by the package alignment gate remains absent unless this
registry replaces it with a reviewed, unblocked canonical interval — or the
reviewed release table `display-releases.json` names it. That table
(`app/scripts/railway/make-display-releases.py`, from an OpenStreetMap
measurement run) never lowers a limit: it lists intervals measured again,
vertex by vertex, against the nearest active OSM railway of the line's own
type and found consistent (verdict A) or disagreeing only where OSM's tunnel
approximation is the coarse one (C), each with its median/p95/max deviation.
An interval measured and found wrong (B) or not measured (D) is never
released. The lane builder copies the table into `display-lanes.json`
(`releasedIntervalsByRegion`), and both renderers open exactly those
intervals for display; routing, mileage and the package audit still read the
package's own verdict. Only that
exact replaced interval is released for display; if every candidate is blocked,
the group stays unresolved and hidden. The Web renderer and the iOS display
network builder apply the same rule.
The Web map fetches this same registry beside the compact package and applies
it only to its GeoJSON display features; its canonical `lineById` geometry
remains untouched. The iOS build applies the registry as it derives the display
geometry, so both renderers use the same station, arm, and junction decisions.

Use this registry only when operator/service geometry and physical-track
evidence agree that several public lines share the approach. Parallel tracks,
same-name corridors, or nearby stations alone are not evidence. High-speed,
commuter, metro, light-rail, and street-running services must remain separate
unless every member has the same reviewed `kind`.

`display-hubs.json` is the reviewed table of convergence hubs — a small
number of named places (Chicago Union Station, the Chicago Loop, Union
Station in DC, Toronto Union, and so on) where several lines' own digitised
geometry legitimately sits inside one small radius of a shared terminal or
junction throat. It exists because the general lane pass in
`build-display-lanes.mjs` ranks lanes per display class over a window at
least `MIN_RUN_METRES` long and may flatten a class onto its single busiest
lane (`DOMINANT_LANE_SHARE`); both rules are right for an ordinary corridor
and both are wrong inside a hub, where the convergence itself is shorter than
`MIN_RUN_METRES` by construction and routinely bundles several branches of
ONE operator's own display class that the general pass never even compares
against each other (same-class parts are deliberately excluded from being
neighbours, so a line never fights its own repeated geometry for a lane —
which also means two branches converging on one platform throat default to
lane 0 together unless a hub says otherwise). Each entry names an `id`,
`region`, `name`, `centre` (`[lon, lat]`), `radiusMetres`, an optional manual
`laneOrder` (an ordered list of `lineId`s, for the rare hub where the
reviewed cartographic order does not follow from geometry alone), and
`evidence`. The hub pass runs once follows are final: for every RENDER KEY
(`displayClassKey` — the same identity the general pass draws as one stroke)
whose members' own geometry crosses a hub's radius AND comes within corridor
distance of that hub's reference/trunk part (an optional `trunkLineId` when
the hub names one, else picked by whichever member the most other members'
follow rows name as canonical), it assigns ONE evenly spaced half-integer
slot centred on zero — `i - (n-1)/2` over the hub's classes, the same scheme
the measured-lateral rank already uses — to every member line of that class,
ordered by branch-block (the majority side that class's own members depart
to beyond the hub: left, then continue, then right), and exempts that window
from `MIN_RUN_METRES` and `DOMINANT_LANE_SHARE`. Two hubs close enough for their radii to overlap
(Union Station and the Loop are under 1 km apart) claim ground in the order
they appear in the file: the first hub to reach a part's stretch keeps it,
so list the more specific or major throat first. Outside a hub radius the
output is unaffected. Review it like the lane rows and `na-render-groups.json`
— a wrong hub membership or slot order is fixed by editing this file or the
derivation, never by hand-editing `display-lanes.json`.

The manifest records the SHA-256 digest of every canonical package and every
generated region file, plus that region's extent and its earliest drawable
zoom. The iOS loader checks a region file's byte count, digest, coordinates,
format, and line references before drawing it. A corrupt or mismatched region
is reported in Settings and is never rendered as partial trusted data.

Run the focused gate after changing the generator:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  app.scripts.railway.tests.test_display_network
```

The complete seven-package railway audit remains the authority for canonical
inventory and topology. This gate proves that the derivative neither cuts nor
loses geometry and checks the explicit shared-corridor contract; it does not
replace the source-data audit.

Every full scan must also capture the reviewed high-error locations in
`audit-hotspots.json`. With a simulator build available, run the combined gate:

```sh
app/scripts/railway/audit-with-hotspots.sh \
  /path/to/RailMap.app /tmp/railway-audit
```

The output contains the machine-readable audit, its text report, the hotspot
registry used for that run, and one resized MapKit screenshot per hotspot.


## Japan: the route-preserving profile

Japan joined the derived, continuous-stroke path on 2026-09-04. The geometry
engine is the same one North America uses — `build-display-lanes.mjs`'s
`deriveDisplayRows` (renamed from `deriveNorthAmericanRows`, because nothing
in it was ever North American except the policy files it reads). What differs
is entirely in reviewed data.

**Identity is the line's name, never its colour.** `jp-render-groups.json`
declares `policy.profile: "route-preserving"` (rules.md §5.2), and under that
profile `displayClassKey` keys on operator + the line's own official N02 name
instead of operator + published colour. It has to: 小田急電鉄, 阪神電気鉄道 and
京浜急行電鉄 each paint EVERY line they own one single hex, and 京王電鉄 paints
six, so the North American default would collapse a whole operator's network
onto one stroke. Measured on this package, the colour default would have
merged 94 operator+colour buckets covering 261 line rows; the profile key
keeps all 593 published lines apart. The key is exactly the package lineId
with its geometry-part suffixes (`-2`, `-3`, `-p1`) stripped, and
`jp-render-groups.json`'s `byLineId` is used for ONE thing only: naming the
40 families (99 line rows) that are those suffixed parts of one railway, so a
railway N02 split into several rows draws as one stroke rather than as
several parallel lanes of itself. It never merges two published lines. The
two policy files are read per region through their own `scope`, and two
policies claiming one region is a build error.

**A follow needs a reason as well as a measurement.** In North America a
follow is discovered purely by measurement. Japan cannot be: the line-by-line
audit separates 342 spans of 坐标精确重合 (exact coordinate coincidence, one
physical track digitised twice) from 245 spans of 真实几何平行 (genuinely
independent centrelines on their own roadbeds — 新幹線 beside JR beside 私鉄
through 京都—大阪), and 35 of those 245 run closer than the 25 m follow
threshold over runs far longer than its 1 km minimum. So under the
route-preserving profile a follow is admitted only when the two parts are the
same railway's own geometry parts, or belong to one render group, or are a
reviewed landlord seed in `shared-corridors.json`'s new `displayLandlords`
table — 53 directed class pairs adjudicated by hand from the coincident spans,
with the two self-contradicting pairs recorded as `unresolved` rather than
guessed. Nothing else. A merely-near pair keeps its own centreline and takes a
parallel lane, which is what both rule sets ask for. The 130 follow runs this
produces are 107 same-railway and 23 reviewed-seed, none discovered, with a
median lateral of 0.1 m.

**Mode vocabulary.** N02 labels a line's mode with its own classes
(`jr_conventional`, `private`, `third_sector`, `shinkansen`, `maglev`,
`subway`, `tram`, `agt`, `monorail`, `funicular`). `KIND_ALIASES` maps them
onto the vocabulary `KIND_PRIORITY` and `HEAVY_RAIL` are written in, so the
"a follow never crosses the mode line" rule still means something here;
`highspeed` was added to both for 新幹線 and リニア (and picks up the one US
high-speed line, Brightline, which now correctly follows Tri-Rail into
MiamiCentral). A reviewed landlord seed outranks the mode test, because
Tokyo's through services really do run a 私鉄 train onto a 地下鉄's track.
`n02` joins the surveyed sources at rank 0 in `sourcePriority`.

**Loops.** `display-loops.json` (`jtm-display-loops-v1`) is the reviewed loop
table rules.md §7.8 and the Japan policy's §6.5 both ask for: the seam
station, the canonical winding, and what the canonical direction is called in
the operator's own language. The winding half is enforced in code —
`partRowsForLine` reverses any `loop` part whose shoelace area is negative, so
every ring in a continuous-stroke region is emitted anticlockwise in lon/lat
— and only ever for a part that actually CLOSES, because `isLoop` is a
property of the railway and a loop with a stem (山万's ユーカリが丘線) arrives as
two open parts whose shoelace sign is not a ring orientation. A reversed part
may carry neither a lane row nor a follow row, checked and thrown: measures
along a reversed part mirror, and rail-network.js derives its own unreversed
parts for the web. Everything else in the file is validated against the
package rather than trusted — a `closed-line` entry whose line is not
`isLoop`, or a seam station that is not on the line, is a build error. Four of
the six entries record what the package is NOT: 山手線 is an open arc
品川→田端 (the east side of the circle is 東北線's and 東海道線's own track and
has no 山手線 geometry at all), 名城線 is two open rows meeting at 金山 and
大曽根, and 大江戸線 is a lasso. Only 大阪環状線 (already anticlockwise, so
untouched) and the two small AGT/monorail rings are stored closed.

**Hubs.** `display-hubs.json` gains 17 Japanese throats. Three of them (新宿,
池袋, 札幌) deliberately declare no `trunkLineId`: no single railway owns the
alignment the others converge on there. 東京 is the one hub that needs the new
`laneOrderOnly` flag — its 2.2 km radius unavoidably covers Marunouchi and
Yaesu, where a dozen unrelated lines pass through on their own alignments, and
a hub slot is `index - (n-1)/2` against an iOS limit of `|lane| <= 8`. With
`laneOrderOnly` the hub bundles exactly the classes its `laneOrder` names and
leaves every other class inside the radius on the lane the general pass gave
it. 京葉線 is deliberately not named (its platforms are ~400 m away under
Yaesu, reached by their own tunnel: it shares the station name, not the
corridor). The assumed east-to-west track order is recorded in the hub's own
`laneOrderWhy`, together with the platform-numbering reading that would swap
its first two entries — an open question for the visual pass, not a settled
fact.

**The 233 hand rows in `jp-2025.json`'s own `lanes[]` are retired.** They are
still in the package, and no longer read: `build-display-lanes.mjs` says so on
stdout every run. `tw`, `hk`, `mo` and `kr` still pass their package rows
through unchanged and are unaffected by any of this.
