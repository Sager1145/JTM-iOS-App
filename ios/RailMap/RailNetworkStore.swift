import Foundation
import MapKit
import RailCore
import SwiftUI
import os

/// Which variant of a line's geometry is resident or wanted: the full
/// document, or the Douglas–Peucker-simplified overview a `"lines"`-
/// strategy region's qualifying lines carry (manifest A2/A3). Overview
/// draws identically to full at app zoom ≤ 7 — the renderer's own
/// decimation there is coarser than the overview's 50 m tolerance — so it
/// is only ever wanted at that zoom or lower, and only for a line that has
/// one. File-scope rather than nested in `RailNetworkStore` so
/// `RailDisplayNetwork.chunk(_:blob:detail:catalog:families:)` can take it
/// without importing anything new.
enum DisplayDetail: Sendable { case overview, full }

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
        /// Whether a continuous chain may share terminal tangents with the
        /// preceding chain of the same line. False marks a reviewed branch
        /// boundary whose coincident station anchor is not a continuation.
        let joinPrevious: Bool
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
            joinPrevious: Bool = true,
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
            self.joinPrevious = joinPrevious
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
    /// `prepareDisplayLine`). `isLandlord` false (tenant): this chain's own
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

    /// The app zoom below which an overview chunk is preferred over a
    /// full one, when the line has an overview at all. See `DisplayDetail`.
    static let overviewDetailMaxZoom = 7.0

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
    /// Geometry currently resident for the map: every railway line the
    /// padded visible rect has reached (loaded a chunk at a time — see
    /// ``activateDisplayLines(intersecting:cameraZoom:)``). Full-region
    /// `lines` and `stations` above remain available to explicit workflows
    /// such as the station editor, but are never fed to the complete-network
    /// layer.
    ///
    /// Resident is not the same as drawn. What bounds the frame is the
    /// renderer's cull — `NetworkLOD` by zoom and by rect, then the
    /// per-interval rect test in `RailMapView.rebuild` — and it is applied to
    /// continuous geometry, so a railway crossing the screen is one stroke
    /// rather than the run of abutting fragments the storage tiles produced.
    ///
    /// Resident is also not permanent any more: a line the byte budget
    /// evicts leaves both arrays on the next publish; ``networkExtent`` is
    /// derived from the countries under the camera, not from residency, so
    /// eviction cannot shrink the frame either.
    private(set) var mapLines: [DrawnLine] = []
    private(set) var mapStations: [DrawnStation] = []
    private(set) var activeRegionCount = 0
    private(set) var requestedRegionCount = 0
    private(set) var activeNetworkBytes = 0
    private(set) var networkFailure: String?
    /// The frame a 定位 (frame the network) tap re-centres on: the union of
    /// the manifest extents of every country the most recent camera request
    /// touched. Countries, not resident lines, so a budget eviction cannot
    /// shrink it and a chunk that has not arrived yet cannot leave it out; the
    /// camera's own countries, not every country ever visited, so a reader who
    /// has looked at both Japan and North America is not framed on the
    /// Atlantic — the long way round between them in map space. A request
    /// over open sea keeps the previous frame. See ``updateNetworkExtent(for:)``.
    private(set) var networkExtent: MKCoordinateRegion?
    /// How many lines are resident right now, how many have ever been
    /// dropped by the budget, and how many were brought in by the idle
    /// prefetch ring rather than a camera request — diagnostics only, no UI
    /// reads these today.
    private(set) var residentLineCount = 0
    private(set) var evictedLineTotal = 0
    private(set) var prefetchedLineTotal = 0
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
        decodeFailedAt = [:]
        pending = []
        state = .idle
        displayLoadTask?.cancel()
        displayLoadTask = nil
        manifestLoadTask?.cancel()
        manifestLoadTask = nil
        loadEpoch += 1
        displayIndex = nil
        displayBlobs = [:]
        loadedDisplayLines = [:]
        loadingDisplayLines = []
        displayAttempts = [:]
        displayFailures = [:]
        displayManifest = nil
        lastDisplayRequest = nil
        lastRequestedDisplayLine = [:]
        requestSerial = 0
        currentBatchWave = nil
        currentBatchIDs = []
        networkExtent = nil
        residentLineCount = 0
        evictedLineTotal = 0
        prefetchedLineTotal = 0
        // Stored, rather than fire-and-forget, so `decodeGeometry` below can
        // await this exact attempt before deciding whether the manifest's
        // colour/render-group catalog is there to read — otherwise a canonical
        // decode racing the manifest read would see `displayManifest == nil`
        // and permanently miss the override, since nothing revisits `lines`/
        // `stations` once built. See ``decodeGeometry(_:)``.
        let startedEpoch = loadEpoch
        manifestLoadTask = Task(priority: .utility) {
            do {
                let manifest = try await Self.loadDisplayManifest()
                guard startedEpoch == loadEpoch else { return }
                displayManifest = manifest
                let index = RailDisplayNetworkIndex.lineIndex(for: manifest)
                guard startedEpoch == loadEpoch else { return }
                displayIndex = index
                #if DEBUG
                await Self.debugCheckFirstChunkOfEachRegion(index: index, catalog: manifest.lines)
                guard startedEpoch == loadEpoch else { return }
                #endif
                if let lastDisplayRequest {
                    activateDisplayLines(
                        intersecting: lastDisplayRequest.rect,
                        cameraZoom: lastDisplayRequest.cameraZoom)
                }
            } catch {
                guard startedEpoch == loadEpoch else { return }
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
        guard region.isEnabled else { return }
        // A region that just failed to decode is not retried on every
        // render-path call — `stations(in:)` calls this on every keystroke
        // in the ride editor, and a corrupt or missing package would
        // otherwise re-decode (and re-append to `failures`) on each one.
        // Declining a retry here is a pure read: no set membership changes.
        if let failedAt = decodeFailedAt[region], Date().timeIntervalSince(failedAt) < 30 {
            return
        }
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
    /// The unit of loading is a railway LINE, not a region: v2 chunks a
    /// region's blob per line, and each chunk decoded here stays resident
    /// until the byte budget evicts it. A request is served in up to two
    /// waves — an urgent one for the visible rect, a padded one for the rest
    /// of the build rect this renderer asked for — and, once both are
    /// satisfied, the store idles into a third: prefetching one more
    /// build-rect-half ring outward at `.utility` priority, capped by
    /// ``residentByteBudget`` so it can never grow the working set past what
    /// eviction then has to undo. A camera move always preempts a prefetch
    /// batch in flight; it waits behind an urgent or padded one. Eviction is
    /// least-recently-requested by line, never a line the current request
    /// needs or a surviving line's `dependsOn` still names. See
    /// ``activateDisplayLines(intersecting:cameraZoom:)`` and
    /// ``evictIfNeeded(index:)``.
    func ensure(regionsIntersecting rect: MKMapRect, cameraZoom: Double) {
        lastDisplayRequest = (rect, cameraZoom)
        guard displayManifest != nil else { return }
        requestSerial += 1
        activateDisplayLines(intersecting: rect, cameraZoom: cameraZoom)
    }

    /// Called when the reader flips the North America setting.
    ///
    /// Off: drops every resident US/CA line immediately and republishes, so
    /// the map redraws with nothing there even though the camera has not
    /// moved. On: re-indexes the two regions (skipped by ``loadAll()`` while
    /// the setting was off) and re-asks for whatever the current camera
    /// rect wants, exactly as a pan into them would.
    func northAmericaEnabledChanged() {
        if Region.northAmericaEnabled {
            Task(priority: .utility) {
                await indexRegions(Region.ordered(.compact).filter(\.isNorthAmerica))
                await indexRegions(Region.ordered(.large).filter(\.isNorthAmerica))
                if let lastDisplayRequest {
                    activateDisplayLines(
                        intersecting: lastDisplayRequest.rect,
                        cameraZoom: lastDisplayRequest.cameraZoom)
                }
            }
        } else {
            // A batch already in flight for these two regions would otherwise
            // land after the filter below has run and draw them right back
            // in — `publishDisplayNetwork()`'s own region guard catches that
            // case too, but there is no reason to let the decode finish at
            // all once nothing here wants its result.
            displayLoadTask?.cancel()
            displayLoadTask = nil
            loadedDisplayLines = loadedDisplayLines.filter {
                Region(rawValue: $0.value.region)?.isNorthAmerica != true
            }
            if let index = displayIndex { evictIfNeeded(index: index) }
            publishDisplayNetwork()
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
                failures.removeAll { $0.region == region }
                failures.append(
                    RegionFailure(region: region, message: error.localizedDescription))
                // A failed decode must not permanently block a retry: `ensure(_:)`
                // only calls back in here when `requested.insert` reports a new
                // member, and this call's own guard at the top only re-enters when
                // `decoding.insert` does the same. Leaving either set holding this
                // region after failure would make the miss permanent. But
                // `ensure(_:)` is called from view bodies on every render, so
                // the retry itself is throttled by `decodeFailedAt` rather than
                // happening the instant `requested` is clear again.
                requested.remove(region)
                decoding.remove(region)
                decodeFailedAt[region] = Date()
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
    /// When each region last failed to decode, so ``ensure(_:)`` — called
    /// from view bodies on every render — can decline to retry a corrupt or
    /// missing package for 30 seconds instead of hammering it once per
    /// keystroke.
    @ObservationIgnored private var decodeFailedAt: [Region: Date] = [:]
    @ObservationIgnored private var displayManifest: RailDisplayNetworkManifest?
    /// The in-flight (or already finished) attempt to read the manifest,
    /// started by ``loadAll()``. `decodeGeometry(_:)` awaits its `.value`
    /// before reading `displayManifest`, which is the only thing that makes
    /// "when the display manifest for a region is available" a promise
    /// rather than a race — the two reads start concurrently in `loadAll()`
    /// and a canonical package decode is the faster of the two for every
    /// shipped region.
    @ObservationIgnored private var manifestLoadTask: Task<Void, Never>?
    /// Bumped by every ``loadAll()`` reset and captured by that call's own
    /// `manifestLoadTask`, so a manifest read started by an earlier `loadAll()`
    /// — cancellation is cooperative, not immediate — cannot publish
    /// `displayManifest`/`displayIndex` after a newer reset has already
    /// cleared them.
    @ObservationIgnored private var loadEpoch: UInt = 0
    /// The one-time index over the manifest — which railway lives at what
    /// offset inside its region's blob, in draw order. Built by
    /// ``loadAll()`` as soon as the manifest arrives; every camera move after
    /// that reuses it rather than walking the manifest's line dictionary.
    @ObservationIgnored private var displayIndex: RailDisplayNetworkIndex?
    /// A region's blob (`{region}.display.bin`), `mmap`ped once the first
    /// time any of its lines is asked for and kept for the life of the app —
    /// slicing a later chunk out of an already-resident blob costs nothing
    /// this store has to account for.
    @ObservationIgnored private var displayBlobs: [String: Data] = [:]
    /// One entry per railway line whose chunk has been decoded and turned
    /// into drawable geometry. The unit of residency is the LINE, not the
    /// region — see ``ensure(regionsIntersecting:cameraZoom:)``.
    @ObservationIgnored private var loadedDisplayLines: [String: PreparedDisplayLine] = [:]
    /// Lines whose chunk is in flight in the current batch, so a second
    /// camera callback while a batch is still running does not ask for the
    /// same line twice.
    @ObservationIgnored private var loadingDisplayLines: Set<String> = []
    /// How many times each LINE's chunk has been asked for. A bundle read is
    /// not a network request and does not usually fail twice, but it CAN fail
    /// once under memory pressure — and a rebuild happens on every zoom tier
    /// and every pan out of the built rect, so a line that simply retried
    /// would retry for the life of the app. Three attempts, then the failure
    /// stands and the diagnostics panel names it.
    @ObservationIgnored private var displayAttempts: [String: Int] = [:]
    /// The last error each region's read produced, so a failure that clears on
    /// a retry stops being reported and one that does not keeps its own name
    /// rather than being replaced by whichever batch finished last.
    @ObservationIgnored private var displayFailures: [String: String] = [:]
    @ObservationIgnored private var displayLoadTask: Task<Void, Never>?
    @ObservationIgnored private var lastDisplayRequest: (rect: MKMapRect, cameraZoom: Double)?
    /// Which wave a batch belongs to — an urgent one covers the visible
    /// rect, a padded one the rest of the build rect, a prefetch one the
    /// idle ring one build-rect-half further out. Only the wave decides the
    /// task priority and whether the batch counts against
    /// ``displayAttempts``: see ``activateDisplayLines(intersecting:cameraZoom:)``.
    private enum DisplayLoadWave { case urgent, padded, prefetch }
    @ObservationIgnored private var currentBatchWave: DisplayLoadWave?
    @ObservationIgnored private var currentBatchIDs: Set<String> = []
    /// The most recent request serial that named each line — bumped once per
    /// ``ensure(regionsIntersecting:cameraZoom:)`` call and used as the LRU
    /// key by eviction. A prefetched line's serial is the request that
    /// prefetched it, same as a padded or urgent one.
    @ObservationIgnored private var lastRequestedDisplayLine: [String: Int] = [:]
    @ObservationIgnored private var requestSerial = 0

    private static let displayAttemptLimit = 3
    /// Resident chunk bytes the store keeps before eviction starts trimming
    /// the least-recently-requested lines. Same unit as ``activeNetworkBytes``.
    private static let residentByteBudget = 16 * 1024 * 1024
    /// How many chunks a batch decodes at once. Bounded by the device's own
    /// core count rather than a flat constant — a chunk is kilobytes, so the
    /// limiting resource is CPU for JSON decode and geometry, not memory.
    private static var maximumConcurrent: Int {
        max(2, min(8, ProcessInfo.processInfo.activeProcessorCount))
    }

    /// The detail a request wants for one entry: the overview when the
    /// camera is at or below `overviewDetailMaxZoom` AND the line has one,
    /// full otherwise. See `DisplayDetail`.
    private func wantedDetail(
        for entry: RailDisplayNetworkIndex.Entry, cameraZoom: Double
    ) -> DisplayDetail {
        cameraZoom <= Self.overviewDetailMaxZoom && entry.overview != nil ? .overview : .full
    }

    private func activateDisplayLines(intersecting rect: MKMapRect, cameraZoom: Double) {
        guard let manifest = displayManifest, let index = displayIndex else { return }
        var needed = RailDisplayNetwork.lines(
            intersecting: rect, cameraZoom: cameraZoom, in: index)
        // A reader with North America off never draws it, no matter what the
        // camera intersects — see `Region.isEnabled`.
        needed.removeAll { Region(rawValue: $0.region)?.isEnabled == false }
        // Whole-region strategy (builder A1): once any of a small region's
        // entries is needed, its whole blob becomes one batch rather than a
        // line at a time — see `RailDisplayNetworkIndex.wholeRegions`.
        let neededRegions = Set(needed.map(\.region))
        var wholeRegionAdditions: [RailDisplayNetworkIndex.Entry] = []
        for region in index.wholeRegions where neededRegions.contains(region) {
            wholeRegionAdditions.append(contentsOf: index.entriesByRegion[region] ?? [])
        }
        if !wholeRegionAdditions.isEmpty {
            let existingIDs = Set(needed.map(\.id))
            for entry in wholeRegionAdditions where !existingIDs.contains(entry.id) {
                needed.append(entry)
            }
        }
        // What the reader is looking at, plus whatever has already been read:
        // a region does not stop being resident because the camera moved off
        // it, so the denominator is the whole working set rather than only
        // this camera's share of it.
        let loadedRegions = Set(loadedDisplayLines.values.map(\.region))
        requestedRegionCount = Set(needed.map(\.region) + Array(loadedRegions)).count
        for entry in needed { lastRequestedDisplayLine[entry.id] = requestSerial }
        updateNetworkExtent(for: rect, index: index)

        // One batch at a time — except a prefetch batch, which a real camera
        // request always preempts: idle-ring work must never make a pan wait.
        if displayLoadTask != nil {
            if currentBatchWave == .prefetch {
                displayLoadTask?.cancel()
                loadingDisplayLines.subtract(currentBatchIDs)
                displayLoadTask = nil
                currentBatchWave = nil
                currentBatchIDs = []
            } else {
                return
            }
        }

        func missing(_ entries: [RailDisplayNetworkIndex.Entry]) -> [RailDisplayNetworkIndex.Entry] {
            entries.filter { entry in
                guard !loadingDisplayLines.contains(entry.id),
                      (displayAttempts[entry.id] ?? 0) < Self.displayAttemptLimit
                else { return false }
                // A line counts as missing when it is not resident at all, or
                // resident at `.overview` while `.full` is wanted. A resident
                // `.full` line is never downgraded back to missing.
                guard let resident = loadedDisplayLines[entry.id] else { return true }
                return resident.detail == .overview
                    && wantedDetail(for: entry, cameraZoom: cameraZoom) == .full
            }
        }

        let p = NetworkLOD.padding / (1 + 2 * NetworkLOD.padding)
        let visibleRect = rect.insetBy(
            dx: rect.size.width * p, dy: rect.size.height * p)
        var urgentBase = needed.filter { entry in
            entry.minimumCameraZoom <= cameraZoom && entry.mapRect.intersects(visibleRect)
        }
        if !wholeRegionAdditions.isEmpty {
            let existingIDs = Set(urgentBase.map(\.id))
            for entry in wholeRegionAdditions where !existingIDs.contains(entry.id) {
                urgentBase.append(entry)
            }
        }
        let urgent = RailDisplayNetwork.closure(of: urgentBase, in: index)

        let wave: DisplayLoadWave
        let batch: [RailDisplayNetworkIndex.Entry]
        if !missing(urgent).isEmpty {
            wave = .urgent
            batch = missing(urgent)
        } else if !missing(needed).isEmpty {
            wave = .padded
            batch = missing(needed)
        } else {
            let prefetchRect = rect.insetBy(
                dx: -rect.size.width * 0.5, dy: -rect.size.height * 0.5)
            let prefetchNeeded = RailDisplayNetwork.lines(
                intersecting: prefetchRect, cameraZoom: cameraZoom, in: index)
            let candidates = missing(prefetchNeeded)
            let candidatesByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
            let residentBytes = loadedDisplayLines.values.reduce(0) { $0 + $1.bytes }
            // Trim to budget by whole dependency groups, not by blob position:
            // `candidates` is already `dependsOn`-closed (see
            // `RailDisplayNetwork.lines`), so simply dropping entries off the
            // end could keep a dependent while cutting the dependency it needs
            // to draw. Walk `candidates` in its own (blob) order, and for each
            // not-yet-selected entry pull in it and every not-yet-selected
            // entry it depends on (restricted to what is actually still
            // missing) as one unit; a unit that does not fit stops the walk,
            // exactly as the old trim-from-the-end stopped at the first fit.
            var selected: Set<String> = []
            var bytes = residentBytes
            for root in candidates {
                guard !selected.contains(root.id) else { continue }
                var groupIDs: Set<String> = []
                var frontier = [root.id]
                while !frontier.isEmpty {
                    var next: [String] = []
                    for id in frontier where !selected.contains(id) && !groupIDs.contains(id) {
                        guard let entry = candidatesByID[id] else { continue }
                        groupIDs.insert(id)
                        next.append(contentsOf: entry.dependsOn)
                    }
                    frontier = next
                }
                let groupBytes = groupIDs.reduce(0) { sum, id in
                    guard let entry = candidatesByID[id] else { return sum }
                    let wanted = wantedDetail(for: entry, cameraZoom: cameraZoom)
                    let length = wanted == .overview
                        ? (entry.overview?.length ?? entry.chunk.length) : entry.chunk.length
                    return sum + length
                }
                guard bytes + groupBytes <= Self.residentByteBudget else { break }
                bytes += groupBytes
                selected.formUnion(groupIDs)
            }
            let trimmed = candidates.filter { selected.contains($0.id) }
            guard !trimmed.isEmpty else { return }
            wave = .prefetch
            batch = trimmed
        }
        guard !batch.isEmpty else { return }

        for entry in batch { loadingDisplayLines.insert(entry.id) }
        if wave != .prefetch {
            for entry in batch { displayAttempts[entry.id, default: 0] += 1 }
        }
        currentBatchWave = wave
        currentBatchIDs = Set(batch.map(\.id))
        let detailByID = Dictionary(uniqueKeysWithValues: batch.map {
            ($0.id, wantedDetail(for: $0, cameraZoom: cameraZoom))
        })

        // The device's own core count rather than a flat constant: a chunk is
        // kilobytes, one railway line out of a region's blob, not a whole
        // country's decoded JSON — the peak cost of preparing a batch of them
        // at once is nowhere near what the old whole-region loader held.
        //
        // Interactive priority for the urgent/padded waves: they follow a
        // reader action or a camera move and gate visible content, unlike
        // the launch badge index. The idle prefetch ring runs at `.utility`
        // so it never competes with either.
        let priority: TaskPriority = wave == .prefetch ? .utility : .userInitiated
        displayLoadTask = Task(priority: priority) {
            let started = ContinuousClock.now
            let result = await Self.loadDisplayChunks(
                batch, blobs: displayBlobs, catalog: manifest.lines, index: index,
                maximumConcurrent: Self.maximumConcurrent, detailByID: detailByID)
            #if DEBUG
            let elapsed = ContinuousClock.now - started
            let milliseconds = elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000
            let detailBreakdown = [DisplayDetail.full, .overview].compactMap { detail -> String? in
                let entries = batch.filter { (detailByID[$0.id] ?? .full) == detail }
                guard !entries.isEmpty else { return nil }
                let bytes = entries.reduce(0) { sum, entry in
                    sum + (detail == .overview
                        ? (entry.overview?.length ?? entry.chunk.length) : entry.chunk.length)
                }
                let label = detail == .overview ? "overview" : "full"
                return "\(entries.count) \(label)/\(bytes / 1024) KB"
            }.joined(separator: ", ")
            Logger(subsystem: "com.JRM.RailMap", category: "display").info(
                "display batch \(String(describing: wave), privacy: .public) \(batch.count) lines [\(detailBreakdown, privacy: .public)] in \(milliseconds) ms (\(result.items.count) ok, \(result.failures.count) failed)")
            #endif
            // Cancellation first: a cancelled batch belongs to a store that
            // has already been reset, and clearing the handle here would clear
            // the replacement's.
            guard !Task.isCancelled else { return }
            let completedWave = currentBatchWave
            displayLoadTask = nil
            currentBatchWave = nil
            currentBatchIDs = []
            for entry in batch { loadingDisplayLines.remove(entry.id) }
            displayBlobs.merge(result.blobs, uniquingKeysWith: { _, new in new })
            for entry in batch { displayFailures[entry.region] = nil }
            displayFailures.merge(result.failures, uniquingKeysWith: { _, new in new })
            networkFailure = displayFailures
                .sorted { $0.key < $1.key }.first?.value
            guard !result.items.isEmpty else {
                // Every line in this batch failed. A camera that has since
                // moved on still deserves its own attempt — but replaying the
                // same rect/zoom this batch just failed for would spin a hot
                // retry loop against the same missing/broken chunks, since
                // nothing about `displayAttempts` or the blobs changed. Only
                // replay when the latest request is actually a different ask.
                if let lastDisplayRequest,
                    !MKMapRectEqualToRect(lastDisplayRequest.rect, rect) || lastDisplayRequest.cameraZoom != cameraZoom {
                    activateDisplayLines(
                        intersecting: lastDisplayRequest.rect,
                        cameraZoom: lastDisplayRequest.cameraZoom)
                }
                return
            }
            loadedDisplayLines.merge(result.items, uniquingKeysWith: { _, new in new })
            if completedWave == .prefetch { prefetchedLineTotal += result.items.count }
            evictIfNeeded(index: index)
            publishDisplayNetwork()
            // A line that arrived while the camera kept moving may have
            // brought a neighbour into range. Ask again from where the map is
            // now rather than from the rect this batch started for.
            if let lastDisplayRequest {
                activateDisplayLines(
                    intersecting: lastDisplayRequest.rect,
                    cameraZoom: lastDisplayRequest.cameraZoom)
            }
        }
    }

    /// Drops the least-recently-requested resident lines until
    /// ``residentByteBudget`` is met, run once per completed batch right
    /// before ``publishDisplayNetwork()``. Never touches a line the most
    /// recent request needs (directly or through `dependsOn`), and never
    /// evicts a line that a surviving line still depends on — evicting X
    /// only to have Y (kept resident) draw without its alignment would be a
    /// worse failure than staying over budget.
    private func evictIfNeeded(index: RailDisplayNetworkIndex) {
        let residentBytes = loadedDisplayLines.values.reduce(0) { $0 + $1.bytes }
        guard residentBytes > Self.residentByteBudget else { return }
        let protectedEntries = lastDisplayRequest.map {
            RailDisplayNetwork.lines(intersecting: $0.rect, cameraZoom: $0.cameraZoom, in: index)
        } ?? []
        let protected = Set(protectedEntries.map(\.id))
        let candidates = loadedDisplayLines.keys.filter { !protected.contains($0) }
            .sorted { a, b in
                let la = lastRequestedDisplayLine[a] ?? 0
                let lb = lastRequestedDisplayLine[b] ?? 0
                return la != lb ? la < lb : a < b
            }
        var bytes = residentBytes
        for id in candidates {
            guard bytes > Self.residentByteBudget else { break }
            let hasSurvivingDependent = loadedDisplayLines.keys.contains { survivorID in
                survivorID != id && index.entryByID[survivorID]?.dependsOn.contains(id) == true
            }
            guard !hasSurvivingDependent, let prepared = loadedDisplayLines[id] else { continue }
            loadedDisplayLines.removeValue(forKey: id)
            displayAttempts.removeValue(forKey: id)
            bytes -= prepared.bytes
            evictedLineTotal += 1
        }
    }

    private func publishDisplayNetwork() {
        guard let index = displayIndex else {
            mapLines = []
            mapStations = []
            activeRegionCount = 0
            activeNetworkBytes = 0
            residentLineCount = 0
            networkExtent = nil
            return
        }
        // The index's own order — manifest region order, each region in blob
        // order — so what the map holds does not depend on which country or
        // which line inside it happened to finish loading first.
        var nextLines: [DrawnLine] = []
        var nextStations: [DrawnStation] = []
        var residentRegions: Set<String> = []
        var bytes = 0
        for region in index.orderedRegions {
            // A disabled region's lines are filtered here too, not only on
            // eviction: an NA chunk batch that finishes loading after the
            // switch has gone off (see `northAmericaEnabledChanged()`) must
            // not be drawn just because it is still resident.
            guard Region(rawValue: region)?.isEnabled != false else { continue }
            for entry in index.entriesByRegion[region] ?? [] {
                guard let prepared = loadedDisplayLines[entry.id] else { continue }
                nextLines.append(contentsOf: prepared.lines)
                nextStations.append(contentsOf: prepared.stations)
                residentRegions.insert(region)
                bytes += prepared.bytes
            }
        }
        mapLines = nextLines
        mapStations = nextStations
        activeRegionCount = residentRegions.count
        activeNetworkBytes = bytes
        residentLineCount = loadedDisplayLines.count
    }

    /// The countries whose manifest extent the request rect touches (with
    /// the same three world shifts the loader uses), framed as one region.
    /// Two countries on opposite sides of the Pacific would union the long
    /// way round in map space — wider than half the world — so in that case
    /// the country nearest the request's centre is framed alone. No touched
    /// country (open sea) leaves the previous frame in place.
    private func updateNetworkExtent(for rect: MKMapRect, index: RailDisplayNetworkIndex) {
        let world = MKMapRect.world.size.width
        let touched = index.orderedRegions.compactMap { region -> MKMapRect? in
            guard let record = index.recordsByRegion[region] else { return nil }
            let extent = record.mapRect
            guard !extent.isNull,
                  [-world, 0, world].contains(where: { shift in
                      extent.offsetBy(dx: shift, dy: 0).intersects(rect)
                  })
            else { return nil }
            return extent
        }
        guard !touched.isEmpty else { return }
        var union = touched[0]
        for extent in touched.dropFirst() { union = union.union(extent) }
        if union.size.width > world / 2 {
            let centre = MKMapPoint(x: rect.midX, y: rect.midY)
            union = touched.min { a, b in
                hypot(a.midX - centre.x, a.midY - centre.y) < hypot(b.midX - centre.x, b.midY - centre.y)
            } ?? union
        }
        let next = MKCoordinateRegion(union)
        if let current = networkExtent,
           current.center.latitude == next.center.latitude,
           current.center.longitude == next.center.longitude,
           current.span.latitudeDelta == next.span.latitudeDelta,
           current.span.longitudeDelta == next.span.longitudeDelta {
            return
        }
        networkExtent = next
    }

    private nonisolated static func loadDisplayManifest() async throws
        -> RailDisplayNetworkManifest {
        try RailDisplayNetwork.manifest()
    }

    #if DEBUG
    /// Decodes the first chunk of every region once, right after the index is
    /// built, as a guard against a stale or hand-edited bundle during
    /// development. A failure is logged, never allowed to crash — this is a
    /// diagnostic, not a gate on the map opening — and the whole function
    /// only exists in `#if DEBUG` builds.
    private nonisolated static func debugCheckFirstChunkOfEachRegion(
        index: RailDisplayNetworkIndex,
        catalog: [String: RailDisplayNetworkManifest.Line]
    ) async {
        for region in index.orderedRegions {
            guard let entry = index.entriesByRegion[region]?.first,
                  let record = index.recordsByRegion[region] else { continue }
            do {
                let blob = try RailDisplayNetwork.blob(record)
                let file = try RailDisplayNetwork.chunk(
                    entry, blob: blob, catalog: catalog, families: record.families ?? [:])
                assert(file.lineId == entry.id, "chunk for \(entry.id) decoded as \(file.lineId ?? "nil")")
            } catch {
                assertionFailure("RailNetworkStore: debug chunk check failed for \(region): \(error)")
            }
        }
    }
    #endif

    private struct PreparedDisplayLine: Sendable {
        var region: String
        var lines: [DrawnLine]
        var stations: [DrawnStation]
        var bytes: Int
        var detail: DisplayDetail
    }

    private struct DisplayChunkLoadItem: Sendable {
        var lineId: String
        var region: String
        var prepared: PreparedDisplayLine?
        var failure: String?
    }

    private struct DisplayChunkLoadResult: Sendable {
        var items: [String: PreparedDisplayLine]
        var failures: [String: String]
        var blobs: [String: Data]
    }

    private nonisolated static func loadDisplayChunks(
        _ entries: [RailDisplayNetworkIndex.Entry],
        blobs: [String: Data],
        catalog: [String: RailDisplayNetworkManifest.Line],
        index: RailDisplayNetworkIndex,
        maximumConcurrent: Int,
        detailByID: [String: DisplayDetail]
    ) async -> DisplayChunkLoadResult {
        var blobs = blobs
        var newBlobs: [String: Data] = [:]
        func blob(for region: String) -> Data? {
            if let existing = blobs[region] { return existing }
            guard let record = index.recordsByRegion[region],
                  let data = try? RailDisplayNetwork.blob(record) else { return nil }
            blobs[region] = data
            newBlobs[region] = data
            return data
        }
        return await withTaskGroup(of: DisplayChunkLoadItem.self) { group in
            var next = 0
            let limit = min(max(1, maximumConcurrent), entries.count)
            for _ in 0..<limit {
                let entry = entries[next]
                next += 1
                let regionBlob = blob(for: entry.region)
                let families = index.recordsByRegion[entry.region]?.families ?? [:]
                let detail = detailByID[entry.id] ?? .full
                group.addTask {
                    loadDisplayChunk(
                        entry, blob: regionBlob, detail: detail, catalog: catalog,
                        families: families)
                }
            }

            var items: [String: PreparedDisplayLine] = [:]
            var failures: [String: String] = [:]
            while let item = await group.next() {
                if let prepared = item.prepared { items[item.lineId] = prepared }
                if let failure = item.failure { failures[item.region] = failure }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if next < entries.count {
                    let entry = entries[next]
                    next += 1
                    let regionBlob = blob(for: entry.region)
                    let families = index.recordsByRegion[entry.region]?.families ?? [:]
                    let detail = detailByID[entry.id] ?? .full
                    group.addTask {
                        loadDisplayChunk(
                            entry, blob: regionBlob, detail: detail, catalog: catalog,
                            families: families)
                    }
                }
            }
            return DisplayChunkLoadResult(items: items, failures: failures, blobs: newBlobs)
        }
    }

    private nonisolated static func loadDisplayChunk(
        _ entry: RailDisplayNetworkIndex.Entry,
        blob: Data?,
        detail: DisplayDetail,
        catalog: [String: RailDisplayNetworkManifest.Line],
        families: [String: RailDisplayNetworkFile.FamilyColor]
    ) -> DisplayChunkLoadItem {
        do {
            try Task.checkCancellation()
            guard let blob else {
                throw RailDisplayNetworkError.missingRegion(entry.region)
            }
            let file = try RailDisplayNetwork.chunk(
                entry, blob: blob, detail: detail, catalog: catalog, families: families)
            try Task.checkCancellation()
            // The detail actually sliced, not necessarily the one requested
            // — `chunk(...)` falls back to full when an overview was asked
            // for but the line has none — so bytes and the resident detail
            // stay in step with what was really loaded.
            let usedDetail: DisplayDetail = detail == .overview && entry.overview != nil
                ? .overview : .full
            let usedBytes = usedDetail == .overview
                ? (entry.overview?.length ?? entry.chunk.length) : entry.chunk.length
            return DisplayChunkLoadItem(
                lineId: entry.id, region: entry.region,
                prepared: prepareDisplayLine(
                    file: file, entry: entry, catalog: catalog, families: families,
                    bytes: usedBytes, detail: usedDetail),
                failure: nil)
        } catch is CancellationError {
            return DisplayChunkLoadItem(
                lineId: entry.id, region: entry.region, prepared: nil, failure: nil)
        } catch {
            return DisplayChunkLoadItem(
                lineId: entry.id, region: entry.region, prepared: nil,
                failure: "\(entry.region): \(error.localizedDescription)")
        }
    }

    private nonisolated static func prepareDisplayLine(
        file: RailDisplayNetworkFile,
        entry: RailDisplayNetworkIndex.Entry,
        catalog: [String: RailDisplayNetworkManifest.Line],
        families: [String: RailDisplayNetworkFile.FamilyColor],
        bytes: Int,
        detail: DisplayDetail
    ) -> PreparedDisplayLine {
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
                    fromMapLibre: Double(metadata.nativeMinZoomMapLibre)),
                lane: fragment.lane ?? 0,
                intervals: intervals,
                continuous: fragment.continuous == true,
                joinPrevious: fragment.joinPrevious ?? true,
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
                    guard let group = families[window.groupID] else { return nil }
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
                lodMinZoom: NetworkLOD.stationMinZoom(
                    portedMinZoom: station.minZoomMapLibre,
                    lineMinZoomMapLibre: metadata.nativeMinZoomMapLibre),
                isTerminal: station.isTerminal, showsLabel: station.showsLabel,
                popup: RailDisplayNetwork.popup(for: station, catalog: catalog),
                lane: station.lane ?? 0, laneBearing: station.bearing,
                slot: station.slot.map { StrokeSlot(chain: $0[0], anchor: $0[1]) })
        }
        return PreparedDisplayLine(
            region: entry.region, lines: lines, stations: stations, bytes: bytes, detail: detail)
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
                        visibilityLengthKm: visibilityLengthByLineId[line.id] ?? 0,
                        region: region.code, operator: line.operator, name: line.name)
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
                    visibilityLengthKm: visibilityLengthKm, region: region.code,
                    operator: line.operator, name: line.name),
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
