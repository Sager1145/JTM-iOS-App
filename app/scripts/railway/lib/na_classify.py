"""What kind of railway a route is, and the official code space it lands in.

Every consumer downstream of the packages — the statistics buckets, the zoom
at which a line appears, the grooming band — asks the same question in a
different vocabulary: is this an intercity train, a commuter railroad, a
metro, a light rail, a streetcar, a people mover, a funicular, a heritage
line? This module answers it once, from what the operator publishes, and
everything else reads the answer.

The signal is the feed's own ``route_type`` first, because that is the
operator's own word for what it runs, and the line's median station spacing
second, because that is what separates the two cases ``route_type`` does not:
light rail from a streetcar (GTFS spells both ``0``), and a metro from an
airport people mover (both ``1``).

## The code space

The packages carry ``institution_type_code`` and ``railway_class_code`` on
every section, the two fields Japan's 国土数値情報 N02 supplies as ``N02_002``
and ``N02_001`` and that every other country's build fills with the same
meanings. North America uses the space Taiwan's build already defined, because
the two networks decompose the same way:

===================================  ==================  =============
kind                                 institution         class
===================================  ==================  =============
high-speed intercity                 1                   12
intercity / national passenger       2                   11
commuter rail                        3                   11
metro, rapid transit, light rail     3                   11
streetcar                            3                   21
monorail, people mover               3 (4 if private)    22
funicular, cable, incline            3 (4 if private)    31
heritage / tourist railway           4                   31
===================================  ==================  =============
"""
from __future__ import annotations

#: Operators whose rail services are intercity passenger railroads rather than
#: an urban network. Matched on the agency name the feed publishes.
INTERCITY_AGENCIES = (
    'amtrak', 'via rail', 'brightline', 'alaska railroad', 'ontario northland',
    'the alaska railroad', 'texas central',
)

#: Services their own operator sells as high-speed.
HIGH_SPEED_ROUTES = ('acela', 'brightline')

#: Heritage, tourist and excursion railways: scheduled public passenger trains
#: on their own right of way, but not part of anybody's transport network.
HERITAGE_HINTS = (
    'scenic', 'heritage', 'museum', 'excursion', 'tourist', 'historic',
    'steam', 'trolley museum', 'railway museum', 'cog railway', 'rocky mountaineer',
)

#: People movers and airport shuttles. They are public passenger railways and
#: belong in the packages; they are not metros and must not be ranked as one.
PEOPLE_MOVER_HINTS = (
    'airtrain', 'air train', 'people mover', 'skylink', 'plane train', 'sky train',
    'automated', 'shuttle train', 'tram (', 'airport tram', 'metromover',
)

STREETCAR_MAX_SPACING_M = 650.0
PEOPLE_MOVER_MAX_LENGTH_M = 12_000.0
PEOPLE_MOVER_MAX_SPACING_M = 1_200.0


def classify(kind, agency_name, route_name, median_spacing_m, length_m,
             private_operator=False, heritage=False):
    """The kind of railway one built line is."""
    agency = (agency_name or '').lower()
    route = (route_name or '').lower()
    text = f'{agency} {route}'

    if heritage or any(h in text for h in HERITAGE_HINTS):
        return 'heritage'
    if kind == 'funicular' or kind == 'cable':
        return 'funicular'
    if kind == 'monorail':
        return ('peoplemover'
                if length_m and length_m <= PEOPLE_MOVER_MAX_LENGTH_M
                else 'monorail')
    if kind == 'rail':
        if any(a in agency for a in INTERCITY_AGENCIES):
            if any(h in route for h in HIGH_SPEED_ROUTES) or 'brightline' in agency:
                return 'highspeed'
            return 'intercity'
        return 'commuter'
    if kind == 'metro':
        if any(h in text for h in PEOPLE_MOVER_HINTS) and (
                length_m <= PEOPLE_MOVER_MAX_LENGTH_M
                and median_spacing_m <= PEOPLE_MOVER_MAX_SPACING_M):
            return 'peoplemover'
        return 'metro'
    if kind == 'tram':
        if median_spacing_m and median_spacing_m <= STREETCAR_MAX_SPACING_M:
            return 'streetcar'
        return 'lightrail'
    return 'commuter'


#: kind -> (rank, institution_type_code, railway_class_code)
CODES = {
    'highspeed':   (0, '1', '12'),
    'intercity':   (1, '2', '11'),
    'commuter':    (2, '3', '11'),
    'metro':       (2, '3', '11'),
    'lightrail':   (3, '3', '11'),
    'streetcar':   (4, '3', '21'),
    'monorail':    (3, '3', '22'),
    'peoplemover': (4, '3', '22'),
    'funicular':   (4, '3', '31'),
    'heritage':    (4, '4', '31'),
}


def codes_for(kind, private_operator=False):
    rank, institution, klass = CODES.get(kind, CODES['commuter'])
    if private_operator and institution == '3' and klass in ('22', '31'):
        institution = '4'
    return rank, institution, klass
