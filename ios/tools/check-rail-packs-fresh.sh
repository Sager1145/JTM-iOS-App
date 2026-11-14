#!/bin/bash
# Freshness guard: every pack in PACK_DIR must carry the inputsSHA256 recomputed from the current
# builder output and sources, and belong to the topology file next to it. Fails (exit 1) on a stale,
# foreign or missing pack. Used by bake-rail-packs.sh after its copy, and runnable on its own.
#
#   ios/tools/check-rail-packs-fresh.sh BUILDER_DIR PACK_DIR [--regions "jp tw hk mo kr"] [--levels 8...34]
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
inputs="$here/rail_pack_inputs.py"

usage() { echo "usage: check-rail-packs-fresh.sh BUILDER_DIR PACK_DIR [--regions \"jp tw hk mo kr\"] [--levels 8...34]" >&2; exit 2; }
[ $# -ge 2 ] || usage
builder_dir=$1
pack_dir=$2
shift 2
regions="jp tw hk mo kr"
levels="8...34"
while [ $# -gt 0 ]; do
    case "$1" in
        --regions) regions=${2:?--regions needs a value}; shift 2 ;;
        --levels) levels=${2:?--levels needs a value}; shift 2 ;;
        *) usage ;;
    esac
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
toolchain=$(python3 -I "$inputs" toolchain)
failed=0
while read -r region name; do
    pack="$pack_dir/$name"
    if [ ! -f "$pack" ]; then
        echo "error: missing pack $pack" >&2
        failed=1
        continue
    fi
    python3 -I "$inputs" check --builder-dir "$builder_dir" --region "$region" \
        --levels "$levels" --toolchain "$toolchain" --pack "$pack" || failed=1
done < <(python3 -I "$inputs" variants --regions "$regions")
if [ "$failed" -ne 0 ]; then
    echo "rail packs are stale: re-run ios/tools/bake-rail-packs.sh" >&2
    exit 1
fi
