#!/bin/bash
source "$(dirname "$0")/common.sh"
filter=''
scratch=/private/tmp/railkit-build-bis
while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter) value "$@"; filter=$2; shift 2 ;;
    --scratch) value "$@"; scratch=$2; shift 2 ;;
    --jobs) value "$@"; jobs=$2; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) fail "Unknown Swift option: $1" ;;
  esac
done
[[ -n "$filter" ]] || fail 'Swift checks require --filter TEST_NAME; there is no default full suite.'
check_jobs
run swift test --package-path "$verification_root/RailKit" --scratch-path "$scratch" --jobs "$jobs" --filter "$filter"
