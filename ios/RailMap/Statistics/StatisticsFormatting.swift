import Foundation
import RailCore
import SwiftUI

/// The number spellings the 統計 panel uses, ported from `app-stats-render.js`.
///
/// These are presentation, not aggregation — nothing here decides what a
/// kilometre counts towards — but they are ported rather than reinvented,
/// because "8.6 km" reading as "9" on one platform and "8.6" on the other is
/// exactly the kind of difference nobody notices until the two are compared
/// side by side.
enum StatisticsFormat {

    /// `formatStatKm`.
    ///
    /// Short distances keep one decimal: a two-digit figure rounded to a whole
    /// kilometre loses a meaningful share of itself (8.6 km reading as "9"),
    /// while anything from 100 km up is precise enough whole.
    ///
    /// The rounding is done before formatting rather than left to the format
    /// style: `Math.round` breaks ties away from zero and
    /// `FloatingPointFormatStyle` breaks them to even, so `0.05` and `100.5`
    /// would otherwise disagree with the web app in their last digit.
    static func km(_ value: Double) -> String {
        let v = value.isFinite ? value : 0
        if abs(v) < 100 {
            let rounded = (v * 10).rounded(.toNearestOrAwayFromZero) / 10
            return rounded.formatted(.number.precision(.fractionLength(1)))
        }
        return v.rounded(.toNearestOrAwayFromZero)
            .formatted(.number.precision(.fractionLength(0)))
    }

    /// `formatStatPct` — a percentage already on the 0–100 scale.
    ///
    /// One decimal only in the (0, 10) band, where a whole number would round
    /// a real 0.4% coverage away to "0". Not locale-grouped, because the
    /// JavaScript spells it with `String(...)` rather than `toLocaleString`,
    /// and no percentage is large enough for a group separator anyway.
    ///
    /// `String(format:)` is `toFixed(1)` here, despite the two disagreeing in
    /// general: they differ only on an exact tie, and at one fraction digit a
    /// tie would have to be exactly `(2k+1)/20`. Twenty has a factor of five,
    /// so no finite `Double` is ever exactly that — the case where `printf`
    /// rounds to even and `toFixed` rounds up is unreachable. (It is very much
    /// reachable at other digit counts, which is why `RailCore` carries a real
    /// `toFixed`; that one is internal to the package.)
    static func percent(_ value: Double) -> String {
        let v = value.isFinite ? value : 0
        if v > 0 && v < 10 { return String(format: "%.1f", v) }
        return String(Int(v.rounded(.toNearestOrAwayFromZero)))
    }

    /// `formatStatDuration` — hours and minutes, or bare minutes under an hour.
    @MainActor
    static func duration(_ minutes: Double, _ localization: AppLocalization) -> String {
        let split = hoursMinutes(minutes)
        if split.hours > 0 {
            return localization.text(
                "fmt.duration",
                params: ["h": .number(Double(split.hours)), "m": .number(Double(split.minutes))])
        }
        return localization.text(
            "fmt.durationM", params: ["m": .number(Double(split.minutes))])
    }

    /// The same split, unformatted.
    ///
    /// The ticket face sets a duration as 「268 時間 40 分」 with the hours at
    /// 大字 and the minutes at 24 px — two figures at two sizes, which no
    /// single formatted string can be cut back into. So the arithmetic lives
    /// here and ``duration(_:_:)`` spells it, rather than the face doing its
    /// own division: 「197 時間 9 分」 rounding one way on the card and another
    /// in the sentence beside it is the exact class of drift this whole file
    /// exists to prevent.
    static func hoursMinutes(_ minutes: Double) -> (hours: Int, minutes: Int) {
        let safe = minutes.isFinite ? minutes : 0
        let rounded = safe.rounded(.toNearestOrAwayFromZero)
        let h = (rounded / 60).rounded(.down)
        let m = rounded - h * 60
        return (Int(h), Int(m))
    }

    /// The placeholder every daily figure reads as while the scope is 全部.
    ///
    /// Deliberately not `0`: a zero is a result, and "you rode nothing that
    /// day" is not what the combined view means (§5.7).
    static let unset = "--"

    /// `statsCompanyLabel` — the short operator label the per-line rows are
    /// grouped by (東日本旅客鉄道 → JR東日本), falling back to the raw N02 name.
    static func companyLabel(_ operatorName: String) -> String {
        guard !operatorName.isEmpty else { return "" }
        return OperatorBranding.companyLabel(operatorName)
    }

    /// `STATS_LINE_COLLATOR` — numeric, case/accent-insensitive, ja/en.
    ///
    /// `localizedStandardCompare` is Foundation's nearest equivalent: it is
    /// numeric-aware, so 1号線 < 2号線 < 10号線 rather than 1 < 10 < 2, and it
    /// folds case. It is not the same collator, so an exotic tie can order
    /// differently from the web app; the rows and their numbers are the same
    /// either way.
    static func linesPrecede(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }
}


@MainActor
extension StatisticsFormat {
    struct ServiceRow: Identifiable {
        let key: String
        let group: Statistics.ServiceGroup
        var id: String { key }
    }

    static func serviceRows(_ services: Statistics.ServiceGroups) -> [ServiceRow] {
        [ServiceRow(key: "stat.hsr", group: services.hsr),
         ServiceRow(key: "stat.ltdexp", group: services.ltd),
         ServiceRow(key: "stat.othertrains", group: services.other)]
    }

    static func dayLabel(_ date: String, localization: AppLocalization) -> String {
        guard let point = RecordDate.date(from: date) else { return date }
        return point.formatted(.dateTime.year().month(.abbreviated).day().locale(localization.locale))
    }

    private static func symbolCalendar(_ localization: AppLocalization) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = localization.locale
        return calendar
    }

    static func monthName(_ month: Int, localization: AppLocalization) -> String {
        let symbols = symbolCalendar(localization).monthSymbols
        guard month >= 1, month <= symbols.count else { return month.formatted() }
        return symbols[month - 1]
    }

    static func weekdayLabel(_ weekday: Int, short: Bool, localization: AppLocalization) -> String {
        let calendar = symbolCalendar(localization)
        let symbols = short ? calendar.shortWeekdaySymbols : calendar.weekdaySymbols
        guard weekday >= 1, weekday <= symbols.count else { return weekday.formatted() }
        return symbols[weekday - 1]
    }

    static func journeyCount(_ count: Int, localization: AppLocalization) -> String {
        localization.text("stat.trains", params: ["n": .number(Double(count))])
    }

    static func rideCount(_ count: Int, localization: AppLocalization) -> String {
        localization.text("stat.rides", params: ["n": .number(Double(count))])
    }

    static func placeName(_ name: String, in recordedRegion: Region? = nil,
                          region: Region?, localization: AppLocalization) -> String {
        localization.placeName(name, region: recordedRegion ?? region ?? localization.regionNaming(name))
    }

    static func sectionLabel(_ row: Statistics.TopRow, region: Region?, localization: AppLocalization) -> String {
        "\(placeName(row.from, region: region, localization: localization)) ↔ \(placeName(row.to, region: region, localization: localization))"
    }

    static func routeLabel(_ tally: PassportStatistics.Tally, region: Region?, localization: AppLocalization) -> String {
        "\(placeName(tally.name, in: tally.region, region: region, localization: localization)) ↔ \(placeName(tally.pair ?? "", in: tally.region, region: region, localization: localization))"
    }

    static func regionName(_ region: Region, localization: AppLocalization) -> String {
        localization.text(region.localizationKey, fallback: region.fallbackName)
    }

    static func flag(_ region: Region) -> String {
        switch region {
        case .jp: "🇯🇵"
        case .tw: "🇹🇼"
        case .hk: "🇭🇰"
        case .mo: "🇲🇴"
        case .kr: "🇰🇷"
        case .cn: "🇨🇳"
        }
    }

    static func spelledDate(_ date: String, localization: AppLocalization) -> String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            let key = Dates.dateLabelKey(date)
            return localization.text(key, fallback: key)
        }
        return localization.text("ios.ticket.date", params: [
            "y": .string(String(parts[0])), "m": .string(String(parts[1])), "d": .string(String(parts[2])),
        ])
    }

    private static func ticketDate(_ date: String) -> String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return date }
        let padded = parts.dropFirst().map { $0 < 10 ? "-\($0)" : "\($0)" }
        return ([String(parts[0])] + padded).joined(separator: ".")
    }

    static func issuedSpan(trains: [Train], localization: AppLocalization) -> String? {
        let dated = Dates.availableDates(trains).filter { $0 != Dates.undated }
        guard let first = dated.first, let last = dated.last else { return nil }
        guard first != last else {
            return localization.text("ios.ticket.spanDay", params: [
                "date": .string(spelledDate(first, localization: localization))])
        }
        return localization.text("ios.ticket.span", params: [
            "from": .string(spelledDate(first, localization: localization)),
            "to": .string(spelledDate(last, localization: localization))])
    }

    static func ticketScope(trains: [Train], groupID: String?, scopeName: String?,
                            region: Region?, localization: AppLocalization) -> String {
        let groupName = trains.first { $0.journeyGroup?.id == groupID && $0.journeyGroup != nil }?.journeyGroup?.name
        return groupName ?? scopeName ?? region.map { regionName($0, localization: localization) }
            ?? localization.text("ios.region.all", fallback: "All regions")
    }

    static func ticketIssued(localization: AppLocalization) -> String {
        localization.text("ios.ticket.issued", params: [
            "date": .string(ticketDate(RecordDate.text(from: Date())))])
    }

    static func ticketSpoken(_ value: String, _ unit: String) -> String {
        unit.isEmpty ? value : "\(value) \(unit)"
    }

    static func ticketRideTime(_ minutes: Double, localization: AppLocalization) -> TicketDisplay {
        let split = hoursMinutes(minutes)
        return .duration(label: localization.text("ios.rideTime", fallback: "Ride time"),
                         hours: split.hours, minutes: split.minutes,
                         hourUnit: localization.text("ios.ticket.unit.hours"),
                         minuteUnit: localization.text("ios.ticket.unit.minutes"),
                         spoken: duration(minutes, localization))
    }

    struct CoverageReading {
        var text: String
        var bar: String
        var fraction: Double
        var spoken: String
        var known: Bool
    }

    static func coverageReading(ridden: Double, denominator: Double, fraction: Double?,
                                localization: AppLocalization) -> CoverageReading {
        guard let fraction else {
            let unknown = localization.text("ios.routeGuide.unknownDistance")
            return CoverageReading(text: unknown, bar: unknown, fraction: 0, spoken: unknown, known: false)
        }
        let text = percent(fraction * 100)
        return CoverageReading(text: text, bar: "\(text)%", fraction: fraction,
                               spoken: localization.text("ios.stats.coverageA11y", params: [
                                "pct": .string(percent(denominator > 0 ? 100 * ridden / denominator : 0)),
                                "ridden": .string(km(ridden)), "total": .string(km(denominator)),
                               ]), known: true)
    }
}
