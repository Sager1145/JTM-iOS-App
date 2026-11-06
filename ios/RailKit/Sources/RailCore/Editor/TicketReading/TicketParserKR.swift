import Foundation

/// Korail / SRT tickets: `서울 → 부산`, `KTX 123`, `5호차 12A`, `₩59,800`.
enum TicketParserKR {
    private static let run = "[가-힣]+"
    private static let services =
        "KTX-?산천|KTX-?이음|KTX-?청룡|KTX|SRT|ITX-?새마을|ITX-?마음|ITX-?청춘|ITX|무궁화호|새마을호|누리로"
    private static let notStations: Set<String> = [
        "승차권", "열차", "출발", "도착", "좌석", "호차", "일반실", "특실", "입석", "자유석",
        "운임", "금액", "승차일", "승차", "산천", "이음", "청룡",
    ]

    static func parse(_ lines: [TicketLine]) -> TicketReadingResult {
        var draft = TicketDraft(region: .kr)
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
            if TicketText.matches("호차|좌석|지정석", in: line.text) {
                reserved = max(reserved ?? 0, line.confidence)
            }
            if line.text.contains("승차권") { plain = max(plain ?? 0, line.confidence) }
        }
        fares.apply(to: &draft, currency: "KRW", minorUnitFactor: 1)
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
            "\\d{1,2}:\\d{2}", "(?:\(services))", "(?:출발|도착|행|발|착)\\s*$",
            "(?<=[가-힣])역(?![가-힣])",
        ] {
            text = TicketText.replacing(pattern, in: text, with: " ")
        }
        return TicketText.replacing("(?:출발|도착)", in: text)
    }

    private static func station(_ run: String?) -> String? {
        guard let run, !notStations.contains(run) else { return nil }
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
            return
        }
        if let hit = TicketText.groups("출발\\s*[:：]?\\s*(\(run))", in: text),
            let name = station(TicketText.firstRun(run, in: clean(hit[1])))
        {
            draft.offer(\.origin, name, line, strength: 0.85)
        }
        if let hit = TicketText.groups("도착\\s*[:：]?\\s*(\(run))", in: text),
            let name = station(TicketText.firstRun(run, in: clean(hit[1])))
        {
            draft.offer(\.destination, name, line, strength: 0.85)
        }
    }

    // MARK: date and time

    private static func date(in text: String) -> (value: TicketDate, strength: Double)? {
        let strength = TicketText.matches("발매|유효|인쇄", in: text) ? 0.4 : 1.0
        if let g = TicketText.groups(
            "(?<!\\d)(\\d{4})\\s*(?:년|[.\\-/])\\s*(\\d{1,2})\\s*(?:월|[.\\-/])\\s*(\\d{1,2})(?!\\d)",
            in: text),
            let year = Int(g[1]), let month = Int(g[2]), let day = Int(g[3]),
            let value = TicketText.validDate(year: year, month: month, day: day)
        {
            return (value, strength)
        }
        if let g = TicketText.groups("(?<!\\d)(\\d{1,2})\\s*월\\s*(\\d{1,2})\\s*일", in: text),
            let month = Int(g[1]), let day = Int(g[2]),
            let value = TicketText.validDate(year: nil, month: month, day: day)
        {
            return (value, strength * 0.9)
        }
        return nil
    }

    private static func departure(in text: String) -> (value: ServiceClockTime, strength: Double)? {
        for pattern in [
            "출발\\s*[:：]?\\s*(\\d{1,2}):(\\d{2})", "(\\d{1,2}):(\\d{2})\\s*출발",
            "(\\d{1,2})\\s*시\\s*(\\d{1,2})\\s*분?\\s*출발",
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
        guard !TicketText.matches("도착|유효|발매|인쇄", in: text),
            let g = TicketText.groups("(?<!\\d)(\\d{1,2}):(\\d{2})(?!\\d)", in: text),
            let time = TicketText.clock(hour: g[1], minute: g[2])
        else { return nil }
        return (time, 0.5)
    }

    // MARK: service, car, seat, class

    private static func service(_ line: TicketLine, _ draft: inout TicketDraft) {
        let text = line.text
        if let g = TicketText.groups("(\(services))\\s*-?\\s*(\\d{1,4})(?!\\d|:)", in: text, ignoreCase: true) {
            draft.offer(\.serviceName, g[1].uppercased(), line, strength: 1.0)
            draft.offer(\.serviceNumber, g[2], line, strength: 1.0)
        } else if let g = TicketText.groups("(\(services))", in: text, ignoreCase: true) {
            draft.offer(\.serviceName, g[1].uppercased(), line, strength: 0.8)
        }
        if let g = TicketText.groups("열차\\s*(?:번호)?\\s*[:：]?\\s*(\\d{1,4})", in: text) {
            draft.offer(\.serviceNumber, g[1], line, strength: 0.9)
        }
    }

    private static func seat(_ line: TicketLine, _ draft: inout TicketDraft) {
        let text = line.text
        if let g = TicketText.groups("(?<!\\d)(\\d{1,2})\\s*호차", in: text) {
            draft.offer(\.car, TicketText.trimmedNumber(g[1]), line, strength: 1.0)
        }
        func offerSeat(_ number: String, _ letter: String, strength: Double) {
            draft.offer(
                \.seat, TicketText.trimmedNumber(number) + letter.uppercased(), line,
                strength: strength)
        }
        if let g = TicketText.groups(
            "좌석\\s*[:：]?\\s*(\\d{1,2})\\s*([A-Da-d])?(?![A-Za-z0-9])", in: text)
        {
            offerSeat(g[1], g[2], strength: 1.0)
        } else if let g = TicketText.groups(
            "호차\\s*(\\d{1,2})\\s*([A-Da-d])(?![A-Za-z0-9])", in: text)
        {
            offerSeat(g[1], g[2], strength: 1.0)
        } else if let g = TicketText.groups("(?<!\\d)(\\d{1,2})\\s*([A-Da-d])\\s*석", in: text) {
            offerSeat(g[1], g[2], strength: 0.9)
        } else if let g = TicketText.groups("^(\\d{1,2})\\s?([A-Da-d])$", in: text) {
            offerSeat(g[1], g[2], strength: 0.7)
        } else if let g = TicketText.groups("호차\\s*(\\d{1,2})(?![\\d:])", in: text) {
            offerSeat(g[1], "", strength: 0.6)
        }
    }

    private static func seatClass(_ line: TicketLine, _ draft: inout TicketDraft) {
        for label in ["특실", "우등실", "일반실", "입석", "자유석"] where line.text.contains(label) {
            draft.offer(\.seatClass, label, line, strength: 1.0)
            return
        }
    }

    // MARK: fare

    private static func fare(_ line: TicketLine, _ fares: inout TicketFareCandidates) {
        let text = line.text
        let labelled = TicketText.matches("합계|총액|운임|금액", in: text)
        for pattern in [
            "₩\\s*(\\d[\\d,]*\\d|\\d)", "(\\d[\\d,]*\\d|\\d)\\s*원",
            "(?:합계|총액|운임|금액)\\s*[:：]?\\s*(\\d[\\d,]*\\d|\\d)",
        ] {
            for g in TicketText.all(pattern, in: text) {
                if let amount = TicketText.amount(g[1]) {
                    fares.add(amount, from: line, isLabelled: labelled)
                }
            }
        }
    }
}
