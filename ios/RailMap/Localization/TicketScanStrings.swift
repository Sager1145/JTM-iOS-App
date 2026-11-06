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
        "ios.ticket.review": [
            .en: "Review what was read", .ja: "読み取り結果を確認", .zhHant: "確認讀取結果", .zhHans: "确认读取结果",
        ],
        "ios.ticket.reviewHint": [
            .en: "Untick anything that looks wrong. Only ticked fields are applied.",
            .ja: "誤りがある項目のチェックを外してください。チェックした項目だけが反映されます。",
            .zhHant: "取消勾選看起來不正確的項目，只會套用已勾選的欄位。",
            .zhHans: "取消勾选看起来不正确的项目，只会应用已勾选的字段。",
        ],
        "ios.ticket.apply": [
            .en: "Apply", .ja: "適用", .zhHant: "套用", .zhHans: "应用",
        ],
        "ios.ticket.cancel": [
            .en: "Cancel", .ja: "キャンセル", .zhHant: "取消", .zhHans: "取消",
        ],
        "ios.ticket.rescan": [
            .en: "Scan again", .ja: "もう一度読み取る", .zhHant: "重新掃描", .zhHans: "重新扫描",
        ],
        "ios.ticket.lowConfidence": [
            .en: "Low confidence", .ja: "信頼度が低い", .zhHant: "可信度低", .zhHans: "可信度低",
        ],
        "ios.ticket.field.origin": [
            .en: "From", .ja: "出発駅", .zhHant: "出發站", .zhHans: "出发站",
        ],
        "ios.ticket.field.destination": [
            .en: "To", .ja: "到着駅", .zhHant: "到達站", .zhHans: "到达站",
        ],
        "ios.ticket.field.date": [
            .en: "Date", .ja: "乗車日", .zhHant: "乘車日期", .zhHans: "乘车日期",
        ],
        "ios.ticket.field.departureTime": [
            .en: "Departure", .ja: "発車時刻", .zhHant: "出發時間", .zhHans: "出发时间",
        ],
        "ios.ticket.field.serviceName": [
            .en: "Service", .ja: "列車名", .zhHant: "列車名稱", .zhHans: "列车名称",
        ],
        "ios.ticket.field.serviceNumber": [
            .en: "Train number", .ja: "列車番号", .zhHant: "車次", .zhHans: "车次",
        ],
        "ios.ticket.field.car": [
            .en: "Car", .ja: "号車", .zhHant: "車廂", .zhHans: "车厢",
        ],
        "ios.ticket.field.seat": [
            .en: "Seat", .ja: "座席", .zhHant: "座位", .zhHans: "座位",
        ],
        "ios.ticket.field.seatClass": [
            .en: "Class", .ja: "座席種別", .zhHant: "座位等級", .zhHans: "座位等级",
        ],
        "ios.ticket.field.fare": [
            .en: "Fare", .ja: "運賃・料金", .zhHant: "票價", .zhHans: "票价",
        ],
        "ios.ticket.field.kind": [
            .en: "Ticket type", .ja: "券の種類", .zhHant: "車票種類", .zhHans: "车票类型",
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
