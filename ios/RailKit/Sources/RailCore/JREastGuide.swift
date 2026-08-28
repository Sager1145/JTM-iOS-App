import Foundation

// =========================================================================
//  JREastGuide.swift — the same journey, drawn by a different app.
//
//  **Not a port.**
//
//  JR東日本アプリ draws a route the way Yahoo! 乗換案内 does not, and the
//  differences are all in the same place: what a row IS.
//
//      8月28日(金)                          ← header
//      04:16 → 18:24
//      14時間8分  乗換7回   10,290円
//      移動距離 605.5km
//                     更新時刻 02:14
//      鳥取 ›                               ← the origin, in a block of its own
//      出発時刻を変更 ›
//      ──────────────────────────────
//      04:16   ▌ ＪＲ因美線                 ← a leg header WITH a time in it
//      当駅始発    智頭行
//                 9駅目 で降りる
//      05:20着                              ← every stop has both times,
//              津ノ井                          not just the transfers
//      05:21発
//      …
//      05:58                                ← the arrival, on its own row
//              智頭     3分                  ← and the station on the next one
//      出発時刻を変更 ›
//
//  Three things follow from that, and they are the whole of this file:
//
//    1. A leg header carries the DEPARTURE TIME of the station above it.
//       Yahoo's carries no time at all, so the Yahoo walk reads that row as a
//       station and loses the leg.
//    2. A boundary station's time and its name are two rows about 150 points
//       apart, with the line graphic's tail between them. Nothing pairs them
//       by proximity; they are paired by ORDER — a bare time, then a bare
//       name, is an arrival.
//    3. Every intermediate stop carries 着 and 発. That costs nothing, since
//       ``TransferGuide/readCall(_:)`` already reads exactly that shape for
//       Yahoo's transfers.
//
//  Everything downstream is shared: the same ``TransferGuide/Route``, the
//  same records, the same station resolution. Only the grammar differs.
// =========================================================================

extension TransferGuide {

    /// Which app a screenshot came from.
    public enum Source: String, Sendable, Equatable {
        case yahoo
        case jrEast
        /// Neither could be told apart from the other. Both are then read and
        /// the better answer kept — see ``read(_:)``.
        case unknown

        public var label: String {
            switch self {
            case .yahoo: "Yahoo! 乗換案内"
            case .jrEast: "JR東日本アプリ"
            case .unknown: ""
            }
        }
    }

    // MARK: - the one entry point

    /// Reads a screenshot from whichever app took it.
    ///
    /// The reader picks a photograph, not a format. So the format is worked
    /// out here, and it is worked out from the LAYOUT before the wordmark:
    /// `9駅目で降りる`, `更新時刻`, `出発時刻を変更` and `移動距離` are JR East's
    /// and no one else's, `IC優先` and the fare boxes are Yahoo's, and none of
    /// them is in the footer. A screenshot cropped to hide the logo — or
    /// scrubbed of it on purpose — still says which app drew it on every
    /// screenful of its body.
    ///
    /// And when it does not, nothing is guessed: both readers run and the one
    /// that made more of the picture wins. Parsing is microseconds; being
    /// wrong about which app it was costs the reader a whole journey.
    public static func read(_ lines: [TextLine]) -> (source: Source, route: Route) {
        let rows = Rows.build(from: lines)
        let verdict = identify(rows)
        if verdict.confident {
            switch verdict.source {
            case .jrEast: return (.jrEast, parseJREast(rows))
            case .yahoo, .unknown: return (.yahoo, parseYahoo(rows))
            }
        }
        let yahoo = parseYahoo(rows)
        let jrEast = parseJREast(rows)
        return score(jrEast) > score(yahoo) ? (.jrEast, jrEast) : (.yahoo, yahoo)
    }

    /// How much of a screenshot a reading actually accounted for.
    ///
    /// Stations first, because that is what a journey is made of, and rows
    /// nothing claimed against it — a reader that produced ten legs of one
    /// station each and left the page unread has not understood it.
    static func score(_ route: Route) -> Int {
        let calls = route.ridableLegs.reduce(0) { $0 + $1.calls.count }
        return calls * 4 - route.unclaimed.count
    }

    // MARK: - telling them apart

    static func identify(_ rows: [Row]) -> (source: Source, confident: Bool) {
        var jrEast = 0
        var yahoo = 0
        var stackedTimes = 0

        for row in rows {
            let text = row.text
            // Layout, not livery. Every one of these is in the body.
            if text.contains("駅目") { jrEast += 3 }
            if text.contains("更新時刻") { jrEast += 3 }
            if text.contains("出発時刻を変更") { jrEast += 3 }
            if text.contains("移動距離") { jrEast += 2 }
            if text.contains("IC優先") { yahoo += 2 }
            if text.contains("二次元コード") || text.contains("ルート共有") { yahoo += 2 }
            if text.contains("指定席") || text.contains("自由席") { yahoo += 1 }
            // The circled 駅 count sits in Yahoo's leg header. JR East writes
            // 駅目 instead, which is why this asks for the count and a service
            // on ONE row rather than for the character.
            if row.tokens.contains(where: { if case .stationCount = $0 { true } else { false } }),
                row.tokens.contains(where: { if case .service = $0 { true } else { false } })
            {
                yahoo += 2
            }
            // Then the wordmark, if it survived.
            if text.contains("JR東日本") || text.contains("East Japan Railway") { jrEast += 4 }
            if text.contains("Yahoo") || text.contains("YAHOO") || text.contains("YAH") {
                yahoo += 4
            }
            if text.contains("乗換案内") { yahoo += 3 }
            if Rows.isTimeOnly(row), row.tokens.count == 1,
                case .time(_, let marker) = row.tokens[0], marker != nil
            {
                stackedTimes += 1
            }
        }
        // Yahoo prints 着 and 発 at transfers only — four of them on a
        // three-leg journey. JR East prints them at every stop.
        if stackedTimes >= 8 { jrEast += 2 }

        if jrEast == yahoo { return (.unknown, false) }
        let source: Source = jrEast > yahoo ? .jrEast : .yahoo
        return (source, abs(jrEast - yahoo) >= 3)
    }

    // MARK: - the walk

    static func parseJREast(_ rows: [Row]) -> Route {
        var route = Route()
        var unclaimed: [String] = []

        var pending: LegHeader?
        var openHeader: LegHeader?
        var carried: CallDraft?
        var drafts: [CallDraft] = []
        var closed: [(LegHeader, [CallDraft])] = []
        /// A bare time waiting for the station name printed under it.
        var pendingArrival: Int?
        /// A `N番線` read while no header was open: the platform a train comes
        /// IN on, which belongs to the leg being closed.
        var pendingArrivalPlatform: Int?
        var started = false

        func closeLeg() {
            guard let header = openHeader else { return }
            var closing = header
            if let platform = pendingArrivalPlatform {
                closing.arrivalPlatform = closing.arrivalPlatform ?? platform
                pendingArrivalPlatform = nil
            }
            closed.append((closing, drafts))
            carried = drafts.last
            drafts = []
            openHeader = nil
        }

        for (position, row) in rows.enumerated() {
            if row.isFooter { continue }

            if route.header.departure == nil, let read = readHeader(row) {
                route.header.merge(read)
                continue
            }
            if let summary = readSummary(row) {
                route.header.merge(summary)
                continue
            }

            // A leg header, and the time on it is the departure of the station
            // standing above. This test comes FIRST: the row carries a time
            // and would otherwise read as a station.
            if let header = readJRLegHeader(row), opensALeg(rows, from: position) {
                closeLeg()
                if let time = unmarkedTime(row) {
                    carried?.times.append((minutes: time, marker: .departure))
                }
                pendingArrival = nil
                pending = header
                started = true
                continue
            }

            // A line name printed mid-leg, where the train runs on to another
            // railway without anybody changing trains. It looks exactly like a
            // leg header — 門司's `ＪＲ鹿児島本線 16:37` even carries a time —
            // and reading it as one splits a ride in half at a station the
            // journey passes straight through.
            if openHeader != nil, let through = readJRLegHeader(row) {
                openHeader?.continue(with: through)
                // The time on such a row is the arrival at the boundary
                // BELOW it, not a departure from anything.
                if let time = unmarkedTime(row), started { pendingArrival = time }
                continue
            }

            // An ordinary stop: 着 and 発 either side of the name.
            if let call = readCall(row) {
                openLegIfPending(&pending, &openHeader, &drafts, &carried)
                pendingArrival = nil
                if openHeader != nil { drafts.append(call) } else { carried = call }
                continue
            }

            if let platform = onlyPlatform(row) {
                if pending != nil {
                    pending?.absorb(row)
                } else {
                    pendingArrivalPlatform = platform
                }
                continue
            }

            if let time = bareTime(row) {
                // The journey's origin has no arrival — the first bare time in
                // the document is 更新時刻 or a header remnant, not a train
                // getting in somewhere.
                if started { pendingArrival = time }
                continue
            }

            if let call = readBoundaryCall(row, arrival: pendingArrival) {
                openLegIfPending(&pending, &openHeader, &drafts, &carried)
                pendingArrival = nil
                started = true
                if openHeader != nil { drafts.append(call) } else { carried = call }
                continue
            }

            if pending != nil {
                pending?.absorb(row)
                continue
            }
            // 出発時刻を変更 and 更新時刻 stand between legs, where no header
            // is open to absorb them. They are furniture, not rows that went
            // unread, and counting them as unread would make this reader look
            // worse than the Yahoo one on a JR East screenshot.
            if isFurniture(row) { continue }
            if !row.tokens.isEmpty { unclaimed.append(row.text) }
        }
        closeLeg()
        if let service = pending?.service, !service.isEmpty { unclaimed.append(service) }

        route.legs = closed.map { header, calls in resolve(header: header, drafts: calls) }
        route.notes = review(route)
        route.unclaimed = unclaimed
        return route
    }

    /// A header block ends at the first station row, exactly as Yahoo's does.
    private static func openLegIfPending(
        _ pending: inout LegHeader?, _ openHeader: inout LegHeader?,
        _ drafts: inout [CallDraft], _ carried: inout CallDraft?
    ) {
        guard let opened = pending else { return }
        openHeader = opened
        drafts = []
        if let carried { drafts.append(carried) }
        carried = nil
        pending = nil
    }

    // MARK: - the rows JR East has and Yahoo does not

    /// Whether the service row at `position` starts a leg.
    ///
    /// Decided by what follows it, because nothing about the row itself can
    /// say. A leg header is followed, before the next station, by the things
    /// a boarding needs: where the train is bound, which platform, whether it
    /// starts here, and how many stops to stay on for. A line the train
    /// merely runs onto is followed by the next station and nothing else.
    static func opensALeg(_ rows: [Row], from position: Int) -> Bool {
        var index = position + 1
        while index < rows.count, index - position <= 8 {
            let row = rows[index]
            // The next station ends the block. Whatever the header was going
            // to say, it has not said it.
            if readCall(row) != nil || readBoundaryCall(row, arrival: nil) != nil { return false }
            for token in row.tokens {
                switch token {
                case .destination, .stationCount, .platform: return true
                case .note(let text) where text.contains("当駅始発"): return true
                default: continue
                }
            }
            index += 1
        }
        return false
    }

    /// The one time on a row that carries no 着/発 badge, whatever else the
    /// row holds.
    static func unmarkedTime(_ row: Row) -> Int? {
        var found: Int?
        for token in row.tokens {
            guard case .time(let minutes, let marker) = token else { continue }
            guard marker == nil, found == nil else { return nil }
            found = minutes
        }
        return found
    }

    /// A row that says something about the app rather than about the journey.
    static func isFurniture(_ row: Row) -> Bool {
        if row.text.contains("更新時刻") { return true }
        guard !row.tokens.isEmpty else { return true }
        return row.tokens.allSatisfy {
            switch $0 {
            case .note, .marker, .duration: true
            default: false
            }
        }
    }

    /// A leg header: a service, and whatever else shares its row.
    ///
    /// Unlike Yahoo's, this row may carry a time and a colour swatch that
    /// reads as a stray letter. Neither disqualifies it — the service does
    /// the identifying.
    static func readJRLegHeader(_ row: Row) -> LegHeader? {
        guard row.tokens.contains(where: { if case .service = $0 { true } else { false } })
        else { return nil }
        var header = LegHeader()
        for line in row.lines {
            for token in Token.read(line.text) {
                // The time on this row belongs to the station above it.
                if case .time = token { continue }
                header.absorbToken(token, from: line)
            }
        }
        return header.service.isEmpty ? nil : header
    }

    /// The one unmarked time on a row that holds nothing else.
    static func bareTime(_ row: Row) -> Int? {
        var found: Int?
        for token in row.tokens {
            switch token {
            case .time(let minutes, let marker):
                guard marker == nil, found == nil else { return nil }
                found = minutes
            // A row that also says something is not a bare time. `更新時刻
            // 02:14` is the clock the app refreshed at, and reading it as an
            // arrival would land the journey's first station two hours early.
            default: return nil
            }
        }
        return found
    }

    static func onlyPlatform(_ row: Row) -> Int? {
        var found: Int?
        for token in row.tokens {
            switch token {
            case .platform(_, let number):
                guard found == nil else { return nil }
                found = number
            case .note, .name: continue
            default: return nil
            }
        }
        return found
    }

    /// A station printed in a block of its own — the origin, a transfer, or
    /// the destination — with the time it arrived read from the row above.
    static func readBoundaryCall(_ row: Row, arrival: Int?) -> CallDraft? {
        var names: [String] = []
        for token in row.tokens {
            switch token {
            case .name(let text): names.append(text)
            // 3分 beside a transfer is how long there is to change, and 乗換
            // なし and the chevron are furniture. None of them stops the row
            // from being a station.
            case .duration, .note, .marker: continue
            default: return nil
            }
        }
        // The leftmost name. `下関 入 1分` puts an icon between the station
        // and the transfer time, and requiring the row to hold exactly one
        // name lost the station 下関 entirely.
        guard let name = names.first(where: { Text.looksLikeStationName($0) }) else { return nil }
        // With no arrival read above it this row is a guess, so it asks for
        // one more character: `指` is 指定席 clipped to its first glyph and
        // sits exactly where a boundary station does.
        guard arrival != nil || name.count >= 2 else { return nil }
        let parts = Text.stationName(gluedMarker(name).name)
        guard !parts.name.isEmpty else { return nil }
        return CallDraft(
            name: parts.name, qualifier: parts.qualifier, raw: name,
            times: arrival.map { [(minutes: $0, marker: Marker.arrival)] } ?? [])
    }
}
