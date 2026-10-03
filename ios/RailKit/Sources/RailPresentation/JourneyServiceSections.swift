import RailCore

/// Consecutive sections with the same recorded service identity form one leg.
/// A company list at journey level cannot establish which line or number it
/// operates, so the grouping uses only explicit section metadata.
public enum JourneyServiceSections {
    public struct Leg: Equatable, Sendable, Identifiable {
        public var fromStopIndex: Int
        public var toStopIndex: Int
        public var info: RouteSectionServiceInfo
        public var id: Int { fromStopIndex }
    }

    public static func legs(of train: Train) -> [Leg] {
        let sections = StoreOperations.rideRouteSections(for: train)
        var legs: [Leg] = []
        for (index, section) in sections.enumerated() {
            let info = RouteSectionServiceInfo(section: section)
            guard !info.isEmpty else { continue }
            if let last = legs.last, last.toStopIndex == index, last.info == info {
                legs[legs.count - 1].toStopIndex = index + 1
            } else {
                legs.append(Leg(fromStopIndex: index, toStopIndex: index + 1, info: info))
            }
        }
        return legs
    }
}
