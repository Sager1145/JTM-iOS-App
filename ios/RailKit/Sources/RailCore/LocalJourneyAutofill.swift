import Foundation

/// Turns an offline physical path into a reviewable draft. Timetables alone
/// can supply passenger calls and times; geometry supplies untimed visits.
public enum LocalJourneyAutofill {
    public struct Proposal: Sendable {
        public let train: Train
        public let choice: RailwayRouteChoices.Choice
        public let conflictingStops: [Stop]
        public var requiresConfirmation: Bool { !conflictingStops.isEmpty }
    }

    public static func proposal(train: Train, choice: RailwayRouteChoices.Choice) -> Proposal? {
        guard let origin = choice.stations.first, let destination = choice.stations.last,
              origin.code != destination.code else { return nil }
        let prepared = RailwayRouteEditing.preparing(train)
        var base = prepared
        var removed: [Stop] = []
        if prepared.stops.first?.n02StationCode != origin.code
            || prepared.stops.last?.n02StationCode != destination.code {
            // Preserve matching visits in traversal order, including authored times.
            var cursor = 0
            var retained: Set<Int> = []
            var visits: [Stop] = []
            for (position, visit) in choice.stations.enumerated() {
                if let index = prepared.stops.indices.dropFirst(cursor).first(where: {
                    prepared.stops[$0].n02StationCode == visit.code
                }) {
                    var stop = prepared.stops[index]
                    if position == 0 { stop.stopType = "origin" }
                    if position == choice.stations.count - 1 { stop.stopType = "destination" }
                    if position > 0 && position < choice.stations.count - 1,
                       ["origin", "destination"].contains(stop.stopType) { stop.stopType = "passenger_stop" }
                    visits.append(stop)
                    retained.insert(index)
                    cursor = index + 1
                } else if position == 0 || position == choice.stations.count - 1 {
                    visits.append(Stop(name: visit.name, n02StationCode: visit.code,
                        stopType: position == 0 ? "origin" : "destination",
                        rideSegment: train.stops.first?.rideSegment ?? false,
                        routeEditing: .init()))
                }
            }
            removed = prepared.stops.indices.filter { !retained.contains($0) }.map { prepared.stops[$0] }
                .filter { !$0.name.isEmpty && !RailwayRouteEditing.isUntouchedGenerated($0) }
            base.stops = visits
            base.routeSections = nil
            // Preferences belonged to the previous journey corridor.
            base.routePolicy = nil
        }
        guard let plan = RailwayRouteEditing.plan(train: base, choice: choice,
            fromVisitID: base.stops.first?.routeEditing?.visitID,
            toVisitID: base.stops.last?.routeEditing?.visitID) else { return nil }
        var result = plan.updatedTrain
        result.origin = origin.name
        result.destination = destination.name
        // This proposal spans the selected ride endpoints; the caller applies
        // it only after the user explicitly selects the physical candidate.
        result.routeConfirmation = .confirmed
        return Proposal(train: result, choice: choice,
            conflictingStops: removed + plan.conflictingStops)
    }
}
