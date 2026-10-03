import RailCore

/// Native map label hierarchy. Connection count is a navigational importance
/// signal, not a claim about passenger volume or a station's official rank.
public enum StationLabelVisibility {
    /// Sparse journeys can offer all calls to collision placement. Limited
    /// expresses get a little more room; long stopping lists still thin by hub.
    public static func preservesSelectedCalls(trainType: String?, country: String, callCount: Int) -> Bool {
        let service = Train(id: "", number: "", trainType: trainType,
                            origin: "", destination: "", stops: [], region: country)
        if TrainServiceBranding.isLimitedExpress(service) { return callCount <= 20 }
        let type = (trainType ?? "").lowercased()
        if ["普通", "各駅停車", "各停", "local", "all stops"].contains(where: type.contains) {
            return false
        }
        return callCount <= 12
    }

    public static func selectedRideMinimumMapLibreZoom(
        role: String, preservesCalls: Bool, densityMinimum: Double?,
        lineCount: Int, isNetworkTerminal: Bool
    ) -> Double? {
        if role == "terminal" || role == "xday" { return nil }
        if role == "pass" { return densityMinimum }
        if preservesCalls { return nil }
        guard let densityMinimum else { return nil }
        guard lineCount > 1 || isNetworkTerminal else { return densityMinimum }
        return min(densityMinimum, minimumMapLibreZoom(
            lineCount: lineCount, isTerminal: isNetworkTerminal))
    }

    /// Actual calls always precede pass-through names, even at a busy hub.
    public static func rideLabelPriority(role: String, lineCount: Int, isNetworkTerminal: Bool) -> Int {
        if role == "terminal" || role == "xday" { return 3_000 }
        let rolePriority = role == "pass" ? 1_000 : 2_000
        return rolePriority + min(max(lineCount, 0), 50) * 10 + (isNetworkTerminal ? 1 : 0)
    }

    public static func minimumMapLibreZoom(lineCount: Int, isTerminal: Bool) -> Double {
        // Major hubs may label even a national overview; the renderer still
        // requires their railway to be drawn and their text to fit.
        if lineCount >= 4 { return 0 }
        if lineCount >= 3 { return 8 }
        if lineCount >= 2 { return 9 }
        return isTerminal ? 10 : 12
    }
}
