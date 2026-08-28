import Foundation

/// The `compact-v1` rail package — the cross-language data contract.
///
/// `app/public/rail/*-2025.json` is read unchanged by both implementations
/// (REFACTOR_FOR_SWIFT_FORK_PROMPT.md §三 contract 7), so this decoder is
/// written against the shipped files rather than against a Swift-shaped
/// re-export of them. Renaming a field here is not a refactor; it is a
/// breaking change to a format the web app, the Node build scripts and this
/// app all depend on.
///
/// The rows are positional arrays rather than objects because the format is
/// built for size — a national package is 17 MB even so.
public struct CompactPackage: Sendable {
    public let format: String
    public let version: String
    public let country: String
    public let lines: [Line]

    public struct Line: Sendable {
        public let id: String
        public let name: String
        public let nameRoma: String?
        public let `operator`: String?
        /// Drives the zoom at which the line first appears; lower is more
        /// important. The web app's `minZoomForRank` consumes it.
        public let rank: Int
        /// Official line colour, light theme. `colorDark` is the dark-theme
        /// substitute where an operator publishes one.
        public let color: String?
        public let colorDark: String?
        /// The package's `logo` flag — `1` where artwork for this railway was
        /// downloaded into `app/public/rail/logos`, absent where it was not.
        ///
        /// It is stored as a flag rather than a path because the path is
        /// derivable and the flag is not: `rail-network.js` turns it into
        /// `/rail/logos/<id>.png`, and `StationDisplay.Network` does the same.
        /// Decoding it here is what lets a caller build that set from the
        /// package itself instead of being handed one — which is how the whole
        /// shipped badge set came to be unused on iOS: the only caller that
        /// ever passed the set was a test.
        public let hasLogo: Bool
        /// The passenger-facing route letter — `G` for 銀座線, `A` for 浅草線.
        ///
        /// Not drawn anywhere yet. It is decoded because it is the package's
        /// own answer to "which route symbol is this", and the badge files are
        /// named after the railway rather than the code, so anything that has
        /// to reason about the two together needs both.
        public let lineCode: String?
        /// The railway's name without the administrative prefix the id keeps —
        /// `銀座線` for `3号線銀座線`, `御堂筋線` for `1号線(御堂筋線)`.
        ///
        /// Every line carries one and 32 of Japan's 652 differ from `name`.
        /// They are the subways, which is exactly the set an itinerary is
        /// likely to name the short way, so this is what lets a recorded ride
        /// find the package line that owns the route symbol.
        public let nameNorm: String?
        public let stations: [Station]
        public let segments: [Segment]
    }

    /// `[id, name, lon, lat, nameRoma, group]`.
    public struct Station: Sendable {
        public let id: String
        public let name: String
        public let coordinate: Coordinate
        public let nameRoma: String?
    }

    /// `[distanceKm, continuesFromPrevious, coordinates]`.
    ///
    /// `continuesFromPrevious` is the seam flag: when set, the interval's
    /// drawn geometry begins at the *previous* interval's last coordinate,
    /// which is how a chain of intervals is stored without repeating the
    /// shared vertex in every row.
    public struct Segment: Sendable {
        public let distanceKm: Double
        public let continuesFromPrevious: Bool
        public let coordinates: [Coordinate]
    }
}

extension CompactPackage: Decodable {
    enum CodingKeys: String, CodingKey {
        case format, version, country, lines
    }
}

extension CompactPackage.Line: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, name, nameRoma, `operator`, rank, color, colorDark, logo, lineCode
        case nameNorm, stations, segments
    }

    /// Written out rather than synthesised for one field: `logo` is stored as
    /// the number `1`, and JSON `1` is not a JSON boolean — a synthesised
    /// `Bool` decode would throw on every line that has artwork. The web app
    /// reads it as `compactLine.logo ? … : null`, so anything truthy counts.
    public init(from decoder: Decoder) throws {
        let row = try decoder.container(keyedBy: CodingKeys.self)
        id = try row.decode(String.self, forKey: .id)
        name = try row.decode(String.self, forKey: .name)
        nameRoma = try row.decodeIfPresent(String.self, forKey: .nameRoma)
        `operator` = try row.decodeIfPresent(String.self, forKey: .operator)
        rank = try row.decode(Int.self, forKey: .rank)
        color = try row.decodeIfPresent(String.self, forKey: .color)
        colorDark = try row.decodeIfPresent(String.self, forKey: .colorDark)
        hasLogo = (try row.decodeIfPresent(Int.self, forKey: .logo) ?? 0) != 0
        lineCode = try row.decodeIfPresent(String.self, forKey: .lineCode)
        nameNorm = try row.decodeIfPresent(String.self, forKey: .nameNorm)
        stations = try row.decode([CompactPackage.Station].self, forKey: .stations)
        segments = try row.decode([CompactPackage.Segment].self, forKey: .segments)
    }
}

extension CompactPackage.Station: Decodable {
    public init(from decoder: Decoder) throws {
        var row = try decoder.unkeyedContainer()
        id = try row.decode(String.self)
        name = try row.decode(String.self)
        let lon = try row.decode(Double.self)
        let lat = try row.decode(Double.self)
        coordinate = Coordinate(lon: lon, lat: lat)
        // Trailing members are optional across packages and countries: Macao
        // carries a romanisation and a group index, some rows carry neither.
        nameRoma = row.isAtEnd ? nil : try? row.decode(String.self)
    }
}

extension CompactPackage.Segment: Decodable {
    public init(from decoder: Decoder) throws {
        var row = try decoder.unkeyedContainer()
        distanceKm = try row.decode(Double.self)
        // Stored as 0/1. Decoded through Int rather than Bool because JSON
        // `0` is not a JSON boolean and a strict decoder will refuse it.
        continuesFromPrevious = (try row.decode(Int.self)) != 0
        coordinates = (try row.decode([[Double]].self)).compactMap(Coordinate.init(pair:))
    }
}

extension CompactPackage {

    /// Decodes one line's station-to-station intervals — the geometry the map
    /// actually draws, one polyline per interval.
    ///
    /// Ported from `rail-network.js` `decodeIntervals`, and there are three
    /// rules in those nineteen lines that a plausible-looking port gets wrong:
    ///
    ///   1. **The seam.** A row flagged `continuesFromPrevious` is prefixed
    ///      with the previous interval's last coordinate. Without it every
    ///      interval boundary is a visible gap.
    ///   2. **The station table wins.** Both endpoints are then *overwritten*
    ///      by the authoritative station anchors. Survey geometry frequently
    ///      stops a few metres short of the platform it serves, and the app's
    ///      rule is that the line passes through the station dot, never near
    ///      it — so geometry loses to the station table, not the reverse.
    ///   3. **Loops close.** The end station index wraps modulo the station
    ///      count, so a circular line's last interval returns to station 0
    ///      rather than running off the end of the table.
    public static func decodeIntervals(_ line: Line) -> [[Coordinate]] {
        let stationCount = line.stations.count
        guard stationCount > 0 else { return [] }

        var intervals: [[Coordinate]] = []
        var previousLast: Coordinate?

        for (index, row) in line.segments.enumerated() {
            var decoded: [Coordinate] = []
            if row.continuesFromPrevious {
                // Matches the JavaScript exactly, including its first-row
                // behaviour: `[previousLastCoordinate].concat(...)` on row 0
                // prepends `null`, which the endpoint overwrite immediately
                // replaces. Reproduced by prepending a placeholder so the
                // resulting vertex COUNT is the same — a port that skips the
                // prepend produces a polyline one vertex shorter.
                decoded.append(previousLast ?? row.coordinates.first ?? Coordinate(lon: 0, lat: 0))
                decoded.append(contentsOf: row.coordinates)
            } else {
                decoded = row.coordinates
            }
            guard !decoded.isEmpty else {
                intervals.append([])
                continue
            }

            let start = line.stations[index % stationCount]
            let end = line.stations[(index + 1) % stationCount]
            decoded[0] = start.coordinate
            decoded[decoded.count - 1] = end.coordinate

            previousLast = decoded[decoded.count - 1]
            intervals.append(decoded)
        }

        return intervals
    }

    public static func load(contentsOf url: URL) throws -> CompactPackage {
        try JSONDecoder().decode(CompactPackage.self, from: Data(contentsOf: url))
    }
}
