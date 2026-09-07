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
        /// Identity of this immutable decoded content. Copies retain it; a
        /// re-decoded line gets a new one even if its public ID is unchanged.
        let contentID = UUID()
        /// The canonical package line id. A reviewed screen-space lane can
        /// give one railway several entries, so `id` identifies the drawn
        /// stroke while this identifies the railway beneath stations, badges
        /// and LOD policy.
        let lineID: String
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
        /// Signed screen-space corridor lane. Zero keeps canonical geometry;
        /// fractional values form the short entry/exit ramps.
        let lane: Double
        /// A continuous stroke (North America): `intervals` is one uncut
        /// chain, drawn as ONE polyline with the lane offset and corner
        /// rounding baked in on device from `laneRows` (metres along the
        /// chain) — see `RailCore.ContinuousStroke`.
        let continuous: Bool
        let laneRows: [ContinuousStroke.LaneRow]
        let totalMetres: Double
        /// Corridor follows: over `from…to` this chain is drawn from the
        /// named stroke's alignment (`DrawnLine.id` of the canonical chain).
        let follows: [StrokeFollow]
        /// Spans this chain bridges rather than cuts (see `WithheldSpan`).
        /// Always empty for a non-continuous line — the alignment gate still
        /// splits those, exactly as before.
        let withheld: [WithheldSpan]
        /// Family-collapse windows along this chain (see `FamilyWindow`).
        /// Always empty for a non-continuous line.
        let familyWindows: [FamilyWindow]
        /// Bounding box in projected map space, computed once at decode time
        /// so the per-rebuild off-screen test is a rectangle intersection
        /// rather than a walk over 394,285 coordinates.
        let mapRect: MKMapRect
        /// One polyline per station-to-station interval, exactly as the web
        /// app draws them.
        let intervals: [[Coordinate]]
        /// The same off-screen test one level down, and the reason a whole
        /// railway can be resident without a whole railway being drawn.
        ///
        /// The line's own rect answers "is any of this near the camera". Over
        /// a 4,000 km corridor that is true from Vancouver to Halifax, and the
        /// build would then decimate every interval of it to draw the six that
        /// are on screen — which is exactly what tiling used to avoid by
        /// cutting the railway up in the bundle instead. One rect per
        /// interval, computed here beside the geometry so it cannot fall out
        /// of step with it, turns that into the same cheap rectangle test per
        /// stroke. `NetworkLOD`'s own note measured the lever at a city view:
        /// 22,185 drawn vertices to 2,460.
        let intervalRects: [MKMapRect]
        var vertexCount: Int { intervals.reduce(0) { $0 + $1.count } }

        /// The rects are derived rather than passed, because the one thing
        /// that must never happen to them is disagreeing with `intervals`.
        init(
            id: String, lineID: String, region: Region, name: String,
            nameRoma: String?, operatorName: String?, color: Color,
            colorDark: Color, colorHex: String, colorDarkHex: String,
            rank: Int, minZoom: Int, visibilityLengthKm: Double,
            lodMinZoom: Double, lane: Double, intervals: [[Coordinate]],
            continuous: Bool = false,
            laneRows: [ContinuousStroke.LaneRow] = [],
            totalMetres: Double = 0,
            follows: [StrokeFollow] = [],
            withheld: [WithheldSpan] = [],
            familyWindows: [FamilyWindow] = []
        ) {
            self.id = id
            self.lineID = lineID
            self.region = region
            self.name = name
            self.nameRoma = nameRoma
            self.operatorName = operatorName
            self.color = color
            self.colorDark = colorDark
            self.colorHex = colorHex
            self.colorDarkHex = colorDarkHex
            self.rank = rank
            self.minZoom = minZoom
            self.visibilityLengthKm = visibilityLengthKm
            self.lodMinZoom = lodMinZoom
            self.lane = lane
            self.continuous = continuous
            self.laneRows = laneRows
            self.totalMetres = totalMetres
            self.follows = follows
            self.withheld = withheld
            self.familyWindows = familyWindows
            self.intervals = intervals
            let rects = intervals.map(Self.boundingRect(of:))
            self.intervalRects = rects
            self.mapRect = rects.reduce(MKMapRect.null) { $0.union($1) }
        }

        /// Union of one interval's vertices, in projected map space.
        ///
        /// `MKMapRect` rather than a latitude/longitude box because the
        /// off-screen test compares against `MKMapView.visibleMapRect`, and
        /// converting one rect per interval per rebuild would undo the point
        /// of precomputing it.
        private static func boundingRect(of interval: [Coordinate]) -> MKMapRect {
            var rect = MKMapRect.null
            for point in interval {
                let mapPoint = MKMapPoint(
                    CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon))
                rect = rect.union(
                    MKMapRect(origin: mapPoint, size: MKMapSize(width: 0, height: 0)))
            }
            return rect
        }
    }

    struct DrawnStation: Identifiable, Sendable {
        let id: String
        let contentID = UUID()
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
        /// The line lane at this platform, plus its clockwise-from-north
        /// direction so the station bead follows the offset stroke.
        let lane: Double
        let laneBearing: Double?
        /// On a continuous-stroke line, the chain and vertex this platform
        /// sits on; its bead is that vertex's offset at every zoom.
        var slot: StrokeSlot? = nil
    }

    struct StrokeSlot: Sendable, Hashable {
        let chain: Int
        let anchor: Int
    }

    struct StrokeFollow: Sendable, Hashable {
        let from: Double
        let to: Double
        /// `DrawnLine.id` of the canonical chain (`lineKey#chain`).
        let canonicalID: String
        let canonicalFrom: Double
        let canonicalTo: Double
    }

    /// A span a continuous-stroke chain draws THROUGH rather than around: the
    /// alignment gate withheld it from the official-geometry comparison, but
    /// the geometry is real, so `displayPartsForLine`
    /// (`bridgeBlockedIntervals`) and this app's own `continuous_chains`
    /// (`build-display-network.py`) both bridge it instead of cutting the
    /// chain there. Metres, in the chain's own measure space — the same ruler
    /// `laneRows`/`totalMetres` use — so the renderer can slice it straight
    /// out of the already-built stroke the way a ride's own slice is cut.
    struct WithheldSpan: Sendable, Hashable {
        let from: Double
        let to: Double
    }

    /// A stretch this chain shares its stroke with a sibling railway of the
    /// same operator collapse (`na-render-groups.json`, `build-display-
    /// network.py`'s `chain_family_windows`). Metres, in the chain's own
    /// measure space — the same ruler `laneRows`/`totalMetres`/`withheld`
    /// use — sliced straight out of the already-built stroke the same way
    /// `WithheldSpan` is.
    ///
    /// `isLandlord` true: this chain draws the shared family stroke over the
    /// window, in `colorHex`/`colorDarkHex` (the group's own colour, resolved
    /// at load time from `RailDisplayNetworkFile.families` — see
    /// `prepareDisplayRegion`). `isLandlord` false (tenant): this chain's own
    /// stroke is withheld over the window; the chain is still built whole
    /// underneath, so a ride or playback can still slice it there.
    struct FamilyWindow: Sendable, Hashable {
        let from: Double
        let to: Double
        let isLandlord: Bool
        let groupID: String
        let colorHex: String
        let colorDarkHex: String
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
    /// Geometry currently resident for the map: the display network of every
    /// region the padded visible rect has reached, whole. Full-region `lines`
    /// and `stations` above remain available to explicit workflows such as the
    /// station editor, but are never fed to the complete-network layer.
    ///
    /// Resident is not the same as drawn. What bounds the frame is the
    /// renderer's cull — `NetworkLOD` by zoom and by rect, then the
    /// per-interval rect test in `RailMapView.rebuild` — and it is applied to
    /// continuous geometry, so a railway crossing the screen is one stroke
    /// rather than the run of abutting fragments the storage tiles produced.
    private(set) var mapLines: [DrawnLine] = []
    private(set) var mapStations: [DrawnStation] = []
    private(set) var activeRegionCount = 0
    private(set) var requestedRegionCount = 0
    private(set) var activeNetworkBytes = 0
    private(set) var networkFailure: String?
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
    /// A region that an editor or solver asks for is read a second time. The
    /// map itself never takes that path: it draws the display derivative,
    /// which carries the reviewed corridors and lanes and no topology at all,
    /// and it reads a country's only when the camera reaches it.
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
        mapLines = []
        mapStations = []
        activeRegionCount = 0
        requestedRegionCount = 0
        activeNetworkBytes = 0
        networkFailure = nil
        badges = RouteBadgeIndex()
        indexed = []
        requested = []
        decoding = []
        loads = []
        failures = []
        pending = []
        state = .idle
        displayLoadTask?.cancel()
        displayLoadTask = nil
        loadedDisplayRegions = [:]
        displayAttempts = [:]
        displayFailures = [:]
        displayManifest = nil
        lastDisplayRequest = nil
        // Stored, rather than fire-and-forget, so `decodeGeometry` below can
        // await this exact attempt before deciding whether the manifest's
        // colour/render-group catalog is there to read — otherwise a canonical
        // decode racing the manifest read would see `displayManifest == nil`
        // and permanently miss the override, since nothing revisits `lines`/
        // `stations` once built. See ``decodeGeometry(_:)``.
        manifestLoadTask = Task(priority: .utility) {
            do {
                displayManifest = try await Self.loadDisplayManifest()
                if let lastDisplayRequest {
                    activateDisplayRegions(
                        intersecting: lastDisplayRequest.rect,
                        cameraZoom: lastDisplayRequest.cameraZoom)
                }
            } catch {
                networkFailure = error.localizedDescription
            }
        }
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

    /// Bring in the display network of every region the padded rect reaches.
    ///
    /// This intentionally does not call ``ensure(_:)``. The two are different
    /// answers to different questions: this one reads the DISPLAY derivative,
    /// which is geometry with the reviewed corridors and screen-space lanes
    /// already applied and nothing else in it, while ``ensure(_:)`` decodes
    /// the canonical package for the editor and the route solver. Map display
    /// stays on the derivative, so panning across a border can never pull a
    /// national package's topology in behind it.
    ///
    /// A region already read stays read. There are seven of them and 18 MB in
    /// total, so the working set is bounded by the data rather than by a
    /// policy — and dropping Japan the moment its edge left the padded rect
    /// would mean re-reading 12 MB to pan back, which is the thrash the tile
    /// pyramid used to have at a smaller granularity.
    func ensure(regionsIntersecting rect: MKMapRect, cameraZoom: Double) {
        lastDisplayRequest = (rect, cameraZoom)
        guard displayManifest != nil else { return }
        activateDisplayRegions(intersecting: rect, cameraZoom: cameraZoom)
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
            // The manifest and this region may both still be reading; wait
            // for that ATTEMPT (not for success) so a region that finishes
            // first does not permanently miss the manifest's colour and
            // render-group catalog for lack of having waited a moment longer.
            // A manifest that fails leaves `displayManifest` `nil`, and the
            // catalog lookup below is then empty everywhere — the package's
            // own colour, exactly as before this catalog existed.
            await manifestLoadTask?.value
            do {
                let decoded = try await Self.decode(
                    region: region, catalog: displayManifest?.lines ?? [:])
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

    @ObservationIgnored private var isIndexing = false
    @ObservationIgnored private var indexed: Set<Region> = []
    @ObservationIgnored private var requested: Set<Region> = []
    @ObservationIgnored private var decoding: Set<Region> = []
    @ObservationIgnored private var pending: [Region] = []
    @ObservationIgnored private var loads: [RegionLoad] = []
    @ObservationIgnored private var failures: [RegionFailure] = []
    @ObservationIgnored private var displayManifest: RailDisplayNetworkManifest?
    /// The in-flight (or already finished) attempt to read the manifest,
    /// started by ``loadAll()``. `decodeGeometry(_:)` awaits its `.value`
    /// before reading `displayManifest`, which is the only thing that makes
    /// "when the display manifest for a region is available" a promise
    /// rather than a race — the two reads start concurrently in `loadAll()`
    /// and a canonical package decode is the faster of the two for every
    /// shipped region.
    @ObservationIgnored private var manifestLoadTask: Task<Void, Never>?
    @ObservationIgnored private var loadedDisplayRegions: [String: PreparedDisplayRegion] = [:]
    /// How many times each region's file has been asked for. A bundle read is
    /// not a network request and does not usually fail twice, but it CAN fail
    /// once under memory pressure — and a rebuild happens on every zoom tier
    /// and every pan out of the built rect, so a region that simply retried
    /// would retry for the life of the app. Three attempts, then the failure
    /// stands and the diagnostics panel names it.
    @ObservationIgnored private var displayAttempts: [String: Int] = [:]
    /// The last error each region's read produced, so a failure that clears on
    /// a retry stops being reported and one that does not keeps its own name
    /// rather than being replaced by whichever batch finished last.
    @ObservationIgnored private var displayFailures: [String: String] = [:]
    @ObservationIgnored private var displayLoadTask: Task<Void, Never>?
    @ObservationIgnored private var lastDisplayRequest: (rect: MKMapRect, cameraZoom: Double)?

    private static let displayAttemptLimit = 3

    private func activateDisplayRegions(intersecting rect: MKMapRect, cameraZoom: Double) {
        guard let manifest = displayManifest else { return }
        let records = RailDisplayNetwork.records(
            intersecting: rect, cameraZoom: cameraZoom, in: manifest)
        // What the reader is looking at, plus whatever has already been read:
        // a region does not stop being resident because the camera moved off
        // it, so the denominator is the whole working set rather than only
        // this camera's share of it.
        requestedRegionCount = Set(
            records.map(\.region) + Array(loadedDisplayRegions.keys)).count
        // One batch at a time. These are national files — 12 MB for Japan —
        // and a second batch started from the next camera callback would be
        // decoding the same country twice.
        guard displayLoadTask == nil else { return }
        let missing = records.filter {
            loadedDisplayRegions[$0.region] == nil
                && (displayAttempts[$0.region] ?? 0) < Self.displayAttemptLimit
        }
        guard !missing.isEmpty else { return }
        for record in missing {
            displayAttempts[record.region, default: 0] += 1
        }

        // Two at a time rather than four. The tile batch was reading pieces of
        // a few hundred kilobytes; these are whole countries, and the peak
        // cost of preparing one is its decoded JSON plus the geometry built
        // from it held at once.
        //
        // Interactive priority: this follows a reader action or a camera move
        // and gates visible content, unlike the launch badge index.
        displayLoadTask = Task(priority: .userInitiated) {
            let result = await Self.loadDisplayRegions(
                missing, catalog: manifest.lines, maximumConcurrent: 2)
            // Cancellation first: a cancelled batch belongs to a store that
            // has already been reset, and clearing the handle here would clear
            // the replacement's.
            guard !Task.isCancelled else { return }
            displayLoadTask = nil
            for record in missing { displayFailures[record.region] = nil }
            displayFailures.merge(result.failures, uniquingKeysWith: { _, new in new })
            networkFailure = displayFailures
                .sorted { $0.key < $1.key }.first?.value
            guard !result.regions.isEmpty else { return }
            loadedDisplayRegions.merge(result.regions, uniquingKeysWith: { _, new in new })
            publishDisplayNetwork()
            // A region that arrived while the camera kept moving may have
            // brought a neighbour into range. Ask again from where the map is
            // now rather than from the rect this batch started for.
            if let lastDisplayRequest {
                activateDisplayRegions(
                    intersecting: lastDisplayRequest.rect,
                    cameraZoom: lastDisplayRequest.cameraZoom)
            }
        }
    }

    private func publishDisplayNetwork() {
        guard let manifest = displayManifest else {
            mapLines = []
            mapStations = []
            activeRegionCount = 0
            activeNetworkBytes = 0
            return
        }
        // The manifest's own order, so what the map holds does not depend on
        // which country the reader happened to pan into first.
        let ordered = manifest.regions.compactMap { record in
            loadedDisplayRegions[record.region]
        }
        var nextLines: [DrawnLine] = []
        var nextStations: [DrawnStation] = []
        for region in ordered {
            nextLines.append(contentsOf: region.lines)
            nextStations.append(contentsOf: region.stations)
        }
        mapLines = nextLines
        mapStations = nextStations
        activeRegionCount = ordered.count
        activeNetworkBytes = ordered.reduce(0) { $0 + $1.bytes }
    }

    private nonisolated static func loadDisplayManifest() async throws
        -> RailDisplayNetworkManifest {
        try RailDisplayNetwork.manifest()
    }

    private struct PreparedDisplayRegion: Sendable {
        var lines: [DrawnLine]
        var stations: [DrawnStation]
        var bytes: Int
    }

    private struct DisplayRegionLoadItem: Sendable {
        var region: String
        var prepared: PreparedDisplayRegion?
        var failure: String?
    }

    private struct DisplayRegionLoadResult: Sendable {
        var regions: [String: PreparedDisplayRegion]
        var failures: [String: String]
    }

    private nonisolated static func loadDisplayRegions(
        _ records: [RailDisplayNetworkManifest.RegionRecord],
        catalog: [String: RailDisplayNetworkManifest.Line],
        maximumConcurrent: Int
    ) async -> DisplayRegionLoadResult {
        await withTaskGroup(of: DisplayRegionLoadItem.self) { group in
            var next = 0
            let limit = min(max(1, maximumConcurrent), records.count)
            for _ in 0..<limit {
                let record = records[next]
                next += 1
                group.addTask { loadDisplayRegion(record, catalog: catalog) }
            }

            var regions: [String: PreparedDisplayRegion] = [:]
            var failures: [String: String] = [:]
            while let item = await group.next() {
                if let prepared = item.prepared { regions[item.region] = prepared }
                if let failure = item.failure { failures[item.region] = failure }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if next < records.count {
                    let record = records[next]
                    next += 1
                    group.addTask { loadDisplayRegion(record, catalog: catalog) }
                }
            }
            return DisplayRegionLoadResult(regions: regions, failures: failures)
        }
    }

    private nonisolated static func loadDisplayRegion(
        _ record: RailDisplayNetworkManifest.RegionRecord,
        catalog: [String: RailDisplayNetworkManifest.Line]
    ) -> DisplayRegionLoadItem {
        do {
            try Task.checkCancellation()
            let file = try RailDisplayNetwork.region(record, catalog: catalog)
            try Task.checkCancellation()
            return DisplayRegionLoadItem(
                region: record.region,
                prepared: prepareDisplayRegion(file, bytes: record.bytes, catalog: catalog),
                failure: nil)
        } catch is CancellationError {
            return DisplayRegionLoadItem(region: record.region, prepared: nil, failure: nil)
        } catch {
            return DisplayRegionLoadItem(
                region: record.region, prepared: nil,
                failure: "\(record.region): \(error.localizedDescription)")
        }
    }

    private nonisolated static func prepareDisplayRegion(
        _ file: RailDisplayNetworkFile,
        bytes: Int,
        catalog: [String: RailDisplayNetworkManifest.Line]
    ) -> PreparedDisplayRegion {
        let lines = file.lines.compactMap { fragment -> DrawnLine? in
            guard let metadata = catalog[fragment.lineKey],
                  let region = Region(rawValue: metadata.region) else { return nil }
            let intervals = fragment.parts.compactMap { part -> [Coordinate]? in
                let source = part.compactMap(Coordinate.init(pair:))
                guard source.count >= 2 else { return nil }
                return AppleMapDatum.display(source, country: region.code)
            }
            guard !intervals.isEmpty else { return nil }
            return DrawnLine(
                // One fragment per railway and lane, so the lane is the whole
                // of what distinguishes two entries of the same line.
                id: fragment.continuous == true
                    ? "\(fragment.lineKey)#\(fragment.chain ?? 0)"
                    : "\(fragment.lineKey)@\(fragment.lane ?? 0)",
                lineID: metadata.id,
                region: region, name: metadata.name, nameRoma: metadata.nameRoma,
                operatorName: metadata.operator,
                color: Color(hex: metadata.color) ?? .accentColor,
                colorDark: Color(hex: metadata.colorDark) ?? .accentColor,
                colorHex: metadata.color.lowercased(),
                colorDarkHex: metadata.colorDark.lowercased(),
                rank: metadata.rank, minZoom: metadata.minZoomMapLibre,
                visibilityLengthKm: metadata.visibilityLengthKm,
                lodMinZoom: RailStyle.zoom(
                    fromMapLibre: Double(metadata.lodMinZoomMapLibre)),
                lane: fragment.lane ?? 0,
                intervals: intervals,
                continuous: fragment.continuous == true,
                laneRows: (fragment.laneRows ?? []).map {
                    ContinuousStroke.LaneRow(from: $0[0], to: $0[1], lane: $0[2])
                },
                totalMetres: fragment.totalMetres ?? 0,
                follows: (fragment.follows ?? []).map {
                    StrokeFollow(
                        from: $0.from, to: $0.to,
                        canonicalID: "\($0.canonicalLineKey)#\($0.canonicalChain)",
                        canonicalFrom: $0.canonicalFrom, canonicalTo: $0.canonicalTo)
                },
                withheld: (fragment.withheld ?? []).compactMap {
                    $0.count >= 2 ? WithheldSpan(from: $0[0], to: $0[1]) : nil
                },
                familyWindows: (fragment.familyWindows ?? []).compactMap { window in
                    // The file already passed `validated()`, which requires
                    // every window's groupID to resolve — this guard is
                    // belt-and-braces against a caller that skipped it.
                    guard let group = file.families[window.groupID] else { return nil }
                    return FamilyWindow(
                        from: window.from, to: window.to,
                        isLandlord: window.isLandlord, groupID: window.groupID,
                        colorHex: group.color.lowercased(),
                        colorDarkHex: group.colorDark.lowercased())
                })
        }
        let stations = file.stations.compactMap { station -> DrawnStation? in
            guard let metadata = catalog[station.lineKey],
                  let region = Region(rawValue: metadata.region) else { return nil }
            let coordinate = AppleMapDatum.display(
                Coordinate(lon: station.lon, lat: station.lat), country: region.code)
            return DrawnStation(
                id: station.id, region: region, lineID: metadata.id,
                stationCode: station.stationCode, name: station.name,
                nameRoma: station.nameRoma ?? "", coordinate: coordinate,
                colorHex: metadata.color, minZoom: station.minZoomMapLibre,
                lodMinZoom: RailStyle.zoom(
                    fromMapLibre: Double(station.lodMinZoomMapLibre)),
                isTerminal: station.isTerminal, showsLabel: station.showsLabel,
                popup: RailDisplayNetwork.popup(for: station, catalog: catalog),
                lane: station.lane ?? 0, laneBearing: station.bearing,
                slot: station.slot.map { StrokeSlot(chain: $0[0], anchor: $0[1]) })
        }
        return PreparedDisplayRegion(lines: lines, stations: stations, bytes: bytes)
    }

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

    /// - Parameter catalog: the display-network manifest's line catalog
    ///   (``RailDisplayNetworkManifest/lines``), keyed `"{region}|{lineID}"`,
    ///   or empty when the manifest has not loaded (or failed to). Where an
    ///   entry exists its `color`/`colorDark`/`renderGroup` are applied to
    ///   this region's canonical `DrawnLine`s and `DrawnStation`s — the same
    ///   values the map's own fragments already draw in, so the two stop
    ///   disagreeing. `sourceCoordinates`/routing are read from `package`
    ///   exactly as before; only display metadata is touched.
    private nonisolated static func decode(
        region: Region,
        catalog: [String: RailDisplayNetworkManifest.Line] = [:]
    ) async throws -> Decoded {
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
        // The manifest's own key shape (`build-display-network.py`'s
        // `key = f"{region}|{line['id']}"`) — resolved once per line rather
        // than reassembling the string per field below.
        func displayMetadata(for lineID: String) -> RailDisplayNetworkManifest.Line? {
            catalog["\(region.code)|\(lineID)"]
        }
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
            // The manifest's colour, when the manifest is available, wins
            // over the package's own — it is already the fully-resolved
            // value (a render-group override where the reviewed policy names
            // one, the package's own colour otherwise), and it is the value
            // the map's own fragments (`mapLines`) are already drawn in. No
            // manifest, or no entry for this line, falls back to the package
            // exactly as before.
            let display = displayMetadata(for: line.id)
            let colorHex = display?.color ?? line.color
            let colorDarkHex = display?.colorDark ?? line.colorDark ?? line.color
            return DrawnLine(
                id: line.id, lineID: line.id,
                region: region,
                name: line.name,
                nameRoma: line.nameRoma,
                operatorName: line.operator,
                color: Color(hex: colorHex) ?? .accentColor,
                colorDark: Color(hex: colorDarkHex) ?? .accentColor,
                colorHex: (colorHex ?? "#7a7a7a").lowercased(),
                colorDarkHex: (colorDarkHex ?? "#7a7a7a").lowercased(),
                rank: line.rank,
                minZoom: portedMinZoom,
                visibilityLengthKm: visibilityLengthKm,
                lodMinZoom: NetworkLOD.minZoom(
                    portedMinZoom: portedMinZoom,
                    rank: line.rank,
                    visibilityLengthKm: visibilityLengthKm),
                lane: 0,
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
        // The same manifest lookup the lines above used, reduced to the two
        // primitive maps `StationDisplay.Network` can take without knowing
        // this module's `RailDisplayNetworkManifest` type — RailCore sits
        // below RailMap and cannot import it. Built once here rather than
        // inside the `Network` initializer's own per-line loop.
        var colorOverrideByLineID: [String: String] = [:]
        var renderGroupByLineID: [String: String] = [:]
        for line in package.lines {
            guard let display = displayMetadata(for: line.id) else { continue }
            colorOverrideByLineID[line.id] = display.color
            if let renderGroup = display.renderGroup {
                renderGroupByLineID[line.id] = renderGroup
            }
        }
        let stationNetwork = StationDisplay.Network(
            package: package,
            loopLineIDs: Set(package.lines.filter(\.isLoop).map(\.id)),
            packageLogoLineIDs: Set(package.lines.filter(\.hasLogo).map(\.id)),
            colorOverrideByLineID: colorOverrideByLineID,
            renderGroupByLineID: renderGroupByLineID)
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
                    network: stationNetwork, stationID: station.stationID),
                lane: 0, laneBearing: nil)
        }
        return Decoded(
            lines: lines, stations: stations, elapsed: ContinuousClock.now - started)
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
