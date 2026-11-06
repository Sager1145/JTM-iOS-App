/// Exact survey vertices used for display joins and their cached geometry inputs.
/// This index changes rendering only; it does not establish route connectivity.
public struct StrokeJunctionIndex: Sendable {
    public struct Line: Sendable, Equatable {
        public let id: String
        public let region: String
        public let operatorName: String?
        public let coordinates: [Coordinate]
        public let continuous: Bool
        public let follows: [String]

        public init(
            id: String, region: String, operatorName: String?, coordinates: [Coordinate],
            continuous: Bool, follows: [String] = []
        ) {
            self.id = id
            self.region = region
            self.operatorName = operatorName
            self.coordinates = coordinates
            self.continuous = continuous
            self.follows = follows
        }
    }

    private struct Key: Hashable, Sendable {
        let region: String
        let operatorName: String?
        let coordinate: Coordinate
    }

    /// What one ``update(_:)`` changed.
    ///
    /// `affectedIDs` is a superset of the ids whose ``dependencyIDs(of:)`` may
    /// differ: that result reads only the line itself, `byVertex` at the line's
    /// endpoint keys (when continuous), and the id/continuous of the candidates
    /// listed there. Any change to those touches one of the line's endpoint
    /// keys or the line itself.
    public struct Change: Sendable, Equatable {
        /// Added, removed, or ids whose winning `Line` differs from before.
        public let changedIDs: Set<String>
        public let affectedIDs: Set<String>
        public var isEmpty: Bool { changedIDs.isEmpty }
    }

    private var byID: [String: Line]
    private var byVertex: [Key: [String]] = [:]

    public init(_ lines: [Line]) {
        byID = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for line in byID.values.sorted(by: { $0.id < $1.id }) {
            for key in Self.vertexKeys(of: line) {
                byVertex[key, default: []].append(line.id)
            }
        }
    }

    /// The line's deduplicated vertex keys, in first-occurrence order.
    /// A coordinate unequal to itself (NaN) can never be looked up, so it is
    /// not indexed; indexing it would also leak a key on every ``update(_:)``.
    private static func vertexKeys(of line: Line) -> [Key] {
        var seen = Set<Coordinate>()
        return line.coordinates.compactMap { coordinate in
            coordinate == coordinate && seen.insert(coordinate).inserted
                ? Key(region: line.region, operatorName: line.operatorName, coordinate: coordinate)
                : nil
        }
    }

    private static func endpointKeys(of line: Line) -> [Key] {
        [line.coordinates.first, line.coordinates.last].compactMap { coordinate in
            coordinate.map { Key(region: line.region, operatorName: line.operatorName, coordinate: $0) }
        }
    }

    /// First index in the ascending `ids` whose element is not less than `id`.
    private static func lowerBound(of id: String, in ids: [String]) -> Int {
        var low = 0, high = ids.count
        while low < high {
            let mid = (low + high) / 2
            if ids[mid] < id { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Replaces the line set, patching only the vertex lists of changed lines.
    /// The result is structurally equal to `StrokeJunctionIndex(lines)`.
    public mutating func update(_ lines: [Line]) -> Change {
        let next = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = Set<String>()
        for (id, line) in next where byID[id] != line { changed.insert(id) }
        for id in byID.keys where next[id] == nil { changed.insert(id) }

        var touched = Set<Key>()
        for id in changed {
            let oldKeys = Set(byID[id].map(Self.vertexKeys(of:)) ?? [])
            let newKeys = Set(next[id].map(Self.vertexKeys(of:)) ?? [])
            touched.formUnion(oldKeys)
            touched.formUnion(newKeys)
            for key in oldKeys.subtracting(newKeys) {
                guard var ids = byVertex[key] else { continue }
                let at = Self.lowerBound(of: id, in: ids)
                if at < ids.count, ids[at] == id { ids.remove(at: at) }
                byVertex[key] = ids.isEmpty ? nil : ids
            }
            for key in newKeys.subtracting(oldKeys) {
                var ids = byVertex[key] ?? []
                ids.insert(id, at: Self.lowerBound(of: id, in: ids))
                byVertex[key] = ids
            }
        }
        byID = next

        var affected = changed
        for key in touched {
            for id in byVertex[key] ?? [] where !affected.contains(id) {
                if let line = byID[id], Self.endpointKeys(of: line).contains(key) {
                    affected.insert(id)
                }
            }
        }
        return Change(changedIDs: changed, affectedIDs: affected)
    }

    public func updated(_ lines: [Line]) -> (index: StrokeJunctionIndex, change: Change) {
        var copy = self
        let change = copy.update(lines)
        return (copy, change)
    }

    /// Number of indexed vertex keys (tests only).
    var vertexKeyCount: Int { byVertex.count }

    func isStructurallyEqual(to other: StrokeJunctionIndex) -> Bool {
        byID == other.byID && byVertex == other.byVertex
    }

    public func candidateIDs(
        sharing coordinate: Coordinate, region: String, operatorName: String?
    ) -> [String] {
        byVertex[Key(region: region, operatorName: operatorName, coordinate: coordinate)] ?? []
    }

    /// Geometry inputs tracked by the native mounted-stroke cache.
    public func dependencyIDs(of id: String) -> Set<String> {
        guard let line = byID[id] else { return [] }
        var dependencies = Set(line.follows)
        func adjacentIDs(_ candidate: Line) -> Set<String> {
            guard candidate.continuous, let hash = candidate.id.lastIndex(of: "#"),
                  let index = Int(candidate.id[candidate.id.index(after: hash)...]) else { return [] }
            let prefix = candidate.id[..<hash]
            var ids: Set<String> = ["\(prefix)#\(index + 1)"]
            if index > 0 { ids.insert("\(prefix)#\(index - 1)") }
            return ids
        }
        dependencies.formUnion(adjacentIDs(line))
        if line.continuous {
            for endpoint in [line.coordinates.first, line.coordinates.last].compactMap({ $0 }) {
                for candidateID in candidateIDs(
                    sharing: endpoint, region: line.region, operatorName: line.operatorName
                ) where candidateID != id {
                    dependencies.insert(candidateID)
                    if let candidate = byID[candidateID] {
                        dependencies.formUnion(adjacentIDs(candidate))
                    }
                }
            }
        }
        dependencies.remove(id)
        return dependencies
    }
}
