import Foundation

/// What a trip's own record says about one station of its stop list: the train
/// called there, the train passed it, or nothing says either.
///
/// The stored `stop_type` alone cannot tell the last two apart. The route
/// planner (`RailwayRouteEditing.appendReplacementVisits`) writes every station
/// between two calls as `pass_through` so that the route, the map and the
/// mileage have the station, but it knows only that the track goes there. A
/// local train stops at all of them and a limited express at some. Those rows
/// keep their `generated_by` marker until the user edits them, and that marker
/// is what separates "the planner put this station on the route" from "the
/// record says the train passed".
///
/// Display code asks this instead of testing `stopType == "pass_through"`, so
/// a station is called passing only when the trip's record says so.
public enum StopCallEvidence: Equatable, Sendable {
    /// The record says the train called here: an origin, destination, passenger
    /// or operational stop, as entered, imported or filled from a timetable.
    case stop
    /// The record says the train passed: a `pass_through` row that was entered,
    /// imported, or edited by the user after the planner made it.
    case recordedPass
    /// The planner put this station on the route and nothing says whether the
    /// train stopped. Shown as on the route, never as passing.
    case onRouteUnknown
}

extension Stop {
    public var callEvidence: StopCallEvidence {
        guard stopType == "pass_through" else { return .stop }
        return routeEditing?.generatedBy != nil ? .onRouteUnknown : .recordedPass
    }
}
