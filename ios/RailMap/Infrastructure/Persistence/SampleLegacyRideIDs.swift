import Foundation

/// The ids the bundled example rides had before they were stored like user
/// rides (`journey_` + 32 hex), by sample resource.
///
/// Read only by the sample load, to migrate copies a reader loaded on an
/// older build: without it the same sample loaded again arrives under new
/// ids and every example ride is listed twice. The table is the "Ride id
/// map" removed from `app/data/sample-trips.sources.md`, bundled as
/// `sample-legacy-ride-ids.json`. A missing or unreadable table migrates
/// nothing; it never blocks the load.
enum SampleLegacyRideIDs {
    private struct Table: Decodable {
        let samples: [String: [String: String]]
    }

    private static let table: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "sample-legacy-ride-ids", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Table.self, from: data)
        else { return [:] }
        return decoded.samples
    }()

    /// Legacy id → current id for one sample resource (`train-store`,
    /// `new-year-grand-loop`, …). Empty for a resource it does not know.
    static func map(for resource: String) -> [String: String] {
        table[resource] ?? [:]
    }
}
