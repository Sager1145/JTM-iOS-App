import MapKit
import RailCore

/// The map's ride deck as last applied, and which rides a new array changed.
///
/// A partial route publication or a single ride edit hands the map a new
/// array in which almost every ride is the one already drawn. The deck keeps
/// one digest per ride (the facts `rideSignature` states) so a new array is
/// compared once, ride by ride, and the result names exactly the rides whose
/// drawing has to change. The deck-wide digest the marker caches key on is
/// derived from the same per-ride digests rather than rehashing every stop.
struct RideDeckState {
    struct Change: Equatable {
        /// Added, removed, or with any drawn fact changed.
        var changed: Set<String>
        /// The id sequence differs (insertions, removals or reordering).
        var orderChanged: Bool
        /// Duplicate ids: per-ride diffs cannot name what changed.
        var ambiguous: Bool

        var isEmpty: Bool { changed.isEmpty && !orderChanged && !ambiguous }
    }

    private(set) var ids: [String] = []
    private(set) var digests: [String: Int] = [:]
    private(set) var deckDigest: Int = RideDeckState.deckDigest(positional: [])

    /// The deck `rides` would be, and how it differs from this one.
    func advanced(to rides: [RiddenRouteStore.DrawnRide]) -> (next: RideDeckState, change: Change) {
        var next = RideDeckState()
        next.ids = rides.map(\.id)
        var digests: [String: Int] = [:]
        digests.reserveCapacity(rides.count)
        var positional: [Int] = []
        positional.reserveCapacity(rides.count)
        var ambiguous = false
        for ride in rides {
            let digest = Self.rideDigest(ride)
            positional.append(digest)
            if digests.updateValue(digest, forKey: ride.id) != nil { ambiguous = true }
        }
        next.digests = digests
        next.deckDigest = Self.deckDigest(positional: positional)
        var changed: Set<String> = []
        for (id, digest) in digests where self.digests[id] != digest { changed.insert(id) }
        for id in self.digests.keys where digests[id] == nil { changed.insert(id) }
        let change = Change(
            changed: changed, orderChanged: next.ids != ids,
            ambiguous: ambiguous || self.digests.count != ids.count)
        return (next, change)
    }

    func digest(of id: String) -> Int? { digests[id] }

    /// Every fact about one ride that changes what is drawn for it — the same
    /// fields, in the same order, as `Coordinator.rideSignature`.
    static func rideDigest(_ ride: RiddenRouteStore.DrawnRide) -> Int {
        var hasher = Hasher()
        hasher.combine(ride.id)
        hasher.combine(ride.geometryDigest)
        hasher.combine(ride.colorHex)
        hasher.combine(ride.visible)
        hasher.combine(ride.trainType)
        hasher.combine(stopsDigest(ride.stops))
        hasher.combine(ride.daySpan.sig)
        return hasher.finalize()
    }

    /// The stops, as the one number the signature needs. `Hasher` rather than
    /// a joined string; seeded per process, which is all that is asked of it —
    /// the comparison is always between two values read in the same run.
    static func stopsDigest(_ stops: [Stop]) -> Int {
        var hasher = Hasher()
        hasher.combine(stops.count)
        for stop in stops {
            hasher.combine(stop.name)
            hasher.combine(stop.stopType)
            hasher.combine(stop.rideSegment)
            hasher.combine(stop.arrival)
            hasher.combine(stop.departure)
            hasher.combine(stop.n02StationCode)
        }
        return hasher.finalize()
    }

    /// Each ride's own digest in deck order. Not looked up by id: with a
    /// duplicate id every position would read the last ride's digest, and a
    /// change to an earlier duplicate would leave the deck digest — and the
    /// marker caches keyed on it — unchanged.
    private static func deckDigest(positional: [Int]) -> Int {
        var hasher = Hasher()
        hasher.combine(positional.count)
        for digest in positional { hasher.combine(digest) }
        return hasher.finalize()
    }
}

/// What the last full rebuild (or rides-only update) installed for the
/// non-selected rides, and the inputs it was drawn under. A rides-only update
/// may reuse it only while every one of those inputs is still current. Stroke
/// references are not stamped: they change only when a full rebuild installs
/// a finished match, which replaces this cache.
struct RideBatchCache {
    struct Stamp: Equatable {
        var frameKey: String
        var buildRect: [Double]
        var linesGeneration: Int
        var selectedTrainID: String?
        var hasSelection: Bool
        var selectedDate: String
        var display: RailMapView.DisplayValues
        var layers: MapLayers
        var categoryCountries: Set<String>
        var dark: Bool

        init(
            frameKey: String, buildRect: MKMapRect, linesGeneration: Int,
            selectedTrainID: String?, hasSelection: Bool, selectedDate: String,
            display: RailMapView.DisplayValues, layers: MapLayers,
            categoryCountries: Set<String>, dark: Bool
        ) {
            self.frameKey = frameKey
            self.buildRect = [buildRect.minX, buildRect.minY, buildRect.width, buildRect.height]
            self.linesGeneration = linesGeneration
            self.selectedTrainID = selectedTrainID
            self.hasSelection = hasSelection
            self.selectedDate = selectedDate
            self.display = display
            self.layers = layers
            self.categoryCountries = categoryCountries
            self.dark = dark
        }
    }

    var stamp: Stamp
    /// Each non-selected ride's batch entry, by ride id.
    var entries: [String: RideOverlayBatching.RideEntry]
    /// The installed batches, in stacking order.
    var batches: [RideOverlayBatching.BatchSpec]
}

/// Ride stroke styling shared by the full rebuild and the rides-only update.
enum RideOverlayStyle {
    /// The seed weight, the reader's 線路粗細 multiplier, the focus boost when
    /// it is the selected one, and then RIDDEN_WIDTH_SCALE — in that order,
    /// because the boost is a width the reader chose and not a proportion of one.
    static func widthToken(display: RailMapView.DisplayValues, selected: Bool) -> CGFloat {
        let seed = RailStyle.riddenWidth * CGFloat(display.routeWidthScale)
        let focused = selected ? CGFloat(display.focusBoost) : 0
        return (seed + focused) * RailStyle.riddenWidthScale
    }

    /// What `MapDateScope.alpha` gives a non-selected ride of a batch's class.
    static func batchAlpha(
        display: RailMapView.DisplayValues, scope: MapDateScope.Scope,
        hasSelection: Bool, inScope: Bool
    ) -> CGFloat {
        hasSelection ? RailStyle.selectDim
            : (inScope ? CGFloat(display.riddenOpacity) : scope.dimOpacity)
    }
}

extension RideOverlayBatching {
    /// One non-selected ride's batch entry: its date-scope class and its
    /// stable cell from the full geometry.
    static func entry(
        for ride: RiddenRouteStore.DrawnRide, scope: MapDateScope.Scope,
        solid: [MKPolyline], crossDay: [MKPolyline], unproven: [MKPolyline]
    ) -> RideEntry {
        RideEntry(
            rideID: ride.id, colorHex: ride.colorHex,
            inScope: !(scope.isActive && !MapDateScope.inScope(ride.daySpan, scope)),
            cell: cell(of: ride.segments.dropFirst().reduce(
                ride.segments.first?.boundingRect ?? .null) { $0.union($1.boundingRect) }),
            solid: solid, crossDay: crossDay, unproven: unproven)
    }

    /// `plan(entries:selectedRideID:)`'s batches, re-formed only for
    /// `affectedCells`: every batch of another cell is carried over from
    /// `previous` unchanged. Equal to a full plan whenever the entries of the
    /// unaffected cells are the ones `previous` was planned from.
    static func replan(
        previous: [BatchSpec], entries: [RideEntry], affectedCells: Set<Int>,
        selectedRideID: String?
    ) -> [BatchSpec] {
        guard !affectedCells.isEmpty else { return previous }
        let reformed = plan(
            entries: entries.filter { affectedCells.contains($0.cell) },
            selectedRideID: selectedRideID).batches
        return (previous.filter { !affectedCells.contains($0.cell) } + reformed)
            .sorted(by: stacksBelow)
    }

    /// The stacking order `plan` produces: kind, scope class, colour, cell.
    static func stacksBelow(_ left: BatchSpec, _ right: BatchSpec) -> Bool {
        if left.kind != right.kind { return left.kind.rawValue < right.kind.rawValue }
        if left.scopeClass != right.scopeClass { return left.scopeClass.rawValue < right.scopeClass.rawValue }
        if left.colorHex != right.colorHex { return left.colorHex < right.colorHex }
        return left.cell < right.cell
    }
}

/// Station and line lookups the marker pass reads, rebuilt only when
/// `lines` or `stations` move (both bump the coordinator's `linesGeneration`).
struct MarkerSetupCache {
    let generation: Int
    let stationsByPlace: [String: [RailNetworkStore.DrawnStation]]
    let linesByStrokeID: [String: RailNetworkStore.DrawnLine]
    let connectionsByPlace: [String: Int]

    init(
        generation: Int, lines: [RailNetworkStore.DrawnLine],
        stations: [RailNetworkStore.DrawnStation]
    ) {
        self.generation = generation
        stationsByPlace = Dictionary(grouping: stations) {
            "\($0.region.rawValue)|\($0.stationCode)"
        }
        linesByStrokeID = Dictionary(
            lines.filter(\.continuous).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        var connections: [String: Int] = [:]
        for station in stations {
            let key = "\(station.region.rawValue)|\(station.stationCode)"
            connections[key] = max(connections[key] ?? 0, station.popup.lines.count)
        }
        connectionsByPlace = connections
    }
}
