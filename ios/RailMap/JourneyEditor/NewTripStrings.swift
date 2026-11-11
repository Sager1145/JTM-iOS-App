import Foundation
import RailCore

/// Sentences for the new-trip form. Looked up through `AppLocalization.text`
/// after this table is merged in `AppStrings`.
enum NewTripStrings {
    static let table: [String: [Localization.Language: String]] = [
        "ios.newTrip.ridden": [
            .en: "I have ridden this journey", .ja: "この行程に乗車済み",
            .zhHant: "我已搭乘此行程", .zhHans: "我已乘坐此行程",
        ],
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

        "ios.newTrip.save": [
            .zhHans: "保存旅程", .zhHant: "儲存旅程", .ja: "旅程を保存", .en: "Save Trip",
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
        "ios.newTrip.historicalNotice": [
            .zhHans: "此行程使用了已停运的线路，将按 {date} 当时的路网进行核对。",
            .zhHant: "此行程使用了已停駛的路線，將依 {date} 當時的路網進行核對。",
            .ja: "この旅程には廃止された路線が含まれています。{date}当時の路線網で確認しています。",
            .en: "This trip uses a line that has since closed. It is checked against the network as it was on {date}.",
        ],
        "ios.newTrip.historicalNoRoute": [
            .zhHans: "{date} 当天没有线路连接这些车站。如果该线路已停运，请检查乘车日期，或在途中添加一个停靠站。",
            .zhHant: "{date} 當天沒有路線連接這些車站。如果該路線已停駛，請檢查乘車日期，或在途中加入一個停靠站。",
            .ja: "{date}にこれらの駅を結ぶ路線はありませんでした。路線が廃止されている場合は、乗車日を確認するか、途中の駅を追加してください。",
            .en: "No line connected these stations on {date}. If the line has closed, check the date you rode it, or add a stop along the way.",
        ],
        "ios.newTrip.historicalOwnTrip": [
            .zhHans: "请将已停运的部分另存为单独的行程，中途不加停靠站。",
            .zhHant: "請將已停駛的部分另存為單獨的行程，途中不加停靠站。",
            .ja: "廃止された区間は、途中の駅を入れずに別の旅程として保存してください。",
            .en: "Save the closed part as its own trip, without stops along the way.",
        ],
        "ios.newTrip.showHistoricalLines": [
            .zhHans: "在地图上显示历史线路", .zhHant: "在地圖上顯示歷史路線",
            .ja: "地図に廃止路線を表示", .en: "Show historical lines on the map",
        ],
        "ios.newTrip.corridorsHiddenByDate": [
            .zhHans: "部分路线因在该日期尚未开通而被隐藏。",
            .zhHant: "部分路線因在該日期尚未開通而被隱藏。",
            .ja: "この日にまだ開業していなかった一部の経路は表示されていません。",
            .en: "Some routes are hidden because they were not open on this date.",
        ],
        "ios.newTrip.noCorridorOnDate": [
            .zhHans: "该日期没有已开通的路线。", .zhHant: "該日期沒有已開通的路線。",
            .ja: "この日に開業していた経路はありません。", .en: "No route was open on this date.",
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
        "ios.newTrip.continueAnyway": [
            .en: "Continue anyway", .ja: "このまま続ける", .zhHant: "仍要繼續", .zhHans: "仍要继续",
        ],
        "ios.newTrip.continueAnywayExplanation": [
            .en: "Treat the listed stations as through-running connections.",
            .ja: "表示された駅で直通運転できるものとして続けます。",
            .zhHant: "將所列車站視為可直通運行的接續點。", .zhHans: "将所列车站视为可直通运行的接续点。",
        ],
        "ios.newTrip.unverifiedConnection": [
            .en: "Unverified connection at {station}", .ja: "{station}での接続は未確認",
            .zhHant: "{station}的接續尚未確認", .zhHans: "{station}的接续尚未确认",
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
        "ios.newTrip.fillDetails": [
            .en: "Fill in trip details", .ja: "行程の詳細を入力",
            .zhHant: "填入行程詳細", .zhHans: "填入行程详情",
        ],
        "ios.newTrip.tripDetails": [
            .en: "Trip details", .ja: "行程の詳細",
            .zhHant: "行程詳細", .zhHans: "行程详情",
        ],
        "ios.newTrip.fillDetailsNote": [
            .en: "Timetables, the line's services, and ChatGPT or pasted text, in one list.", .ja: "時刻表、路線の列車種別、ChatGPT または貼り付けたテキストをひとつの一覧で。",
            .zhHant: "時刻表、路線的列車種別，以及 ChatGPT 或貼上的文字，集中在一個清單。", .zhHans: "时刻表、线路的列车种别，以及 ChatGPT 或粘贴的文字，集中在一个列表。",
        ],
        "ios.newTrip.completeWithText": [
            .en: "ChatGPT or pasted text", .ja: "ChatGPT または貼り付けたテキスト",
            .zhHant: "ChatGPT 或貼上的文字", .zhHans: "ChatGPT 或粘贴的文字",
        ],
        "ios.newTrip.completeWithTextNote": [
            .en: "Review every proposed change before it is applied.", .ja: "適用する前に、提案された変更をすべて確認します。",
            .zhHant: "套用前會先檢視每一項建議的變更。", .zhHans: "应用前会先查看每一项建议的更改。",
        ],
        "ios.newTrip.savedRoute": [
            .en: "Saved route", .ja: "保存済みの経路",
            .zhHant: "已儲存的路線", .zhHans: "已保存的路线",
        ],
        "ios.newTrip.repairChoose": [
            .en: "Choose the route between {from} and {to}", .ja: "{from}と{to}の間の経路を選んでください",
            .zhHant: "請選擇{from}與{to}之間的路線", .zhHans: "请选择{from}与{to}之间的路线",
        ],
        "ios.newTrip.repairSkip": [
            .en: "Leave this part as it is", .ja: "この区間はそのままにする",
            .zhHant: "此區段保持不變", .zhHans: "此区段保持不变",
        ],
        "ios.newTrip.repairing": [
            .en: "Repairing route", .ja: "経路を修復中",
            .zhHant: "正在修復路線", .zhHans: "正在修复路线",
        ],
        "ios.newTrip.trainTypeNotSet": [
            .en: "Not set", .ja: "未設定",
            .zhHant: "未設定", .zhHans: "未设置",
        ],
        "ios.newTrip.moreDetails": [
            .en: "More details", .ja: "その他の詳細",
            .zhHant: "更多詳細資料", .zhHans: "更多详细信息",
        ],
        "ios.newTrip.fewerDetails": [
            .en: "Fewer details", .ja: "詳細を隠す",
            .zhHant: "收起詳細資料", .zhHans: "收起详细信息",
        ],
        "ios.newTrip.stopsNote": [
            .en: "To change the route, pick other stations or add a stop on the map.", .ja: "経路を変えるには、地図で別の駅を選ぶか経由駅を追加します。",
            .zhHant: "若要變更路線，請在地圖上選擇其他車站或新增途經站。", .zhHans: "若要更改路线，请在地图上选择其他车站或添加途经站。",
        ],
        "ios.newTrip.pickOnMap": [
            .en: "Tap a station on the map, or search", .ja: "地図で駅をタップするか、検索します",
            .zhHant: "在地圖上點選車站，或搜尋", .zhHans: "在地图上点选车站，或搜索",
        ],
        "ios.newTrip.directionUnknown": [
            .en: "Direction not known", .ja: "方向不明",
            .zhHant: "方向未知", .zhHans: "方向未知",
        ],
        "ios.newTrip.boundFor": [
            .en: "Toward {name}", .ja: "{name}方面",
            .zhHant: "{name}方向", .zhHans: "{name}方向",
        ],
        "ios.newTrip.boundForTitle": [
            .en: "Bound for", .ja: "方面",
            .zhHant: "方向", .zhHans: "方向",
        ],
        "ios.newTrip.boundForChoose": [
            .en: "Choose", .ja: "選択",
            .zhHant: "選擇", .zhHans: "选择",
        ],
        "ios.newTrip.boundForOther": [
            .en: "Other…", .ja: "その他…",
            .zhHant: "其他…", .zhHans: "其他…",
        ],
        "ios.newTrip.boundForClear": [
            .en: "Clear", .ja: "クリア",
            .zhHant: "清除", .zhHans: "清除",
        ],
        "ios.newTrip.platformAdd": [
            .en: "+ Platform", .ja: "+ 番線",
            .zhHant: "+ 月台", .zhHans: "+ 站台",
        ],
        "ios.newTrip.platformOther": [
            .en: "Other", .ja: "その他",
            .zhHant: "其他", .zhHans: "其他",
        ],
        "ios.newTrip.platformClear": [
            .en: "Clear", .ja: "クリア",
            .zhHant: "清除", .zhHans: "清除",
        ],
        "ios.newTrip.vehicleSuggestions": [
            .en: "Suggestions", .ja: "候補",
            .zhHant: "建議", .zhHans: "建议",
        ],
        "ios.newTrip.vehicleAdd": [
            .en: "Add", .ja: "追加",
            .zhHant: "新增", .zhHans: "添加",
        ],
        "ios.newTrip.missingPlatforms": [
            .en: "{count} platforms", .ja: "番線 {count} 件",
            .zhHant: "{count} 個月台", .zhHans: "{count} 个站台",
        ],
        "ios.newTrip.needsDetails": [
            .en: "Still missing: {items}", .ja: "未入力：{items}",
            .zhHant: "尚未填寫：{items}", .zhHans: "尚未填写：{items}",
        ],
        "ios.newTrip.platforms": [
            .en: "Platforms", .ja: "番線",
            .zhHant: "月台", .zhHans: "站台",
        ],
        "ios.newTrip.departureShort": [
            .en: "Dep.", .ja: "発",
            .zhHant: "發", .zhHans: "发",
        ],
        "ios.newTrip.arrivalShort": [
            .en: "Arr.", .ja: "着",
            .zhHant: "到", .zhHans: "到",
        ],
        "ios.newTrip.enterByHand": [
            .en: "Enter the rest by hand", .ja: "残りを手入力する",
            .zhHant: "其餘手動填寫", .zhHans: "其余手动填写",
        ],
        "ios.newTrip.filterCompany": [
            .en: "Company", .ja: "会社",
            .zhHant: "公司", .zhHans: "公司",
        ],
        "ios.newTrip.filterLine": [
            .en: "Line", .ja: "路線",
            .zhHant: "路線", .zhHans: "线路",
        ],
        "ios.newTrip.filterClear": [
            .en: "Clear filters", .ja: "絞り込みを解除",
            .zhHant: "清除篩選", .zhHans: "清除筛选",
        ],
        "ios.newTrip.dateHint": [
            .en: "YYYY-MM-DD", .ja: "年-月-日",
            .zhHant: "年-月-日", .zhHans: "年-月-日",
        ],
        "ios.newTrip.dateForms": [
            .en: "e.g. 2026-11-05, 11/05 or 1105", .ja: "例：2026-11-05、11/05、1105",
            .zhHant: "例如 2026-11-05、11/05、1105", .zhHans: "例如 2026-11-05、11/05、1105",
        ],
        "ios.newTrip.dateInvalid": [
            .en: "Not a date. Try 2026-11-05, 11/05 or 1105.", .ja: "日付として読めません。2026-11-05、11/05、1105 の形で入力してください。",
            .zhHant: "無法辨識日期。請輸入 2026-11-05、11/05 或 1105。", .zhHans: "无法识别日期。请输入 2026-11-05、11/05 或 1105。",
        ],
        "ios.newTrip.timeInvalid": [
            .en: "Not a time. Try 9:30 or 0930.", .ja: "時刻として読めません。9:30 または 0930 の形で入力してください。",
            .zhHant: "無法辨識時間。請輸入 9:30 或 0930。", .zhHans: "无法识别时间。请输入 9:30 或 0930。",
        ],
        "ios.newTrip.openCalendar": [
            .en: "Calendar", .ja: "カレンダー",
            .zhHant: "月曆", .zhHans: "日历",
        ],
        "ios.newTrip.sectionTitle": [
            .en: "Section {n} of {count}: {from} → {to}", .ja: "区間 {n}/{count}：{from} → {to}",
            .zhHant: "第 {n}/{count} 段：{from} → {to}", .zhHans: "第 {n}/{count} 段：{from} → {to}",
        ],
        "ios.newTrip.sectionsToChoose": [
            .en: "{count} sections still to choose before the stations are filled in", .ja: "あと {count} 区間を選ぶと、通過駅が入力されます",
            .zhHant: "尚有 {count} 段需選擇，選完後會填入經過的車站", .zhHans: "还有 {count} 段需选择，选完后会填入经过的车站",
        ],
        "ios.newTrip.sectionNoRoute": [
            .en: "No route", .ja: "経路なし",
            .zhHant: "沒有路線", .zhHans: "没有路线",
        ],
        "ios.newTrip.sectionOptions": [
            .en: "{count} options", .ja: "候補 {count} 件",
            .zhHant: "{count} 個選項", .zhHans: "{count} 个选项",
        ],
        "ios.newTrip.didYouMean": [
            .en: "Did you mean {text}?", .ja: "もしかして：{text}",
            .zhHant: "您是不是要找：{text}", .zhHans: "您是不是要找：{text}",
        ],
        "ios.newTrip.journey": [
            .en: "Journey", .ja: "行程",
            .zhHant: "行程", .zhHans: "行程",
        ],
        "ios.newTrip.scanTicket": [
            .en: "Scan ticket", .ja: "きっぷを読み取る",
            .zhHant: "掃描車票", .zhHans: "扫描车票",
        ],
        "ios.newTrip.findTrain": [
            .en: "Find train", .ja: "列車を探す",
            .zhHant: "尋找列車", .zhHans: "查找列车",
        ],
        "ios.newTrip.ticketFilled": [
            .en: "Filled {count} fields from the ticket. Check them below.", .ja: "きっぷから{count}項目を入力しました。下で確認してください。",
            .zhHant: "已從車票填入 {count} 個欄位，請在下方確認。", .zhHans: "已从车票填入 {count} 个字段，请在下方确认。",
        ],
        "ios.newTrip.ticketFilledNone": [
            .en: "Nothing on the ticket could be used.", .ja: "きっぷから使える情報がありませんでした。",
            .zhHant: "車票上沒有可用的資訊。", .zhHans: "车票上没有可用的信息。",
        ],
        "ios.newTrip.quickFillNote": [
            .en: "A ticket or timetable fills what it knows. Fields you change are never overwritten.", .ja: "きっぷや時刻表で分かる項目を自動入力します。自分で変更した項目は上書きされません。",
            .zhHant: "車票或時刻表會填入已知的欄位，您修改過的欄位不會被覆寫。", .zhHans: "车票或时刻表会填入已知的字段，您修改过的字段不会被覆盖。",
        ],
        "ios.newTrip.fillSource.ticket": [
            .en: "Ticket", .ja: "きっぷ",
            .zhHant: "車票", .zhHans: "车票",
        ],
        "ios.newTrip.fillSource.timetable": [
            .en: "Timetable", .ja: "時刻表",
            .zhHant: "時刻表", .zhHans: "时刻表",
        ],
        "ios.newTrip.fillSource.nearby": [
            .en: "Nearby", .ja: "現在地",
            .zhHant: "附近", .zhHans: "附近",
        ],
        "ios.newTrip.nearbyStation": [
            .en: "{station} · {distance} m", .ja: "{station}・{distance} m",
            .zhHant: "{station}・{distance} 公尺", .zhHans: "{station}・{distance} 米",
        ],
        "ios.newTrip.nearby": [
            .en: "Stations near you", .ja: "近くの駅",
            .zhHant: "附近車站", .zhHans: "附近车站",
        ],
        "ios.newTrip.timeFilled": [
            .en: "Check the time; changing it keeps your value.", .ja: "時刻を確認してください。変更した値はそのまま保持されます。",
            .zhHant: "請確認時間；修改後會保留您的設定。", .zhHans: "请确认时间；修改后会保留您的设置。",
        ],
        "ios.newTrip.trainNumberShort": [
            .en: "Train", .ja: "列車",
            .zhHant: "列車", .zhHans: "列车",
        ],
        "ios.newTrip.suggestionHint": [
            .en: "Fills in this value", .ja: "この値を入力します",
            .zhHant: "填入此值", .zhHans: "填入此值",
        ],
        "ios.newTrip.setNumber": [
            .en: "Set", .ja: "編成",
            .zhHant: "編組", .zhHans: "编组",
        ],
        "ios.newTrip.carCount": [
            .en: "Cars", .ja: "両数",
            .zhHant: "節數", .zhHans: "节数",
        ],
        "ios.newTrip.riddenCar": [
            .en: "Car ridden", .ja: "乗車号車",
            .zhHant: "搭乘車廂", .zhHans: "乘坐车厢",
        ],
        "ios.newTrip.carNumbers": [
            .en: "Car numbers", .ja: "車両番号",
            .zhHant: "車號", .zhHans: "车号",
        ],
        "ios.newTrip.livery": [
            .en: "Livery", .ja: "塗装",
            .zhHant: "塗裝", .zhHans: "涂装",
        ],
        "ios.newTrip.vehicle": [
            .en: "Train and car", .ja: "車両",
            .zhHant: "車輛", .zhHans: "车辆",
        ],
        "ios.newTrip.carRow": [
            .en: "Car {n}", .ja: "{n}号車",
            .zhHant: "第 {n} 車", .zhHans: "第 {n} 节",
        ],
        "ios.newTrip.carNumber": [
            .en: "Number", .ja: "番号",
            .zhHant: "號碼", .zhHans: "号码",
        ],
        "ios.newTrip.carNumbersNote": [
            .en: "Set Cars first to list every car of the set.", .ja: "先に両数を入れると編成の全車両が並びます。",
            .zhHant: "先填寫節數即可列出整組車廂。", .zhHans: "先填写节数即可列出整组车厢。",
        ],
        "ios.newTrip.seat": [
            .en: "Seat", .ja: "座席",
            .zhHant: "座位", .zhHans: "座位",
        ],
        "ios.newTrip.seatClass": [
            .en: "Class", .ja: "設備",
            .zhHant: "車廂等級", .zhHans: "车厢等级",
        ],
        "ios.newTrip.fare": [
            .en: "Fare", .ja: "運賃・料金",
            .zhHant: "票價", .zhHans: "票价",
        ],
        "ios.newTrip.ticketKind": [
            .en: "Ticket", .ja: "券種",
            .zhHant: "票種", .zhHans: "票种",
        ],
        "ios.newTrip.ticketKindNone": [
            .en: "Not set", .ja: "未設定",
            .zhHant: "未設定", .zhHans: "未设置",
        ],
        "ios.newTrip.ticket": [
            .en: "Ticket", .ja: "きっぷ",
            .zhHant: "車票", .zhHans: "车票",
        ],
        "ios.newTrip.addActualTimes": [
            .en: "Add actual times", .ja: "実際の時刻を追加",
            .zhHant: "加入實際時間", .zhHans: "添加实际时间",
        ],
        "ios.newTrip.delayOnTime": [
            .en: "On time", .ja: "定刻",
            .zhHant: "準點", .zhHans: "准点",
        ],
        "ios.newTrip.delayPlus": [
            .en: "+{minutes} min", .ja: "+{minutes}分",
            .zhHant: "+{minutes} 分", .zhHans: "+{minutes} 分",
        ],
        "ios.newTrip.delayCustom": [
            .en: "Custom", .ja: "その他",
            .zhHant: "自訂", .zhHans: "自定义",
        ],
    ]
}
