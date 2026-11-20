import RailCore

/// Which of the selected trip's stations draw a mark, and which also offer a
/// name, at a given map scale.
///
/// The rule works on screen spacing, not on zoom numbers: a station appears
/// once it stands far enough, in screen points, from every station that
/// outranks it. So a 7 km metro hop and an 800 km Shinkansen run both show
/// their stations as soon as the trip fills the screen, and both thin out
/// evenly when the reader zooms away.
///
/// ## The rule
///
/// 1. Stations are ranked once per trip, tier by tier: origin and
///    destination, then stations where the trip changes line, then other
///    stopping stations, then passing stations and stations whose class no
///    source states (``StationClass/onRoute``) together.
/// 2. Inside a tier the next station is always the one farthest from
///    everything already ranked, so each halving of the scale adds stations
///    evenly along the trip instead of from one end.
/// 3. A station's *separation* is its distance to the nearest station ranked
///    before it. It draws a mark while `separation / metresPerPoint` is at
///    least its class's ``dotGap(_:)``, and offers a name while it is at
///    least ``nameGap(_:)``. Passing and on-route stations also need the map
///    to be closer than ``passDotMaxMetresPerPoint`` (names:
///    ``passNameMaxMetresPerPoint``), so they never show on an overview.
///
/// Because the separation is fixed per trip, each station has one scale from
/// which it shows, and it stays shown at every closer scale: zooming in
/// never removes a mark. Names are only *offered* here; the map's label pass
/// still drops a name that would overlap a higher-priority one
/// (``labelPriority(_:)``).
public enum SelectedTripStationTiers {
    public enum StationClass: Int, Sendable, CaseIterable {
        /// The trip's origin, destination, or a cross-day boundary.
        case terminal
        /// A stopping station where the trip changes line.
        case transfer
        case stop
        /// A station a source says the train ran through without stopping.
        case pass
        /// A station on the route whose stop/pass class no source states.
        /// Drawn as a neutral mark: it is neither a stop nor a pass.
        case onRoute

        /// Ranking tier. Passing and on-route stations share the last one.
        var tier: Int {
            switch self {
            case .terminal: 0
            case .transfer: 1
            case .stop: 2
            case .pass, .onRoute: 3
            }
        }
    }

    /// The map's three trip-station switches.
    public struct Layers: Equatable, Sendable {
        public var terminals: Bool
        public var stops: Bool
        public var pass: Bool

        public init(terminals: Bool = true, stops: Bool = true, pass: Bool = true) {
            self.terminals = terminals
            self.stops = stops
            self.pass = pass
        }

        public func draws(_ stationClass: StationClass) -> Bool {
            switch stationClass {
            case .terminal: terminals
            case .transfer, .stop: stops
            case .pass, .onRoute: pass
            }
        }
    }

    public struct Station: Sendable {
        /// The caller's identity for this station's marker.
        public var key: String
        public var stationClass: StationClass
        public var coordinate: Coordinate

        public init(key: String, stationClass: StationClass, coordinate: Coordinate) {
            self.key = key
            self.stationClass = stationClass
            self.coordinate = coordinate
        }
    }

    public struct Mark: Equatable, Sendable {
        public var stationClass: StationClass
        public var drawsDot: Bool
        public var offersName: Bool

        public init(stationClass: StationClass, drawsDot: Bool, offersName: Bool) {
            self.stationClass = stationClass
            self.drawsDot = drawsDot
            self.offersName = offersName
        }
    }

    public struct Rank: Equatable, Sendable {
        public var stationClass: StationClass
        /// Distance to the nearest station ranked earlier; infinite for the
        /// first station ranked.
        public var separationMetres: Double
        /// The mark draws while the map scale is at most this.
        public var dotMaxMetresPerPoint: Double
        /// The name is offered while the map scale is at most this.
        public var nameMaxMetresPerPoint: Double
    }

    /// One trip's ranking: fixed for the trip, read at any scale.
    public struct Ranking: Equatable, Sendable {
        public private(set) var ranks: [String: Rank]

        public static let empty = Ranking(ranks: [:])

        /// `nil` when the station is not part of this trip's ranking.
        public func mark(for key: String, metresPerPoint: Double, layers: Layers = Layers()) -> Mark? {
            guard let rank = ranks[key] else { return nil }
            let drawsDot = layers.draws(rank.stationClass) && metresPerPoint <= rank.dotMaxMetresPerPoint
            return Mark(
                stationClass: rank.stationClass, drawsDot: drawsDot,
                offersName: drawsDot && metresPerPoint <= rank.nameMaxMetresPerPoint)
        }

        /// Marks and names per class at one scale, before label collisions.
        public func counts(metresPerPoint: Double, layers: Layers = Layers()) -> [StationClass: (dots: Int, names: Int)] {
            var result: [StationClass: (dots: Int, names: Int)] = [:]
            for key in ranks.keys {
                guard let mark = mark(for: key, metresPerPoint: metresPerPoint, layers: layers) else { continue }
                var entry = result[mark.stationClass] ?? (0, 0)
                if mark.drawsDot { entry.dots += 1 }
                if mark.offersName { entry.names += 1 }
                result[mark.stationClass] = entry
            }
            return result
        }
    }

    // MARK: - the numbers

    /// Screen points a station must stand clear of every station ranked
    /// before it to draw its mark.
    public static func dotGap(_ stationClass: StationClass) -> Double {
        switch stationClass {
        case .terminal: 0
        case .transfer: 10
        case .stop: 12
        case .pass, .onRoute: 20
        }
    }

    /// Screen points of clearance before the station offers its name.
    public static func nameGap(_ stationClass: StationClass) -> Double {
        switch stationClass {
        case .terminal: 0
        case .transfer: 10
        case .stop: 36
        case .pass, .onRoute: 64
        }
    }

    /// Passing and on-route marks need a map at least this close (about a
    /// whole metropolitan area on a phone), whatever their spacing.
    public static let passDotMaxMetresPerPoint = 120.0
    /// Passing and on-route names need the closest tier (about one city).
    public static let passNameMaxMetresPerPoint = 40.0

    /// Label-pass priority: lower tiers yield to higher ones. The steps are
    /// wider than ``maxLabelBonus``, so a busy hub never outranks a higher
    /// tier.
    public static func labelPriority(_ stationClass: StationClass) -> Int {
        switch stationClass {
        case .terminal: 5_000
        case .transfer: 4_000
        case .stop: 3_000
        case .pass: 2_000
        case .onRoute: 1_000
        }
    }

    /// The most a station's connections may add inside its tier.
    public static let maxLabelBonus = 501

    /// Inside a tier, busier stations name first.
    public static func labelPriority(
        _ stationClass: StationClass, lineCount: Int, isNetworkTerminal: Bool
    ) -> Int {
        labelPriority(stationClass) + min(max(lineCount, 0), 50) * 10 + (isNetworkTerminal ? 1 : 0)
    }

    // MARK: - classification

    /// A trip stop's class, from the same fields the trip card's timeline
    /// reads (`Stop.stopType`, `Stop.routeEditing.generatedBy`, its times).
    ///
    /// A pass-through that the route guide generated and that carries no time
    /// is the timeline's "inferred passing station": nothing recorded says the
    /// train ran through, so it is ``StationClass/onRoute``. A station with no
    /// stop record at all (`stopType == nil`, a route-section endpoint) is
    /// on-route for the same reason.
    public static func stationClass(
        stopType: String?, isBoundary: Bool, changesLine: Bool, isGenerated: Bool, hasTime: Bool
    ) -> StationClass {
        if isBoundary { return .terminal }
        guard let stopType else { return .onRoute }
        if stopType == "pass_through" {
            return isGenerated && !hasTime ? .onRoute : .pass
        }
        return changesLine ? .transfer : .stop
    }

    /// The stops where the recorded line changes: section `k - 1` and section
    /// `k` both name lines, and share none. `boundaryStop` maps the boundary
    /// before section `k` to its stop, or `nil` when no stop stands there.
    public static func lineChangeStopIndices(
        sectionLineNames: [[String]], boundaryStop: (Int) -> Int?
    ) -> Set<Int> {
        var result: Set<Int> = []
        guard sectionLineNames.count >= 2 else { return result }
        for index in 1..<sectionLineNames.count {
            let before = Set(sectionLineNames[index - 1].filter { !$0.isEmpty })
            let after = Set(sectionLineNames[index].filter { !$0.isEmpty })
            guard !before.isEmpty, !after.isEmpty, before.isDisjoint(with: after),
                  let stop = boundaryStop(index) else { continue }
            result.insert(stop)
        }
        return result
    }

    // MARK: - ranking

    /// Ranks a trip's stations, given in travel order. A key that repeats
    /// (a loop that returns to a station) keeps its highest-ranking class.
    public static func rank(_ stations: [Station]) -> Ranking {
        var unique: [Station] = []
        var indexByKey: [String: Int] = [:]
        for station in stations {
            if let index = indexByKey[station.key] {
                if station.stationClass.tier < unique[index].stationClass.tier {
                    unique[index].stationClass = station.stationClass
                }
            } else {
                indexByKey[station.key] = unique.count
                unique.append(station)
            }
        }

        var ranks: [String: Rank] = [:]
        ranks.reserveCapacity(unique.count)
        // Distance from each unranked station to the nearest ranked one.
        var nearest = [Double](repeating: .infinity, count: unique.count)
        var ranked = [Bool](repeating: false, count: unique.count)

        for tier in 0...3 {
            var remaining = unique.indices.filter { unique[$0].stationClass.tier == tier }
            while !remaining.isEmpty {
                // Farthest from everything ranked so far; travel order on ties.
                var pick = 0
                for offset in remaining.indices.dropFirst()
                where nearest[remaining[offset]] > nearest[remaining[pick]] {
                    pick = offset
                }
                let index = remaining.remove(at: pick)
                let station = unique[index]
                ranks[station.key] = Self.rank(station.stationClass, separation: nearest[index])
                ranked[index] = true
                for other in unique.indices where !ranked[other] {
                    let distance = Geometry.distanceMeters(station.coordinate, unique[other].coordinate)
                    if distance < nearest[other] { nearest[other] = distance }
                }
            }
        }
        return Ranking(ranks: ranks)
    }

    static func rank(_ stationClass: StationClass, separation: Double) -> Rank {
        func limit(_ gap: Double) -> Double {
            gap <= 0 || separation == .infinity ? .infinity : separation / gap
        }
        var dot = limit(dotGap(stationClass))
        var name = limit(nameGap(stationClass))
        if stationClass.tier == 3 {
            dot = min(dot, passDotMaxMetresPerPoint)
            name = min(name, passNameMaxMetresPerPoint)
        }
        return Rank(
            stationClass: stationClass, separationMetres: separation,
            dotMaxMetresPerPoint: dot, nameMaxMetresPerPoint: min(name, dot))
    }
}
