import Foundation
import RailCore

/// How a stored, zone-free `YYYY-MM-DD` record date is shown to the reader.
///
/// The text depends only on the stored string, the style and the app's own
/// language. It never reads the device's time zone, calendar, locale or clock:
/// the weekday is computed from the civil date by integer arithmetic and the
/// patterns are written out here, so a phone set to another zone, a Japanese
/// era calendar or another language cannot change a single character.
///
/// The year is always shown. There is no "Today" or "Tomorrow".
public enum RecordDate {

    public enum LabelStyle: Sendable, Hashable {
        /// Weekday, year, month, day.
        case full
        /// Year, month, day; the shortest unambiguous form per language.
        case compact
    }

    /// The text for a stored record date.
    ///
    /// - nil, empty and `Dates.undated`: the language's "No date" word.
    /// - `Dates.allDates`: the language's "All dates" word.
    /// - Non-padded input such as `2026-11-5` is accepted.
    /// - Anything that is not a real calendar date is returned unchanged.
    public static func label(
        _ date: String?,
        _ style: LabelStyle,
        language: Localization.Language
    ) -> String {
        guard let date, !date.isEmpty, date != Dates.undated else {
            return words(language).noDate
        }
        if date == Dates.allDates { return words(language).allDates }
        guard let (y, m, d) = parse(date) else { return date }

        switch language {
        case .en:
            let day = "\(months[m - 1]) \(d), \(y)"
            return style == .full ? "\(weekdaysEn[weekday(y, m, d)]), \(day)" : day
        case .ja:
            let day = "\(y)年\(m)月\(d)日"
            return style == .full ? "\(day)(\(weekdaysJa[weekday(y, m, d)]))" : day
        case .zhHans:
            let day = "\(y)年\(m)月\(d)日"
            return style == .full ? "\(day) 周\(weekdaysZh[weekday(y, m, d)])" : day
        case .zhHant:
            let day = "\(y)年\(m)月\(d)日"
            return style == .full ? "\(day)週\(weekdaysZh[weekday(y, m, d)])" : day
        }
    }

    // MARK: - words

    private struct Words { let noDate: String; let allDates: String }

    private static func words(_ language: Localization.Language) -> Words {
        switch language {
        case .en: return Words(noDate: "No date", allDates: "All dates")
        case .ja: return Words(noDate: "日付なし", allDates: "すべての日付")
        case .zhHans: return Words(noDate: "无日期", allDates: "全部日期")
        case .zhHant: return Words(noDate: "無日期", allDates: "全部日期")
        }
    }

    // Index 0 is Sunday.
    private static let weekdaysEn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let weekdaysJa = ["日", "月", "火", "水", "木", "金", "土"]
    private static let weekdaysZh = ["日", "一", "二", "三", "四", "五", "六"]
    private static let months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    // MARK: - civil date arithmetic

    private static func parse(_ s: String) -> (Int, Int, Int)? {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }),
              parts[0].utf8.count == 4, parts[1].utf8.count <= 2, parts[2].utf8.count <= 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1, d <= daysIn(y, m)
        else { return nil }
        return (y, m, d)
    }

    private static func daysIn(_ y: Int, _ m: Int) -> Int {
        switch m {
        case 2: return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// 0 = Sunday. Days since 1970-01-01 (a Thursday), proleptic Gregorian.
    private static func weekday(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let yy = m <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146097 + doe - 719468
        return ((days + 4) % 7 + 7) % 7
    }
}
