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
usage: rebuild-na-official-networks.sh --source-dir DIR [--raw-dir DIR] [--from STEP]

  --source-dir DIR  rail source tree; writes DIR/official-networks and reads
                    the operator GTFS three normalizers need from DIR/gtfs
  --raw-dir DIR     cache of raw government downloads
                    (default: <source-dir>/official-raw)
  --from STEP       skip every normalizer step before STEP (raw downloads
                    still run, but are already a no-op for cached files).
                    One failing step should not force re-running every
                    normalizer that already passed; steps, in order:
                    mta-cta-norta, ttc-subway, ottawa, ca-central,
                    via-ontario, canada-west, east, septa-regional-rail,
                    intercity, vre,
                    midwest, northeast-commuter, northeast2, canada-east,
                    south-midwest2, south-central, southeast-midwest,
                    west-central-strict, oregon-metro, us-mountain,
                    us-south, us-west-metro, caltrans, us-west
                    (the final provenance report always runs)
USAGE
}

source_dir=""
raw_dir=""
from_step=""
while [ $# -gt 0 ]; do
    case "$1" in
        --source-dir) source_dir=${2:?--source-dir needs a path}; shift 2 ;;
        --raw-dir) raw_dir=${2:?--raw-dir needs a path}; shift 2 ;;
        --from) from_step=${2:?--from needs a step name}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument $1" >&2; usage; exit 2 ;;
    esac
done
if [ -z "$source_dir" ]; then
    usage
    exit 2
fi

# Gate for --from: each normalizer step below is wrapped in
# `if should_run STEP; then ...; fi` so a rerun after a single failing step
# does not have to redo every earlier (already-verified) normalizer, or
# refetch anything -- the raw-download block above already skips any file
# that is already cached, whether or not --from is given.
step_reached=0
should_run() {
    if [ -z "$from_step" ]; then
        return 0
    fi
    if [ "$step_reached" -eq 1 ]; then
        return 0
    fi
    if [ "$1" = "$from_step" ]; then
        step_reached=1
        return 0
    fi
    return 1
}

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
        ttc|ontario-orwn|nrcan-nrwn-on|metc-transitways) echo "$raw_dir/$1.zip" ;;
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
if should_run mta-cta-norta; then
    python3 "$here/download-north-america-official-networks.py" \
        --output-dir "$out_dir" \
        --mta-input "$(raw mta)" \
        --cta-input "$(raw cta)" \
        --norta-input "$(raw norta)"
fi

# TTC subway, from the City of Toronto shapefile package.
if should_run ttc-subway; then
    python3 "$here/normalize-canada-official-networks.py" \
        --output-dir "$out_dir" \
        --ttc-subway-zip "$(raw ttc)"
fi

# O-Train Lines 2 and 4, cut from the City of Ottawa engineering alignment by
# OC Transpo's official station order.
if should_run ottawa; then
    python3 "$here/normalize-ottawa-official-networks.py" \
        --output-dir "$out_dir" \
        --alignment-input "$(raw ottawa-trillium)" \
        --gtfs-input "$gtfs_dir/2154.zip"
fi

# GO Transit and UP Express, cut out of the Ontario railway network by the
# operator's own GTFS.
if should_run ca-central; then
    python3 "$here/normalize-ca-central-official-networks.py" \
        --output-dir "$out_dir" \
        --orwn-input "$(raw ontario-orwn)" \
        --go-gtfs "$gtfs_dir/mdb-1993.zip" \
        --up-gtfs "$gtfs_dir/1995.zip"
fi

# VIA's three accepted Ontario corridors are isolated from that same
# provincial railway inventory. Other VIA routes stay fail-closed unless a
# separate route-specific government centreline is added to the registry.
if should_run via-ontario; then
    python3 "$here/normalize-via-ontario-official-networks.py" \
        --output-dir "$out_dir" \
        --orwn-input "$(raw ontario-orwn)" \
        --via-gtfs "$gtfs_dir/735.zip"
fi

# Calgary, Edmonton and TransLink.
if should_run canada-west; then
    python3 "$here/normalize-canada-west-official-networks.py" \
        --output-dir "$out_dir" \
        --calgary-input "$(raw calgary-lrt)" \
        --edmonton-input "$(raw edmonton-lrt)" \
        --translink-input "$(raw translink-system-map)"
fi

# MBTA rapid transit and commuter rail (MassGIS), SEPTA high-speed and
# trolley.
if should_run east; then
    python3 "$here/normalize-east-official-networks.py" \
        --output-dir "$out_dir" \
        --massgis-mbta-rapid-input "$(raw massgis-mbta-rapid)" \
        --massgis-mbta-commuter-input "$(raw massgis-mbta-commuter)" \
        --septa-high-speed-input "$(raw septa-high-speed)" \
        --septa-trolley-input "$(raw septa-trolley)"
fi

# SEPTA Regional Rail (OpenDataPhilly). A separate step from `east` above:
# the layer needs no route-token grouping (Route_Name already names the
# branch) and belongs to a separate GTFS feed record (na-feeds.json slug
# septa-regional-rail, mdb-503) from SEPTA's bus/trolley/high-speed feed.
if should_run septa-regional-rail; then
    python3 "$here/normalize-septa-regional-rail-official-networks.py" \
        --output-dir "$out_dir" \
        --septa-regional-rail-input "$(raw septa-regional-rail)"
fi

# Amtrak (NTAD), Metro-North and Metrolink. `--mnr-input` and the
# `--lirr-input` two blocks below are deliberately the same file: both
# branches come from one MTA rail-branch layer, and feeding it twice is what
# keeps the single `mta-rail-branches` manifest record consistent with the
# bytes both halves were cut from.
if should_run intercity; then
    python3 "$here/normalize-intercity-official-networks.py" \
        --output-dir "$out_dir" \
        --amtrak-input "$(raw amtrak-ntad)" \
        --mnr-input "$(raw mta-rail-branches)" \
        --metrolink-input "$(raw metrolink-scrra)"
fi

# Virginia Railway Express, cut from Virginia DRPT's passenger-rail lines.
if should_run vre; then
    python3 "$here/normalize-vre-official-networks.py" \
        --output-dir "$out_dir" \
        --input "$(raw virginia-drpt-vre)"
fi

# Metra and Metro Transit (Twin Cities).
if should_run midwest; then
    python3 "$here/normalize-midwest-official-networks.py" \
        --output-dir "$out_dir" \
        --metra-kml "$(raw chicago-metra-kml)" \
        --metc-transitways-zip "$(raw metc-transitways)"
fi

# Long Island Rail Road, NJ Transit rail and light rail, PATH.
if should_run northeast-commuter; then
    python3 "$here/normalize-northeast-commuter-official-networks.py" \
        --output-dir "$out_dir" \
        --lirr-input "$(raw mta-rail-branches)" \
        --njt-rail-input "$(raw njt-rail)" \
        --njt-light-input "$(raw njt-light)" \
        --path-input "$(raw njt-path)"
fi

# Route-isolated Northeast updates: DCGIS Metrorail, MTA service lines,
# reviewed LIRR seams, current South Coast Rail, one-track DC Streetcar and
# Pittsburgh Regional Transit fixed guideways. This runs after the older
# regional normalizers because it owns only the new route-specific keys and
# merges them into the same provenance manifest.
if should_run northeast2; then
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
fi

# Eastern Canada: Québec's provincial rail inventory, NRCan's Ontario
# railway network and Toronto's track asset centreline. Operator GTFS is used
# only to select station order; every output coordinate remains government GIS.
if should_run canada-east; then
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
fi

# Route-isolated government/agency GIS for Dallas/Fort Worth, Detroit,
# Cincinnati, Milwaukee, Charlotte, Metra and Houston.
if should_run south-midwest2; then
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
fi

# CATS, DC Streetcar, Brightline and SunRail.
if should_run south-central; then
    python3 "$here/normalize-south-central-official-networks.py" \
        --output-dir "$out_dir" \
        --cats-blue-line "$(raw cats-blue-line)" \
        --dcgis-streetcar "$(raw dcgis-streetcar)" \
        --fdot-brightline "$(raw fdot-brightline)" \
        --fdot-sunrail "$(raw fdot-sunrail)"
fi

# MARTA, Miami-Dade, Maryland MTA and the two MoDOT layers.
if should_run southeast-midwest; then
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
fi

# El Paso Streetcar and TEXRail. Both are independent city/regional GIS
# centrelines rather than exports of the operator GTFS used for station order.
if should_run west-central-strict; then
    python3 "$here/normalize-west-central-strict-official-networks.py" \
        --output-dir "$out_dir" \
        --sunmetro-input "$(raw sunmetro-streetcar)" \
        --nctcog-input "$(raw nctcog-existing-rail-lines)"
fi

# Portland Streetcar A Loop, isolated from Oregon Metro RLIS's independently
# surveyed physical rail inventory. Other TriMet/Streetcar routes remain
# blocked until they are reviewed and mapped separately.
if should_run oregon-metro; then
    python3 "$here/normalize-oregon-metro-official-networks.py" \
        --output-dir "$out_dir" \
        --input "$(raw oregonmetro-rlis-rail-transit)"
fi

# UTA. The reviewed endpoint already filters the state layer to
# OPERATOR='UT Transit Auth'; the normalizer refuses any other operator, so
# an unfiltered copy of the Utah railroad layer is not a substitute.
if should_run us-mountain; then
    python3 "$here/normalize-us-mountain-official-networks.py" \
        --output-dir "$out_dir" \
        --railroad-input "$(raw utah-railroads)" \
        --gtfs-input "$gtfs_dir/170.zip"
fi

# Houston METRORail.
if should_run us-south; then
    python3 "$here/normalize-us-south-official-networks.py" \
        --output-dir "$out_dir" \
        --input "$(raw houston-metro)"
fi

# LA Metro rail and SFMTA Muni Metro.
if should_run us-west-metro; then
    python3 "$here/normalize-us-west-metro-official-networks.py" \
        --output-dir "$out_dir" \
        --la-input "$(raw la-metro)" \
        --sfmta-input "$(raw sfmta)"
fi

# Caltrain and San Diego Trolley, isolated from Caltrans' statewide rail
# network.  Route-level gates in the registry decide which extracts are
# complete enough to publish.
if should_run caltrans; then
    python3 "$here/normalize-caltrans-official-networks.py" \
        --output-dir "$out_dir" \
        --input "$(raw caltrans-crn)"
fi

# VTA light rail. Sound Transit engineering GIS is deliberately absent: its
# licence makes it a local reference-only input, never a distributable
# official-network source. See docs/NORTH_AMERICA_RAIL_OPTIMIZATION.md.
if should_run us-west; then
    python3 "$here/normalize-us-west-official-networks.py" \
        --output-dir "$out_dir" \
        --vta-input "$(raw vta)"
fi

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
