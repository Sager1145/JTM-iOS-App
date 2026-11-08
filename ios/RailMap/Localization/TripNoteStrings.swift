import Foundation
import RailCore

/// Sentences for trip event notes. Registered in ``AppStrings``.
///
/// Placeholders use the catalog's `{name}` syntax (not `%@` / `%d`). The catalog
/// has no plural forms, so counts are phrased neutrally ("Notes: {n}").
enum TripNoteStrings {
    static let table: [String: [Localization.Language: String]] = [
        "ios.tripNotes.title": [
            .en: "Notes", .ja: "メモ", .zhHant: "備註", .zhHans: "备注",
        ],
        "ios.tripNotes.add": [
            .en: "Add note", .ja: "メモを追加", .zhHant: "新增備註", .zhHans: "新增备注",
        ],
        "ios.tripNotes.edit": [
            .en: "Edit", .ja: "編集", .zhHant: "編輯", .zhHans: "编辑",
        ],
        "ios.tripNotes.delete": [
            .en: "Delete", .ja: "削除", .zhHant: "刪除", .zhHans: "删除",
        ],
        "ios.tripNotes.deleteConfirm": [
            .en: "Delete this note?", .ja: "このメモを削除しますか？", .zhHant: "要刪除此備註嗎？", .zhHans: "要删除此备注吗？",
        ],
        "ios.tripNotes.save": [
            .en: "Save", .ja: "保存", .zhHant: "儲存", .zhHans: "保存",
        ],
        "ios.tripNotes.share": [
            .en: "Share", .ja: "共有", .zhHant: "分享", .zhHans: "分享",
        ],
        "ios.tripNotes.cancel": [
            .en: "Cancel", .ja: "キャンセル", .zhHant: "取消", .zhHans: "取消",
        ],
        "ios.tripNotes.discardConfirm": [
            .en: "Discard changes?", .ja: "変更を破棄しますか？", .zhHant: "要捨棄變更嗎？", .zhHans: "要放弃更改吗？",
        ],
        "ios.tripNotes.discard": [
            .en: "Discard", .ja: "破棄", .zhHant: "捨棄", .zhHans: "放弃",
        ],
        "ios.tripNotes.category": [
            .en: "Category", .ja: "カテゴリ", .zhHant: "類別", .zhHans: "类别",
        ],
        "ios.tripNotes.categoryPlaceholder": [
            .en: "e.g. Crew change", .ja: "例：乗務員交代", .zhHant: "例如：換乘務員", .zhHans: "例如：换乘务员",
        ],
        "ios.tripNotes.text": [
            .en: "Note", .ja: "メモ", .zhHant: "備註內容", .zhHans: "备注内容",
        ],
        "ios.tripNotes.textPlaceholder": [
            .en: "What happened?", .ja: "何がありましたか？", .zhHant: "發生了什麼事？", .zhHans: "发生了什么事？",
        ],
        "ios.tripNotes.time": [
            .en: "Time", .ja: "時刻", .zhHant: "時間", .zhHans: "时间",
        ],
        "ios.tripNotes.noTime": [
            .en: "No time", .ja: "時刻なし", .zhHant: "不指定時間", .zhHans: "不指定时间",
        ],
        "ios.tripNotes.nextDay": [
            .en: "+{n}", .ja: "+{n}", .zhHant: "+{n}", .zhHans: "+{n}",
        ],
        "ios.tripNotes.place": [
            .en: "Place", .ja: "場所", .zhHant: "地點", .zhHans: "地点",
        ],
        "ios.tripNotes.changePlace": [
            .en: "Change place", .ja: "場所を変更", .zhHant: "更改地點", .zhHans: "更改地点",
        ],
        "ios.tripNotes.placeAtStation": [
            .en: "At {station}", .ja: "{station}", .zhHant: "在{station}", .zhHans: "在{station}",
        ],
        "ios.tripNotes.placeBetween": [
            .en: "{from} → {to}", .ja: "{from} → {to}", .zhHant: "{from} → {to}", .zhHans: "{from} → {to}",
        ],
        "ios.tripNotes.placeOnMap": [
            .en: "Pinned on map", .ja: "地図上にピン留め", .zhHant: "已在地圖上標記", .zhHans: "已在地图上标记",
        ],
        "ios.tripNotes.placeUnplaced": [
            .en: "No place", .ja: "場所なし", .zhHant: "未指定地點", .zhHans: "未指定地点",
        ],
        "ios.tripNotes.saveRefused": [
            .en: "Couldn't save the note. Try again.", .ja: "メモを保存できませんでした。もう一度お試しください。",
            .zhHant: "無法儲存備註，請再試一次。", .zhHans: "无法保存备注，请重试。",
        ],
        "ios.tripNotes.count": [
            .en: "Notes: {n}", .ja: "メモ：{n}件", .zhHant: "備註：{n} 則", .zhHans: "备注：{n} 条",
        ],
        "ios.tripNotes.marker.accessibility": [
            .en: "Note: {text}", .ja: "メモ：{text}", .zhHant: "備註：{text}", .zhHans: "备注：{text}",
        ],
        "ios.tripNotes.pick.title": [
            .en: "Move the map to place the note", .ja: "地図を動かしてメモの場所を決めてください", .zhHant: "移動地圖以放置備註", .zhHans: "移动地图以放置备注",
        ],
        "ios.tripNotes.pick.offLine": [
            .en: "Move the pin onto this trip's line", .ja: "ピンをこの行程の路線上に移してください", .zhHant: "請將圖釘移到此行程的路線上", .zhHans: "请将图钉移到此行程的路线上",
        ],
        "ios.tripNotes.pick.routePending": [
            .en: "This trip's route isn't drawn yet. Choose a station.",
            .ja: "この行程の路線はまだ表示されていません。駅を選んでください。",
            .zhHant: "此行程的路線尚未繪製，請選擇車站。",
            .zhHans: "此行程的路线尚未绘制，请选择车站。",
        ],
        "ios.tripNotes.pick.myLocation": [
            .en: "My location", .ja: "現在地", .zhHant: "我的位置", .zhHans: "我的位置",
        ],
        "ios.tripNotes.pick.station": [
            .en: "Station", .ja: "駅", .zhHant: "車站", .zhHans: "车站",
        ],
        "ios.tripNotes.pick.confirm": [
            .en: "Confirm", .ja: "決定", .zhHant: "確認", .zhHans: "确认",
        ],
        "ios.tripNotes.pick.cancel": [
            .en: "Cancel", .ja: "キャンセル", .zhHant: "取消", .zhHans: "取消",
        ],
        "ios.tripNotes.location.denied": [
            .en: "Location access is off. Turn it on in Settings, or pick a station.", .ja: "位置情報の利用がオフです。設定でオンにするか、駅を選んでください。", .zhHant: "定位服務已關閉。請在設定中開啟，或改選車站。", .zhHans: "定位服务已关闭。请在设置中开启，或改选车站。",
        ],
        "ios.tripNotes.location.tooFar": [
            .en: "You're more than 2 km from this trip's route.", .ja: "この行程の経路から2km以上離れています。", .zhHant: "你距離此行程的路線超過 2 公里。", .zhHans: "你距离此行程的路线超过 2 公里。",
        ],
        "ios.tripNotes.location.failed": [
            .en: "Couldn't get your location.", .ja: "現在地を取得できませんでした。", .zhHant: "無法取得你的位置。", .zhHans: "无法获取你的位置。",
        ],
        "ios.tripNotes.category.default.incident": [
            .en: "Incident", .ja: "事故・トラブル", .zhHant: "事件", .zhHans: "事件",
        ],
        "ios.tripNotes.category.default.observation": [
            .en: "Observation", .ja: "観察", .zhHant: "觀察", .zhHans: "观察",
        ],
        "ios.tripNotes.category.default.finding": [
            .en: "Finding", .ja: "発見", .zhHant: "發現", .zhHans: "发现",
        ],
        "ios.tripNotes.category.default.unscheduledStop": [
            .en: "Unscheduled stop", .ja: "臨時停車", .zhHant: "臨時停車", .zhHans: "临时停车",
        ],
        "ios.tripNotes.category.default.crewChange": [
            .en: "Crew change", .ja: "乗務員交代", .zhHant: "換乘務員", .zhHans: "换乘务员",
        ],
        "ios.tripNotes.category.default.other": [
            .en: "Other", .ja: "その他", .zhHant: "其他", .zhHans: "其他",
        ],
    ]
}
