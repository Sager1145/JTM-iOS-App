/// Relates physical route sections to recorded visits without inventing calls
/// at source-only boundaries. Section ordinals remain physical identities;
/// ride flags, clocks and visit edits use the enclosing recorded interval.
public struct RecordedRouteMapping: Equatable, Sendable {
    public let sectionStopIntervals: [Int]
    /// Physical section boundary for each recorded visit, in visit order.
    /// The destination uses the final boundary even if it was passed earlier.
    public let stopSectionBoundaries: [Int]

    /// Accepts one continuous explicit chain through every recorded visit.
    /// Conflicting codes cannot match by name; repeated visits consume distinct
    /// ordered boundaries, using the canonical archive's occurrence contract.
    public init?(stops: [Stop], sections: [RouteSection]) {
        guard stops.count >= 2, let first = sections.first, let last = sections.last else { return nil }
        func matches(_ code: String?, _ name: String?, _ otherCode: String?, _ otherName: String?) -> Bool {
            if let code, !code.isEmpty, let otherCode, !otherCode.isEmpty {
                return sameCodeUnits(StationCodeAliases.canonical(code), StationCodeAliases.canonical(otherCode))
            }
            guard let name, !name.isEmpty, let otherName, !otherName.isEmpty else { return false }
            return sameCodeUnits(name, otherName)
        }
        guard matches(first.fromN02StationCode, first.from, stops[0].n02StationCode, stops[0].name),
              matches(last.toN02StationCode, last.to, stops[stops.count - 1].n02StationCode, stops[stops.count - 1].name)
        else { return nil }
        // Adjacent recorded sections may mix code-only and name-only references
        // to the same visit. Both endpoints resolve through that recorded visit;
        // source-only boundaries below still require direct chain continuity.
        if sections.count == stops.count - 1, sections.indices.allSatisfy({ index in
            matches(sections[index].fromN02StationCode, sections[index].from,
                    stops[index].n02StationCode, stops[index].name)
                && matches(sections[index].toN02StationCode, sections[index].to,
                           stops[index + 1].n02StationCode, stops[index + 1].name)
        }) {
            sectionStopIntervals = Array(sections.indices)
            stopSectionBoundaries = Array(0...sections.count)
            return
        }
        var boundaries = [0]
        var nextStop = 1
        for (index, section) in sections.enumerated() {
            guard section.fromN02StationCode?.isEmpty == false || section.from?.isEmpty == false,
                  section.toN02StationCode?.isEmpty == false || section.to?.isEmpty == false else { return nil }
            if index > 0 {
                let previous = sections[index - 1]
                guard matches(previous.toN02StationCode, previous.to, section.fromN02StationCode, section.from)
                else { return nil }
            }
            if index < sections.count - 1, nextStop < stops.count - 1,
               matches(section.toN02StationCode, section.to, stops[nextStop].n02StationCode, stops[nextStop].name) {
                boundaries.append(index + 1)
                nextStop += 1
            }
        }
        guard nextStop == stops.count - 1 else { return nil }
        boundaries.append(sections.count)
        var intervals = Array(repeating: 0, count: sections.count)
        for stopIndex in 0..<(boundaries.count - 1) {
            for sectionIndex in boundaries[stopIndex]..<boundaries[stopIndex + 1] {
                intervals[sectionIndex] = stopIndex
            }
        }
        sectionStopIntervals = intervals
        stopSectionBoundaries = boundaries
    }

    public func stopInterval(forSectionIndex index: Int) -> Int? {
        sectionStopIntervals.indices.contains(index) ? sectionStopIntervals[index] : nil
    }

    public func sectionRange(fromStopIndex: Int, toStopIndex: Int) -> Range<Int>? {
        guard fromStopIndex >= 0, fromStopIndex < toStopIndex,
              stopSectionBoundaries.indices.contains(toStopIndex) else { return nil }
        return stopSectionBoundaries[fromStopIndex]..<stopSectionBoundaries[toStopIndex]
    }

    /// A physical boundary can be a source-only point rather than a call.
    public func stopIndex(atSectionBoundary boundary: Int) -> Int? {
        stopSectionBoundaries.firstIndex(of: boundary)
    }
}
