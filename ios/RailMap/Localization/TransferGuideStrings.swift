import Foundation
import RailCore

/// The strings the screenshot importer needs, which no other screen has.
///
/// Every entry carries all four interface languages, for the reason
/// ``DataStrings`` gives: a fallback string is an English string, and an
/// English string shown to a reader who chose 日本語 is a localisation bug
/// that compiles. Registered in ``AppStrings`` alongside the other five
/// tables, which is also what checks that none of these keys is spelled
/// anywhere else.
enum TransferGuideStrings {

    static let table: [String: [Localization.Language: String]] = [

        // MARK: entry

        "ios.guide.entry": [
            .zhHant: "讀取乘換案內截圖",
            .zhHans: "读取乘换案内截图",
            .ja: "乗換案内のスクリーンショットを読み込む",
            .en: "Read a transfer-guide screenshot",
        ],
        "ios.guide.title": [
            .zhHant: "從截圖匯入", .zhHans: "从截图导入", .ja: "スクリーンショットから読み込む",
            .en: "Import from a screenshot",
        ],
        "ios.guide.source": [
            .zhHant: "讀自 {app}", .zhHans: "读自 {app}", .ja: "{app} から読み取り",
            .en: "Read from {app}",
        ],
        "ios.guide.sourceUnknown": [
            .zhHant: "無法確定是哪個 App 的截圖，已用讀得較完整的那一種解析。",
            .zhHans: "无法确定是哪个 App 的截图，已用读得较完整的那一种解析。",
            .ja: "どのアプリの画面か判別できなかったため、より多く読み取れた方の解釈を採用しました。",
            .en:
                "Which app this came from could not be told, so whichever reading accounted for more of the picture was used.",
        ],
        "ios.guide.entryNote": [
            .zhHant: "從 Yahoo! 乗換案内 或 JR東日本アプリ 的路線截圖讀出車次、車站、時刻與月台。是哪個 App 由版面判斷，抹掉底部標誌也照樣認得。支援很長的長截圖；一條路線分成多張時可一次全選，會依順序接成一份。",
            .zhHans: "从 Yahoo! 乗換案内 或 JR東日本アプリ 的路线截图读出车次、车站、时刻与站台。是哪个 App 由版面判断，抹掉底部标志也照样认得。支持很长的长截图；一条路线分成多张时可一次全选，会按顺序拼成一份。",
            .ja: "Yahoo! 乗換案内 と JR東日本アプリ の経路スクリーンショットから列車・駅・時刻・のりばを読み取ります。どちらのアプリかは画面の作りから判断するので、下部のロゴを消してあっても読めます。非常に長い画像に対応し、1 経路が複数枚に分かれている場合はまとめて選ぶと順につなげます。",
            .en:
                "Reads the trains, stations, times and platforms out of a route in Yahoo! 乗換案内 or the JR East app. Which app it came from is worked out from the layout, so a screenshot with its footer logo removed still reads. Very tall screenshots are fine, and a route split across several images can be picked all at once — they are joined in order.",
        ],
        "ios.guide.choosePhotos": [
            .zhHant: "從照片選擇", .zhHans: "从照片选择", .ja: "写真から選ぶ", .en: "Choose from Photos",
        ],
        "ios.guide.chooseFiles": [
            .zhHant: "選擇圖片檔案", .zhHans: "选择图片文件", .ja: "画像ファイルを選ぶ",
            .en: "Choose image files",
        ],
        "ios.guide.pages": [
            .zhHant: "{count} 張截圖", .zhHans: "{count} 张截图", .ja: "{count} 枚",
            .en: "{count} screenshots",
        ],

        // MARK: reading

        "ios.guide.reading": [
            .zhHant: "正在辨識文字… {done}/{total}",
            .zhHans: "正在识别文字… {done}/{total}",
            .ja: "文字を認識しています… {done}/{total}",
            .en: "Reading text… {done}/{total}",
        ],
        "ios.guide.readingPlain": [
            .zhHant: "正在辨識文字…", .zhHans: "正在识别文字…", .ja: "文字を認識しています…",
            .en: "Reading text…",
        ],
        "ios.guide.readFailed": [
            .zhHant: "無法讀取這張截圖", .zhHans: "无法读取这张截图", .ja: "この画像は読み取れませんでした",
            .en: "This screenshot could not be read",
        ],
        "ios.guide.failUndecodable": [
            .zhHant: "這個檔案不是能讀取的圖片。",
            .zhHans: "这个文件不是能读取的图片。",
            .ja: "この画像は読み取れませんでした。",
            .en: "That file is not an image this can read.",
        ],
        "ios.guide.failTooLarge": [
            .zhHant: "圖片太大了（{detail}），請分成兩張再試。",
            .zhHans: "图片太大了（{detail}），请分成两张再试。",
            .ja: "画像が大きすぎます（{detail}）。2 枚に分けてお試しください。",
            .en: "The image is too large ({detail}). Split it into two and try again.",
        ],
        "ios.guide.failNoText": [
            .zhHant: "圖片裡沒有讀到文字。",
            .zhHans: "图片里没有读到文字。",
            .ja: "画像から文字が読み取れませんでした。",
            .en: "No text was found in the image.",
        ],
        "ios.guide.failUnavailable": [
            .zhHant: "這台裝置的文字辨識不支援日文。",
            .zhHans: "这台设备的文字识别不支持日文。",
            .ja: "この端末の文字認識は日本語に対応していません。",
            .en: "Text recognition on this device cannot read Japanese.",
        ],
        "ios.guide.networkLoading": [
            .zhHant: "鐵道資料還在載入，載入完成後才能對上車站。",
            .zhHans: "铁道数据还在载入，载入完成后才能匹配车站。",
            .ja: "鉄道データを読み込み中です。読み込みが終わると駅を照合できます。",
            .en: "The rail data is still loading; stations can be matched once it has.",
        ],
        "ios.guide.done": [
            .zhHant: "完成", .zhHans: "完成", .ja: "完了", .en: "Done",
        ],
        "ios.guide.retry": [
            .zhHant: "重新選擇", .zhHans: "重新选择", .ja: "選び直す", .en: "Choose again",
        ],

        // MARK: the route

        "ios.guide.summary": [
            .zhHant: "行程", .zhHans: "行程", .ja: "経路", .en: "Route",
        ],
        "ios.guide.window": [
            .zhHant: "{from} → {to}", .zhHans: "{from} → {to}", .ja: "{from} → {to}",
            .en: "{from} → {to}",
        ],
        "ios.guide.windowLabel": [
            .zhHant: "時刻", .zhHans: "时刻", .ja: "時刻", .en: "Times",
        ],
        "ios.guide.stations": [
            .zhHant: "車站", .zhHans: "车站", .ja: "駅", .en: "Stations",
        ],
        "ios.guide.hoursMinutes": [
            .zhHant: "{hours} 小時 {minutes} 分",
            .zhHans: "{hours} 小时 {minutes} 分",
            .ja: "{hours} 時間 {minutes} 分",
            .en: "{hours} h {minutes} min",
        ],
        "ios.guide.minutesOnly": [
            .zhHant: "{minutes} 分", .zhHans: "{minutes} 分", .ja: "{minutes} 分",
            .en: "{minutes} min",
        ],
        "ios.guide.duration": [
            .zhHant: "歷時 {text}", .zhHans: "历时 {text}", .ja: "所要 {text}", .en: "Takes {text}",
        ],
        "ios.guide.fare": [
            .zhHant: "車資 {yen} 円", .zhHans: "车费 {yen} 円", .ja: "運賃 {yen} 円",
            .en: "¥{yen}",
        ],
        "ios.guide.transfers": [
            .zhHant: "轉乘 {count} 次", .zhHans: "换乘 {count} 次", .ja: "乗換 {count} 回",
            .en: "{count} transfers",
        ],
        "ios.guide.distance": [
            .zhHant: "{km} 公里", .zhHans: "{km} 公里", .ja: "{km} km", .en: "{km} km",
        ],
        "ios.guide.date": [
            .zhHant: "日期", .zhHans: "日期", .ja: "日付", .en: "Date",
        ],
        "ios.guide.dateRead": [
            .zhHant: "日期讀自截圖；截圖不寫年份，已取最接近今天的一年。",
            .zhHans: "日期读自截图；截图不写年份，已取最接近今天的一年。",
            .ja: "日付はスクリーンショットから読み取りました。年は表示されないため、今日にいちばん近い年を当てています。",
            .en:
                "The day came off the screenshot. Screenshots carry no year, so the nearest one to today was used.",
        ],
        "ios.guide.dateGuessed": [
            .zhHant: "截圖裡沒有日期，先填今天。",
            .zhHans: "截图里没有日期，先填今天。",
            .ja: "スクリーンショットに日付がないため、今日を入れてあります。",
            .en: "The screenshot printed no date, so today is filled in.",
        ],

        // MARK: ridden or planned

        "ios.guide.status": [
            .zhHant: "記錄方式", .zhHans: "记录方式", .ja: "記録の種類", .en: "Record as",
        ],
        "ios.guide.ridden": [
            .zhHant: "已搭乘", .zhHans: "已乘坐", .ja: "乗車済み", .en: "Ridden",
        ],
        "ios.guide.planned": [
            .zhHant: "預定搭乘", .zhHans: "计划乘坐", .ja: "乗車予定", .en: "Planned",
        ],
        "ios.guide.riddenNote": [
            .zhHant: "路線照常繪製，區間計入里程統計。",
            .zhHans: "路线照常绘制，区间计入里程统计。",
            .ja: "経路は通常どおり描かれ、区間は距離の統計に入ります。",
            .en: "The route draws as usual and its segments count towards the mileage statistics.",
        ],
        "ios.guide.plannedNote": [
            .zhHant: "路線照常繪製，日期在今天之後會出現在「即將出發」，但區間不計入里程統計。搭過之後再到編輯裡打開「已搭乘區間」即可。",
            .zhHans: "路线照常绘制，日期在今天之后会出现在「即将出发」，但区间不计入里程统计。坐过之后再到编辑里打开「已乘坐区间」即可。",
            .ja: "経路は通常どおり描かれ、今日より後の日付は「これから」に並びますが、区間は距離の統計に入りません。乗ったあとに編集で「乗車区間」を有効にしてください。",
            .en:
                "The route draws as usual and a future date appears under Upcoming, but its segments stay out of the mileage statistics. Turn on the ridden-segment switch in the editor once the journey has happened.",
        ],

        // MARK: legs

        "ios.guide.legs": [
            .zhHant: "車次", .zhHans: "车次", .ja: "列車", .en: "Trains",
        ],
        "ios.guide.legSummary": [
            .zhHant: "{count} 站 · {from} {depart} → {to} {arrive}",
            .zhHans: "{count} 站 · {from} {depart} → {to} {arrive}",
            .ja: "{count} 駅 · {from} {depart} → {to} {arrive}",
            .en: "{count} stations · {from} {depart} → {to} {arrive}",
        ],
        "ios.guide.legPlatforms": [
            .zhHant: "發 {from} 號月台 · 到 {to} 號月台",
            .zhHans: "发 {from} 号站台 · 到 {to} 号站台",
            .ja: "発 {from} 番線 · 着 {to} 番線",
            .en: "Departs platform {from} · arrives platform {to}",
        ],
        "ios.guide.legPlatformFrom": [
            .zhHant: "發 {from} 號月台", .zhHans: "发 {from} 号站台", .ja: "発 {from} 番線",
            .en: "Departs platform {from}",
        ],
        "ios.guide.legPlatformTo": [
            .zhHant: "到 {to} 號月台", .zhHans: "到 {to} 号站台", .ja: "着 {to} 番線",
            .en: "Arrives platform {to}",
        ],
        "ios.guide.legLines": [
            .zhHant: "路線 {names}", .zhHans: "线路 {names}", .ja: "路線 {names}",
            .en: "Line {names}",
        ],
        "ios.guide.legBound": [
            .zhHant: "往 {bound}", .zhHans: "开往 {bound}", .ja: "{bound}行", .en: "For {bound}",
        ],
        "ios.guide.legCars": [
            .zhHant: "{count} 節", .zhHans: "{count} 节", .ja: "{count} 両", .en: "{count} cars",
        ],
        "ios.guide.legStartsHere": [
            .zhHant: "本站始發", .zhHans: "本站始发", .ja: "当駅始発", .en: "Starts here",
        ],
        "ios.guide.matched": [
            .zhHant: "已對上 {resolved}/{total} 個車站",
            .zhHans: "已匹配 {resolved}/{total} 个车站",
            .ja: "{total} 駅中 {resolved} 駅を照合",
            .en: "{resolved} of {total} stations matched",
        ],
        "ios.guide.unresolved": [
            .zhHant: "對不上的站名", .zhHans: "匹配不上的站名", .ja: "照合できなかった駅",
            .en: "Stations with no match",
        ],
        "ios.guide.unresolvedNote": [
            .zhHant: "鐵道資料裡找不到這些站。記錄會保留站名但沒有站碼，相關區間可能畫不出來——匯入後可在編輯裡挑選車站補上。",
            .zhHans: "铁道数据里找不到这些站。记录会保留站名但没有站码，相关区间可能画不出来——导入后可在编辑里挑选车站补上。",
            .ja: "鉄道データにこれらの駅が見つかりません。駅名は残りますが駅コードがないため、その区間は描けないことがあります。読み込んだあと編集で駅を選び直せます。",
            .en:
                "The rail data has no station spelled this way. The record keeps the name but has no code, so those stretches may not draw — pick the station in the editor after importing.",
        ],

        // MARK: what the parser wants to say

        "ios.guide.notes": [
            .zhHant: "值得看一眼", .zhHans: "值得看一眼", .ja: "確認してほしいこと",
            .en: "Worth a look",
        ],
        "ios.guide.noteNoHeader": [
            .zhHant: "沒有讀到最上面的行程摘要，日期可能要自己選。",
            .zhHans: "没有读到最上面的行程摘要，日期可能要自己选。",
            .ja: "上部の経路サマリーが読めませんでした。日付は手で選んでください。",
            .en: "The summary row at the top was not read, so the date may need choosing by hand.",
        ],
        "ios.guide.noteNoLegs": [
            .zhHant: "這張圖裡沒有讀到任何車次。請確認截的是路線詳情頁。",
            .zhHans: "这张图里没有读到任何车次。请确认截的是路线详情页。",
            .ja: "列車がひとつも読み取れませんでした。経路詳細の画面かどうか確認してください。",
            .en: "No train was found. Check that this is the route detail screen.",
        ],
        "ios.guide.noteBackwards": [
            .zhHant: "時刻比上一站早，可能認錯了數字：{subject}",
            .zhHans: "时刻比上一站早，可能认错了数字：{subject}",
            .ja: "前の駅より早い時刻です。数字を読み違えた可能性があります：{subject}",
            .en: "This time is earlier than the one above it — probably a misread digit: {subject}",
        ],
        "ios.guide.noteCount": [
            .zhHant: "讀到的站數和截圖上寫的不一樣：{subject}",
            .zhHans: "读到的站数和截图上写的不一样：{subject}",
            .ja: "読み取った駅数が画面の表示と違います：{subject}",
            .en: "The station count read does not match the one printed: {subject}",
        ],
        "ios.guide.noteShort": [
            .zhHant: "這段不足兩站，已略過：{subject}",
            .zhHans: "这段不足两站，已跳过：{subject}",
            .ja: "2 駅に満たないため除きました：{subject}",
            .en: "Fewer than two stations, so it was left out: {subject}",
        ],
        "ios.guide.noteNotRidden": [
            .zhHant: "步行或非鐵道區間，不會匯入：{subject}",
            .zhHans: "步行或非铁道区间，不会导入：{subject}",
            .ja: "徒歩など鉄道以外の区間は読み込みません：{subject}",
            .en: "Walking or non-rail, so it is not imported: {subject}",
        ],
        "ios.guide.noteMidnight": [
            .zhHant: "跨過午夜，之後的時刻寫成 24:09 這種形式：{subject}",
            .zhHans: "跨过午夜，之后的时刻写成 24:09 这种形式：{subject}",
            .ja: "日をまたぐため、以降の時刻は 24:09 のように書きます：{subject}",
            .en: "It crosses midnight, so the later times are spelled 24:09: {subject}",
        ],

        // MARK: the raw reading

        "ios.guide.raw": [
            .zhHant: "辨識到的原文", .zhHans: "识别到的原文", .ja: "認識した文字",
            .en: "What was read",
        ],
        "ios.guide.rawCount": [
            .zhHant: "{lines} 行 · {pages} 張 · {tiles} 塊",
            .zhHans: "{lines} 行 · {pages} 张 · {tiles} 块",
            .ja: "{lines} 行 · {pages} 枚 · {tiles} タイル",
            .en: "{lines} rows · {pages} images · {tiles} tiles",
        ],
        "ios.guide.unclaimed": [
            .zhHant: "沒有用到的文字", .zhHans: "没有用到的文字", .ja: "使わなかった文字",
            .en: "Rows nothing claimed",
        ],

        // MARK: committing

        "ios.guide.import": [
            .zhHant: "匯入 {count} 筆", .zhHans: "导入 {count} 条", .ja: "{count} 件を読み込む",
            .en: "Import {count}",
        ],
        "ios.guide.imported": [
            .zhHant: "已匯入 {count} 筆記錄。",
            .zhHans: "已导入 {count} 条记录。",
            .ja: "{count} 件を読み込みました。",
            .en: "Imported {count} journeys.",
        ],
        "ios.guide.nothing": [
            .zhHant: "沒有可以匯入的車次。", .zhHans: "没有可以导入的车次。",
            .ja: "読み込める列車がありません。", .en: "There is no train to import.",
        ],
    ]
}
