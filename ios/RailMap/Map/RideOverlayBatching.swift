import MapKit

/// Groups the non-selected rides' polylines into a few shared overlays.
///
/// One overlay per ride and kind costs one MapKit renderer each — 500 rides
/// were 500–1500 overlays. A batch is every ride of one colour, one kind
/// (solid / cross-day / unproven) and one date-scope class, so the overlay
/// count is bounded by the palette rather than the ride count, and adding or
/// removing a ride only touches the batches of its own colour.
///
/// Each batch is also sharded by a stable geographic cell of the ride's full
/// geometry, so a pan that culls one ride's segment in or out rebuilds only
/// the small batch of that cell, not every ride of the colour.
///
/// Accepted visual changes against one overlay per ride:
/// - Overlapping rides inside one batch no longer compound alpha when dimmed
///   (selection spotlight, date scope).
/// - Stacking is deterministic by kind, scope, colour and cell, not deck order.
/// - A newly picked ride is dimmed with its batch until the full rebuild that
///   gives it its own cores (normally the same run loop; longer only while a
///   rebuild is deferred by playback or a gesture).
///
/// Pure: it never touches an `MKMapView`, never changes coordinates and never
/// re-chunks. The selected ride is not batched; it keeps its own overlays so
/// it can carry a casing and sit on top.
enum RideOverlayBatching {
    enum Kind: Int, CaseIterable {
        case ride, rideCrossDay, rideUnproven

        /// The same prefixes `MapOverlayStyles.rideSuffixes` lists.
        var prefix: String {
            switch self {
            case .ride: "ride"
            case .rideCrossDay: "ride-xday"
            case .rideUnproven: "ride-unproven"
            }
        }
        var dashed: Bool { self == .rideCrossDay }
        var historical: Bool { self == .rideUnproven }
    }

    enum ScopeClass: Int {
        /// Outside the date scope; drawn underneath.
        case off
        /// Inside the date scope (or no scope is active).
        case inScope

        var token: String { self == .off ? "off" : "in" }
    }

    struct RideEntry {
        var rideID: String
        var colorHex: String
        var inScope: Bool
        /// Stable per-ride geographic cell (see `cell(of:)`), from the ride's
        /// full geometry rather than its culled segments.
        var cell: Int
        var solid: [MKPolyline]
        var crossDay: [MKPolyline]
        var unproven: [MKPolyline]

        func polylines(of kind: Kind) -> [MKPolyline] {
            switch kind {
            case .ride: solid
            case .rideCrossDay: crossDay
            case .rideUnproven: unproven
            }
        }
    }

    struct BatchSpec {
        var key: String
        var kind: Kind
        var scopeClass: ScopeClass
        var colorHex: String
        var cell: Int
        var polylines: [MKPolyline]
    }

    struct Plan {
        /// Non-selected rides, in stacking order (bottom first).
        var batches: [BatchSpec]
        /// The selected ride's own entry, when it is among the inputs.
        var selected: RideEntry?
    }

    static func normalisedColor(_ hex: String) -> String {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.hasPrefix("#") ? trimmed : "#" + trimmed
    }

    static let gridSide = 16

    /// Cell of the centre of `rect` on a 16x16 grid over `MKMapRect.world`.
    static func cell(of rect: MKMapRect) -> Int {
        let world = MKMapRect.world
        func index(_ value: Double, _ extent: Double) -> Int {
            guard value.isFinite else { return 0 }
            return min(max(Int(value / (extent / Double(gridSide))), 0), gridSide - 1)
        }
        let col = index(rect.midX, world.width)
        let row = index(rect.midY, world.height)
        return row * gridSide + col
    }

    static func batchKey(kind: Kind, scopeClass: ScopeClass, colorHex: String, cell: Int) -> String {
        "rides|\(kind.prefix)|\(scopeClass.token)|\(normalisedColor(colorHex))|c\(cell)"
    }

    static func plan(entries: [RideEntry], selectedRideID: String?) -> Plan {
        var selected: RideEntry?
        var rest: [(index: Int, entry: RideEntry)] = []
        for (index, entry) in entries.enumerated() {
            if entry.rideID == selectedRideID {
                selected = entry
            } else {
                rest.append((index, entry))
            }
        }
        // Stable member order, so an unchanged batch has an identical array.
        rest.sort { $0.entry.rideID == $1.entry.rideID
            ? $0.index < $1.index : $0.entry.rideID < $1.entry.rideID }

        struct Slot: Hashable {
            var kind: Kind
            var scopeClass: ScopeClass
            var color: String
            var cell: Int
        }
        var buckets: [Slot: [MKPolyline]] = [:]
        for (_, entry) in rest {
            let scopeClass: ScopeClass = entry.inScope ? .inScope : .off
            let color = normalisedColor(entry.colorHex)
            for kind in Kind.allCases {
                let polylines = entry.polylines(of: kind)
                guard !polylines.isEmpty else { continue }
                buckets[Slot(kind: kind, scopeClass: scopeClass, color: color, cell: entry.cell), default: []]
                    .append(contentsOf: polylines)
            }
        }
        let batches = buckets.sorted { left, right in
            if left.key.kind != right.key.kind { return left.key.kind.rawValue < right.key.kind.rawValue }
            if left.key.scopeClass != right.key.scopeClass {
                return left.key.scopeClass.rawValue < right.key.scopeClass.rawValue
            }
            if left.key.color != right.key.color { return left.key.color < right.key.color }
            return left.key.cell < right.key.cell
        }.map { slot, polylines in
            BatchSpec(
                key: batchKey(kind: slot.kind, scopeClass: slot.scopeClass, colorHex: slot.color,
                         cell: slot.cell),
                kind: slot.kind, scopeClass: slot.scopeClass, colorHex: slot.color, cell: slot.cell,
                polylines: polylines)
        }
        return Plan(batches: batches, selected: selected)
    }
}
