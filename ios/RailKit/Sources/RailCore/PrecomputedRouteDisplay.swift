import Foundation

extension RouteNetwork {
    public struct PrecomputedDisplayPart: Sendable {
        public let coordinates: [Coordinate]
        public let sourceCoordinates: [Coordinate]
        public let displayLineIDs: [String]
        public let matchedSectionCodes: [String]

        public init(coordinates: [Coordinate], sourceCoordinates: [Coordinate],
                    displayLineIDs: [String] = [], matchedSectionCodes: [String] = []) {
            self.coordinates = coordinates
            self.sourceCoordinates = sourceCoordinates
            self.displayLineIDs = displayLineIDs
            self.matchedSectionCodes = matchedSectionCodes
        }
    }

    /// Apply the same display slice as a freshly solved ride without replacing
    /// the precompute's source path used by mileage, exports and edge matching.
    public func precomputedDisplayParts(
        source: [Coordinate], hints: RouteHints,
        temporalKind: RouteGraph.TemporalKind = .current,
        continueFrom: Coordinate? = nil, cache: inout RouteProjectionCache
    ) -> [PrecomputedDisplayPart] {
        guard source.count >= 2 else { return [] }
        let canonical = RouteGraph.TemporalKind.shouldCanonicalizeDisplayNetwork(temporalKind)
            ? canonicalizeRouteFeature(
                RouteFeature(geometry: .lineString(source), hints: hints),
                continueFrom: continueFrom, cache: &cache) : nil
        let drawn = canonical?.geometry.lines ?? [source]
        var start = 0
        return drawn.enumerated().map { index, coordinates in
            let end: Int
            if index == drawn.count - 1 { end = source.count - 1 }
            else if let endpoint = coordinates.last {
                end = (start..<source.count).min {
                    Geometry.distanceMeters(source[$0], endpoint)
                        < Geometry.distanceMeters(source[$1], endpoint)
                } ?? start
            } else { end = start }
            let original = Array(source[start...end])
            start = end
            return PrecomputedDisplayPart(
                coordinates: coordinates, sourceCoordinates: original,
                displayLineIDs: canonical?.displayLineIds ?? [],
                matchedSectionCodes: canonical.map {
                    $0.matchedSectionCodes.isEmpty ? hints.sectionCodes : $0.matchedSectionCodes
                } ?? [])
        }
    }
}
