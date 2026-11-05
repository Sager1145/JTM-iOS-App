import Foundation

/// Planning through reader-chosen via stations.
///
/// The whole trip is planned first with the ordinary
/// ``TripRoutePlanner/plan(package:request:rideDate:admissionContext:)`` rules;
/// corridors that pass every via in order are kept. Only when none does is
/// each leg planned separately and the legs joined. A via station only
/// narrows the search; it never grants a connection the planner would refuse:
/// a line change at a via is never treated as reviewed continuity, so it is
/// reported as `.disconnected` unless the request already allows unverified
/// connections. (A through service the base planner admits is found by the
/// first, whole-trip pass.)
extension TripRoutePlanner {
    /// Most whole-journey candidates kept after joining legs.
    public static let maximumViaCorridors = 4

    public static func plan(package: CompactPackage, request: Request, viaCodes: [String],
                            rideDate: String? = nil,
                            admissionContext: RailwayRouteChoices.AdmissionContext? = nil) throws -> Outcome {
        let vias = waypointCodes(request: request, viaCodes: viaCodes)
        guard !vias.isEmpty else {
            return try plan(package: package, request: request, rideDate: rideDate,
                            admissionContext: admissionContext)
        }
        guard package.country.lowercased() == "jp" else {
            return plan(package: package, request: request, viaCodes: vias, rideDate: rideDate,
                        patterns: [], connectors: [], admissionContext: admissionContext)
        }
        let catalog = try JapanThroughServices.loadBundled()
        return plan(package: package, request: request, viaCodes: vias, rideDate: rideDate,
                    patterns: catalog.patterns, connectors: catalog.connectors,
                    admissionContext: admissionContext)
    }

    static func plan(package: CompactPackage, request: Request, viaCodes: [String],
                     rideDate: String?,
                     patterns: [JapanThroughServices.Pattern],
                     connectors: [JapanThroughServices.Connector],
                     admissionContext: RailwayRouteChoices.AdmissionContext? = nil) -> Outcome {
        let vias = waypointCodes(request: request, viaCodes: viaCodes)
        guard !vias.isEmpty else {
            return plan(package: package, request: request, rideDate: rideDate,
                        patterns: patterns, connectors: connectors, admissionContext: admissionContext)
        }
        let whole = plan(package: package, request: request, rideDate: rideDate,
                         patterns: patterns, connectors: connectors, admissionContext: admissionContext)
        if case .corridors(let corridors) = whole {
            let through = corridors.filter { passes($0, through: vias) }
            if !through.isEmpty { return .corridors(through) }
        }
        let waypoints = [request.originCode] + vias + [request.destinationCode]
        var legs: [[Corridor]] = []
        for index in 0..<(waypoints.count - 1) {
            var leg = request
            leg.originCode = waypoints[index]
            leg.destinationCode = waypoints[index + 1]
            leg.originLineID = index == 0 ? request.originLineID : nil
            leg.destinationLineID = index == waypoints.count - 2 ? request.destinationLineID : nil
            let outcome = plan(package: package, request: leg, rideDate: rideDate,
                               patterns: patterns, connectors: connectors,
                               admissionContext: admissionContext)
            guard case .corridors(let corridors) = outcome, !corridors.isEmpty else {
                return outcome == .corridors([]) ? .noRoute : outcome
            }
            legs.append(corridors)
        }
        let lineNames = Dictionary(package.lines.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return join(legs: legs, allowUnverifiedConnections: request.allowUnverifiedConnections) {
            lineNames[$0]
        }
    }

    /// Via codes with endpoints and immediate repeats removed, in order.
    static func waypointCodes(request: Request, viaCodes: [String]) -> [String] {
        var result: [String] = []
        for code in viaCodes where !code.isEmpty
            && code != request.originCode && code != request.destinationCode
            && code != result.last {
            result.append(code)
        }
        return result
    }

    /// Whether the corridor visits every via, in order.
    static func passes(_ corridor: Corridor, through vias: [String]) -> Bool {
        var remaining = vias[...]
        for visit in corridor.choice.stations.dropFirst().dropLast() where visit.code == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    /// Joins per-leg corridors in order. Pure, so the joining rules are testable
    /// without a package. A line change at a via is unreviewed (`.none`).
    static func join(legs: [[Corridor]], allowUnverifiedConnections: Bool,
                     maximum: Int = maximumViaCorridors,
                     lineName: (String) -> String?)
        -> Outcome {
        guard !legs.isEmpty, legs.allSatisfy({ !$0.isEmpty }) else { return .noRoute }
        // Bound the product: the planner already ranks each leg, best first.
        var partial: [Corridor] = Array(legs[0].prefix(maximum))
        for leg in legs.dropFirst() {
            var next: [Corridor] = []
            for head in partial {
                for tail in leg.prefix(maximum) {
                    if let joined = joined(head, tail, lineName: lineName) { next.append(joined) }
                }
            }
            next.sort(by: ranks)
            partial = Array(next.prefix(maximum * maximum))
        }
        var seen: Set<String> = []
        let unique = partial.sorted(by: ranks).filter { seen.insert($0.id).inserted }
        let admitted = unique.filter { corridor in
            allowUnverifiedConnections || corridor.junctions.allSatisfy { $0.link != .none }
        }
        if !admitted.isEmpty { return .corridors(Array(admitted.prefix(maximum))) }
        guard let best = unique.first else { return .noRoute }
        let refused = best.junctions.filter { $0.link == .none }
        return .disconnected(refused.isEmpty ? best.junctions : refused)
    }

    private static func ranks(_ lhs: Corridor, _ rhs: Corridor) -> Bool {
        if lhs.distanceKm != rhs.distanceKm { return lhs.distanceKm < rhs.distanceKm }
        if lhs.junctions.count != rhs.junctions.count { return lhs.junctions.count < rhs.junctions.count }
        return lhs.id < rhs.id
    }

    /// Nil when the legs do not meet at one station or the result revisits a station.
    private static func joined(
        _ head: Corridor, _ tail: Corridor, lineName: (String) -> String?
    ) -> Corridor? {
        guard let meeting = head.choice.stations.last, let start = tail.choice.stations.first,
              meeting.code == start.code else { return nil }
        // A via is a pass-through point. Doubling back over it is a different trip.
        let codes = head.choice.stations.map(\.code) + tail.choice.stations.dropFirst().map(\.code)
        guard Set(codes).count == codes.count else { return nil }
        var choice = head.choice
        choice.stations += tail.choice.stations.dropFirst()
        choice.sectionCodes += tail.choice.sectionCodes
        choice.routeSections += tail.choice.routeSections
        choice.lineIDs = collapsedRepeats(head.choice.lineIDs + tail.choice.lineIDs)
        choice.lineNames = uniqued(head.choice.lineNames + tail.choice.lineNames)
        choice.operatorNames = uniqued(head.choice.operatorNames + tail.choice.operatorNames)
        var junctions = head.junctions
        if let fromID = head.choice.routeSections.last?.lineIDs?.first ?? head.choice.lineIDs.last,
           let toID = tail.choice.routeSections.first?.lineIDs?.first ?? tail.choice.lineIDs.first,
           fromID != toID {
            junctions.append(Junction(
                stationCode: head.choice.routeSections.last?.toN02StationCode ?? meeting.code,
                stationName: meeting.name,
                fromLineID: fromID, fromLineName: lineName(fromID) ?? fromID,
                toLineID: toID, toLineName: lineName(toID) ?? toID,
                // Two legs meeting at a station prove no train continues there.
                link: .none))
        }
        junctions += tail.junctions
        return Corridor(
            id: choice.id, choice: choice,
            lineNames: choice.lineNames, operatorNames: choice.operatorNames,
            junctions: junctions, distanceKm: head.distanceKm + tail.distanceKm,
            passStationCount: max(0, choice.stations.count - 2))
    }

    private static func collapsedRepeats(_ values: [String]) -> [String] {
        values.reduce(into: []) { result, value in
            if result.last != value { result.append(value) }
        }
    }

    private static func uniqued(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
