import Foundation

extension RecordedRouteMapping {
    /// Sections an editor should work on for `train`. A complete recorded chain
    /// is kept exactly. Otherwise (after a manual stop insertion/deletion) one
    /// section per adjacent stop pair is built; an existing section is reused
    /// only when the whole list lines up, or when exactly one existing section
    /// and exactly one occurrence match the pair. Endpoints compare with
    /// ``sameStation(code:name:otherCode:otherName:)``: codes when both sides
    /// have one, otherwise names; a missing reference never matches.
    public static func editableRouteSections(for train: Train) -> [RouteSection] {
        let source = train.routeSections ?? []
        if RecordedRouteMapping(stops: train.stops, sections: source) != nil { return source }
        let stops = train.stops
        let indices = 0..<max(0, stops.count - 1)
        func matches(_ section: RouteSection, _ index: Int) -> Bool {
            sameStation(code: section.fromN02StationCode, name: section.from,
                        otherCode: stops[index].n02StationCode, otherName: stops[index].name)
                && sameStation(code: section.toN02StationCode, name: section.to,
                               otherCode: stops[index + 1].n02StationCode, otherName: stops[index + 1].name)
        }
        func sameStop(_ a: Int, _ b: Int) -> Bool {
            sameStation(code: stops[a].n02StationCode, name: stops[a].name,
                        otherCode: stops[b].n02StationCode, otherName: stops[b].name)
        }
        let aligned = source.count == indices.count
            && indices.allSatisfy { matches(source[$0], $0) }
        return indices.map { index in
            let from = stops[index], to = stops[index + 1]
            if aligned { return source[index] }
            let existing = source.filter { matches($0, index) }
            let occurrences = indices.filter { sameStop($0, index) && sameStop($0 + 1, index + 1) }
            if existing.count == 1 && occurrences.count == 1 { return existing[0] }
            var section = RouteSection(from: from.name, to: to.name,
                                       fromN02StationCode: from.n02StationCode,
                                       toN02StationCode: to.n02StationCode)
            if let id = from.stationID, !id.isEmpty { section.fromStationID = id }
            if let id = to.stationID, !id.isEmpty { section.toStationID = id }
            return section
        }
    }
}
