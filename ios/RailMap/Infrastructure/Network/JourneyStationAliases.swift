import Foundation
import RailCore

/// Call from the detached search worker, keeping cold JSON decoding off the main actor.
/// Resource failure is distinct from a successful search with no station aliases.
nonisolated func loadJourneyStationAliases(for codes: [String], package: CompactPackage) throws -> [String: String] {
    let groups = try Stations.bundledIdentityIndex(country: package.country.lowercased()).groups
    return LocalJourneySearch.stationAliases(for: codes, package: package) { groups[$0] }
}

/// Uses the request's selected day. Missing history/date preserves conservative
/// compact admission; a present malformed history must reach the worker error UI.
nonisolated func loadJourneyAdmissionContext(
    rideDate: String?, package: CompactPackage
) throws -> RailwayRouteChoices.AdmissionContext? {
    guard let rideDate else { return nil }
    guard let url = Bundle.main.url(
        forResource: Region.countrySuffixed("rail-history", country: package.country.lowercased()),
        withExtension: "json") else { return nil }
    return try RailwayRouteChoices.AdmissionContext(history: RailHistoryOverlay.load(from: url), civilDay: rideDate)
}
