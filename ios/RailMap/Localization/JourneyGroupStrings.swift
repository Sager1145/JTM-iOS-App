import Foundation
import RailCore

/// Journey-group sentences. Namespaced so `title` and `name` stay isolated
/// from every other screen. ``AppLocalization/text(_:params:fallback:)`` reads
/// them from ``AppStrings/table``.
enum JourneyGroupStrings {
    static let table: AppStrings.Table = [
        "ios.journeyGroup.title": [
            .zhHans: "行程组",
            .zhHant: "行程組",
            .ja: "旅程グループ",
            .en: "Journey group",
        ],
        "ios.journeyGroup.all": [
            .zhHans: "全部行程组",
            .zhHant: "全部行程組",
            .ja: "すべてのグループ",
            .en: "All journey groups",
        ],
        "ios.journeyGroup.none": [
            .zhHans: "不分组",
            .zhHant: "不分組",
            .ja: "グループなし",
            .en: "No group",
        ],
        "ios.journeyGroup.create": [
            .zhHans: "创建行程组",
            .zhHant: "建立行程組",
            .ja: "グループを作成",
            .en: "Create journey group",
        ],
        "ios.journeyGroup.name": [
            .zhHans: "自定义名称",
            .zhHant: "自訂名稱",
            .ja: "グループ名",
            .en: "Custom name",
        ],
        "ios.journeyGroup.limit": [
            .zhHans: "最多 12 个字符",
            .zhHant: "最多 12 個字元",
            .ja: "12文字まで",
            .en: "Up to 12 characters",
        ],
        "ios.journeyGroup.crossRegion": [
            .zhHans: "同一行程组可包含多个地区的铁路记录。",
            .zhHant: "同一行程組可包含多個地區的鐵路記錄。",
            .ja: "異なる地域の乗車記録を同じグループにまとめられます。",
            .en: "A group can include railway journeys from multiple regions.",
        ],
    ]
}
