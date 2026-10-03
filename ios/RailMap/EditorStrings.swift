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

        "ios.editor.generatedStation": [
            .zhHans: "自动填入", .zhHant: "自動填入",
            .ja: "自動入力", .en: "Automatically filled",
        ],
        "ios.editor.generatedStationsNote": [
            .zhHans: "通过站根据你确认的线路自动补齐，未包含时刻表信息。可打开各站修改，保存后仍可编辑。",
            .zhHant: "通過站根據你確認的路線自動補齊，未包含時刻表資訊。可開啟各站修改，儲存後仍可編輯。",
            .ja: "確認した経路から通過駅を補完しています。時刻表の情報は含みません。各駅を開いて変更でき、保存後も編集できます。",
            .en: "Passing stations are filled from the route you confirm, without timetable information. Open any station to make changes, including after saving.",
        ],
        "ios.editor.chooseEndpointsFirst": [
            .zhHans: "选择两端车站后，选择实际经过的线路。", .zhHant: "選擇兩端車站後，選擇實際經過的路線。",
            .ja: "両端の駅を選んでから、実際に走る路線を選択します。", .en: "Choose both endpoint stations, then the physical line.",
        ],
        "ios.editor.physicalRouteNote": [
            .zhHans: "仅显示连接两端的实际线路。中间站会自动补齐为未填写时刻的途经站；时刻与停站信息可另行补充。",
            .zhHant: "僅顯示連接兩端的實際路線。中間站會自動補齊為未填寫時刻的途經站；時刻與停站資訊可另行補充。",
            .ja: "両端を結ぶ実際の路線のみ表示します。途中駅は時刻未設定の通過駅として補完し、時刻や停車情報は後から入力できます。",
            .en: "Only physical lines connecting both endpoints are shown. Intermediate stations are added as untimed pass-through visits; add times and passenger stops separately.",
        ],
        "ios.editor.noViableRoute": [
            .zhHans: "没有符合列车类型且避开已删除车站的可用线路。请选择其他两端车站，或撤销删除。",
            .zhHant: "沒有符合列車類型且避開已刪除車站的可用路線。請選擇其他兩端車站，或復原刪除。",
            .ja: "列車種別に合い、削除した駅を避ける経路がありません。両端の駅を変更するか、削除を取り消してください。",
            .en: "No viable physical route matches this train type and avoids the deleted stations. Change the endpoints or undo the deletion.",
        ],

        "ios.editor.useOfficialEnglishName": [
            .zhHans: "使用官方英文名称", .zhHant: "使用官方英文名稱",
            .ja: "公式英語名を使用", .en: "Use official English name",
        ],
        "ios.editor.officialEnglishNameUnavailable": [
            .zhHans: "暂无匹配的官方英文名称，可自行填写。", .zhHant: "暫無相符的官方英文名稱，可自行填寫。",
            .ja: "一致する公式英語名は未収録です。自由に入力できます。", .en: "No matching official English name is available. You can enter your own.",
        ],
        "ios.editor.sectionServices": [
            .zhHans: "分段公司、线路与车次", .zhHant: "分段公司、路線與車次",
            .ja: "区間ごとの会社・路線・列車番号", .en: "Operators, lines and train numbers by section",
        ],
        "ios.editor.sectionService": [
            .zhHans: "区间列车信息", .zhHant: "區間列車資訊",
            .ja: "区間の列車情報", .en: "Section service",
        ],
        "ios.editor.addSectionService": [
            .zhHans: "添加区间列车信息", .zhHant: "新增區間列車資訊",
            .ja: "区間の列車情報を追加", .en: "Add section service",
        ],
        "ios.editor.applySectionService": [
            .zhHans: "应用", .zhHant: "套用",
            .ja: "適用", .en: "Apply",
        ],
        "ios.editor.clearSectionService": [
            .zhHans: "清除所选区间信息", .zhHant: "清除所選區間資訊",
            .ja: "選択区間の情報を消去", .en: "Clear selected section details",
        ],
        "ios.editor.sectionNumberUnknown": [
            .zhHans: "未填写", .zhHant: "未填寫",
            .ja: "未入力", .en: "Not entered",
        ],
        "ios.editor.sectionServicesNote": [
            .zhHans: "直通列车可按公司或车次变化处分段。选择起终站后填写该区间的公司、线路及车次；不知道的车次留空。线路及公司也用于确定地图路线。", .zhHant: "直通列車可按公司或車次變化處分段。選擇起終站後填寫該區間的公司、路線及車次；不知道的車次留空。路線及公司也用於確定地圖路徑。",
            .ja: "直通列車は会社や列車番号が変わる駅で区切れます。開始・終了駅を選び、その区間の会社・路線・列車番号を入力してください。不明な番号は空欄にします。路線と会社は地図の経路探索にも使われます。", .en: "For through-running trains, divide the journey where the operator or number changes. Select the stations and enter that section’s operator, line and train number. Leave unknown numbers blank. Lines and operators also guide the map route.",
        ],
        "ios.editor.selectExpressStops": [
            .zhHans: "从特急班次导入停站", .zhHant: "從特急班次匯入停站",
            .ja: "特急から駅を入力", .en: "Use limited express stops",
        ],
        "ios.editor.expressStopsNote": [
            .zhHans: "可打开各站修改已公布时刻；列车详情中也可使用 AI 核对。",
            .zhHant: "可開啟各站修改已公布時刻；列車詳情中也可使用 AI 核對。",
            .ja: "掲載時刻は各駅を開いて変更できます。列車の詳細からAI照合も利用できます。",
            .en: "Open each stop to edit published times. AI checking is also available in train details.",
        ],
        "ios.editor.replaceExistingStopsTitle": [
            .zhHans: "替换现有停站？", .zhHant: "替換現有停站？",
            .ja: "既存の駅を置き換えますか？", .en: "Replace existing stops?",
        ],
        "ios.editor.replaceExistingStops": [
            .zhHans: "替换停站", .zhHant: "替換停站",
            .ja: "置き換える", .en: "Replace stops",
        ],
        "ios.editor.actualTimes": [
            .zhHans: "实际时间", .zhHant: "實際時間", .ja: "実際の時刻", .en: "Actual times",
        ],
        "ios.editor.actualArrival": [
            .zhHans: "实际到达", .zhHant: "實際抵達", .ja: "実際の到着", .en: "Actual arrival",
        ],
        "ios.editor.actualDeparture": [
            .zhHans: "实际出发", .zhHant: "實際出發", .ja: "実際の発車", .en: "Actual departure",
        ],
        "ios.editor.actualTimesNote": [
            .zhHans: "仅在已知实际时间时填写。未填写时保留计划时间。",
            .zhHant: "僅在已知實際時間時填寫。未填寫時保留計劃時間。",
            .ja: "実績が分かる場合のみ入力してください。未入力なら予定時刻を保持します。",
            .en: "Enter actual times only when known. Scheduled times remain when these are blank.",
        ],
        "ios.editor.actualOnTime": [
            .zhHans: "准点", .zhHant: "準點", .ja: "定刻", .en: "On time",
        ],
        "ios.editor.actualDelayed": [
            .zhHans: "晚点 {minutes} 分钟", .zhHant: "晚點 {minutes} 分鐘",
            .ja: "{minutes}分遅れ", .en: "{minutes} min late",
        ],
        "ios.editor.actualEarly": [
            .zhHans: "提前 {minutes} 分钟", .zhHant: "提前 {minutes} 分鐘",
            .ja: "{minutes}分早い", .en: "{minutes} min early",
        ],
        "ios.editor.limitedExpressName": [
            .zhHans: "特急名称", .zhHant: "特急名稱",
            .ja: "特急列車名", .en: "Limited express name",
        ],
        "ios.editor.timetableDateChanged": [
            .zhHans: "已导入班次的日期为 {date}。更改日期后请重新查询或核对时刻；已编辑的停站会保留。",
            .zhHant: "已匯入班次的日期為 {date}。更改日期後請重新查詢或核對時刻；已編輯的停站會保留。",
            .ja: "取り込んだ列車の運転日は {date} です。日付を変えた場合は時刻を再検索・確認してください。編集した駅は保持します。",
            .en: "The imported train runs on {date}. Search again or check its times after changing the date. Your edited stops are kept.",
        ],
        "ios.editor.timetableBrowse": [
            .zhHans: "按日期、列车或车站查找班次", .zhHant: "按日期、列車或車站查找班次",
            .ja: "日付・列車・駅から探す", .en: "Browse trains by date, name or station",
        ],
        "ios.editor.timetableBrowseDate": [
            .zhHans: "班次日期", .zhHant: "班次日期", .ja: "運転日", .en: "Service date",
        ],
        "ios.editor.timetableAnyDate": [
            .zhHans: "清除日期，浏览线路模式", .zhHant: "清除日期，瀏覽路線模式",
            .ja: "日付を解除してパターンを見る", .en: "Clear date and browse route patterns",
        ],
        "ios.editor.timetableSearchPrompt": [
            .zhHans: "名称、车次、车站或时刻", .zhHant: "名稱、車次、車站或時刻",
            .ja: "列車名・番号・駅・時刻", .en: "Name, number, station or time",
        ],
        "ios.editor.timetableSearchHelp": [
            .zhHans: "空格组合关键词，例如 azusa 松本；用 東京 → 松本 按停站方向查找。支持英文列车名、平假名、片假名和全角数字。选择班次后仍需确认保存。",
            .zhHant: "空格組合關鍵詞，例如 azusa 松本；用 東京 → 松本 按停站方向查找。支援英文列車名、平假名、片假名和全形數字。選擇班次後仍需確認儲存。",
            .ja: "空白で条件を組み合わせます（azusa 松本）。東京 → 松本 で停車順を検索。英語の列車名・かな・全角数字も使えます。選択後に保存を確認します。",
            .en: "Combine terms with spaces (azusa 松本), or use 東京 → 松本 for stop order. English train names, kana and full-width numbers work too. Review before saving.",
        ],
        "ios.editor.timetableMatchTitle": [
            .zhHans: "从本地时刻表补全", .zhHant: "從本地時刻表補全",
            .ja: "保存済み時刻表から補完", .en: "Complete from timetable",
        ],
        "ios.editor.timetableSources": [
            .zhHans: "查看资料来源", .zhHant: "查看資料來源",
            .ja: "出典を見る", .en: "View sources",
        ],
        "ios.editor.timetableVerifiedRoute": [
            .zhHans: "完整线路已核验", .zhHant: "完整路線已核驗",
            .ja: "全経路確認済み", .en: "Verified full route",
        ],
        "ios.editor.timetablePublishedDraft": [
            .zhHans: "已公布停站草稿", .zhHant: "已公布停站草稿",
            .ja: "公表済み停車駅の下書き", .en: "Published stops draft",
        ],
        "ios.editor.timetableSearch": [
            .zhHans: "查找已公布班次", .zhHant: "查找已公布班次",
            .ja: "公表済み列車を検索", .en: "Find published trains",
        ],
        "ios.editor.timetableSearching": [
            .zhHans: "正在查找班次…", .zhHant: "正在查找班次…",
            .ja: "列車を検索中…", .en: "Finding trains…",
        ],
        "ios.editor.timetableNoMatch": [
            .zhHans: "本地时刻表中没有端点与时刻完全吻合的班次。可继续使用 AI 补全或手动填写。",
            .zhHant: "本地時刻表中沒有端點與時刻完全吻合的班次。可繼續使用 AI 補全或手動填寫。",
            .ja: "両端の駅と時刻が一致する列車はありません。AI 補完または手入力を利用できます。",
            .en: "No train matches both endpoint stations and times. Continue with AI completion or enter details manually.",
        ],
        "ios.editor.timetableMatchNote": [
            .zhHans: "已公布但缺少完整线路的班次只生成可编辑草稿；请核对来源并补齐缺项。",
            .zhHant: "已公布但缺少完整路線的班次只生成可編輯草稿；請核對來源並補齊缺項。",
            .ja: "全経路が未確認の列車は編集用の下書きになります。出典を確認し、不足分を補ってください。",
            .en: "Trains without a verified full route create an editable draft. Check the source and complete missing details.",
        ],
        "ios.editor.timetableMatchRequirements": [
            .zhHans: "先填写日期，并在两端选择数据库车站和输入出发、到达时刻。",
            .zhHant: "先填寫日期，並在兩端選擇資料庫車站和輸入出發、抵達時刻。",
            .ja: "日付、両端のデータベース駅、出発・到着時刻を入力してください。",
            .en: "Enter a date, choose both database stations, and add departure and arrival times.",
        ],
        "ios.editor.vehicleSearchNote": [
            .zhHans: "输入以查找建议，也可以填写自定义内容。车辆类型建议来自已保存的行程。",
            .zhHant: "輸入以查找建議，也可以填寫自訂內容。車輛類型建議來自已儲存的行程。",
            .ja: "入力して候補を検索するか、自由に記入できます。車両形式の候補は保存済みの旅程から表示されます。",
            .en: "Type to find suggestions or enter your own value. Vehicle suggestions come from saved journeys.",
        ],
        "ios.editor.step.region": [
            .zhHans: "地区与列车类型",
            .zhHant: "地區與列車類型",
            .ja: "地域と列車種別",
            .en: "Region and train type",
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
            .zhHans: "先选择地区和列车类型，再选择两端车站及实际线路。",
            .zhHant: "先選擇地區和列車類型，再選擇兩端車站及實際路線。",
            .ja: "地域と列車種別を選んでから、両端の駅と実際の路線を選択します。",
            .en: "Choose the region and train type first, then the endpoints and physical line.",
        ],
        "ios.editor.step.routeNote": [
            .zhHans: "先选择出发站与到达站，再选择连接两端的实际线路。中间站自动补齐。",
            .zhHant: "先選擇出發站與到達站，再選擇連接兩端的實際路線。中間站自動補齊。",
            .ja: "出発駅と到着駅を選んでから、両端を結ぶ実際の路線を選択します。途中駅は自動補完されます。",
            .en: "Choose departure and arrival stations, then a physical line connecting both. Intermediate stations fill automatically.",
        ],
        "ios.editor.step.serviceNote": [
            .zhHans: "特急请填写名称；车次可在下一步从时刻表或 AI 补全。普通列车可留空。",
            .zhHant: "特急請填寫名稱；車次可在下一步從時刻表或 AI 補全。普通列車可留空。",
            .ja: "特急は列車名を入力してください。番号は次の画面で補完できます。普通列車は空欄でも進めます。",
            .en: "Enter the limited express name when applicable. The next step can fill the train number. Local trains can leave it blank.",
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
        "ios.editor.useSelectedDate": [
            .zhHant: "使用所選日期",
            .zhHans: "使用所选日期",
            .ja: "選択した日付を使用",
            .en: "Use selected date",
        ],
        "ios.editor.useSelectedTime": [
            .zhHant: "使用所選時刻",
            .zhHans: "使用所选时间",
            .ja: "選択した時刻を使用",
            .en: "Use selected time",
        ],
        "ios.editor.serviceDay": [
            .zhHant: "行車日", .zhHans: "运行日", .ja: "運行日", .en: "Service day",
        ],
        "ios.editor.today": [
            .zhHant: "當日", .zhHans: "当天", .ja: "当日", .en: "Today",
        ],
        "ios.editor.later": [
            .zhHant: "更晚", .zhHans: "更晚", .ja: "後日", .en: "Later",
        ],
        "ios.editor.serviceDaysLater": [
            .zhHant: "{count} 個行車日後", .zhHans: "{count} 个运行日后",
            .ja: "{count} 運行日後", .en: "{count} service days later",
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
        "ios.editor.sharedJourneyDateNote": [
            .zhHant: "全程共用這個出發日期；每站可另選到達或出發日期與時間。",
            .zhHans: "全程共用这个出发日期；每站可另选到达或出发日期与时间。",
            .ja: "この出発日は旅程全体で共通です。各駅の到着・発車日時は別に選べます。",
            .en: "The journey shares this departure date. Choose each stop's arrival or departure date and time below.",
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
        "ios.editor.stationUnmatched": [
            .zhHant: "未對應到目錄中的車站", .zhHans: "未匹配到目录中的车站",
            .ja: "ディレクトリの駅と一致していません",
            .en: "This station is not matched to the catalog",
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
        "ios.editor.nextServiceDay": [
            .zhHans: "次日运行",
            .zhHant: "次日運行",
            .ja: "翌運行日",
            .en: "Next service day",
        ],
        "ios.editor.passTime": [
            .zhHans: "通过时刻",
            .zhHant: "通過時刻",
            .ja: "通過時刻",
            .en: "Pass time",
        ],
        "ios.editor.timeUnfilled": [
            .zhHans: "时间未填写",
            .zhHant: "時間未填寫",
            .ja: "時刻未入力",
            .en: "Time not entered",
        ],
        "ios.editor.invalidClock": [
            .zhHans: "时间无效，不会改成 00:00。",
            .zhHant: "時間無效，不會改成 00:00。",
            .ja: "時刻が無効です。00:00 には置き換えません。",
            .en: "That time is not valid and was not changed to 00:00.",
        ],
        "ios.editor.invalidArrivalTime": [
            .zhHans: "到达时间无效。",
            .zhHant: "到達時間無效。",
            .ja: "到着時刻が無効です。",
            .en: "Arrival time is invalid.",
        ],
        "ios.editor.invalidDepartureTime": [
            .zhHans: "出发时间无效。",
            .zhHant: "出發時間無效。",
            .ja: "出発時刻が無効です。",
            .en: "Departure time is invalid.",
        ],
        "ios.editor.ai.noStation": [
            .zhHans: "请先选择车站",
            .zhHant: "請先選擇車站",
            .ja: "先に駅を選択してください",
            .en: "Choose a station first.",
        ],
        "ios.editor.ai.noTime": [
            .zhHans: "请填写该站时间",
            .zhHant: "請填寫該站時間",
            .ja: "その駅の時刻を入力してください",
            .en: "Enter a time at that station.",
        ],
        "ios.editor.ai.invalidTime": [
            .zhHans: "时间格式无效",
            .zhHant: "時間格式無效",
            .ja: "時刻の形式が正しくありません",
            .en: "The time is not valid.",
        ],
        "ios.editor.ai.timeNotOnStation": [
            .zhHans: "时间和车站不在同一站",
            .zhHant: "時間和車站不在同一站",
            .ja: "時刻と駅が同じ停車にありません",
            .en: "The time and station are not on the same stop.",
        ],
        "ios.editor.ai.busy": [
            .zhHans: "正在处理，请稍候",
            .zhHant: "正在處理，請稍候",
            .ja: "処理中です",
            .en: "A request is already in progress.",
        ],

        "ios.editor.retiredStation": [
            .zhHans: "已废止车站", .zhHant: "已廢止車站",
            .ja: "廃止駅", .en: "Former station",
        ],
        "ios.editor.retiredOn": [
            .zhHans: "{date} 废止", .zhHant: "{date} 廢止",
            .ja: "{date} 廃止", .en: "Closed {date}",
        ],
        "ios.editor.retiredStationsSection": [
            .zhHans: "乘车日期仍在营业的已废止车站",
            .zhHant: "乘車日期仍在營業的已廢止車站",
            .ja: "乗車日に営業していた廃止駅",
            .en: "Former stations open on the ride date",
        ],
        "ios.editor.retiredStationNote": [
            .zhHans: "已废止车站。路线按乘车日期的线路绘制。",
            .zhHant: "已廢止車站。路線按乘車日期的路線繪製。",
            .ja: "廃止駅です。経路は乗車日の路線で描かれます。",
            .en: "Former station. The route is drawn on the railway as it was on the ride date.",
        ],
        "ios.editor.renamedStation": [
            .zhHans: "旧站名", .zhHant: "舊站名",
            .ja: "旧駅名", .en: "Former name",
        ],
        "ios.editor.renamedOn": [
            .zhHans: "{date} 更名", .zhHant: "{date} 更名",
            .ja: "{date} 改称", .en: "Renamed {date}",
        ],
        "ios.editor.renamedStationNote": [
            .zhHans: "旧站名。路线按乘车日期的线路绘制。",
            .zhHant: "舊站名。路線按乘車日期的路線繪製。",
            .ja: "旧駅名です。経路は乗車日の路線で描かれます。",
            .en: "Former station name. The route is drawn on the railway as it was on the ride date.",
        ],
    ]
}
