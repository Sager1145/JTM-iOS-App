"""Integrity and authority checks for normalized official rail geometry.

The manifest is not treated as proof by itself.  A route extract is trusted
only when its publisher and endpoint match this reviewed allow-list, its
embedded source record matches the manifest, and its bytes match the recorded
SHA-256.  This makes the direct-chord exception below a property of audited
government/operator survey data, not of a filename or geometrySource string.
"""
from __future__ import annotations

import hashlib
import json
import os
import re


SOURCES = {
    'mta': {
        'publisher': 'Metropolitan Transportation Authority',
        'url': ('https://data.ny.gov/resource/s692-irgq.geojson?'
                '$select=service_name,service,geometry&$limit=100'),
    },
    'cta': {
        'publisher': 'Chicago Transit Authority / City of Chicago',
        'url': ('https://data.cityofchicago.org/api/v3/views/'
                'xbyr-jnvx/query.geojson?accessType=DOWNLOAD'),
    },
    'norta': {
        'publisher': 'City of New Orleans GIS Department',
        'url': ('https://services.arcgis.com/VhMjCzR3cIjEkh7L/ArcGIS/rest/'
                'services/2022_RTA_Public_Transit_Routes/FeatureServer/0/'
                'query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'ttc': {
        'publisher': 'City of Toronto / Toronto Transit Commission',
        'url': ('https://ckan0.cf.opendata.inter.prod-toronto.ca/dataset/'
                'c01c6d71-de1f-493d-91ba-364ce64884ac/resource/'
                '7d68bb52-3285-45d7-a248-7748cb47f6ce/download/'
                'ttc-subway-shapefile-wgs84.zip'),
    },
    'ottawa-trillium': {
        'publisher': 'City of Ottawa / Rail Implementation Office',
        'url': ('https://maps.ottawa.ca/arcgis/rest/services/'
                'Rail_Implementation_Office/MapServer/33/query?'
                "where=REFNAME%3D%27Trillium%27%20AND%20LAYER%20LIKE%20"
                "%27T-ALIGN%25%27&outFields=OBJECTID%2CLAYER%2CREFNAME&"
                'returnGeometry=true&outSR=4326&f=geojson'),
    },
    'vta': {
        'publisher': 'Santa Clara Valley Transportation Authority',
        'url': ('https://gis.vta.org/gis/rest/services/LRT_BART/MapServer/6/'
                'query?where=1%3D1&outFields=*&returnGeometry=true&'
                'outSR=4326&f=geojson'),
    },
    'massgis-mbta-rapid': {
        'publisher': ('MassGIS (Bureau of Geographic Information), '
                      'Commonwealth of Massachusetts EOTSS'),
        'url': ('https://arcgisserver.digital.mass.gov/arcgisserver/rest/'
                'services/AGOL/MBTA_Rapid_Transit/FeatureServer/4/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'massgis-mbta-commuter': {
        'publisher': ('MassGIS (Bureau of Geographic Information), '
                      'Commonwealth of Massachusetts EOTSS'),
        'url': ('https://services9.arcgis.com/zkB26wYVlNoTUmsC/ArcGIS/'
                'rest/services/MassGIS_trains/FeatureServer/2/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'septa-high-speed': {
        'publisher': 'SEPTA Planning Division',
        'url': ('https://opendata.arcgis.com/api/v3/datasets/'
                '1e7754ca5f7d47e480a628e282466428_0/downloads/data?'
                'format=geojson&spatialRefId=4326'),
    },
    'septa-trolley': {
        'publisher': 'SEPTA Planning Division',
        'url': ('https://opendata.arcgis.com/api/v3/datasets/'
                '33944ef79d2249aca38561a68dc3e06f_0/downloads/data?'
                'format=geojson&spatialRefId=4326'),
    },
    'septa-regional-rail': {
        'publisher': 'SEPTA Planning Division',
        'url': ('https://opendata.arcgis.com/api/v3/datasets/'
                '7ebff6bc356d4fa28d4a7e4147d03b32_0/downloads/data?'
                'format=geojson&spatialRefId=4326'),
    },
    'calgary-lrt': {
        'publisher': 'The City of Calgary / Calgary Transit',
        'url': ('https://data.calgary.ca/resource/avbp-2r3h.geojson?'
                '$limit=50000'),
    },
    'edmonton-lrt': {
        'publisher': 'The City of Edmonton / Edmonton Transit Service',
        'url': ('https://data.edmonton.ca/resource/8r95-rjy4.geojson?'
                '$limit=50000'),
    },
    'translink-system-map': {
        'publisher': 'TransLink',
        'url': ('https://services7.arcgis.com/WpS8F3vcmrEQUG8m/arcgis/rest/'
                'services/Translink_System_App_2/FeatureServer/5/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'atlanta-official-heavy-rail': {
        'publisher': 'City of Atlanta / MARTA Special Projects and Analysis',
        'url': ('https://services5.arcgis.com/5RxyIIJ9boPdptdo/arcgis/rest/'
                'services/Official_MARTA_Heavy_Rail_Lines_2021/'
                'FeatureServer/0/query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'atlanta-official-streetcar': {
        'publisher': 'City of Atlanta / Atlanta Streetcar',
        'url': ('https://services5.arcgis.com/5RxyIIJ9boPdptdo/arcgis/rest/'
                'services/Official_Streetcar_Rail_Line_2021/FeatureServer/0/'
                'query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'miami-dade-metrorail': {
        'publisher': 'Miami-Dade County / Miami-Dade Transit',
        'url': ('https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/'
                'services/MetroRail_gdb/FeatureServer/0/query?where=1%3D1&'
                'outFields=*&outSR=4326&returnGeometry=true&f=geojson'),
    },
    'miami-dade-metromover': {
        'publisher': 'Miami-Dade County / Miami-Dade Transit',
        'url': ('https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/'
                'services/MetroMover_gdb/FeatureServer/0/query?where=1%3D1&'
                'outFields=*&outSR=4326&returnGeometry=true&f=geojson'),
    },
    'maryland-mta-light-rail': {
        'publisher': 'MD iMAP / Maryland Transit Administration',
        'url': ('https://mdgeodata.md.gov/imap/rest/services/Transportation/'
                'MD_Transit/FeatureServer/3/query?where=1%3D1&outFields=*&'
                'outSR=4326&returnGeometry=true&f=geojson'),
    },
    'maryland-mta-metro': {
        'publisher': 'MD iMAP / Maryland Transit Administration',
        'url': ('https://mdgeodata.md.gov/imap/rest/services/Transportation/'
                'MD_Transit/FeatureServer/5/query?where=1%3D1&outFields=*&'
                'outSR=4326&returnGeometry=true&f=geojson'),
    },
    'modot-kc-streetcar': {
        'publisher': 'Missouri Department of Transportation',
        'url': ('https://services1.arcgis.com/VVapzOPgBae5joyC/ArcGIS/rest/'
                'services/MoDOT_LRTP_and_SFRP_Layers_WFL1/FeatureServer/9/'
                'query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'modot-stl-metrolink': {
        'publisher': 'Missouri Department of Transportation',
        'url': ('https://services1.arcgis.com/VVapzOPgBae5joyC/ArcGIS/rest/'
                'services/MoDOT_LRTP_and_SFRP_Layers_WFL1/FeatureServer/10/'
                'query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'sunmetro-streetcar': {
        'publisher': 'City of El Paso / Sun Metro',
        'url': ('https://gis.elpasotexas.gov/arcgis/rest/services/SunMetro/'
                'StreetcarRoute/FeatureServer/0/query?where=1%3D1&'
                'outFields=*&outSR=4326&returnGeometry=true&f=geojson'),
    },
    'nctcog-existing-rail-lines': {
        'publisher': ('North Central Texas Council of Governments (NCTCOG), '
                      'Transportation Department'),
        'url': ('https://geospatial.nctcog.org/map/rest/services/'
                'Transportation/DFWMaps_Transit/MapServer/2/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'chicago-metra-kml': {
        'publisher': 'City of Chicago',
        'url': ('https://data.cityofchicago.org/download/'
                'e7du-96jw/application/xml'),
    },
    'metc-transitways': {
        'publisher': 'Metropolitan Council',
        'url': ('https://resources.gisdata.mn.gov/pub/gdrs/data/pub/'
                'us_mn_state_metc/trans_transitways_generalized/'
                'shp_trans_transitways_generalized.zip'),
    },
    'la-metro': {
        'publisher': 'Los Angeles County / LA Metro',
        'url': ('https://services.arcgis.com/RmCCgQtiZLDCtblq/ArcGIS/rest/'
                'services/MTA_Metro_Lines/FeatureServer/0/query?where=1%3D1&'
                'outFields=*&returnGeometry=true&outSR=4326&f=geojson'),
    },
    'sfmta': {
        'publisher': ('DataSF / San Francisco Municipal '
                      'Transportation Agency'),
        'url': ('https://data.sfgov.org/api/v3/views/9exe-acju/'
                'query.geojson?accessType=DOWNLOAD'),
    },
    'amtrak-ntad': {
        'publisher': ('Federal Railroad Administration / '
                      'Bureau of Transportation Statistics'),
        'url': ('https://services.arcgis.com/xOi1kZaI0eWDREZv/arcgis/rest/'
                'services/NTAD_Amtrak_Routes/FeatureServer/0/query?'
                'where=1%3D1&outFields=*&returnGeometry=true&'
                'outSR=4326&f=geojson'),
    },
    'mta-rail-branches': {
        'publisher': 'Metropolitan Transportation Authority',
        'url': ('https://data.ny.gov/resource/2vcb-zrh4.geojson?'
                '$limit=50000'),
    },
    'metrolink-scrra': {
        'publisher': ('Southern California Regional Rail Authority / '
                      'Southern California Association of Governments'),
        'url': ('https://maps.scag.ca.gov/scaggis/rest/services/OpenData/'
                'Metrolinklinescag/MapServer/0/query?where=1%3D1&'
                'outFields=*&returnGeometry=true&outSR=4326&f=geojson'),
    },
    'njt-rail': {
        'publisher': 'NJ Transit GIS Department',
        'url': ('https://services6.arcgis.com/M0t0HPE53pFK525U/arcgis/rest/'
                'services/NJTRANSIT_RAIL_LINES_1/FeatureServer/0/query?'
                'where=1%3D1&outFields=*&returnGeometry=true&'
                'outSR=4326&f=geojson'),
    },
    'njt-light': {
        'publisher': 'NJ Transit GIS Department',
        'url': ('https://services6.arcgis.com/M0t0HPE53pFK525U/arcgis/rest/'
                'services/NJTransit_Light_Rail/FeatureServer/0/query?'
                'where=1%3D1&outFields=*&returnGeometry=true&'
                'outSR=4326&f=geojson'),
    },
    'njt-path': {
        'publisher': 'NJ Transit GIS Department',
        'url': ('https://services6.arcgis.com/M0t0HPE53pFK525U/arcgis/rest/'
                'services/PATH/FeatureServer/1/query?where=1%3D1&'
                'outFields=*&returnGeometry=true&outSR=4326&f=geojson'),
    },
    'utah-railroads': {
        'publisher': 'Utah Geospatial Resource Center (UGRC)',
        'url': ('https://services1.arcgis.com/99lidPhWCzftIe9K/ArcGIS/rest/'
                'services/UtahRailroads/FeatureServer/0/query?where='
                'OPERATOR%3D%27UT%20Transit%20Auth%27&outFields=*&'
                'returnGeometry=true&outSR=4326&f=geojson'),
    },
    'houston-metro': {
        'publisher': ('Metropolitan Transit Authority of Harris County '
                      '(METRO)'),
        'url': ('https://services5.arcgis.com/p8QKnlioaN3sruqA/arcgis/rest/'
                'services/METRO_transit_layers/FeatureServer/4/query?'
                'where=1%3D1&outFields=*&returnGeometry=true&'
                'outSR=4326&f=geojson'),
    },
    'ontario-orwn': {
        'publisher': ('Ontario Ministry of Natural Resources - '
                      'Geospatial Ontario'),
        'url': ('https://ws.gisetl.lrc.gov.on.ca/fmedatadownload/Packages/'
                'ORWNTRK.zip'),
    },
    'virginia-drpt-vre': {
        'publisher': ('Virginia Department of Rail and Public '
                      'Transportation'),
        'url': ('https://services9.arcgis.com/9oDT7ErWemWCzvY7/arcgis/rest/'
                'services/VRE_Lines/FeatureServer/7/query?where=1%3D1&'
                'outFields=*&returnGeometry=true&outSR=4326&f=geojson'),
    },
    'caltrans-crn': {
        'publisher': 'California Department of Transportation (Caltrans)',
        'url': ('https://hub.arcgis.com/api/v3/datasets/'
                '2ac93358aca84aa7b547b29a42d5ff52_0/downloads/data?'
                'format=geojson&spatialRefId=4326&where=1%3D1'),
    },
    'cats-blue-line': {
        'publisher': 'Charlotte Area Transit System / City of Charlotte',
        'url': ('https://services.arcgis.com/9Nl857LBlQVyzq54/arcgis/rest/'
                'services/LYNX_Blue_Line_Route/FeatureServer/0/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'dcgis-streetcar': {
        'publisher': ('District Department of Transportation / '
                      'District of Columbia GIS'),
        'url': ('https://maps2.dcgis.dc.gov/dcgis/rest/services/DCGIS_DATA/'
                'Transportation_Rail_Bus_WebMercator/MapServer/113/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
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
    'quebec-mtq-reseau-ferroviaire': {
        'publisher': ('Ministère des Transports et de la Mobilité durable '
                      'du Québec'),
        'url': ('https://ws.mapserver.transports.gouv.qc.ca/swtq?'
                'service=wfs&version=2.0.0&request=getfeature&'
                'typename=ms:reseau_chfer_qc&outfile=ReseauFerroviaire&'
                'srsname=EPSG:4326&outputformat=geojson'),
    },
    'nrcan-nrwn-on': {
        'publisher': ('Natural Resources Canada - GeoBase National Railway '
                      'Network'),
        'url': ('https://ftp.maps.canada.ca/pub/nrcan_rncan/vector/'
                'geobase_nrwn_rfn/on/nrwn_rfn_on_shp_en.zip'),
    },
    'toronto-ttc-track': {
        'publisher': 'City of Toronto - Geospatial Competency Centre',
        'url': ('https://services3.arcgis.com/b9WvedVPoizGfvfD/arcgis/rest/'
                'services/COTGEO_TTC_TRACK/FeatureServer/0/query?'
                'where=1%3D1&outFields=*&outSR=4326&returnGeometry=true&'
                'f=geojson&resultRecordCount=10000'),
    },
    'toronto-ttc-route-view': {
        'publisher': 'City of Toronto - Geospatial Competency Centre',
        'url': ('https://services3.arcgis.com/b9WvedVPoizGfvfD/arcgis/rest/'
                'services/COT_Geospatial_TTC_Streetcar_Route_view/'
                'FeatureServer/0/query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson&resultRecordCount=2000'),
    },
    #: Validation reference only, never a build input: the City's topographic
    #: mapping of subway track (`SUBTYPE_CODE` 2005) covers the open-cut and
    #: surface sections a surveyor can see and nothing in a tunnel. It is what
    #: `validate-ttc-subway-osm.py` measures the Line 1 / Line 2 OSM relations
    #: and the City's own route layer against, and the registry's
    #: `osmRelationEvidenceByRouteId` for the TTC quotes its result.
    'toronto-topo-railway-subway': {
        'publisher': 'City of Toronto - Geospatial Competency Centre',
        'url': ('https://services3.arcgis.com/b9WvedVPoizGfvfD/arcgis/rest/'
                'services/COTGEO_TOPO_RAILWAY/FeatureServer/0/query?'
                'where=SUBTYPE_CODE%3D2005&outFields=*&outSR=4326&f=geojson'),
    },
    'detroit-people-mover-route': {
        'publisher': 'City of Detroit, Open Data Portal',
        'url': ('https://services2.arcgis.com/qvkbeam7Wirps6zC/arcgis/rest/'
                'services/Detroit_People_Mover_Route/FeatureServer/0/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'detroit-qline-route': {
        'publisher': 'City of Detroit, Open Data Portal',
        'url': ('https://services2.arcgis.com/qvkbeam7Wirps6zC/arcgis/rest/'
                'services/QLine_Route/FeatureServer/0/query?where=1%3D1&'
                'outFields=*&outSR=4326&returnGeometry=true&f=geojson'),
    },
    'cagis-cincinnati-streetcar': {
        'publisher': ('CAGIS - Cincinnati Area Geographic Information System '
                      '(City of Cincinnati / Hamilton County)'),
        'url': ('https://services.arcgis.com/JyZag7oO4NteHGiq/arcgis/rest/'
                'services/Open_Data_Feature_Collection/FeatureServer/13/'
                'query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'milwaukee-dpw-streetcar': {
        'publisher': 'City of Milwaukee, Department of Public Works',
        'url': ('https://milwaukeemaps.milwaukee.gov/arcgis/rest/services/'
                'DPW/DPW_streetcar/MapServer/1/query?where=1%3D1&'
                'outFields=*&outSR=4326&returnGeometry=true&f=geojson'),
    },
    'cats-gold-line': {
        'publisher': 'Charlotte Area Transit System / City of Charlotte',
        'url': ('https://services.arcgis.com/9Nl857LBlQVyzq54/arcgis/rest/'
                'services/LYNX_Gold_Line_Route/FeatureServer/0/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'rta-metra-rail-lines': {
        'publisher': ('Regional Transportation Authority of Northeastern '
                      'Illinois, Mapping and GIS Portal'),
        'url': ('https://services5.arcgis.com/NIHJ1cAxHq972sDH/ArcGIS/rest/'
                'services/Transit_Services_FS/FeatureServer/5/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'houston-metrorail-lines': {
        'publisher': ('Metropolitan Transit Authority of Harris County '
                      '(METRO)'),
        'url': ('https://services5.arcgis.com/p8QKnlioaN3sruqA/arcgis/rest/'
                'services/METRORail_LRT_Lines___Stations_WFL1/FeatureServer/'
                '5/query?where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'fdot-brightline': {
        'publisher': ('Florida Department of Transportation, Freight and '
                      'Multimodal Operations Office'),
        'url': ('https://services1.arcgis.com/O1JpcwDW8sjYuddV/ArcGIS/rest/'
                'services/Rail_System_Layers_2025/FeatureServer/9/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'fdot-sunrail': {
        'publisher': ('Florida Department of Transportation, Freight and '
                      'Multimodal Operations Office'),
        'url': ('https://services1.arcgis.com/O1JpcwDW8sjYuddV/ArcGIS/rest/'
                'services/Rail_System_Layers_2025/FeatureServer/2/query?'
                'where=1%3D1&outFields=*&outSR=4326&'
                'returnGeometry=true&f=geojson'),
    },
    'oregonmetro-rlis-rail-transit': {
        'publisher': 'Oregon Metro Data Resource Center (RLIS)',
        'url': ('https://services2.arcgis.com/McQ0OlIABe29rJJy/arcgis/rest/'
                'services/Light_rail/FeatureServer/0/query?where=1%3D1&'
                'outFields=*&returnGeometry=true&outSR=4326&f=geojson'),
        'licenseUrl': ('https://rlisdiscovery.oregonmetro.gov/pages/'
                       'open-database-license'),
    },
    # BART's own GTFS shape for route_ids 1/2 (Yellow-S/N) draws the SFO
    # Airport<->Millbrae wye as a straight chord; no government GIS layer
    # for it is known, but OpenStreetMap relation 2827684 ("BART Yellow
    # Line") digitises the physical track end to end -- including the wye
    # -- as a chain of `railway=subway` ways (tagged "Y-Line"/"W-Line"
    # through the wye itself). This is the first OpenStreetMap-derived
    # entry in this allow-list; it is admitted the same way every other
    # entry is, by publisher+endpoint+hash review, not by relaxing the
    # review for OSM generally.
    'bart-osm-sfo-millbrae-wye': {
        'publisher': 'OpenStreetMap contributors',
        'url': ('https://overpass-api.de/api/interpreter?data=%5Bout%3A'
                'json%5D%3Brelation(2827684)%3B(._%3B%3E%3B)%3Bout%20geom%3B'),
        'licenseUrl': 'https://www.openstreetmap.org/copyright',
    },
}

KEY_SOURCE_PREFIXES = {
    'mta-subway-': 'mta',
    'cta-': 'cta',
    'norta-': 'norta',
    'ttc-subway-': 'ttc',
    'vta-': 'vta',
    'amtrak-ntad-': 'amtrak-ntad',
    'mnr-': 'mta-rail-branches',
    'lirr-': 'mta-rail-branches',
    'metrolink-scrra-': 'metrolink-scrra',
    'njt-rail-': 'njt-rail',
    'njt-light-': 'njt-light',
    'path-njt-': 'njt-path',
    'prt-t-': 'prt-fixed-guideway-corridors',
    'prt-incline-': 'prt-fixed-guideway-corridors',
}

KEY_SOURCE_EXACT = {
    'bart-sfo-millbrae-wye': 'bart-osm-sfo-millbrae-wye',
    **{f'la-metro-{route}': 'la-metro'
       for route in ('801', '802', '803', '804', '805', '807')},
    **{f'sfmta-{route}-{direction}': 'sfmta'
       for route in ('ca', 'f', 'j', 'k', 'l', 'm', 'n', 'ph', 'pm', 't')
       for direction in ('i', 'o')},
    **{f'uta-{route}': 'utah-railroads'
       for route in ('701', '703', '704', '720', '750')},
    **{f'houston-metro-{route}': 'houston-metro'
       for route in ('700', '800', '900')},
    **{f'orwn-go-{route}': 'ontario-orwn'
       for route in ('br', 'ki', 'le', 'lw', 'mi', 'rh', 'st')},
    'orwn-up-up': 'ontario-orwn',
    **{f'orwn-via-{route}': 'ontario-orwn'
       for route in ('119-93', '119-341', '119-618')},
    'ottawa-trillium-2': 'ottawa-trillium',
    'ottawa-trillium-4': 'ottawa-trillium',
    'vre-fredericksburg': 'virginia-drpt-vre',
    'vre-manassas': 'virginia-drpt-vre',
    'caltrans-caltrain': 'caltrans-crn',
    'caltrans-sd-blue': 'caltrans-crn',
    'caltrans-sd-orange': 'caltrans-crn',
    **{f'mbta-rapid-{suffix}': 'massgis-mbta-rapid'
       for suffix in ('blue', 'orange', 'red', 'mattapan',
                      'green-b', 'green-c', 'green-d', 'green-e')},
    **{f'mbta-commuter-{suffix}': 'massgis-mbta-commuter'
       for suffix in ('capeflyer', 'cr-fairmount', 'cr-newbedford',
                      'cr-fitchburg', 'cr-foxboro', 'cr-worcester',
                      'cr-franklin', 'cr-greenbush', 'cr-haverhill',
                      'cr-kingston', 'cr-lowell', 'cr-needham',
                      'cr-newburyport', 'cr-providence')},
    **{f'septa-{route}': 'septa-high-speed'
       for route in ('b1', 'b3', 'l1', 'm1')},
    **{f'septa-{route}': 'septa-trolley'
       for route in ('d1', 'd2', 'g1', 't1', 't2', 't3', 't4', 't5')},
    **{f'septa-rail-{route}': 'septa-regional-rail'
       for route in ('air', 'che', 'chw', 'cyn', 'fox', 'lan', 'med',
                      'nor', 'pao', 'tre', 'war', 'wtr', 'wil')},
    'calgary-red': 'calgary-lrt',
    'calgary-blue': 'calgary-lrt',
    'edmonton-capital': 'edmonton-lrt',
    'edmonton-metro': 'edmonton-lrt',
    'edmonton-valley': 'edmonton-lrt',
    'translink-canada': 'translink-system-map',
    'translink-expo': 'translink-system-map',
    'translink-millennium': 'translink-system-map',
    'translink-wce': 'translink-system-map',
    'marta-blue': 'atlanta-official-heavy-rail',
    'marta-gold': 'atlanta-official-heavy-rail',
    'marta-green': 'atlanta-official-heavy-rail',
    'marta-red': 'atlanta-official-heavy-rail',
    'marta-streetcar': 'atlanta-official-streetcar',
    'miami-metrorail': 'miami-dade-metrorail',
    'miami-metromover': 'miami-dade-metromover',
    'maryland-light-rail': 'maryland-mta-light-rail',
    'maryland-metro': 'maryland-mta-metro',
    'modot-kc-streetcar': 'modot-kc-streetcar',
    'modot-stl-metrolink': 'modot-stl-metrolink',
    'sunmetro-streetcar': 'sunmetro-streetcar',
    'nctcog-texrail': 'nctcog-existing-rail-lines',
    **{f'metra-{route}': 'chicago-metra-kml'
       for route in ('bnsf', 'hc', 'md-n', 'md-w', 'me', 'ncs', 'ri',
                     'sws', 'up-n', 'up-nw', 'up-w')},
    'metro-transit-blue': 'metc-transitways',
    'metro-transit-green': 'metc-transitways',
    'cats-blue': 'cats-blue-line',
    'dc-streetcar': 'dcgis-streetcar',
    'dc-streetcar-benning': 'dcgis-streetcar',
    **{f'wmata-metrorail-{route}': 'dcgis-metro-lines-regional'
       for route in ('red', 'blue', 'green', 'yellow', 'orange', 'silver')},
    'mbta-rapid-red-columbia': 'massgis-mbta-rapid',
    **{f'mbta-{suffix}': 'massgis-mbta-commuter-rail-lines'
       for suffix in ('cr-newbedford', 'cr-providence', 'cr-foxboro')},
    **{f'mtq-exo-{route}': 'quebec-mtq-reseau-ferroviaire'
       for route in ('1', '3', '4', '5', '6')},
    'nrwn-on-up-up': 'nrcan-nrwn-on',
    'nrwn-on-go-ki': 'nrcan-nrwn-on',
    'ttc-streetcar-306': 'toronto-ttc-track',
    'ttc-streetcar-501': 'toronto-ttc-track',
    'ttc-streetcar-505': 'toronto-ttc-track',
    'ttc-streetcar-506': 'toronto-ttc-track',
    **{key: 'nctcog-existing-rail-lines' for key in (
        'dart-blue', 'dart-green', 'dart-orange', 'dart-red', 'dart-silver',
        'dart-tre', 'dart-m-line', 'dallas-streetcar', 'texrail',
        'dcta-a-train')},
    'detroit-dpm': 'detroit-people-mover-route',
    'qline': 'detroit-qline-route',
    'cincinnati-connector': 'cagis-cincinnati-streetcar',
    'milwaukee-hop': 'milwaukee-dpw-streetcar',
    'cats-gold': 'cats-gold-line',
    'rta-metra-ri': 'rta-metra-rail-lines',
    'rta-metra-up-n': 'rta-metra-rail-lines',
    'rta-metra-up-w': 'rta-metra-rail-lines',
    'houston-metrorail-900': 'houston-metrorail-lines',
    'fdot-brightline': 'fdot-brightline',
    'fdot-sunrail': 'fdot-sunrail',
    'oregonmetro-rlis-portland-streetcar-a':
        'oregonmetro-rlis-rail-transit',
}

SHA256 = re.compile(r'^[0-9a-f]{64}$')


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as source:
        for chunk in iter(lambda: source.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def verify_route_networks(directory, requested_keys):
    """Return ``(verified metadata by key, diagnostics)``.

    Diagnostics are intentionally suitable for the build log but contain no
    untrusted file contents.  A bad entry is omitted, so callers fail closed.
    """
    verified = {}
    diagnostics = []
    manifest_path = os.path.join(directory, 'manifest.json')
    try:
        with open(manifest_path, encoding='utf-8') as source:
            manifest = json.load(source)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        return {}, [f'official network manifest unavailable or invalid: {exc}']
    if manifest.get('schemaVersion') != 1:
        return {}, ['official network manifest has unsupported schemaVersion']

    source_for_key = {
        key: (KEY_SOURCE_EXACT.get(key)
              or next((source_id
                       for prefix, source_id in KEY_SOURCE_PREFIXES.items()
                       if key.startswith(prefix)), None))
        for key in requested_keys
    }
    needed_sources = {value for value in source_for_key.values() if value}
    declared_sources = manifest.get('sources') or {}
    source_by_signature = {}
    for source_id in sorted(needed_sources):
        expected = SOURCES[source_id]
        declared = declared_sources.get(source_id) or {}
        raw_sha = str(declared.get('rawSha256') or '').lower()
        if (declared.get('publisher') != expected['publisher']
                or declared.get('url') != expected['url']
                or not SHA256.fullmatch(raw_sha)):
            diagnostics.append(
                f'{source_id}: official source provenance is missing or invalid')
            continue
        signature = (expected['publisher'], expected['url'], raw_sha)
        source_by_signature[signature] = source_id

    files = manifest.get('files') or {}
    for key in sorted(set(requested_keys)):
        if source_for_key.get(key) is None:
            diagnostics.append(f'{key}: no reviewed official source owns this key')
            continue
        record = files.get(key) or {}
        expected_name = f'{key}.geojson'
        if record.get('file') != expected_name:
            diagnostics.append(f'{key}: manifest has no exact route extract')
            continue
        expected_sha = str(record.get('sha256') or '').lower()
        if not SHA256.fullmatch(expected_sha):
            diagnostics.append(f'{key}: normalized SHA-256 is missing or invalid')
            continue
        path = os.path.join(directory, expected_name)
        try:
            actual_sha = file_sha256(path)
            with open(path, encoding='utf-8') as source:
                payload = json.load(source)
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            diagnostics.append(f'{key}: route extract unavailable or invalid: {exc}')
            continue
        if actual_sha != expected_sha:
            diagnostics.append(f'{key}: normalized SHA-256 mismatch')
            continue
        source = payload.get('source') or {}
        signature = (
            source.get('publisher'), source.get('url'),
            str(source.get('rawSha256') or '').lower())
        source_id = source_by_signature.get(signature)
        features = payload.get('features') or []
        if (payload.get('type') != 'FeatureCollection'
                or payload.get('sourceId') != key
                or source_id != source_for_key[key]
                or record.get('features') != len(features)
                or not features):
            diagnostics.append(f'{key}: normalized payload provenance is invalid')
            continue
        verified[key] = {
            'sourceId': source_id,
            'publisher': source['publisher'],
            'url': source['url'],
            'rawSha256': source['rawSha256'],
            'sha256': actual_sha,
        }
    return verified, diagnostics
