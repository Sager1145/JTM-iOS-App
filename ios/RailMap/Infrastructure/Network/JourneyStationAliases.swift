import Foundation
import RailCore

/// Call from the detached search worker, keeping cold JSON decoding off the main actor.
/// Resource failure is distinct from a successful search with no station aliases.
nonisolated func loadJourneyStationAliases(for codes: [String], package: CompactPackage) throws -> [String: String] {
    let groups = try Stations.bundledIdentityIndex(country: package.country.lowercased()).groups
    return LocalJourneySearch.stationAliases(for: codes, package: package) { groups[$0] }
}
