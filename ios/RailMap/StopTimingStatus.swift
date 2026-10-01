import RailCore

enum StopTimingStatus {
    @MainActor
    static func localizedLabel(
        scheduled: String?, actual: String?, localization: AppLocalization
    ) -> String? {
        guard let minutes = offsetMinutes(scheduled: scheduled, actual: actual) else { return nil }
        if minutes == 0 { return localization.editorText("ios.editor.actualOnTime") }
        return localization.editorText(minutes > 0
            ? "ios.editor.actualDelayed" : "ios.editor.actualEarly",
            ["minutes": .number(Double(abs(minutes)))])
    }

    static func label(scheduled: String?, actual: String?) -> String? {
        guard let minutes = offsetMinutes(scheduled: scheduled, actual: actual) else { return nil }
        if minutes == 0 { return "定刻" }
        return minutes > 0 ? "\(minutes)分遅れ" : "\(-minutes)分早い"
    }

    private static func offsetMinutes(scheduled: String?, actual: String?) -> Int? {
        guard case .valid(_, let planned) = EditorTime.parseTime(scheduled),
              case .valid(_, let observed) = EditorTime.parseTime(actual)
        else { return nil }
        return observed.serviceMinutes - planned.serviceMinutes
    }
}
