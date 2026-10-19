#!/bin/bash
set -euo pipefail
verification_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
dry_run=false
jobs=2
fail() { echo "$*" >&2; exit 2; }
value() { [[ $# -ge 2 && -n "$2" ]] || fail "Missing value for $1"; }
check_jobs() { [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail '--jobs must be a positive integer'; }
run() {
  printf 'Command:'; printf ' %q' "$@"; printf '\n'
  if ! "$dry_run"; then "$@"; fi
}
