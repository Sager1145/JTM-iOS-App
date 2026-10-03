import RailCore

/// Immutable detail inputs, prepared off the UI actor once per record revision.
public struct JourneyDetailSnapshot: Sendable {
    public let train: Train
    public let sections: [RouteSection]
    private let codesByName: [String: String]

    public init(train: Train) {
        self.train = train
        sections = StoreOperations.rideRouteSections(for: train)
        var codes: [String: String] = [:]
        for stop in train.stops {
            guard let code = stop.n02StationCode, !code.isEmpty else { continue }
            let key = Stations.normalizeStationName(stop.name)
            if !key.isEmpty, codes[key] == nil { codes[key] = code }
        }
        codesByName = codes
    }

    /// Preserve the journey naming fallback without scanning all stops per row.
    public func stationCode(named name: String, recorded code: String?) -> String? {
        code ?? codesByName[Stations.normalizeStationName(name)]
    }
}
