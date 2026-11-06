import Foundation

/// Reviewed list of rows that are the other track of a parallel railway: two
/// tracks of one line that split apart for a loop or a second tunnel and meet
/// again, so a ride along one can legitimately hand over to the other at the
/// seam. The package only declares `paired_alignment` rows; this catalog adds
/// the sourced up/down assignment and the review status, and
/// ``Catalog/validated(against:)`` drops any entry the package does not back.
///
/// A row that is a real branch (函館線-2 via 渡島砂原, 上越線-2 ガーラ湯沢)
/// is listed under `notPairs` so it can never be mistaken for a paired track.
public enum PairedTracks {
    public typealias Direction = TrackPreference
    public enum Status: String, Codable, Sendable { case confirmed, unclear }
    public enum DirectionStatus: String, Codable, Sendable { case confirmed, unclear, unknown }

    public struct Station: Codable, Sendable, Equatable {
        public let name: String
        public let code: String
    }

    public struct Pair: Codable, Sendable, Equatable {
        public let pairedLineID: String
        public let parentLineID: String
        public let line: String
        public let `operator`: String?
        public let from: Station
        public let to: Station
        public let upTrack: String?
        public let downTrack: String?
        /// The row both directions use between `from` and `to` (a parent that
        /// still carries the other direction and intermediate stations).
        public let sharedTrack: String?
        /// Whether the two rows are one railway's two tracks.
        public let pairStatus: Status
        /// Whether `upTrack`/`downTrack` are sourced. Only `confirmed` is held to the package.
        public let directionStatus: DirectionStatus
        public let sources: [String]
        public let note: String?
    }

    public struct NotPair: Codable, Sendable, Equatable {
        public let lineID: String
        public let reason: String
        public let sources: [String]
    }

    public struct Catalog: Codable, Sendable {
        public let schemaVersion: Int
        public let region: String
        public let pairs: [Pair]
        public let notPairs: [NotPair]

        public init(schemaVersion: Int = 1, region: String = "jp", pairs: [Pair], notPairs: [NotPair] = []) {
            self.schemaVersion = schemaVersion
            self.region = region
            self.pairs = pairs
            self.notPairs = notPairs
        }

        public static let empty = Catalog(pairs: [])

        /// A missing or damaged resource is a defect, never an empty catalog.
        public static let bundled: Catalog = {
            guard let url = Bundle.module.url(forResource: "japan-paired-tracks", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
                  catalog.schemaVersion == 1 else {
                fatalError("japan-paired-tracks.json is missing or damaged")
            }
            return catalog
        }()

        public func pair(forRow rowID: String) -> Pair? {
            pairs.first { $0.pairedLineID == rowID }
        }

        /// The confirmed pair joined at a seam: the last interval of one part is
        /// on the parent and the first interval of the next on its own paired
        /// row (either order), at one of the pair's two shared stations. An
        /// unclear pair never splices.
        public func isSeam(fromLineID: String, toLineID: String, stationCode: String) -> Pair? {
            pairs.first { pair in
                pair.pairStatus == .confirmed
                    && (stationCode == pair.from.code || stationCode == pair.to.code)
                    && ((fromLineID == pair.parentLineID && toLineID == pair.pairedLineID)
                        || (fromLineID == pair.pairedLineID && toLineID == pair.parentLineID))
            }
        }

        public func track(for direction: Direction, pair: Pair) -> String? {
            direction == .up ? pair.upTrack : pair.downTrack
        }

        /// The row a section must ride when the passenger forces `direction` on
        /// `pair`: that direction's own track, else the shared one. Nil when the
        /// pair offers no override: its direction is not confirmed, or the
        /// catalog names no row for it.
        public func forcedTrack(_ direction: Direction, pair: Pair) -> String? {
            guard pair.pairStatus == .confirmed, pair.directionStatus == .confirmed else { return nil }
            return track(for: direction, pair: pair) ?? pair.sharedTrack
        }

        /// Pairs a ride between two stations of the parent row crosses, or the
        /// pair whose own two stations the ride joins. It is the lookup the
        /// track-override UI and the override's solver filters build on.
        public func traversedPairs(fromCode: String, toCode: String, package: CompactPackage) -> [Pair] {
            traversedPairs(fromCode: fromCode, toCode: toCode, rows: package.lines)
        }

        public func traversedPairs(fromCode: String, toCode: String, rows lines: [CompactPackage.Line]) -> [Pair] {
            let rows = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return pairs.filter { pair in
                guard let parent = rows[pair.parentLineID] else { return false }
                let ids = parent.stations.map(\.id)
                if let start = ids.firstIndex(of: fromCode), let end = ids.firstIndex(of: toCode),
                   let a = ids.firstIndex(of: pair.from.code), let b = ids.firstIndex(of: pair.to.code) {
                    return max(min(start, end), min(a, b)) < min(max(start, end), max(a, b))
                }
                return Set([fromCode, toCode]) == Set([pair.from.code, pair.to.code])
            }
        }

        /// The confirmed pairs a section can force a track on. Empty when the
        /// override cannot work, so a stale or imported preference is ignored:
        /// the section has authored interval codes; its line ids exclude a row of
        /// a traversed pair; or an endpoint lies strictly inside a pair's parent
        /// span (the other row skips that station, e.g. 垂井, 新函館北斗). Pairs
        /// whose direction is not confirmed are never offered.
        public func overridablePairs(for section: RouteSection, rows lines: [CompactPackage.Line]) -> [Pair] {
            guard section.sectionCodes?.isEmpty != false,
                  let from = section.fromN02StationCode, let to = section.toN02StationCode else { return [] }
            let traversed = traversedPairs(fromCode: from, toCode: to, rows: lines)
                .filter { $0.pairStatus == .confirmed && $0.directionStatus == .confirmed }
            guard !traversed.isEmpty else { return [] }
            let rows = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let ids = section.lineIDs ?? []
            for pair in traversed {
                if !ids.isEmpty, !(ids.contains(pair.pairedLineID) && ids.contains(pair.parentLineID)) { return [] }
                guard let parent = rows[pair.parentLineID]?.stations.map(\.id),
                      let a = parent.firstIndex(of: pair.from.code), let b = parent.firstIndex(of: pair.to.code)
                else { return [] }
                for endpoint in [from, to] {
                    if let index = parent.firstIndex(of: endpoint), min(a, b) < index, index < max(a, b) { return [] }
                }
            }
            return traversed
        }

        /// The entries the package itself backs. Never cached: it is cheap, and a
        /// cache keyed by anything short of content can serve the wrong catalog.
        public func validated(against package: CompactPackage) -> Catalog {
            validated(against: package.lines)
        }

        public func validated(against lines: [CompactPackage.Line]) -> Catalog {
            let rows = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let rejected = Set(notPairs.map(\.lineID))
            return Catalog(schemaVersion: schemaVersion, region: region,
                pairs: pairs.filter { Self.rejection(of: $0, rows: rows, notPairs: rejected) == nil },
                notPairs: notPairs)
        }

        /// Why the package does not back an entry, or nil when it does.
        static func rejection(
            of pair: Pair, rows: [String: CompactPackage.Line], notPairs: Set<String>
        ) -> String? {
            guard let paired = rows[pair.pairedLineID], let parent = rows[pair.parentLineID] else {
                return "row missing from the package"
            }
            if notPairs.contains(pair.pairedLineID) || notPairs.contains(pair.parentLineID) {
                return "listed in notPairs"
            }
            guard paired.alignmentRole == "paired_alignment", paired.alignmentOf == pair.parentLineID else {
                return "not declared paired_alignment of the parent"
            }
            guard paired.name == parent.name, paired.operator == parent.operator else {
                return "name or operator differs from the parent"
            }
            let pairedIDs = paired.stations.map(\.id)
            guard pairedIDs.first == pair.from.code, pairedIDs.last == pair.to.code, pairedIDs.count >= 2 else {
                return "stations do not run from \(pair.from.name) to \(pair.to.name)"
            }
            let parentIDs = parent.stations.map(\.id)
            let positions = pairedIDs.compactMap { parentIDs.firstIndex(of: $0) }
            guard positions.count == pairedIDs.count, let first = positions.first, let last = positions.last,
                  first != last else { return "paired stations are not all on the parent" }
            let ascending = first < last
            guard zip(positions, positions.dropFirst()).allSatisfy({ ascending ? $0 < $1 : $0 > $1 }) else {
                return "paired stations are in a different order than the parent"
            }
            let between = parentIDs[(min(first, last) + 1)..<max(first, last)]
            if !between.allSatisfy(pairedIDs.contains), pair.sharedTrack != pair.parentLineID {
                return "parent has extra stations in the span but sharedTrack is not the parent"
            }
            if [pair.upTrack, pair.downTrack, pair.sharedTrack].contains(where: { id in
                id != nil && id != pair.pairedLineID && id != pair.parentLineID }) {
                return "track is neither the paired row nor the parent"
            }
            guard pair.directionStatus == .confirmed else { return nil }
            if let stated = paired.alignmentDirection, let direction = Direction(rawValue: stated),
               (direction == .up ? pair.upTrack : pair.downTrack) != pair.pairedLineID {
                return "package says the paired row is \(stated) but the entry disagrees"
            }
            for declaration in parent.alignmentPairs where declaration.with == pair.pairedLineID {
                guard let stated = Direction(rawValue: declaration.direction) else { continue }
                if (stated == .up ? pair.upTrack : pair.downTrack) == pair.pairedLineID {
                    return "package says the parent is \(declaration.direction) but the entry gives that track to the paired row"
                }
            }
            return nil
        }
    }
}
