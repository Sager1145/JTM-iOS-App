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
        // Catalog junction aliases may differ from the package station code,
        // so also accept adjacent legs — but only at the station where those
        // legs actually join. Two legs that run side by side (総武線-3 and
        // 東海道線 between 東京 and 品川) must not join at an intermediate
        // station such as 新橋.
        for pattern in JapanThroughServices.patterns {
            for (a, b) in zip(pattern.legs, pattern.legs.dropFirst()) {
                let firstIDs = [a.lineID] + (a.reverseLineID.map { [$0] } ?? [])
                let secondIDs = [b.lineID] + (b.reverseLineID.map { [$0] } ?? [])
                let joins: Set<String> = [a.toStationCode, b.fromStationCode]
                guard joins.contains(stationCode) else { continue }
                if (firstIDs.contains(from.id) && secondIDs.contains(to.id))
                    || (firstIDs.contains(to.id) && secondIDs.contains(from.id)) {
                    return .throughService
                }
            }
        }
        func isTerminal(_ line: CompactPackage.Line) -> Bool {
            !line.isLoop && (line.stations.first?.id == stationCode || line.stations.last?.id == stationCode)
        }
        // A station both rows merely pass through is an interchange, not a
        // track junction (for example, 東横線 × 大井町線 at 自由が丘).
        guard from.name == to.name || isTerminal(from) || isTerminal(to) else { return .none }
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
