#!/bin/bash
# Explicit, optional checks. No default test suite or automatic build.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
module=${1:-help}
case "$module" in
  help|--help|-h)
    cat <<'EOF'
Usage: ios/verify.sh MODULE [options]
  swift      --filter TEST_NAME [--jobs N] [--scratch PATH]
  build      --target diagnostics [--jobs N] [--derived-data PATH]
  diagnostic --request JSON [--app APP_PATH]
Add --dry-run to print a selected command without executing it.
Default: help only. No full Swift suite, clean build, or automatic retries.
The diagnostic module launches the unified native app; launch success is not inspection success.
Run one heavy job at a time. See ios/VERIFICATION.md for result interpretation.
EOF
    exit 0 ;;
  swift|build|diagnostic) shift ;;
  *) echo "Unknown module: $module" >&2; exit 2 ;;
esac
exec bash "$root/ios/tools/verification/$module.sh" "$@"
