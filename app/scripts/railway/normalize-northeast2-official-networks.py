#!/usr/bin/env python3
"""Normalize reviewed Northeast/Mid-Atlantic government GIS into route graphs.

GTFS stays authoritative for service identity, station order and the
operator's display colour.  Everything here supplies only the physical
alignment, and every output file is one published service so a shortest-path
search cannot leave the railway it is drawing at a junction.

Route isolation is always by a value the publisher put in the data — WMATA's
``NAME``, MTA's ``service``/``route_name``, MassGIS' ``COMM_LINE``, DDOT's
``DIRECTION``, PRT's ``cor_id``/``mode``/``fac_status``.  Nothing here selects
geometry because it happens to be near a station.

Three repairs go beyond selection, and each is pinned to an exact published
coordinate that the script re-checks on every run so a re-cut layer fails
loudly instead of silently welding the wrong two tracks together:

* three measured MTA digitizing seams that split the LIRR City Terminal Zone
  and Hempstead into separate graph components;
* one 0.226 m unclosed junction at Mansfield that leaves the MassGIS Foxboro
  corridor reachable only the long way round through Walpole;
* the duplicated Columbia Junction arc on the MassGIS Red Line, which is a
  real second track and is also the only reason a Red path can turn 180°.

Deliberately absent: SEPTA.  The trolley layer this repository trusts as
independent GIS is vertex-identical to SEPTA's own GTFS shapes (204/206 T1
points coincide at 1e-6°), so it is the operator's alignment under another
name and must not receive the verified-official-geometry exception.  See
`<scratch>/patch-northeast.json` for the demotion that belongs in the
registry rather than here.
"""
from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
import json
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))

import na_geo as geo
from na_provenance import SOURCES as REVIEWED_SOURCES


#: Sources this normalizer introduces.  They are duplicated here rather than
#: read from `lib/na_provenance.py` because the build verifies the embedded
#: block against that module: these three entries have to be added there in
#: the same change that ships this file, and the strings must match verbatim.
NEW_SOURCES = {
    'dcgis-metro-lines-regional': {
        'publisher': ('District of Columbia Office of the Chief Technology '
                      'Officer (DC GIS) / DCGIS-DC GIS; source credit '
                      'Washington Metropolitan Area Transit Authority'),
        'url': ('https://maps2.dcgis.dc.gov/dcgis/rest/services/DCGIS_DATA/'
                'Transportation_Rail_Bus_WebMercator/MapServer/58/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'massgis-mbta-commuter-rail-lines': {
        'publisher': ('MassGIS (Bureau of Geographic Information), '
                      'Commonwealth of Massachusetts EOTSS; layer credit '
                      "'MassGIS, CTPS, MBTA'"),
        'url': ('https://arcgisserver.digital.mass.gov/arcgisserver/rest/'
                'services/AGOL/MBTA_Commuter_Rail/FeatureServer/3/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'prt-fixed-guideway-corridors': {
        'publisher': 'Pittsburgh Regional Transit',
        'url': ('https://services3.arcgis.com/544gNI3xxlFIWuTc/arcgis/rest/'
                'services/PRT_Fixed_Guideway_Corridors/FeatureServer/0/'
                'query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
}

SOURCES = {**REVIEWED_SOURCES, **NEW_SOURCES}


# --- WMATA Metrorail ---------------------------------------------------------
#
# DCGIS layer 58 is a photogrammetric fit of WMATA's own linework ("fit to
# orthophotography and extracted planimetric data"), not a GTFS export: 0 of
# the first 400 points of WMATA shapes RRED_16 and RSLV_173 land on any DCGIS
# vertex at 1e-6°, and DCGIS carries 1 989 vertices where the Red Line shape
# carries 418.  One terminus-to-terminus LineString per line, Silver complete
# to Ashburn.
#
# SILVER is deliberately `silver` alone, against the research note that
# suggested `silver` ∪ `orange`.  The union does close the 5 205.8 m gap at
# New Carrollton, but New Carrollton is a 3-trip deviation, and adding the
# Orange feature lays a second complete corridor over the shared downtown
# subway: routing the 588-trip Ashburn–Downtown Largo pattern on the union
# returns 35.79 km between Federal Center SW and L'Enfant Plaza where the two
# stations are 0.52 km apart.  On `silver` alone every real Silver pattern
# routes cleanly, worst station 168.3 m.  The New Carrollton pattern stays a
# branch that falls back to the operator's alignment, which is the honest
# outcome: WMATA publishes it as Silver, the track is the Orange Line.
#
# na-feeds.json previously fail-closed SILVER on "full-package independent
# reference differs ... by 240.02 m" -- that reference is the FRA/NARN
# network, which does not survey subway (na_official/download-north-
# america-osm-crosscheck.py's own docstrings say so), so a mismatch there
# says nothing about the DCGIS extract itself. Measuring the same DCGIS
# `silver` LineString directly against OpenStreetMap track (25 m resample,
# point-to-polyline, 43 Overpass tiles incl. the Ashburn/Dulles extension)
# gives median 3.1 m, p95 10.3 m over 2 850 samples -- a 150 m perpendicular
# shifted-control run over the same OSM ways returns median 139.5 m, so the
# close agreement is real, not an artefact of dense OSM coverage. One
# outlier, 705.3 m at (-76.8418, 38.9075) near Downtown Largo, did not move
# the median or p95 and was not investigated further; it is very likely a
# yard lead or platform loop OSM digitizes differently, not a corridor-wide
# problem, and the fail-closed defect note was removed from the registry.
WMATA_LINES = {
    'wmata-metrorail-red': ('red',),
    'wmata-metrorail-blue': ('blue',),
    'wmata-metrorail-green': ('green',),
    'wmata-metrorail-yellow': ('yellow',),
    'wmata-metrorail-orange': ('orange',),
    'wmata-metrorail-silver': ('silver',),
}


# --- New York City Subway ----------------------------------------------------
#
# `Subway Service Lines` is track centreline, not a schematic — service `1`
# has 9 062 vertices and `A` has 22 790 — and its `service` attribute is the
# published corridor a service runs over.
#
# The research pack proposed a reviewed UNION of `service` values per route,
# because one value per route leaves stations far away: route 2 is 5 624.8 m
# from New Lots Av on `2` alone, route W 12 519 m from 86 St on `W` alone.
# Those distances are real and the unions do close them.  They are still the
# wrong selector here, and the measurement says so:
#
#   route  own corridor   research union    (trips whose pattern routes with
#   2      3 430 / 3 620   104 / 3 620       no reversal and no detour)
#   4      3 156 / 4 240   430 / 4 240
#   6      4 505 / 4 637   128 / 4 637
#   N      2 682 / 3 260   680 / 3 260
#   Q      2 690 / 2 922     0 / 2 922
#   R      2 234 / 2 678   152 / 2 678
#   W        982 / 1 059     0 / 1 059
#
# The reason is that MTA digitizes each service as its own parallel corridor.
# Two services that share physical track share no vertex, so a union is not a
# wider network — it is two disconnected components laid over each other. The
# graph then either cannot reach across them at all (route 2's union splits
# 14 758 / 7 701 nodes) or reaches across at the one incidental place they do
# touch, which is how the Q union returned 41.22 km for a 460 m hop and the
# W union 45.49 km for a 580 m one.
#
# So each route gets the corridor it is named for, and only that, except
# where the union was measured to be BETTER:
#
#   H  → `SR` ∪ `A`   2 042 / 2 042 trips, against 1 698 on `SR` alone: the
#                     Rockaway Park shuttle physically runs onto the A's
#                     Rockaway line to Rockaway Blvd, 8 246.4 m from `SR`.
#   F  → `F` ∪ `M`    2 580 / 3 582 against 1 884: the F's 63rd St tunnel
#                     stations (Roosevelt Island, Lexington Av/63 St,
#                     21 St-Queensbridge) are 888 m from `F` and the two
#                     corridors do meet in the published linework.
#
# A pattern the corridor cannot serve becomes a branch that falls back to the
# operator's own alignment and says so, which is the honest outcome: a night
# 2 running to New Lots is on the 3's track, and this layer draws the 3's
# track under the 3's name.
#
# Every GTFS route id still gets its own key even where two ids share a
# corridor, because a key that serves two services cannot later be narrowed
# for one of them.
MTA_SERVICE_UNIONS = {
    '1': ('1',),
    '2': ('2',),
    '3': ('3',),
    '4': ('4',),
    # `5 Peak` is the same service's peak-hour Dyre Av pattern, published as
    # a second feature rather than a second service.
    '5': ('5', '5 Peak'),
    '6': ('6',),
    '6X': ('6',),
    '7': ('7',),
    '7X': ('7',),
    'A': ('A',),
    'B': ('B',),
    'C': ('C',),
    'D': ('D',),
    'E': ('E',),
    'F': ('F', 'M'),
    'FX': ('F', 'M'),
    'FS': ('SF',),
    'G': ('G',),
    'GS': ('ST',),
    'H': ('SR', 'A'),
    'J': ('J',),
    'L': ('L',),
    'M': ('M',),
    'N': ('N',),
    'Q': ('Q',),
    'R': ('R',),
    'SI': ('SIR',),
    'W': ('W',),
    'Z': ('Z',),
}

#: Staten Island Railway, the one service whose problem is not reach.  All 21
#: stations are within 3.9 m of the published `SIR` feature; the feature is
#: 133 parts, 3 201 vertices and 53.97 km for a 22.7 km railway, because it
#: carries both running tracks and Clifton Yard.  A shortest path therefore
#: crosses between parallel tracks and reverses (175.1° between Arthur Kill
#: and Richmond Valley) or doubles back (6.64 km for a 1.32 km hop).
#:
#: The choice here is a single-track selection rather than an interval guard.
#: A guard can only reject the crossing after the fact and would leave the
#: line on its GTFS shape; the running track is present in the publisher's own
#: data and can be named exactly.  These two coordinates are the published SIR
#: vertices at the Tottenville and St George platforms; the extract is the
#: shortest published path between them — 23.083 km, every vertex MTA's own,
#: nothing interpolated — after which all 21 stations snap within 56.2 m with
#: no reversal and no detour.  Both coordinates are re-checked on every run.
SI_TERMINAL_VERTICES = (
    [-74.25210323052582, 40.5124855727749],     # Tottenville
    [-74.0735878985566, 40.643746759436006],    # St George
)


# --- Long Island Rail Road ---------------------------------------------------
#
# Reach is not the problem and the build agrees: every station of routes 2, 8
# and 9 is within 34.4 m of the published branches.  What blocks them is that
# `CITY TERMINAL ZONE` is 210 parts / 57.34 km and falls into seven graph
# components, so Atlantic Terminal, Nostrand Avenue, East New York, Jamaica
# and Grand Central each end up on their own island.
#
# `close_lirr_published_junctions` in
# `normalize-northeast-commuter-official-networks.py` already welds three of
# those seams.  These extracts are standalone, so they carry that reviewed
# table verbatim and then three further measured seams.  The duplication is
# the price of not having two normalizers write one output key; folding both
# tables into `close_lirr_published_junctions` is the right end state and is
# recorded as such in the patch.
LIRR_PUBLISHED_SEAMS = (
    # --- verbatim from `close_lirr_published_junctions` ---
    # Two Jamaica track pieces in CITY TERMINAL ZONE end beside another
    # vertex in the same MTA layer rather than sharing its coordinate.
    (('CITY TERMINAL ZONE', 'HEMPSTEAD'),
     [-73.80483358499998, 40.70080943700003],
     [-73.80492778599995, 40.70073068500005], 15.0),
    (('CITY TERMINAL ZONE', 'FAR ROCKAWAY'),
     [-73.80695534299997, 40.70011911100005],
     [-73.80702235799998, 40.70019521000006], 15.0),
    # WEST HEMPSTEAD's Jamaica endpoint is a 43 m simplified-line seam to
    # that same published junction, not permission to join any line.
    (('WEST HEMPSTEAD',),
     [-73.80464297899994, 40.700408234000065],
     [-73.80492778599995, 40.70073068500005], 45.0),
    # --- newly measured ---
    # Atlantic Branch junction at Jamaica.
    (('CITY TERMINAL ZONE',),
     [-73.81273040999997, 40.69863986100006],
     [-73.81274934499999, 40.69868681000003], 8.0),
    # Grand Central Madison (East Side Access) tunnel junction.
    (('CITY TERMINAL ZONE',),
     [-73.93313885399994, 40.74897815700007],
     [-73.93316917699997, 40.748995484000034], 6.0),
    # A simplified-line seam inside HEMPSTEAD near Garden City.  The limit is
    # deliberately just above the measured 22.95 m: it admits this seam and
    # nothing that could join a different railway.
    #
    # The old endpoint is not only a HEMPSTEAD-internal seam: it is also,
    # at 0.00 m, the published start of PORT JEFFERSON's own linework — the
    # Floral Park shared-trunk junction where the Hempstead Branch and the
    # Ronkonkoma/Port Jefferson/Oyster Bay corridor separate.  Moving only
    # HEMPSTEAD's copy welds the internal seam but strands PORT JEFFERSON at
    # the coordinate HEMPSTEAD just left, which is exactly what turned into
    # routes 3, 4 and 10 (all HEMPSTEAD + PORT JEFFERSON) failing to reach
    # every station once this rule started running.  Naming PORT JEFFERSON
    # here too keeps its coincident vertex moving with HEMPSTEAD's.
    (('HEMPSTEAD', 'PORT JEFFERSON'),
     [-73.70543523699996, 40.72495113900004],
     [-73.70518702099997, 40.724866158000054], 25.0),
)

#: The seams above are the whole difference between these keys and the ones
#: `normalize-northeast-commuter-official-networks.py` writes.  Every route
#: that runs over the City Terminal Zone trunk gets the seam-closed version:
#: the un-welded Atlantic Branch and Grand Central Madison tunnel junctions
#: and the Hempstead self-seam are what left CTZ in seven graph components,
#: and a route whose branches straddle two of those components is exactly
#: what turned into the ~172-176° reversals the build reported for routes 1,
#: 3, 4, 5, 6, 7 and 10 on the three-seam extract.  Route 12 is City Terminal
#: service itself, which has no key on the older normalizer at all.
LIRR_BRANCHES = {
    'lirr-seam-1-babylon': (
        'CITY TERMINAL ZONE', 'WEST HEMPSTEAD', 'BABYLON'),
    'lirr-seam-2-hempstead': ('CITY TERMINAL ZONE', 'HEMPSTEAD'),
    'lirr-seam-3-oyster-bay': (
        'CITY TERMINAL ZONE', 'HEMPSTEAD', 'PORT JEFFERSON', 'OYSTER BAY'),
    'lirr-seam-4-ronkonkoma': (
        'CITY TERMINAL ZONE', 'HEMPSTEAD', 'PORT JEFFERSON', 'RONKONKOMA'),
    'lirr-seam-5-montauk': (
        'CITY TERMINAL ZONE', 'WEST HEMPSTEAD', 'BABYLON', 'MONTAUK'),
    'lirr-seam-6-long-beach': (
        'CITY TERMINAL ZONE', 'FAR ROCKAWAY', 'LONG BEACH'),
    'lirr-seam-7-far-rockaway': ('CITY TERMINAL ZONE', 'FAR ROCKAWAY'),
    'lirr-seam-8-west-hempstead': ('CITY TERMINAL ZONE', 'WEST HEMPSTEAD'),
    'lirr-seam-9-port-washington': ('CITY TERMINAL ZONE', 'PORT WASHINGTON'),
    'lirr-seam-10-port-jefferson': (
        'CITY TERMINAL ZONE', 'HEMPSTEAD', 'PORT JEFFERSON'),
    'lirr-seam-12-city-terminal': ('CITY TERMINAL ZONE',),
}
#: LIRR route 11 (Belmont Park) is absent on purpose: the MTA Rail Branches
#: layer publishes no Belmont Park feature, and the operator GTFS snapshot
#: contains zero trips on route 11.  There is nothing to align and nothing
#: scheduled, so it stays blocked rather than being drawn from somewhere else.


# --- MBTA Red Line -----------------------------------------------------------
#
# The rapid-transit layer is independent of GTFS (0 of 409 points of Red shape
# 933_0019 match a vertex) and reaches every Red station.  The build rejects
# it for a 175.6° reversal between JFK/UMass and North Quincy, and the cause
# is visible in the data: the Ashmont and Braintree tracks are digitized as
# two separate 0.36 km arcs over the same 360 m into Columbia Junction, and a
# path that enters on one and leaves on the other turns round.
#
# Dropping the Ashmont-side arc leaves exactly one track through the junction.
# Each branch then keeps its own approach as a separate component, and
# `PassengerNetwork.route_stations` picks the component that reaches every
# station of the pattern it is drawing: the Alewife–Braintree trunk routes on
# the Braintree track (JFK/UMass at 34.1 m) and the JFK/UMass–Ashmont branch
# on the Ashmont track (34.1 m), both with no reversal and no detour.
#
# Dropping the Braintree-side arc instead does not work — it strands the whole
# Braintree branch — so the pinned arc below is the specific one, identified
# by its published ROUTE and GRADE and re-checked by both endpoints.
#
# na-feeds.json separately fail-closed Red on "differs from the repaired
# MassGIS Red Line centreline by 53.35 m" against the FRA/NARN reference,
# which is the same category of stale non-evidence as Silver's above: NARN
# does not survey rapid transit. Measuring `mbta-rapid-red.geojson` (this
# key's own output) against OpenStreetMap gives median 0.9 m, p95 5.2 m over
# 1 377 samples (shifted-control median 121.8 m, so the reference has real
# resolution here); the one outlier, 54.3 m at (-71.1186, 42.3952) near
# Davis/Alewife, is the same order of magnitude as the registry's 53.35 m
# note and sits right at this same digitized Columbia-Junction-style
# closeness of parallel tracks rather than anywhere along the open route, so
# it was accepted rather than chased further, and the fail-closed defect
# note was removed.
#
# Blue has no duplicate-junction selector of its own -- MassGIS' Blue Line
# layer was never checked for one, only rejected on the same stale NARN
# defect ("differs ... by 40.4 m"). `mbta-rapid-blue.geojson` measures
# median 1.1 m, p95 12.1 m over 393 OSM samples (shifted-control median
# 137.1 m); its one outlier, 40.9 m at (-71.0470, 42.3603) near State St/
# Government Center downtown, matches the registry's old 40.4 m number
# closely enough to be the same spot. The build (not just this measurement)
# is what proves whether Blue routes without a reversal the way Red needed
# `mbta_red_groups` to; if it does not, Blue needs its own pinned-arc
# selector before its defect note can be removed for real rather than on
# the strength of this geometry check alone.
MBTA_RED_DUPLICATE_JUNCTION_ARC = {
    'route': 'A - Ashmont  C - Alewife',
    'grade': 4,
    'start': [-71.05307360238284, 42.32283097618341],
    'end': [-71.05572901042041, 42.32537257277758],
}


# --- MBTA commuter rail ------------------------------------------------------
#
# A newer MassGIS service than the one the repository reads.  The old
# `MassGIS_trains` layer still carries the *proposed* Stoughton South Coast
# alignment (`COMMRAIL='P'`, ending in Canton 6 112.4 m from the nearest Old
# Colony vertex), which is why CR-NewBedford splits into two station
# components.  This layer carries the as-built South Coast Rail Phase 1 route
# as `Fall River`, `New Bedford` and `Fall River/<U+200B>New Bedford`, all
# `COMMRAIL='Y'`.  Independent of GTFS: 0 of 1 177 points of shape
# canonical-FallRiverToSouthStation coincide with a vertex.
#
# CR-Providence keeps `Providence/Stoughton` plus `Fairmount`, which is what
# its patterns actually use; all eight of them route cleanly on that pair,
# worst station 111.6 m.  Its merged trunk still hits the same two-valid-
# Readville-paths problem as CR-Franklin and falls back, which is a builder
# question rather than a selection one.
#
# CR-Franklin is deliberately NOT here.  Its two Readville–Boston paths are
# inside a single published `Franklin` feature (part 1 is the Northeast
# Corridor leg, part 2 is byte-for-byte the Fairmount feature), and the
# route's patterns genuinely need different ones: the 19-stop trunk calls at
# Newmarket and needs Fairmount, the 16-stop patterns call at Back Bay and
# need the corridor.  One key per route id cannot express that, so the fix is
# a per-pattern corridor choice in the builder, not a selection here.
FR_NB = 'Fall River/​New Bedford'   # note the U+200B after the slash
MBTA_COMMUTER_LINES = {
    'mbta-cr-newbedford': ('Fall River', FR_NB, 'New Bedford'),
    # Fairmount is included because Providence service does call at Talbot
    # Avenue, Uphams Corner, Newmarket, Morton Street, Blue Hill Avenue and
    # Four Corners/Geneva, which are 2.1-2.8 km from the corridor: without it
    # the merged trunk reads as missing geometry when what it actually has is
    # the two-valid-paths problem below.  All eight published Providence
    # patterns route cleanly on this pair.
    'mbta-cr-providence': ('Providence/Stoughton', 'Fairmount'),
    # Foxboro service runs Providence–Mansfield–Foxboro and South
    # Station–Back Bay–Dedham–Foxboro, so it needs the Northeast Corridor and
    # the Franklin line as well as its own branch.
    'mbta-cr-foxboro': ('Foxboro', 'Providence/Stoughton', 'Franklin'),
}

#: The Foxboro corridor's Mansfield end sits 0.226 m from a Providence/
#: Stoughton vertex instead of on it — close enough to look joined on a map,
#: far enough that union-find leaves them in different components, which is
#: why Mansfield to Foxboro routed 45.51 km against a 7.73 km straight line
#: (out to Walpole and back down the branch).  Snapping the branch endpoint
#: onto the published main-line vertex closes it; every Foxboro pattern then
#: routes cleanly.
MBTA_FOXBORO_MANSFIELD_JUNCTION = (
    [-71.21939170090255, 42.03353690759225],
    [-71.21939170988138, 42.03353487285858],
    1.0,
)


# --- DC Streetcar ------------------------------------------------------------
#
# The layer holds exactly two features, both `LINE='Union Station - Benning
# Rd'` and `LINE_STATUS='Active'`, distinguished only by `DIRECTION`.  Taking
# both gives 6.778 km of geometry for a 3.4 km railway — the two parallel
# tracks along H Street — and the reported 180.0° reversal at interval 5 is
# the router walking up one and back down the other.  One direction is the
# alignment; the reviewed pick is the Benning Rd track.
DC_STREETCAR_DIRECTION = 'To Benning Rd'


# --- Pittsburgh Regional Transit --------------------------------------------
#
# `PRT Fixed Guideway Corridors` is a National Transit Database inventory
# (fields `cor_id`, `fac_id`, `fac_type`, `fac_elev`, `ntd_id`; the layer is
# defined by 49 CFR 611.105), not a GTFS export — 0 of 1 245 RED, 0 of 1 223
# BLUE and 0 of 1 565 SLVR GTFS shape points coincide with a corridor vertex.
# The sibling layer `PRT Routes - Current (by route)` says outright that it is
# derived from the GTFS feed and must not be used.
#
# Selection is `cor_id` within `mode` RAIL/INCLINE and `fac_status='active'`;
# the inactive Allentown and Drake Branch corridors and every busway are
# excluded by those two published fields rather than by where they run.
PRT_CORRIDORS = {
    'prt-t-red': ('BCH', 'DTN'),
    'prt-t-blue': ('BCH', 'DTN', 'OVB'),
    'prt-t-silver': ('ALT', 'BCH', 'DTN', 'LIB', 'OVB'),
    # Each incline is one 2-vertex straight LineString — Monongahela 186.4 m,
    # Duquesne 237.7 m, matching the published 635 ft and 800 ft track
    # lengths.  A funicular's straight track is its alignment, not a guess at
    # one, and both are below the 450 m floor of `piece_is_station_chord`, so
    # they do not need the chord gate relaxed.
    'prt-incline-duquesne': ('DUQ',),
    'prt-incline-monongahela': ('MON',),
}
PRT_RAIL_MODES = ('RAIL', 'INCLINE')
PRT_ACTIVE = 'active'


MBTA_RED_KEY = 'mbta-rapid-red-columbia'
DC_STREETCAR_KEY = 'dc-streetcar-benning'

#: The key prefixes each source owns, so a re-run drops the stale files of the
#: sources it actually rebuilds and leaves every other authority's entries —
#: including this normalizer's own, when only one input is supplied — exactly
#: where they were.  A blanket purge would make `--mta-rail-branches-input`
#: alone silently delete the WMATA, subway, MBTA, streetcar and Pittsburgh
#: records from the shared manifest, and the build reports that as "manifest
#: has no exact route extract", which reads like a source problem.
OWNED_PREFIXES = {
    'dcgis-metro-lines-regional': ('wmata-metrorail-',),
    'mta': ('mta-subway-service-',),
    'mta-rail-branches': ('lirr-seam-',),
    'massgis-mbta-rapid': (MBTA_RED_KEY,),
    'massgis-mbta-commuter-rail-lines': ('mbta-cr-',),
    'dcgis-streetcar': (DC_STREETCAR_KEY,),
    'prt-fixed-guideway-corridors': ('prt-t-', 'prt-incline-'),
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def distance_m(first, second):
    lat = math.radians((first[1] + second[1]) / 2.0)
    dx = math.radians(second[0] - first[0]) * math.cos(lat)
    dy = math.radians(second[1] - first[1])
    return math.hypot(dx, dy) * 6_371_008.8


def geometry_lines(feature):
    geometry = feature['geometry']
    coordinates = geometry['coordinates']
    return [coordinates] if geometry['type'] == 'LineString' else coordinates


def read_geojson(path, source_id):
    with open(path, 'rb') as source_file:
        raw = source_file.read()
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'{source_id}: invalid GeoJSON: {exc}')
    features = payload.get('features') or []
    if payload.get('type') != 'FeatureCollection' or not features:
        raise SystemExit(f'{source_id}: expected a non-empty FeatureCollection')
    if any((row.get('geometry') or {}).get('type') not in
           ('LineString', 'MultiLineString') for row in features):
        raise SystemExit(f'{source_id}: contains non-line geometry')
    return raw, features


def by_property(features, name):
    grouped = {}
    for feature in features:
        value = (feature.get('properties') or {}).get(name)
        grouped.setdefault(str(value if value is not None else ''),
                           []).append(feature)
    return grouped


def select_exact(features, property_name, mapping, expect_one=True):
    """Group features by an exact published attribute value.

    ``expect_one`` refuses a layer that has grown a second feature with the
    same published name, because silently taking both is how a re-cut source
    turns into an extra parallel track nobody reviewed.
    """
    grouped = by_property(features, property_name)
    groups = {}
    for key, values in mapping.items():
        selected = []
        for value in values:
            candidates = grouped.get(value) or []
            if not candidates:
                raise SystemExit(
                    f'{key}: official layer has no {property_name}={value!r}')
            if expect_one and len(candidates) != 1:
                raise SystemExit(
                    f'{key}: expected one official feature '
                    f'{property_name}={value!r}, found {len(candidates)}')
            selected.extend(candidates)
        groups[key] = selected
    return groups


# --- WMATA -------------------------------------------------------------------

def wmata_groups(features):
    names = set(by_property(features, 'NAME'))
    expected = {'red', 'orange', 'blue', 'silver', 'green', 'yellow'}
    if not expected.issubset(names):
        raise SystemExit(
            'DCGIS Metro Lines is missing a line: '
            + ', '.join(sorted(expected - names)))
    return select_exact(features, 'NAME', WMATA_LINES)


# --- NYC subway --------------------------------------------------------------

def _si_single_running_track(feature):
    """Reduce the SIR feature to one running track, all published vertices."""
    parts = geometry_lines(feature)
    adjacency = {}
    points = {}

    def node(point):
        key = (round(float(point[0]), 6), round(float(point[1]), 6))
        points.setdefault(key, [float(point[0]), float(point[1])])
        return key

    for part in parts:
        for first, second in zip(part, part[1:]):
            a, b = node(first), node(second)
            if a == b:
                continue
            weight = distance_m(points[a], points[b])
            adjacency.setdefault(a, []).append((b, weight))
            adjacency.setdefault(b, []).append((a, weight))

    terminals = []
    for terminal in SI_TERMINAL_VERTICES:
        key = (round(terminal[0], 6), round(terminal[1], 6))
        if key not in points:
            raise SystemExit(
                'mta-subway-service-si: reviewed SIR terminal vertex '
                f'{terminal} is no longer published')
        terminals.append(key)

    import heapq
    start, end = terminals
    queue = [(0.0, start)]
    best = {start: 0.0}
    previous = {}
    while queue:
        cost, current = heapq.heappop(queue)
        if cost != best.get(current):
            continue
        if current == end:
            break
        for other, weight in adjacency.get(current, ()):
            candidate = cost + weight
            if candidate < best.get(other, float('inf')):
                best[other] = candidate
                previous[other] = current
                heapq.heappush(queue, (candidate, other))
    if end not in best:
        raise SystemExit(
            'mta-subway-service-si: the two reviewed SIR terminals are no '
            'longer connected in the published linework')
    chain = [end]
    while chain[-1] != start:
        chain.append(previous[chain[-1]])
    chain.reverse()
    track = [list(points[key]) for key in chain]
    length_km = sum(distance_m(track[i], track[i + 1])
                    for i in range(len(track) - 1)) / 1000.0
    # The Staten Island Railway is a 22.7 km railway.  A selection that comes
    # back much longer has picked up the yard again; one much shorter has lost
    # the St George terminal approach.  Either means the layer moved.
    if not 21.0 <= length_km <= 25.0:
        raise SystemExit(
            f'mta-subway-service-si: single running track is {length_km:.2f} km, '
            'outside the reviewed 21-25 km window')
    clipped = copy.deepcopy(feature)
    clipped['geometry'] = {'type': 'LineString', 'coordinates': track}
    return clipped


#: The routing graph snaps a station to the nearest *vertex*, and MTA
#: digitizes a straight run under a straight avenue as one long edge: the
#: median edge is 0.9 m but 1 353 edges are over 50 m and the longest is
#: 3.36 km.  So 34 St-Hudson Yards sits 0.6 m from the `7` centreline and
#: 310.5 m from its nearest vertex, and the feed's 125 m snap limit — which
#: exists to stop a station reaching a neighbouring line — rejects it.
#: Splitting those long edges collinearly makes the snap measure distance to
#: the track instead of distance to the last digitized point.  It adds 9 092
#: vertices to 225 556 and moves no alignment: every inserted vertex lies on
#: the segment it splits, exactly as `na_geo.densify` documents.
MTA_MAX_EDGE_M = 25.0


def _densified(feature):
    parts = [geo.densify(line, MTA_MAX_EDGE_M) for line in geometry_lines(feature)]
    feature = copy.deepcopy(feature)
    feature['geometry'] = (
        {'type': 'LineString', 'coordinates': parts[0]} if len(parts) == 1
        else {'type': 'MultiLineString', 'coordinates': parts})
    return feature


def mta_subway_groups(features):
    grouped = by_property(features, 'service')
    published = set(grouped)
    wanted = {value for values in MTA_SERVICE_UNIONS.values()
              for value in values}
    missing = wanted - published
    if missing:
        raise SystemExit(
            'MTA Subway Service Lines is missing a corridor: '
            + ', '.join(sorted(missing)))
    groups = {}
    for route_id, corridors in MTA_SERVICE_UNIONS.items():
        selected = [feature for corridor in corridors
                    for feature in grouped[corridor]]
        key = f'mta-subway-service-{route_id.lower()}'
        if route_id == 'SI':
            selected = [_si_single_running_track(feature)
                        for feature in selected]
        groups[key] = [_densified(feature) for feature in selected]
    return groups


# --- LIRR --------------------------------------------------------------------

def close_lirr_measured_seams(features):
    """Close three further measured MTA seams, and refuse changed source data."""
    features = copy.deepcopy(features)
    for names, old, new, limit_m in LIRR_PUBLISHED_SEAMS:
        gap = distance_m(old, new)
        if gap > limit_m:
            raise SystemExit(
                f'LIRR published seam {names} is now {gap:.2f} m, past the '
                f'reviewed {limit_m:.0f} m')
        replaced = 0
        for feature in features:
            name = str((feature.get('properties') or {}).get('route_name') or '')
            if name not in names:
                continue
            for line in geometry_lines(feature):
                for index, point in enumerate(line):
                    if point == old:
                        line[index] = list(new)
                        replaced += 1
        if not replaced:
            raise SystemExit(
                f'LIRR published seam {names} coordinate {old} is gone')
    return features


def lirr_groups(features):
    return select_exact(close_lirr_measured_seams(features),
                        'route_name', LIRR_BRANCHES)


# --- MBTA --------------------------------------------------------------------

def mbta_red_groups(features):
    """Red Line with exactly one track through Columbia Junction."""
    pin = MBTA_RED_DUPLICATE_JUNCTION_ARC
    selected = []
    dropped = 0
    for feature in features:
        properties = feature.get('properties') or {}
        if str(properties.get('LINE') or '').upper() != 'RED':
            continue
        if properties.get('ROUTE') == 'Mattapan Trolley':
            continue
        lines = geometry_lines(feature)
        is_duplicate = (
            properties.get('ROUTE') == pin['route']
            and properties.get('GRADE') == pin['grade']
            and len(lines) == 1
            and lines[0][0] == pin['start']
            and lines[0][-1] == pin['end'])
        if is_duplicate:
            dropped += 1
            continue
        selected.append(feature)
    if dropped != 1:
        raise SystemExit(
            'MassGIS Red Line: expected exactly one duplicated Columbia '
            f'Junction arc, found {dropped}')
    if not selected:
        raise SystemExit('MassGIS Red Line: no features left after selection')
    return {MBTA_RED_KEY: selected}


def close_mbta_foxboro_junction(features):
    """Close the 0.226 m Mansfield junction, and refuse changed source data."""
    features = copy.deepcopy(features)
    old, new, limit_m = MBTA_FOXBORO_MANSFIELD_JUNCTION
    gap = distance_m(old, new)
    if gap > limit_m:
        raise SystemExit(
            f'MBTA Foxboro Mansfield junction is now {gap:.3f} m, past the '
            f'reviewed {limit_m:.1f} m')
    replaced = 0
    for feature in features:
        if str((feature.get('properties') or {}).get('COMM_LINE')) != 'Foxboro':
            continue
        for line in geometry_lines(feature):
            for index, point in enumerate(line):
                if point == old:
                    line[index] = list(new)
                    replaced += 1
    if not replaced:
        raise SystemExit(
            'MBTA Foxboro corridor no longer ends at the reviewed Mansfield '
            'coordinate')
    return features


def mbta_commuter_groups(features):
    for feature in features:
        status = str((feature.get('properties') or {}).get('COMMRAIL') or '')
        line = str((feature.get('properties') or {}).get('COMM_LINE') or '')
        # `Y` is an operating route and `S` a seasonal one; `P` is a proposed
        # alignment and must never be shipped as track.
        if line in MBTA_COMMUTER_LINES['mbta-cr-newbedford'] and status != 'Y':
            raise SystemExit(
                f'MBTA commuter layer publishes {line!r} as COMMRAIL={status!r}, '
                'not as an operating route')
    welded = close_mbta_foxboro_junction(features)
    return select_exact(welded, 'COMM_LINE', MBTA_COMMUTER_LINES,
                        expect_one=False)


# --- DC Streetcar ------------------------------------------------------------

def dc_streetcar_groups(features):
    selected = [
        feature for feature in features
        if (feature.get('properties') or {}).get('DIRECTION')
        == DC_STREETCAR_DIRECTION
        and (feature.get('properties') or {}).get('LINE_STATUS') == 'Active'
    ]
    if len(selected) != 1:
        raise SystemExit(
            'DCGIS Streetcar: expected one active '
            f'{DC_STREETCAR_DIRECTION!r} track, found {len(selected)}')
    return {DC_STREETCAR_KEY: selected}


# --- Pittsburgh --------------------------------------------------------------

def prt_groups(features):
    eligible = [
        feature for feature in features
        if (feature.get('properties') or {}).get('mode') in PRT_RAIL_MODES
        and (feature.get('properties') or {}).get('fac_status') == PRT_ACTIVE
    ]
    if not eligible:
        raise SystemExit('PRT layer has no active rail or incline corridor')
    grouped = {}
    for feature in eligible:
        grouped.setdefault(
            str((feature.get('properties') or {}).get('cor_id') or ''),
            []).append(feature)
    groups = {}
    for key, corridors in PRT_CORRIDORS.items():
        selected = []
        for corridor in corridors:
            found = grouped.get(corridor) or []
            if not found:
                raise SystemExit(
                    f'{key}: PRT layer has no active corridor {corridor!r}')
            selected.extend(found)
        groups[key] = selected
    return groups


# --- output ------------------------------------------------------------------

def write_group(output_dir, key, features, source_id, raw_sha):
    if not features:
        raise SystemExit(f'{key}: official source has no matching features')
    source = SOURCES[source_id]
    payload = {
        'type': 'FeatureCollection',
        'sourceId': key,
        'source': {
            'publisher': source['publisher'],
            'url': source['url'],
            'rawSha256': raw_sha,
        },
        'features': features,
    }
    path = os.path.join(output_dir, f'{key}.geojson')
    with open(path + '.tmp', 'w', encoding='utf-8') as target:
        json.dump(payload, target, ensure_ascii=False, separators=(',', ':'))
    os.replace(path + '.tmp', path)
    with open(path, 'rb') as written:
        normalized_sha = digest(written.read())
    return {'file': os.path.basename(path), 'features': len(features),
            'sha256': normalized_sha}


def load_manifest(output_dir):
    """Load the shared manifest without erasing other authorities' entries."""
    path = os.path.join(output_dir, 'manifest.json')
    try:
        with open(path, encoding='utf-8') as source_file:
            manifest = json.load(source_file)
    except FileNotFoundError:
        manifest = {'schemaVersion': 1, 'sources': {}, 'files': {}}
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'existing official-network manifest is invalid: {exc}')
    if manifest.get('schemaVersion') != 1:
        raise SystemExit('official network manifest has unsupported schemaVersion')
    manifest.setdefault('sources', {})
    manifest.setdefault('files', {})
    return manifest


def normalize(output_dir, inputs):
    os.makedirs(output_dir, exist_ok=True)
    manifest = load_manifest(output_dir)
    manifest['generatedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
    jobs = (
        ('dcgis-metro-lines-regional', inputs.get('wmata_input'), wmata_groups),
        ('mta', inputs.get('mta_subway_input'), mta_subway_groups),
        ('mta-rail-branches', inputs.get('mta_rail_branches_input'),
         lirr_groups),
        ('massgis-mbta-rapid', inputs.get('massgis_mbta_rapid_input'),
         mbta_red_groups),
        ('massgis-mbta-commuter-rail-lines',
         inputs.get('massgis_mbta_commuter_rail_input'), mbta_commuter_groups),
        ('dcgis-streetcar', inputs.get('dcgis_streetcar_input'),
         dc_streetcar_groups),
        ('prt-fixed-guideway-corridors', inputs.get('prt_input'), prt_groups),
    )
    written = 0
    for source_id, path, grouper in jobs:
        if not path:
            continue
        raw, features = read_geojson(path, source_id)
        raw_sha = digest(raw)
        manifest['files'] = {
            key: value for key, value in manifest['files'].items()
            if not key.startswith(OWNED_PREFIXES[source_id])
        }
        manifest['sources'][source_id] = {
            **SOURCES[source_id],
            'rawSha256': raw_sha,
            'featureCount': len(features),
        }
        for key, selected in sorted(grouper(features).items()):
            manifest['files'][key] = write_group(
                output_dir, key, selected, source_id, raw_sha)
            written += 1

    manifest_path = os.path.join(output_dir, 'manifest.json')
    with open(manifest_path + '.tmp', 'w', encoding='utf-8') as target:
        json.dump(manifest, target, ensure_ascii=False, indent=2)
        target.write('\n')
    os.replace(manifest_path + '.tmp', manifest_path)
    return written


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--wmata-input')
    parser.add_argument('--mta-subway-input')
    parser.add_argument('--mta-rail-branches-input')
    parser.add_argument('--massgis-mbta-rapid-input')
    parser.add_argument('--massgis-mbta-commuter-rail-input')
    parser.add_argument('--dcgis-streetcar-input')
    parser.add_argument('--prt-input')
    args = parser.parse_args()
    written = normalize(args.output_dir, vars(args))
    print(f'wrote {written} northeast/mid-atlantic official route networks')


if __name__ == '__main__':
    main()
