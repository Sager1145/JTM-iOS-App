#!/bin/bash
# Cold-launch Main twice at one exact camera: network ON, then OFF (showsNetwork
# defaults to false and is not persisted, so an unknown layer key leaves it off).
# Captures only after two consecutive identical window frames (render settled).
# usage: ios/tools/verification/main-cold-pair.sh OUTDIR STATIONID LAT LON SPAN STORAGEID [APP]
set -u
out=$1 sid=$2 lat=$3 lon=$4 span=$5 store=$6
APP=${7:-/Users/sager/Library/Developer/Xcode/DerivedData/RailMap-cysvihgspfvwbzatdiakpqjbxkno/Build/Products/Debug-maccatalyst/RailMap.app}
EXE="$APP/Contents/MacOS/RailMap"; HERE=$(cd "$(dirname "$0")" && pwd)
CACHE="${TMPDIR:-/tmp}/jtm-main-cold-pair"; mkdir -p "$CACHE"
WINID="$CACHE/winid"
[ -x "$WINID" ] && [ "$WINID" -nt "$HERE/winid.swift" ] || swiftc -O "$HERE/winid.swift" -o "$WINID"
tmp=$(mktemp -d)
quit() { pkill -f "$EXE"; for i in $(seq 20); do pgrep -f "$EXE" >/dev/null || return 0; sleep 0.5; done; pkill -9 -f "$EXE"; sleep 1; }
shot() {
  quit
  open -n "$APP" --env RAILMAP_UI_TEST_CAMERA=$lat,$lon,$span --env RAILMAP_UI_TEST_LAYERS=$2 --env RAILMAP_UI_TEST_STAGE=compact --env RAILMAP_UI_TEST_STORAGE_ID=$store
  sleep $((10 + ${MINWAIT:-0})); pid=$(pgrep -f "$EXE" | head -1); w=$("$WINID" $pid); prev=""
  for i in $(seq 30); do
    screencapture -x -o -l "$w" "$tmp/f.png"; h=$(shasum -a 256 "$tmp/f.png" | cut -c1-64)
    if [ "$h" = "$prev" ]; then break; fi; prev=$h; sleep 3
  done
  mv "$tmp/f.png" "$out/$sid-cold-$1.png"
  echo "{\"station\":\"$sid\",\"mode\":\"$1\",\"pid\":$pid,\"window\":$w,\"settledAfterPolls\":$i,\"sha256\":\"$h\"}"
}
# A settled frame can still be a pre-render frame, and lines draw in their own colours,
# so compare ON with OFF in the map area (outside the panel and controls): an ON frame
# whose overlay has not rendered differs from OFF by almost nothing. Retry ON with longer waits.
VENV="$HERE/../../../railway-evidence/local/tools/pyenv/bin/python"; [ -x "$VENV" ] && DEFPY="$VENV" || DEFPY=python3; PY=${RAILMAP_PYTHON:-$DEFPY}
# The venv lives in the iCloud-synced evidence folder; a stalled read once hung a wave for 2 h.
pyt() { perl -e 'alarm shift; exec @ARGV' 120 "$PY" "$@"; }
diffpx() { pyt -I -c "
import sys
from PIL import Image, ImageChops
a=Image.open(sys.argv[1]).convert('RGB').crop((440,40,1130,690)); b=Image.open(sys.argv[2]).convert('RGB').crop((440,40,1130,690))
n=sum(1 for v in ImageChops.difference(a,b).convert('L').getdata() if v>40)
# An inactive (background) window greys the toolbar badge and MapKit may skip the overlay: treat as not rendered.
badge=Image.open(sys.argv[1]).convert('RGB').crop((325,712,362,750))
print(n if sum(1 for r,g,bl in badge.getdata() if bl>180 and bl-r>80)>=100 else 0)" "$out/$sid-cold-on.png" "$out/$sid-cold-off.png"; }
shot off none
if ! pyt -I -c "import PIL" 2>/dev/null; then
  shot on network; quit; rm -rf "$tmp"
  echo "WARNING: PIL missing for $PY; ON/OFF guard skipped (set RAILMAP_PYTHON to a python with Pillow)" >&2; exit 0
fi
for extra in 0 20 45; do
  MINWAIT=$extra shot on network; n=$(diffpx)
  echo "{\"station\":\"$sid\",\"onOffDifferencePixels\":$n,\"extraWaitSeconds\":$extra}"
  [ "$n" -ge 300 ] && break
done
quit; rm -rf "$tmp"
[ "$n" -ge 300 ] || { echo "WARNING $sid: overlay never rendered in ON capture" >&2; exit 2; }
