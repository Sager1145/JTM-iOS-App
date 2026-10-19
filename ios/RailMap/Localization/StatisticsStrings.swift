import RailCore

/// Statistics-screen strings with no key in the generated web catalog.
///
/// Held here rather than in the shell's own table because this screen
/// introduced them; the shared vocabulary stays in the catalog both apps read.
/// One of ``AppStrings``' contributors — `statsText` and `statsCategoryText`
/// live there with the other four screens' entry points.
enum StatisticsStrings {
    static let table: [String: [Localization.Language: String]] = [
        "ios.stats.allTime": [
            .en: "All Time", .ja: "全期間", .zhHans: "全部时间", .zhHant: "全部時間",
        ],
        // MARK: 券面 — the ticket face's own words
        "ios.ticket.kind.history": [
            .en: "History", .ja: "乗車記録", .zhHans: "乗車記録", .zhHant: "乗車記録",
        ],
        //
        // §5.7's figures, re-labelled for a printed form. The passport's cards
        // set every label at one size in a two-column block, which is a much
        // tighter budget than a card header: 「総乗車距離」 is the heading over
        // a statistic and 「乗車距離」 is the field on a ticket, and the design
        // asks for the second. The three that already had a short form
        // (`ios.rideTime`, `ios.stops`, `ios.stats.operatorsLabel`) are reused
        // rather than restated here.
        "ios.ticket.label.distance": [
            .en: "Distance", .ja: "乗車距離", .zhHans: "乘车里程", .zhHant: "乘車里程",
        ],
        "ios.ticket.label.rides": [
            .en: "Rides", .ja: "乗車回数", .zhHans: "乘车次数", .zhHant: "乘車次數",
        ],
        "ios.ticket.label.coverage": [
            .en: "Coverage", .ja: "路線カバー率", .zhHans: "路线覆盖率", .zhHant: "路線覆蓋率",
        ],
        // The counters, and the three that are EMPTY in English on purpose.
        //
        // 「乗車回数 412 回」 is a form field: the counter is what tells a
        // reader that 412 is a count of rides and not of anything else. English
        // has no counters — "Rides 412 rides" says the noun twice — so the
        // value here is the empty string and the face draws no unit at all.
        // That is a real difference between the languages, and spelling it as
        // an entry in the catalog is what keeps it from being read as a
        // missing translation.
        "ios.ticket.unit.hours": [
            .en: "h", .ja: "時間", .zhHans: "小时", .zhHant: "小時",
        ],
        "ios.ticket.unit.minutes": [
            .en: "min", .ja: "分", .zhHans: "分", .zhHant: "分",
        ],
        "ios.ticket.unit.rides": [
            .en: "", .ja: "回", .zhHans: "次", .zhHant: "次",
        ],
        "ios.ticket.unit.stops": [
            .en: "", .ja: "駅", .zhHans: "站", .zhHant: "站",
        ],
        "ios.ticket.unit.operators": [
            .en: "", .ja: "社", .zhHans: "家", .zhHant: "家",
        ],
        // Full-width in the two scripts that set it full-width. A ticket's
        // percentage sign sits on the same em as the kanji beside it.
        "ios.ticket.unit.percent": [
            .en: "%", .ja: "％", .zhHans: "％", .zhHant: "％",
        ],
        // 「集計期間は年を必ず入れる」 — the design's own 表記 rule, and the
        // reason this is a spelled date rather than the compact 年.月.日 form
        // the foot of the card uses. A span that read 「4.1 から 3.31」 would
        // not say which year, and this line is the only place on the face that
        // says what the figures above it cover.
        "ios.ticket.date": [
            .en: "{y}-{m}-{d}", .ja: "{y}年{m}月{d}日",
            .zhHans: "{y}年{m}月{d}日", .zhHant: "{y}年{m}月{d}日",
        ],
        "ios.ticket.span": [
            .en: "From {from} to {to}",
            .ja: "{from}から　{to}まで集計",
            .zhHans: "统计 {from} 至 {to}",
            .zhHant: "統計 {from} 至 {to}",
        ],
        "ios.ticket.spanDay": [
            .en: "From {date}", .ja: "{date}分を集計",
            .zhHans: "统计 {date}", .zhHant: "統計 {date}",
        ],
        // 最下行の左: 「集計日　RAILMAP 発行」. The design's own form carries a
        // terminal number after the issuer — 「（1-14）」, the MARS machine the
        // ticket came out of. There is no such number here and inventing one
        // would be the only fabricated thing on a card of measured figures, so
        // the row is issued without it.
        "ios.ticket.issued": [
            .en: "{date}　RAILMAP issued", .ja: "{date}　RAILMAP 発行",
            .zhHans: "{date}　RAILMAP 发行", .zhHant: "{date}　RAILMAP 發行",
        ],
        "ios.stats.scope": [
            .en: "Date scope", .ja: "対象日", .zhHans: "日期范围", .zhHant: "日期範圍",
        ],
        // §5.3.5's other half: a picture of the numbers, beside the film of
        // the route. See `StatisticsShareImage.swift`.
        "ios.stats.shareImage": [
            .en: "Share image", .ja: "画像を共有",
            .zhHans: "分享图片", .zhHant: "分享圖片",
        ],
        "ios.stats.shareComposer": [
            .en: "Share composer", .ja: "共有画像を編集",
            .zhHans: "编辑分享图片", .zhHant: "編輯分享圖片",
        ],
        "ios.stats.shareExport": [
            .en: "Export", .ja: "書き出す", .zhHans: "导出", .zhHant: "匯出",
        ],
        "ios.stats.shareCanvas": [
            .en: "Share image canvas", .ja: "共有画像キャンバス",
            .zhHans: "分享图片画布", .zhHant: "分享圖片畫布",
        ],
        "ios.stats.shareNoOverlap": [
            .en: "The region selection and map cards do not overlap.",
            .ja: "地域の選択と地図カードの範囲が重なっていません。",
            .zhHans: "地区选择与地图卡片的范围不重叠。",
            .zhHant: "地區選擇與地圖卡片的範圍不重疊。",
        ],
        "ios.stats.shareDoesNotFit": [
            .en: "Doesn’t fit", .ja: "収まりません",
            .zhHans: "无法放入", .zhHant: "無法放入",
        ],
        "ios.stats.shareRatio": [
            .en: "Canvas ratio", .ja: "画像の比率", .zhHans: "画布比例", .zhHant: "畫布比例",
        ],
        "ios.stats.shareAppearance": [
            .en: "Appearance", .ja: "外観", .zhHans: "外观", .zhHant: "外觀",
        ],
        "ios.stats.shareSize": [
            .en: "Image size", .ja: "画像サイズ", .zhHans: "图片尺寸", .zhHant: "圖片尺寸",
        ],
        "ios.stats.shareSizeSmall": [
            .en: "S", .ja: "小", .zhHans: "小", .zhHant: "小",
        ],
        "ios.stats.shareSizeMedium": [
            .en: "M", .ja: "中", .zhHans: "中", .zhHant: "中",
        ],
        "ios.stats.shareSizeLarge": [
            .en: "L", .ja: "大", .zhHans: "大", .zhHant: "大",
        ],
        "ios.stats.shareLayouts": [
            .en: "Layouts", .ja: "レイアウト", .zhHans: "布局", .zhHant: "版面配置",
        ],
        "ios.stats.shareLayoutJapan": [
            .en: "Japan islands", .ja: "日本列島", .zhHans: "日本列岛", .zhHant: "日本列島",
        ],
        "ios.stats.shareAdd": [
            .en: "Add card", .ja: "カードを追加", .zhHans: "添加卡片", .zhHant: "加入卡片",
        ],
        "ios.stats.shareMotion.edit": [
            .en: "Edit", .ja: "編集", .zhHans: "编辑", .zhHant: "編輯",
        ],
        "ios.stats.shareMotion.done": [
            .en: "Done", .ja: "完了", .zhHans: "完成", .zhHant: "完成",
        ],
        "ios.stats.shareMotion.moveEarlier": [
            .en: "Move earlier", .ja: "前へ移動", .zhHans: "前移", .zhHant: "往前移",
        ],
        "ios.stats.shareMotion.moveLater": [
            .en: "Move later", .ja: "後へ移動", .zhHans: "后移", .zhHant: "往後移",
        ],
        "ios.stats.shareMotion.remove": [
            .en: "Remove", .ja: "削除", .zhHans: "移除", .zhHant: "移除",
        ],
        "ios.stats.shareMotion.restore": [
            .en: "Return to canvas", .ja: "キャンバスに戻す",
            .zhHans: "放回画布", .zhHant: "放回畫布",
        ],
        "ios.stats.shareMotion.parked": [
            .en: "Set aside", .ja: "一時保留中", .zhHans: "已暂时搁置", .zhHant: "已暫時擱置",
        ],
        "ios.stats.shareExportFailed": [
            .en: "Export failed", .ja: "書き出しに失敗しました",
            .zhHans: "导出失败", .zhHant: "匯出失敗",
        ],
        "ios.stats.shareExportFailedBody": [
            .en: "Could not create the image. Please try again.",
            .ja: "画像を作成できませんでした。再試行してください。",
            .zhHans: "未能生成分享图片，请重试。", .zhHant: "未能產生分享圖片，請重試。",
        ],
        "ios.stats.shareShape.square": [
            .en: "Square", .ja: "正方形", .zhHans: "正方形", .zhHant: "正方形",
        ],
        "ios.stats.shareShape.mini": [
            .en: "Mini · 1×1", .ja: "ミニ · 1×1", .zhHans: "迷你 · 1×1", .zhHant: "迷你 · 1×1",
        ],
        "ios.stats.shareShape.strip": [
            .en: "Strip · 2×1", .ja: "横長ミニ · 2×1", .zhHans: "短条 · 2×1", .zhHant: "短條 · 2×1",
        ],
        "ios.stats.shareCompactCards": [
            .en: "Mini cards", .ja: "ミニカード", .zhHans: "迷你卡片", .zhHant: "迷你卡片",
        ],
        "ios.stats.shareShape.landscape": [
            .en: "Landscape", .ja: "横長", .zhHans: "横向", .zhHant: "橫向",
        ],
        "ios.stats.shareShape.portrait": [
            .en: "Portrait", .ja: "縦長", .zhHans: "纵向", .zhHant: "縱向",
        ],
        "ios.stats.shareShape.largeSquare": [
            .en: "Large square", .ja: "大きな正方形",
            .zhHans: "大正方形", .zhHant: "大正方形",
        ],
        "ios.stats.shareMotion.dropToTray": [
            .en: "Drag here to set aside", .ja: "ここにドラッグして一時保留",
            .zhHans: "拖到这里暂时搁置", .zhHant: "拖到這裡暫時擱置",
        ],
        "ios.stats.shareTicket": [
            .en: "Ticket", .ja: "きっぷ", .zhHans: "车票", .zhHant: "車票",
        ],
        "ios.stats.shareMap": [
            .en: "Map", .ja: "地図", .zhHans: "地图", .zhHant: "地圖",
        ],
        "ios.stats.shareStatistics": [
            .en: "Statistics", .ja: "統計", .zhHans: "统计", .zhHant: "統計",
        ],
        "ios.stats.shareCardSize": [
            .en: "Card size", .ja: "カードサイズ", .zhHans: "卡片尺寸", .zhHant: "卡片尺寸",
        ],
        "ios.stats.shareTicketFixedRatio": [
            .en: "Ticket proportions are fixed.",
            .ja: "きっぷの縦横比は固定です。",
            .zhHans: "车票比例固定。", .zhHant: "車票比例固定。",
        ],
        "ios.stats.shareNoData": [
            .en: "No data for this scope", .ja: "この範囲のデータはありません",
            .zhHans: "此范围没有数据", .zhHant: "此範圍沒有資料",
        ],
        "ios.stats.shareMapRatio": [
            .en: "Map ratio", .ja: "地図の比率", .zhHans: "地图比例", .zhHant: "地圖比例",
        ],
        "ios.stats.shareZoom": [
            .en: "Zoom", .ja: "拡大率", .zhHans: "缩放", .zhHant: "縮放",
        ],
        "ios.stats.shareCardLabel": [
            .en: "{name}, {columns} by {rows}", .ja: "{name}、{columns}×{rows}",
            .zhHans: "{name}，{columns}×{rows}", .zhHant: "{name}，{columns}×{rows}",
        ],
        "ios.stats.shareLight": [
            .en: "Share in light mode", .ja: "ライトモードで共有",
            .zhHans: "亮色分享", .zhHant: "亮色分享",
        ],
        "ios.stats.shareDark": [
            .en: "Share in dark mode", .ja: "ダークモードで共有",
            .zhHans: "暗色分享", .zhHant: "暗色分享",
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
        "ios.stats.totalRiddenKm": [
            .en: "Total ridden km", .ja: "乗車した全区間",
            .zhHans: "已乘总里程", .zhHant: "已乘總里程",
        ],
        "ios.stats.currentRiddenKm": [
            .en: "Current network ridden", .ja: "現行路線の乗車",
            .zhHans: "现行路网已乘", .zhHant: "現行路網已乘",
        ],
        "ios.stats.retiredKm": [
            .en: "Retired network ridden", .ja: "廃止路線の乗車",
            .zhHans: "停运路网已乘", .zhHant: "停運路網已乘",
        ],
        "ios.stats.relocatedOldKm": [
            .en: "Relocated old alignment", .ja: "移設前の線路",
            .zhHans: "改线前线路", .zhHant: "改線前線路",
        ],
        "ios.stats.historicalKm": [
            .en: "Historical unique km ridden", .ja: "歴史区間の乗車距離",
            .zhHans: "历史区间已乘里程", .zhHant: "歷史區間已乘里程",
        ],
        "ios.stats.retiredLines": [
            .en: "Retired lines ridden", .ja: "乗った廃止路線",
            .zhHans: "已乘停运线路", .zhHant: "已乘停運線路",
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
        // The label over a bare count of companies, as against
        // `ios.stats.operatorCount`, which is the count WITH its unit in a
        // clause ("35 家業者"). A column header cannot carry the unit twice.
        "ios.stats.operatorsLabel": [
            .en: "Operators", .ja: "事業者数",
            .zhHans: "公司数量", .zhHant: "業者數",
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
        "ios.stats.unit.lines": [.en: "lines", .ja: "路線", .zhHans: "条线路", .zhHant: "條路線"],
        "ios.stats.shareInheritRegion": [.en: "Follow page region", .ja: "ページの地域を使用", .zhHans: "使用页面地区", .zhHant: "使用頁面地區"],
        "ios.stats.shareInheritDates": [.en: "Follow page dates", .ja: "ページの期間を使用", .zhHans: "使用页面日期", .zhHant: "使用頁面日期"],
        "ios.stats.shareCardRegion": [.en: "Card region", .ja: "カードの地域", .zhHans: "卡片地区", .zhHant: "卡片地區"],
        "ios.stats.shareCardDates": [.en: "Card dates", .ja: "カードの期間", .zhHans: "卡片日期", .zhHant: "卡片日期"],
        "ios.stats.shareCustomizeDates": [.en: "Set card dates", .ja: "カードの期間を設定", .zhHans: "设置卡片日期", .zhHant: "設定卡片日期"],
        "ios.stats.shareMostVisited": [.en: "Most visited", .ja: "最も利用した駅", .zhHans: "到访最多", .zhHant: "到訪最多"],
        "ios.stats.shareMostRidden": [.en: "Most ridden", .ja: "最も乗った", .zhHans: "乘坐最多", .zhHant: "乘坐最多"],
        "ios.stats.shareDistanceShare": [.en: "Share of distance", .ja: "乗車距離の割合", .zhHans: "乘坐里程占比", .zhHant: "乘坐里程占比"],
        "ios.stats.shareUndatedExcluded": [.en: "Undated rides excluded: {n}", .ja: "日付のない乗車は対象外：{n} 本", .zhHans: "未计入无日期乘车：{n} 趟", .zhHant: "未計入無日期乘車：{n} 趟"],
        "ios.stats.shareAllYears": [.en: "All years", .ja: "全期間", .zhHans: "所有年份", .zhHant: "所有年份"],
        // Japanese area scopes and the card names used by the share composer.
        "ios.area.japanAll": [.en: "Japan (all)", .ja: "日本（全域）", .zhHans: "日本（全部）", .zhHant: "日本（全部）"],
        "ios.area.honshuAll": [.en: "Honshu (all)", .ja: "本州（全域）", .zhHans: "本州（全部）", .zhHant: "本州（全部）"],
        "ios.area.hokkaido": [.en: "Hokkaido", .ja: "北海道", .zhHans: "北海道", .zhHant: "北海道"],
        "ios.area.honshu": [.en: "Honshu", .ja: "本州", .zhHans: "本州", .zhHant: "本州"],
        "ios.area.tohoku": [.en: "Tohoku", .ja: "東北", .zhHans: "东北", .zhHant: "東北"],
        "ios.area.kanto": [.en: "Kanto", .ja: "関東", .zhHans: "关东", .zhHant: "關東"],
        "ios.area.hokuriku": [.en: "Hokuriku", .ja: "北陸", .zhHans: "北陆", .zhHant: "北陸"],
        "ios.area.koshin": [.en: "Koshin", .ja: "甲信", .zhHans: "甲信", .zhHant: "甲信"],
        "ios.area.tokai": [.en: "Tokai", .ja: "東海", .zhHans: "东海", .zhHant: "東海"],
        "ios.area.kinki": [.en: "Kinki", .ja: "近畿", .zhHans: "近畿", .zhHant: "近畿"],
        "ios.area.chugoku": [.en: "Chugoku", .ja: "中国", .zhHans: "中国", .zhHant: "中國"],
        "ios.area.shikoku": [.en: "Shikoku", .ja: "四国", .zhHans: "四国", .zhHant: "四國"],
        "ios.area.kyushu": [.en: "Kyushu", .ja: "九州", .zhHans: "九州", .zhHant: "九州"],
        "ios.area.okinawa": [.en: "Okinawa", .ja: "沖縄", .zhHans: "冲绳", .zhHant: "沖繩"],
        "ios.stats.card.recordTicket": [.en: "Record ticket", .ja: "乗車記録券", .zhHans: "乘车记录票", .zhHant: "乘車記錄票"],
        "ios.stats.card.dailyTicket": [.en: "Daily ticket", .ja: "当日乗車券", .zhHans: "当日乘车票", .zhHant: "當日乘車票"],
        "ios.stats.card.rhythm": [.en: "Travel rhythm", .ja: "乗車分布", .zhHans: "乘坐分布", .zhHant: "乘坐分佈"],
        "ios.stats.card.distance": [.en: "Longest trip", .ja: "最長の乗車距離", .zhHans: "最长行程", .zhHant: "最長行程"],
        "ios.stats.card.time": [.en: "Longest time", .ja: "最長の乗車時間", .zhHans: "最长乘车时间", .zhHant: "最長乘車時間"],
        "ios.stats.card.rides": [.en: "Rides", .ja: "乗車回数", .zhHans: "乘车次数", .zhHant: "乘車次數"],
        "ios.stats.card.coverage": [.en: "Coverage", .ja: "走破率", .zhHans: "覆盖率", .zhHant: "覆蓋率"],
        "ios.stats.card.service": [.en: "Service mix", .ja: "車種の構成", .zhHans: "车种构成", .zhHant: "車種構成"],
        "ios.stats.card.stations": [.en: "Visited stations", .ja: "利用した駅", .zhHans: "到访车站", .zhHant: "到訪車站"],
        "ios.stats.card.operators": [.en: "Ridden operators", .ja: "利用した事業者", .zhHans: "乘坐过的运营商", .zhHant: "乘坐過的業者"],
        "ios.stats.card.routes": [.en: "Ridden routes", .ja: "乗車した発着区間", .zhHans: "乘坐过的起讫", .zhHant: "乘坐過的起訖"],
        "ios.stats.card.topSegments": [.en: "Most ridden segment", .ja: "最も乗った区間", .zhHans: "乘坐最多的区间", .zhHant: "乘坐最多的區間"],
        "ios.stats.card.regions": [.en: "Regions", .ja: "国と地域", .zhHans: "国家与地区", .zhHant: "國家與地區"],
        "ios.stats.card.lineDetail": [.en: "Line coverage", .ja: "路線の走破率", .zhHans: "线路覆盖率", .zhHant: "路線覆蓋率"],
        "ios.stats.widget.openDetails": [
            .en: "Open details", .ja: "詳細を開く",
            .zhHans: "打开详情", .zhHant: "開啟詳情",
        ],
    ]
}
