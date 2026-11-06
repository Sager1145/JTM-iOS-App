#!/bin/bash
# Headless area capture/problems/preview/write CLI (jtm-area). Builds the CLI
# incrementally inside the shared heavy-job lock, releases the lock, then runs
# the binary: guard/write/undo take the same lock themselves for their swift
# tests, so holding it here would deadlock.
source "$(dirname "$0")/common.sh"
package="$verification_root/auxiliary/RailDiagnostics/Modules/AreaRepair"
scratch=${JTM_AREA_SCRATCH:-/private/tmp/jtm-area-build}
config=${JTM_AREA_CONFIG:-release}
lock=/private/tmp/jtm-heavy-job.lock
# --dry-run is this wrapper's only option and is recognised in first position
# (jtm-area verbs such as `guard` have their own --dry-run).
if [[ ${1:-} == --dry-run ]]; then dry_run=true; shift; fi
build=(swift build --package-path "$package" --product jtm-area --scratch-path "$scratch" -c "$config")
binary="$scratch/$config/jtm-area"
if "$dry_run"; then
  printf 'Build (inside heavy-job lock):'; printf ' %q' "${build[@]}"; printf '\n'
  printf 'Run (lock released):'; printf ' %q' "$binary" "$@"; printf '\n'
  exit 0
fi
(
  until mkdir "$lock" 2>/dev/null; do sleep 20; done
  trap 'rmdir "$lock"' EXIT
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer "${build[@]}" >&2
) || fail 'jtm-area build failed.'
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
exec "$binary" "$@"
