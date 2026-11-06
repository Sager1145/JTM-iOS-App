import Foundation
import RailCore

/// Everything a detector reads.
public struct DetectionContext {
    public var data: AreaData
    public var scope: AreaScope
    /// Rides already selected as crossing the area (may be empty).
    public var trains: [Train]
    public var thresholds: AreaThresholds

    public init(data: AreaData, scope: AreaScope, trains: [Train] = [], thresholds: AreaThresholds = .default) {
        self.data = data; self.scope = scope; self.trains = trains; self.thresholds = thresholds
    }
}

/// Runs the six detectors over one area.
public enum AreaProblems {
    public static func detect(scope: AreaScope, data: AreaData, trains: [Train] = [],
                              thresholds: AreaThresholds = .default, kinds: Set<Problem.Kind> = Set(Problem.Kind.allCases)) -> [Problem] {
        let context = DetectionContext(data: data, scope: scope, trains: trains, thresholds: thresholds)
        var problems: [Problem] = []
        if kinds.contains(.missingJunction) { problems += MissingJunctionDetector.detect(context) }
        if kinds.contains(.lostHistoryStamp) { problems += LostHistoryStampDetector.detect(context) }
        if kinds.contains(.uncertifiedPairedTrack) { problems += UncertifiedPairedTrackDetector.detect(context) }
        if kinds.contains(.stationDotOffLine) { problems += StationDotOffLineDetector.detect(context) }
        if kinds.contains(.overRoundedCorner) { problems += OverRoundedCornerDetector.detect(context) }
        if kinds.contains(.pairedDirectionSide) { problems += PairedDirectionSideDetector.detect(context) }
        return problems
    }

    static func today() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static func format(_ metres: Double) -> String { String(format: "%.1f m", metres) }
}
