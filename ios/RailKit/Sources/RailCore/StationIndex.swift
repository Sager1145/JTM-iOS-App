import Foundation

// =========================================================================
//  StationIndex.swift — the rail package, as much of it as CHOOSING A
//  STATION needs.
//
//  **Not a port.** It is the half of the screenshot importer that is about
//  the RAIL DATA rather than about reading a picture: given `大宮`, which of
//  the ten thousand stations the Japanese package carries is that? The name
//  alone cannot answer it — 大宮 is a station in Saitama and another one in
//  Kyoto — so the answer comes from the sequence a journey makes, which is
//  what ``resolve(names:hints:index:)`` and ``fill(names:places:index:)`` are
//  between them.
//
//  It sits in its own file rather than inside ``TransferGuide`` because the
//  two are different subjects: one is a grammar for reading screenshots, and
//  Yahoo's and JR East's differ; this is the table both of them ask, and it
//  does not.
//
//  A value type rather than a protocol, so a test can build one out of six
//  stations, and so nothing in here can reach the app's network store. That
//  is the only reason any of it is testable.
//
//  The spelling rules it looks names up by live in ``TransferGuide/Text``.
//  They were written for a text recogniser and they are the same rules the
//  table needs: 大宮（埼玉県）, 東京駅 and ＪＲ難波 are the same three stations
//  whichever app printed them.
// =========================================================================

public struct StationIndex: Sendable {

    // MARK: - what a package row is

    /// One line at a station complex.
    public struct LineRef: Sendable, Hashable {
        public let name: String
        /// The package's `operator` field — `東日本旅客鉄道`, the official
        /// name, not the `JR東日本` a record carries.
        public let operatorName: String?
        public let colorHex: String?

        public init(name: String, operatorName: String? = nil, colorHex: String? = nil) {
            self.name = name
            self.operatorName = operatorName
            self.colorHex = colorHex
        }

        public var isShinkansen: Bool { name.contains("新幹線") }
        public var isJR: Bool { (operatorName ?? "").hasSuffix("旅客鉄道") }
    }

    /// One platform of one complex, as the package stores it.
    public struct Entry: Sendable {
        public let code: String
        public let name: String
        public let coordinate: Coordinate
        public let line: LineRef

        public init(code: String, name: String, coordinate: Coordinate, line: LineRef) {
            self.code = code
            self.name = name
            self.coordinate = coordinate
            self.line = line
        }
    }

    /// One complex — the thing a stop's `n02_station_code` names.
    public struct Place: Sendable, Hashable {
        public let code: String
        public let name: String
        public let coordinate: Coordinate
        public let lines: [LineRef]

        public var lineNames: [String] { lines.map(\.name) }
    }

    // MARK: - the indexes

    private let byKey: [String: [Place]]
    private let byCode: [String: Place]
    /// Every complex, in package order. Held so a hole in a chain can be
    /// filled by looking at what is actually THERE — see
    /// ``fill(names:places:index:)``.
    public let all: [Place]

    public var isEmpty: Bool { byCode.isEmpty }

    public init(_ entries: [Entry]) {
        var order: [String] = []
        var names: [String: String] = [:]
        var coordinates: [String: Coordinate] = [:]
        var lines: [String: [LineRef]] = [:]
        for entry in entries {
            if lines[entry.code] == nil {
                order.append(entry.code)
                names[entry.code] = entry.name
                coordinates[entry.code] = entry.coordinate
                lines[entry.code] = []
            }
            if !(lines[entry.code]?.contains(entry.line) ?? false) {
                lines[entry.code]?.append(entry.line)
            }
        }
        var places: [String: Place] = [:]
        var keyed: [String: [Place]] = [:]
        for code in order {
            guard let name = names[code], let coordinate = coordinates[code] else { continue }
            let place = Place(
                code: code, name: name, coordinate: coordinate, lines: lines[code] ?? [])
            places[code] = place
            keyed[TransferGuide.Text.matchKey(name), default: []].append(place)
        }
        byCode = places
        byKey = keyed
        all = order.compactMap { places[$0] }
    }

    /// Every complex spelled this way, in package order.
    public func places(named name: String) -> [Place] {
        byKey[TransferGuide.Text.matchKey(name)] ?? []
    }

    public func place(code: String) -> Place? { byCode[code] }

    // MARK: - choosing a station

    /// The cheapest chain of station codes through a sequence of names.
    ///
    /// A plain Viterbi over great-circle distance. Positions with no candidate
    /// at all break the chain rather than ending it: a station the package
    /// does not carry leaves a hole in the codes, and the stations after it
    /// are still worth resolving against each other.
    ///
    /// `hints` are the line names the leg claims, one list per position. A
    /// candidate that serves one of them is discounted by ``hintBonusMeters``
    /// — enough to settle a tie between two 大宮 twelve kilometres apart, and
    /// nowhere near enough to pull the chain across the country.
    public static func resolve(
        names: [String], hints: [[String]], index: StationIndex
    ) -> [Place?] {
        let candidates = names.map { index.places(named: $0) }
        var chosen = [Place?](repeating: nil, count: names.count)

        var start = 0
        while start < candidates.count {
            guard !candidates[start].isEmpty else {
                start += 1
                continue
            }
            var end = start
            while end + 1 < candidates.count, !candidates[end + 1].isEmpty { end += 1 }
            for (offset, place) in chain(
                candidates: Array(candidates[start...end]),
                hints: Array(hints[start...end])
            ).enumerated() {
                chosen[start + offset] = place
            }
            start = end + 1
        }
        return chosen
    }

    /// How much a line hint is worth, in metres of detour.
    static let hintBonusMeters = 30_000.0

    private static func chain(candidates: [[Place]], hints: [[String]]) -> [Place?] {
        guard let first = candidates.first else { return [] }
        var costs = first.map { place in -hintScore(place, hints: hints[0]) }
        var back = [[Int]](repeating: [], count: candidates.count)

        for position in 1..<candidates.count {
            let row = candidates[position]
            var next = [Double](repeating: .greatestFiniteMagnitude, count: row.count)
            var pointers = [Int](repeating: 0, count: row.count)
            for (index, place) in row.enumerated() {
                for (previous, cost) in costs.enumerated() {
                    let step =
                        cost
                        + Geometry.distanceMeters(
                            candidates[position - 1][previous].coordinate, place.coordinate)
                    if step < next[index] {
                        next[index] = step
                        pointers[index] = previous
                    }
                }
                next[index] -= hintScore(place, hints: hints[position])
            }
            costs = next
            back[position] = pointers
        }

        var picked = [Place?](repeating: nil, count: candidates.count)
        guard var cursor = costs.indices.min(by: { costs[$0] < costs[$1] }) else { return picked }
        for position in stride(from: candidates.count - 1, through: 0, by: -1) {
            picked[position] = candidates[position][cursor]
            if position > 0 { cursor = back[position][cursor] }
        }
        return picked
    }

    private static func hintScore(_ place: Place, hints: [String]) -> Double {
        guard !hints.isEmpty else { return 0 }
        let serves = place.lines.contains { line in
            hints.contains { matches(line: line.name, hint: $0) }
        }
        return serves ? hintBonusMeters : 0
    }

    /// Fills a hole the chain left, from the corridor its neighbours define.
    ///
    /// A station whose name came back damaged — 北本 read as `北`, 行田 as
    /// `行[` — resolves to nothing, and the two sections either side of it
    /// then lose their endpoints. But its POSITION is known within a few
    /// kilometres: it lies between the two stations that did resolve.
    ///
    /// So the corridor is the segment between them, and the only candidates
    /// considered are the stations that actually sit on it — projecting
    /// between the ends rather than merely near them, which is what keeps
    /// 北上尾 (behind 桶川) and 北鴻巣 (past 鴻巣) out of a search for a station
    /// between the two. A candidate must also share a name stem with what was
    /// read, and it must be the ONLY one that does. 浦和 read as `申木` shares
    /// nothing with anything and stays unresolved, which is the honest answer:
    /// the preview names it and the editor can fix it.
    static func fill(
        names: [String], places: inout [Place?], index: StationIndex
    ) {
        for position in places.indices where places[position] == nil {
            guard let before = places[..<position].last(where: { $0 != nil }) ?? nil,
                let after = places[(position + 1)...].first(where: { $0 != nil }) ?? nil,
                let stem = TransferGuide.Text.letters(TransferGuide.Text.matchKey(names[position])), !stem.isEmpty
            else { continue }

            let corridor = Corridor(from: before.coordinate, to: after.coordinate)
            guard corridor.isMeasurable else { continue }
            var found: Place?
            var ambiguous = false
            for candidate in index.all {
                guard corridor.contains(candidate.coordinate) else { continue }
                guard
                    let other = TransferGuide.Text.letters(
                        TransferGuide.Text.matchKey(candidate.name)), !other.isEmpty,
                    resembles(stem, other)
                else { continue }
                if found != nil, found?.code != candidate.code {
                    ambiguous = true
                    break
                }
                found = candidate
            }
            if !ambiguous, let found { places[position] = found }
        }
    }

    /// Whether a damaged reading and a real name are the same station.
    ///
    /// Only ever asked inside a corridor that already narrows the answer to
    /// the stations physically between two known ones, so it can afford to be
    /// generous — and it has to be, because the damage is not always at the
    /// end. 津ノ井 came back as `津ノ丼` and 東郡家 as `東部家`: one is a
    /// prefix away and the other is one character wrong in the middle.
    ///
    /// Two ways to be the same name, then. Either one starts the other — 北
    /// for 北本, 行 for 行田 — or they are the same length and agree on at
    /// least half their characters, which is a misread rather than a
    /// different word.
    static func resembles(_ read: String, _ candidate: String) -> Bool {
        guard read.count >= 1, candidate.count >= 1 else { return false }
        if read.hasPrefix(candidate) || candidate.hasPrefix(read) { return true }
        guard read.count == candidate.count, read.count >= 2 else { return false }
        let agreed = zip(read, candidate).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }
        return agreed * 2 >= read.count
    }

    /// The stretch of track between two stations, as a rectangle around it.
    ///
    /// Equirectangular around the midpoint: over the tens of kilometres
    /// between two adjacent stops the error is metres, and the alternative —
    /// a great-circle cross-track distance — is a different formula for the
    /// same answer.
    struct Corridor {
        private let originLon: Double
        private let originLat: Double
        private let scaleX: Double
        private let end: (x: Double, y: Double)
        private let lengthSquared: Double

        /// How far off the straight line a station may sit and still be on it.
        /// A railway between two stops is not a ruled line; three kilometres
        /// covers the curve without reaching the next valley.
        static let widthMeters = 3_000.0

        init(from: Coordinate, to: Coordinate) {
            originLon = from.lon
            originLat = from.lat
            scaleX = cos(from.lat * .pi / 180) * 111_320
            end = ((to.lon - from.lon) * scaleX, (to.lat - from.lat) * 110_540)
            lengthSquared = end.x * end.x + end.y * end.y
        }

        var isMeasurable: Bool { lengthSquared > 1 }

        func contains(_ point: Coordinate) -> Bool {
            let x = (point.lon - originLon) * scaleX
            let y = (point.lat - originLat) * 110_540
            let along = (x * end.x + y * end.y) / lengthSquared
            // Strictly between: an endpoint is already resolved, and its
            // neighbour on the far side is not on this stretch.
            guard along > 0.02, along < 0.98 else { return false }
            let offX = x - along * end.x
            let offY = y - along * end.y
            return offX * offX + offY * offY <= Self.widthMeters * Self.widthMeters
        }
    }

    /// Whether a package line and a screenshot's line name are the same line.
    ///
    /// Containment in either direction, because the two spellings disagree
    /// predictably and in both directions: Yahoo writes `JR高崎線` where the
    /// package writes `高崎線`, and `ＪＲ上野東京ライン` where the package has
    /// no such line at all but does have the `東北本線` it runs over.
    static func matches(line: String, hint: String) -> Bool {
        let a = TransferGuide.Text.matchKey(line)
        let b = TransferGuide.Text.matchKey(hint)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.contains(b) || b.contains(a)
    }

    /// The line names a leg claims, as a package might spell them.
    ///
    /// `JR` is stripped because no package line carries it — the operator does
    /// — and a named express (`JR特急北斗8号`) yields nothing at all, which is
    /// correct: 北斗 is a train, not a line, and pretending otherwise would
    /// constrain the solver to a line that does not exist.
    static func sharedLines(
        from: Place?, to: Place?, shinkansen: Bool, hints: [String]
    ) -> [LineRef] {
        guard let from, let to else { return [] }
        let toNames = Set(to.lines.map(\.name))
        var shared = from.lines.filter { toNames.contains($0.name) }
        let sameKind = shared.filter { $0.isShinkansen == shinkansen }
        if !sameKind.isEmpty { shared = sameKind }
        let hinted = shared.filter { line in hints.contains { matches(line: line.name, hint: $0) } }
        return hinted.isEmpty ? shared : hinted
    }

    /// N02_002 事業者種別: 1 JR 新幹線, 2 JR 在来線, 3 公営, 4 民営, 5 三セク.
    ///
    /// Named only where the leg says something definite. A private railway
    /// leaves this at the default five rather than guessing between 民営 and
    /// 第三セクター, which is a distinction a screenshot never states.
    static func institutionCodes(shinkansen: Bool, isJR: Bool) -> [String] {
        if shinkansen { return ["1"] }
        if isJR { return ["2"] }
        return TrainValidation.defaultAllowedInstitutionTypeCodes
    }
}
