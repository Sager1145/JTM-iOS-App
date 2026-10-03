/// Station connection counts for selected journeys, independent of the
/// viewport's resident network geometry.
actor MapRideStationImportance {
    static let shared = MapRideStationImportance()

    private var countsByCountry: [String: [String: Int]] = [:]

    func lineCounts(for country: String) -> [String: Int] {
        if let cached = countsByCountry[country] { return cached }

        guard let manifest = try? RailDisplayNetwork.manifest(),
              let record = manifest.regions.first(where: { $0.region == country }),
              let table = try? RailDisplayNetwork.stationIdentity(region: record),
              table.region == country else {
            countsByCountry[country] = [:]
            return [:]
        }

        // Nearby platform coordinates can flag an ID collision at a real hub
        // (Tokyo and Shin-Osaka). Keep those within the map's 600 m name merge
        // distance; widely separated reused IDs cannot identify one station.
        let ambiguousIDs = Set(table.stations.filter {
            $0.idCollision && $0.spreadMetres > 600
        }.map(\.id))
        var counts: [String: Int] = [:]
        for station in table.stations where !ambiguousIDs.contains(station.id) {
            counts[station.id] = max(counts[station.id] ?? 0, Set(station.lines).count)
        }
        countsByCountry[country] = counts
        return counts
    }
}
