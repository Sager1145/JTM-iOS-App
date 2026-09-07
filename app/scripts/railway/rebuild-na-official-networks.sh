#!/bin/sh
# Rebuild <source-dir>/official-networks from the reviewed government sources.
#
# The North America build reads route-isolated GeoJSON out of that directory
# and trusts a route only when `lib/na_provenance.py` can match the manifest
# entry to its allow-listed publisher and endpoint and re-hash the bytes.  A
# tree that is missing those files does not fail the build: the routes are
# silently dropped and the package comes out short.  So the tree has to be
# rebuildable on demand, and this is that command:
#
#   ./rebuild-na-official-networks.sh --source-dir /path/to/jtm-na-rail
#
# Every raw government download is cached under --raw-dir (default
# <source-dir>/official-raw) and reused on the next run.  Re-running is
# therefore idempotent in the sense that matters here — the same raw bytes
# produce the same normalized bytes and the same manifest hashes — while a
# deleted raw file is re-fetched from the same reviewed URL.  Keep the cache:
# a publisher who re-cuts a layer changes the recorded rawSha256, and every
# package hash downstream of it moves with no note in the data saying why.
#
# The URLs are never written here.  They are read out of the SOURCES table in
# `lib/na_provenance.py`, which is the same table the build verifies against,
# so a URL this script fetches cannot drift away from the one the build will
# accept.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
# The two inline Python blocks below import the same provenance module the
# build uses; they are fed the script directory rather than deriving it,
# because a heredoc on stdin has no __file__ of its own.
REBUILD_SCRIPT_DIR="$here"
export REBUILD_SCRIPT_DIR

usage() {
    cat >&2 <<'USAGE'
usage: rebuild-na-official-networks.sh --source-dir DIR [--raw-dir DIR]

  --source-dir DIR  rail source tree; writes DIR/official-networks and reads
                    the operator GTFS three normalizers need from DIR/gtfs
  --raw-dir DIR     cache of raw government downloads
                    (default: <source-dir>/official-raw)
USAGE
}

source_dir=""
raw_dir=""
while [ $# -gt 0 ]; do
    case "$1" in
        --source-dir) source_dir=${2:?--source-dir needs a path}; shift 2 ;;
        --raw-dir) raw_dir=${2:?--raw-dir needs a path}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument $1" >&2; usage; exit 2 ;;
    esac
done
if [ -z "$source_dir" ]; then
    usage
    exit 2
fi

out_dir="$source_dir/official-networks"
gtfs_dir="$source_dir/gtfs"
raw_dir=${raw_dir:-$source_dir/official-raw}
mkdir -p "$out_dir" "$raw_dir"

# Three normalizers copy geometry from a government survey but take station
# selection from the operator's own GTFS, so those feeds must already be in
# the tree. They are named by their registry `mdb` id, exactly as the builder
# resolves them.
for feed in mdb-1993 1995 748 732 170 735 2154; do
    if [ ! -f "$gtfs_dir/$feed.zip" ]; then
        echo "error: missing $gtfs_dir/$feed.zip — run download-north-america-gtfs.py first" >&2
        exit 1
    fi
done

# Fetch every raw input that is not cached yet. One Python process for all of
# them: each download is a separate government endpoint and a failure has to
# name which one, rather than aborting the run with a bare curl exit code.
python3 - "$raw_dir" <<'PY'
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.join(os.environ['REBUILD_SCRIPT_DIR'], 'lib'))
import na_provenance as provenance

# The archive formats the normalizers open by name rather than by sniffing.
SUFFIX = {
    'ttc': '.zip',
    'ontario-orwn': '.zip',
    'nrcan-nrwn-on': '.zip',
    'metc-transitways': '.zip',
    'chicago-metra-kml': '.kml',
}

raw_dir = sys.argv[1]
failed = []
for source_id in sorted(provenance.SOURCES):
    url = provenance.SOURCES[source_id]['url']
    path = os.path.join(raw_dir, source_id + SUFFIX.get(source_id, '.geojson'))
    if os.path.exists(path) and os.path.getsize(path) > 0:
        continue
    request = urllib.request.Request(
        url, headers={'User-Agent': 'jtm-rail-official-networks/1.0'})
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            body = response.read()
    except urllib.error.HTTPError as error:
        failed.append(f'{source_id}: HTTP {error.code} {error.reason}')
        continue
    except OSError as error:
        failed.append(f'{source_id}: {type(error).__name__}: {error}')
        continue
    if not body:
        failed.append(f'{source_id}: empty response')
        continue
    with open(path + '.tmp', 'wb') as target:
        target.write(body)
    os.replace(path + '.tmp', path)
    print(f'fetched {source_id} ({len(body)} bytes)')
for line in failed:
    print('error: ' + line, file=sys.stderr)
sys.exit(1 if failed else 0)
PY

raw() {
    case "$1" in
        ttc|ontario-orwn|metc-transitways) echo "$raw_dir/$1.zip" ;;
        chicago-metra-kml) echo "$raw_dir/$1.kml" ;;
        *) echo "$raw_dir/$1.geojson" ;;
    esac
}

# Each normalizer merges into the shared manifest, so they all write to the
# same --output-dir and the order below does not matter. Inputs are handed
# over as local files rather than left to a per-script download because the
# raw bytes are what the manifest hashes: one download per run, reused by
# every normalizer that needs it, is what keeps two scripts that share a
# source from recording two different rawSha256 values for it.

# MTA subway, CTA and New Orleans RTA.
python3 "$here/download-north-america-official-networks.py" \
    --output-dir "$out_dir" \
    --mta-input "$(raw mta)" \
    --cta-input "$(raw cta)" \
    --norta-input "$(raw norta)"

# TTC subway, from the City of Toronto shapefile package.
python3 "$here/normalize-canada-official-networks.py" \
    --output-dir "$out_dir" \
    --ttc-subway-zip "$(raw ttc)"

# O-Train Lines 2 and 4, cut from the City of Ottawa engineering alignment by
# OC Transpo's official station order.
python3 "$here/normalize-ottawa-official-networks.py" \
    --output-dir "$out_dir" \
    --alignment-input "$(raw ottawa-trillium)" \
    --gtfs-input "$gtfs_dir/2154.zip"

# GO Transit and UP Express, cut out of the Ontario railway network by the
# operator's own GTFS.
python3 "$here/normalize-ca-central-official-networks.py" \
    --output-dir "$out_dir" \
    --orwn-input "$(raw ontario-orwn)" \
    --go-gtfs "$gtfs_dir/mdb-1993.zip" \
    --up-gtfs "$gtfs_dir/1995.zip"

# VIA's three accepted Ontario corridors are isolated from that same
# provincial railway inventory. Other VIA routes stay fail-closed unless a
# separate route-specific government centreline is added to the registry.
python3 "$here/normalize-via-ontario-official-networks.py" \
    --output-dir "$out_dir" \
    --orwn-input "$(raw ontario-orwn)" \
    --via-gtfs "$gtfs_dir/735.zip"

# Calgary, Edmonton and TransLink.
python3 "$here/normalize-canada-west-official-networks.py" \
    --output-dir "$out_dir" \
    --calgary-input "$(raw calgary-lrt)" \
    --edmonton-input "$(raw edmonton-lrt)" \
    --translink-input "$(raw translink-system-map)"

# MBTA rapid transit and commuter rail (MassGIS), SEPTA high-speed and
# trolley.
python3 "$here/normalize-east-official-networks.py" \
    --output-dir "$out_dir" \
    --massgis-mbta-rapid-input "$(raw massgis-mbta-rapid)" \
    --massgis-mbta-commuter-input "$(raw massgis-mbta-commuter)" \
    --septa-high-speed-input "$(raw septa-high-speed)" \
    --septa-trolley-input "$(raw septa-trolley)"

# Amtrak (NTAD), Metro-North and Metrolink. `--mnr-input` and the
# `--lirr-input` two blocks below are deliberately the same file: both
# branches come from one MTA rail-branch layer, and feeding it twice is what
# keeps the single `mta-rail-branches` manifest record consistent with the
# bytes both halves were cut from.
python3 "$here/normalize-intercity-official-networks.py" \
    --output-dir "$out_dir" \
    --amtrak-input "$(raw amtrak-ntad)" \
    --mnr-input "$(raw mta-rail-branches)" \
    --metrolink-input "$(raw metrolink-scrra)"

# Virginia Railway Express, cut from Virginia DRPT's passenger-rail lines.
python3 "$here/normalize-vre-official-networks.py" \
    --output-dir "$out_dir" \
    --input "$(raw virginia-drpt-vre)"

# Metra and Metro Transit (Twin Cities).
python3 "$here/normalize-midwest-official-networks.py" \
    --output-dir "$out_dir" \
    --metra-kml "$(raw chicago-metra-kml)" \
    --metc-transitways-zip "$(raw metc-transitways)"

# Long Island Rail Road, NJ Transit rail and light rail, PATH.
python3 "$here/normalize-northeast-commuter-official-networks.py" \
    --output-dir "$out_dir" \
    --lirr-input "$(raw mta-rail-branches)" \
    --njt-rail-input "$(raw njt-rail)" \
    --njt-light-input "$(raw njt-light)" \
    --path-input "$(raw njt-path)"

# Route-isolated Northeast updates: DCGIS Metrorail, MTA service lines,
# reviewed LIRR seams, current South Coast Rail, one-track DC Streetcar and
# Pittsburgh Regional Transit fixed guideways. This runs after the older
# regional normalizers because it owns only the new route-specific keys and
# merges them into the same provenance manifest.
python3 "$here/normalize-northeast2-official-networks.py" \
    --output-dir "$out_dir" \
    --wmata-input "$(raw dcgis-metro-lines-regional)" \
    --mta-subway-input "$(raw mta)" \
    --mta-rail-branches-input "$(raw mta-rail-branches)" \
    --massgis-mbta-rapid-input "$(raw massgis-mbta-rapid)" \
    --massgis-mbta-commuter-rail-input \
        "$(raw massgis-mbta-commuter-rail-lines)" \
    --dcgis-streetcar-input "$(raw dcgis-streetcar)" \
    --prt-input "$(raw prt-fixed-guideway-corridors)"

# Eastern Canada: Québec's provincial rail inventory, NRCan's Ontario
# railway network and Toronto's track asset centreline. Operator GTFS is used
# only to select station order; every output coordinate remains government GIS.
python3 "$here/normalize-canada-east-official-networks.py" \
    --output-dir "$out_dir" \
    --quebec-input "$(raw quebec-mtq-reseau-ferroviaire)" \
    --exo-gtfs "$gtfs_dir/748.zip" \
    --nrwn-on-input "$(raw nrcan-nrwn-on)" \
    --up-gtfs "$gtfs_dir/1995.zip" \
    --go-gtfs "$gtfs_dir/mdb-1993.zip" \
    --ttc-track-input "$(raw toronto-ttc-track)" \
    --ttc-route-input "$(raw toronto-ttc-route-view)" \
    --ttc-gtfs "$gtfs_dir/732.zip"

# Route-isolated government/agency GIS for Dallas/Fort Worth, Detroit,
# Cincinnati, Milwaukee, Charlotte, Metra and Houston.
python3 "$here/normalize-south-midwest2-official-networks.py" \
    --output-dir "$out_dir" \
    --nctcog-existing-rail-lines-input \
        "$(raw nctcog-existing-rail-lines)" \
    --detroit-people-mover-route-input \
        "$(raw detroit-people-mover-route)" \
    --detroit-qline-route-input "$(raw detroit-qline-route)" \
    --cagis-cincinnati-streetcar-input \
        "$(raw cagis-cincinnati-streetcar)" \
    --milwaukee-dpw-streetcar-input "$(raw milwaukee-dpw-streetcar)" \
    --cats-gold-line-input "$(raw cats-gold-line)" \
    --rta-metra-rail-lines-input "$(raw rta-metra-rail-lines)" \
    --houston-metrorail-lines-input "$(raw houston-metrorail-lines)"

# CATS, DC Streetcar, Brightline and SunRail.
python3 "$here/normalize-south-central-official-networks.py" \
    --output-dir "$out_dir" \
    --cats-blue-line "$(raw cats-blue-line)" \
    --dcgis-streetcar "$(raw dcgis-streetcar)" \
    --fdot-brightline "$(raw fdot-brightline)" \
    --fdot-sunrail "$(raw fdot-sunrail)"

# MARTA, Miami-Dade, Maryland MTA and the two MoDOT layers.
python3 "$here/normalize-southeast-midwest-official-networks.py" \
    --output-dir "$out_dir" \
    --atlanta-official-heavy-rail "$(raw atlanta-official-heavy-rail)" \
    --atlanta-official-streetcar "$(raw atlanta-official-streetcar)" \
    --miami-dade-metrorail "$(raw miami-dade-metrorail)" \
    --miami-dade-metromover "$(raw miami-dade-metromover)" \
    --maryland-mta-light-rail "$(raw maryland-mta-light-rail)" \
    --maryland-mta-metro "$(raw maryland-mta-metro)" \
    --modot-kc-streetcar "$(raw modot-kc-streetcar)" \
    --modot-stl-metrolink "$(raw modot-stl-metrolink)"

# El Paso Streetcar and TEXRail. Both are independent city/regional GIS
# centrelines rather than exports of the operator GTFS used for station order.
python3 "$here/normalize-west-central-strict-official-networks.py" \
    --output-dir "$out_dir" \
    --sunmetro-input "$(raw sunmetro-streetcar)" \
    --nctcog-input "$(raw nctcog-existing-rail-lines)"

# Portland Streetcar A Loop, isolated from Oregon Metro RLIS's independently
# surveyed physical rail inventory. Other TriMet/Streetcar routes remain
# blocked until they are reviewed and mapped separately.
python3 "$here/normalize-oregon-metro-official-networks.py" \
    --output-dir "$out_dir" \
    --input "$(raw oregonmetro-rlis-rail-transit)"

# UTA. The reviewed endpoint already filters the state layer to
# OPERATOR='UT Transit Auth'; the normalizer refuses any other operator, so
# an unfiltered copy of the Utah railroad layer is not a substitute.
python3 "$here/normalize-us-mountain-official-networks.py" \
    --output-dir "$out_dir" \
    --railroad-input "$(raw utah-railroads)" \
    --gtfs-input "$gtfs_dir/170.zip"

# Houston METRORail.
python3 "$here/normalize-us-south-official-networks.py" \
    --output-dir "$out_dir" \
    --input "$(raw houston-metro)"

# LA Metro rail and SFMTA Muni Metro.
python3 "$here/normalize-us-west-metro-official-networks.py" \
    --output-dir "$out_dir" \
    --la-input "$(raw la-metro)" \
    --sfmta-input "$(raw sfmta)"

# Caltrain and San Diego Trolley, isolated from Caltrans' statewide rail
# network.  Route-level gates in the registry decide which extracts are
# complete enough to publish.
python3 "$here/normalize-caltrans-official-networks.py" \
    --output-dir "$out_dir" \
    --input "$(raw caltrans-crn)"

# VTA light rail. Sound Transit engineering GIS is deliberately absent: its
# licence makes it a local reference-only input, never a distributable
# official-network source. See docs/NORTH_AMERICA_RAIL_OPTIMIZATION.md.
python3 "$here/normalize-us-west-official-networks.py" \
    --output-dir "$out_dir" \
    --vta-input "$(raw vta)"

# Report what the build will actually accept, rather than what was written.
# A file on disk is not a verified route: the manifest record, the embedded
# source block and the bytes all have to agree with the reviewed allow-list.
python3 - "$out_dir" "$here/na-feeds.json" <<'PY'
import json
import os
import sys

sys.path.insert(0, os.path.join(os.environ['REBUILD_SCRIPT_DIR'], 'lib'))
import na_provenance as provenance

out_dir, registry_path = sys.argv[1], sys.argv[2]
with open(registry_path, encoding='utf-8') as source:
    registry = json.load(source)

requested = set()


def walk(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == 'officialNetwork' and isinstance(value, str):
                requested.add(value)
            elif key == 'officialNetworkByRouteId' and isinstance(value, dict):
                requested.update(v for v in value.values()
                                 if isinstance(v, str))
            else:
                walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)


walk(registry)
# Québec's VIA alignment is not a route extract in this directory: the build
# reads it straight from <source-dir>/quebec-rail.geojson, so it has no entry
# in the provenance allow-list and is not this script's to produce.
requested.discard('quebec-mtq-via')
verified, diagnostics = provenance.verify_route_networks(out_dir, requested)
print(f'{len(verified)} of {len(requested)} registry keys pass provenance')
for line in diagnostics:
    print('  ' + line)
PY
