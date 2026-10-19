public enum TripConnectivity {
    public enum Link: String, Equatable, Sendable {
        case sameLine, throughService, none
    }

    /// Display relationship between rows; a through-service label is not physical proof.
    public static func link(from: CompactPackage.Line, to: CompactPackage.Line,
                            atStationCode stationCode: String, on date: String? = nil,
                            patterns: [JapanThroughServices.Pattern],
                            connectors: [JapanThroughServices.Connector]) -> Link {
        if from.id == to.id { return .sameLine }
        if !JapanThroughServices.continuationCodes(
            fromLineID: from.id, toLineID: to.id, atStationCode: stationCode,
            on: date, patterns: patterns, connectors: connectors).isEmpty {
            return .throughService
        }
        // Compact rows and through-service labels contain no reviewed
        // cross-track junction evidence. Shared names, operators, terminal
        // positions and railway kinds cannot supply physical permission.
        return .none
    }

    /// Same surveyed row only. Metadata never grants a physical connection.
    public static func allows(from: CompactPackage.Line, to: CompactPackage.Line,
                              atStationCode stationCode: String, on date: String? = nil) -> Bool {
        from.id == to.id
    }
}
