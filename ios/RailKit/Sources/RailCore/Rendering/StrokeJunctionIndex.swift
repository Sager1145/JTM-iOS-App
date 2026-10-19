/// Exact survey vertices used for display joins and their cached geometry inputs.
/// This index changes rendering only; it does not establish route connectivity.
public struct StrokeJunctionIndex: Sendable {
    public struct Line: Sendable {
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

    private let byID: [String: Line]
    private var byVertex: [Key: [String]] = [:]

    public init(_ lines: [Line]) {
        byID = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for line in byID.values.sorted(by: { $0.id < $1.id }) {
            var seen = Set<Coordinate>()
            for coordinate in line.coordinates where seen.insert(coordinate).inserted {
                let key = Key(region: line.region, operatorName: line.operatorName, coordinate: coordinate)
                byVertex[key, default: []].append(line.id)
            }
        }
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
