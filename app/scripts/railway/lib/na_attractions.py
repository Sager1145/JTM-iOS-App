"""The one place that says which rail rides are attractions, not transport.

A ride inside a paid attraction — a theme park, a zoo, a resort, a
living-history museum — is a fairground ride that happens to run on rails, and
these packages leave it out. There is no field in GTFS or in OpenStreetMap
that says "this is not transport", so the test is on the names, and the names
have to live somewhere.

They live here because they used to live in two places and the two disagreed.
`make-na-feed-registry.py` held `ATTRACTION_OPERATORS` (`theme park`, `aria
resort`, `casino`) and guarded only the GTFS path; `report-na-coverage.py`
held `ATTRACTIONS` (`brookfield`, `henry dorrly`, `memphis zoo`, `dallas zoo`)
under a comment claiming it matched "the same way `make-na-feed-registry.py`
matches them", which it did not; and the OpenStreetMap path in the builder
held nothing at all. Neither list named Fort Edmonton Park, so
`ca-2025.json` shipped `osm-fort-edmonton-park-fort-edmonton-park-st` — a
streetcar that runs inside a paid living-history park in Edmonton and goes
nowhere else. One list, three callers, and the next omission is one entry
rather than three.

## The test is on a LINE, not on an operator

`Edmonton Radial Railway Society` is the concrete reason. It operates two
tramways: the Fort Edmonton Park Streetcar, which runs inside the paid park,
and the High Level Bridge Streetcar, which crosses the North Saskatchewan
River on a public bridge between Whyte Avenue and Jasper Plaza and is a way of
getting across Edmonton. The society is not an attraction; one of its two
railways is. So `is_attraction` is asked about every name a line carries —
its operator AND its own name — and answers for that line alone. The same
shape catches `Edmonton Yukon and Pacific`, whose only line is named "Fort
Edmonton Park Steam Train": the operator says nothing, the line says it all.

## Why the terms are this specific

`park` alone would take the Grand Canyon Railway, every "…Park" station name
and Fort Worth's TEXRail; `edmonton` alone would take the Valley Line and the
Capital Line. A term earns its place by being specific enough that no public
railway on the continent can contain it — which is why the entry below is
`fort edmonton park` and not either half of it.
"""
from __future__ import annotations

#: Substrings that identify a ride inside a paid attraction, matched
#: case-insensitively against any of the names a line or a feed carries.
#:
#: The union of the two lists this module replaced, plus `fort edmonton park`.
#: Several entries are redundant against `zoo` — `brookfield` is Brookfield
#: Zoo, `henry dorrly` is Omaha's Henry Doorly Zoo (spelt as the coverage
#: report spelt it), `memphis zoo` and `dallas zoo` are already `zoo` — and
#: they are kept so that folding the two lists together changed no decision
#: either of them was already making.
ATTRACTION_TERMS = (
    'disney', 'busch gardens', 'six flags', 'cedar point', 'universal',
    'zoo', 'aquarium', 'springs preserve', 'storm king', 'jungle jim',
    'theme park', 'aria resort', 'casino',
    'brookfield', 'henry dorrly', 'memphis zoo', 'dallas zoo',
    # Fort Edmonton Park, whose streetcar and steam train are tagged in
    # OpenStreetMap under three different operators — "Fort Edmonton Park",
    # "Edmonton Radial Railway Society" and "Edmonton Yukon and Pacific" —
    # and are one attraction under all three.
    'fort edmonton park',
)


def matched_term(*text):
    """The attraction term one of these names contains, or ``None``.

    Returns the term rather than a boolean so a caller can say WHY it dropped
    something. Every one of the three callers writes its drops to a report,
    and "attraction" is a much weaker thing to read than "attraction: matched
    'fort edmonton park'".
    """
    folded = ' '.join(str(part or '') for part in text).lower()
    for term in ATTRACTION_TERMS:
        if term in folded:
            return term
    return None


def is_attraction(*text):
    """Whether any of these names is a ride inside a paid attraction.

    Pass every name that describes the thing being judged — for a GTFS feed
    its provider and feed name, for an OpenStreetMap route its operator and
    the relation's own name. A match on any one of them is a match, because
    the operator and the line name are two ways of saying the same fact and
    OpenStreetMap's contributors have used both.
    """
    return matched_term(*text) is not None
