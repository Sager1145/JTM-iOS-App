import Foundation
import MapKit
import RailCore
import SwiftUI

/// Loads a country's rail package out of the app bundle and turns it into
/// something the map can draw.
///
/// The decoding and the interval geometry both come from `RailCore`, which is
/// the point: this type contains no geometry of its own, so there is nothing
/// here that could disagree with the web app without a fixture catching it.
@MainActor
@Observable
final class RailNetworkStore {

    struct DrawnLine: Identifiable, Sendable {
        let id: String
        /// Which package this line came out of. Nothing about *drawing* needs
        /// it — every line draws in its own colour on its own geometry — but
        /// the statistics screen and the ride editor both scope by region, and
        /// re-deriving it from the id at every call site would be a rule
        /// spelled out in several places instead of one.
        let region: Region
        let name: String
        let nameRoma: String?
        /// The package's `operator` — `東日本旅客鉄道`, the official name and
        /// not the `JR東日本` a journey record carries. Held because the
        /// screenshot importer writes `preferred_operator_names`, which the
        /// solver reads in the package's own spelling, and because
        /// `OperatorBranding.companyLabel` needs the official name to produce
        /// the short one.
        let operatorName: String?
        let color: Color
        /// The operator's dark-mode colour where it publishes one. The
        /// packages have always carried this — `rail-network.js` reads
        /// `colorDark || color` — and the web app switches palettes with the
        /// theme. Ignoring it would have made dark mode a different map, not
        /// a darker one.
        let colorDark: Color
        /// Kept alongside the resolved `Color`s because the renderer batches
        /// lines by colour, and a hex string is a cheap, stable bucket key
        /// where `Color` is neither.
        let colorHex: String
        let colorDarkHex: String
        let rank: Int
        /// The zoom below which this line is not drawn — the web app's own
        /// rule, ported in `RailCore.Visibility`, not a performance knob.
        let minZoom: Int
        /// Complete visibility-group length, not this administrative piece's
        /// own length. The native low-zoom policy uses the unbucketed value so
        /// very long trunks can survive wider views than merely long lines.
        let visibilityLengthKm: Double
        /// The threshold this app actually uses: the ported rule plus the rank
        /// and finer wide-view length terms. See `NetworkLOD` — it is
        /// deliberately stricter than the web app at low zoom, and
        /// deliberately not in `RailCore`.
        let lodMinZoom: Double
        /// Bounding box in projected map space, computed once at decode time
        /// so the per-rebuild off-screen test is a rectangle intersection
        /// rather than a walk over 394,285 coordinates.
        let mapRect: MKMapRect
        /// One polyline per station-to-station interval, exactly as the web
        /// app draws them.
        let intervals: [[Coordinate]]
        var vertexCount: Int { intervals.reduce(0) { $0 + $1.count } }
    }

    struct DrawnStation: Identifiable, Sendable {
        let id: String
        /// The package this station came out of — the ride editor's picker is
        /// scoped to the region of the itinerary being edited, so that a
        /// Japanese ride cannot pick up a Korean platform.
        let region: Region
        /// The line this platform belongs to. A station is per (line, place),
        /// so this is single-valued even at an interchange: 東京 arrives as
        /// nine platforms of five railways, each with its own dot and its own
        /// line. The map reads it to draw a dot only while its line is drawn.
        let lineID: String
        /// The package's own station-group code — the identity a ride's stop
        /// carries (`n02_station_code`), which is why the ride editor picks
        /// stations by it rather than by name.
        let stationCode: String
        let name: String
        let nameRoma: String
        let coordinate: Coordinate
        let colorHex: String
        /// The web app's own threshold for this dot, in MapLibre's zoom — the
        /// line's for a terminal, the denser spacing-based one for an
        /// intermediate stop.
        let minZoom: Int
        /// The threshold this app draws by, in **this app's** zoom: the one
        /// above, raised to the line's own if the line appears later. See
        /// `NetworkLOD` — a dot may not precede the rail it sits on.
        let lodMinZoom: Double
        let isTerminal: Bool
        let showsLabel: Bool
        let popup: StationDisplay.PopupModel
    }

    /// What one region's package cost and contributed, so the diagnostics
    /// panel reports measurements rather than an estimate.
    struct RegionLoad: Identifiable, Sendable {
        var region: Region
        var lineCount: Int
        var stationCount: Int
        var elapsed: Duration
        var id: String { region.rawValue }
    }

    enum LoadState {
        case idle
        /// Regions still being decoded. The map draws what has already
        /// arrived: the packages differ by three orders of magnitude in size,
        /// so waiting for Japan before showing Macao would hide four networks
        /// behind the slowest one.
        case loading(pending: [Region])
        case loaded(regions: [RegionLoad], failures: [RegionFailure], elapsed: Duration)
    }

    struct RegionFailure: Identifiable, Sendable {
        var region: Region
        var message: String
        var id: String { region.rawValue }
    }

    private(set) var state: LoadState = .idle
    private(set) var lines: [DrawnLine] = []
    private(set) var stations: [DrawnStation] = []
    /// Which mark each railway wears, for the surfaces that hold a recorded
    /// journey rather than a network line — see ``RouteBadgeIndex``.
    ///
    /// Observed like the other two, and published well before them: a region
    /// hands this over as soon as its package is parsed rather than when its
    /// geometry is finished, which is the difference between a journeys list
    /// that settles on its route symbols in a moment and one that wears
    /// company marks for several seconds first.
    private(set) var badges = RouteBadgeIndex()

    /// One region's badges, taken as soon as that region has them.
    ///
    /// First writer wins inside ``RouteBadgeIndex/merge(_:)``, and the regions
    /// arrive in whatever order they parse, so a key two packages share
    /// resolves to whichever landed first. No key is shared today — every one
    /// of them begins with the region's own code.
    private func adopt(_ regionBadges: RouteBadgeIndex) {
        badges.merge(regionBadges)
    }

    /// Every region drawn at once — but decoded only when one is needed.
    ///
    /// The web app loads one package because it has a region switch; this app
    /// has none, so all five are merged into one field of lines and one of
    /// stations. Nothing downstream needs to know a region boundary exists —
    /// `NetworkLOD` culls by zoom and by the visible rect, which is a rule
    /// about what is on screen rather than about which country it is in.
    ///
    /// What this does NOT do any more is decode all five at launch. Measured
    /// over the shipped packages, a region's decode is a parse and then a
    /// geometry pass, and the geometry is almost all of it:
    ///
    ///     jp  9.3 MB   parse 280 ms   geometry 1744 ms
    ///     kr  845 KB   parse  20 ms   geometry  122 ms
    ///     tw  480 KB   parse  13 ms   geometry  112 ms
    ///
    /// and the map opens with its network layer OFF, so on a launch where the
    /// reader never turns it on, none of that geometry is ever drawn. Two
    /// phases, then. Every region is INDEXED at launch — read far enough to
    /// answer which mark each of its railways wears, which is the line
    /// attributes and no geometry at all (``index(region:)``) and is what a
    /// journeys list is waiting for. A region's geometry is decoded when
    /// something asks for it, through ``ensure(_:)``.
    ///
    /// A region that is asked for is read a second time, and that is the
    /// deliberate trade: holding seven parsed packages alive to save it would
    /// be holding 394,285 coordinates for countries the reader may never pan
    /// to, to save one background read in the one case where they do.
    ///
    /// ## The two large regions are indexed after the five compact ones
    ///
    /// Not throttling for its own sake — it is what makes the phase useful to
    /// the reader it is for. The five compact packages come to 3 MB together
    /// and Japan alone is 9.3 MB, so a task group holding all seven puts
    /// Macao's 8 KB in a queue behind the two files that take an order of
    /// magnitude longer than the rest of the app's launch. A reader whose
    /// journeys are Taiwanese then waits on Japan and the United States for
    /// marks that Taiwan's own package could have supplied in 12 ms.
    ///
    /// Compact first and concurrently, large after and concurrently with each
    /// other: the ONLY thing the second phase can delay is a badge for a
    /// journey in Japan or the United States, and it is the phase that has to
    /// read 16 MB to produce one. See ``Region/DataWeight``.
    func loadAll() {
        if isIndexing { return }
        isIndexing = true
        lines = []
        stations = []
        badges = RouteBadgeIndex()
        indexed = []
        requested = []
        decoding = []
        loads = []
        failures = []
        pending = []
        state = .idle
        // The complete network is context and starts hidden; route restoration
        // and interaction work should outrank reading seven national packages.
        Task(priority: .utility) {
            await indexRegions(Region.ordered(.compact))
            await indexRegions(Region.ordered(.large))
            isIndexing = false
            // Anything asked for while the indexes were still being built. The
            // ask is recorded rather than acted on during indexing, so that a
            // reader who turns the network on immediately does not have the
            // geometry competing with the indexes every other screen wants.
            for region in Region.ordered where requested.contains(region) {
                decodeGeometry(region)
            }
        }
    }

    /// Index one weight class, concurrently within it.
    ///
    /// Every region's badges are adopted as that region's read finishes rather
    /// than when the class does, so a journeys list settles country by country
    /// instead of in one step at the end.
    private func indexRegions(_ regions: [Region]) async {
        guard !regions.isEmpty else { return }
        await withTaskGroup(of: (Region, RouteBadgeIndex?).self) { group in
            for region in regions {
                group.addTask { (region, try? await Self.index(region: region)) }
            }
            for await (region, index) in group {
                guard let index else { continue }
                adopt(index)
                indexed.insert(region)
            }
        }
    }

    /// Decode one region's geometry, if it has not been asked for already.
    ///
    /// Idempotent and cheap to call from a render path: the second and every
    /// later call for a region is a set lookup. Whoever needs a region's lines
    /// or stations is the one that knows it needs them, so the ask lives at
    /// the point of need rather than in a launch sequence that has to guess.
    func ensure(_ region: Region) {
        guard requested.insert(region).inserted else { return }
        // While the indexes are being built the ask is only recorded; the
        // indexing task drains `requested` when it finishes.
        if !isIndexing { decodeGeometry(region) }
    }

    /// Every region whose network could be on screen in `rect`.
    ///
    /// `Region.networkExtent` is a constant, so this answers without having
    /// decoded anything — which is the whole point: the map can say which
    /// countries it is looking at before any of them has been read.
    func ensure(regionsIntersecting rect: MKMapRect) {
        for region in Region.ordered where Self.mapRect(of: region).intersects(rect) {
            ensure(region)
        }
    }

    // There is deliberately no `ensureAll()`.
    //
    // There was, and its one caller was the statistics screen, on the belief
    // that a coverage figure needs the drawn network. It does not: coverage is
    // a fraction of `Statistics.EdgeIndex.totalKm`, which is built from
    // `rail-sections*.json` by `EdgeIndexCache` and never touches this store.
    // What the call actually paid for was a camera rect, which
    // `Region.networkExtent` answers as a constant — so opening Passport
    // decoded seven packages' geometry, the most expensive thing this type
    // does, for a bounding box that is written down.
    //
    // Every region at once is not a want any surface has. Ask for the one you
    // need, or for the ones on screen.

    private func decodeGeometry(_ region: Region) {
        guard decoding.insert(region).inserted else { return }
        pending.append(region)
        state = .loading(pending: pending)
        let started = ContinuousClock.now
        Task(priority: .utility) {
            do {
                let decoded = try await Self.decode(region: region)
                lines.append(contentsOf: decoded.lines)
                stations.append(contentsOf: decoded.stations)
                loads.append(
                    RegionLoad(
                        region: region, lineCount: decoded.lines.count,
                        stationCount: decoded.stations.count,
                        elapsed: decoded.elapsed))
                loads.sort { Region.ordered.firstIndex(of: $0.region) ?? 0
                    < Region.ordered.firstIndex(of: $1.region) ?? 0 }
            } catch {
                // One missing package is not a dead map: the others still draw,
                // and the data screen names the one that did not. A
                // region-switching app could treat this as fatal; an
                // all-regions one cannot.
                failures.append(
                    RegionFailure(region: region, message: error.localizedDescription))
            }
            pending.removeAll { $0 == region }
            state = pending.isEmpty
                ? .loaded(
                    regions: loads, failures: failures,
                    elapsed: ContinuousClock.now - started)
                : .loading(pending: pending)
        }
    }

    /// The region's own extent, in the projected space the map tests against.
    private static func mapRect(of region: Region) -> MKMapRect {
        let extent = region.networkExtent
        let north = extent.center.latitude + extent.span.latitudeDelta / 2
        let south = extent.center.latitude - extent.span.latitudeDelta / 2
        let west = extent.center.longitude - extent.span.longitudeDelta / 2
        let east = extent.center.longitude + extent.span.longitudeDelta / 2
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: east))
        return MKMapRect(
            x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x), height: abs(bottomRight.y - topLeft.y))
    }

    @ObservationIgnored private var isIndexing = false
    @ObservationIgnored private var indexed: Set<Region> = []
    @ObservationIgnored private var requested: Set<Region> = []
    @ObservationIgnored private var decoding: Set<Region> = []
    @ObservationIgnored private var pending: [Region] = []
    @ObservationIgnored private var loads: [RegionLoad] = []
    @ObservationIgnored private var failures: [RegionFailure] = []

    /// The stations of one region only — the ride editor's picker, which is
    /// scoped to the region the itinerary being edited belongs to.
    /// One region's platforms, in store order.
    ///
    /// Grouped once per generation of ``stations`` rather than filtered per
    /// call, and that is not a micro-optimisation: the ride editor asks for
    /// this from inside a `NavigationLink`'s destination, which SwiftUI builds
    /// on every body evaluation of the stop editor — so a reader typing a
    /// station name was running a pass over all ~20,000 platforms of five
    /// countries per character. Grouping preserves relative order, so the
    /// answer is the one `filter` gave.
    func stations(in region: Region) -> [DrawnStation] {
        // The ride editor's picker is the only caller, and it is a surface
        // that exists precisely because the reader wants this region — so the
        // ask belongs here rather than in whoever presented the editor.
        ensure(region)
        if let stationsByRegion, ArrayGeneration.same(stationsByRegion.of, stations) {
            return stationsByRegion.grouped[region] ?? []
        }
        var grouped: [Region: [DrawnStation]] = [:]
        for station in stations { grouped[station.region, default: []].append(station) }
        stationsByRegion = (stations, grouped)
        return grouped[region] ?? []
    }

    /// The grouping above, with the generation it was taken from.
    @ObservationIgnored private var stationsByRegion:
        (of: [DrawnStation], grouped: [Region: [DrawnStation]])?

    private struct Decoded: Sendable {
        var lines: [DrawnLine]
        var stations: [DrawnStation]
        var elapsed: Duration
    }

    /// Decoding a national package is tens of thousands of coordinates, so it
    /// is `nonisolated` — it runs off the main actor and the main actor only
    /// sees the finished value. Marked `async` rather than dispatched by hand
    /// because that is what lets the compiler check the hand-off instead of
    /// trusting it.
    /// Phase one: which mark each of a region's railways wears.
    ///
    /// The line ATTRIBUTES and nothing else. The index reads six strings per
    /// railway and not one coordinate, so it goes through
    /// `CompactPackage.Headers` — one scan of the same file that stops at the
    /// geometry instead of materialising it. Measured on the shipped packages
    /// that is 234.6 ms → 29.4 ms for Japan and 138.8 ms → 17.2 ms for the
    /// United States, and across all seven regions the launch index falls from
    /// ~454 ms to ~57 ms of host time.
    ///
    /// This is not the second decoder `verify.sh` refuses. That contract is
    /// about reading one file TWICE for two halves of one answer, which is why
    /// anything needing geometry still goes through
    /// `DisplayParts.LoadedPackage`; this reads it once, for less.
    private nonisolated static func index(region: Region) async throws -> RouteBadgeIndex {
        let interval = RailSignpost.data.begin("data.package.index")
        defer { RailSignpost.data.end("data.package.index", interval) }
        guard let url = Bundle.main.url(
            forResource: region.packageResource, withExtension: "json")
        else { throw LoadError.missingResource(region.code) }
        return RouteBadgeIndex(
            region: region, headers: try CompactPackage.Headers.load(contentsOf: url))
    }

    private nonisolated static func decode(region: Region) async throws -> Decoded {
        let interval = RailSignpost.data.begin("data.package.decode")
        defer { RailSignpost.data.end("data.package.decode", interval) }
        let started = ContinuousClock.now
        guard let url = Bundle.main.url(
            forResource: region.packageResource, withExtension: "json")
        else { throw LoadError.missingResource(region.code) }

        // Both halves of the package come off one read and one parse. Asking
        // the compact decoder and the topology decoder separately opened the
        // same file twice and scanned it twice — 9.1 MB apiece for Japan, with
        // all five regions decoding concurrently at launch.
        let loaded = try DisplayParts.LoadedPackage.load(contentsOf: url)
        let package = loaded.package
        let topologies = loaded.topologyByLineID
        let visibilityLengthByLineId = Visibility.groupLengthByLineId(package)
        let minZoomByLineId = visibilityLengthByLineId.mapValues {
            Visibility.minZoomForLength(totalKm: $0)
        }
        // The native threshold for every line, in MapLibre's zoom, computed
        // once here because both halves of the network read it: the line, to
        // know when it is drawn, and every station on it, which may not
        // precede it. `uniquingKeysWith` rather than `uniqueKeysWithValues`
        // for the reason `StationDisplay.Network` gives — a duplicate line id
        // is a package question, and the last writer wins there too.
        let lodMinZoomByLineId = Dictionary(
            package.lines.map { line in
                (
                    line.id,
                    NetworkLOD.minZoomMapLibre(
                        portedMinZoom: minZoomByLineId[line.id] ?? 0,
                        rank: line.rank,
                        visibilityLengthKm: visibilityLengthByLineId[line.id] ?? 0)
                )
            }, uniquingKeysWith: { _, last in last })
        let lines = package.lines.map { line in
            let sourceIntervals = DisplayParts.parts(
                for: line, topology: topologies[line.id] ?? .init())
            // `DisplayParts` stays byte-for-byte WGS84-compatible with the
            // WebUI. Only the coordinates handed to MapKit are shifted for
            // regions served by Apple's GCJ-02 basemap.
            let intervals = sourceIntervals.map {
                AppleMapDatum.display($0, country: region.code)
            }
            // The line's own length is deliberately NOT used for the LOD:
            // `minZoomByLineId` answers with the length of the line's
            // visibility GROUP, so every administrative piece of one physical
            // railway appears and vanishes together.
            let portedMinZoom = minZoomByLineId[line.id] ?? 0
            let visibilityLengthKm = visibilityLengthByLineId[line.id] ?? 0
            return DrawnLine(
                id: line.id,
                region: region,
                name: line.name,
                nameRoma: line.nameRoma,
                operatorName: line.operator,
                color: Color(hex: line.color) ?? .accentColor,
                colorDark: Color(hex: line.colorDark ?? line.color) ?? .accentColor,
                colorHex: (line.color ?? "#7a7a7a").lowercased(),
                colorDarkHex: (line.colorDark ?? line.color ?? "#7a7a7a").lowercased(),
                rank: line.rank,
                minZoom: portedMinZoom,
                visibilityLengthKm: visibilityLengthKm,
                lodMinZoom: NetworkLOD.minZoom(
                    portedMinZoom: portedMinZoom,
                    rank: line.rank,
                    visibilityLengthKm: visibilityLengthKm),
                mapRect: Self.boundingRect(of: intervals),
                intervals: intervals
            )
        }
        // The badge set is passed, and until now it was not.
        //
        // `packageLogoLineIDs` defaults to empty, the only caller that ever
        // supplied it was a parity test, and `line.logo` was therefore nil for
        // every railway on device. That is the whole third leg of
        // `OperatorBranding.logoForLine` — the package's own per-line art —
        // never firing: 382 Japanese railways, the 350 files
        // `copy-rail-packages.sh` ships and the reason 銀座線 wore the 東京メトロ
        // company mark instead of its orange G.
        // `loopLineIDs` had the identical defect and the identical cause: it
        // defaults to empty, no caller but a parity test ever supplied it, and
        // a circular railway was therefore drawn with a terminus at each end
        // of a line that has neither.
        let stationNetwork = StationDisplay.Network(
            package: package,
            loopLineIDs: Set(package.lines.filter(\.isLoop).map(\.id)),
            packageLogoLineIDs: Set(package.lines.filter(\.hasLogo).map(\.id)))
        func lineThreshold(under station: StationDisplay.Network.Station) -> Int {
            lodMinZoomByLineId[stationNetwork.lines[station.lineIndex].lineID] ?? 0
        }
        // Elected on the thresholds THIS app draws by, not the package's.
        //
        // The election hands a complex's name to whichever of its platforms
        // appears first, so that a complex on screen always has the named one
        // among its visible platforms. That holds only while the election and
        // the renderer use the same thresholds, and since `NetworkLOD` they do
        // not: 高崎 elects on its 上越線 platform, which this app does not draw
        // at app zoom 5, while its 信越線 and 北陸新幹線 platforms are drawn —
        // so the ported election would leave 高崎 standing there as two bare
        // dots. Two complexes are in that position at app zoom 5 and nine more
        // at app zoom 7. Electing on the thresholds actually in force moves
        // the name to a platform that is drawn. Exactly the same 9,021
        // complexes are named across jp either way — 39 of the names change
        // which PLATFORM of their complex holds them, and no complex gains or
        // loses a name (tw 3, hk 1, mo 0, kr 3).
        let labelWinners = Set(
            StationDisplay.stationLabelWinners(stationNetwork) { station in
                NetworkLOD.stationMinZoomMapLibre(
                    portedMinZoom: station.minZoom,
                    lineMinZoomMapLibre: lineThreshold(under: station))
            })
        let stations = stationNetwork.stations.enumerated().map { index, station in
            let line = stationNetwork.lines[station.lineIndex]
            return DrawnStation(
                id: station.stationID, region: region,
                lineID: line.lineID,
                stationCode: station.stationGroupID,
                name: station.name,
                nameRoma: station.nameRoma ?? "",
                coordinate: AppleMapDatum.display(station.coordinate, country: region.code),
                colorHex: line.color, minZoom: station.minZoom,
                lodMinZoom: NetworkLOD.stationMinZoom(
                    portedMinZoom: station.minZoom,
                    lineMinZoomMapLibre: lineThreshold(under: station)),
                isTerminal: station.isTerminal, showsLabel: labelWinners.contains(index),
                popup: StationDisplay.buildPopupModel(
                    network: stationNetwork, stationID: station.stationID))
        }
        return Decoded(
            lines: lines, stations: stations, elapsed: ContinuousClock.now - started)
    }

    /// Union of every vertex, in projected map space.
    ///
    /// `MKMapRect` rather than a latitude/longitude box because the off-screen
    /// test compares against `MKMapView.visibleMapRect`, and converting one
    /// rect per line per rebuild would undo the point of precomputing it.
    private nonisolated static func boundingRect(of intervals: [[Coordinate]]) -> MKMapRect {
        var rect = MKMapRect.null
        for interval in intervals {
            for point in interval {
                let mapPoint = MKMapPoint(
                    CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon))
                rect = rect.union(MKMapRect(origin: mapPoint, size: MKMapSize(width: 0, height: 0)))
            }
        }
        return rect
    }

    enum LoadError: LocalizedError {
        case missingResource(String)

        var errorDescription: String? {
            switch self {
            case .missingResource(let country):
                return """
                    \(country)-2025.json is not in the app bundle. \
                    Run ios/copy-rail-packages.sh — the packages are copied from \
                    app/public/rail rather than committed twice.
                    """
            }
        }
    }
}
