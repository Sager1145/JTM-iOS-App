#!/bin/bash
# Bake the prebuilt rail map packs through a hash-keyed cache (docs/maintenance/2026-11-12-prebuilt-rail-map-pack.md, section 6).
#
#   ios/tools/bake-rail-packs.sh BUILDER_DIR DEST_DIR [--regions "jp tw hk mo kr"] [--levels 8...34]
#
# BUILDER_DIR is the directory `build-display-network.py` wrote (manifest.json, {region}.display.bin,
# {region}.stations.json, {region}.display-history.json, {region}.topology.bin). For every pack the
# build makes (`rail_pack_inputs.py variants`) the script computes the pack's inputsSHA256, looks in
# ios/.build/railpack-cache/{inputsSHA256}/, bakes with `RailBake` only on a miss, copies the pack to
# DEST_DIR and then runs the freshness guard on what it copied. Packs are not committed to git.
#
# Nothing calls this yet: the packs are not in the app bundle or the Xcode project, and the
# "Copy rail packages" phase (ios/copy-rail-packages.sh) does not run it.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
inputs="$here/rail_pack_inputs.py"

usage() { echo "usage: bake-rail-packs.sh BUILDER_DIR DEST_DIR [--regions \"jp tw hk mo kr\"] [--levels 8...34]" >&2; exit 2; }
[ $# -ge 2 ] || usage
builder_dir=$1
dest_dir=$2
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
[ -d "$builder_dir" ] || { echo "error: no builder directory $builder_dir" >&2; exit 1; }

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cache_root="$root/ios/.build/railpack-cache"
tool_scratch="$root/ios/.build/railbake-tool"
toolchain=$(python3 -I "$inputs" toolchain)
mkdir -p "$dest_dir" "$cache_root"

tool=""
ensure_tool() {
    [ -n "$tool" ] && return 0
    swift build -c release --package-path "$root/ios/tools/railbake" --scratch-path "$tool_scratch" --product RailBake >&2
    tool="$(swift build -c release --package-path "$root/ios/tools/railbake" --scratch-path "$tool_scratch" --show-bin-path)/RailBake"
}

baked=0
hits=0
while read -r region datum name; do
    key=$(python3 -I "$inputs" key --builder-dir "$builder_dir" --region "$region" --datum "$datum" \
        --levels "$levels" --toolchain "$toolchain")
    cached="$cache_root/$key/$name"
    if [ -f "$cached" ]; then
        hits=$((hits + 1))
        echo "cache hit  $name ($key)"
    else
        ensure_tool
        mkdir -p "$cache_root/$key"
        echo "baking     $name ($key)"
        "$tool" --builder-dir "$builder_dir" --region "$region" --datum "$datum" --levels "$levels" \
            --inputs-sha256 "$key" --output "$cached.partial" --report > "$cache_root/$key/$name.report.txt"
        mv "$cached.partial" "$cached"
        baked=$((baked + 1))
    fi
    cp -p "$cached" "$dest_dir/$name"
done < <(python3 -I "$inputs" variants --regions "$regions")

bash "$here/check-rail-packs-fresh.sh" "$builder_dir" "$dest_dir" --regions "$regions" --levels "$levels"
echo "rail packs in $dest_dir: $baked baked, $hits from cache"
