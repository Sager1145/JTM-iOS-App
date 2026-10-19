#!/bin/bash
source "$(dirname "$0")/common.sh"
request=''
app=/private/tmp/jtm-rail-diagnostics/Build/Products/Debug-maccatalyst/RailDiagnostics.app
while [[ $# -gt 0 ]]; do
  case "$1" in
    --request) value "$@"; request=$2; shift 2 ;;
    --app) value "$@"; app=$2; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) fail "Unknown diagnostic option: $1" ;;
  esac
done
[[ "$request" = /* && -f "$request" ]] || fail 'Provide an absolute --request JSON file.'
[[ "$app" = /* && -d "$app" ]] || fail 'Built RailDiagnostics.app is missing; build explicitly first.'
run open -a "$app" "$request"
if ! "$dry_run"; then echo 'Request sent to RailDiagnostics. Read processID and run-status.json/result.json in the requested session; open success is not a completed inspection.'; fi
