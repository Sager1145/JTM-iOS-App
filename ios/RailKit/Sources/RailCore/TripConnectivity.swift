public enum TripConnectivity {
    public enum Link: String, Equatable, Sendable {
        case sameLine, throughService, network, none
    }

    /// Whether one train can continue between these lines at the junction.
    public static func link(from: CompactPackage.Line, to: CompactPackage.Line,
                            atStationCode stationCode: String, on date: String? = nil) -> Link {
        link(from: from, to: to, atStationCode: stationCode, on: date, patterns: JapanThroughServices.patterns)
    }

    static func link(from: CompactPackage.Line, to: CompactPackage.Line,
                     atStationCode stationCode: String, on date: String?,
                     patterns: [JapanThroughServices.Pattern],
                     connectors: [JapanThroughServices.Connector] = JapanThroughServices.connectors) -> Link {
        if from.id == to.id { return .sameLine }
        if !JapanThroughServices.continuationCodes(
            fromLineID: from.id, toLineID: to.id, atStationCode: stationCode,
            on: date, patterns: patterns, connectors: connectors).isEmpty {
            return .throughService
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
                              atStationCode stationCode: String, on date: String? = nil) -> Bool {
        link(from: from, to: to, atStationCode: stationCode, on: date) != .none
    }
}
