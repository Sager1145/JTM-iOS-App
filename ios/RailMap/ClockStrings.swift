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

        // MARK: the North American clocks
        //
        // Named for the zone rather than for the country, because that is what
        // they are: a train from Chicago to Seattle changes clock twice
        // without leaving the United States, and one from Montréal to New York
        // crosses a border without changing clock at all. Six of these eight
        // observe summer time, and none of these names says so — "Eastern
        // Time" is the zone whether it is standard or daylight, and the offset
        // printed beside it is read from the database on the journey's own
        // day.

        "ios.clock.zoneEastern": [
            .zhHant: "北美東部時間", .zhHans: "北美东部时间", .ja: "北米東部時間",
            .en: "Eastern Time",
        ],
        "ios.clock.zoneCentral": [
            .zhHant: "北美中部時間", .zhHans: "北美中部时间", .ja: "北米中部時間",
            .en: "Central Time",
        ],
        "ios.clock.zoneMountain": [
            .zhHant: "北美山區時間", .zhHans: "北美山区时间", .ja: "北米山岳部時間",
            .en: "Mountain Time",
        ],
        "ios.clock.zonePacific": [
            .zhHant: "北美太平洋時間", .zhHans: "北美太平洋时间", .ja: "北米太平洋時間",
            .en: "Pacific Time",
        ],
        "ios.clock.zoneAlaska": [
            .zhHant: "阿拉斯加時間", .zhHans: "阿拉斯加时间", .ja: "アラスカ時間",
            .en: "Alaska Time",
        ],
        "ios.clock.zoneAtlantic": [
            .zhHant: "北美大西洋時間", .zhHans: "北美大西洋时间", .ja: "北米大西洋時間",
            .en: "Atlantic Time",
        ],
        "ios.clock.zoneNewfoundland": [
            .zhHant: "紐芬蘭時間", .zhHans: "纽芬兰时间", .ja: "ニューファンドランド時間",
            .en: "Newfoundland Time",
        ],
        // The two North American zones that keep standard time all year, named
        // so rather than as plain "Mountain" / "Central": for half the year
        // Phoenix keeps Pacific's clock and Regina keeps the Mountain zone's,
        // and a reader comparing two journeys deserves to be told which.
        "ios.clock.zoneArizona": [
            .zhHant: "北美山區標準時間（亞利桑那）",
            .zhHans: "北美山区标准时间（亚利桑那）",
            .ja: "北米山岳部標準時（アリゾナ）",
            .en: "Mountain Standard Time (Arizona)",
        ],
        "ios.clock.zoneSaskatchewan": [
            .zhHant: "北美中部標準時間（薩斯喀徹溫）",
            .zhHans: "北美中部标准时间（萨斯喀彻温）",
            .ja: "北米中部標準時（サスカチュワン）",
            .en: "Central Standard Time (Saskatchewan)",
        ],
        "ios.clock.zoneHawaii": [
            .zhHant: "夏威夷－阿留申時間", .zhHans: "夏威夷－阿留申时间",
            .ja: "ハワイ・アリューシャン時間",
            .en: "Hawaii–Aleutian Time",
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

        // The same note for a journey that changes clock on the way. It names
        // both ends rather than one, because the single-clock sentence would
        // be a false statement about half the list — and because the reader's
        // next question, on seeing an arrival that looks earlier than a
        // departure, is exactly which clock each was printed on.
        "ios.clock.localTimesCrossing": [
            .zhHant: "時刻皆為當地時間，沿途跨越時區（起點 {fromZone}，終點 {toZone}）",
            .zhHans: "时刻均为当地时间，沿途跨越时区（起点 {fromZone}，终点 {toZone}）",
            .ja: "時刻はすべて現地時間です。途中で時間帯をまたぎます（始発 {fromZone}／終着 {toZone}）",
            .en: "All times are local; this journey crosses time zones "
                + "(departs {fromZone}, arrives {toZone})",
        ],
    ]
}
