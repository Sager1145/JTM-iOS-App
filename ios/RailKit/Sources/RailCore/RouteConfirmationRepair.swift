import Foundation

/// Clears inferred `.pending` markers so a stored ride can be solved again.
///
/// The editor used to mark a ride pending before inference had a result. The
/// route store skips every pending ride, so a journey whose stops already
/// name stations was saved and then never drawn. This pass clears only that
/// case. A pending ride that is missing a station code, or that has fewer
/// than two stops, stays pending, and a confirmed ride is left alone.
public enum RouteConfirmationRepair {
    /// Returns every train, with inferred pending cleared, and how many
    /// confirmations changed.
    public static func clearInferredPending(_ trains: [Train]) -> (trains: [Train], changed: Int) {
        var changed = 0
        var repaired = trains
        for index in repaired.indices {
            let train = repaired[index]
            guard train.routeConfirmation == .pending,
                  train.stops.count >= 2,
                  train.stops.allSatisfy({ $0.n02StationCode?.isEmpty == false })
            else { continue }
            repaired[index].routeConfirmation = nil
            changed += 1
        }
        return (repaired, changed)
    }
}
