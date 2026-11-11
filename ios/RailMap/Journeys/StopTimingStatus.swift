import RailCore

enum StopTimingStatus {
    @MainActor
    static func localizedLabel(
        scheduled: String?, actual: String?, localization: AppLocalization
    ) -> String? {
        guard let minutes = offsetMinutes(scheduled: scheduled, actual: actual) else { return nil }
        return offsetLabel(minutes, localization: localization)
    }

    @MainActor
    private static func offsetLabel(_ minutes: Int, localization: AppLocalization) -> String {
        if minutes == 0 { return localization.text("ios.editor.actualOnTime") }
        return localization.text(minutes > 0
            ? "ios.editor.actualDelayed" : "ios.editor.actualEarly", params: ["minutes": .number(Double(abs(minutes)))])
    }

    /// One side of a trip as the card and the detail print it.
    ///
    /// `shown` is the effective clock: the actual one when recorded, else the
    /// scheduled one. `scheduled` is set only when an actual exists AND
    /// differs, which is when the scheduled clock is drawn struck through.
    /// `offsetMinutes` is nil when there is nothing to compare.
    struct TimeDisplay: Equatable {
        var shown: String
        var scheduled: String?
        var offsetMinutes: Int?

        var isLate: Bool { (offsetMinutes ?? 0) > 0 }
        var isEarly: Bool { (offsetMinutes ?? 0) < 0 }
        var isOnTime: Bool { offsetMinutes == 0 }
    }

    /// Blank strings count as missing. `nil` when neither clock exists.
    static func timeDisplay(scheduled: String?, actual: String?) -> TimeDisplay? {
        let plan = scheduled.flatMap { $0.isEmpty ? nil : $0 }
        let real = actual.flatMap { $0.isEmpty ? nil : $0 }
        guard let real else { return plan.map { TimeDisplay(shown: $0) } }
        guard let plan, let minutes = offsetMinutes(scheduled: plan, actual: real) else {
            return TimeDisplay(shown: real)
        }
        return TimeDisplay(
            shown: real, scheduled: minutes == 0 ? nil : plan, offsetMinutes: minutes)
    }

    /// "+5 min", "−5 min" or "On time"; nil when there is no comparison.
    @MainActor
    static func markerText(_ display: TimeDisplay, localization: AppLocalization) -> String? {
        guard let minutes = display.offsetMinutes else { return nil }
        if minutes == 0 { return localization.text("ios.editor.actualOnTime") }
        return localization.text(
            minutes > 0 ? "ios.delay.markerLate" : "ios.delay.markerEarly",
            params: ["minutes": .number(Double(abs(minutes)))])
    }

    /// The SF Symbol that backs the sign, so colour is never the only cue.
    static func markerSymbol(_ display: TimeDisplay) -> String {
        if display.isLate { return "clock.badge.exclamationmark" }
        if display.isEarly { return "clock.arrow.2.circlepath" }
        return "checkmark.circle"
    }

    /// "Departure 10:35, scheduled 10:30, 5 min late".
    @MainActor
    static func spoken(
        role: String?, _ display: TimeDisplay, localization: AppLocalization
    ) -> String {
        var parts = [[role, display.shown].compactMap { $0 }.joined(separator: " ")]
        if let scheduled = display.scheduled {
            parts.append(localization.text("ios.delay.scheduledSpoken", params: ["time": .string(scheduled)]))
        }
        if let minutes = display.offsetMinutes {
            parts.append(offsetLabel(minutes, localization: localization))
        }
        return parts.joined(separator: ", ")
    }

    private static func offsetMinutes(scheduled: String?, actual: String?) -> Int? {
        guard case .valid(_, let planned) = EditorTime.parseTime(scheduled),
              case .valid(_, let observed) = EditorTime.parseTime(actual)
        else { return nil }
        var difference = observed.serviceMinutes - planned.serviceMinutes
        // 23:58 planned and 00:03 observed is +5 across midnight, not -1435.
        if difference > 720 { difference -= 1440 } else if difference < -720 { difference += 1440 }
        return difference
    }
}
