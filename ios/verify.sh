#!/bin/sh
# The gate. Everything the port has to survive, in one command.
#
# Porting runs in parallel, so "it compiles on my branch" is not a useful
# report — this is what every piece of work is checked against before it is
# claimed to be done, and it is the same command whether a person or an agent
# runs it.
#
#   ./verify.sh            everything
#   ./verify.sh --swift    Swift + app build
#   ./verify.sh --core     RailCore + its parity tests only (the porting loop)
#   ./verify.sh --js       JavaScript only
#
# SCRATCH lets parallel workers avoid fighting over one build directory:
#
#   SCRATCH=/tmp/port-a ./verify.sh --swift
#
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)

# The repository is on an iCloud-backed path. The file provider re-adds
# com.apple.FinderInfo to build products and codesign then refuses to sign
# them ("resource fork, Finder information, or similar detritus not allowed"),
# so the build directory has to live off the synced volume.
scratch=${SCRATCH:-${TMPDIR:-/tmp}railkit-verify}

# Prefer the beta toolchain when it is installed, because that is what this
# port is developed against — but only when it is actually there, or CI (and
# anyone with a plain Xcode) inherits a path that does not exist.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode-beta.app ]; then
    DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
    export DEVELOPER_DIR
fi

run_js=1
run_swift=1
run_app=1
case "${1:-}" in
    --swift) run_js=0 ;;
    # --core skips the app build: several ports can run at once, and the
    # simulator build is both the slowest step and the one that does not
    # contend well.
    --core) run_js=0; run_app=0 ;;
    --js) run_swift=0; run_app=0 ;;
    "") ;;
    *) echo "usage: verify.sh [--swift|--core|--js]" >&2; exit 2 ;;
esac

fail() { echo "FAIL: $1" >&2; exit 1; }

if [ "$run_js" = 1 ]; then
    echo "== JavaScript =================================================="
    cd "$repo/app"

    # The reduced app tree is the reference implementation retained by this
    # standalone repository. --check regenerates into memory and fails if any
    # answer moved. A fixture
    # may only change deliberately: a diff here is the list of answers the
    # Swift port has to be re-verified against.
    node scripts/build/build-port-fixtures.mjs --check >/dev/null 2>&1 \
        || fail "fixtures are stale — rerun build-port-fixtures.mjs and review the diff"
    echo "  fixtures match the code that generated them"
fi

if [ "$run_swift" = 1 ]; then
    echo "== Swift ======================================================="
    cd "$here/RailKit"

    swift build --scratch-path "$scratch" >/dev/null 2>&1 || {
        swift build --scratch-path "$scratch" 2>&1 | grep -E 'error:' | head -20
        fail "swift build"
    }
    echo "  RailCore and RailPresentation build"

    if ! swift test --scratch-path "$scratch" >"$scratch.log" 2>&1; then
        grep -E '^✘|error:' "$scratch.log" | head -30
        fail "swift test (full log: $scratch.log)"
    fi
    # Counted rather than described as "parity tests": most of them are, but
    # RailPresentationTests checks an invariant no fixture can express — that
    # one set of inputs resolves to one primary action — and calling that a
    # parity test would misreport what the number means.
    passed=$(grep -cE '^✔ Test ' "$scratch.log" || true)
    echo "  $passed tests pass"

    # Warnings in our own sources fail the gate.
    #
    # Not pedantry: six ports can be in flight at once, each writing a
    # thousand-odd lines, and a warning nobody owns is one nobody fixes. Scoped
    # to the directories we write, so an SDK or toolchain warning cannot fail a
    # build for something we did not write and cannot fix.
    #
    # This half sees the PACKAGE only. It used to name `RailMap` in the filter
    # too, which read as though the app target were covered — and it never was:
    # `swift build` here builds RailKit, whose log cannot contain a RailMap
    # path, so 26,000 lines of app were being grepped for in a file that could
    # not mention them. The app's own warnings are checked against the app's own
    # build log, below.
    warnings=$(swift build --scratch-path "$scratch" 2>&1 \
        | grep 'warning:' \
        | grep -E '/(RailCore|RailPresentation)/' \
        | sort -u)
    if [ -n "$warnings" ]; then
        echo "$warnings"
        fail "warnings in RailCore or RailPresentation"
    fi
    echo "  no warnings in RailCore or RailPresentation"

    # RailCore must not reach for a platform. That constraint is what makes the
    # port checkable at all — with no platform underneath it, the same code can
    # be run against the same fixtures as the JavaScript. Enforced here because
    # a stray `import MapKit` compiles perfectly well and quietly ends that.
    #
    # RailPresentation is held to the same ban for the same reason. It is the
    # display-state tier of JRM_FLIGHTY_UI_REFACTOR_SPEC.md §11 — the thing that
    # decides which single task a surface is about — and the only reason that
    # decision is testable at all is that it is made without a view underneath
    # it. One `import SwiftUI` and the priority resolver is back inside the app
    # target, where nothing runs it.
    if grep -rlE '^import (MapKit|SwiftUI|UIKit|CoreLocation)' \
        Sources/RailCore/ Sources/RailPresentation/ 2>/dev/null | grep .; then
        fail "a pure target imported a platform framework (see the files above)"
    fi
    echo "  RailCore imports nothing but Foundation"

    # And RailPresentation nothing but Foundation and RailCore: it may consume
    # the ported business logic, never the app's storage or map objects.
    if grep -rhE '^import ' Sources/RailPresentation/ 2>/dev/null \
        | sort -u | grep -vE '^import (Foundation|RailCore)$' | grep .; then
        fail "RailPresentation imported something other than Foundation/RailCore (above)"
    fi
    echo "  RailPresentation imports nothing but Foundation and RailCore"

    # Both renderers decimate, and how far the drawn line may leave the
    # surveyed one is ONE number they have to agree on.
    #
    # Nothing else can catch a disagreement. The DisplayParts fixtures compare
    # the two apps' line geometry BEFORE either of them simplifies, so for as
    # long as this app decimated at 0.5 against the web app's 0.0625 every
    # parity test passed while the drawn line stood eight times further off the
    # track — a difference visible on the map and nowhere in the suite. This is
    # a text contract for the same reason `${API_BASE}` is: the style tier is
    # the one part of the web app that does not port as data.
    js_tolerance=$(grep -oE 'SEGMENT_SIMPLIFY_TOLERANCE_PX = [0-9.]+' \
        "$repo/app/public/railmap-style.js" | sed 's/.*= //')
    swift_tolerance=$(grep -oE 'simplifyTolerance: Double = [0-9.]+' \
        "$here/RailMap/RailStyle.swift" | sed 's/.*= //')
    [ -n "$js_tolerance" ] || fail "SEGMENT_SIMPLIFY_TOLERANCE_PX not found in railmap-style.js"
    [ "$js_tolerance" = "$swift_tolerance" ] || fail \
        "simplify tolerance disagrees: railmap-style.js $js_tolerance, RailStyle.swift ${swift_tolerance:-none}"

    # Equal declarations are not enough: the regression this contract exists
    # for lived in the final MapKit renderer, below every geometry parity test.
    # Keep the renderer wired to the shared value, and keep both subjects of
    # the contract — the complete network and ridden routes — on that one
    # epsilon. A new third simplifier is review-worthy rather than something
    # this textual gate should silently bless.
    grep -q '\* RailStyle\.simplifyTolerance' \
        "$here/RailMap/RailMapView.swift" \
        || fail "RailMapView no longer derives epsilon from RailStyle.simplifyTolerance"
    renderer_simplifiers=$(grep -c \
        'Geometry\.douglasPeuckerIndices(.*epsilonMeters: epsilon)' \
        "$here/RailMap/RailMapView.swift" || true)
    [ "$renderer_simplifiers" = 2 ] || fail \
        "expected network and ridden-route simplifiers to share epsilon; found $renderer_simplifiers"
    echo "  both renderers decimate to the same $js_tolerance pt"

    # The annotation layer is the map's, and only the map's.
    #
    # Its ten classes used to be `private` members of the coordinator, so the
    # compiler guaranteed no other file could reach them. Lifting them into
    # `RailMapAnnotations.swift` made them module-internal, because Swift has
    # no access level meaning "this file and one other" — so the guarantee has
    # to be restored here or it is simply gone. Comment lines are skipped: a
    # doc comment elsewhere may point AT one of these types, it just may not
    # use one.
    #
    # The allowed list is "the map's own files", and the map is three files
    # now: `MapPlaybackLayer` was lifted out of the coordinator, which is where
    # the playback trail's beads and head are built. Widening the list is
    # therefore not a relaxation — the contract is about which SUBSYSTEM may
    # name these classes, and adding a file the map itself owns keeps it exact.
    # Anything outside the map still fails, which is the whole point: a
    # statistics or editor screen reaching for `StationAnnotationView` is the
    # regression this guards.
    #
    # Rooted at $here, not at the shell's cwd: this block runs after
    # `cd "$here/RailKit"`, where `RailMap` does not exist. Written relative,
    # grep warned to stderr, the `|| true` ate the failure and the check
    # passed on an empty result no matter what the sources said — a check that
    # cannot fail, which is the same defect this file already fixed once for
    # the app-target warnings. Caught by audit; keep the path absolute.
    annotation_users=$(cd "$here" && grep -rnE \
        '\b(PlaybackAnnotation|PlaybackAnnotationView|StationAnnotation|RideStationAnnotation|RideLabelAnnotation|EndpointLabelAnnotation|StationAnnotationView|RideStationAnnotationView|RideLabelAnnotationView|EndpointLabelView)\b' \
        --include='*.swift' RailMap \
        | grep -vE '^RailMap/(RailMapAnnotations|RailMapView|MapPlaybackLayer)\.swift:' \
        | grep -vE ':[0-9]+: *//' || true)
    if [ -n "$annotation_users" ]; then
        echo "$annotation_users"
        fail "the map's annotation classes are named outside the map (lines above)"
    fi
    echo "  the annotation layer is used by the map and nothing else"

    # The five packages are WGS84 and must stay that way for the WebUI, but
    # Apple's Taiwan, Hong Kong, Macao and Korea basemaps are presented in GCJ-02.
    # Keep the datum correction
    # at the MapKit boundary and on every subject that can be drawn: network
    # lines, network stations and ridden routes. The latter keeps its WGS84
    # copy for statistics and the on-disk route cache, or fixing the picture
    # would silently break route classification and double-shift cached rides.
    datum_network_calls=$(grep -c 'AppleMapDatum\.display' \
        "$here/RailMap/RailNetworkStore.swift" || true)
    [ "$datum_network_calls" = 2 ] || fail \
        "expected Apple datum conversion on network lines and stations; found $datum_network_calls"
    grep -q 'self\.coordinates = AppleMapDatum\.display(coordinates, country: country)' \
        "$here/RailMap/RiddenRouteStore.swift" \
        || fail "ridden routes no longer enter MapKit through AppleMapDatum"
    grep -q 'coordinates: \$0\.sourceCoordinates\.map' \
        "$here/RailMap/RiddenRouteStore.swift" \
        || fail "route cache no longer preserves canonical WGS84 coordinates"
    grep -q 'lines: \[segment\.sourceCoordinates\]' \
        "$here/RailMap/RailMapView.swift" \
        || fail "ridden-line statistics no longer use canonical WGS84 coordinates"
    grep -q 'lines: \[segment\.sourceCoordinates\]' \
        "$here/RailMap/MileageStatisticsStore.swift" \
        || fail "mileage statistics no longer use canonical WGS84 coordinates"
    grep -q 'gcj02Countries: Set<String> = \["tw", "hk", "mo", "kr"\]' \
        "$here/RailMap/AppleMapDatum.swift" \
        || fail "Apple datum correction is no longer scoped to Taiwan, Hong Kong, Macao and Korea"
    echo "  Taiwan, Hong Kong, Macao and Korea enter Apple Maps in GCJ-02; shared data stays WGS84"

    # A station hands Apple Maps a PLACE, and every link to one is built in the
    # single tier that is tested.
    #
    # The card used to assemble `maps.apple.com/?ll=…&q=…` inline, which is a
    # dropped pin: it arrives at the other end with no exits, no platforms and
    # no name of its own. `StationPlaceLink` is where both links now come from
    # — `/place?place-id=` for a resolved station and the captioned pin for a
    # station no map service could answer for — and it is checked by
    # `StationPlaceLinkTests` against recorded live answers. A second builder
    # anywhere would be a link nothing tests, so there may not be one.
    #
    # Naming the host is not the same as building one, though: a file that
    # RECOGNISES `maps.apple.com` — to spot a pasted link, say — hands back no
    # `URL`, and the direction is the whole difference. So the allowance is a
    # rule rather than a list of files: any file other than the builder may
    # name the host, and none of them may assemble one.
    named=$(grep -rl 'maps\.apple\.com' --include='*.swift' \
        "$here/RailMap" "$here/RailKit/Sources" "$here/RailMapUITests" "$here/tools" \
        2>/dev/null | grep -v 'StationPlaceLink\.swift' || true)
    for file in $named; do
        # `URL` alone, not `URLComponents` — taking a link apart uses the
        # components too, but only a finished link is a `URL`. The second
        # half is the same rule from the other side: the host handed to
        # anything that assembles a link, however the result is spelled.
        # Comment lines are free to say either.
        built=$(grep -nE '(^|[^A-Za-z_])URL([^A-Za-z_]|$)|URL[A-Za-z]*\(.*maps\.apple\.com' \
            "$file" | grep -v '^[0-9]*: *//' || true)
        if [ -n "$built" ]; then
            echo "$file"
            echo "$built"
            fail "an Apple Maps link is built outside StationPlaceLink (lines above)"
        fi
    done

    # And the card actually resolves one. Both halves live in a SwiftUI body
    # with no test target underneath them, and dropping either silently
    # restores the pin: without the lookup there is no place, and without
    # `openInMaps()` on the resolved item the button re-opens a URL that Maps
    # has to resolve for a second time.
    # The lookup also carries the station's aliases, so its arguments are
    # intentionally formatted over several lines. Match the call rather than
    # requiring SwiftFormat to collapse it to one exact line.
    awk '
        /place = await StationPlaceStore\.shared\.place\(/ { in_call = 1 }
        in_call && /for: card[,)]/ { found = 1 }
        in_call && /\)/ { in_call = 0 }
        END { exit !found }
    ' "$here/RailMap/StationCardView.swift" \
        || fail "the station card no longer looks up its Apple Maps place"
    grep -q 'item.openInMaps()' "$here/RailMap/StationCardView.swift" \
        || fail "the station card no longer opens the resolved map item"
    echo "  every station link is built by StationPlaceLink, and the card resolves its place"
fi

if [ "$run_app" = 1 ] && [ "$run_swift" = 1 ]; then
    echo "== app ========================================================="
    cd "$here"
    xcodebuild -project RailMap.xcodeproj -scheme RailMap -sdk iphonesimulator \
        -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
        -derivedDataPath "$scratch-app" build >"$scratch-app.log" 2>&1 \
        || { grep -E 'error: ' "$scratch-app.log" | head -20; fail "app build"; }
    echo "  RailMap.app builds"

    # …and builds clean. The app target is two thirds of the Swift in this
    # repository and, until this check existed, the only tier whose warnings
    # nothing read: a Swift 6 actor-isolation warning sat in the screenshot
    # importer through a green gate. Scoped to RailMap for the reason the
    # package check is scoped — an SDK warning is not ours to fix.
    app_warnings=$(grep 'warning:' "$scratch-app.log" \
        | grep -E '/RailMap/' \
        | sort -u)
    if [ -n "$app_warnings" ]; then
        echo "$app_warnings"
        fail "warnings in the app target"
    fi
    echo "  no warnings in RailMap"

    # Every badge the branding tables name must resolve, in the built bundle,
    # to a file iOS can actually decode.
    #
    # "Resolves to a real file" is not enough, and believing it was is how a
    # quarter of the station popup's rows shipped wearing a colour swatch: 95
    # of the paths name an SVG, ImageIO has no SVG decoder on iOS, and
    # `UIImage(contentsOfFile:)` returned nil for every one of them. macOS
    # decodes SVG perfectly well, so nothing on the host could see it —
    # `sips`, Preview and Xcode all open the artwork. That is why the check
    # below is written against the *extension* rather than against a decoder:
    # a host-side decode test passes on exactly the files the device rejects.
    #
    # It applies the loader's own rule from OperatorBadge.image — strip the
    # leading slash, and append `.png` to an `.svg` — so it fails if the rule,
    # the rasterized companions or the copy phase drift apart.
    app_bundle="$scratch-app/Build/Products/Debug-iphonesimulator/RailMap.app"
    [ -d "$app_bundle" ] || fail "no built RailMap.app at $app_bundle"
    python3 - "$repo" "$app_bundle" <<'PY' || fail "badge artwork the device cannot decode (above)"
import os, re, sys

repo, bundle = sys.argv[1], sys.argv[2]
source = os.path.join(repo, "app", "public", "rail")

# What ImageIO decodes on iOS. SVG is decodable on macOS and not on iOS, which
# is the whole reason this list is spelled out rather than inferred from a
# host-side decode: a decode test passes on exactly the files the device
# rejects. Anything in the artwork directories that is not one of these and
# not an SVG with a companion is something the popup cannot draw.
DECODABLE = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic", ".bmp", ".tiff"}
ARTWORK = DECODABLE | {".svg"}


def resolve(relative):
    """OperatorBadge.image: an .svg is served by its rasterized companion."""
    return relative + ".png" if relative.endswith(".svg") else relative


# Every piece of artwork that ships must be loadable. Driven from the source
# tree rather than from the tables, so that art added without a companion is
# caught even before a line is pointed at it.
missing, undecodable = [], []
for family in ("logos", "line-logos", "operator-logos"):
    for directory, _, names in os.walk(os.path.join(source, family)):
        for name in names:
            full = os.path.join(directory, name)
            relative = os.path.relpath(full, source)
            if os.path.splitext(name)[1].lower() not in ARTWORK:
                continue  # README.md, logo-credits.json — not artwork
            resolved = resolve(relative)
            if os.path.splitext(resolved)[1].lower() not in DECODABLE:
                undecodable.append(relative)
            elif not os.path.isfile(os.path.join(bundle, "rail", resolved)):
                missing.append(resolved)

# And every answer the ported rule gives for the popup must land on one of
# them. `station-display.json` is the fixture that records what the C5 popup
# draws; `operator-branding.json` is not used here because it feeds the rule
# invented inputs — a `logo` field of `/rail/logos/anything.png` — to prove
# which branch wins, and those are not artwork that ships.
raw = open(os.path.join(repo, "port-fixtures", "station-display.json"), encoding="utf-8").read()
paths = sorted(set(re.findall(r'/rail/[^"\\ ]+?\.[A-Za-z0-9]+', raw)))
unresolved = [
    path for path in paths
    if not os.path.isfile(os.path.join(bundle, "rail", resolve(path.lstrip("/")[len("rail/"):])))
]

for relative in undecodable[:10]:
    print(f"  undecodable on iOS, no companion: {relative}")
for relative in missing[:10]:
    print(f"  artwork missing from the bundle: {relative}")
for path in unresolved[:10]:
    print(f"  popup badge path resolves to nothing: {path}")
if missing or undecodable or unresolved:
    print(f"  {len(undecodable)} undecodable, {len(missing)} missing, "
          f"{len(unresolved)} of {len(paths)} popup paths unresolved")
    sys.exit(1)
print(f"  {len(paths)} popup badge paths resolve to artwork iOS can decode")
PY

    # The app icon must survive the asset catalog, and must declare layers
    # that are actually there.
    #
    # The icon is an Icon Composer document — `RailMap/AppIcon.icon` — not an
    # `.appiconset`, so the system renders the Liquid Glass treatment and the
    # dark and mono appearances from the layers instead of the build shipping
    # a flat PNG per appearance. That moves the silent failures:
    #
    #   * An icon the target does not name — `ASSETCATALOG_COMPILER_APPICON_NAME`
    #     deleted, or the document moved out of the synchronized folder — still
    #     compiles, and the app just wears the grey placeholder.
    #   * A layer whose `image-name` names no file in `Assets/` also still
    #     compiles. The layer is simply absent, and the icon is missing its
    #     route, or its stations, with nothing said about it.
    #   * An `.appiconset` left behind under the same name is a second claim on
    #     `AppIcon`, and which one wins is not worth finding out on a device.
    #
    # There is deliberately no alpha check here. That rule was about the
    # 1024×1024 PNG an `.appiconset` handed to App Store validation; the
    # renditions actool generates from a `.icon` are RGBA by design.
    python3 - "$here" "$app_bundle" <<'PY' || fail "app icon (above)"
import json, os, plistlib, sys

source, bundle = sys.argv[1], sys.argv[2]
document = os.path.join(source, "RailMap", "AppIcon.icon")

problems = []

# The document compiled *and* the target claimed it. `CFBundleIconName` is
# written by the asset catalog compiler; its absence means the icon never
# reached the build.
info = plistlib.load(open(os.path.join(bundle, "Info.plist"), "rb"))
named = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {}).get("CFBundleIconName")
if named != "AppIcon":
    problems.append(f"the bundle names {named!r} as its icon, not 'AppIcon'")

# ...and it left renditions behind, which is the part `CFBundleIconName` alone
# does not prove.
renditions = [name for name in os.listdir(bundle)
              if name.startswith("AppIcon") and name.endswith(".png")]
if not renditions:
    problems.append("the bundle carries no AppIcon rendition")

stale = os.path.join(source, "RailMap", "Assets.xcassets", "AppIcon.appiconset")
if os.path.exists(stale):
    problems.append("AppIcon.appiconset is still present and competes with AppIcon.icon")

layers = []
try:
    composition = json.load(open(os.path.join(document, "icon.json"), encoding="utf-8"))
except (OSError, ValueError) as error:
    problems.append(f"AppIcon.icon/icon.json: {error}")
else:
    for group in composition.get("groups", []):
        layers.extend(group.get("layers", []))
    if not layers:
        problems.append("AppIcon.icon declares no layer")
    for layer in layers:
        image = layer.get("image-name")
        if not image:
            problems.append(f"layer {layer.get('name')!r}: names no image")
        elif not os.path.isfile(os.path.join(document, "Assets", image)):
            problems.append(f"{image}: declared by AppIcon.icon, not on disk")

for problem in problems:
    print(f"  {problem}")
if problems:
    sys.exit(1)
print(f"  the app icon composes {len(layers)} layers into "
      f"{len(renditions)} built renditions")
PY

    # Three behaviours the app target cannot unit-test, because they live in
    # SwiftUI view bodies with no test target underneath them. All three were
    # real regressions, and each is one deleted line away from coming back.

    # An edit that is not written to the library survives until the next
    # launch and no further. `ItineraryStore` holds the store in memory;
    # `RideLibrary` is what puts it on disk. Passport shipped with the first
    # half only, so the same edit was durable in Journeys and not in Passport.
    for file in $(grep -rl 'itineraries\.replace(\|itineraries\.rebuildRoute' \
        RailMap/ | grep -v 'ItineraryStore.swift'); do
        grep -q 'library\.save(' "$file" \
            || fail "$file commits an edit without persisting it"
    done
    echo "  every surface that edits a journey also persists it"

    # A store arriving from outside this app is placed in its region BEFORE it
    # is published, never corrected afterwards.
    #
    # An untagged ride is `Region.resolved`-as-Japanese: drawn against Japan's
    # package and solved against Japan's station table. The four non-Japanese
    # stores carry the operator's own station codes — `MLM-TAIPA-MLM-BARRA`,
    # `TYMC-A13`, `AEL-MTR-HOK` — which name no region on their face, so the
    # string rule cannot place them and only `RegionCodeIndex` can. That pass
    # used to run at launch only, so loading the Macanese sample asked Japan's
    # solver for 媽閣 and the card said 無法繪製路線 until the app was next
    # launched. Three doors admit a store — `load`, `merge`, `replaceAll`. A
    # fourth is not forbidden; it just has to place its rides too, and be
    # counted here.
    doors=$(grep -c 'await MergedStore.regionTagged(' RailMap/ItineraryStore.swift || true)
    [ "$doors" = 3 ] || fail \
        "expected 3 doors that place an incoming store in its region; found $doors"
    echo "  a sample loads into its own region on the launch that loads it"

    # The route reload key must be the whole record, not a projection of it.
    #
    # `DrawnRide` bakes in a journey's colour, visibility, stops and day span,
    # and solves its geometry from the stops, sections and policy. A key built
    # from some of those fields reports "nothing changed" for an edit that
    # changed the rest, and the map then draws the previous line — in the
    # previous colour, along the previous path — under the record the list is
    # already showing. `[Train]` is Equatable; anything narrower is a guess.
    grep -q 'private var routeLoadKey: \[Train\]? { itineraries.loaded?.trains }' \
        RailMap/AppShell.swift \
        || fail "routeLoadKey no longer keys the route reload on the whole record"
    echo "  editing a journey reloads what the map draws of it"

    # A journey nobody has confirmed riding is not a kilometre.
    #
    # §5.3's passport reports what the reader SAYS they rode. The line is
    # drawn in four places — the statistics load, the coverage map's scope,
    # the cards that count 旅程數 / 出行日 / 停站數, and the journey log under
    # them — and all four have to draw it identically or the screen
    # contradicts itself: a log listing a trip the total above it did not
    # count, or a map drawing a line the percentage beside it excludes. One
    # rule (`RideLedger.hasBeenRidden`), named in all four.
    for file in AppShell.swift ContentView.swift StatisticsView.swift \
        PassportWorkspaceView.swift; do
        grep -q 'RideLedger\.hasBeenRidden(' "RailMap/$file" \
            || fail "RailMap/$file scopes the passport without excluding what is not confirmed"
    done
    echo "  the passport counts only journeys the record says were ridden"

    # And that rule has no clock in it.
    #
    # This is the whole point of the type, and it is the one property a
    # reviewer cannot see by reading a call site: the app knows what day it is
    # in five regions, the record carries a date, and comparing the two is one
    # line away at all times. It would be wrong. A date is a plan — a trip
    # written down and then cancelled, a booking moved, a ticket never used —
    # and an app that counted it would be writing kilometres into somebody's
    # passport for track they never rode, on a day they did not open it.
    #
    # So the rule may name no clock, no calendar and no today. `RegionClock`
    # still exists and is still right; it answers what is UPCOMING (§5.1),
    # which is a question about the calendar and changes no record.
    clocked=$(grep -nE 'Date\(|RegionClock|Calendar|today|isUpcoming|hasPassed|isTodayOrEarlier' \
        RailKit/Sources/RailPresentation/RideLedger.swift \
        | grep -vE ':[0-9]+: *(///|//)' || true)
    if [ -n "$clocked" ]; then
        echo "$clocked"
        fail "RideLedger consulted a clock (lines above); what is counted is a stated fact"
    fi
    echo "  what the passport counts is a stated fact, not a date"

    # The statistics decide whether they have work to do BEFORE they take the
    # numbers off the screen.
    #
    # The shell re-keys this load on the whole record of every journey, which
    # is deliberate and correct — a key made of fewer fields reports "nothing
    # changed" for an edit that changed everything. The cost is that renaming
    # or recolouring a journey arrives here as a reload, and a reload re-reads
    # a 377,620-edge index and re-walks every vertex of every ride while the
    # figures are replaced by a progress stage. `Fingerprint` is what makes
    # that free; a guard placed after `state = .loading` would still blank the
    # screen for work it then declines to do.
    awk '/func load\(countries:/ { inside = 1 }
         inside && /guard fingerprint != servedFingerprint/ { guarded = 1 }
         inside && /state = \.loading/ && !seen { seen = 1; ok = guarded }
         END { exit !ok }' RailMap/MileageStatisticsStore.swift \
        || fail "the statistics reload no longer fingerprints its inputs before clearing the screen"
    echo "  unchanged statistics inputs are not recalculated"

    # One PlaybackController serves the whole app (§5.3.5 gives Passport its
    # own replay entry point over the same transport). A TabView calls
    # onDisappear on every tab switch, so stopping playback there means a run
    # started in Journeys dies the moment the reader opens Passport to watch
    # it. Stopping is a thing the reader asks for, from the transport controls.
    if awk '/\.onDisappear \{/ { n = 10 }
            n && /playback\.stop\(\)/ { print FILENAME ":" FNR; found = 1 }
            n { n-- }
            END { exit !found }' RailMap/*.swift; then
        fail "a workspace stops the shared playback when its tab goes off screen"
    fi
    echo "  playback survives a tab switch"

    # A display-link frame must not tear down playback's MapKit object graph.
    # Finished trail pieces and station annotations are stable; only the short
    # unfinished head segment is replaced, and the head annotation moves by
    # changing its coordinate. The previous renderer removed and recreated
    # every overlay and annotation at 60 Hz while the main thread also moved
    # the camera.
    # These three read `MapPlaybackLayer.swift`, which is where the chase went
    # when it was lifted out of the map coordinator. `seen` is why the first
    # one names the file's own function twice: pinned to `RailMapView.swift`,
    # this awk stopped finding `paintPlayback` the moment it moved and then
    # passed on an empty scan — the same "check that cannot fail" defect this
    # file has already had to fix twice. It now fails if the frame tears its
    # layer down OR if the function it scans is not there at all.
    if awk '/private func paint\(/ { inside = 1; seen = 1 }
            /private func syncDone\(/ { inside = 0 }
            inside && /clear\(on:/ { tears = 1 }
            END { exit !(tears || !seen) }' RailMap/MapPlaybackLayer.swift; then
        fail "the playback frame tears down its whole layer, or has moved out from under this check"
    fi
    # Singular, and no plural beside it: the frame replaces the one unfinished
    # stroke and nothing else. Matched by SHAPE rather than by the local's
    # name — the previous spelling pinned `removeOverlay(old)`, and a rename to
    # `previous` (correct in itself: the removal moved into a `defer` so the
    # replacement mounts first) silently broke the check.
    if ! awk '/private func updatePartial\(/ { inside = 1 }
              /private func updateAnnotations\(/ { inside = 0 }
              inside && /mapView\.removeOverlay\(/ { single = 1 }
              inside && /mapView\.removeOverlays\(/ { plural = 1 }
              END { exit !(single && !plural) }' RailMap/MapPlaybackLayer.swift; then
        fail "playback no longer limits frame replacement to its partial trail"
    fi
    grep -q 'annotation\.coordinate = head\.clLocation' RailMap/MapPlaybackLayer.swift \
        || fail "playback no longer moves its retained head annotation in place"
    echo "  playback frames retain completed overlays and annotations"

    # The chase owns the camera at display-link cadence. Network LOD still
    # restyles continuously, but rebuilding its complete MapKit object graph
    # waits until playback releases the camera. Basemap opacity is likewise a
    # one-polygon renderer update, not a network invalidation.
    grep -q 'if playbackLayer\.lastSnapshot != nil {' RailMap/RailMapView.swift \
        || fail "playback camera changes are no longer isolated from network rebuilds"
    grep -q 'if basemapChanged { updateBasemapVeil(on: mapView) }' \
        RailMap/RailMapView.swift \
        || fail "basemap opacity once again invalidates the complete map"
    echo "  playback camera and basemap opacity use narrow MapKit invalidation"

    # A region's package is opened and JSON-scanned ONCE, wherever it is read.
    #
    # The compact rows and the per-line topology are separate contracts with
    # separate decoders, so asking each of them for itself is the natural thing
    # to write — and it read jp-2025.json's 9.1 MB twice and ran the scanner
    # over it twice, for two values that come off the same rows. The two
    # callers regress independently: the network store pays it for five regions
    # at launch, the route solver pays it again on every route cache miss.
    # `DisplayParts.LoadedPackage` takes both halves off one decoder;
    # `byLineID(contentsOf:)` stays in RailCore for ports outside this app.
    if grep -rln 'LineTopology\.byLineID(contentsOf:\|CompactPackage\.load(contentsOf:' \
        --include='*.swift' RailMap; then
        fail "an app-side caller reads a package twice instead of using LoadedPackage"
    fi
    echo "  every package read in the app is single-pass"

    # A cold route lookup must not re-read a whole dataset per journey.
    #
    # The dataset search used to decode every part in a manifest before reading
    # the train id it had just paid for, so one uncached journey cost all 201
    # parts of the Japanese sample and the next one cost them again. The id to
    # part mapping is built once per dataset, and the full part decode — the
    # one that materialises coordinates — is reachable only through it.
    grep -q 'try await DatasetPartIndex\.shared\.parts(in: dataset)' \
        RailMap/RiddenRouteStore.swift \
        || fail "the dataset search no longer goes through the per-dataset part index"
    [ "$(grep -c 'JSONDecoder()\.decode(Part\.self' RailMap/RiddenRouteStore.swift)" = 1 ] \
        || fail "a second full precomputed-part decode can bypass the part index"
    echo "  a dataset is scanned once, not once per journey"

    # The route cache sweep is the only thing in this app that deletes
    # anything, and everything it can reach is re-solvable. That stays true for
    # exactly as long as its single removal is fed by an enumeration of the
    # route cache directory: a second remover here, or one pointed elsewhere,
    # is data loss rather than a re-solve.
    [ "$(grep -c 'removeItem(at:' RailMap/RiddenRouteStore.swift)" = 1 ] \
        || fail "the route store gained a second file removal"
    grep -q 'at: cacheDirectory(country: region.code),' RailMap/RiddenRouteStore.swift \
        || fail "the route cache sweep no longer enumerates only the route cache directory"
    grep -q 'guard !didSweepRouteCache else { return }' RailMap/RiddenRouteStore.swift \
        || fail "the route cache sweep is no longer bounded to once per launch"
    echo "  the route cache is swept once per launch, and only the route cache"

    # Every write belongs to the persistence actor, and they wait for each
    # other. A second writer on the main actor is a save nothing can order
    # against the queued ones, which is how an edit gets put back by a save
    # that started before it — and an actor alone does not answer this, because
    # Swift makes no promise about which enqueued message an actor takes next.
    if awk '/^actor RideStorage/ { inside = 1 }
            !inside && /\.write\(to:/ { print FILENAME ":" FNR; found = 1 }
            END { exit !found }' RailMap/RideLibrary.swift; then
        fail "RideLibrary writes a file outside RideStorage (lines above)"
    fi
    grep -q 'await previous?.value' RailMap/RideLibrary.swift \
        || fail "RideLibrary's file operations no longer wait for the one before them"

    # A store half-written because the app was killed mid-save is worse than no
    # store: the reader does not find out until the next launch. And both the
    # store and its backup are the web app's own export spelling — a second
    # spelling on disk under the first's name is a file nothing can import.
    if grep -n '\.write(to:' RailMap/RideLibrary.swift | grep -v 'options: \.atomic'; then
        fail "a store or backup file is written non-atomically (lines above)"
    fi
    [ "$(grep -c 'MergedStore.export(store)' RailMap/RideLibrary.swift)" = 2 ] \
        || fail "the saved store or its backup is no longer written canonically"
    echo "  saved stores are written in order, atomically, in the canonical spelling"

    # Grouping carries the same hazard the saves do: work started earlier can
    # finish later, and a superseded regroup publishing over a newer one leaves
    # the list showing a grouping the store no longer has.
    grep -q 'guard ticket == groupingTicket' RailMap/ItineraryStore.swift \
        || fail "a superseded regroup can publish over a newer one"

    # A duplicated id resolves to the FIRST journey carrying it — that journey
    # appears twice and the second never does. That is what the linear scan
    # this replaced answered with, so it is what the lookup has to answer with.
    grep -q 'uniquingKeysWith: { first, _ in first }' RailMap/ItineraryStore.swift \
        || fail "the date bridge no longer resolves a duplicate id to the first journey"
    echo "  journeys group in one pass, and the newest grouping is the one shown"

    # The working set has exactly ONE writer, and that writer counts itself.
    #
    # `load` is five suspension points long — two library calls, the store
    # read, the region tagging, the grouping — and everything the reader can do
    # in that window publishes a newer working set: folding in a sample,
    # committing an import, editing a journey. `load` used to resume
    # afterwards, overwrite it with the snapshot it had started from, and then
    # SAVE that snapshot on top, so a sample loaded seconds after launch was
    # gone from the list, from memory and from the file, with nothing said
    # about it.
    #
    # The generation guard is what stops that, and it only works while every
    # writer is counted. A second `store =` anywhere in this file is the bug
    # coming back, which is why this counts writers rather than reading them.
    # Counted over the whole line rather than anchored to its start: a second
    # writer arrives as `extension ItineraryStore { … store = s }` on one line
    # long before it arrives as a tidy statement, and an anchored pattern reads
    # that as clean. `let`/`var` bindings are declarations, not writes.
    store_writers=$(grep -oE '(let |var )?(self\.)?\bstore = ' \
        RailMap/ItineraryStore.swift | grep -vcE '^(let|var) ' || true)
    [ "$store_writers" = 1 ] || fail \
        "the working set has $store_writers writers; only publishWorkingSet may assign it"
    grep -q 'guard generation == storeGeneration else { return }' \
        RailMap/ItineraryStore.swift \
        || fail "a suspended load can once again publish over a newer working set"
    echo "  the working set has one writer, and a suspended load cannot overwrite a newer one"

    # The exporter films MapKit on the main actor and must keep doing it.
    # `layer.render(in:)` and every UIKit object the caption touches are
    # main-actor-only; moving them behind a queue yields a plausible film with
    # occasional corrupt frames, which is the worst kind of wrong. Swift 6
    # already refuses — CVBuffer is @_nonSendable and the adaptor is not
    # Sendable — so the only way back in is an escape hatch, and that is what
    # this looks for.
    if grep -nE 'DispatchQueue|nonisolated\(unsafe\)|@unchecked Sendable' \
        RailMap/PlaybackVideoExporter.swift; then
        fail "the video exporter left the main actor (lines above)"
    fi

    # And its per-frame path stays free of the allocations it used to rebuild
    # sixty times a second, on the same actor the playback renderer is moving
    # the camera on. Each of these belongs to the run, not to the frame.
    if awk '/private func append\(/ { inside = 1 }
            /private func captionLayout\(/ { inside = 0 }
            inside && /CGColorSpaceCreateDeviceRGB|UIFont\.systemFont|NSMutableParagraphStyle|UIColor\(railHex:/ \
                { print FILENAME ":" FNR ": " $0; found = 1 }
            END { exit !found }' RailMap/PlaybackVideoExporter.swift; then
        fail "the video exporter rebuilds frame-invariant state per frame (above)"
    fi

    # Skipping frames the writer cannot take is what bounds the exporter's
    # memory. Without it a slow encoder is answered by holding every frame.
    grep -q 'input\.isReadyForMoreMediaData' RailMap/PlaybackVideoExporter.swift \
        || fail "the video exporter no longer skips frames the writer cannot take"
    echo "  the video exporter stays on the main actor and allocates per run"
fi

echo "OK"
