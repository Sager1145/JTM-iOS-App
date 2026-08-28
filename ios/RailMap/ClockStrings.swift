import Foundation
import RailCore

/// What the app calls the clock a journey is on.
///
/// Its own table rather than a corner of `JourneyStrings` because the zone
/// names are not one screen's copy: they name the five regions' clocks, and
/// they are read out of `RailPresentation.RegionClock.nameKey` — one tier
/// down, where there is no catalog. That tier hands up a key and a structural
/// English fallback exactly as `PresentationText` does; this is where the four
/// languages live.
///
/// Every entry carries all four interface languages, for the reason
/// ``DataStrings`` gives: a fallback string is an English string, and an
/// English string shown to a reader who chose 日本語 is a localisation bug that
/// compiles. Registered in ``AppStrings`` alongside the other tables, which is
/// also what checks that none of these keys is spelled anywhere else.
///
/// The keys deliberately do not end in a region code. `countryText` reads a
/// trailing `.tw` / `.hk` / `.mo` / `.kr` / `.jp` as a country VARIANT of the
/// key in front of it and resolves it against the statistics screen's selected
/// region — so `ios.clock.zone.jp` would be answered by whichever region the
/// reader last looked at statistics for, rather than by the ride's own.
enum ClockStrings {

    static let table: [String: [Localization.Language: String]] = [

        // MARK: the five clocks

        "ios.clock.zoneJapan": [
            .zhHant: "日本標準時間", .zhHans: "日本标准时间", .ja: "日本標準時",
            .en: "Japan Standard Time",
        ],
        "ios.clock.zoneTaiwan": [
            .zhHant: "臺灣標準時間", .zhHans: "台湾标准时间", .ja: "台湾標準時",
            .en: "Taiwan Standard Time",
        ],
        "ios.clock.zoneHongKong": [
            .zhHant: "香港時間", .zhHans: "香港时间", .ja: "香港時間",
            .en: "Hong Kong Time",
        ],
        "ios.clock.zoneMacao": [
            .zhHant: "澳門時間", .zhHans: "澳门时间", .ja: "マカオ時間",
            .en: "Macao Time",
        ],
        "ios.clock.zoneKorea": [
            .zhHant: "韓國標準時間", .zhHans: "韩国标准时间", .ja: "韓国標準時",
            .en: "Korea Standard Time",
        ],

        // MARK: saying which clock the times are on

        // Said once under the stop list rather than beside every time. The
        // sentence is about what the record ALREADY holds — the app converts
        // nothing — so it is a note, not a setting.
        "ios.clock.localTimes": [
            .zhHant: "時刻皆為當地時間（{zone}，{offset}）",
            .zhHans: "时刻均为当地时间（{zone}，{offset}）",
            .ja: "時刻はすべて現地時間（{zone}・{offset}）です",
            .en: "All times are local ({zone}, {offset})",
        ],
    ]
}
