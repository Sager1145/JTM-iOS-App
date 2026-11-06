#!/bin/bash
# Proves a Release/Archive RailMap.app contains none of the DEBUG developer
# tools: no railmap-test URL scheme, and no control-channel or developer-ball
# code or strings in the main binary or any embedded framework/dylib.
#
#   bash ios/tools/app-control/check-release-clean.sh /path/to/Release/RailMap.app
#   bash ios/tools/app-control/check-release-clean.sh --debug-sanity /path/to/Debug/RailMap.app
#
# --debug-sanity inverts the check on a Debug build (the markers MUST be there),
# which proves the markers are real. Exit 0 clean, 1 markers found / missing, 2 usage.
set -euo pipefail

expect_present=false
if [[ "${1:-}" == "--debug-sanity" ]]; then expect_present=true; shift; fi
app=${1:-}
[[ -d "$app" ]] || { echo "usage: $0 [--debug-sanity] RailMap.app" >&2; exit 2; }

# Type names (reflection metadata) and string literals longer than 15 bytes
# (shorter Swift literals are stored inline in code, invisible to `strings`)
# that exist only in #if DEBUG code. The URL scheme is checked in Info.plist.
markers=(
  RailMapAppControl
  AppControlHost
  AppControlDispatcher
  AppControlRequest
  AppControlEditorHandle
  AppControlCameraRun
  DevToolsController
  DevToolsWindow
  DevPerfSampler
  DevStorage
  SignpostRecorder
  RAILMAP_APP_CONTROL
  RAILMAP_DEVTOOLS
  RAILMAP_SIGNPOST_RECORDER
  appControlLastResult
  devtools.storageOverride
)

binaries=()
main="$app/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist" 2>/dev/null || echo RailMap)"
[[ -f "$main" ]] || main="$app/Contents/MacOS/RailMap"   # Mac Catalyst layout
[[ -f "$main" ]] && binaries+=("$main")
while IFS= read -r -d '' file; do
  if file "$file" | grep -q 'Mach-O'; then binaries+=("$file"); fi
done < <(find "$app" \( -name '*.dylib' -o -path '*.framework/*' -type f \) -print0 2>/dev/null)

found=()
plist="$app/Info.plist"; [[ -f "$plist" ]] || plist="$app/Contents/Info.plist"
if plutil -convert xml1 -o - "$plist" | grep -q 'railmap-test'; then found+=("Info.plist: railmap-test URL scheme"); fi

for bin in "${binaries[@]}"; do
  dump=$( { strings -a "$bin"; nm -m "$bin" 2>/dev/null | xcrun swift-demangle 2>/dev/null || true; } )
  for marker in "${markers[@]}"; do
    if grep -qF -- "$marker" <<<"$dump"; then found+=("$(basename "$bin"): $marker"); fi
  done
done

if $expect_present; then
  # Every marker must be detectable in a Debug build, or it proves nothing in Release.
  missing=()
  for marker in "${markers[@]}"; do
    printf '%s\n' "${found[@]}" | grep -qF -- ": $marker" || missing+=("$marker")
  done
  if (( ${#missing[@]} > 0 )); then
    echo "debug-sanity FAILED: not detectable in Debug: ${missing[*]}" >&2; exit 1
  fi
  echo "debug-sanity ok: all ${#markers[@]} markers detected in Debug (${#binaries[@]} binaries scanned)"
  exit 0
fi
if (( ${#found[@]} > 0 )); then
  echo "Release NOT clean (${#binaries[@]} binaries scanned):" >&2
  printf '  %s\n' "${found[@]}" >&2
  exit 1
fi
echo "Release clean: no developer-tool markers in ${#binaries[@]} binaries or the Info.plist"
