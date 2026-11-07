import Foundation
import RailCore

/// Sentences for the ticket scanner. Registered in ``AppStrings``.
enum TicketScanStrings {
    static let table: [String: [Localization.Language: String]] = [
        "ios.ticket.title": [
            .en: "Scan a ticket", .ja: "乗車券を読み取る", .zhHant: "掃描車票", .zhHans: "扫描车票",
        ],
        "ios.ticket.camera": [
            .en: "Camera", .ja: "カメラ", .zhHant: "相機", .zhHans: "相机",
        ],
        "ios.ticket.photos": [
            .en: "Photos", .ja: "写真", .zhHant: "照片", .zhHans: "照片",
        ],
        "ios.ticket.privacy": [
            .en: "Text is read on this device. Nothing is uploaded.",
            .ja: "文字認識はこのデバイス上で行います。送信はされません。",
            .zhHant: "文字辨識在此裝置上進行，不會上傳任何內容。",
            .zhHans: "文字识别在此设备上进行，不会上传任何内容。",
        ],
        "ios.ticket.reading": [
            .en: "Reading the ticket…", .ja: "読み取り中…", .zhHant: "讀取中…", .zhHans: "读取中…",
        ],
        "ios.ticket.cameraUnavailable": [
            .en: "The camera is not available on this device. Choose a photo instead.",
            .ja: "このデバイスではカメラを使えません。写真から選んでください。",
            .zhHant: "此裝置無法使用相機，請改選照片。",
            .zhHans: "此设备无法使用相机，请改选照片。",
        ],
        "ios.ticket.unavailable": [
            .en: "Text recognition for this region is not available on this device.",
            .ja: "このデバイスでは、この地域の文字認識を使えません。",
            .zhHant: "此裝置無法辨識此地區的文字。",
            .zhHans: "此设备无法识别此地区的文字。",
        ],
        "ios.ticket.failed": [
            .en: "The image could not be read.", .ja: "画像を読み取れませんでした。",
            .zhHant: "無法讀取此圖片。", .zhHans: "无法读取此图片。",
        ],
        "ios.ticket.nothingFound": [
            .en: "Nothing could be read from this ticket. Try a sharper, well-lit photo.",
            .ja: "この乗車券から読み取れる内容がありませんでした。明るく鮮明な写真でお試しください。",
            .zhHant: "無法從此車票讀取任何內容，請改用清晰、光線充足的照片。",
            .zhHans: "无法从此车票读取任何内容，请改用清晰、光线充足的照片。",
        ],
        "ios.ticket.cancel": [
            .en: "Cancel", .ja: "キャンセル", .zhHant: "取消", .zhHans: "取消",
        ],
        "ios.ticket.kind.ticket": [
            .en: "Fare ticket", .ja: "乗車券", .zhHant: "乘車票", .zhHans: "乘车票",
        ],
        "ios.ticket.kind.expressSupplement": [
            .en: "Express supplement", .ja: "特急券", .zhHant: "特急附加票", .zhHans: "特急附加票",
        ],
        "ios.ticket.kind.seatReservation": [
            .en: "Reserved seat", .ja: "指定席券", .zhHant: "對號座位", .zhHans: "对号座位",
        ],
    ]
}
