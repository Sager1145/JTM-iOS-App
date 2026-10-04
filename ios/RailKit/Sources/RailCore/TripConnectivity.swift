public enum TripConnectivity {
    public enum Link: String, Equatable, Sendable {
        case sameLine, throughService, network, none
    }

    /// Whether one train can continue between these lines at the junction.
    public static func link(from: CompactPackage.Line, to: CompactPackage.Line,
                            atStationCode stationCode: String) -> Link {
        if from.id == to.id { return .sameLine }
        if !JapanThroughServices.continuationCodes(
            fromLineID: from.id, toLineID: to.id, atStationCode: stationCode).isEmpty {
            return .throughService
        }
        // Catalog junction aliases may differ from the package station code.
        for pattern in JapanThroughServices.patterns {
            for (a, b) in zip(pattern.legs, pattern.legs.dropFirst()) {
                let firstIDs = [a.lineID] + (a.reverseLineID.map { [$0] } ?? [])
                let secondIDs = [b.lineID] + (b.reverseLineID.map { [$0] } ?? [])
                if (firstIDs.contains(from.id) && secondIDs.contains(to.id))
                    || (firstIDs.contains(to.id) && secondIDs.contains(from.id)) {
                    return .throughService
                }
            }
        }
        if from.kind == "jr_conventional", to.kind == "jr_conventional" { return .network }
        if from.kind == "shinkansen", to.kind == "shinkansen" { return .network }
        if let operatorName = from.operator, !operatorName.isEmpty,
           operatorName == to.operator, from.kind == to.kind,
           from.kind == "private" || from.kind == "third_sector" {
            return .network
        }
        return .none
    }

    public static func allows(from: CompactPackage.Line, to: CompactPackage.Line,
                              atStationCode stationCode: String) -> Bool {
        link(from: from, to: to, atStationCode: stationCode) != .none
    }
}
