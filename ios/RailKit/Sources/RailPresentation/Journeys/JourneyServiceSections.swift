import RailCore

/// Consecutive sections with the same recorded service identity form one leg.
/// A company list at journey level cannot establish which line or number it
/// operates, so the grouping uses only explicit section metadata.
public enum JourneyServiceSections {
    public struct Leg: Equatable, Sendable, Identifiable {
        public var fromStopIndex: Int
        public var toStopIndex: Int
        public var fromSectionIndex: Int
        public var toSectionIndex: Int
        /// Physical service endpoints may be source-only boundaries, not calls.
        public var from: String?
        public var to: String?
        public var fromStationCode: String?
        public var toStationCode: String?
        public var info: RouteSectionServiceInfo
        public var id: Int { fromSectionIndex }
    }

    public static func legs(of train: Train) -> [Leg] {
        let sections = StoreOperations.rideRouteSections(for: train)
        guard let mapping = RecordedRouteMapping(stops: train.stops, sections: sections) else { return [] }
        var legs: [Leg] = []
        for (index, section) in sections.enumerated() {
            let info = RouteSectionServiceInfo(section: section)
            guard !info.isEmpty, let stopInterval = mapping.stopInterval(forSectionIndex: index) else { continue }
            if let last = legs.last, last.toSectionIndex == index, last.info == info {
                legs[legs.count - 1].toStopIndex = stopInterval + 1
                legs[legs.count - 1].toSectionIndex = index + 1
                legs[legs.count - 1].to = section.to
                legs[legs.count - 1].toStationCode = section.toN02StationCode
            } else {
                legs.append(Leg(fromStopIndex: stopInterval, toStopIndex: stopInterval + 1,
                    fromSectionIndex: index, toSectionIndex: index + 1,
                    from: section.from, to: section.to,
                    fromStationCode: section.fromN02StationCode, toStationCode: section.toN02StationCode,
                    info: info))
            }
        }
        return legs
    }
}
