import RailCore

/// Independent strings so the endpoint flow can be developed beside the editor.
enum LocalJourneyStrings {
    static func text(_ key: String, language: Localization.Language) -> String {
        let table: [String: [Localization.Language: String]] = [
            "title": [.zhHans: "起终点自动填入", .zhHant: "起終點自動填入", .ja: "発着駅から自動入力", .en: "Fill from endpoints"],
            "search": [.zhHans: "本地搜索线路", .zhHant: "本機搜尋路線", .ja: "端末内で経路を検索", .en: "Search offline routes"],
            "searching": [.zhHans: "正在搜索线路", .zhHant: "正在搜尋路線", .ja: "経路を検索中", .en: "Searching routes"],
            "note": [.zhHans: "仅需选择起点和终点。选择线路后补齐途经站；时刻留空。跨公司区间会保留各段实际线路。", .zhHant: "只需選擇起點和終點。選擇路線後補齊途經站；時刻留空。跨公司區間會保留各段實際路線。", .ja: "発着駅を選ぶと経路を検索できます。途中駅を時刻未設定で入力し、会社をまたぐ区間も実際の路線を保持します。", .en: "Choose the endpoints to find a route. Intermediate visits have no times. Each section keeps its physical line and operator."],
            "choose": [.zhHans: "选择车站", .zhHant: "選擇車站", .ja: "駅を選択", .en: "Choose station"],
            "apply": [.zhHans: "填入此线路", .zhHant: "填入此路線", .ja: "この経路を入力", .en: "Fill this route"],
            "empty": [.zhHans: "未找到可用的本地线路。请核对起终站和列车类型。", .zhHant: "未找到可用的本機路線。請核對起終站和列車類型。", .ja: "端末内に利用可能な経路がありません。発着駅と列車種別を確認してください。", .en: "No offline route was found. Check the endpoints and train type."],
            "sourceScope": [.zhHans: "适用区段请查看来源", .zhHant: "適用區段請查看來源", .ja: "対象区間は出典を確認", .en: "See the source for the covered section"],
            "reviewed": [.zhHans: "核实于", .zhHant: "核實於", .ja: "確認日", .en: "Checked"],
            "types": [.zhHans: "线路列车种别", .zhHant: "路線列車種別", .ja: "路線の列車種別", .en: "Line service types"],
            "unknown": [.zhHans: "该线路的列车种别尚未核实", .zhHant: "此路線的列車種別尚未核實", .ja: "この路線の種別は未確認です", .en: "Service types have not been verified for this line"],
            "partial": [.zhHans: "已核实部分种别；适用区段见来源，不能据此判断全程直通或停站。", .zhHant: "已核實部分種別；適用區段見來源，不能據此判斷全程直通或停站。", .ja: "確認済みの種別のみ掲載。対象区間は出典を確認してください。全区間の直通や停車は保証しません。", .en: "Verified types are a partial list. Check the source for their sections; they do not establish end-to-end through service or calls."],
            "replace": [.zhHans: "替换已填写车站？", .zhHant: "替換已填寫車站？", .ja: "入力済みの駅を置き換えますか？", .en: "Replace authored visits?"],
            "route": [.zhHans: "候选线路", .zhHant: "候選路線", .ja: "経路候補", .en: "Route alternatives"],
            "physical": [.zhHans: "线路连通不代表无需换乘；可按各区间补充列车信息。", .zhHant: "路線連通不代表無需轉乘；可按各區間補充列車資訊。", .ja: "経路がつながっていても乗換が必要な場合があります。区間ごとに列車情報を入力できます。", .en: "Connected track may require changing trains. Add service details by section."],
            "services": [.zhHans: "运营线路／直通系统", .zhHant: "營運路線／直通系統", .ja: "運転系統・直通運転", .en: "Operating lines and through services"],
            "anyService": [.zhHans: "按实际线路搜索", .zhHant: "依實際路線搜尋", .ja: "実際の路線で検索", .en: "Search physical lines"],
            "continues": [.zhHans: "后续车次", .zhHant: "後續車次", .ja: "続く列車番号", .en: "Continues as"],
            "timetable": [.zhHans: "已收录时刻表片段", .zhHant: "已收錄時刻表片段", .ja: "収録済みの時刻表抜粋", .en: "Published timetable excerpts"],
            "timetableNote": [.zhHans: "仅展示来源明确的日期与车站；其他停站和日期仍待补充。", .zhHant: "僅顯示來源明確的日期與車站；其他停站及日期仍待補充。", .ja: "出典で確認できた運転日と駅のみ掲載。他の駅や日付は未収録です。", .en: "Only sourced dates and stops are shown. Other stops and dates remain unverified."],
        ]
        return table[key]?[language] ?? table[key]?[.en] ?? key
    }
}
