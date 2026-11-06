import Foundation

/// A trip cut into sections at the reader's via stations.
///
/// Each section, station to station, is planned on its own with the ordinary
/// ``TripRoutePlanner/plan(package:request:rideDate:admissionContext:)`` rules,
/// so only a section with more than one plausible path asks the reader, and
/// changing one section never re-plans the others. ``joining(_:wholeTrip:allowUnverifiedConnections:lineName:)``
/// turns one chosen corridor per section into the trip's route.
///
/// A via only narrows the search; it never grants a connection the planner
/// would refuse. A line change at a via follows the same ``TripConnectivity``
/// rule as the planner (same row, dated reviewed physical junction or dated
/// through service); a whole-trip corridor for that exact route keeps its own
/// junctions.
extension TripRoutePlanner {
    /// The trip's sections in travel order: one request per pair of
    /// consecutive waypoints. Only the first section keeps the origin line
    /// and only the last keeps the destination line.
    public static func sectionRequests(_ request: Request, viaCodes: [String]) -> [Request] {
        let waypoints = [request.originCode] + waypointCodes(request: request, viaCodes: viaCodes)
            + [request.destinationCode]
        return (0..<(waypoints.count - 1)).map { index in
            var leg = request
            leg.originCode = waypoints[index]
            leg.destinationCode = waypoints[index + 1]
            leg.originLineID = index == 0 ? request.originLineID : nil
            leg.destinationLineID = index == waypoints.count - 2 ? request.destinationLineID : nil
            return leg
        }
    }

    /// A section's candidates that do not run through another of the trip's
    /// waypoints. Such a path would make the joined trip pass that stop twice,
    /// so it is not a real choice; on a loop it is the "wrong way round". When
    /// every candidate does, they are all kept and the join reports it.
    public static func plausible(
        _ corridors: [Corridor], waypoints: [String], stationAliases: [String: String] = [:]
    ) -> [Corridor] {
        func fold(_ code: String) -> String { stationAliases[code] ?? code }
        let stops = Set(waypoints.map(fold))
        let kept = corridors.filter { corridor in
            let ends = Set([corridor.choice.stations.first?.code, corridor.choice.stations.last?.code]
                .compactMap { $0 }.map(fold))
            return !corridor.choice.stations.dropFirst().dropLast().contains {
                let code = fold($0.code)
                return stops.contains(code) && !ends.contains(code)
            }
        }
        return kept.isEmpty ? corridors : kept
    }

    /// The trip's route from one chosen corridor per section.
    ///
    /// `wholeTrip` is the whole-trip plan's corridors, when there are vias:
    /// a joined route the whole-trip plan found keeps that corridor's own
    /// junctions. Otherwise a line change at a via is judged by
    /// ``TripConnectivity`` on `rideDate` with the bundled through-service
    /// catalog and physical junctions of `region`; a `.none` change makes the
    /// result `.disconnected` unless unverified connections are allowed. A route
    /// that passes a station twice is `.noRoute`.
    /// `stationAliases` folds per-line codes of one interchange together, so
    /// sections that meet at a station with a code per line still join.
    public static func joining(
        _ sections: [Corridor], wholeTrip: [Corridor] = [], allowUnverifiedConnections: Bool,
        stationAliases: [String: String] = [:], region: String? = nil, rideDate: String? = nil,
        lineName: (String) -> String?
    ) -> Outcome {
        let catalog = region?.lowercased() == "jp" ? try? JapanThroughServices.loadBundled() : nil
        return joining(
            sections, wholeTrip: wholeTrip, allowUnverifiedConnections: allowUnverifiedConnections,
            stationAliases: stationAliases, rideDate: rideDate,
            patterns: catalog?.patterns ?? [], connectors: catalog?.connectors ?? [],
            junctions: region.map { TripConnectivity.Junctions.bundled(region: $0) } ?? .empty,
            lineName: lineName)
    }

    static func joining(
        _ sections: [Corridor], wholeTrip: [Corridor] = [], allowUnverifiedConnections: Bool,
        stationAliases: [String: String] = [:], rideDate: String?,
        patterns: [JapanThroughServices.Pattern], connectors: [JapanThroughServices.Connector],
        junctions: TripConnectivity.Junctions, lineName: (String) -> String?
    ) -> Outcome {
        func link(_ fromID: String, _ toID: String, _ code: String) -> TripConnectivity.Link {
            TripConnectivity.link(fromLineID: fromID, toLineID: toID, atStationCode: code, on: rideDate,
                                  patterns: patterns, connectors: connectors, junctions: junctions)
        }
        guard var route = sections.first else { return .noRoute }
        for next in sections.dropFirst() {
            guard let joined = joined(route, next, aliases: stationAliases, link: link, lineName: lineName)
            else { return .noRoute }
            route = joined
        }
        if let proven = wholeTrip.first(where: { $0.id == route.id }) { return .corridors([proven]) }
        let refused = route.junctions.filter { $0.link == .none }
        if !refused.isEmpty, !allowUnverifiedConnections { return .disconnected(refused) }
        return .corridors([route])
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

    /// Nil when the legs do not meet at one station or the result revisits a station.
    private static func joined(
        _ head: Corridor, _ tail: Corridor, aliases: [String: String] = [:],
        link: (String, String, String) -> TripConnectivity.Link, lineName: (String) -> String?
    ) -> Corridor? {
        func fold(_ code: String) -> String { aliases[code] ?? code }
        guard let meeting = head.choice.stations.last, let start = tail.choice.stations.first,
              fold(meeting.code) == fold(start.code) else { return nil }
        // A via is a pass-through point. Doubling back over it is a different trip.
        let codes = (head.choice.stations.map(\.code) + tail.choice.stations.dropFirst().map(\.code)).map(fold)
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
            let code = head.choice.routeSections.last?.toN02StationCode ?? meeting.code
            junctions.append(Junction(
                stationCode: code,
                stationName: meeting.name,
                fromLineID: fromID, fromLineName: lineName(fromID) ?? fromID,
                toLineID: toID, toLineName: lineName(toID) ?? toID,
                // Two legs meeting at a station prove nothing by themselves;
                // only the connectivity rule lets one train continue.
                link: link(fromID, toID, code)))
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
