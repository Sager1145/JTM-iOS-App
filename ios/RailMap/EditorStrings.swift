import Foundation
import RailCore

/// The strings the editor, the journey detail and the route-state surface need
/// that the web catalog does not carry.
///
/// Same shape and same reason as ``DataStrings``: `AppLocalization` owns a
/// table like this one, but it is another port's file, so adding to it from
/// here would be an edit to work in flight. The lookup goes through the shared
/// engine FIRST — a key the web app already spells (`btn.rebuildRoute`,
/// `status.routeNoPath`, `stoptype.pass_through`) keeps the web app's own
/// wording in every language — and only falls back to this table for the
/// sentences the native editor invented.
///
/// Every entry carries all four interface languages. A fallback string is an
/// English string, and an English string shown to a reader who chose 日本語 is
/// a localisation bug that compiles — which is exactly what the editor was
/// full of before this slice: `"From station"`, `"Discard changes?"` and two
/// dozen others were `String` literals with no table behind them at all.
enum EditorStrings {

    static let table: [String: [Localization.Language: String]] = [
        "ios.editor.vehicleSearchNote": [
            .zhHans: "输入以查找建议，也可以填写自定义内容。车辆类型建议来自已保存的行程。",
            .zhHant: "輸入以查找建議，也可以填寫自訂內容。車輛類型建議來自已儲存的行程。",
            .ja: "入力して候補を検索するか、自由に記入できます。車両形式の候補は保存済みの旅程から表示されます。",
            .en: "Type to find suggestions or enter your own value. Vehicle suggestions come from saved journeys.",
        ],
        "ios.editor.step.region": [
            .zhHans: "选择地区",
            .zhHant: "選擇地區",
            .ja: "地域を選択",
            .en: "Choose a region",
        ],
        "ios.editor.step.route": [
            .zhHans: "车站与线路",
            .zhHant: "車站與路線",
            .ja: "駅と路線",
            .en: "Stations and lines",
        ],
        "ios.editor.step.service": [
            .zhHans: "列车与车辆",
            .zhHant: "列車與車輛",
            .ja: "列車と車両",
            .en: "Train and vehicle",
        ],
        "ios.editor.step.date": [
            .zhHans: "日期与乘坐状态",
            .zhHant: "日期與乘坐狀態",
            .ja: "日付と乗車状況",
            .en: "Date and ride status",
        ],
        "ios.editor.step.confirm": [
            .zhHans: "确认行程",
            .zhHant: "確認行程",
            .ja: "旅程を確認",
            .en: "Review journey",
        ],
        "ios.editor.step.regionNote": [
            .zhHans: "先选择行程所在地区，以显示对应的车站和线路。",
            .zhHant: "先選擇行程所在地區，以顯示對應的車站和路線。",
            .ja: "地域を選ぶと、その地域の駅と路線を検索できます。",
            .en: "Choose the region to search its stations and lines.",
        ],
        "ios.editor.step.routeNote": [
            .zhHans: "依次选择出发站、到达站和途经站，可输入搜索线路。",
            .zhHant: "依序選擇出發站、到達站和途經站，可輸入搜尋路線。",
            .ja: "出発駅・到着駅・経由駅を指定し、路線を検索できます。",
            .en: "Choose departure, arrival and intermediate stops. Search for a line if needed.",
        ],
        "ios.editor.step.serviceNote": [
            .zhHans: "填写列车名称或车次，车型和车辆类型可选。",
            .zhHant: "填寫列車名稱或車次，車種和車輛類型可選。",
            .ja: "列車名や番号を入力します。種別と車両形式は任意です。",
            .en: "Enter a train name or number. Service and vehicle types are optional.",
        ],
        "ios.editor.step.dateNote": [
            .zhHans: "输入日期或从日历选择，也可以暂不填写日期。",
            .zhHant: "輸入日期或從日曆選擇，也可以暫不填寫日期。",
            .ja: "日付を入力するか、カレンダーで選択します。日付なしでも保存できます。",
            .en: "Type a date or use the calendar. You can also leave the journey undated.",
        ],
        "ios.editor.step.confirmNote": [
            .zhHans: "检查以下信息。可以返回修改，确认保存后才会加入行程。",
            .zhHant: "檢查以下資訊。可以返回修改，確認儲存後才會加入行程。",
            .ja: "内容を確認してください。戻って修正できます。保存すると旅程が追加されます。",
            .en: "Check your details. Go back to make changes, or save to add this journey.",
        ],
        "ios.editor.previous": [
            .zhHans: "上一步",
            .zhHant: "上一步",
            .ja: "戻る",
            .en: "Previous",
        ],
        "ios.editor.next": [
            .zhHans: "下一步",
            .zhHant: "下一步",
            .ja: "次へ",
            .en: "Next",
        ],
        "ios.editor.stepCount": [
            .zhHans: "第 {current} 步，共 {total} 步",
            .zhHant: "第 {current} 步，共 {total} 步",
            .ja: "{total} ステップ中 {current}",
            .en: "Step {current} of {total}",
        ],
        "ios.editor.changeRegion": [
            .zhHans: "更改地区？",
            .zhHant: "更改地區？",
            .ja: "地域を変更しますか？",
            .en: "Change region?",
        ],
        "ios.editor.resetRoute": [
            .zhHans: "更改地区并重选车站",
            .zhHant: "更改地區並重選車站",
            .ja: "変更して駅を選び直す",
            .en: "Change region and reset route",
        ],
        "ios.editor.changeRegionNote": [
            .zhHans: "已选择的车站和线路将被清除，其他信息会保留。",
            .zhHant: "已選擇的車站和路線將被清除，其他資訊會保留。",
            .ja: "選択した駅と路線は消去されます。他の入力内容は保持されます。",
            .en: "Selected stations and lines will be cleared. Other details will be kept.",
        ],
        "ios.editor.noDate": [
            .zhHans: "未指定日期",
            .zhHant: "未指定日期",
            .ja: "日付なし",
            .en: "Undated",
        ],
        "ios.editor.yes": [
            .zhHans: "是",
            .zhHant: "是",
            .ja: "はい",
            .en: "Yes",
        ],
        "ios.editor.no": [
            .zhHans: "否",
            .zhHant: "否",
            .ja: "いいえ",
            .en: "No",
        ],
        "ios.editor.partly": [
            .zhHans: "部分已乘坐",
            .zhHant: "部分已乘坐",
            .ja: "一部乗車済み",
            .en: "Partly ridden",
        ],


        "ios.editor.serviceType.local": [
            .zhHant: "普通",
            .zhHans: "普通",
            .ja: "普通",
            .en: "Local",
        ],
        "ios.editor.serviceType.rapid": [
            .zhHant: "快速",
            .zhHans: "快速",
            .ja: "快速",
            .en: "Rapid",
        ],
        "ios.editor.serviceType.express": [
            .zhHant: "急行",
            .zhHans: "急行",
            .ja: "急行",
            .en: "Express",
        ],
        "ios.editor.serviceType.limitedExpress": [
            .zhHant: "特急",
            .zhHans: "特急",
            .ja: "特急",
            .en: "Limited express",
        ],
        "ios.editor.serviceType.highSpeed": [
            .zhHant: "高速鐵路",
            .zhHans: "高速铁路",
            .ja: "高速鉄道",
            .en: "High-speed rail",
        ],
        "ios.editor.reorderStops": [
            .zhHant: "調整順序", .zhHans: "调整顺序", .ja: "並べ替え", .en: "Reorder",
        ],
        "ios.editor.finishReordering": [
            .zhHant: "完成排序", .zhHans: "完成排序", .ja: "並べ替えを完了", .en: "Done reordering",
        ],
        "ios.editor.vehicleType": [
            .zhHant: "車輛型號／類型",
            .zhHans: "车辆型号／类型",
            .ja: "車両形式・種類",
            .en: "Vehicle model / type",
        ],
        "ios.editor.chooseDate": [
            .zhHant: "選擇日期",
            .zhHans: "选择日期",
            .ja: "日付を選択",
            .en: "Choose date",
        ],
        "ios.editor.searchLines": [
            .zhHant: "搜尋線路",
            .zhHans: "搜索线路",
            .ja: "路線を検索",
            .en: "Search lines",
        ],
        "ios.editor.serviceDetails": [
            .zhHant: "列車與線路（選填）",
            .zhHans: "列车与线路（选填）",
            .ja: "列車と路線（任意）",
            .en: "Train & lines (optional)",
        ],
        "ios.editor.searchDetailsNote": [
            .zhHant: "輸入以搜尋建議，也可以直接填寫。線路會作為路徑偏好。車輛型號的建議來自已儲存的行程。",
            .zhHans: "输入以搜索建议，也可以直接填写。线路会作为路径偏好。车辆型号的建议来自已保存的行程。",
            .ja: "入力すると候補を検索できます。自由入力も可能です。路線は経路の優先条件になり、車両形式の候補は保存済みの記録から表示されます。",
            .en: "Type to find suggestions or enter your own value. Lines are routing preferences. Vehicle suggestions come from saved journeys.",
        ],
        "ios.editor.selectedLines": [
            .zhHant: "已選線路",
            .zhHans: "已选线路",
            .ja: "選択した路線",
            .en: "Selected lines",
        ],
        "ios.editor.removeLine": [
            .zhHant: "點一下以移除此線路",
            .zhHans: "点按以移除此线路",
            .ja: "タップして路線を解除",
            .en: "Tap to remove this line",
        ],
        "ios.editor.lineSelected": [
            .zhHant: "已選擇",
            .zhHans: "已选择",
            .ja: "選択済み",
            .en: "Selected",
        ],
        "ios.editor.useEntered": [
            .zhHant: "使用「{value}」",
            .zhHans: "使用“{value}”",
            .ja: "「{value}」を使用",
            .en: "Use “{value}”",
        ],
        "ios.editor.noLineMatches": [
            .zhHant: "沒有符合的線路。可輸入線路名稱並加入。",
            .zhHans: "没有匹配的线路。可输入线路名称并添加。",
            .ja: "一致する路線がありません。路線名を入力して追加できます。",
            .en: "No matching lines. You can enter and add a line name.",
        ],
        "ios.editor.lineSearchPrompt": [
            .zhHant: "線路、羅馬字或營運商",
            .zhHans: "线路、罗马字或运营商",
            .ja: "路線名・ローマ字・事業者",
            .en: "Line, romanized name, or operator",
        ],
        "ios.editor.reviewRequired": [
            .zhHant: "檢查必填資訊", .zhHans: "检查必填信息",
            .ja: "必須項目を確認", .en: "Review required details",
        ],
        "ios.editor.stationGuide": [
            .zhHant: "選擇車站，或輸入車站名稱。", .zhHans: "选择车站，或输入车站名称。",
            .ja: "駅を選ぶか、駅名を入力してください。", .en: "Choose a station or enter its name.",
        ],
        "ios.editor.includeDate": [
            .zhHant: "加入日期", .zhHans: "添加日期", .ja: "日付を追加", .en: "Include a date",
        ],
        "ios.editor.newGuide": [
            .zhHant: "填寫列車與車站。其他細節可以稍後補上。",
            .zhHans: "填写列车与车站。其他细节可以稍后补上。",
            .ja: "駅と列車の情報を入力しましょう。その他の詳細は後から追加できます。",
            .en: "Add your train and stops. You can fill in other details later.",
        ],
        "ios.editor.optionalDetails": [
            .zhHant: "選填資訊與進階設定",
            .zhHans: "选填信息与高级设置",
            .ja: "任意の詳細と詳細設定",
            .en: "Optional details & settings",
        ],
        "ios.editor.requiredGuide": [
            .zhHant: "填寫列車名稱並選擇至少兩個車站，即可儲存旅程。",
            .zhHans: "填写列车名称并选择至少两个车站，即可保存旅程。",
            .ja: "列車名と2つ以上の駅を入力して保存します。",
            .en: "Enter a train name and at least two stations to save your journey.",
        ],
        "ios.editor.beforeSaving": [
            .zhHant: "儲存前",
            .zhHans: "保存前",
            .ja: "保存する前に",
            .en: "Before saving",
        ],
        "ios.editor.chooseOrigin": [
            .zhHant: "選擇出發站",
            .zhHans: "选择出发站",
            .ja: "出発駅を選択",
            .en: "Choose departure station",
        ],
        "ios.editor.chooseDestination": [
            .zhHant: "選擇抵達站",
            .zhHans: "选择到达站",
            .ja: "到着駅を選択",
            .en: "Choose arrival station",
        ],

        // MARK: - §5.5 route resolution — the five user-visible states

        "ios.route.section": [
            .zhHant: "路線狀態", .zhHans: "路线状态", .ja: "経路の状態", .en: "Route state",
        ],
        "ios.route.preparing": [
            .zhHant: "準備路線", .zhHans: "准备路线", .ja: "経路を準備中", .en: "Preparing route",
        ],
        "ios.route.preparingDetail": [
            .zhHant: "尚未開始求解這趟行程的鐵路路徑。",
            .zhHans: "尚未开始求解这趟行程的铁路路径。",
            .ja: "この乗車記録の経路探索はまだ始まっていません。",
            .en: "Solving has not started for this journey yet.",
        ],
        "ios.route.resolving": [
            .zhHant: "正在重建路線", .zhHans: "正在重建路线", .ja: "経路を再構築中", .en: "Rebuilding route",
        ],
        "ios.route.resolvingDetail": [
            .zhHant: "正在依停站與線路約束求解鐵路路徑。可以繼續瀏覽。",
            .zhHans: "正在依停靠站与线路约束求解铁路路径。可以继续浏览。",
            .ja: "停車駅と路線の制約から鉄道経路を探索しています。ほかの操作は続けられます。",
            .en: "Solving a railway path from the stops and line constraints. You can keep browsing.",
        ],
        "ios.route.resolved": [
            .zhHant: "路線已生成", .zhHans: "路线已生成", .ja: "経路を生成しました", .en: "Route generated",
        ],
        "ios.route.resolvedDetail": [
            .zhHant: "{count} 個區間都畫在實測鐵路上。",
            .zhHans: "{count} 个区间都画在实测铁路上。",
            .ja: "{count} 区間すべてを実測の線形上に描画しました。",
            .en: "All {count} sections are drawn on surveyed railway.",
        ],
        "ios.route.needsReview": [
            .zhHant: "路線需要檢查", .zhHans: "路线需要检查", .ja: "経路の確認が必要です",
            .en: "Route needs review",
        ],
        "ios.route.needsReviewDetail": [
            .zhHant: "{expected} 個區間畫出了 {solved} 個；其餘區間沒有找到符合目前線路約束的路徑。",
            .zhHans: "{expected} 个区间画出了 {solved} 个；其余区间没有找到符合当前线路约束的路径。",
            .ja: "{expected} 区間のうち {solved} 区間を描画しました。残りは現在の路線制約に合う経路が見つかりません。",
            .en: "{solved} of {expected} sections drew. The rest found no path that fits the current line constraints.",
        ],
        "ios.route.unavailable": [
            .zhHant: "無法繪製路線", .zhHans: "无法绘制路线", .ja: "経路を描画できません",
            .en: "Route unavailable",
        ],
        "ios.route.unavailableDetail": [
            .zhHant: "這趟行程的 {expected} 個區間都沒有找到符合目前線路約束的路徑。",
            .zhHans: "这趟行程的 {expected} 个区间都没有找到符合当前线路约束的路径。",
            .ja: "この乗車記録の {expected} 区間すべてで、現在の路線制約に合う経路が見つかりませんでした。",
            .en: "None of this journey's {expected} sections found a path that fits the current line constraints.",
        ],
        "ios.route.noSections": [
            .zhHant: "尚無可繪製的路線", .zhHans: "尚无可绘制的路线", .ja: "描画できる経路がありません",
            .en: "No drawable route yet",
        ],
        "ios.route.noSectionsDetail": [
            .zhHant: "這趟行程還沒有標記為已乘坐的相鄰停站，因此沒有可求解的區間。",
            .zhHans: "这趟行程还没有标记为已乘坐的相邻停靠站，因此没有可求解的区间。",
            .ja: "乗車済みとして連続する停車駅がないため、探索できる区間がありません。",
            .en: "No two adjacent stops are marked as ridden, so there is no section to solve.",
        ],
        // §13.3 line three: what was kept. §1.1: never a straight line.
        "ios.route.recordKept": [
            .zhHant: "行程記錄與停站沒有改變，也沒有用直線代替鐵路。",
            .zhHans: "行程记录与停靠站没有改变，也没有用直线代替铁路。",
            .ja: "乗車記録と停車駅は変更されていません。直線での代替描画も行っていません。",
            .en: "The journey record and its stops are unchanged, and no straight line stood in for railway.",
        ],
        "ios.route.affected": [
            .zhHant: "受影響區間", .zhHans: "受影响区间", .ja: "影響のある区間",
            .en: "Affected sections",
        ],
        "ios.route.affectedSection": [
            .zhHant: "第 {index} 段 · {from} → {to}",
            .zhHans: "第 {index} 段 · {from} → {to}",
            .ja: "第 {index} 区間 · {from} → {to}",
            .en: "Section {index} · {from} → {to}",
        ],
        "ios.route.unnamedStation": [
            .zhHant: "未命名車站", .zhHans: "未命名车站", .ja: "駅名未設定", .en: "Unnamed station",
        ],
        "ios.route.rebuildExplain": [
            .zhHant: "會依目前的停站與路徑約束重新生成 route sections 與幾何。停站本身不會被改動。",
            .zhHans: "会依当前的停靠站与路径约束重新生成 route sections 与几何。停靠站本身不会被改动。",
            .ja: "現在の停車駅と経路制約から route sections と形状を作り直します。停車駅そのものは変更されません。",
            .en: "Regenerates the route sections and geometry from the current stops and constraints. The stops themselves are not touched.",
        ],
        "ios.route.rebuilding": [
            .zhHant: "正在重建路線…", .zhHans: "正在重建路线…", .ja: "経路を再構築しています…",
            .en: "Rebuilding the route…",
        ],
        "ios.route.editStops": [
            .zhHant: "編輯停站", .zhHans: "编辑停靠站", .ja: "停車駅を編集", .en: "Edit stops",
        ],
        "ios.route.viewConstraints": [
            .zhHant: "查看路徑約束", .zhHans: "查看路径约束", .ja: "経路の制約を見る",
            .en: "View route constraints",
        ],
        // §8.4: a solve in flight must not let playback or a video export start.
        "ios.route.playbackBlocked": [
            .zhHant: "路線就緒前無法開始回放或影片輸出。",
            .zhHans: "路线就绪前无法开始回放或视频导出。",
            .ja: "経路が揃うまで再生と動画書き出しは開始できません。",
            .en: "Playback and video export cannot start until the route is ready.",
        ],
        "ios.route.rebuildTakesTime": [
            .zhHant: "求解會在背景進行，完成後地圖會自動更新。",
            .zhHans: "求解会在后台进行，完成后地图会自动更新。",
            .ja: "探索はバックグラウンドで行われ、完了すると地図が更新されます。",
            .en: "Solving runs in the background; the map updates when it finishes.",
        ],

        // MARK: - §5.3 journey detail

        "ios.detail.service": [
            .zhHant: "運營資訊", .zhHans: "运营信息", .ja: "運行情報", .en: "Service",
        ],
        "ios.detail.advanced": [
            .zhHant: "進階記錄資訊", .zhHans: "高级记录信息", .ja: "詳細な記録情報",
            .en: "Advanced record details",
        ],
        "ios.detail.routeSections": [
            .zhHant: "路線區間（{count}）", .zhHans: "路线区间（{count}）",
            .ja: "経路区間（{count}）", .en: "Route sections ({count})",
        ],
        "ios.detail.noRouteSections": [
            .zhHant: "尚未寫入 route_sections。", .zhHans: "尚未写入 route_sections。",
            .ja: "route_sections はまだありません。", .en: "No route_sections written yet.",
        ],
        // §7.3 / §10.4: an overnight time keeps its 24+ spelling. The detail
        // explains the crossing rather than rewriting the value into a date.
        "ios.detail.crossDay": [
            .zhHant: "這趟行程跨日。24:00 以上的時刻屬於隔天，例如 25:10 是隔天 01:10，資料裡保留原始寫法。",
            .zhHans: "这趟行程跨日。24:00 以上的时刻属于隔天，例如 25:10 是隔天 01:10，数据里保留原始写法。",
            .ja: "この乗車は日をまたぎます。24 時以降の時刻は翌日を表し（25:10 は翌日 01:10）、データは元の表記のまま保持します。",
            .en: "This journey crosses midnight. Times past 24:00 are the next day — 25:10 is 01:10 tomorrow — and the record keeps the original spelling.",
        ],
        "ios.detail.nextDay": [
            .zhHant: "隔天", .zhHans: "隔天", .ja: "翌日", .en: "Next day",
        ],
        "ios.detail.notRidden": [
            .zhHant: "未乘坐", .zhHans: "未乘坐", .ja: "乗車なし", .en: "Not ridden",
        ],
        "ios.detail.ridden": [
            .zhHant: "已乘坐", .zhHans: "已乘坐", .ja: "乗車済み", .en: "Ridden",
        ],
        "ios.detail.hiddenTitle": [
            .zhHant: "已從地圖隱藏", .zhHans: "已从地图隐藏", .ja: "地図から非表示",
            .en: "Hidden from the map",
        ],
        // §8.5: hiding changes the map, not the record or the export, and the
        // copy has to say which.
        "ios.detail.hiddenDetail": [
            .zhHant: "只影響地圖顯示。記錄、統計與匯出的 JSON 都不變。",
            .zhHans: "只影响地图显示。记录、统计与导出的 JSON 都不变。",
            .ja: "地図の表示だけが変わります。記録・統計・書き出す JSON は変わりません。",
            .en: "This only changes the map. The record, the statistics and the exported JSON are unaffected.",
        ],
        "ios.detail.showOnMap": [
            .zhHant: "在地圖上顯示", .zhHans: "在地图上显示", .ja: "地図に表示する",
            .en: "Show on the map",
        ],
        "ios.detail.hideFromMap": [
            .zhHant: "從地圖隱藏", .zhHans: "从地图隐藏", .ja: "地図から隠す",
            .en: "Hide from the map",
        ],
        // §5.3's rule, in the reader's words: the passport counts what they
        // say they rode, and the app never decides that from a date. The
        // detail copy has to carry the whole of that — what is not counted,
        // that nothing is wrong, and that one tap settles it.
        "ios.detail.notRiddenTitle": [
            .zhHant: "尚未確認乘坐", .zhHans: "尚未确认乘坐", .ja: "乗車が未確認です",
            .en: "Not confirmed as ridden",
        ],
        "ios.detail.notRiddenDetail": [
            .zhHant: "這趟行程還沒有計入里程統計。實際乘坐之後在這裡確認，日期不會替你決定。",
            .zhHans: "这趟行程还没有计入里程统计。实际乘坐之后在这里确认，日期不会替你决定。",
            .ja: "この行程はまだ距離の集計に入っていません。実際に乗った後でここで確認してください。日付が勝手に決めることはありません。",
            .en: "This journey is not in the mileage statistics yet. Confirm it here once you have travelled — the date will never decide for you.",
        ],
        "ios.detail.confirmRidden": [
            .zhHant: "確認已乘坐", .zhHans: "确认已乘坐", .ja: "乗車を確認する",
            .en: "Confirm as ridden",
        ],
        "ios.detail.markNotRidden": [
            .zhHant: "標記為未乘坐", .zhHans: "标记为未乘坐", .ja: "未乗車に戻す",
            .en: "Mark as not ridden",
        ],
        "ios.detail.riddenState": [
            .zhHant: "乘坐狀態", .zhHans: "乘坐状态", .ja: "乗車状態",
            .en: "Ridden",
        ],
        "ios.detail.riddenYes": [
            .zhHant: "已乘坐", .zhHans: "已乘坐", .ja: "乗車済み", .en: "Ridden",
        ],
        "ios.detail.riddenNo": [
            .zhHant: "未乘坐", .zhHans: "未乘坐", .ja: "未乗車", .en: "Not ridden",
        ],
        // A journey the per-stop editor left half switched on. It IS counted,
        // for the part that was ridden, so the word cannot be either of the
        // two above.
        "ios.detail.riddenPartly": [
            .zhHant: "部分區間已乘坐", .zhHans: "部分区间已乘坐",
            .ja: "一部区間のみ乗車", .en: "Partly ridden",
        ],
        // The rule, stated where the switch is. "日期不會替你決定" is the
        // whole of it and is why this note exists at all: a reader who has
        // just typed next month's date needs to know that the switch above,
        // and only the switch, decides whether it is counted.
        "ios.editor.riddenNote": [
            .zhHant: "只有這個開關決定要不要計入里程統計，日期不會替你決定。新建時會依日期先幫你選好，你可以立刻改。",
            .zhHans: "只有这个开关决定要不要计入里程统计，日期不会替你决定。新建时会按日期先帮你选好，你可以立刻改。",
            .ja: "集計に入れるかどうかを決めるのはこのスイッチだけで、日付が代わりに決めることはありません。新規作成時は日付から初期値を選んでおきますが、その場で変更できます。",
            .en: "Only this switch decides whether the journey is counted — the date never will. A new journey opens on the likely answer, and you can change it straight away.",
        ],
        "ios.editor.riddenPartlyNote": [
            .zhHant: "目前有 {n} 個區間算已乘坐。逐站調整請用下方的停站清單。",
            .zhHans: "目前有 {n} 个区间算已乘坐。逐站调整请用下方的停靠站列表。",
            .ja: "現在 {n} 区間が乗車済みです。区間ごとの調整は下の停車駅リストで行えます。",
            .en: "{n} intervals count as ridden. Adjust them one by one in the stop list below.",
        ],
        "ios.detail.stopsCount": [
            .zhHant: "{count} 個停站", .zhHans: "{count} 个停靠站", .ja: "停車駅 {count}",
            .en: "{count} stops",
        ],
        "ios.detail.platformValue": [
            .zhHant: "月台 {number}", .zhHans: "站台 {number}", .ja: "{number}番線",
            .en: "Platform {number}",
        ],

        // MARK: - §5.4 editor — groups

        "ios.editor.basics": [
            .zhHant: "基本資訊", .zhHans: "基本信息", .ja: "基本情報", .en: "Basics",
        ],
        "ios.editor.record": [
            .zhHant: "記錄資訊", .zhHans: "记录信息", .ja: "記録情報", .en: "Record details",
        ],
        "ios.editor.recordNote": [
            .zhHant: "技術欄位。ID 會決定路線快取與匯出檔案裡的鍵，新建時已自動生成。",
            .zhHans: "技术字段。ID 决定路线缓存与导出文件里的键，新建时已自动生成。",
            .ja: "技術的な項目です。ID は経路キャッシュと書き出しファイルのキーになります。新規作成時は自動生成されます。",
            .en: "Technical fields. The id keys the route cache and the exported file; a new journey already has one.",
        ],
        "ios.editor.sectionEndpoints": [
            .zhHant: "第 {index} 段：起訖各需要站名或車站代碼其中之一。",
            .zhHans: "第 {index} 段：起讫各需要站名或车站代码其中之一。",
            .ja: "区間 {index}：始終点それぞれに駅名か駅コードのどちらかが必要です。",
            .en: "Section {index}: each end needs either a station name or a station code.",
        ],
        "ios.editor.sectionCodeRule": [
            .zhHant: "第 {index} 段：車站代碼須為六位 N02_005c 或 TDX StationUID。",
            .zhHans: "第 {index} 段：车站代码须为六位 N02_005c 或 TDX StationUID。",
            .ja: "区間 {index}：駅コードは 6 桁の N02_005c か TDX StationUID である必要があります。",
            .en: "Section {index}: a station code must be a six-digit N02_005c or a TDX StationUID.",
        ],
        "ios.editor.policyCodesRule": [
            .zhHant: "允許的事業者種別只能是 N02_002 的 1／2／3／4／5。",
            .zhHans: "允许的事业者种别只能是 N02_002 的 1／2／3／4／5。",
            .ja: "許可する事業者種別は N02_002 の 1／2／3／4／5 のみです。",
            .en: "Allowed institution types must be N02_002 codes 1/2/3/4/5 only.",
        ],
        "ios.editor.policyModeRule": [
            .zhHant: "事業者篩選模式只能是 soft 或 hard。",
            .zhHans: "事业者筛选模式只能是 soft 或 hard。",
            .ja: "事業者フィルタのモードは soft か hard のみです。",
            .en: "The institution filter mode must be soft or hard.",
        ],
        "ios.editor.regionNote": [
            .zhHant: "決定這趟行程用哪一國的路網求解路線、計入哪一區的統計，以及選站時可挑哪些車站。",
            .zhHans: "决定这趟行程用哪一国的路网求解路线、计入哪一区的统计，以及选站时可挑哪些车站。",
            .ja: "この乗車をどの国の路線網で経路探索し、どの地域の統計に数え、駅選択でどの駅を出すかを決めます。",
            .en: "Which network this journey is routed on, which region's statistics it counts towards, and which stations the picker offers.",
        ],
        "ios.editor.date": [
            .zhHant: "日期", .zhHans: "日期", .ja: "日付", .en: "Date",
        ],
        "ios.editor.routeColor": [
            .zhHant: "路線顏色", .zhHans: "路线颜色", .ja: "経路の色", .en: "Route color",
        ],
        "ios.editor.visibilityNote": [
            .zhHant: "只影響地圖顯示。記錄與匯出的 JSON 不變。",
            .zhHans: "只影响地图显示。记录与导出的 JSON 不变。",
            .ja: "地図の表示だけが変わります。記録と書き出す JSON は変わりません。",
            .en: "This only changes the map. The record and the exported JSON are unaffected.",
        ],
        "ios.editor.stationsNote": [
            .zhHant: "起訖站應與停站序列的首末站一致，否則地圖與統計會以停站為準。",
            .zhHans: "起讫站应与停靠站序列的首末站一致，否则地图与统计会以停靠站为准。",
            .ja: "始発・終着は停車駅リストの最初と最後に一致させてください。一致しない場合、地図と統計は停車駅を優先します。",
            .en: "Origin and destination should match the first and last stop; where they differ, the map and statistics follow the stops.",
        ],
        "ios.editor.stopsNote": [
            .zhHant: "至少 2 個停站。順序即行駛順序，可拖曳調整。",
            .zhHans: "至少 2 个停靠站。顺序即行驶顺序，可拖动调整。",
            .ja: "停車駅は 2 つ以上必要です。並び順が走行順です（ドラッグで並べ替え）。",
            .en: "At least two stops. Their order is the running order; drag to rearrange.",
        ],
        "ios.editor.rebuildAfterSave": [
            .zhHant: "儲存停站後，可在行程詳情的「路線狀態」裡重建路線。",
            .zhHans: "保存停靠站后，可在行程详情的「路线状态」里重建路线。",
            .ja: "停車駅を保存したあと、乗車記録の「経路の状態」から経路を再構築できます。",
            .en: "After the stops are saved, rebuild the route from the journey's Route state card.",
        ],

        // MARK: - §5.4 editor — actions, in specific verbs

        "ios.editor.saveJourney": [
            .zhHant: "儲存行程", .zhHans: "保存行程", .ja: "乗車記録を保存", .en: "Save journey",
        ],
        "ios.editor.discardTitle": [
            .zhHant: "放棄未儲存的修改？", .zhHans: "放弃未保存的修改？",
            .ja: "保存していない変更を破棄しますか？", .en: "Discard unsaved changes?",
        ],
        "ios.editor.discardDetail": [
            .zhHant: "這次編輯的修改會被丟棄。已儲存的行程記錄不受影響。",
            .zhHans: "这次编辑的修改会被丢弃。已保存的行程记录不受影响。",
            .ja: "今回の編集内容は破棄されます。保存済みの記録は変わりません。",
            .en: "The changes made in this session are dropped. The saved journey is unaffected.",
        ],
        "ios.editor.discardChanges": [
            .zhHant: "放棄修改", .zhHans: "放弃修改", .ja: "変更を破棄", .en: "Discard changes",
        ],
        "ios.editor.keepEditing": [
            .zhHant: "繼續編輯", .zhHans: "继续编辑", .ja: "編集を続ける", .en: "Keep editing",
        ],
        "ios.editor.showErrors": [
            .zhHant: "查看錯誤", .zhHans: "查看错误", .ja: "エラーを見る", .en: "Show the error",
        ],
        "ios.editor.cannotSaveYet": [
            .zhHant: "還不能儲存", .zhHans: "还不能保存", .ja: "まだ保存できません",
            .en: "Not ready to save",
        ],
        "ios.editor.blockedCount": [
            .zhHant: "有 {count} 個問題擋住儲存。",
            .zhHans: "有 {count} 个问题挡住保存。",
            .ja: "保存を妨げている問題が {count} 件あります。",
            .en: "{count} problems are blocking the save.",
        ],
        "ios.editor.undoDelete": [
            .zhHant: "復原刪除", .zhHans: "撤销删除", .ja: "削除を元に戻す", .en: "Undo delete",
        ],
        "ios.editor.deletedStops": [
            .zhHant: "已刪除 {count} 個停站", .zhHans: "已删除 {count} 个停靠站",
            .ja: "{count} 駅を削除しました", .en: "Deleted {count} stops",
        ],
        "ios.editor.policyReset": [
            .zhHant: "重設為預設路徑策略", .zhHans: "重置为默认路径策略",
            .ja: "経路ポリシーを既定に戻す", .en: "Reset the route policy",
        ],

        // MARK: - §5.4 editor — the rules, said next to the field

        "ios.editor.idRequired": [
            .zhHant: "請填寫列車 ID。", .zhHans: "请填写列车 ID。",
            .ja: "列車 ID を入力してください。", .en: "Enter a train ID.",
        ],
        "ios.editor.stationCodeRule": [
            .zhHant: "車站代碼需為六位 N02_005c 或 TDX StationUID；沒有就留空。",
            .zhHans: "车站代码需为六位 N02_005c 或 TDX StationUID；没有就留空。",
            .ja: "駅コードは 6 桁の N02_005c または TDX StationUID です。無い場合は空欄にしてください。",
            .en: "A station code is a six-digit N02_005c or a TDX StationUID; leave it empty if there is none.",
        ],
        "ios.editor.idRule": [
            .zhHant: "只能使用英文字母、數字、底線與連字號。",
            .zhHans: "只能使用英文字母、数字、下划线与连字符。",
            .ja: "英数字・アンダースコア・ハイフンのみ使用できます。",
            .en: "Letters, digits, underscores and hyphens only.",
        ],
        "ios.editor.idTaken": [
            .zhHant: "「{id}」已被另一趟行程使用。儲存時不會覆蓋對方，這趟會保留原本的 ID。",
            .zhHans: "「{id}」已被另一趟行程使用。保存时不会覆盖对方，这趟会保留原本的 ID。",
            .ja: "「{id}」は別の乗車記録が使用中です。保存しても相手を上書きせず、この記録は元の ID のままになります。",
            .en: "“{id}” already belongs to another journey. Saving will not overwrite it; this journey keeps its previous id.",
        ],
        "ios.editor.numberRequired": [
            .zhHant: "請填寫車次。", .zhHans: "请填写车次。", .ja: "列車番号を入力してください。",
            .en: "Enter a train number.",
        ],
        "ios.editor.originRequired": [
            .zhHant: "請填寫起站。", .zhHans: "请填写始发站。", .ja: "始発駅を入力してください。",
            .en: "Enter an origin station.",
        ],
        "ios.editor.destinationRequired": [
            .zhHant: "請填寫終站。", .zhHans: "请填写终到站。", .ja: "終着駅を入力してください。",
            .en: "Enter a destination station.",
        ],
        "ios.editor.dateRule": [
            .zhHant: "請輸入有效日期，格式為 YYYY-MM-DD。",
            .zhHans: "请输入有效日期，格式为 YYYY-MM-DD。",
            .ja: "有効な日付を YYYY-MM-DD 形式で入力してください。",
            .en: "Enter a valid date in YYYY-MM-DD format.",
        ],
        "ios.editor.colorRule": [
            .zhHant: "路線顏色需為 #RRGGBB。留空則使用預設色。",
            .zhHans: "路线颜色需为 #RRGGBB。留空则使用默认色。",
            .ja: "経路の色は #RRGGBB 形式です。空欄なら既定色を使います。",
            .en: "Use #RRGGBB, or leave it empty for the default color.",
        ],
        "ios.editor.stopCountRule": [
            .zhHant: "至少需要 2 個停站，目前只有 {count} 個。",
            .zhHans: "至少需要 2 个停靠站，目前只有 {count} 个。",
            .ja: "停車駅は 2 つ以上必要です（現在 {count} 駅）。",
            .en: "At least two stops are needed; there are {count}.",
        ],
        "ios.editor.stopNameRequired": [
            .zhHant: "請填寫站名。", .zhHans: "请填写站名。", .ja: "駅名を入力してください。",
            .en: "Enter a station name.",
        ],
        "ios.editor.firstStopTimes": [
            .zhHant: "首站不需要同時填到達與出發時間，請刪掉其中一個。",
            .zhHans: "首站不需要同时填到达与出发时间，请删掉其中一个。",
            .ja: "最初の駅に到着と出発の両方は不要です。どちらか一方を消してください。",
            .en: "The first stop should not carry both an arrival and a departure — remove one.",
        ],
        "ios.editor.lastStopTimes": [
            .zhHant: "終站不需要同時填到達與出發時間，請刪掉其中一個。",
            .zhHans: "终站不需要同时填到达与出发时间，请删掉其中一个。",
            .ja: "最後の駅に到着と出発の両方は不要です。どちらか一方を消してください。",
            .en: "The final stop should not carry both an arrival and a departure — remove one.",
        ],
        "ios.editor.stopTypeRule": [
            .zhHant: "停站類型必須是 origin / passenger_stop / operational_stop / pass_through 之一。",
            .zhHans: "停站类型必须是 origin / passenger_stop / operational_stop / pass_through 之一。",
            .ja: "停車種別は origin / passenger_stop / operational_stop / pass_through のいずれかです。",
            .en: "Stop type must be origin, passenger_stop, operational_stop or pass_through.",
        ],
        "ios.editor.policyProblem": [
            .zhHant: "路徑策略不符合 schema 1.3，儲存會被拒絕。重設即可修正。",
            .zhHans: "路径策略不符合 schema 1.3，保存会被拒绝。重置即可修正。",
            .ja: "経路ポリシーが schema 1.3 に適合していないため保存できません。既定に戻すと解消します。",
            .en: "The route policy does not match schema 1.3, so the save is refused. Resetting it fixes this.",
        ],
        "ios.editor.otherProblem": [
            .zhHant: "這趟行程還不符合 schema 1.3。",
            .zhHans: "这趟行程还不符合 schema 1.3。",
            .ja: "この乗車記録はまだ schema 1.3 に適合していません。",
            .en: "This journey does not match schema 1.3 yet.",
        ],
        "ios.editor.crossDayHint": [
            .zhHant: "跨日時刻請寫成 24:00 以上，例如 25:10 表示隔天 01:10。",
            .zhHans: "跨日时刻请写成 24:00 以上，例如 25:10 表示隔天 01:10。",
            .ja: "日をまたぐ時刻は 24 時以降で入力します（25:10 は翌日 01:10）。",
            .en: "For a time after midnight, keep counting past 24:00 — 25:10 means 01:10 the next day.",
        ],
        "ios.editor.rideSegmentNote": [
            .zhHant: "關閉表示這一段沒有實際乘坐：不計入里程，也不會畫在地圖上。",
            .zhHans: "关闭表示这一段没有实际乘坐：不计入里程，也不会画在地图上。",
            .ja: "オフにするとその区間は実乗車ではない扱いになり、距離にも地図にも反映されません。",
            .en: "Off means this stretch was not actually ridden: it counts for no mileage and is not drawn.",
        ],

        // MARK: - §5.4 editor — field and screen labels

        "ios.editor.stopIndex": [
            .zhHant: "第 {index} 站", .zhHans: "第 {index} 站", .ja: "{index} 駅目",
            .en: "Stop {index}",
        ],
        "ios.editor.untitledStop": [
            .zhHant: "未命名停站", .zhHans: "未命名停靠站", .ja: "駅名未設定", .en: "Untitled stop",
        ],
        "ios.editor.sectionIndex": [
            .zhHant: "第 {index} 段", .zhHans: "第 {index} 段", .ja: "第 {index} 区間",
            .en: "Section {index}",
        ],
        "ios.editor.station": [
            .zhHant: "車站", .zhHans: "车站", .ja: "駅", .en: "Station",
        ],
        "ios.editor.stationName": [
            .zhHant: "站名", .zhHans: "站名", .ja: "駅名", .en: "Station name",
        ],
        "ios.editor.stationCode": [
            .zhHant: "車站代碼", .zhHans: "车站代码", .ja: "駅コード", .en: "Station code",
        ],
        "ios.editor.platformNumber": [
            .zhHant: "月台編號", .zhHans: "站台编号", .ja: "番線", .en: "Platform number",
        ],
        "ios.editor.platformOptional": [
            .zhHant: "沒有資料時留空", .zhHans: "没有数据时留空", .ja: "不明なら空欄",
            .en: "Leave blank when unknown",
        ],
        "ios.editor.platformRule": [
            .zhHant: "月台編號必須是 0 或正整數；沒有資料時請留空。",
            .zhHans: "站台编号必须是 0 或正整数；没有数据时请留空。",
            .ja: "番線は 0 以上の整数で入力してください。不明なら空欄にします。",
            .en: "Platform number must be zero or a positive integer; leave it blank when unknown.",
        ],
        "ios.editor.chooseStation": [
            .zhHant: "從路網車站選擇", .zhHans: "从路网车站选择", .ja: "路線網の駅から選ぶ",
            .en: "Choose from railway stations",
        ],
        "ios.editor.stationSearch": [
            .zhHant: "站名或代碼", .zhHans: "站名或代码", .ja: "駅名またはコード",
            .en: "Station name or code",
        ],
        "ios.editor.times": [
            .zhHant: "時刻", .zhHans: "时刻", .ja: "時刻", .en: "Times",
        ],
        "ios.editor.endpoints": [
            .zhHant: "端點", .zhHans: "端点", .ja: "端点", .en: "Endpoints",
        ],
        "ios.editor.fromStation": [
            .zhHant: "起點站", .zhHans: "起点站", .ja: "開始駅", .en: "From station",
        ],
        "ios.editor.toStation": [
            .zhHant: "終點站", .zhHans: "终点站", .ja: "終了駅", .en: "To station",
        ],
        "ios.editor.constraints": [
            .zhHant: "約束", .zhHans: "约束", .ja: "制約", .en: "Constraints",
        ],
        "ios.editor.branchService": [
            .zhHant: "分支車次", .zhHans: "分支车次", .ja: "分割運転の車次",
            .en: "Branch service",
        ],
        "ios.editor.displayName": [
            .zhHant: "顯示名稱", .zhHans: "显示名称", .ja: "表示名", .en: "Display name",
        ],
        "ios.editor.lineNames": [
            .zhHant: "線路名稱", .zhHans: "线路名称", .ja: "路線名", .en: "Line names",
        ],
        "ios.editor.operatorNames": [
            .zhHant: "運營方名稱", .zhHans: "运营方名称", .ja: "事業者名",
            .en: "Operator names",
        ],
        "ios.editor.onePerComma": [
            .zhHant: "以逗號分隔", .zhHans: "以逗号分隔", .ja: "カンマ区切り",
            .en: "One per comma",
        ],
        "ios.editor.solver": [
            .zhHant: "求解器", .zhHans: "求解器", .ja: "経路探索", .en: "Solver",
        ],
        "ios.editor.institutionFilter": [
            .zhHant: "事業者篩選", .zhHans: "事业者筛选", .ja: "事業者フィルタ",
            .en: "Institution filter",
        ],
        "ios.editor.automatic": [
            .zhHant: "自動", .zhHans: "自动", .ja: "自動", .en: "Automatic",
        ],
        "ios.editor.softPreference": [
            .zhHant: "軟偏好", .zhHans: "软偏好", .ja: "ソフト（優先）", .en: "Soft preference",
        ],
        "ios.editor.hardConstraint": [
            .zhHant: "硬約束", .zhHans: "硬约束", .ja: "ハード（制限）", .en: "Hard constraint",
        ],
        "ios.editor.jrOnlyHint": [
            .zhHant: "JR 限定提示", .zhHans: "JR 限定提示", .ja: "JR 限定ヒント",
            .en: "JR only hint",
        ],
        "ios.editor.routeAlternatives": [
            .zhHant: "備選路線", .zhHans: "备选路线", .ja: "代替経路",
            .en: "Route alternatives",
        ],
        "ios.editor.straightLineFallback": [
            .zhHant: "直線回退", .zhHans: "直线回退", .ja: "直線での代替描画",
            .en: "Straight-line fallback",
        ],
        "ios.editor.disabled": [
            .zhHant: "已停用", .zhHans: "已停用", .ja: "無効", .en: "Disabled",
        ],
        "ios.editor.preferences": [
            .zhHant: "偏好", .zhHans: "偏好", .ja: "優先設定", .en: "Preferences",
        ],
        "ios.editor.institutionCodes": [
            .zhHant: "事業者種別代碼", .zhHans: "事业者种别代码", .ja: "事業者種別コード",
            .en: "Institution type codes",
        ],
        "ios.editor.preferredLines": [
            .zhHant: "偏好線路", .zhHans: "偏好线路", .ja: "優先する路線",
            .en: "Preferred lines",
        ],
        "ios.editor.preferredOperators": [
            .zhHant: "偏好運營方", .zhHans: "偏好运营方", .ja: "優先する事業者",
            .en: "Preferred operators",
        ],
        "ios.editor.policyFooter": [
            .zhHant: "硬約束可能讓路線完全無法求解；軟偏好只影響排序。",
            .zhHans: "硬约束可能让路线完全无法求解；软偏好只影响排序。",
            .ja: "ハード制約は経路が全く見つからなくなる場合があります。ソフト優先は順位付けにのみ影響します。",
            .en: "A hard filter can stop a route resolving at all; a soft preference only influences ranking.",
        ],
    ]
}
