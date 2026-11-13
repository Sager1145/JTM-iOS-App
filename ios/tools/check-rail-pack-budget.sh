#!/bin/bash
# Size guard for the baked rail map packs (docs/maintenance/2026-11-13-rail-pack-size-design.md,
# sections 4.6 and 8): every pack in PACK_DIR is within its region's byte budget and all of them
# together are within the bundle budget (60,000,000 bytes, user requirement). Exits 1 and says which
# limit broke; never edit the budgets to make it pass.
#
#   ios/tools/check-rail-pack-budget.sh PACK_DIR [BUDGETS_JSON]
#
# The per-level vertex ceilings and the phone and pad window caps are checked by
# `RailBake --budgets` when each pack is baked (bake-rail-packs.sh passes the same file); this
# script only needs the finished files, so it also runs on a directory of cached packs.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
[ $# -ge 1 ] || { echo "usage: check-rail-pack-budget.sh PACK_DIR [BUDGETS_JSON]" >&2; exit 2; }
pack_dir=$1
budgets=${2:-$here/railbake/pack-budgets.json}
[ -d "$pack_dir" ] || { echo "error: no pack directory $pack_dir" >&2; exit 2; }
[ -f "$budgets" ] || { echo "error: no budgets file $budgets" >&2; exit 2; }

python3 -I - "$pack_dir" "$budgets" <<'PY'
import json
import sys
from pathlib import Path

pack_dir, budgets = Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text())
packs = sorted(pack_dir.glob("*.railpack"))
if not packs:
    print(f"error: no .railpack files in {pack_dir}", file=sys.stderr)
    sys.exit(2)
total = 0
failed = False
for pack in packs:
    size = pack.stat().st_size
    total += size
    region = pack.name.split(".")[0]
    limit = budgets["packs"].get(region, {}).get("bytes")
    state = "ok"
    if limit is None:
        state = "NO BUDGET for this region"
        failed = True
    elif size > limit:
        state = f"OVER its budget of {limit}"
        failed = True
    print(f"{pack.name:<18} {size:>12} bytes  {state}")
bundle = budgets["bundleBytes"]
print(f"{'total':<18} {total:>12} bytes  of {bundle}")
if total > bundle:
    print(f"error: the packs total {total} bytes, over the {bundle} byte bundle budget "
          f"by {total - bundle}", file=sys.stderr)
    failed = True
sys.exit(1 if failed else 0)
PY
