import Foundation

// =========================================================================
//  TransferGuide.swift — reading a Yahoo! 乗換案内 route screenshot back
//  into stations and times.
//
//  **Not a port.** There is no JavaScript counterpart and no fixture: the web
//  app has no screenshot importer. It lives in RailCore for the reason
//  `RideMarkerVisibility` does — it is decidable without a platform
//  underneath it, and `swift test` can only reach this far down.
//
//  The split that makes it testable is the one Vision hands us anyway:
//
//    * THIS file takes ``TextLine`` values — a string and the rectangle it was
//      read from — and produces a ``Route``. It never sees a pixel, so every
//      case that matters (a two-line transfer stop, a 直通 leg that changes
//      line under way, a journey that crosses midnight) can be written down
//      as a handful of boxes in a test.
//    * ``TransferGuideTrains`` turns that ``Route`` into canonical records.
//    * The app owns the half that cannot be tested: running Vision over a
//      screenshot twenty thousand pixels tall.
//
//  ## What the layout actually is
//
//  Yahoo's route detail is two columns and one vertical rail:
//
//      10:45  発 │ 札幌                 ← a boundary station, larger type
//      (13駅)    │ ＪＲ特急北斗８号      ← a leg header block
//                │ 当駅始発 函館行
//                │ 発 8番線 / 着 2番線
//      10:54     │ 新札幌               ← an intermediate stop
//      …
//      14:18着   │
//                │ 新函館北斗           ← a transfer: two times, one name
//      14:39発   │
//
//  Everything below reads that grammar rather than pixel colours, because
//  colour is the one thing OCR does not return. The load-bearing rule is that
//  A LEG HEADER SPLITS THE DOCUMENT: the station row just above a leg header
//  is that leg's origin, the rows below it up to the next leg header are its
//  remaining calls, and the last of those is both its destination and the
//  next leg's origin. No font-size heuristic is needed to find a transfer,
//  which matters because font size is exactly what changes between an
//  iPhone SE screenshot and an iPad one.
// =========================================================================

public enum TransferGuide {

    // MARK: - what the caller hands in

    /// A rectangle in document space: x to the right, **y downward**, origin
    /// at the top-left of the screenshot.
    ///
    /// Downward y rather than Vision's own upward-y normalised space because
    /// this parser reads a document top to bottom, and a comparison that has
    /// to be mentally flipped every time is one that eventually gets written
    /// the wrong way round. The app converts once, at the boundary.
    ///
    /// The unit is only ever compared against other boxes from the same
    /// document, so it can be pixels, points, or the stitched space of several
    /// screenshots laid end to end — which is what lets a route captured in
    /// two screenshots parse as one document.
    public struct Box: Sendable, Hashable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public var minX: Double { x }
        public var maxX: Double { x + width }
        public var minY: Double { y }
        public var maxY: Double { y + height }
        public var midY: Double { y + height / 2 }
    }

    /// One line of text as an OCR engine returned it.
    public struct TextLine: Sendable, Hashable {
        public var text: String
        public var box: Box
        /// 0…1. Carried for the preview, not weighed by the parser: a
        /// confident misreading and a hesitant correct one are
        /// indistinguishable from here.
        public var confidence: Double

        public init(text: String, box: Box, confidence: Double = 1) {
            self.text = text
            self.box = box
            self.confidence = confidence
        }
    }

    // MARK: - what comes out

    public struct Route: Sendable, Equatable {
        public var header: Header
        public var legs: [Leg]
        public var notes: [Note]
        /// Rows no rule claimed, in document order. The preview shows these: a
        /// screenshot that parsed into two legs and forty unclaimed rows is a
        /// screenshot that did not parse, and saying so is cheaper than
        /// letting the reader discover it in the editor.
        public var unclaimed: [String]

        public init(
            header: Header = Header(), legs: [Leg] = [], notes: [Note] = [],
            unclaimed: [String] = []
        ) {
            self.header = header
            self.legs = legs
            self.notes = notes
            self.unclaimed = unclaimed
        }

        /// The legs that describe a train ride — walking connections and the
        /// blocks that are not a rail service dropped.
        public var ridableLegs: [Leg] { legs.filter { $0.kind == .train && $0.calls.count >= 2 } }
    }

    /// The route summary Yahoo prints above the itinerary.
    ///
    /// Every field is optional and none is required to build a journey: this
    /// is what the preview shows so the reader can tell at a glance whether
    /// the right screenshot was read.
    public struct Header: Sendable, Equatable {
        public var departure: String?
        public var arrival: String?
        public var durationMinutes: Int?
        /// The calendar day Yahoo prints — `8月28日(金)`. The year is almost
        /// never on screen, so it is resolved by the caller against today.
        public var month: Int?
        public var day: Int?
        public var year: Int?
        public var weekday: String?
        public var fareYen: Int?
        public var transferCount: Int?
        public var distanceKm: Double?

        public init() {}

        public var hasCalendarDay: Bool { month != nil && day != nil }

        public var hasContent: Bool {
            departure != nil || arrival != nil || hasCalendarDay || fareYen != nil
                || transferCount != nil || distanceKm != nil || durationMinutes != nil
        }

        mutating func merge(_ other: Header) {
            departure = departure ?? other.departure
            arrival = arrival ?? other.arrival
            durationMinutes = durationMinutes ?? other.durationMinutes
            month = month ?? other.month
            day = day ?? other.day
            year = year ?? other.year
            weekday = weekday ?? other.weekday
            fareYen = fareYen ?? other.fareYen
            transferCount = transferCount ?? other.transferCount
            distanceKm = distanceKm ?? other.distanceKm
        }
    }

    /// One block between two boundary stations.
    public struct Leg: Sendable, Equatable {

        public enum Kind: String, Sendable {
            /// A train, and the only kind that becomes a ``Train``.
            case train
            /// 徒歩 — a walking connection between two stations.
            case walk
            /// Recognised as a leg header but not as something on rails: a
            /// bus, a ferry, an airport connection.
            case other
        }

        public var kind: Kind
        /// `ＪＲ特急北斗８号` as `JR特急北斗8号` — normalised, and never blank
        /// for a leg the parser emitted.
        public var service: String
        /// The further lines a 直通 block names. `JR上野東京ライン` followed by
        /// `JR高崎線` is ONE ride that changes line under way, and splitting it
        /// into two legs would invent a transfer that never happened.
        public var throughServices: [String]
        /// `函館行` as `函館`.
        public var destination: String?
        /// The rolling stock Yahoo prints in brackets after the service —
        /// `(E5系)`, `(N700A)`.
        ///
        /// Kept apart from ``service`` rather than left inside it, and not
        /// because it is unimportant: it is the part a text recogniser gets
        /// wrong most often, because it is four Latin characters in a line of
        /// Japanese at the smallest size on the screen. `(N700A)` has been
        /// read as `(ND9OA)`. Out here that is a wrong note on a preview; in
        /// the service name it would be a wrong journey title, and it would
        /// disagree with the same train's name on the next screenshot.
        public var equipment: String?
        /// 当駅始発.
        public var startsHere: Bool
        public var departurePlatform: Int?
        public var arrivalPlatform: Int?
        /// 15両.
        public var carCount: Int?
        /// The `13駅` Yahoo prints in the circle. Compared against the calls
        /// actually read, which is the cheapest possible check on whether the
        /// screenshot was cropped mid-leg.
        public var declaredStationCount: Int?
        public var fareYen: Int?
        public var notes: [String]
        /// Every station this leg stops at, origin and destination included.
        public var calls: [Call]

        public init(
            kind: Kind = .train, service: String = "", throughServices: [String] = [],
            destination: String? = nil, equipment: String? = nil, startsHere: Bool = false,
            departurePlatform: Int? = nil, arrivalPlatform: Int? = nil,
            carCount: Int? = nil, declaredStationCount: Int? = nil,
            fareYen: Int? = nil, notes: [String] = [], calls: [Call] = []
        ) {
            self.kind = kind
            self.service = service
            self.throughServices = throughServices
            self.destination = destination
            self.equipment = equipment
            self.startsHere = startsHere
            self.departurePlatform = departurePlatform
            self.arrivalPlatform = arrivalPlatform
            self.carCount = carCount
            self.declaredStationCount = declaredStationCount
            self.fareYen = fareYen
            self.notes = notes
            self.calls = calls
        }

        /// Every line this leg runs over, the service's own first.
        public var serviceNames: [String] { [service] + throughServices }
    }

    /// One station as the screenshot spells it.
    ///
    /// Named `Call` rather than `Stop` so that nothing in this module can
    /// shadow ``RailCore/Stop``, which is the canonical on-disk shape and a
    /// different thing entirely: this one is what was read, that one is what
    /// is written.
    public struct Call: Sendable, Equatable {
        /// The station as a rail package would spell it — `森(北海道)` read as
        /// `森`. This is what a station table is asked for.
        public var name: String
        /// `北海道` out of `森(北海道)`. Yahoo prints it only where the name is
        /// ambiguous nationally, which makes it the single most useful hint
        /// there is for choosing between two stations of one name.
        public var qualifier: String?
        /// The row exactly as it was read, kept so a misreading can be
        /// recognised as one in the preview.
        public var rawName: String
        /// `"HH:MM"`, hours running past 24 for the next day — jsonspec
        /// §10.5, applied by ``rollOverMidnight(_:)``.
        public var arrival: String?
        public var departure: String?

        public init(
            name: String, qualifier: String? = nil, rawName: String = "",
            arrival: String? = nil, departure: String? = nil
        ) {
            self.name = name
            self.qualifier = qualifier
            self.rawName = rawName.isEmpty ? name : rawName
            self.arrival = arrival
            self.departure = departure
        }
    }

    /// Something the reader should know before importing.
    ///
    /// Deliberately not an error: none of these stops the import. A journey
    /// read out of a photograph is a draft, and the honest thing to do with a
    /// doubt is to name it beside the thing it is about.
    public struct Note: Sendable, Equatable {
        public enum Kind: String, Sendable {
            /// No `10:45→00:09` row was found.
            case noHeader
            /// No leg header was found, so nothing can be imported.
            case noLegs
            /// A time is earlier than the one above it by too little to be a
            /// midnight crossing. Almost always a misread digit.
            case timeWentBackwards
            /// Yahoo said `13駅` and a different number of calls was read.
            case stationCountDisagrees
            /// A leg that reached fewer than two stations.
            case shortLeg
            /// A 徒歩 or bus block, which is not imported as a ride.
            case legNotRidden
            /// A leg crosses midnight; its later times are spelled `24:09`.
            case crossedMidnight
        }

        public var kind: Kind
        /// A record value — a station name, a service, a time — never a
        /// catalog key. The interface writes the sentence; this says what the
        /// sentence is about.
        public var subject: String

        public init(kind: Kind, subject: String = "") {
            self.kind = kind
            self.subject = subject
        }
    }

    // MARK: - the parse

    /// Reads a screenshot's text into a route.
    ///
    /// Total: never throws, never returns nil. A screenshot of something else
    /// parses into a route with no legs and a `noLegs` note, which is
    /// something the preview can show; a thrown error is not.
    public static func parse(_ lines: [TextLine]) -> Route {
        parseYahoo(Rows.build(from: lines))
    }

    /// Yahoo's grammar. JR東日本アプリ's is ``parseJREast(_:)``, and
    /// ``read(_:)`` is the door both are behind.
    static func parseYahoo(_ rows: [Row]) -> Route {
        var route = Route()
        var unclaimed: [String] = []

        // The document walk. `pending` is a leg header block still being read;
        // `openHeader` is the leg it became once a station row closed it;
        // `carried` is the boundary station that belongs to two legs at once.
        var pending: LegHeader?
        /// Whether `pending` is the rest of the open leg rather than a new one.
        var pendingContinues = false
        var openHeader: LegHeader?
        var carried: CallDraft?
        var drafts: [CallDraft] = []
        var closed: [(LegHeader, [CallDraft])] = []

        func closeLeg() {
            guard let header = openHeader else { return }
            closed.append((header, drafts))
            carried = drafts.last
            drafts = []
            openHeader = nil
        }

        for row in rows {
            if row.isFooter { continue }

            if route.header.departure == nil, let read = readHeader(row) {
                route.header.merge(read)
                continue
            }
            if let summary = readSummary(row) {
                route.header.merge(summary)
                continue
            }
            if let call = readCall(row) {
                if let opened = pending {
                    if pendingContinues, openHeader != nil {
                        // 乗換不要: one ride whose LINE changed under it. The
                        // block below the badge names the new line, and
                        // folding it into the leg above is what keeps
                        // 越後湯沢→直江津 one journey instead of three.
                        openHeader?.continue(with: opened)
                    } else {
                        // The header block just ended. This leg's origin is
                        // the boundary station standing above it.
                        openHeader = opened
                        drafts = []
                        if let carried { drafts.append(carried) }
                        carried = nil
                    }
                    pending = nil
                    pendingContinues = false
                }
                if openHeader != nil {
                    drafts.append(call)
                } else {
                    // Above the first leg header: the journey's own origin.
                    // The last one wins — it is the row directly above the
                    // block, and anything earlier was a misread.
                    carried = call
                }
                continue
            }
            // An open block swallows everything until a station row closes
            // it, INCLUDING a second service name. `ＪＲ上野東京ライン` and
            // the `ＪＲ高崎線` printed under it are one 直通 ride that changes
            // line at 大宮; reading the second as a new leg would invent a
            // transfer at a station the train does not even stop long enough
            // to be transferred at.
            if pending != nil {
                pending?.absorb(row)
                continue
            }
            // A station whose time was not read at all. Only inside a leg
            // that is already running, and only for a row that is a bare
            // station name: a stop that arrives without its time is a stop
            // with a gap in it, and a stop that never arrives is a journey
            // that skips a station it made.
            if openHeader != nil, !drafts.isEmpty, let call = readBareCall(row) {
                drafts.append(call)
                continue
            }
            if let header = readLegHeader(row) {
                // A block that follows a 乗換不要 station belongs to the leg
                // already running; anything else ends it.
                if openHeader != nil, drafts.last?.continues == true {
                    pendingContinues = true
                } else {
                    closeLeg()
                }
                pending = header
                continue
            }
            if !row.tokens.isEmpty { unclaimed.append(row.text) }
        }
        closeLeg()
        // A header block at the very end of a cropped screenshot never met a
        // station row. It is not a leg; it is the top of the next screenshot.
        if let service = pending?.service, !service.isEmpty { unclaimed.append(service) }

        route.legs = closed.map { header, calls in resolve(header: header, drafts: calls) }
        route.notes = review(route)
        route.unclaimed = unclaimed
        return route
    }

    // MARK: - rows

    /// One horizontal band of the screenshot.
    struct Row {
        var lines: [TextLine]
        var tokens: [Token]
        var text: String
        var box: Box
        /// Where the reader sees this row, which stops being the middle of its
        /// box as soon as it adopts a time from half a row above. 新函館北斗
        /// stays where its name is printed however many times are handed to
        /// it — otherwise adopting the 着 drags the row up far enough that the
        /// 発 below can no longer reach it.
        var anchorY: Double

        var isFooter: Bool { Vocabulary.footerMarkers.contains { text.contains($0) } }
    }

    enum Rows {

        /// Groups OCR lines into the bands a reader sees as rows.
        ///
        /// Two passes, because the transfer stop needs both. The first
        /// clusters on a GLOBAL scale — half the median glyph height — so the
        /// answer cannot depend on which row happened to come first, and a
        /// tall heading cannot swallow the list under it. The second repairs
        /// the one case the first cannot see: at a transfer, `14:18着` and
        /// `14:39発` are stacked in the time column against one station name,
        /// and each is its own band until it is given back to that name.
        static func build(from lines: [TextLine]) -> [Row] {
            let usable = lines.compactMap { line -> TextLine? in
                let text = Text.normalize(line.text)
                guard !text.isEmpty else { return nil }
                var copy = line
                copy.text = text
                return copy
            }
            guard !usable.isEmpty else { return [] }

            let scale = median(usable.map(\.box.height))
            let tolerance = max(scale * 0.45, 0.5)
            let sorted = usable.sorted {
                $0.box.midY == $1.box.midY ? $0.box.minX < $1.box.minX : $0.box.midY < $1.box.midY
            }

            var bands: [[TextLine]] = []
            var current: [TextLine] = []
            var anchor = sorted[0].box.midY
            for line in sorted {
                if current.isEmpty {
                    anchor = line.box.midY
                    current = [line]
                } else if abs(line.box.midY - anchor) <= tolerance {
                    current.append(line)
                } else {
                    bands.append(current)
                    anchor = line.box.midY
                    current = [line]
                }
            }
            if !current.isEmpty { bands.append(current) }

            let rows = bands.map(assemble)
            return reuniteTimes(rows, reach: adoptionReach(rows, scale: scale))
        }

        /// How far a stray time band may be adopted from.
        ///
        /// Measured from the document's own row PITCH rather than from glyph
        /// height, because the two numbers this has to separate are both
        /// expressed in it: the stacked 着/発 pair of a transfer sits at about
        /// half a row, and the next station is a whole one away. A fraction of
        /// the pitch splits them at any font size; a multiple of the glyph
        /// height only splits them at the size it was tuned against.
        static func adoptionReach(_ rows: [Row], scale: Double) -> Double {
            let pitch = median(
                zip(rows, rows.dropFirst()).map { abs($1.anchorY - $0.anchorY) })
            return pitch > 0 ? pitch * 1.35 : max(scale * 3, 1)
        }

        /// Gives a band that is nothing but times back to the station name it
        /// stands beside.
        ///
        /// Only ever moves a time band into a name band, never the other way
        /// round, so the worst case of a wrong guess is a call that keeps a
        /// time it should not have — visible in the preview — rather than a
        /// leg that splits in the wrong place.
        static func reuniteTimes(_ rows: [Row], reach: Double) -> [Row] {
            var rows = rows
            var index = 0
            while index < rows.count {
                guard isTimeOnly(rows[index]) else {
                    index += 1
                    continue
                }
                var target: Int?
                var best = Double.greatestFiniteMagnitude
                for offset in [index - 1, index + 1] where rows.indices.contains(offset) {
                    guard isAdoptive(rows[offset]) else { continue }
                    let gap = abs(rows[offset].anchorY - rows[index].anchorY)
                    if gap < best, gap <= reach {
                        best = gap
                        target = offset
                    }
                }
                guard let target else {
                    index += 1
                    continue
                }
                let anchor = rows[target].anchorY
                rows[target] = assemble(rows[target].lines + rows[index].lines)
                rows[target].anchorY = anchor
                rows.remove(at: index)
                if target < index { index = target + 1 }
            }
            return rows
        }

        static func isTimeOnly(_ row: Row) -> Bool {
            guard !row.tokens.isEmpty else { return false }
            // `10:45→00:09` is two times and nothing else, and it is the route
            // summary rather than a transfer's stray half. Handing it to the
            // first station under it would give the journey's origin the whole
            // journey's arrival time.
            guard !row.text.contains("→"), !row.text.contains("~") else { return false }
            return row.tokens.allSatisfy {
                switch $0 {
                case .time, .marker: true
                default: false
                }
            }
        }

        /// A row that can take a stray time: it names a station, and it holds
        /// nothing that belongs to a leg header.
        ///
        /// A row that already has a time of its own still qualifies, because a
        /// transfer hands over two — `14:18着` above the name and `14:39発`
        /// below it — and the second would have nowhere to go if the first
        /// had disqualified its own new home.
        static func isAdoptive(_ row: Row) -> Bool {
            var hasName = false
            for token in row.tokens {
                switch token {
                case .name: hasName = true
                case .marker, .time: continue
                default: return false
                }
            }
            return hasName
        }

        static func assemble(_ lines: [TextLine]) -> Row {
            // (x, then y): the two halves of a transfer stop sit in the same
            // column, and `sorted` is not stable, so a tie has to be broken
            // deliberately or 14:18着 and 14:39発 swap between runs.
            let ordered = lines.sorted {
                $0.box.minX == $1.box.minX ? $0.box.minY < $1.box.minY : $0.box.minX < $1.box.minX
            }
            var box = ordered.first?.box ?? Box(x: 0, y: 0, width: 0, height: 0)
            for line in ordered.dropFirst() {
                let minX = min(box.minX, line.box.minX)
                let minY = min(box.minY, line.box.minY)
                box = Box(
                    x: minX, y: minY,
                    width: max(box.maxX, line.box.maxX) - minX,
                    height: max(box.maxY, line.box.maxY) - minY)
            }
            return Row(
                lines: ordered,
                tokens: ordered.flatMap { Token.read($0.text) },
                text: ordered.map(\.text).joined(separator: " "),
                box: box,
                anchorY: box.midY)
        }

        static func median(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
    }

    // MARK: - row meaning

    public enum Marker: String, Sendable, Equatable {
        case arrival
        case departure
    }

    /// `10:45→00:09 (13時間24分) 8月28日(金)`.
    ///
    /// The arrow is what separates this from a station row that happens to
    /// carry two times, and it is read from the text rather than the tokens
    /// because Vision returns it as `→`, `~`, `-` and `>` on different runs of
    /// the same screenshot. Where none of those survived, a row carrying two
    /// times AND a duration or a calendar day is the same row: no station row
    /// ever carries either.
    static func readHeader(_ row: Row) -> Header? {
        var times: [Int] = []
        var header = Header()
        var hasDuration = false
        for token in row.tokens {
            switch token {
            case .time(let minutes, _): times.append(minutes)
            case .duration(let minutes):
                header.durationMinutes = minutes
                hasDuration = true
            case .calendar(let month, let day, let year, let weekday):
                header.month = month
                header.day = day
                header.year = year
                header.weekday = weekday
            default: continue
            }
        }
        let arrowed = row.text.contains("→") || row.text.contains("~")
        guard times.count >= 2, arrowed || hasDuration || header.hasCalendarDay else { return nil }
        header.departure = Clock.text(times[0])
        header.arrival = Clock.text(times[1])
        return header
    }

    /// `IC優先 47,280円 乗換2回 2338.2km`, and the bare date row Yahoo
    /// sometimes prints on its own.
    ///
    /// A fare on its own is NOT this row: that is a leg header's price box,
    /// and reading it as the route total would put ¥3,170 on a ¥47,280
    /// journey. The route summary is the row that counts transfers or
    /// measures the whole distance, and nothing else does either.
    static func readSummary(_ row: Row) -> Header? {
        var header = Header()
        var counted = false
        var hasDuration = false
        for token in row.tokens {
            switch token {
            case .fare(let yen): header.fareYen = yen
            case .duration(let minutes):
                header.durationMinutes = minutes
                hasDuration = true
            case .transfers(let count):
                header.transferCount = count
                counted = true
            case .distance(let km):
                header.distanceKm = km
                counted = true
            case .calendar(let month, let day, let year, let weekday):
                header.month = month
                header.day = day
                header.year = year
                header.weekday = weekday
                counted = true
            // Stray glyphs ride along on this row — the QR badge beside
            // Yahoo's summary comes back as `日A ロロ` — and rejecting the row
            // for carrying them would lose the fare, the transfers and the
            // distance with them.
            case .note, .name, .marker: continue
            default: return nil
            }
        }
        // A duration counts only in the company of a fare. JR East writes both
        // on one row (`14時間8分 乗換7回 10,290円`); a duration ON ITS OWN is
        // the `3分` printed beside a transfer station, and reading that row as
        // the route summary would swallow the station.
        if hasDuration, header.fareYen != nil { counted = true }
        return counted ? header : nil
    }

    /// A station row: a name, and the times printed beside it.
    static func readCall(_ row: Row) -> CallDraft? {
        var times: [(minutes: Int, marker: Marker?)] = []
        var names: [String] = []
        var fallbackNames: [String] = []
        var markers: [Marker] = []
        var continues = false

        for token in row.tokens {
            switch token {
            case .time(let minutes, let marker): times.append((minutes, marker))
            case .marker(let marker): markers.append(marker)
            case .name(let text): names.append(text)
            // A station can wear a badge. `乗換不要 犀潟` is where the line
            // changes under a train that does not — rejecting the row for
            // carrying a note dropped the station AND made the block below it
            // look like a fresh journey.
            case .note(let text): continues = continues || Self.isThrough(text)
            // 鉄道博物館 and 学園都市線 are station names that read as service
            // names on their face. A leg header never carries a time, so a row
            // that does can take one back.
            case .service(let text, _), .destination(let text): fallbackNames.append(text)
            // Anything else says this is not a station row: a duration, a
            // fare, a platform and a station count all belong to the blocks
            // around the list, never to a call inside it.
            default: return nil
            }
        }
        guard !times.isEmpty || !markers.isEmpty else { return nil }
        // The LEFTMOST name, not the last. The 駅構内図 icon stands to the
        // RIGHT of the station and comes back as its own word — `東京 iff` —
        // so taking the last one names the journey's transfer station `iff`.
        guard let name = names.first ?? (times.isEmpty ? nil : fallbackNames.first) else {
            return nil
        }
        guard Text.looksLikeStationName(name) else { return nil }

        let glued = gluedMarker(name)
        let parts = Text.stationName(glued.name)
        guard !parts.name.isEmpty else { return nil }

        // A bare 発 or 着 badge beside a time says which one it is. Applied to
        // the LAST unmarked time so that `14:18着 14:39 発 東京` — where Vision
        // attached the badge to the second time and not the first — still
        // reads as arrive-then-depart.
        var resolved = times
        if let marker = markers.first ?? glued.marker,
            let index = resolved.lastIndex(where: { $0.marker == nil })
        {
            resolved[index].marker = marker
        }
        return CallDraft(
            name: parts.name, qualifier: parts.qualifier, raw: name, times: resolved,
            continues: continues)
    }

    /// Whether a badge says the train carries on through this station.
    static func isThrough(_ text: String) -> Bool {
        text.contains("乗換不要") || text.contains("乗り換え不要") || text.contains("乗換なし")
    }

    /// The 着/発 badge, where Vision returned it stuck to the station.
    ///
    /// `00:09 着 博多` is a time, a grey badge and a heading; the last two came
    /// back as one word, `着博多`. 着 is safe to take off the front because no
    /// station begins with it. 発 is not: 発寒, 発寒中央 and 発坂 are real
    /// stations, and they are the reason this is a list rather than a rule.
    static func gluedMarker(_ raw: String) -> (marker: Marker?, name: String) {
        let text = Text.normalize(raw)
        guard text.count > 1 else { return (nil, raw) }
        if text.hasPrefix("着") { return (.arrival, String(text.dropFirst())) }
        guard text.hasPrefix("発"), !hatsuStations.contains(text) else { return (nil, raw) }
        return (.departure, String(text.dropFirst()))
    }

    /// Every station in the five packages whose name begins with 発.
    ///
    /// There are exactly four, and this list is checked against the packages
    /// rather than remembered: 発寒南 was missing, so a route ending there was
    /// read as a 発 badge glued to a station called 寒南 — a name no package
    /// carries, so the stop was saved with no code and that stretch of the
    /// journey never drew.
    static let hatsuStations: Set<String> = ["発寒", "発寒中央", "発寒南", "発坂"]

    /// A station row whose time column came back empty.
    static func readBareCall(_ row: Row) -> CallDraft? {
        var names: [String] = []
        var continues = false
        for token in row.tokens {
            switch token {
            case .name(let text): names.append(text)
            case .note(let text): continues = continues || Self.isThrough(text)
            case .marker: continue
            default: return nil
            }
        }
        // A station read with no time beside it is a rescue, so it asks for
        // one more character than usual: `指` is 指定席 clipped to its first
        // glyph, and 森, 泊 and 蕨 are one-character stations that still have
        // their times.
        guard names.count == 1, let name = names.first, name.count >= 2,
            Text.looksLikeStationName(name)
        else { return nil }
        let parts = Text.stationName(gluedMarker(name).name)
        guard !parts.name.isEmpty else { return nil }
        return CallDraft(
            name: parts.name, qualifier: parts.qualifier, raw: name, times: [],
            continues: continues)
    }

    /// The first row of a leg header block.
    static func readLegHeader(_ row: Row) -> LegHeader? {
        let opens = row.tokens.contains {
            switch $0 {
            case .service, .stationCount: true
            default: false
            }
        }
        guard opens else { return nil }
        var header = LegHeader()
        header.absorb(row)
        return header
    }

    // MARK: - drafts

    /// A station row before it knows which leg it belongs to.
    ///
    /// The times stay unresolved on purpose: the same row is the destination
    /// of one leg and the origin of the next, and `14:18着 / 14:39発` means
    /// arrival to one of them and departure to the other. Deciding at the row
    /// would force one leg to carry the other's time.
    struct CallDraft {
        var name: String
        var qualifier: String?
        var raw: String
        var times: [(minutes: Int, marker: Marker?)]
        /// The row said 乗換不要: the line changes here and the train does not.
        var continues = false
    }

    /// A leg header block while it is still being read.
    struct LegHeader {
        var kind: Leg.Kind = .train
        var service: String = ""
        var throughServices: [String] = []
        var destination: String?
        var equipment: String?
        var startsHere = false
        var departurePlatform: Int?
        var arrivalPlatform: Int?
        var carCount: Int?
        var declaredStationCount: Int?
        var fareYen: Int?
        var notes: [String] = []
        /// The box the service name was read from. A long service wraps onto a
        /// second line in the real interface — `ＪＲ新幹線はやぶ` / `さ28号(E5系)`
        /// — and the only thing that says the second line is the rest of the
        /// first is that it starts at the same x, a few points below it.
        var serviceBox: Box?

        /// `のぞみ57号(N700A)` as the train, the stock, and — where the
        /// bracket holds `(小田原行)` instead — the destination it really was.
        static func split(
            service text: String
        ) -> (name: String, equipment: String?, destination: String?) {
            guard let cut = bracketStart(in: text) else { return (text, nil, nil) }
            let head = String(text[text.startIndex..<cut.name])
                .trimmingCharacters(in: .whitespaces)
            var body = String(text[cut.body...])
            // An unmatched closing paren: the opening one is the character
            // most often lost, because it sits between a kanji and a Latin
            // capital at the smallest size on the screen.
            if body.hasSuffix(")"), !body.contains("(") { body = String(body.dropLast()) }
            let cleaned = Text.stripDecorations(body)
            guard !head.isEmpty, Text.hasWordCharacter(cleaned) else { return (text, nil, nil) }
            if let bound = Scan.destination(cleaned) { return (head, nil, bound) }
            return (head, cleaned, nil)
        }

        /// Where the service's own name ends and its bracket begins.
        ///
        /// The bracket first, when it survived. When it did not — Vision read
        /// `はやぶさ28号(E5系)` as `はやぶさ28号$5系)` — 号 is the fallback,
        /// because a named train ends there and everything after it is the
        /// stock. Bounded to a short tail so that a service whose name simply
        /// contains 号 cannot lose half of itself.
        private static func bracketStart(
            in text: String
        ) -> (name: String.Index, body: String.Index)? {
            if let open = text.firstIndex(of: "("), open != text.startIndex {
                return (open, text.index(after: open))
            }
            guard let mark = text.firstIndex(of: "号"), mark != text.startIndex else { return nil }
            let after = text.index(after: mark)
            let tail = text[after...]
            guard !tail.isEmpty, tail.count <= 8 else { return nil }
            return (after, after)
        }

        /// Folds a 乗換不要 block into the leg it continues.
        ///
        /// The first block's train is the one that was boarded, so its
        /// service, platform and rolling stock all stay; what the second adds
        /// is the line it changes onto and the stations it counts. The
        /// destination moves too — 直江津行 written at 犀潟 is where this ride
        /// actually ends.
        mutating func `continue`(with other: LegHeader) {
            for name in other.serviceNames where !name.isEmpty {
                guard !Self.sameService(name, service),
                    !throughServices.contains(where: { Self.sameService(name, $0) })
                else { continue }
                throughServices.append(name)
            }
            destination = other.destination ?? destination
            arrivalPlatform = other.arrivalPlatform ?? arrivalPlatform
            carCount = carCount ?? other.carCount
            let fares = [fareYen, other.fareYen].compactMap { $0 }
            fareYen = fares.max()
            // Yahoo counts each block separately, so the leg's own count is
            // their sum. Left as whichever exists when only one block said.
            if let mine = declaredStationCount, let theirs = other.declaredStationCount {
                declaredStationCount = mine + theirs
            } else {
                declaredStationCount = declaredStationCount ?? other.declaredStationCount
            }
            for note in other.notes where !notes.contains(note) { notes.append(note) }
        }

        var serviceNames: [String] { ([service] + throughServices).filter { !$0.isEmpty } }

        /// Whether two service rows name the same train.
        ///
        /// Compared without the bracketed rolling stock, because that is
        /// exactly the part a recogniser gets wrong: `のぞみ57号(N700A)` came
        /// back once as itself and once as `のぞみ57号(ND9OA)`, and treating
        /// the second as a further line turned one Shinkansen into a 直通
        /// service that changes trains at its own departure platform.
        static func sameService(_ a: String, _ b: String) -> Bool {
            func stem(_ text: String) -> String {
                guard let bracket = text.firstIndex(of: "("), bracket != text.startIndex else {
                    return Text.matchKey(text)
                }
                return Text.matchKey(String(text[text.startIndex..<bracket]))
            }
            let left = stem(a)
            let right = stem(b)
            return !left.isEmpty && left == right
        }

        /// Everything a block's further rows can add. Called for the row that
        /// opened the block too, so `13駅 ＪＲ特急北斗８号 24,640円` on one row
        /// and the same three facts on three rows read identically.
        mutating func absorb(_ row: Row) {
            // The platform, from the ROW rather than from any one line of it.
            // 発, 8 and 番線 are three separate boxes in the interface, so no
            // single line of this row carries the whole `発 8番線`.
            var text = row.text
            for _ in 0..<2 {
                guard let taken = Scan.takePlatform(text) else { break }
                if case .platform(let marker, let number) = taken.token {
                    switch marker {
                    case .departure: departurePlatform = departurePlatform ?? number
                    case .arrival: arrivalPlatform = arrivalPlatform ?? number
                    }
                }
                text = taken.remainder
            }

            for line in row.lines {
                if absorbServiceContinuation(line) { continue }
                for token in Token.read(line.text) { absorbToken(token, from: line) }
            }
        }

        /// Whether this line is the rest of the service name above it.
        ///
        /// Guarded three ways, because the row under a service is usually 当駅
        /// 始発 rather than a continuation: it has to start at the same x, sit
        /// within a QUARTER of a line of the bottom of the service, and
        /// tokenise to nothing but a name or a line.
        ///
        /// The quarter is what separates the two cases, and it was measured
        /// rather than chosen. On real captures a wrapped service sits 4 to 5
        /// points below its first line; the next row of the block — 当駅始発,
        /// or the second line of a 直通 service, which is NOT a continuation —
        /// sits at least ten. Anything that reads as a note, a destination or
        /// a platform is itself whatever the gap says.
        private mutating func absorbServiceContinuation(_ line: TextLine) -> Bool {
            guard let anchor = serviceBox, !service.isEmpty,
                abs(line.box.minX - anchor.minX) <= 10,
                line.box.minY >= anchor.minY,
                line.box.minY - anchor.maxY <= anchor.height * 0.25
            else { return false }
            let tokens = Token.read(line.text)
            guard tokens.count == 1 else { return false }
            let tail: String
            switch tokens[0] {
            case .name(let text), .service(let text, _): tail = text
            default: return false
            }
            service += tail
            serviceBox = Box(
                x: anchor.minX, y: anchor.minY,
                width: max(anchor.width, line.box.maxX - anchor.minX),
                height: line.box.maxY - anchor.minY)
            return true
        }

        mutating func absorbToken(_ token: Token, from line: TextLine) {
            switch token {
            case .service(let text, let serviceKind):
                let parts = Self.split(service: text)
                if let bound = parts.destination { destination = destination ?? bound }
                if service.isEmpty {
                    service = parts.name
                    kind = serviceKind
                    equipment = equipment ?? parts.equipment
                    serviceBox = line.box
                } else if !Self.sameService(parts.name, service),
                    !throughServices.contains(where: { Self.sameService(parts.name, $0) })
                {
                    throughServices.append(parts.name)
                }
            case .destination(let text): destination = destination ?? text
            case .platform(.departure, let number):
                departurePlatform = departurePlatform ?? number
            case .platform(.arrival, let number):
                arrivalPlatform = arrivalPlatform ?? number
            case .cars(let count): carCount = carCount ?? count
            case .stationCount(let count):
                declaredStationCount = declaredStationCount ?? count
            // The largest number in the block is the through fare; the
            // 指定席 surcharge beside it is smaller. Taking the maximum
            // avoids having to know which box Vision read first.
            case .fare(let yen): fareYen = max(fareYen ?? 0, yen)
            case .note(let text):
                if text.contains("当駅始発") { startsHere = true }
                if !notes.contains(text) { notes.append(text) }
            case .name(let text):
                // `8` and `番線` are the platform, already taken from the
                // row. Repeating them as notes would put "8 · 番線" under
                // the service name of every leg.
                guard text != "番線", !text.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                    return
                }
                if !notes.contains(text) { notes.append(text) }
            default: return
            }
        }
    }

    /// Turns a block's drafts into a leg, deciding arrival from departure with
    /// the whole leg in view.
    static func resolve(header: LegHeader, drafts: [CallDraft]) -> Leg {
        // Split here rather than where the service was first read: a long
        // service arrives in two pieces — `ＪＲ新幹線はやぶ` and `さ28号(E5系)`
        // — and the bracket only exists once they are back together.
        let named = LegHeader.split(service: header.service)
        var leg = Leg(
            kind: header.kind,
            service: named.name,
            throughServices: header.throughServices,
            destination: header.destination ?? named.destination,
            equipment: header.equipment ?? named.equipment,
            startsHere: header.startsHere,
            departurePlatform: header.departurePlatform,
            arrivalPlatform: header.arrivalPlatform,
            carCount: header.carCount,
            declaredStationCount: header.declaredStationCount,
            fareYen: header.fareYen,
            notes: header.notes)

        var minutes: [(arrival: Int?, departure: Int?)] = []
        for (index, draft) in drafts.enumerated() {
            let isFirst = index == 0
            let isLast = index == drafts.count - 1
            var arrival: Int?
            var departure: Int?
            var unmarked: [Int] = []
            for time in draft.times {
                switch time.marker {
                case .arrival: arrival = arrival ?? time.minutes
                case .departure: departure = departure ?? time.minutes
                case nil: unmarked.append(time.minutes)
                }
            }
            if unmarked.count >= 2 {
                // Two bare times against one name is the transfer layout with
                // the 着/発 badges unread: the earlier one is the arrival.
                let sorted = unmarked.sorted()
                arrival = arrival ?? sorted[0]
                departure = departure ?? sorted[1]
            } else if let only = unmarked.first {
                if isLast, !isFirst {
                    arrival = arrival ?? only
                } else {
                    departure = departure ?? only
                }
            }
            // A leg's origin needs a departure and its destination needs an
            // arrival; where the screenshot printed only the other one, the
            // same minute is the honest answer — the train did not wait.
            if isFirst, departure == nil { departure = arrival }
            if isLast, !isFirst, arrival == nil { arrival = departure }
            // A boundary station carries one time for each of the two legs it
            // belongs to. `14:18着 / 14:39発` at 新函館北斗 means the 北斗 got
            // in at 14:18 and the はやぶさ left at 14:39 — so the leg that ends
            // here keeps only the arrival, and the leg that starts here keeps
            // only the departure. Leaving both on both would have the 北斗
            // departing a station it terminated at.
            if drafts.count > 1 {
                if isFirst { arrival = nil }
                if isLast { departure = nil }
            }
            minutes.append((arrival, departure))
        }

        minutes = rollOverMidnight(minutes)
        leg.calls = zip(drafts, minutes).map { draft, time in
            Call(
                name: draft.name, qualifier: draft.qualifier, rawName: draft.raw,
                arrival: time.arrival.map(Clock.text),
                departure: time.departure.map(Clock.text))
        }
        return leg
    }

    /// jsonspec §10.5: a journey that runs past midnight spells the next day
    /// `24:09`, not `00:09`.
    ///
    /// Only a jump backwards of more than twelve hours rolls the day over. A
    /// single misread digit — 18:59 read as 17:59 — steps backwards by an
    /// hour, and treating that as midnight would push every later call of the
    /// journey into tomorrow. It is left alone here and reported by
    /// ``review(_:)`` instead: a wrong time the reader can see beside a
    /// station name is repairable, and a silently shifted day is not.
    static func rollOverMidnight(
        _ times: [(arrival: Int?, departure: Int?)]
    ) -> [(arrival: Int?, departure: Int?)] {
        var out = times
        var previous: Int?
        var offset = 0
        func advance(_ raw: Int) -> Int {
            var value = raw + offset
            if let last = previous, last - value > 12 * 60 {
                offset += 24 * 60
                value += 24 * 60
            }
            previous = value
            return value
        }
        for index in out.indices {
            if let arrival = out[index].arrival { out[index].arrival = advance(arrival) }
            if let departure = out[index].departure { out[index].departure = advance(departure) }
        }
        return out
    }

    // MARK: - review

    static func review(_ route: Route) -> [Note] {
        var notes: [Note] = []
        if !route.header.hasContent { notes.append(Note(kind: .noHeader)) }
        if route.legs.isEmpty {
            notes.append(Note(kind: .noLegs))
            return notes
        }
        for leg in route.legs {
            if leg.kind != .train {
                notes.append(Note(kind: .legNotRidden, subject: leg.service))
                continue
            }
            if leg.calls.count < 2 {
                notes.append(Note(kind: .shortLeg, subject: leg.service))
                continue
            }
            // Yahoo counts the intervals in the circle, not the stations, so
            // both readings of `13駅` are accepted before anything is said.
            if let declared = leg.declaredStationCount,
                declared != leg.calls.count, declared != leg.calls.count - 1
            {
                notes.append(
                    Note(kind: .stationCountDisagrees, subject: "\(leg.service) \(declared)"))
            }
            var previous: Int?
            var crossed = false
            for call in leg.calls {
                for text in [call.arrival, call.departure] {
                    guard let text, let minutes = Clock.minutes(text) else { continue }
                    if minutes >= 24 * 60 { crossed = true }
                    if let last = previous, minutes < last {
                        notes.append(
                            Note(kind: .timeWentBackwards, subject: "\(call.name) \(text)"))
                    }
                    previous = minutes
                }
            }
            if crossed { notes.append(Note(kind: .crossedMidnight, subject: leg.service)) }
        }
        return notes
    }

    // MARK: - times

    public enum Clock {

        /// `"HH:MM"` for a minute count that may run past 24 hours.
        public static func text(_ minutes: Int) -> String {
            let clamped = max(0, minutes)
            return String(format: "%02d:%02d", clamped / 60, clamped % 60)
        }

        /// Minutes since the journey's own midnight, `25:10` included.
        public static func minutes(_ text: String) -> Int? {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
                hour >= 0, minute >= 0, minute < 60
            else { return nil }
            return hour * 60 + minute
        }
    }
}
