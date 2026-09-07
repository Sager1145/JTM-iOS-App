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

North America (`us`, `ca`) is written differently from the five older
regions, and drawn differently by both clients. A fragment there is one
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
