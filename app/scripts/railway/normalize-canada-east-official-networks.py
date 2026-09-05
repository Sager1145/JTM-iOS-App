#!/usr/bin/env python3
"""Build eastern-Canada passenger networks from three government track layers.

Three services were blocked for three different reasons, and one publisher
answers each.

exo's own Geomatics host refuses TCP on 443, so there is no reproducible
download behind the Données Québec record for `lignes-de-train-exo`.  The
Ministère des Transports et de la Mobilité durable publishes the provincial
railway inventory instead, and it names EXO as a track user or operator on
618 of its records — a rail asset inventory with owner, operator, user,
subdivision, mileage and track class, not a repackaged `shapes.txt`.

Ontario's UP Express weaves through the Bathurst corridor on ORWN because
ORWN has no name for the airport spur; NRCan's National Railway Network
carries an explicit `Pearson` subdivision for it, so the branch is a selector
rather than something a router has to find among parallel tracks.

Toronto's 306 and 506 Carlton were blocked on a 294 m deviation measured
against OpenStreetMap.  The City's own `COTGEO_TTC_TRACK` asset centreline
does not reproduce it — its whole schema is OBJECTID / TRACK_ID /
Shape__Length, with no route id and no colour, so it cannot have come from a
GTFS feed, and the GTFS vertices sit a median 1.4 m from it.

Each service is isolated by an attribute its own publisher prints — a Québec
subdivision name, an NRWN subdivision and track class, a City route id — and
the operator's GTFS station order then chooses the path across that
selection.  GTFS selects; every coordinate written here comes from the
government layer.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import io
import json
import math
import os
import sys
import zipfile
from collections import defaultdict

import shapefile


HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'lib'))
import na_build as build
import na_geo as geo
import na_narn


SOURCES = {
    'quebec-mtq-reseau-ferroviaire': {
        'publisher': ('Ministère des Transports et de la Mobilité durable '
                      'du Québec'),
        'catalogUrl': ('https://www.donneesquebec.ca/recherche/dataset/'
                       'reseau-ferroviaire'),
        'url': ('https://ws.mapserver.transports.gouv.qc.ca/swtq?'
                'service=wfs&version=2.0.0&request=getfeature&'
                'typename=ms:reseau_chfer_qc&outfile=ReseauFerroviaire&'
                'srsname=EPSG:4326&outputformat=geojson'),
        'license': 'Creative Commons Attribution 4.0 (CC-BY 4.0)',
    },
    'nrcan-nrwn-on': {
        'publisher': ('Natural Resources Canada - GeoBase National Railway '
                      'Network'),
        'catalogUrl': ('https://open.canada.ca/data/en/dataset/'
                       'ac26807e-a1e8-49fa-87bf-451175a859b8'),
        'url': ('https://ftp.maps.canada.ca/pub/nrcan_rncan/vector/'
                'geobase_nrwn_rfn/on/nrwn_rfn_on_shp_en.zip'),
        'license': 'Open Government Licence - Canada',
    },
    'toronto-ttc-track': {
        'publisher': 'City of Toronto - Geospatial Competency Centre',
        'catalogUrl': ('https://services3.arcgis.com/b9WvedVPoizGfvfD/'
                       'arcgis/rest/services/COTGEO_TTC_TRACK/FeatureServer/0'),
        'url': ('https://services3.arcgis.com/b9WvedVPoizGfvfD/arcgis/rest/'
                'services/COTGEO_TTC_TRACK/FeatureServer/0/query?'
                'where=1%3D1&outFields=*&outSR=4326&returnGeometry=true&'
                'f=geojson&resultRecordCount=10000'),
        'license': 'Open Government Licence - Toronto',
    },
    # Declared, hashed, and used for nothing but the route selector below.
    # No output key is owned by it, because none of its coordinates are
    # written: its identity half is verbatim GTFS `routes.txt`, and a source
    # that carries an operator's own route id cannot also be the independent
    # survey that verifies it.
    'toronto-ttc-route-view': {
        'publisher': 'City of Toronto - Geospatial Competency Centre',
        'catalogUrl': ('https://services3.arcgis.com/b9WvedVPoizGfvfD/arcgis/'
                       'rest/services/'
                       'COT_Geospatial_TTC_Streetcar_Route_view/'
                       'FeatureServer/0'),
        'url': ('https://services3.arcgis.com/b9WvedVPoizGfvfD/arcgis/rest/'
                'services/COT_Geospatial_TTC_Streetcar_Route_view/'
                'FeatureServer/0/query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson&resultRecordCount=2000'),
        'license': 'Open Government Licence - Toronto',
    },
}

#: Québec prints a subdivision name on every main-track record, and each exo
#: line runs over a named few.  Two lines share `Westmount` and two share
#: `Adirondack`, so the subdivision narrows the province to a corridor and the
#: operator's own station order picks the line within it — the same division of
#: labour as the ORWN selection in `normalize-ca-central-official-networks.py`.
#: Every name here was read off the MTQ record nearest each vertex of that
#: route's longest published shape; none was guessed from a map.
MTQ_ROUTE_SUBDIVISIONS = {
    '1': {'Vaudreuil', 'M & O', 'Westmount', 'Winchester'},
    '3': {'St-Hyacinthe', 'Montreal'},
    '4': {'Parc', 'Adirondack', 'Westmount'},
    # `Vaudreuil` is one record: the junction at Montréal-Ouest that the
    # Candiac train crosses to reach the Westmount subdivision.  Without it
    # the corridor is severed there and the line cannot be routed at all.
    '5': {'Adirondack', 'Westmount', 'Vaudreuil'},
    '6': {'St-Laurent', 'Joliette'},
}
#: Mascouche is the line the subdivision list cannot carry on its own: exo
#: owns its northern half outright and MTQ leaves `nomsubdiv1` empty there,
#: naming exo as both operator and user instead.  Accepting a record that
#: names EXO anywhere is what joins that half to the CN subdivisions the
#: trains reach it over.
MTQ_EXO_CODE = 'EXO'
#: The only line whose corridor includes track MTQ records without a
#: subdivision name.  Every other exo line is isolated by subdivision alone.
MTQ_UNNAMED_EXO_ROUTES = {'6'}
MTQ_OPERATIONAL = 'Opérationnel'
#: `Triage` is a yard and `Transbordeur` is a car float; neither is a
#: passenger path.  The rest are the French names of the ORWN classes this
#: repository already admits.
MTQ_TRACK_CLASSES = {
    'Principale', 'Évitement', 'Liaison', 'Bretelle', 'Épi',
    'Triangle de virage',
}

#: NRWN's own subdivision names, read the same way off the record nearest each
#: vertex of the Metrolinx shapes.  `Pearson` is the whole point: it is the
#: airport spur, named, which is what ORWN could not offer.
NRWN_ROUTE_SUBDIVISIONS = {
    'nrwn-on-up-up': {'Weston', 'Pearson'},
    'nrwn-on-go-ki': {'Weston', 'Guelph', 'Halton', 'Galt'},
}
NRWN_OPERATIONAL = 'Operational'
NRWN_ADMIN_AREA = 'Ontario'
#: `Yard` is here for one reason and it is a good one: NRWN classifies the
#: Union Station Rail Corridor as yard track, so refusing yard refuses the
#: platforms every Kitchener train ends its journey on, and the terminus then
#: snaps 446 m away to the nearest main line.  What keeps the rest of Toronto's
#: yards out is not the class but the corridor test below, which admits a
#: record only where it runs along the passenger alignment for most of its
#: length.
NRWN_TRACK_CLASSES = {
    'Main', 'Siding', 'Crossover', 'Connecting', 'Wye', 'Yard',
}

#: The City publishes one already-isolated line per streetcar route, and its
#: `ROUTE_ID` is the only published attribute anywhere that separates the
#: Carlton night car from the Carlton day car.  Its geometry is not used; it
#: is snapped to `COTGEO_TTC_TRACK` and would add nothing but a second copy.
#:
#: Queen and Dundas are here for a different reason than Carlton: their GTFS
#: shapes sit a median 1-3 m from the City track, but with a stop every
#: 250 m along a straight street, a shape that follows the street is
#: indistinguishable from stop-to-stop chords to the builder's schematic
#: test, and both routes were refused as "no usable alignment".  The City
#: track carries them instead, on the same terms as Carlton.
TTC_ROUTE_KEYS = {
    '306': 'ttc-streetcar-306',
    '501': 'ttc-streetcar-501',
    '505': 'ttc-streetcar-505',
    '506': 'ttc-streetcar-506',
}

#: How far a surveyed record may sit from the operator's own alignment and
#: still be admitted.  Québec is measured at one vertex, because MTQ segments
#: its inventory at every junction and a connecting piece that leaves the
#: corridor at its far end is still the piece the corridor needs; 300 m is
#: enough for the two Montréal lines that approach the Mont-Royal tunnel the
#: REM took over.  Ontario and Toronto are measured across most of the record,
#: because there the clutter to exclude is a parallel track a few metres away
#: and admitting it on one grazing vertex is what made the previous ORWN
#: routing double back through the Bathurst corridor.
MTQ_CORRIDOR_M = 300.0
NRWN_CORRIDOR_M = 15.0
NRWN_CORRIDOR_SHARE = 0.8
TTC_CORRIDOR_M = 25.0
TTC_CORRIDOR_SHARE = 0.8
#: Two exo stations really are hundreds of metres from any railway MTQ still
#: records: Montréal's Mont-Royal tunnel approach passed to the REM, which is
#: a light metro and therefore outside a railway inventory.  Mascouche's
#: terminus at Gare Centrale is 446 m from the nearest surviving track and
#: Mont-Saint-Hilaire's is 185 m.  Both are the published station beside a
#: railway the province no longer owns, not a routing failure, and refusing
#: them would delete two lines to avoid admitting a known gap.
MTQ_STATION_OFFSET_M = 600.0


def digest(data):
    return hashlib.sha256(data).hexdigest()


# ------------------------------------------------------------------ readers


def read_mtq(raw):
    """The Québec railway inventory as ``(properties, lines)`` records."""
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'MTQ railway network is not valid GeoJSON: {exc}')
    if payload.get('type') != 'FeatureCollection':
        raise SystemExit('MTQ railway network is not a FeatureCollection')
    features = []
    for feature in payload.get('features') or ():
        properties = feature.get('properties') or {}
        geometry = feature.get('geometry') or {}
        coordinates = geometry.get('coordinates') or []
        lines = ([coordinates] if geometry.get('type') == 'LineString'
                 else coordinates if geometry.get('type') == 'MultiLineString'
                 else [])
        lines = [[list(point) for point in line]
                 for line in lines if len(line) >= 2]
        if lines:
            features.append((properties, lines))
    required = {'siguti1vo', 'siguti2vo', 'siglexploi', 'nomsubdiv1',
                'nomsubdiv2', 'classvoie', 'etat'}
    if not features or not required.issubset(features[0][0]):
        raise SystemExit('MTQ railway network is missing its audited fields')
    if len(features) < 10_000:
        raise SystemExit('MTQ railway network is unexpectedly incomplete')
    return features


def zip_member(archive, name_end):
    names = [name for name in archive.namelist()
             if name.upper().endswith(name_end.upper())]
    if len(names) != 1:
        raise SystemExit(f'NRWN archive must contain exactly one {name_end}')
    return io.BytesIO(archive.read(names[0]))


def read_nrwn(raw):
    """The Ontario National Railway Network track layer."""
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            reader = shapefile.Reader(
                shp=zip_member(archive, 'TRACK.shp'),
                shx=zip_member(archive, 'TRACK.shx'),
                dbf=zip_member(archive, 'TRACK.dbf'),
                encoding='cp1252')
            fields = [field[0] for field in reader.fields[1:]]
            required = {'STATUS', 'TRACKCLASS', 'SUBDI1NAME', 'SUBDI2NAME',
                        'ADMINAREA', 'GEOACQTECH', 'GEOACCURA', 'OPERATOENA',
                        'TRKUSR1ENA'}
            if not required.issubset(fields):
                raise SystemExit('NRWN track schema is missing audited fields')
            features = []
            for shape_record in reader.iterShapeRecords():
                properties = dict(zip(fields, shape_record.record))
                points = [list(point) for point in shape_record.shape.points]
                parts = list(shape_record.shape.parts) + [len(points)]
                lines = [points[start:end]
                         for start, end in zip(parts, parts[1:])
                         if end - start >= 2]
                if lines:
                    features.append((properties, lines))
    except (OSError, zipfile.BadZipFile, shapefile.ShapefileException) as exc:
        raise SystemExit(f'NRWN track archive is invalid: {exc}')
    if len(features) < 10_000:
        raise SystemExit('NRWN track archive is unexpectedly incomplete')
    return features


def read_geojson_lines(raw, label, required_fields):
    """A City of Toronto ArcGIS response as ``(properties, lines)`` records."""
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f'{label} is not valid GeoJSON: {exc}')
    if payload.get('type') != 'FeatureCollection':
        raise SystemExit(f'{label} is not a FeatureCollection')
    if payload.get('exceededTransferLimit'):
        # The City caps some of its layers at a page and says so in the
        # response.  A truncated track layer would silently shorten a railway,
        # so refuse it rather than publish half of one.
        raise SystemExit(f'{label} is a truncated page, not the whole layer')
    features = []
    for feature in payload.get('features') or ():
        properties = feature.get('properties') or {}
        geometry = feature.get('geometry') or {}
        coordinates = geometry.get('coordinates') or []
        lines = ([coordinates] if geometry.get('type') == 'LineString'
                 else coordinates if geometry.get('type') == 'MultiLineString'
                 else [])
        lines = [[list(point) for point in line]
                 for line in lines if len(line) >= 2]
        if lines:
            features.append((properties, lines))
    if not features:
        raise SystemExit(f'{label} contains no line geometry')
    if not required_fields.issubset(features[0][0]):
        raise SystemExit(f'{label} is missing its audited fields')
    return features


# -------------------------------------------------------------------- GTFS


def gtfs_patterns(path, route_ids, operator):
    """Maximal station patterns, and the longest shape, per route.

    A pattern is one ordered list of distinct stops.  Reverse-direction
    duplicates collapse onto one another, and a pattern that is a subsequence
    of a longer one is dropped, so a short-turn does not become a second
    railway.  The shapes are kept only to draw the selection corridor.
    """
    with zipfile.ZipFile(path) as archive:
        def rows(name):
            return list(csv.DictReader(io.TextIOWrapper(
                archive.open(name), encoding='utf-8-sig', newline='')))

        routes = {row['route_id'] for row in rows('routes.txt')
                  if row['route_id'] in route_ids}
        trips = {row['trip_id']: row for row in rows('trips.txt')
                 if row.get('route_id') in routes}
        stops = {row['stop_id']: row for row in rows('stops.txt')}
        shape_points = defaultdict(list)
        wanted_shapes = {trip.get('shape_id') for trip in trips.values()}
        for row in rows('shapes.txt'):
            if row.get('shape_id') in wanted_shapes:
                shape_points[row['shape_id']].append((
                    int(row['shape_pt_sequence']),
                    [float(row['shape_pt_lon']), float(row['shape_pt_lat'])]))
        times = defaultdict(list)
        for row in rows('stop_times.txt'):
            if row.get('trip_id') in trips and row.get('stop_id') in stops:
                times[row['trip_id']].append(
                    (int(row['stop_sequence']), row['stop_id']))

    shapes = {shape_id: [point for _, point in sorted(sequence)]
              for shape_id, sequence in shape_points.items()}
    result = {route_id: {'patterns': {}, 'shapes': {}}
              for route_id in sorted(routes)}
    for trip_id, sequence in times.items():
        trip = trips[trip_id]
        route_id = trip['route_id']
        stop_ids = []
        points = []
        for _, stop_id in sorted(sequence):
            if stop_ids and stop_ids[-1] == stop_id:
                continue
            stop = stops[stop_id]
            try:
                point = [float(stop['stop_lon']), float(stop['stop_lat'])]
            except (KeyError, TypeError, ValueError):
                continue
            stop_ids.append(stop_id)
            points.append(point)
        if len(points) < 2:
            continue
        shape = shapes.get(trip.get('shape_id')) or []
        if len(shape) >= 2:
            result[route_id]['shapes'][trip['shape_id']] = shape
        key = tuple(stop_ids)
        if tuple(reversed(key)) < key:
            key = tuple(reversed(key))
            points.reverse()
        previous = result[route_id]['patterns'].get(key)
        if previous is None or len(shape) > len(previous['shape']):
            result[route_id]['patterns'][key] = {
                'tripId': trip_id, 'stationPoints': points, 'shape': shape,
            }

    def subsequence(small, large):
        iterator = iter(large)
        return all(any(value == candidate for candidate in iterator)
                   for value in small)

    for route_id, data in result.items():
        by_sequence = data['patterns']
        data['patterns'] = [
            pattern for sequence, pattern in by_sequence.items()
            if not any(len(other) > len(sequence)
                       and subsequence(sequence, other)
                       for other in by_sequence)
        ]
        data['shapes'] = list(data['shapes'].values())
        if not data['patterns']:
            raise SystemExit(f'{operator} GTFS has no route {route_id} pattern')
        if not data['shapes']:
            raise SystemExit(f'{operator} GTFS has no route {route_id} shape')
    return result


# --------------------------------------------------------------- selection


def corridor_index(shapes, spacing_m=50.0):
    index = geo.ReferenceIndex(cell_deg=0.02)
    for shape in shapes:
        index.add_line(geo.densify(shape, spacing_m))
    return index


def any_vertex_within(lines, index, meters):
    """Admit a surveyed record that touches the corridor anywhere.

    Government linework is already segmented at railway topology changes, so
    one nearby vertex is enough: refusing a record because its far end leaves
    the corridor would drop the connecting piece a junction needs.
    """
    for line in lines:
        for point in line:
            if index.nearest(point, search_cells=1)[0] <= meters:
                return True
    return False


def most_vertices_within(lines, index, meters, share):
    """Admit only a record that lies along the corridor for most of itself.

    The Bathurst corridor is where this matters: NRWN carries four parallel
    main tracks through it, and admitting each one that grazes the passenger
    alignment is what made the ORWN routing double back on itself.  Requiring
    the record to agree for most of its length picks the track the train is
    on instead of every track beside it.
    """
    total = sum(len(line) for line in lines)
    if not total:
        return False
    near = sum(1 for line in lines for point in line
               if index.nearest(point, search_cells=1)[0] <= meters)
    return near >= max(1, int(share * total))


def mtq_selects(properties, route_id):
    """Whether one Québec record is published as part of this exo line."""
    if properties.get('etat') != MTQ_OPERATIONAL:
        return False
    if properties.get('classvoie') not in MTQ_TRACK_CLASSES:
        return False
    named = {str(properties.get(field) or '').strip()
             for field in ('nomsubdiv1', 'nomsubdiv2')} - {'', 'Aucun'}
    if named:
        # A named subdivision is the isolation.  Two lines share `Westmount`
        # and two share `Adirondack`, and both of those really are shared
        # rails; what must never happen is Vaudreuil track reaching Candiac,
        # so a record MTQ has named is admitted only to the lines whose
        # published subdivision list contains that name.
        return bool(MTQ_ROUTE_SUBDIVISIONS[route_id].intersection(named))
    # Mascouche is the line the subdivision list cannot carry: exo owns its
    # northern half outright, MTQ leaves `nomsubdiv1` empty there and names
    # EXO as operator and user instead.  Only an unnamed record may be
    # admitted this way, and only to a line whose list says so.
    if MTQ_UNNAMED_EXO_ROUTES and route_id not in MTQ_UNNAMED_EXO_ROUTES:
        return False
    return MTQ_EXO_CODE in {
        str(properties.get(field) or '').strip()
        for field in ('siguti1vo', 'siguti2vo', 'siglexploi')
    }


def nrwn_selects(properties, key):
    """Whether one Ontario record is published as part of this corridor."""
    if properties.get('ADMINAREA') != NRWN_ADMIN_AREA:
        return False
    if properties.get('STATUS') != NRWN_OPERATIONAL:
        return False
    if properties.get('TRACKCLASS') not in NRWN_TRACK_CLASSES:
        return False
    subdivisions = NRWN_ROUTE_SUBDIVISIONS[key]
    return bool(subdivisions.intersection({
        str(properties.get(field) or '').strip()
        for field in ('SUBDI1NAME', 'SUBDI2NAME')
    }))


# ----------------------------------------------------------------- routing


def routing_network(records):
    """The selected records as a routable graph keyed on their own endpoints."""
    edges = []
    for properties, lines in records:
        for line in lines:
            if len(line) < 2:
                continue
            props = dict(properties)
            props['FRFRANODE'] = tuple(round(value, 6) for value in line[0])
            props['TOFRANODE'] = tuple(round(value, 6) for value in line[-1])
            edges.append({
                'type': 'Feature', 'properties': props,
                'geometry': {'type': 'LineString', 'coordinates': line},
            })
    return na_narn.Network(edges)


def turn_degrees(a, b, c):
    plane = geo.Plane(b[0], b[1])
    ax, ay = plane.to_xy(a)
    bx, by = plane.to_xy(b)
    cx, cy = plane.to_xy(c)
    ux, uy = bx - ax, by - ay
    vx, vy = cx - bx, cy - by
    denominator = math.hypot(ux, uy) * math.hypot(vx, vy)
    if denominator == 0:
        return 0.0
    cosine = max(-1.0, min(1.0, (ux * vx + uy * vy) / denominator))
    return math.degrees(math.acos(cosine))


def remove_short_return_spikes(points, tolerance_m=5.0):
    """Remove only A-B-A survey branches whose outer points coincide.

    A government track layer is a graph of every rail, crossovers and yard
    leads included, and a shortest path across it can enter one and come
    straight back out — which draws as a train reversing through 177 degrees
    and then reversing again.  Requiring the two outer official coordinates to
    agree within a few metres makes this a topology cleanup rather than a
    simplification: nothing is moved, only a detour that returns to where it
    started is dropped.
    """
    cleaned = []
    for point in points:
        cleaned.append(point)
        while (len(cleaned) >= 3
               and geo.haversine(cleaned[-3], cleaned[-1]) <= tolerance_m):
            del cleaned[-2:]
        changed = True
        while changed and len(cleaned) >= 3:
            changed = False
            for index in range(1, len(cleaned) - 1):
                a, b, c = cleaned[index - 1:index + 2]
                if (turn_degrees(a, b, c) >= 170.0
                        and geo.haversine(a, c) <= 50.0):
                    del cleaned[index]
                    changed = True
                    break
    return cleaned


#: Station anchors are taken from the surveyed path rather than from the
#: operator's own coordinate, so that every coordinate in the extract is one
#: the government layer drew.  `cut_at_stations` would substitute the
#: operator's coordinate past this distance; no accepted pattern comes near
#: it, and the per-family limit below refuses the ones that would.
ANCHOR_LIMIT_M = 600.0


def routed_features(records, patterns, key, dataset, max_snap_m,
                    width_m=300.0, max_station_offset_m=100.0,
                    require_every_pattern=True, primary_pattern_only=False):
    """One end-to-end surveyed path per pattern, cut at its stations.

    The obvious way to do this is to ask the network for each station pair in
    turn.  It is also wrong on a double-track railway, and spectacularly so on
    a double-track street railway: the two rails of Carlton Street are six
    metres apart, so consecutive platforms snap to opposite ones and the
    shortest path between them runs to the next crossover and back — 2.5 km
    between two stops 130 m apart, nineteen times the distance, on ten of the
    line's sixty-three intervals.

    Asking once for the whole line and cutting the answer at the platforms
    fixes that by construction: one path cannot be on two rails at once.  The
    corridor is the operator's own published shape, which is what keeps the
    end-to-end answer on the route the trains take rather than on whatever
    parallel track is shortest, and the cut is `na_build.cut_at_stations`, the
    same monotone walk the package uses everywhere else.  Stations are first
    projected onto that shape so a platform marker beside the corridor names a
    position along it rather than a rail beside it.

    A pattern whose stations do not lie on the path it produced is refused,
    not repaired: that is the Bathurst Station short-turn loop, which the City
    track layer does not carry, and drawing its two patterns down the through
    track instead would be an invention.
    """
    network = routing_network(records)
    output = []
    seen = set()
    # A street railway's extract must contain ONE thread, not the union of
    # every pattern's thread.  The builder routes this file again itself, over
    # the same double-track graph, and a union puts the two rails of Carlton
    # Street back in front of it — which is the ambiguity this normalizer
    # exists to resolve, handed downstream instead of solved.  The line's
    # fullest pattern is the one thread; its short-turns are subsets of it.
    if primary_pattern_only and patterns:
        patterns = [max(patterns, key=lambda p: len(p['stationPoints']))]
    for pattern_index, pattern in enumerate(patterns):
        stations = pattern['stationPoints']
        shape = pattern['shape']
        if len(shape) < 2:
            continue
        selectors = [geo.project_to_line(point, shape)[3]
                     for point in stations]
        routed, diagnostic = na_narn.route_stations(
            network, [shape, selectors], [selectors[0], selectors[-1]],
            width_m=width_m, max_snap_m=max_snap_m, pad_cells=1)
        path = routed[0] if routed else None
        if path is not None and len(path) >= 2:
            path = remove_short_return_spikes(path)
        if path is None or len(path) < 2:
            if require_every_pattern:
                raise SystemExit(
                    f'{key}: {dataset} cannot route GTFS pattern '
                    f'{pattern["tripId"]}: {diagnostic}')
            continue
        offset = max(geo.project_to_line(point, path)[0]
                     for point in selectors)
        if offset > max_station_offset_m:
            if require_every_pattern:
                raise SystemExit(
                    f'{key}: {dataset} path for pattern '
                    f'{pattern["tripId"]} misses a station by '
                    f'{offset:.0f} m')
            continue
        intervals, _, _ = build.cut_at_stations(
            path, selectors, ANCHOR_LIMIT_M)
        for interval_index, interval in enumerate(intervals):
            if not interval or len(interval) < 2:
                continue
            signature = min(
                tuple((round(point[0], 7), round(point[1], 7))
                      for point in interval),
                tuple((round(point[0], 7), round(point[1], 7))
                      for point in reversed(interval)))
            if signature in seen:
                continue
            seen.add(signature)
            output.append({
                'type': 'Feature',
                'properties': {
                    'routeKey': key,
                    'sourceDataset': dataset,
                    'gtfsSelectionTrip': pattern['tripId'],
                    'patternIndex': pattern_index,
                    'intervalIndex': interval_index,
                    'stationOffsetMeters': round(offset, 1),
                },
                'geometry': {'type': 'LineString', 'coordinates': interval},
            })
    if not output:
        raise SystemExit(f'{key}: {dataset} routed no GTFS pattern')
    return output


def exo_groups(mtq, exo_gtfs):
    groups = {}
    for route_id, data in sorted(exo_gtfs.items()):
        index = corridor_index(data['shapes'])
        selected = [(properties, lines) for properties, lines in mtq
                    if mtq_selects(properties, route_id)
                    and any_vertex_within(lines, index, MTQ_CORRIDOR_M)]
        key = f'mtq-exo-{route_id}'
        if not selected:
            raise SystemExit(f'{key}: no Québec railway record selected')
        groups[key] = routed_features(
            selected, data['patterns'], key, 'Réseau ferroviaire du Québec',
            max_snap_m=600.0, max_station_offset_m=MTQ_STATION_OFFSET_M)
    return groups


def ontario_groups(nrwn, gtfs_by_key):
    groups = {}
    for key, data in sorted(gtfs_by_key.items()):
        index = corridor_index(data['shapes'])
        selected = [(properties, lines) for properties, lines in nrwn
                    if nrwn_selects(properties, key)
                    and most_vertices_within(lines, index, NRWN_CORRIDOR_M,
                                             NRWN_CORRIDOR_SHARE)]
        if not selected:
            raise SystemExit(f'{key}: no NRWN railway record selected')
        groups[key] = routed_features(
            selected, data['patterns'], key, 'National Railway Network Track',
            max_snap_m=600.0, max_station_offset_m=100.0)
    return groups


def toronto_groups(track, route_view, ttc_gtfs):
    lines_by_route = {}
    for properties, lines in route_view:
        route_id = str(properties.get('ROUTE_ID') or '').strip()
        if route_id in TTC_ROUTE_KEYS:
            lines_by_route[route_id] = lines
    missing = set(TTC_ROUTE_KEYS) - set(lines_by_route)
    if missing:
        raise SystemExit(
            f'City streetcar route layer has no ROUTE_ID {sorted(missing)}')
    groups = {}
    for route_id, key in sorted(TTC_ROUTE_KEYS.items()):
        # Both corridors, because each covers what the other does not.  The
        # City's own `ROUTE_ID` line is the published statement that this
        # route exists and where it normally runs; the operator's shape is the
        # only source for the diversion the 506 is running today, which takes
        # ten consecutive stops up to 618 m off the City's line and onto City
        # track the City's line does not describe.
        index = corridor_index(
            lines_by_route[route_id] + ttc_gtfs[route_id]['shapes'],
            spacing_m=10.0)
        selected = [(properties, lines) for properties, lines in track
                    if most_vertices_within(lines, index, TTC_CORRIDOR_M,
                                            TTC_CORRIDOR_SHARE)]
        if not selected:
            raise SystemExit(f'{key}: no City track record selected')
        # Short-turn patterns that reverse on the Bathurst Station loop are
        # refused rather than drawn: the City track layer does not carry that
        # loop, so their terminus lands 400 m off any path across it.  They
        # are patterns of a line whose through service routes completely, and
        # refusing the whole railway over them would restore exactly the
        # blocker this source was found to clear.
        groups[key] = routed_features(
            selected, ttc_gtfs[route_id]['patterns'], key,
            'TTC Streetcar Track', max_snap_m=300.0, width_m=60.0,
            max_station_offset_m=100.0, require_every_pattern=False,
            primary_pattern_only=True)
    return groups


# ---------------------------------------------------------------- manifest


def load_manifest(output_dir):
    path = os.path.join(output_dir, 'manifest.json')
    try:
        with open(path, encoding='utf-8') as source:
            manifest = json.load(source)
    except FileNotFoundError:
        manifest = {'schemaVersion': 1, 'sources': {}, 'files': {}}
    if manifest.get('schemaVersion') != 1:
        raise SystemExit('official-network manifest schema is unsupported')
    manifest.setdefault('sources', {})
    manifest.setdefault('files', {})
    return manifest


KEY_PREFIXES = ('mtq-exo-', 'nrwn-on-', 'ttc-streetcar-')


def normalize(output_dir, inputs, generated_at=None):
    raw = {name: open(path, 'rb').read() for name, path in inputs.items()}
    shas = {name: digest(data) for name, data in raw.items()}

    exo_gtfs = gtfs_patterns(inputs['exo_gtfs'], {'1', '3', '4', '5', '6'},
                             'exo')
    up_gtfs = gtfs_patterns(inputs['up_gtfs'], {'UP'}, 'UP Express')
    go_gtfs = gtfs_patterns(inputs['go_gtfs'],
                            {'06260926-GT', '09261126-GT'}, 'GO Transit')
    ttc_gtfs = gtfs_patterns(inputs['ttc_gtfs'], set(TTC_ROUTE_KEYS), 'TTC')

    # GO renumbers its route ids at every seasonal timetable, and both halves
    # of the pair are the same Kitchener railway.  Merge them into one key so
    # the corridor is selected once, from every shape either id published.
    kitchener = {'patterns': [], 'shapes': []}
    for data in go_gtfs.values():
        kitchener['patterns'] += data['patterns']
        kitchener['shapes'] += data['shapes']
    if not kitchener['patterns']:
        raise SystemExit('GO Transit GTFS has no Kitchener pattern')

    groups = {}
    groups.update(exo_groups(read_mtq(raw['quebec']), exo_gtfs))
    groups.update(ontario_groups(read_nrwn(raw['nrwn_on']), {
        'nrwn-on-up-up': up_gtfs['UP'],
        'nrwn-on-go-ki': kitchener,
    }))
    groups.update(toronto_groups(
        read_geojson_lines(raw['ttc_track'], 'City of Toronto TTC track',
                           {'TRACK_ID'}),
        read_geojson_lines(raw['ttc_routes'], 'City of Toronto TTC routes',
                           {'ROUTE_ID', 'ROUTE_COLOR'}),
        ttc_gtfs))

    key_source = {}
    for key in groups:
        if key.startswith('mtq-exo-'):
            key_source[key] = ('quebec-mtq-reseau-ferroviaire', 'quebec')
        elif key.startswith('nrwn-on-'):
            key_source[key] = ('nrcan-nrwn-on', 'nrwn_on')
        else:
            key_source[key] = ('toronto-ttc-track', 'ttc_track')

    os.makedirs(output_dir, exist_ok=True)
    manifest = load_manifest(output_dir)
    manifest['sources']['quebec-mtq-reseau-ferroviaire'] = {
        **SOURCES['quebec-mtq-reseau-ferroviaire'],
        'rawSha256': shas['quebec'],
    }
    manifest['sources']['nrcan-nrwn-on'] = {
        **SOURCES['nrcan-nrwn-on'], 'rawSha256': shas['nrwn_on'],
    }
    manifest['sources']['toronto-ttc-track'] = {
        **SOURCES['toronto-ttc-track'], 'rawSha256': shas['ttc_track'],
    }
    manifest['sources']['toronto-ttc-route-view'] = {
        **SOURCES['toronto-ttc-route-view'], 'rawSha256': shas['ttc_routes'],
    }
    manifest['files'] = {
        key: value for key, value in manifest['files'].items()
        if not key.startswith(KEY_PREFIXES)
    }
    for key, features in sorted(groups.items()):
        source_id, raw_name = key_source[key]
        source = {**SOURCES[source_id], 'rawSha256': shas[raw_name]}
        if source_id == 'toronto-ttc-track':
            # The layer that isolated the route is not the layer that drew it,
            # and both belong in the record of how this file was made.
            source['selectorUrl'] = SOURCES['toronto-ttc-route-view']['url']
            source['selectorRawSha256'] = shas['ttc_routes']
        payload = {
            'type': 'FeatureCollection', 'sourceId': key, 'source': source,
            'features': features,
        }
        encoded = json.dumps(payload, ensure_ascii=False,
                             separators=(',', ':')).encode()
        filename = f'{key}.geojson'
        path = os.path.join(output_dir, filename)
        with open(path + '.tmp', 'wb') as output:
            output.write(encoded)
        os.replace(path + '.tmp', path)
        manifest['files'][key] = {
            'file': filename, 'features': len(features),
            'sha256': digest(encoded),
        }
    manifest['generatedAt'] = (generated_at
                               or dt.datetime.now(dt.timezone.utc).isoformat())
    path = os.path.join(output_dir, 'manifest.json')
    with open(path + '.tmp', 'w', encoding='utf-8') as output:
        json.dump(manifest, output, ensure_ascii=False, indent=2)
        output.write('\n')
    os.replace(path + '.tmp', path)
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--quebec-input', required=True)
    parser.add_argument('--exo-gtfs', required=True)
    parser.add_argument('--nrwn-on-input', required=True)
    parser.add_argument('--up-gtfs', required=True)
    parser.add_argument('--go-gtfs', required=True)
    parser.add_argument('--ttc-track-input', required=True)
    parser.add_argument('--ttc-route-input', required=True)
    parser.add_argument('--ttc-gtfs', required=True)
    args = parser.parse_args()
    manifest = normalize(args.output_dir, {
        'quebec': args.quebec_input,
        'exo_gtfs': args.exo_gtfs,
        'nrwn_on': args.nrwn_on_input,
        'up_gtfs': args.up_gtfs,
        'go_gtfs': args.go_gtfs,
        'ttc_track': args.ttc_track_input,
        'ttc_routes': args.ttc_route_input,
        'ttc_gtfs': args.ttc_gtfs,
    })
    count = sum(key.startswith(KEY_PREFIXES) for key in manifest['files'])
    print(f'wrote {count} route-isolated eastern-Canada railway networks')


if __name__ == '__main__':
    main()
