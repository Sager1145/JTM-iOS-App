import RailCore

enum StopTimingStatus {
    @MainActor
    static func localizedLabel(
        scheduled: String?, actual: String?, localization: AppLocalization
    ) -> String? {
        guard let minutes = offsetMinutes(scheduled: scheduled, actual: actual) else { return nil }
        if minutes == 0 { return localization.text("ios.editor.actualOnTime") }
        return localization.text(minutes > 0
            ? "ios.editor.actualDelayed" : "ios.editor.actualEarly", params: ["minutes": .number(Double(abs(minutes)))])
    }

    private static func offsetMinutes(scheduled: String?, actual: String?) -> Int? {
        guard case .valid(_, let planned) = EditorTime.parseTime(scheduled),
              case .valid(_, let observed) = EditorTime.parseTime(actual)
        else { return nil }
        return observed.serviceMinutes - planned.serviceMinutes
    }
}
