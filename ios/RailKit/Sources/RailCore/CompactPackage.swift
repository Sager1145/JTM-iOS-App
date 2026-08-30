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
        /// Passenger-facing short operator name, when the source registry
        /// distinguishes it from the legal agency name.
        public let operatorShort: String?
        /// Audited operator/network artwork bundled under `rail/`.
        public let operatorLogo: String?
        /// Normalised service class produced by the North American builder
        /// (`metro`, `commuter`, `intercity`, `streetcar`, …).
        public let kind: String?
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
        /// Whether the railway closes on itself — 大阪環状線, Kaohsiung's
        /// circular LRT, Hong Kong's two light-rail loops, and the twenty-six
        /// North American streetcar and people-mover loops.
        ///
        /// Stored as `1` like ``hasLogo``, and decoded here for the same
        /// reason that one is: until it was, nothing on this side of the port
        /// could see it. `rail-network.js` has read `compactLine.isLoop` all
        /// along, so a loop drew one way on the web and another on the device
        /// — its first and last stations dressed as termini when a loop has
        /// none, and a hop across the seam sliced the long way round the
        /// circle. See ``RouteFeature/canonicalLineSlice(lineIndex:start:end:rawCoordinates:)``.
        public let isLoop: Bool
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
        case id, name, nameRoma, `operator`, operatorShort, operatorLogo, kind
        case rank, color, colorDark, logo, isLoop, lineCode
        case nameNorm, stations, segments
    }

    /// JavaScript's truthiness, for the flags the packages store as `1`.
    ///
    /// `logo` and `isLoop` are written by the builders as the number `1`, and
    /// JSON `1` is not a JSON boolean — a synthesised `Bool` decode throws on
    /// every line that carries one. The web app asks `compactLine.isLoop ? …`,
    /// which is true of the number and of the boolean alike, and the port
    /// fixtures exercise BOTH spellings: the shipped packages use `1` and the
    /// synthetic station-display cases use `true`. Accepting only one of them
    /// is how this decoder first went in and how it failed.
    private static func truthy(
        _ row: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) throws -> Bool {
        if let flag = try? row.decodeIfPresent(Bool.self, forKey: key) { return flag }
        return (try row.decodeIfPresent(Int.self, forKey: key) ?? 0) != 0
    }

    /// Written out rather than synthesised, for the two flags above.
    public init(from decoder: Decoder) throws {
        let row = try decoder.container(keyedBy: CodingKeys.self)
        id = try row.decode(String.self, forKey: .id)
        name = try row.decode(String.self, forKey: .name)
        nameRoma = try row.decodeIfPresent(String.self, forKey: .nameRoma)
        `operator` = try row.decodeIfPresent(String.self, forKey: .operator)
        operatorShort = try row.decodeIfPresent(String.self, forKey: .operatorShort)
        operatorLogo = try row.decodeIfPresent(String.self, forKey: .operatorLogo)
        kind = try row.decodeIfPresent(String.self, forKey: .kind)
        rank = try row.decode(Int.self, forKey: .rank)
        color = try row.decodeIfPresent(String.self, forKey: .color)
        colorDark = try row.decodeIfPresent(String.self, forKey: .colorDark)
        hasLogo = try Self.truthy(row, .logo)
        isLoop = try Self.truthy(row, .isLoop)
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

extension CompactPackage {

    /// A package's per-line ATTRIBUTES, without a single coordinate.
    ///
    /// The same idea, and for the same reason, as the iOS app's
    /// `DatasetPartIndex`: the geometry is nearly all of a package's bytes and
    /// there are questions about a package that need none of it. "Which mark
    /// does each railway wear?" is one — it reads six strings per line — and
    /// answering it through the full decoder materialises every station and
    /// every vertex of every interval so they can be thrown away.
    ///
    /// Measured over the shipped packages (`ios/tools/bench`, release, Apple
    /// silicon), full decode against this one:
    ///
    ///     ca  1.4 MB   30.3 ms →  3.7 ms
    ///     jp  9.1 MB  234.6 ms → 29.4 ms
    ///     us  6.5 MB  138.8 ms → 17.2 ms
    ///
    /// This is NOT a second way to read a package. It answers a strictly
    /// smaller question in one scan, and a caller that needs geometry still
    /// goes through `DisplayParts.LoadedPackage` and still reads the file
    /// once. What it removes is the case where a caller took the whole
    /// package *because that was the only decoder there was*.
    public struct Headers: Sendable, Decodable {
        public let lines: [Line]

        /// The fields that say what a railway IS, as opposed to where it runs.
        ///
        /// Deliberately a subset rather than `CompactPackage.Line` minus two
        /// fields: every member here is one this decoder can promise for every
        /// package, and adding a member is a decision to read it, not an
        /// accident of sharing a type with the geometry decoder.
        public struct Line: Sendable {
            public let id: String
            public let name: String
            public let nameRoma: String?
            public let `operator`: String?
            public let operatorShort: String?
            public let operatorLogo: String?
            public let kind: String?
            public let rank: Int
            public let color: String?
            public let colorDark: String?
            /// See ``CompactPackage/Line/hasLogo``.
            public let hasLogo: Bool
            /// See ``CompactPackage/Line/isLoop``.
            public let isLoop: Bool
            public let lineCode: String?
            /// See ``CompactPackage/Line/nameNorm``.
            public let nameNorm: String?

            public init(
                id: String, name: String, nameRoma: String? = nil,
                operator operatorName: String? = nil, operatorShort: String? = nil,
                operatorLogo: String? = nil, kind: String? = nil, rank: Int = 0,
                color: String? = nil, colorDark: String? = nil,
                hasLogo: Bool = false, isLoop: Bool = false,
                lineCode: String? = nil, nameNorm: String? = nil
            ) {
                self.id = id
                self.name = name
                self.nameRoma = nameRoma
                self.operator = operatorName
                self.operatorShort = operatorShort
                self.operatorLogo = operatorLogo
                self.kind = kind
                self.rank = rank
                self.color = color
                self.colorDark = colorDark
                self.hasLogo = hasLogo
                self.isLoop = isLoop
                self.lineCode = lineCode
                self.nameNorm = nameNorm
            }
        }

        public static func load(contentsOf url: URL) throws -> Headers {
            try JSONDecoder().decode(Headers.self, from: Data(contentsOf: url))
        }
    }

    /// The same projection, taken from a package that is already decoded.
    ///
    /// So that a caller holding a full package and a caller holding only the
    /// headers put the SAME values in front of whatever consumes them. Without
    /// it the two would be built by two pieces of code, and the parity tests
    /// — which decode the whole package — would be exercising a path the app
    /// no longer takes.
    public var headers: Headers {
        Headers(lines: lines.map(\.header))
    }
}

extension CompactPackage.Line {
    /// This line's attributes, without its geometry.
    public var header: CompactPackage.Headers.Line {
        CompactPackage.Headers.Line(
            id: id, name: name, nameRoma: nameRoma, operator: `operator`,
            operatorShort: operatorShort, operatorLogo: operatorLogo, kind: kind,
            rank: rank, color: color, colorDark: colorDark, hasLogo: hasLogo,
            isLoop: isLoop, lineCode: lineCode, nameNorm: nameNorm)
    }
}

extension CompactPackage.Headers {
    enum CodingKeys: String, CodingKey { case lines }
}

extension CompactPackage.Headers.Line: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, name, nameRoma, `operator`, operatorShort, operatorLogo, kind
        case rank, color, colorDark, logo, isLoop, lineCode, nameNorm
    }

    /// `logo` and `isLoop` are written as the number `1`. The rule is
    /// ``CompactPackage/Line/truthy(_:_:)``'s and is restated rather than
    /// shared because the two decoders key on different `CodingKeys` types;
    /// `CompactPackageHeadersTests` holds the two to the same answer over the
    /// shipped packages.
    private static func truthy(
        _ row: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) throws -> Bool {
        if let flag = try? row.decodeIfPresent(Bool.self, forKey: key) { return flag }
        return (try row.decodeIfPresent(Int.self, forKey: key) ?? 0) != 0
    }

    public init(from decoder: Decoder) throws {
        let row = try decoder.container(keyedBy: CodingKeys.self)
        id = try row.decode(String.self, forKey: .id)
        name = try row.decode(String.self, forKey: .name)
        nameRoma = try row.decodeIfPresent(String.self, forKey: .nameRoma)
        `operator` = try row.decodeIfPresent(String.self, forKey: .operator)
        operatorShort = try row.decodeIfPresent(String.self, forKey: .operatorShort)
        operatorLogo = try row.decodeIfPresent(String.self, forKey: .operatorLogo)
        kind = try row.decodeIfPresent(String.self, forKey: .kind)
        rank = try row.decode(Int.self, forKey: .rank)
        color = try row.decodeIfPresent(String.self, forKey: .color)
        colorDark = try row.decodeIfPresent(String.self, forKey: .colorDark)
        hasLogo = try Self.truthy(row, .logo)
        isLoop = try Self.truthy(row, .isLoop)
        lineCode = try row.decodeIfPresent(String.self, forKey: .lineCode)
        nameNorm = try row.decodeIfPresent(String.self, forKey: .nameNorm)
    }
}
