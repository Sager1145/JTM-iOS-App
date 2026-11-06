import Foundation

/// 乗車券 / 特急券 / 指定席券 as printed by JR: `東京 → 新大阪`, `のぞみ 25号`,
/// `5号車 12番A席`, `¥14,720`, `10:30発`.
enum TicketParserJP {
    private static let run = "[\\p{Han}\\p{Hiragana}\\p{Katakana}ー々ヶ・A-Za-z]+"
    /// `run` without the 発/着/駅 markers, for patterns that are anchored on them.
    private static let markedRun =
        "(?:(?![発着駅])[\\p{Han}\\p{Hiragana}\\p{Katakana}ー々ヶ・A-Za-z])+"
    private static let notStations: Set<String> = [
        "乗車券", "特急券", "指定席", "自由席", "新幹線", "普通車", "グリーン車", "グランクラス",
        "片道", "往復", "大人", "小児", "有効", "経由", "乗車券・特急券", "新幹線特急券",
        "指定席特急券", "特急券・乗車券",
    ]
    private static let knownServices = [
        "スーパーあずさ", "サンダーバード", "びわこエクスプレス", "ワイドビューひだ", "のぞみ", "ひかり",
        "こだま", "みずほ", "さくら", "つばめ", "はやぶさ", "はやて", "やまびこ", "なすの", "こまち",
        "かがやき", "はくたか", "つるぎ", "あさま", "たにがわ", "ひたち", "ときわ", "あずさ", "かいじ",
        "しらさぎ", "しなの", "ふじかわ", "しおかぜ", "いしづち", "しおさい", "わかしお", "さざなみ",
        "はるか", "くろしお", "こうのとり", "きのさき", "踊り子", "ひだ", "南紀", "とき",
    ]

    static func parse(_ lines: [TicketLine]) -> TicketReadingResult {
        var draft = TicketDraft(region: .jp)
        var fares = TicketFareCandidates()
        var kinds: [TicketKind: Double] = [:]
        for line in lines {
            route(line, &draft)
            if let date = date(in: line.text) {
                draft.offer(\.date, date.value, line, strength: date.strength)
            }
            if let time = departure(in: line.text) {
                draft.offer(\.departureTime, time.value, line, strength: time.strength)
            }
            service(line, &draft)
            seat(line, &draft)
            seatClass(line, &draft)
            fare(line, &fares)
            for (kind, hit) in kind(in: line.text) where hit {
                kinds[kind] = max(kinds[kind] ?? 0, line.confidence)
            }
        }
        fares.apply(to: &draft, currency: "JPY", minorUnitFactor: 1)
        for kind in [TicketKind.seatReservation, .expressSupplement, .ticket] {
            if let confidence = kinds[kind] {
                draft.offer(\.kind, kind, confidence: confidence * 0.9)
                break
            }
        }
        return draft.result
    }

    // MARK: stations

    private static func clean(_ segment: String) -> String {
        var text = segment
        for (pattern, template) in [
            ("[（(][^）)]*[）)]", " "), ("「[^」]*」", " "), ("経由.*$", " "),
            ("\\d{1,2}:\\d{2}", " "), ("(?:ゆき|行き|行|まで)\\s*$", " "), ("[発着駅]", " "),
        ] {
            text = TicketText.replacing(pattern, in: text, with: template)
        }
        return text
    }

    private static func station(_ run: String?) -> String? {
        guard let run, !notStations.contains(run) else { return nil }
        if run.count == 1, run.unicodeScalars.first.map({ !$0.properties.isIdeographic }) ?? true {
            return nil
        }
        return run
    }

    private static func route(_ line: TicketLine, _ draft: inout TicketDraft) {
        let text = line.text
        if let parts = TicketText.splitRoute(text),
            let from = station(TicketText.lastRun(run, in: clean(parts.left))),
            let to = station(TicketText.firstRun(run, in: clean(parts.right)))
        {
            draft.offer(\.origin, from, line, strength: 0.9)
            draft.offer(\.destination, to, line, strength: 0.9)
            if let time = TicketText.groups("(\\d{1,2}):(\\d{2})", in: parts.left),
                let clock = TicketText.clock(hour: time[1], minute: time[2])
            {
                draft.offer(\.departureTime, clock, line, strength: 0.9)
            }
            return
        }
        // Label forms: `東京 10:30発` / `新大阪 12:55着`, `乗車駅 東京`, `降車駅 新大阪`.
        let marker = "(\(markedRun))\\s*(?:駅)?\\s*(?:\\d{1,2}:\\d{2}\\s*)?"
        if let hit = TicketText.groups(marker + "発(?!売)", in: text), let name = station(hit[1]) {
            draft.offer(\.origin, name, line, strength: 0.85)
        }
        if let hit = TicketText.groups(marker + "着", in: text), let name = station(hit[1]) {
            draft.offer(\.destination, name, line, strength: 0.85)
        }
        if let hit = TicketText.groups("(?:乗車駅|発駅|出発駅)\\s*[:：]?\\s*(\(markedRun))", in: text),
            let name = station(hit[1])
        {
            draft.offer(\.origin, name, line, strength: 0.85)
        }
        if let hit = TicketText.groups("(?:降車駅|着駅|到着駅)\\s*[:：]?\\s*(\(markedRun))", in: text),
            let name = station(hit[1])
        {
            draft.offer(\.destination, name, line, strength: 0.85)
        }
    }

    // MARK: date and time

    private static func date(in text: String) -> (value: TicketDate, strength: Double)? {
        let issued = TicketText.matches("発売|有効|印刷|購入|発行", in: text)
        let strength = issued ? 0.4 : 1.0
        if let g = TicketText.groups("令和\\s*(\\d{1,2})\\s*年\\s*(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*日", in: text),
            let year = Int(g[1]), let month = Int(g[2]), let day = Int(g[3]),
            let value = TicketText.validDate(year: 2018 + year, month: month, day: day)
        {
            return (value, strength)
        }
        for pattern in [
            "(?<!\\d)(\\d{4})\\s*年\\s*(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*日",
            "(?<!\\d)(\\d{4})[/.\\-](\\d{1,2})[/.\\-](\\d{1,2})(?!\\d)",
        ] {
            if let g = TicketText.groups(pattern, in: text), let year = Int(g[1]),
                let month = Int(g[2]), let day = Int(g[3]),
                let value = TicketText.validDate(year: year, month: month, day: day)
            {
                return (value, strength)
            }
        }
        if let g = TicketText.groups("(?<!\\d)(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*日", in: text),
            let month = Int(g[1]), let day = Int(g[2]),
            let value = TicketText.validDate(year: nil, month: month, day: day)
        {
            return (value, strength * 0.9)
        }
        return nil
    }

    private static func departure(in text: String) -> (value: ServiceClockTime, strength: Double)? {
        for pattern in [
            "(\\d{1,2}):(\\d{2})\\s*発(?!売)", "発\\s*(\\d{1,2}):(\\d{2})", "(\\d{1,2})時(\\d{1,2})分?\\s*発(?!売)",
        ] {
            if let g = TicketText.groups(pattern, in: text),
                let time = TicketText.clock(hour: g[1], minute: g[2])
            {
                return (time, 1.0)
            }
        }
        if let parts = TicketText.splitRoute(text),
            let g = TicketText.groups("(\\d{1,2}):(\\d{2})", in: parts.left),
            let time = TicketText.clock(hour: g[1], minute: g[2])
        {
            return (time, 0.8)
        }
        guard !TicketText.matches("着|有効|発売|まで", in: text),
            let g = TicketText.groups("(?<!\\d)(\\d{1,2}):(\\d{2})(?!\\d)", in: text),
            let time = TicketText.clock(hour: g[1], minute: g[2])
        else { return nil }
        return (time, 0.5)
    }

    // MARK: service, car, seat, class

    private static func service(_ line: TicketLine, _ draft: inout TicketDraft) {
        let text = line.text
        let known = knownServices.joined(separator: "|")
        if let g = TicketText.groups("(\(known))\\s*(\\d{1,4})\\s*号(?!車)", in: text) {
            draft.offer(\.serviceName, g[1], line, strength: 1.0)
            draft.offer(\.serviceNumber, g[2], line, strength: 1.0)
        } else if let g = TicketText.groups(
            "([\\p{Han}\\p{Katakana}\\p{Hiragana}ー]{2,8}?)\\s*(\\d{1,4})\\s*号(?!車)", in: text)
        {
            let name = TicketText.replacing(
                "^(?:新幹線|寝台特急|特急|ＪＲ|JR)", in: g[1], with: "")
            if !name.isEmpty {
                draft.offer(\.serviceName, name, line, strength: 0.6)
            }
            draft.offer(\.serviceNumber, g[2], line, strength: 0.8)
        }
    }

    private static func seat(_ line: TicketLine, _ draft: inout TicketDraft) {
        let text = line.text
        if let g = TicketText.groups("(?<!\\d)(\\d{1,2})\\s*号車", in: text) {
            draft.offer(\.car, TicketText.trimmedNumber(g[1]), line, strength: 1.0)
        }
        func offerSeat(_ number: String, _ letter: String, strength: Double) {
            draft.offer(
                \.seat, TicketText.trimmedNumber(number) + letter.uppercased(), line,
                strength: strength)
        }
        if let g = TicketText.groups("(?<!\\d)(\\d{1,2})\\s*番\\s*([A-Ea-e])\\s*席?", in: text) {
            offerSeat(g[1], g[2], strength: 1.0)
        } else if let g = TicketText.groups("(?<!\\d)(\\d{1,2})\\s*([A-Ea-e])\\s*席", in: text) {
            offerSeat(g[1], g[2], strength: 1.0)
        } else if let g = TicketText.groups(
            "号車\\s*(\\d{1,2})\\s*([A-Ea-e])(?![A-Za-z0-9])", in: text)
        {
            offerSeat(g[1], g[2], strength: 0.9)
        } else if let g = TicketText.groups("^(\\d{1,2})\\s?([A-Ea-e])$", in: text) {
            offerSeat(g[1], g[2], strength: 0.7)
        } else if let g = TicketText.groups("(?<!\\d)(\\d{1,2})\\s*番(?!線|号|台|口)", in: text) {
            draft.offer(\.seat, TicketText.trimmedNumber(g[1]), line, strength: 0.6)
        }
    }

    private static func seatClass(_ line: TicketLine, _ draft: inout TicketDraft) {
        // A more specific class beats the bare 指定席 that appears in ticket titles.
        for (pattern, label, strength) in [
            ("グランクラス", "グランクラス", 1.0), ("グリーン", "グリーン車", 1.0), ("普通車", "普通車", 1.0),
            ("自由席", "自由席", 0.95), ("指定席", "指定席", 0.7),
        ] where line.text.contains(pattern) {
            draft.offer(\.seatClass, label, line, strength: strength)
            return
        }
    }

    // MARK: fare and kind

    private static func fare(_ line: TicketLine, _ fares: inout TicketFareCandidates) {
        let text = line.text
        guard !TicketText.matches("預|釣|つり|ポイント", in: text) else { return }
        let labelled = TicketText.matches("合計|総額|計", in: text)
        for pattern in ["¥\\s*(\\d[\\d,.]*\\d|\\d)", "(\\d[\\d,.]*\\d|\\d)\\s*円"] {
            for g in TicketText.all(pattern, in: text) {
                if let amount = TicketText.amount(g[1]) {
                    fares.add(amount, from: line, isLabelled: labelled)
                }
            }
        }
    }

    private static func kind(in text: String) -> [TicketKind: Bool] {
        [
            .seatReservation: text.contains("指定席"),
            .expressSupplement: text.contains("特急券") || text.contains("特急料金"),
            .ticket: text.contains("乗車券"),
        ]
    }
}
