import Foundation

/// The exact geographic scope of one area capture or repair.
///
/// JSON is strict and flat; unknown keys are rejected:
/// `{"kind":"rect","minLon":..,"minLat":..,"maxLon":..,"maxLat":..,"marginMetres":500}`,
/// `{"kind":"stationPair","lineID":..,"fromStationID":..,"toStationID":..}`,
/// `{"kind":"lineSection","lineID":..,"firstInterval":..,"lastInterval":..}`,
/// `{"kind":"centre","lon":..,"lat":..,"radiusMetres":..}`. `marginMetres` is
/// optional on every kind (default 500).
public struct AreaSelection: Codable, Equatable, Sendable {
    public enum Mode: Codable, Equatable, Sendable {
        case rect(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double)
        case stationPair(lineID: String, fromStationID: String, toStationID: String)
        case lineSection(lineID: String, firstInterval: Int, lastInterval: Int)
        case centre(lon: Double, lat: Double, radiusMetres: Double)

        public var kind: String {
            switch self {
            case .rect: "rect"
            case .stationPair: "stationPair"
            case .lineSection: "lineSection"
            case .centre: "centre"
            }
        }

        // Mode is always coded inline through AreaSelection; these keep the
        // standalone Codable conformance consistent with the flat form.
        public init(from decoder: Decoder) throws { self = try AreaSelection(from: decoder).mode }
        public func encode(to encoder: Encoder) throws { try AreaSelection(mode: self).encode(to: encoder) }
    }

    public static let defaultMarginMetres = 500.0
    public static let maximumRadiusMetres = 20_000.0
    public static let maximumMarginMetres = 5_000.0

    public var mode: Mode
    public var marginMetres: Double

    public init(mode: Mode, marginMetres: Double = AreaSelection.defaultMarginMetres) {
        self.mode = mode
        self.marginMetres = marginMetres
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, marginMetres
        case minLon, minLat, maxLon, maxLat
        case lineID, fromStationID, toStationID
        case firstInterval, lastInterval
        case lon, lat, radiusMetres
    }
    private struct InputKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    private static func keys(for kind: String) -> Set<CodingKeys>? {
        switch kind {
        case "rect": [.minLon, .minLat, .maxLon, .maxLat]
        case "stationPair": [.lineID, .fromStationID, .toStationID]
        case "lineSection": [.lineID, .firstInterval, .lastInterval]
        case "centre": [.lon, .lat, .radiusMetres]
        default: nil
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(String.self, forKey: .kind)
        guard let required = Self.keys(for: kind) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: values,
                debugDescription: "Unknown area kind \(kind); expected rect, stationPair, lineSection or centre.")
        }
        let raw = try decoder.container(keyedBy: InputKey.self)
        let allowed = Set((required.union([.kind, .marginMetres])).map(\.rawValue))
        let unknown = raw.allKeys.map(\.stringValue).filter { !allowed.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unsupported \(kind) area fields: \(unknown.joined(separator: ", "))."))
        }
        let mode: Mode
        switch kind {
        case "rect":
            mode = .rect(minLon: try values.decode(Double.self, forKey: .minLon),
                         minLat: try values.decode(Double.self, forKey: .minLat),
                         maxLon: try values.decode(Double.self, forKey: .maxLon),
                         maxLat: try values.decode(Double.self, forKey: .maxLat))
        case "stationPair":
            mode = .stationPair(lineID: try values.decode(String.self, forKey: .lineID),
                                fromStationID: try values.decode(String.self, forKey: .fromStationID),
                                toStationID: try values.decode(String.self, forKey: .toStationID))
        case "lineSection":
            mode = .lineSection(lineID: try values.decode(String.self, forKey: .lineID),
                                firstInterval: try values.decode(Int.self, forKey: .firstInterval),
                                lastInterval: try values.decode(Int.self, forKey: .lastInterval))
        default:
            mode = .centre(lon: try values.decode(Double.self, forKey: .lon),
                           lat: try values.decode(Double.self, forKey: .lat),
                           radiusMetres: try values.decode(Double.self, forKey: .radiusMetres))
        }
        self.init(mode: mode, marginMetres: try values.decodeIfPresent(Double.self, forKey: .marginMetres) ?? Self.defaultMarginMetres)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(mode.kind, forKey: .kind)
        switch mode {
        case let .rect(minLon, minLat, maxLon, maxLat):
            try values.encode(minLon, forKey: .minLon); try values.encode(minLat, forKey: .minLat)
            try values.encode(maxLon, forKey: .maxLon); try values.encode(maxLat, forKey: .maxLat)
        case let .stationPair(lineID, from, to):
            try values.encode(lineID, forKey: .lineID)
            try values.encode(from, forKey: .fromStationID); try values.encode(to, forKey: .toStationID)
        case let .lineSection(lineID, first, last):
            try values.encode(lineID, forKey: .lineID)
            try values.encode(first, forKey: .firstInterval); try values.encode(last, forKey: .lastInterval)
        case let .centre(lon, lat, radius):
            try values.encode(lon, forKey: .lon); try values.encode(lat, forKey: .lat)
            try values.encode(radius, forKey: .radiusMetres)
        }
        try values.encode(marginMetres, forKey: .marginMetres)
    }

    /// Rejects non-finite or out-of-range coordinates, empty boxes, radius
    /// outside (0, 20 000] m, margin outside 0...5 000 m, reversed or negative
    /// interval ranges and empty identifiers. Line/station existence is
    /// checked later against the loaded data, never here.
    public func validate() throws {
        func fail(_ reason: String) -> DiagnosticError { .invalidRequest("Area selection: \(reason)") }
        guard marginMetres.isFinite, (0...Self.maximumMarginMetres).contains(marginMetres) else {
            throw fail("margin must be finite and within 0...\(Int(Self.maximumMarginMetres)) m.")
        }
        func validLon(_ v: Double) -> Bool { v.isFinite && (-180...180).contains(v) }
        func validLat(_ v: Double) -> Bool { v.isFinite && (-90...90).contains(v) }
        func nonEmpty(_ s: String) -> Bool { !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch mode {
        case let .rect(minLon, minLat, maxLon, maxLat):
            guard validLon(minLon), validLon(maxLon), validLat(minLat), validLat(maxLat) else {
                throw fail("rect coordinates must be finite longitude/latitude values.")
            }
            guard minLon < maxLon, minLat < maxLat else { throw fail("rect requires minLon < maxLon and minLat < maxLat.") }
        case let .stationPair(lineID, from, to):
            guard nonEmpty(lineID), nonEmpty(from), nonEmpty(to) else { throw fail("station pair needs a line ID and two station IDs.") }
            guard from != to else { throw fail("station pair needs two different stations.") }
        case let .lineSection(lineID, first, last):
            guard nonEmpty(lineID) else { throw fail("line section needs a line ID.") }
            guard first >= 0, first <= last else { throw fail("line section needs 0 <= firstInterval <= lastInterval.") }
        case let .centre(lon, lat, radius):
            guard validLon(lon), validLat(lat) else { throw fail("centre must be a finite longitude/latitude.") }
            guard radius.isFinite, radius > 0, radius <= Self.maximumRadiusMetres else {
                throw fail("radius must be within (0, \(Int(Self.maximumRadiusMetres))] m.")
            }
        }
    }

    /// Parses the CLI shorthand:
    /// `stations:LINE:FROM-TO`, `line:LINE:FIRST-LAST`,
    /// `rect:minLon,minLat,maxLon,maxLat`, `centre:lon,lat,radius`, each
    /// optionally followed by `@margin` (metres). The result is validated.
    public static func parse(shorthand: String) throws -> AreaSelection {
        var text = shorthand.trimmingCharacters(in: .whitespacesAndNewlines)
        var margin = defaultMarginMetres
        if let at = text.lastIndex(of: "@") {
            guard let value = Double(text[text.index(after: at)...]) else {
                throw DiagnosticError.invalidRequest("Area shorthand: margin after @ must be a number.")
            }
            margin = value
            text = String(text[..<at])
        }
        guard let colon = text.firstIndex(of: ":") else {
            throw DiagnosticError.invalidRequest("Area shorthand must start with stations:, line:, rect: or centre:.")
        }
        let kind = text[..<colon], body = String(text[text.index(after: colon)...])
        func numbers(_ count: Int) throws -> [Double] {
            let parts = body.split(separator: ",", omittingEmptySubsequences: false).map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == count, parts.allSatisfy({ $0 != nil }) else {
                throw DiagnosticError.invalidRequest("Area shorthand \(kind): expected \(count) comma-separated numbers.")
            }
            return parts.map { $0! }
        }
        func lineAndRange() throws -> (String, String, String) {
            guard let split = body.lastIndex(of: ":") else {
                throw DiagnosticError.invalidRequest("Area shorthand \(kind): expected LINE:A-B.")
            }
            let line = String(body[..<split]), range = body[body.index(after: split)...]
            let ends = range.split(separator: "-", maxSplits: 1).map(String.init)
            guard ends.count == 2 else { throw DiagnosticError.invalidRequest("Area shorthand \(kind): expected A-B after the line ID.") }
            return (line, ends[0], ends[1])
        }
        let mode: Mode
        switch kind {
        case "stations":
            let (line, from, to) = try lineAndRange()
            mode = .stationPair(lineID: line, fromStationID: from, toStationID: to)
        case "line":
            let (line, first, last) = try lineAndRange()
            guard let a = Int(first), let b = Int(last) else {
                throw DiagnosticError.invalidRequest("Area shorthand line: interval indices must be integers.")
            }
            mode = .lineSection(lineID: line, firstInterval: a, lastInterval: b)
        case "rect":
            let v = try numbers(4)
            mode = .rect(minLon: v[0], minLat: v[1], maxLon: v[2], maxLat: v[3])
        case "centre", "center":
            let v = try numbers(3)
            mode = .centre(lon: v[0], lat: v[1], radiusMetres: v[2])
        default:
            throw DiagnosticError.invalidRequest("Area shorthand must start with stations:, line:, rect: or centre:.")
        }
        let selection = AreaSelection(mode: mode, marginMetres: margin)
        try selection.validate()
        return selection
    }
}
