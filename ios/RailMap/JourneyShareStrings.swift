import RailCore

extension AppLocalization {
    func journeyShareText(_ key: String) -> String {
        Self.journeyShareStrings[key]?[language] ?? Self.journeyShareStrings[key]?[.en] ?? key
    }

    private static let journeyShareStrings: [String: [Localization.Language: String]] = [
        "title": [.zhHans: "分享行程", .zhHant: "分享行程", .ja: "旅程を共有", .en: "Share journey"],
        "full": [.zhHans: "完整行程", .zhHant: "完整行程", .ja: "旅程全体", .en: "Full journey"],
        "basic": [.zhHans: "车次基本信息", .zhHant: "車次基本資訊", .ja: "列車の基本情報", .en: "Train information"],
        "fullNote": [.zhHans: "分享一张包含全部行程内容的图片，并附上完整文字。", .zhHant: "分享一張包含全部行程內容的圖片，並附上完整文字。", .ja: "旅程全体の画像1枚と、すべての内容のテキストを共有します。", .en: "Share one image of the entire journey together with its complete text."],
        "basicNote": [.zhHans: "仅分享车次信息和停车站的图片。", .zhHant: "僅分享車次資訊和停車站的圖片。", .ja: "列車情報と停車駅の画像のみを共有します。", .en: "Share only an image of the train information and stopping stations."],
        "stops": [.zhHans: "停车站", .zhHant: "停車站", .ja: "停車駅", .en: "Stopping stations"],
        "timeline": [.zhHans: "全部记录站点", .zhHant: "全部記錄站點", .ja: "すべての記録駅", .en: "All recorded stations"],
        "preparing": [.zhHans: "正在生成分享图片…", .zhHant: "正在產生分享圖片…", .ja: "共有画像を作成中…", .en: "Preparing image…"],
        "failed": [.zhHans: "未能生成分享图片，请重试。", .zhHant: "未能產生分享圖片，請重試。", .ja: "共有画像を作成できませんでした。再試行してください。", .en: "Could not create the image. Please try again."],
        "retry": [.zhHans: "重试", .zhHant: "重試", .ja: "再試行", .en: "Try again"],
        "date": [.zhHans: "日期", .zhHant: "日期", .ja: "日付", .en: "Date"],
        "undated": [.zhHans: "未记录日期", .zhHant: "未記錄日期", .ja: "日付の記録なし", .en: "Date not recorded"],
        "noStops": [.zhHans: "未记录停车站", .zhHant: "未記錄停車站", .ja: "停車駅の記録なし", .en: "No stopping stations recorded"],
        "preview": [.zhHans: "行程分享图片", .zhHant: "行程分享圖片", .ja: "旅程の共有画像", .en: "Journey share image"],
        "timeZone": [.zhHans: "时区", .zhHant: "時區", .ja: "時間帯", .en: "Time zone"],
    ]
}
