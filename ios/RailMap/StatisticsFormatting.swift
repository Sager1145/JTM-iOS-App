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
        let safe = minutes.isFinite ? minutes : 0
        let h = (safe / 60).rounded(.down)
        let m = (safe.truncatingRemainder(dividingBy: 60)).rounded(.toNearestOrAwayFromZero)
        if h > 0 {
            return localization.statsText(
                "fmt.duration", params: ["h": .number(h), "m": .number(m)])
        }
        return localization.statsText("fmt.durationM", params: ["m": .number(m)])
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

/// Statistics-screen strings with no key in the generated web catalog.
///
/// Held here rather than in the shell's own table because this screen
/// introduced them; the shared vocabulary stays in the catalog both apps read.
/// One of ``AppStrings``' contributors — `statsText` and `statsCategoryText`
/// live there with the other four screens' entry points.
enum StatisticsStrings {
    static let table: [String: [Localization.Language: String]] = [
        "ios.stats.scope": [
            .en: "Date scope", .ja: "対象日", .zhHans: "日期范围", .zhHant: "日期範圍",
        ],
        // §5.3.5's other half: a picture of the numbers, beside the film of
        // the route. See `StatisticsShareImage.swift`.
        "ios.stats.shareImage": [
            .en: "Share statistics image", .ja: "統計の画像を共有",
            .zhHans: "分享统计图片", .zhHant: "分享統計圖片",
        ],
        // The one line under the app's name on the poster's banner: what the
        // app the picture came from actually is.
        "ios.stats.shareTagline": [
            .en: "Rail journey log", .ja: "鉄道乗車記録",
            .zhHans: "铁道乘车记录", .zhHant: "鐵道乘車記錄",
        ],
        "ios.stats.shareTitle": [
            .en: "Statistics image", .ja: "統計の画像",
            .zhHans: "统计图片", .zhHant: "統計圖片",
        ],
        "ios.stats.shareImageLabel": [
            .en: "A picture of the statistics on this screen",
            .ja: "この画面の統計の画像",
            .zhHans: "本页统计内容的图片",
            .zhHant: "本頁統計內容的圖片",
        ],
        // The line above the numbers in that picture: which region, and which
        // day, the figures below are scoped to.
        "ios.stats.shareScope": [
            .en: "{region} · {date}", .ja: "{region}・{date}",
            .zhHans: "{region} · {date}", .zhHant: "{region} · {date}",
        ],
        "ios.stats.totalDistance": [
            .en: "Total distance ridden", .ja: "総乗車距離",
            .zhHans: "总乘车里程", .zhHant: "總乘車里程",
        ],
        "ios.stats.calculating": [
            .en: "Calculating statistics", .ja: "統計を計算しています",
            .zhHans: "正在计算统计", .zhHant: "正在計算統計",
        ],
        "ios.stats.stage.readingNetwork": [
            .en: "Reading the rail network", .ja: "路線網を読み込んでいます",
            .zhHans: "正在读取路网", .zhHant: "正在讀取路網",
        ],
        "ios.stats.stage.matchingRides": [
            .en: "Matching rides to the network", .ja: "乗車記録を路線に対応させています",
            .zhHans: "正在把乘车记录对应到路网", .zhHant: "正在把乘車記錄對應到路網",
        ],
        "ios.stats.stage.aggregating": [
            .en: "Adding up coverage", .ja: "カバー率を集計しています",
            .zhHans: "正在汇总覆盖率", .zhHant: "正在彙總覆蓋率",
        ],
        "ios.stats.stage.scopingDay": [
            .en: "Recalculating the selected day", .ja: "対象日を計算し直しています",
            .zhHans: "正在重新计算所选日期", .zhHant: "正在重新計算所選日期",
        ],
        "ios.stats.matchedOf": [
            .en: "{done} of {total} journeys",
            .ja: "{total} 本中 {done} 本",
            .zhHans: "{total} 趟中的 {done} 趟",
            .zhHant: "{total} 趟中的 {done} 趟",
        ],
        "ios.stats.keepUsing": [
            .en: "The rest of the app keeps working while this finishes.",
            .ja: "計算中もアプリの他の機能は利用できます。",
            .zhHans: "计算过程中，应用的其他部分仍可正常使用。",
            .zhHant: "計算過程中，應用程式的其他部分仍可正常使用。",
        ],
        "ios.stats.detailTitle": [
            .en: "Detail by line and category", .ja: "路線・種別ごとの内訳",
            .zhHans: "按线路与类别的明细", .zhHant: "依線路與類別的明細",
        ],
        "ios.stats.unmatchedTitle": [
            .en: "Unmatched distance", .ja: "未一致の距離",
            .zhHans: "未匹配里程", .zhHant: "未配對里程",
        ],
        // §5.3 counts only what the reader has said they rode. This is the
        // one line that says so, and it is stated as a holding with an action
        // rather than as an exclusion — nothing has been lost, nothing is
        // wrong, and the thing to do about it is named.
        "ios.stats.unconfirmedTitle": [
            .en: "Waiting to be confirmed", .ja: "確認待ち",
            .zhHans: "待确认", .zhHant: "待確認",
        ],
        // Counted before the verb rather than "{n} journeys …", because the
        // catalog has no plural forms — `ios.stats.operatorCount` reads
        // "1 operators" — and a sentence that puts the number in a clause of
        // its own is right at every count in all four languages.
        "ios.stats.unconfirmedHeld": [
            .en: "Journeys not confirmed as ridden: {n}. "
                + "Confirm one and it joins these figures.",
            .ja: "乗車が未確認の行程：{n} 本。確認すると集計に加わります。",
            .zhHans: "尚未确认乘坐的行程：{n} 趟。确认后即计入统计。",
            .zhHant: "尚未確認乘坐的行程：{n} 趟。確認後即計入統計。",
        ],
        "ios.stats.coverageA11y": [
            .en: "{pct} percent covered, {ridden} of {total} kilometres",
            .ja: "カバー率 {pct} パーセント、{total} キロ中 {ridden} キロ",
            .zhHans: "覆盖率 {pct}%，{total} 公里中的 {ridden} 公里",
            .zhHant: "覆蓋率 {pct}%，{total} 公里中的 {ridden} 公里",
        ],
        "ios.stats.failedTitle": [
            .en: "Statistics could not be calculated",
            .ja: "統計を計算できませんでした",
            .zhHans: "无法计算统计",
            .zhHant: "無法計算統計",
        ],
        "ios.stats.failedBody": [
            .en: "Your journeys and routes are unchanged.",
            .ja: "乗車記録と経路は変更されていません。",
            .zhHans: "行程记录与路线均未改变。",
            .zhHant: "行程記錄與路線均未改變。",
        ],
        "ios.stats.passportTitle": [
            .en: "All-time rail passport", .ja: "全期間 鉄道パスポート",
            .zhHans: "全时段 铁道护照", .zhHant: "全期間 鐵道護照",
        ],
        // The reference's "1.4x around the world". Written with the number
        // ahead of the unit in English and behind it in CJK, because
        // 「地球 1.4 周」 is how the lap is counted in all three.
        "ios.stats.earthLaps": [
            .en: "{n}× around the world", .ja: "地球 {n} 周",
            .zhHans: "绕地球 {n} 圈", .zhHant: "繞地球 {n} 圈",
        ],
        "ios.stats.journeysLabel": [
            .en: "Journeys", .ja: "乗車本数", .zhHans: "乘车趟数", .zhHant: "乘車趟數",
        ],
        "ios.stats.linesRidden": [
            .en: "Lines ridden", .ja: "乗車路線", .zhHans: "已乘线路", .zhHant: "已乘線路",
        ],
        "ios.stats.operatorCount": [
            .en: "{n} operators", .ja: "{n} 事業者",
            .zhHans: "{n} 家运营商", .zhHant: "{n} 家業者",
        ],
        "ios.stats.topSection": [
            .en: "Most ridden section", .ja: "最も乗った区間",
            .zhHans: "乘坐最多的区间", .zhHant: "乘坐最多的區間",
        ],
        "ios.stats.unsetSpoken": [
            .en: "no date selected", .ja: "対象日が未選択", .zhHans: "未选择日期", .zhHant: "未選擇日期",
        ],

        // MARK: - the distribution card (the reference's "FLIGHTS PER")

        "ios.stats.rhythmTitle": [
            .en: "Journeys over time", .ja: "乗車の分布",
            .zhHans: "乘坐分布", .zhHant: "乘坐分佈",
        ],
        "ios.stats.scaleLabel": [
            .en: "Grouped by", .ja: "分布の単位",
            .zhHans: "分布单位", .zhHant: "分佈單位",
        ],
        "ios.stats.scale.year": [
            .en: "Year", .ja: "年", .zhHans: "年", .zhHant: "年",
        ],
        "ios.stats.scale.month": [
            .en: "Month", .ja: "月", .zhHans: "月", .zhHant: "月",
        ],
        "ios.stats.scale.weekday": [
            .en: "Weekday", .ja: "曜日", .zhHans: "星期", .zhHant: "星期",
        ],
        "ios.stats.mostJourneys": [
            .en: "Most journeys", .ja: "最も乗った",
            .zhHans: "乘坐最多", .zhHant: "乘坐最多",
        ],
        // Counted before the verb, for the reason `ios.stats.unconfirmedHeld`
        // is: the catalog carries no plural forms, and a sentence that keeps
        // the number in a clause of its own reads at every count.
        "ios.stats.undatedHeld": [
            .en: "Journeys carrying no date: {n}. "
                + "They are in every total here, and in none of these columns.",
            .ja: "日付のない行程：{n} 本。合計には入りますが、この分布には入りません。",
            .zhHans: "没有日期的行程：{n} 趟。计入上面的总量，但不在此分布中。",
            .zhHant: "沒有日期的行程：{n} 趟。計入上面的總量，但不在此分佈中。",
        ],

        // MARK: - the distance and time record cards

        "ios.stats.distanceTitle": [
            .en: "Distance records", .ja: "距離の記録",
            .zhHans: "距离纪录", .zhHant: "距離紀錄",
        ],
        "ios.stats.timeTitle": [
            .en: "Time records", .ja: "時間の記録",
            .zhHans: "时间纪录", .zhHant: "時間紀錄",
        ],
        "ios.stats.perJourney": [
            .en: "Per journey", .ja: "1 乗車あたり",
            .zhHans: "每趟平均", .zhHant: "每趟平均",
        ],
        // The three scale comparisons. Each is a real ratio against a real
        // figure — the WGS-84 equator, the Moon's mean distance, the Sun's own
        // circumference — because §5.3 asks for expressive AND accurate, and a
        // souvenir number that is not true is just a number.
        "ios.stats.aroundEarth": [
            .en: "Around the world", .ja: "地球一周",
            .zhHans: "绕地球一圈", .zhHant: "繞地球一圈",
        ],
        "ios.stats.toTheMoon": [
            .en: "To the Moon", .ja: "月までの距離",
            .zhHans: "到月球的距离", .zhHant: "到月球的距離",
        ],
        "ios.stats.aroundSun": [
            .en: "Around the Sun", .ja: "太陽一周",
            .zhHans: "绕太阳一圈", .zhHant: "繞太陽一圈",
        ],
        "ios.stats.longestByDistance": [
            .en: "Longest by distance", .ja: "最長（距離）",
            .zhHans: "最长（距离）", .zhHant: "最長（距離）",
        ],
        "ios.stats.shortestByDistance": [
            .en: "Shortest by distance", .ja: "最短（距離）",
            .zhHans: "最短（距离）", .zhHant: "最短（距離）",
        ],
        "ios.stats.longestByTime": [
            .en: "Longest by time", .ja: "最長（時間）",
            .zhHans: "最长（时间）", .zhHant: "最長（時間）",
        ],
        "ios.stats.shortestByTime": [
            .en: "Shortest by time", .ja: "最短（時間）",
            .zhHans: "最短（时间）", .zhHant: "最短（時間）",
        ],
        "ios.stats.days": [.en: "Days", .ja: "日", .zhHans: "天", .zhHant: "天"],
        "ios.stats.weeks": [.en: "Weeks", .ja: "週", .zhHans: "周", .zhHant: "週"],
        "ios.stats.months": [.en: "Months", .ja: "か月", .zhHans: "个月", .zhHant: "個月"],
        "ios.stats.years": [.en: "Years", .ja: "年", .zhHans: "年", .zhHant: "年"],

        // MARK: - the ranked lists

        "ios.stats.stationsTitle": [
            .en: "Most visited stations", .ja: "よく発着した駅",
            .zhHans: "最常进出的车站", .zhHant: "最常進出的車站",
        ],
        "ios.stats.stationsHint": [
            .en: "A station counts once for each journey that began or ended there. "
                + "The calls in between are not visits.",
            .ja: "乗り降りした行程ごとに 1 回。途中の停車は数えません。",
            .zhHans: "每趟在此上下车各计 1 次；中途停靠不计。",
            .zhHant: "每趟在此上下車各計 1 次；中途停靠不計。",
        ],
        "ios.stats.operatorsTitle": [
            .en: "Most ridden operators", .ja: "よく乗った事業者",
            .zhHans: "最常乘坐的运营商", .zhHant: "最常乘坐的業者",
        ],
        "ios.stats.routesTitle": [
            .en: "Most ridden routes", .ja: "よく乗った発着区間",
            .zhHans: "最常乘坐的起讫", .zhHant: "最常乘坐的起訖",
        ],
        "ios.stats.routesHint": [
            .en: "The two ends of a journey, counted in either direction — "
                + "a return trip is one route ridden twice.",
            .ja: "行程の始点と終点。向きは問わないので、往復は同じ区間を 2 回です。",
            .zhHans: "行程的起点与终点，不分方向：往返算同一组起讫乘坐两次。",
            .zhHant: "行程的起點與終點，不分方向：來回算同一組起訖乘坐兩次。",
        ],
        "ios.stats.regionsTitle": [
            .en: "Countries and territories", .ja: "国と地域",
            .zhHans: "国家与地区", .zhHant: "國家與地區",
        ],
        "ios.stats.rankBy": [
            .en: "Rank by", .ja: "並べ替え",
            .zhHans: "排序依据", .zhHant: "排序依據",
        ],
        "ios.stats.metric.count": [
            .en: "Journeys", .ja: "乗車数", .zhHans: "趟数", .zhHant: "趟數",
        ],
        "ios.stats.metric.distance": [
            .en: "Distance", .ja: "距離", .zhHans: "里程", .zhHant: "里程",
        ],
        "ios.stats.showMore": [
            .en: "Show more ({n})", .ja: "さらに表示（{n}）",
            .zhHans: "显示更多（{n}）", .zhHant: "顯示更多（{n}）",
        ],
        // The counters a total is spelled with. Separate keys rather than one
        // "{n} of them", because the counter is part of the noun in three of
        // the four languages and there is no neutral word for all of them.
        "ios.stats.unit.stations": [
            .en: "stations", .ja: "駅", .zhHans: "座车站", .zhHant: "座車站",
        ],
        "ios.stats.unit.operators": [
            .en: "operators", .ja: "事業者", .zhHans: "家运营商", .zhHant: "家業者",
        ],
        "ios.stats.unit.routes": [
            .en: "routes", .ja: "区間", .zhHans: "组起讫", .zhHant: "組起訖",
        ],
        "ios.stats.unit.regions": [
            .en: "regions", .ja: "か国・地域",
            .zhHans: "个国家或地区", .zhHant: "個國家或地區",
        ],
    ]
}
