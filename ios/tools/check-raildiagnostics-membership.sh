#!/usr/bin/env bash
# Guard: RailDiagnostics compiles ios/RailMap wholesale (project.yml `path: ../../RailMap`), so its
# committed project.pbxproj must list every Swift file there. A stale project (new RailMap file added,
# xcodegen not re-run) fails the Mac Catalyst build with "cannot find ... in scope".
# Fix: xcodegen generate --spec ios/auxiliary/RailDiagnostics/project.yml
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PBX="$ROOT/ios/auxiliary/RailDiagnostics/RailDiagnostics.xcodeproj/project.pbxproj"
missing=0
while IFS= read -r f; do
  b="$(basename "$f")"
  grep -q "/\* $b \*/" "$PBX" || { echo "RailDiagnostics project.pbxproj is missing $f"; missing=1; }
done < <(find "$ROOT/ios/RailMap" -name '*.swift')
if [ "$missing" -eq 0 ]; then
  echo "RailDiagnostics membership ok"
else
  echo "Run: xcodegen generate --spec ios/auxiliary/RailDiagnostics/project.yml"
  exit 1
fi
