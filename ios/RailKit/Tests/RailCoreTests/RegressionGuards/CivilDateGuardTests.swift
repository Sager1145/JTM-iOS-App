import Foundation
import Testing
@testable import RailCore

/// One shared civil-date helper (`CivilDate`). The five month-length / leap-year
/// copies and the two days-since-1970 copies it replaced are kept below VERBATIM
/// (renamed `Legacy...`) and the helper must agree with each for every year and
/// month. The parsers that call it are pinned on representative and malformed
/// inputs. `CivilDate` takes no calendar, locale or time zone, so none of these
/// answers can depend on the device; the source guard keeps it that way.
@Suite("RegressionGuardCivilDate")
struct RegressionGuardCivilDate {

    // MARK: Verbatim legacy copies

    private static func legacyBranding(_ month: Int, year: Int) -> Int {
        switch month {
        case 2:
            let leapYear = year.isMultiple(of: 400)
                || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
            return leapYear ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    private static func legacyTopology(year: Int, month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    private static func legacyEditor(year: Int, month: Int) -> Int {
        func isLeapYear(_ year: Int) -> Bool {
            if year % 400 == 0 { return true }
            if year % 100 == 0 { return false }
            return year % 4 == 0
        }
        switch month {
        case 1, 3, 5, 7, 8, 10, 12:
            return 31
        case 4, 6, 9, 11:
            return 30
        case 2:
            return isLeapYear(year) ? 29 : 28
        default:
            return 0
        }
    }

    private static func legacyPatterns(year: Int, month: Int) -> Int {
        let leapYear = year.isMultiple(of: 400)
            || (year.isMultiple(of: 4) && year.isMultiple(of: 100) == false)
        return [
            31, leapYear ? 29 : 28, 31, 30, 31, 30,
            31, 31, 30, 31, 30, 31,
        ][month - 1]
    }

    private static func legacyDaysFromCivilTopology(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private static func legacyDaysFromCivilDates(year: Int, month: Int, day: Int) -> Int {
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146097 + dayOfEra - 719468
    }

    private static func legacyCivilFromDays(_ serial: Int) -> (year: Int, month: Int, day: Int) {
        let z = serial + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let dayOfEra = z - era * 146097
        let yearOfEra =
            (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365
        let year = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp + (mp < 10 ? 3 : -9)
        return (year + (month <= 2 ? 1 : 0), month, day)
    }

    // MARK: Helper equals every legacy copy

    @Test func monthLengthsMatchEveryLegacyCopy() {
        for year in -800...12_000 {
            for month in 1...12 {
                let shared = CivilDate.daysInMonth(year: year, month: month)
                #expect(shared == Self.legacyBranding(month, year: year), "branding \(year)-\(month)")
                #expect(shared == Self.legacyTopology(year: year, month: month), "topology \(year)-\(month)")
                #expect(shared == Self.legacyEditor(year: year, month: month), "editor \(year)-\(month)")
                #expect(shared == Self.legacyPatterns(year: year, month: month), "patterns \(year)-\(month)")
            }
        }
        // Only the editor copy answered a month outside 1...12 (0); every caller guards the month first.
        for month in [-1, 0, 13, 99] {
            #expect(CivilDate.daysInMonth(year: 2024, month: month) == 0)
        }
    }

    @Test func leapYearRule() {
        for (year, leap) in [(1900, false), (2000, true), (2023, false), (2024, true),
                             (2100, false), (2400, true), (4, true), (1, false), (0, true), (-4, true)] {
            #expect(CivilDate.isLeapYear(year) == leap, "\(year)")
        }
    }

    @Test func serialsMatchLegacyAndRoundTrip() {
        for year in stride(from: -400, through: 3_000, by: 1) {
            for month in 1...12 {
                for day in [1, 15, CivilDate.daysInMonth(year: year, month: month)] {
                    let serial = CivilDate.daysFromCivil(year: year, month: month, day: day)
                    #expect(serial == Self.legacyDaysFromCivilTopology(year: year, month: month, day: day))
                    #expect(serial == Self.legacyDaysFromCivilDates(year: year, month: month, day: day))
                    let back = CivilDate.civilFromDays(serial)
                    let old = Self.legacyCivilFromDays(serial)
                    #expect(back.year == old.year && back.month == old.month && back.day == old.day)
                    #expect(back.year == year && back.month == month && back.day == day)
                }
            }
        }
        #expect(CivilDate.daysFromCivil(year: 1970, month: 1, day: 1) == 0)
        #expect(CivilDate.daysFromCivil(year: 2000, month: 3, day: 1) == 11_017)
    }

    // MARK: Callers keep their own syntax rules

    @Test func topologyDayNumberPins() {
        #expect(RailTopologyFormat.dayNumber(ofISODate: "1800-01-01") == 1)
        #expect(RailTopologyFormat.dayNumber(ofISODate: "1800-01-02") == 2)
        #expect(RailTopologyFormat.dayNumber(ofISODate: "1799-12-31") == nil)
        #expect(RailTopologyFormat.dayNumber(ofISODate: "2024-02-29") == 81_874)
        #expect(RailTopologyFormat.dayNumber(ofISODate: "2023-02-29") == nil)
        #expect(RailTopologyFormat.dayNumber(ofISODate: "1900-02-29") == nil)
        #expect(RailTopologyFormat.dayNumber(ofISODate: "2000-02-29") != nil)
        #expect(RailTopologyFormat.dayNumber(ofISODate: "2024-04-31") == nil)
        #expect(RailTopologyFormat.dayNumber(ofISODate: "2024-13-01") == nil)
        #expect(RailTopologyFormat.dayNumber(ofISODate: "2024-00-10") == nil)
        #expect(RailTopologyFormat.dayNumber(ofISODate: "2024-01-00") == nil)
        for bad in ["", "2024-1-01", "2024/01/01", "24-01-01", "2024-01-011", "2024-01", "abcd-01-01", "2024-01-01 "] {
            #expect(RailTopologyFormat.dayNumber(ofISODate: bad) == nil, "\(bad)")
        }
    }

    @Test func editorDateParsePins() {
        func valid(_ y: Int, _ m: Int, _ d: Int) -> ServiceDateParse {
            .valid(year: y, month: m, day: d, canonical: String(format: "%04d-%02d-%02d", y, m, d))
        }
        #expect(EditorTime.parseDate("2024-02-29") == valid(2024, 2, 29))
        #expect(EditorTime.parseDate("2024/02/29") == valid(2024, 2, 29))
        #expect(EditorTime.parseDate("2023-02-29") == .invalid(raw: "2023-02-29"))
        #expect(EditorTime.parseDate("1900-02-29") == .invalid(raw: "1900-02-29"))
        #expect(EditorTime.parseDate("2024-06-31") == .invalid(raw: "2024-06-31"))
        #expect(EditorTime.parseDate("2024-12-31") == valid(2024, 12, 31))
        #expect(EditorTime.parseDate("2024-13-01") == .invalid(raw: "2024-13-01"))
        #expect(EditorTime.parseDate("2024-00-01") == .invalid(raw: "2024-00-01"))
        #expect(EditorTime.parseDate("2024-01-00") == .invalid(raw: "2024-01-00"))
        #expect(EditorTime.parseDate("2024-01/01") == .invalid(raw: "2024-01/01"))
        #expect(EditorTime.parseDate("") == .unset)
        #expect(EditorTime.parseDate(nil) == .unset)
        // Flexible input: defaults the year and still enforces month length.
        #expect(EditorTime.parseDateInput("2/29", defaultYear: 2024) == valid(2024, 2, 29))
        #expect(EditorTime.parseDateInput("2/29", defaultYear: 2023) == .invalid(raw: "2/29"))
        #expect(EditorTime.parseDateInput("20240229", defaultYear: 2000) == valid(2024, 2, 29))
        // The editor's strict path has no year floor (unlike the validity parsers); unchanged by the refactor.
        #expect(EditorTime.parseDateInput("0000-01-01", defaultYear: 2000) == valid(0, 1, 1))
    }

    @Test func servicePatternValidityDayPins() {
        typealias Day = TrainServicePatterns.Pattern.GregorianDay
        for good in ["2024-02-29", "2000-02-29", "2023-12-31", "0001-01-01", "9999-12-31"] {
            #expect(Day(good) != nil, "\(good)")
        }
        for bad in ["2023-02-29", "1900-02-29", "2024-04-31", "2024-00-10", "2024-13-10",
                    "2024-01-00", "0000-01-01", "2024-1-01", "2024/01/01", "2024-01-011", "",
                    "２０２４-01-01", "+024-01-01"] {
            #expect(Day(bad) == nil, "\(bad)")
        }
    }

    @Test func dateShimAddDaysPins() {
        #expect(Dates.addDays("2024-02-28", 1) == "2024-02-29")
        #expect(Dates.addDays("2023-02-28", 1) == "2023-03-01")
        #expect(Dates.addDays("2023-12-31", 1) == "2024-01-01")
        #expect(Dates.addDays("2024-03-01", -1) == "2024-02-29")
        #expect(Dates.addDays("1900-02-28", 1) == "1900-03-01")
        #expect(Dates.addDays("not-a-date", 1) == nil)
        #expect(Dates.addDays(nil, 1) == nil)
    }

    // MARK: Source guard — no second civil-date implementation

    private static let sources: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RegressionGuards
            .deletingLastPathComponent() // RailCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // RailKit
            .appendingPathComponent("Sources/RailCore")
    }()

    private static func read(_ path: String) -> String {
        (try? String(contentsOf: sources.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    @Test func callersUseTheSharedHelperAndCarryNoSecondParser() {
        let files = ["Identity/TrainServiceBranding.swift", "Topology/RailTopologyFormat.swift",
                     "Editor/EditorTime.swift", "Timetable/TrainServicePatterns.swift",
                     "Utilities/Dates.swift"]
        for file in files {
            let text = Self.read(file)
            #expect(!text.isEmpty, "\(file) not readable")
            #expect(text.contains("CivilDate."), "\(file) must use CivilDate")
            for marker in ["func daysInMonth", "func isLeapYear", "func daysFromCivil",
                           "func civilFromDays", "isMultiple(of: 400)", "% 400", "let leapYear"] {
                #expect(!text.contains(marker), "\(file) re-implements civil-date maths (\(marker))")
            }
        }
        let shared = Self.read("Utilities/CivilDate.swift")
        #expect(shared.contains("enum CivilDate"))
        for forbidden in ["Calendar", "TimeZone", "DateFormatter", "Locale"] {
            let code = shared.split(separator: "\n").filter { !$0.hasPrefix("///") }.joined(separator: "\n")
            #expect(!code.contains(forbidden), "CivilDate must stay pure integer maths (\(forbidden))")
        }
    }
}
