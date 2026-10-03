import RailCore

/// Station identities for selected journeys, independent of viewport geometry.
actor MapRideStationImportance {
    static let shared = MapRideStationImportance()

    nonisolated struct Snapshot: Sendable {
        var lineCounts: [String: Int] = [:]
        var endpointPositions: [String: MapEndpointLabels.StationPosition] = [:]
    }

    private var snapshotsByCountry: [String: Snapshot] = [:]

    func snapshot(for country: String) -> Snapshot {
        if let cached = snapshotsByCountry[country] { return cached }

        guard let manifest = try? RailDisplayNetwork.manifest(),
              let record = manifest.regions.first(where: { $0.region == country }),
              let table = try? RailDisplayNetwork.stationIdentity(region: record),
              table.region == country else {
            snapshotsByCountry[country] = Snapshot()
            return Snapshot()
        }

        let history: RailDisplayHistoryFile?
        do { history = try RailDisplayNetwork.history(record) }
        catch {
            snapshotsByCountry[country] = Snapshot()
            return Snapshot()
        }
        let stamps = history?.stationStampRows ?? [:]

        // Nearby platform coordinates can flag an ID collision at a real hub
        // (Tokyo and Shin-Osaka). Keep those within the map's 600 m name merge
        // distance; widely separated reused IDs cannot identify one station.
        let ambiguousIDs = Set(table.stations.filter {
            $0.idCollision && $0.spreadMetres > 600
        }.map(\.id))
        var snapshot = Snapshot()
        for station in table.stations where !ambiguousIDs.contains(station.id) {
            snapshot.lineCounts[station.id] = max(
                snapshot.lineCounts[station.id] ?? 0, Set(station.lines).count)
        }
        // An exact id with conflicting locations cannot identify an endpoint.
        // No proximity rule can resolve that identity on the reader's behalf.
        var rejectedIDs: Set<String> = []
        for station in table.stations {
            let source = Coordinate(lon: station.lon, lat: station.lat)
            guard !station.id.isEmpty, !station.idCollision,
                  MapEndpointLabels.validPosition(source) else {
                rejectedIDs.insert(station.id)
                continue
            }
            let coordinate = AppleMapDatum.display(source, country: country)
            guard MapEndpointLabels.validPosition(coordinate) else {
                rejectedIDs.insert(station.id)
                continue
            }
            // History stamps use platform identities (line id:station id).
            // A station location survives while any of its memberships does;
            // this lookup establishes no connection between those memberships.
            let serviceBounds = station.lines.map { lineID in
                let stamp = stamps["\(lineID):\(station.id)"]
                return MapEndpointLabels.StationServiceBounds(
                    validFrom: stamp?.validFrom, validTo: stamp?.validTo)
            }
            let position = MapEndpointLabels.StationPosition(
                country: country, coordinate: coordinate,
                serviceBounds: serviceBounds)
            if let previous = snapshot.endpointPositions[station.id], previous != position {
                rejectedIDs.insert(station.id)
            } else {
                snapshot.endpointPositions[station.id] = position
            }
        }
        for id in rejectedIDs { snapshot.endpointPositions.removeValue(forKey: id) }
        snapshotsByCountry[country] = snapshot
        return snapshot
    }
}
