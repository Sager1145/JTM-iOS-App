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
# Help needs no rebuild when the binary is newer than every AreaRepair source
# (a cheap mtime check), so `--help` never waits behind other sessions' jobs.
wants_help=false
if [[ $# -eq 0 ]]; then wants_help=true; fi
for arg in "$@"; do
  if [[ $arg == --help || $arg == -h || $arg == help ]]; then wants_help=true; fi
done
fresh=false
if "$wants_help" && [[ -x $binary ]] \
  && [[ -z $(find "$package/Sources" "$package/Package.swift" -newer "$binary" -print -quit) ]]; then
  fresh=true
fi
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
if ! "$fresh"; then
  # The machine-wide lock convention of /private/tmp/jtm-heavy-job-run.sh:
  # the holder records pid and cmd; a waiter clears the lock only when its
  # pid file names a dead process (never one without a pid file) and says
  # once whom it is waiting for.
  release_lock() { rm -f "$lock/pid" "$lock/cmd"; rmdir "$lock" 2>/dev/null || true; }
  announced=false
  while ! mkdir "$lock" 2>/dev/null; do
    holder=$(cat "$lock/pid" 2>/dev/null || true)
    if [[ -n $holder ]] && ! kill -0 "$holder" 2>/dev/null; then
      rm -f "$lock/pid" "$lock/cmd"; rmdir "$lock" 2>/dev/null || true
      continue
    fi
    if ! "$announced"; then
      echo "jtm-area: waiting for heavy-job lock held by PID ${holder:-unknown} ($(cat "$lock/cmd" 2>/dev/null || true))" >&2
      announced=true
    fi
    sleep 20
  done
  echo $$ > "$lock/pid"
  printf '%s\n' "${build[*]}" > "$lock/cmd"
  trap release_lock EXIT
  "${build[@]}" >&2 || fail 'jtm-area build failed.'
  # Release before exec: guard/write/undo take the lock for their swift tests.
  release_lock
  trap - EXIT
fi
exec "$binary" "$@"
