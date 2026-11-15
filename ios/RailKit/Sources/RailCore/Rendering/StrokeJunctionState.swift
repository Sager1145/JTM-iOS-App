/// A junction index together with the dependency ids of every line it
/// holds. Advancing it is pure: the receiver is never changed, so the map can
/// compute the next state on a worker while a geometry preparation still holds
/// the current one.
public struct StrokeJunctionState: Sendable {
    public private(set) var index: StrokeJunctionIndex
    /// ``StrokeJunctionIndex/dependencyIDs(of:)`` for every line of the last
    /// advance, keyed by line id.
    public private(set) var dependencyIDs: [String: Set<String>]

    public init() {
        self.index = StrokeJunctionIndex([])
        self.dependencyIDs = [:]
    }

    /// The state for `lines` and what moved. Dependency ids are recomputed only
    /// for the lines the update may have affected; every other line keeps its
    /// cached set. Equal to a state built fresh from `lines`.
    public func advanced(
        to lines: [StrokeJunctionIndex.Line]
    ) -> (state: StrokeJunctionState, change: StrokeJunctionIndex.Change) {
        var next = self
        let change = next.index.update(lines)
        var nextDependencyIDs: [String: Set<String>] = [:]
        nextDependencyIDs.reserveCapacity(lines.count)
        for line in lines {
            if !change.affectedIDs.contains(line.id), let cached = dependencyIDs[line.id] {
                nextDependencyIDs[line.id] = cached
            } else {
                nextDependencyIDs[line.id] = next.index.dependencyIDs(of: line.id)
            }
        }
        next.dependencyIDs = nextDependencyIDs
        return (next, change)
    }
}
