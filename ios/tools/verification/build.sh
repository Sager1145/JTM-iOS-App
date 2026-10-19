#!/bin/bash
source "$(dirname "$0")/common.sh"
target=''
derived=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) value "$@"; target=$2; shift 2 ;;
    --derived-data) value "$@"; derived=$2; shift 2 ;;
    --jobs) value "$@"; jobs=$2; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) fail "Unknown build option: $1" ;;
  esac
done
case "$target" in
  diagnostics) scheme=RailDiagnostics; derived=${derived:-/private/tmp/jtm-rail-diagnostics} ;;
  *) fail 'Build requires --target diagnostics' ;;
esac
check_jobs
run xcodebuild -project "$verification_root/auxiliary/$scheme/$scheme.xcodeproj" -scheme "$scheme" -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath "$derived" CODE_SIGN_IDENTITY=- -jobs "$jobs" build
