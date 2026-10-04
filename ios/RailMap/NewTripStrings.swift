import Foundation
import RailCore

/// Sentences for the new-trip form. Looked up through `AppLocalization.text`
/// after this table is merged in `AppStrings`.
enum NewTripStrings {
    static let table: [String: [Localization.Language: String]] = [
        "ios.newTrip.timetable": [
            .en: "Timetable", .ja: "時刻表", .zhHant: "時刻表", .zhHans: "时刻表",
        ],
        "ios.newTrip.serviceName": [
            .en: "Service name", .ja: "列車名", .zhHant: "列車名稱", .zhHans: "列车名称",
        ],
        "ios.newTrip.serviceSuggestions": [
            .en: "Service suggestions", .ja: "列車名の候補", .zhHant: "列車名稱建議", .zhHans: "列车名称建议",
        ],
        "ios.newTrip.timetableBrowse": [
            .en: "Browse timetables", .ja: "時刻表を探す", .zhHant: "瀏覽時刻表", .zhHans: "浏览时刻表",
        ],
        "ios.newTrip.timetableFailed": [
            .en: "This timetable could not be applied.", .ja: "この時刻表を適用できませんでした。", .zhHant: "無法套用此時刻表。", .zhHans: "无法应用此时刻表。",
        ],
        "ios.newTrip.timetableRemove": [
            .en: "Remove", .ja: "削除", .zhHant: "移除", .zhHans: "移除",
        ],

        "ios.newTrip.cancel": [
            .zhHans: "取消", .zhHant: "取消", .ja: "キャンセル", .en: "Cancel",
        ],
        "ios.newTrip.save": [
            .zhHans: "保存", .zhHant: "儲存", .ja: "保存", .en: "Save",
        ],
        "ios.newTrip.region": [
            .zhHans: "地区", .zhHant: "地區", .ja: "地域", .en: "Region",
        ],
        "ios.newTrip.stations": [
            .zhHans: "车站", .zhHant: "車站", .ja: "駅", .en: "Stations",
        ],
        "ios.newTrip.from": [
            .zhHans: "出发", .zhHant: "出發", .ja: "出発", .en: "From",
        ],
        "ios.newTrip.to": [
            .zhHans: "到达", .zhHant: "到達", .ja: "到着", .en: "To",
        ],
        "ios.newTrip.chooseStation": [
            .zhHans: "选择车站", .zhHant: "選擇車站", .ja: "駅を選択", .en: "Choose station",
        ],
        "ios.newTrip.swap": [
            .zhHans: "交换出发站和到达站", .zhHant: "交換出發站和到達站",
            .ja: "発着駅を入れ替え", .en: "Swap stations",
        ],
        "ios.newTrip.service": [
            .zhHans: "列车", .zhHant: "列車", .ja: "列車", .en: "Service",
        ],
        "ios.newTrip.trainType": [
            .zhHans: "列车类型", .zhHant: "列車類型", .ja: "列車種別", .en: "Train type",
        ],
        "ios.newTrip.trainNumber": [
            .zhHans: "车次或列车名", .zhHant: "車次或列車名",
            .ja: "列車番号または列車名", .en: "Train number or name",
        ],
        "ios.newTrip.company": [
            .zhHans: "公司", .zhHant: "公司", .ja: "会社", .en: "Company",
        ],
        "ios.newTrip.anyCompany": [
            .zhHans: "所有公司", .zhHant: "所有公司", .ja: "すべての会社", .en: "Any company",
        ],
        "ios.newTrip.time": [
            .zhHans: "时间", .zhHant: "時間", .ja: "時刻", .en: "Time",
        ],
        "ios.newTrip.departure": [
            .zhHans: "出发", .zhHant: "出發", .ja: "出発", .en: "Departure",
        ],
        "ios.newTrip.arrival": [
            .zhHans: "到达", .zhHant: "到達", .ja: "到着", .en: "Arrival",
        ],
        "ios.newTrip.arrivalBeforeDeparture": [
            .zhHans: "到达时间早于出发时间。", .zhHant: "到達時間早於出發時間。",
            .ja: "到着が出発より前です。", .en: "Arrival is before departure.",
        ],
        "ios.newTrip.route": [
            .zhHans: "路线", .zhHant: "路線", .ja: "経路", .en: "Route",
        ],
        "ios.newTrip.searching": [
            .zhHans: "正在搜索路线", .zhHant: "正在搜尋路線",
            .ja: "経路を検索中", .en: "Searching routes",
        ],
        "ios.newTrip.multipleRoutes": [
            .zhHans: "有多条路线连接这些车站，请选择一条",
            .zhHant: "有多條路線連接這些車站，請選擇一條",
            .ja: "これらの駅を結ぶ経路が複数あります。1つ選んでください",
            .en: "Multiple routes connect these stations — choose one",
        ],
        "ios.newTrip.stationCount": [
            .zhHans: "{count}个车站", .zhHant: "{count}個車站",
            .ja: "{count}駅", .en: "{count} stations",
        ],
        "ios.newTrip.stationCountDistance": [
            .zhHans: "{count}个车站 · {km}公里", .zhHant: "{count}個車站 · {km}公里",
            .ja: "{count}駅 · {km} km", .en: "{count} stations · {km} km",
        ],
        "ios.newTrip.throughService": [
            .zhHans: "在{station}直通运行", .zhHant: "在{station}直通運行",
            .ja: "{station}で直通運転", .en: "Through service at {station}",
        ],
        "ios.newTrip.continuesAt": [
            .zhHans: "在{station}继续", .zhHant: "在{station}繼續",
            .ja: "{station}で継続", .en: "Continues at {station}",
        ],
        "ios.newTrip.disconnected": [
            .zhHans: "这些线路并不相连，一趟列车无法这样运行。请在以下车站换乘：{changes}",
            .zhHant: "這些路線並不相連，一班列車無法這樣運行。請在以下車站轉乘：{changes}",
            .ja: "これらの路線はつながっていません。1本の列車では走れません。乗り換え：{changes}",
            .en: "These lines are not connected — one train cannot run this way. Change trains at: {changes}",
        ],
        "ios.newTrip.changeAt": [
            .zhHans: "{station}（{from} → {to}）", .zhHant: "{station}（{from} → {to}）",
            .ja: "{station}（{from} → {to}）", .en: "{station} ({from} → {to})",
        ],
        "ios.newTrip.addLegs": [
            .zhHans: "请将每一段分别添加为一次行程。", .zhHant: "請將每一段分別新增為一次行程。",
            .ja: "各区間を別の乗車として追加してください。", .en: "Add each leg as its own trip.",
        ],
        "ios.newTrip.noRoute": [
            .zhHans: "这些车站之间没有铁路连接。", .zhHant: "這些車站之間沒有鐵路連接。",
            .ja: "これらの駅を結ぶ鉄道路線はありません。", .en: "No rail connection between these stations.",
        ],
        "ios.newTrip.noCompanyRoute": [
            .zhHans: "这些车站之间没有由{company}运营的路线。",
            .zhHant: "這些車站之間沒有由{company}營運的路線。",
            .ja: "これらの駅の間に{company}が運行する経路はありません。",
            .en: "No route between these stations is operated by {company}.",
        ],
        "ios.newTrip.sameStation": [
            .zhHans: "请选择两个不同的车站。", .zhHant: "請選擇兩個不同的車站。",
            .ja: "別々の駅を2つ選んでください。", .en: "Choose two different stations.",
        ],
        "ios.newTrip.truncated": [
            .zhHans: "搜索范围太大。请选择公司，或更换列车类型。",
            .zhHant: "搜尋範圍太大。請選擇公司，或更換列車類型。",
            .ja: "検索範囲が広すぎます。会社を選ぶか、列車種別を変えてください。",
            .en: "The search was too large. Try choosing a company or a different train type.",
        ],
        "ios.newTrip.passStations": [
            .zhHans: "此路线上的车站（{count}）", .zhHant: "此路線上的車站（{count}）",
            .ja: "この経路の駅（{count}）", .en: "Stations on this route ({count})",
        ],
        "ios.newTrip.lineChange": [
            .zhHans: "{from} → {to}", .zhHant: "{from} → {to}",
            .ja: "{from} → {to}", .en: "{from} → {to}",
        ],
        "ios.newTrip.autofillFailed": [
            .zhHans: "无法应用此路线。", .zhHant: "無法套用此路線。",
            .ja: "この経路を適用できませんでした。", .en: "This route could not be applied.",
        ],
        "ios.newTrip.loadFailed": [
            .zhHans: "无法加载该地区的铁路数据。", .zhHant: "無法載入此地區的鐵路資料。",
            .ja: "この地域の鉄道データを読み込めませんでした。",
            .en: "The rail data for this region could not be loaded.",
        ],
        "ios.newTrip.searchPrompt": [
            .zhHans: "按车站、线路或公司搜索", .zhHant: "按車站、路線或公司搜尋",
            .ja: "駅、路線、会社で検索", .en: "Search by station, line or company",
        ],
        "ios.newTrip.searchTitle": [
            .zhHans: "选择车站", .zhHant: "選擇車站", .ja: "駅を選択", .en: "Choose a station",
        ],
        "ios.newTrip.onlyCompany": [
            .zhHans: "仅{company}", .zhHant: "僅{company}",
            .ja: "{company}のみ", .en: "Only {company}",
        ],
    ]
}
