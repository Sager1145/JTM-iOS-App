import Foundation

/// 台鐵 / 高鐵 tickets: `臺北 → 臺中`, `車次 0123`, `車廂 5 座位 12A` / `5車 12A`, `NT$1,490`.
enum TicketParserTW {
    private static let run = "\\p{Han}+"
    private static let services = "新自強|自強|莒光|復興|區間快|區間|普悠瑪|太魯閣|高鐵|THSR"
    private static let notStations: Set<String> = [
        "車次", "車廂", "座位", "票價", "乘車", "單程", "全票", "標準", "商務", "對號", "訂位",
        "起訖", "有效", "高鐵", "台鐵", "臺鐵", "台灣高鐵", "臺灣鐵路", "乘車票", "車票",
    ]

    static func parse(_ lines: [TicketLine]) -> TicketReadingResult {
        var draft = TicketDraft(region: .tw)
        var fares = TicketFareCandidates()
        var reserved: Double?
        var plain: Double?
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
            if TicketText.matches("車廂|座位|對號|訂位|\\d\\s*車(?![次廂站票])", in: line.text) {
                reserved = max(reserved ?? 0, line.confidence)
            }
            if TicketText.matches("車票|乘車票|單程|全票|票價", in: line.text) {
                plain = max(plain ?? 0, line.confidence)
            }
        }
        fares.apply(to: &draft, currency: "TWD", minorUnitFactor: 100)
        if let reserved {
            draft.offer(\.kind, .seatReservation, confidence: reserved * 0.9)
        } else if let plain {
            draft.offer(\.kind, .ticket, confidence: plain * 0.8)
        }
        return draft.result
    }

    // MARK: stations

    private static func clean(_ segment: String) -> String {
        var text = segment
        for pattern in [
            "\\d{1,2}:\\d{2}", "(?:\(services))(?=\\s*(?:號|\\d))", "號", "站",
            "起訖|起站|迄站|上車|下車|出發|抵達|到達|開車|乘車區間|乘車|車次|車廂|座位|票價",
        ] {
            text = TicketText.replacing(pattern, in: text)
        }
        return text
    }

    private static func station(_ run: String?) -> String? {
        guard let run, !notStations.contains(run) else { return nil }
        return run
    }

    private static func route(_ line: TicketLine, _ draft: inout TicketDraft) {
        let text = line.text
        if let parts = TicketText.splitRoute(text, extra: ["\\s*至\\s*"]),
            let from = station(TicketText.lastRun(run, in: clean(parts.left))),
            let to = station(TicketText.firstRun(run, in: clean(parts.right)))
        {
            draft.offer(\.origin, from, line, strength: 0.9)
            draft.offer(\.destination, to, line, strength: 0.9)
            return
        }
        if let hit = TicketText.groups(
            "(?:起站|上車站|出發站|出發地|出發)\\s*[:：]?\\s*(\(run))", in: text),
            let name = station(clean(hit[1]).trimmingCharacters(in: .whitespaces))
        {
            draft.offer(\.origin, name, line, strength: 0.85)
        }
        if let hit = TicketText.groups(
            "(?:迄站|下車站|到達站|抵達站|到達|抵達)\\s*[:：]?\\s*(\(run))", in: text),
            let name = station(clean(hit[1]).trimmingCharacters(in: .whitespaces))
        {
            draft.offer(\.destination, name, line, strength: 0.85)
        }
    }

    // MARK: date and time

    private static func date(in text: String) -> (value: TicketDate, strength: Double)? {
        let strength = TicketText.matches("發售|有效|列印|售票|購票", in: text) ? 0.4 : 1.0
        // (pattern, year offset: 0 Gregorian, 1911 Republic era)
        for (pattern, offset) in [
            ("(?<!\\d)(\\d{4})\\s*年\\s*(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*日", 0),
            ("(?<!\\d)(\\d{4})[/.\\-](\\d{1,2})[/.\\-](\\d{1,2})(?!\\d)", 0),
            ("民國\\s*(\\d{2,3})\\s*年\\s*(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*日", 1911),
            ("(?<!\\d)(\\d{3})\\s*年\\s*(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*日", 1911),
            ("(?<!\\d)(\\d{3})[/.\\-](\\d{1,2})[/.\\-](\\d{1,2})(?!\\d)", 1911),
        ] {
            if let g = TicketText.groups(pattern, in: text), let year = Int(g[1]),
                let month = Int(g[2]), let day = Int(g[3]),
                let value = TicketText.validDate(year: year + offset, month: month, day: day)
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
            "(?:開車|出發|發車)(?:時間)?\\s*[:：]?\\s*(\\d{1,2}):(\\d{2})",
            "(\\d{1,2}):(\\d{2})\\s*(?:開|發|出發)",
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
        guard !TicketText.matches("到達|抵達|迄|有效|發售|列印", in: text),
            let g = TicketText.groups("(?<!\\d)(\\d{1,2}):(\\d{2})(?!\\d)", in: text),
            let time = TicketText.clock(hour: g[1], minute: g[2])
        else { return nil }
        return (time, 0.5)
    }

    // MARK: service, car, seat, class

    private static func service(_ line: TicketLine, _ draft: inout TicketDraft) {
        let text = line.text
        if let g = TicketText.groups("(\(services))", in: text, ignoreCase: true) {
            draft.offer(\.serviceName, g[1].uppercased() == "THSR" ? "高鐵" : g[1], line, strength: 1.0)
        }
        if let g = TicketText.groups("車次\\s*[:：]?\\s*(\\d{1,4})", in: text) {
            draft.offer(\.serviceNumber, g[1], line, strength: 1.0)
        } else if let g = TicketText.groups("(?:\(services))\\s*號?\\s*(\\d{2,4})\\s*次?", in: text) {
            draft.offer(\.serviceNumber, g[1], line, strength: 0.9)
        } else if let g = TicketText.groups("(?<!\\d)(\\d{1,4})\\s*次(?!\\d)", in: text) {
            draft.offer(\.serviceNumber, g[1], line, strength: 0.8)
        }
    }

    private static func seat(_ line: TicketLine, _ draft: inout TicketDraft) {
        let text = line.text
        if let g = TicketText.groups("車廂\\s*[:：]?\\s*(\\d{1,2})", in: text) {
            draft.offer(\.car, TicketText.trimmedNumber(g[1]), line, strength: 1.0)
        } else if let g = TicketText.groups("(?<!\\d)(\\d{1,2})\\s*車(?![次廂站票])", in: text) {
            draft.offer(\.car, TicketText.trimmedNumber(g[1]), line, strength: 0.9)
        }
        func offerSeat(_ number: String, _ letter: String, strength: Double) {
            draft.offer(
                \.seat, TicketText.trimmedNumber(number) + letter.uppercased(), line,
                strength: strength)
        }
        if let g = TicketText.groups(
            "(?:座位|座號|席位)\\s*[:：]?\\s*(\\d{1,2})\\s*([A-Fa-f])?(?![A-Za-z0-9])", in: text)
        {
            offerSeat(g[1], g[2], strength: 1.0)
        } else if let g = TicketText.groups(
            "車\\s*(\\d{1,2})\\s*([A-Fa-f])(?![A-Za-z0-9])", in: text)
        {
            offerSeat(g[1], g[2], strength: 0.9)
        } else if let g = TicketText.groups("(?<!\\d)(\\d{1,2})\\s*([A-Fa-f])\\s*座", in: text) {
            offerSeat(g[1], g[2], strength: 0.9)
        } else if let g = TicketText.groups("^(\\d{1,2})\\s?([A-Fa-f])$", in: text) {
            offerSeat(g[1], g[2], strength: 0.7)
        }
    }

    private static func seatClass(_ line: TicketLine, _ draft: inout TicketDraft) {
        for (pattern, label) in [
            ("商務", "商務車廂"), ("標準", "標準車廂"), ("自由座", "自由座"), ("非對號", "非對號"),
            ("無座", "無座"), ("對號", "對號座"),
        ] where line.text.contains(pattern) {
            draft.offer(\.seatClass, label, line, strength: 1.0)
            return
        }
    }

    // MARK: fare

    private static func fare(_ line: TicketLine, _ fares: inout TicketFareCandidates) {
        let text = line.text
        let labelled = TicketText.matches("票價|金額|合計|總計", in: text)
        for pattern in [
            "(?:NT\\$?|TWD|NTD)\\s*(\\d[\\d,]*\\d|\\d)", "(?<![A-Za-z])\\$\\s*(\\d[\\d,]*\\d|\\d)",
            "(\\d[\\d,]*\\d|\\d)\\s*元", "(?:票價|金額|合計|總計)\\s*[:：]?\\s*(\\d[\\d,]*\\d|\\d)",
        ] {
            for g in TicketText.all(pattern, in: text, ignoreCase: true) {
                if let amount = TicketText.amount(g[1]) {
                    fares.add(amount, from: line, isLabelled: labelled)
                }
            }
        }
    }
}
