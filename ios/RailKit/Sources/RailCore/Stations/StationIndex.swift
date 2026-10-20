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

    /// A legacy HK/MO code resolves through ``StationCodeAliases`` (ADR 0010).
    public func place(code: String) -> Place? {
        byCode[code] ?? byCode[StationCodeAliases.canonical(code)]
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
