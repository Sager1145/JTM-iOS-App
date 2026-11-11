import Foundation
import RailCore
import Testing

@testable import RailPresentation

@Suite("TripDateLabel", .serialized)
struct TripDateLabelTests {
    typealias L = Localization.Language

    // date, then [en, ja, zhHans, zhHant] for full and compact.
    static let cases: [(String, [String], [String])] = [
        ("2026-11-05",
         ["Thu, Nov 5, 2026", "2026年11月5日(木)", "2026年11月5日 周四", "2026年11月5日 週四"],
         ["Nov 5, 2026", "2026年11月5日", "2026年11月5日", "2026年11月5日"]),
        ("2026-11-5",
         ["Thu, Nov 5, 2026", "2026年11月5日(木)", "2026年11月5日 周四", "2026年11月5日 週四"],
         ["Nov 5, 2026", "2026年11月5日", "2026年11月5日", "2026年11月5日"]),
        ("2024-02-29",
         ["Thu, Feb 29, 2024", "2024年2月29日(木)", "2024年2月29日 周四", "2024年2月29日 週四"],
         ["Feb 29, 2024", "2024年2月29日", "2024年2月29日", "2024年2月29日"]),
        ("2025-12-31",
         ["Wed, Dec 31, 2025", "2025年12月31日(水)", "2025年12月31日 周三", "2025年12月31日 週三"],
         ["Dec 31, 2025", "2025年12月31日", "2025年12月31日", "2025年12月31日"]),
        ("2026-01-01",
         ["Thu, Jan 1, 2026", "2026年1月1日(木)", "2026年1月1日 周四", "2026年1月1日 週四"],
         ["Jan 1, 2026", "2026年1月1日", "2026年1月1日", "2026年1月1日"]),
        ("2000-01-02",
         ["Sun, Jan 2, 2000", "2000年1月2日(日)", "2000年1月2日 周日", "2000年1月2日 週日"],
         ["Jan 2, 2000", "2000年1月2日", "2000年1月2日", "2000年1月2日"]),
    ]
    static let languages: [L] = [.en, .ja, .zhHans, .zhHant]

    @Test func everyLanguageAndStyle() {
        for (date, full, compact) in Self.cases {
            for (i, lang) in Self.languages.enumerated() {
                #expect(TripDateLabel.label(date, .full, language: lang) == full[i], "\(date) \(lang)")
                #expect(TripDateLabel.label(date, .compact, language: lang) == compact[i], "\(date) \(lang)")
            }
        }
    }

    @Test func undatedAndEmpty() {
        let expected = ["No date", "日付なし", "无日期", "無日期"]
        for (i, lang) in Self.languages.enumerated() {
            for style in [TripDateLabel.LabelStyle.full, .compact] {
                #expect(TripDateLabel.label(nil, style, language: lang) == expected[i])
                #expect(TripDateLabel.label("", style, language: lang) == expected[i])
                #expect(TripDateLabel.label(Dates.undated, style, language: lang) == expected[i])
            }
        }
        #expect(TripDateLabel.label(Dates.allDates, .full, language: .en) == "All dates")
    }

    @Test func malformedIsReturnedUnchanged() {
        for bad in ["2026-13-01", "2026-02-29", "2026-00-10", "2026-11-31", "26-11-05",
                    "2026/11/05", "abc", "2026-11", "2026-11-05T10:00", "2026-1x-05",
                    "2026-11-005", " 2026-11-05", "２０２６-11-05"] {
            for lang in Self.languages {
                #expect(TripDateLabel.label(bad, .full, language: lang) == bad)
                #expect(TripDateLabel.label(bad, .compact, language: lang) == bad)
            }
        }
    }

    @Test func independentOfZoneAndLocale() {
        func snapshot() -> [String] {
            var out: [String] = []
            for (date, _, _) in Self.cases {
                for lang in Self.languages {
                    out.append(TripDateLabel.label(date, .full, language: lang))
                    out.append(TripDateLabel.label(date, .compact, language: lang))
                }
            }
            return out
        }
        let savedZone = NSTimeZone.default
        defer { NSTimeZone.default = savedZone }
        let baseline = snapshot()
        for id in ["Pacific/Kiritimati", "America/Los_Angeles", "UTC", "Asia/Tokyo"] {
            NSTimeZone.default = TimeZone(identifier: id)!
            #expect(snapshot() == baseline, "zone \(id)")
        }
        let savedLocale = getenv("LC_ALL").map { String(cString: $0) }
        defer {
            if let savedLocale { setenv("LC_ALL", savedLocale, 1) } else { unsetenv("LC_ALL") }
        }
        for loc in ["ja_JP", "ar_SA@calendar=islamic", "th_TH@calendar=buddhist"] {
            setenv("LC_ALL", loc, 1)
            #expect(snapshot() == baseline, "locale \(loc)")
        }
    }
}
