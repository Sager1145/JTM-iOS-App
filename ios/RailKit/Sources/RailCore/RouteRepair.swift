import Foundation

/// Spans of a ride whose surveyed route is missing, and a bounded search of
/// just that span. Applying a result stays with `RailwayRouteEditing`.
public enum RouteRepair {
    public struct Gap: Equatable, Sendable {
        public var segmentIndex: Int
        public var isBoundary: Bool
        /// Joining station for a boundary gap. Unused for a section gap.
        public var station: String?

        public init(segmentIndex: Int, isBoundary: Bool, station: String? = nil) {
            self.segmentIndex = segmentIndex
            self.isBoundary = isBoundary
            self.station = station
        }
    }

    public enum Reason: Equatable, Sendable {
        case boundary(station: String?)
        case section
        case unsolved
    }

    /// Inclusive visit indexes into `train.stops`.
    public struct Span: Equatable, Sendable {
        public var fromVisitIndex: Int
        public var toVisitIndex: Int
        public var reason: Reason

        public init(fromVisitIndex: Int, toVisitIndex: Int, reason: Reason) {
            self.fromVisitIndex = fromVisitIndex
            self.toVisitIndex = toVisitIndex
            self.reason = reason
        }
    }

    public enum Attempt: Equatable, Sendable {
        case unique(RailwayRouteChoices.Choice)
        case ambiguous([RailwayRouteChoices.Choice])
        case none
    }

    /// A non-boundary gap or an unsolved section `i` covers visits `i...i+1`.
    /// A boundary gap at section `i` covers visits `i-1...i+1`. Overlapping and
    /// adjacent spans merge. A merged reason prefers boundary, then section,
    /// then unsolved, and keeps the first boundary station.
    public static func failingSpans(train: Train, gaps: [Gap], unsolved: [Int] = []) -> [Span] {
        let count = train.stops.count
        guard count >= 2 else { return [] }
        var raw: [Span] = []
        for gap in gaps {
            let index = gap.segmentIndex
            if gap.isBoundary {
                let from = max(0, index - 1)
                let to = min(count - 1, index + 1)
                guard from < to else { continue }
                raw.append(Span(fromVisitIndex: from, toVisitIndex: to, reason: .boundary(station: gap.station)))
            } else {
                let from = index
                let to = index + 1
                guard from >= 0, to < count else { continue }
                raw.append(Span(fromVisitIndex: from, toVisitIndex: to, reason: .section))
            }
        }
        for index in unsolved {
            let from = index
            let to = index + 1
            guard from >= 0, to < count else { continue }
            raw.append(Span(fromVisitIndex: from, toVisitIndex: to, reason: .unsolved))
        }
        raw.sort {
            $0.fromVisitIndex < $1.fromVisitIndex
                || ($0.fromVisitIndex == $1.fromVisitIndex && $0.toVisitIndex < $1.toVisitIndex)
        }
        var merged: [Span] = []
        for span in raw {
            if let last = merged.indices.last, span.fromVisitIndex <= merged[last].toVisitIndex {
                merged[last].toVisitIndex = max(merged[last].toVisitIndex, span.toVisitIndex)
                merged[last].reason = preferred(merged[last].reason, span.reason)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    /// Search only the visits inside `span`. Recorded stop order supplies
    /// direction. One untruncated path from labeled inference is `.unique`;
    /// several are `.ambiguous`. A path found only by the final package
    /// search, without those line labels, is `.ambiguous` even when alone.
    public static func attempt(
        span: Span, train: Train, package: CompactPackage, stationAliases: [String: String] = [:]
    ) -> Attempt {
        guard let slice = slice(span, from: train) else { return .none }
        let inferred = classify(slice, package: package, stationAliases: stationAliases)
        if inferred != .none { return inferred }
        let coded = slice.stops.filter { ($0.n02StationCode?.isEmpty == false) }
        if coded.count >= 2, coded.count != slice.stops.count {
            var reduced = slice
            reduced.stops = coded
            reduced.origin = coded[0].name
            reduced.destination = coded[coded.count - 1].name
            reduced.routeSections = nil
            let retry = classify(reduced, package: package, stationAliases: stationAliases)
            if retry != .none { return retry }
        }
        let codes = slice.stops.compactMap(\.n02StationCode).filter { !$0.isEmpty }
        guard let origin = codes.first, let destination = codes.last, origin != destination else { return .none }
        let searched = LocalJourneySearch.search(
            package: package, originCode: origin, destinationCode: destination,
            trainType: slice.trainType, requiredStationCodes: codes,
            stationAliases: stationAliases, maximumExpansions: 200_000)
        if searched.choices.isEmpty { return .none }
        // No line labels survived to this search. One result still goes to
        // the guide; it is not an automatic `.unique` apply.
        return .ambiguous(searched.choices)
    }

    private static func slice(_ span: Span, from train: Train) -> Train? {
        let stops = train.stops
        guard span.fromVisitIndex >= 0, span.toVisitIndex < stops.count,
              span.fromVisitIndex < span.toVisitIndex else { return nil }
        var slice = train
        slice.stops = Array(stops[span.fromVisitIndex...span.toVisitIndex])
        slice.origin = slice.stops[0].name
        slice.destination = slice.stops[slice.stops.count - 1].name
        if let sections = train.routeSections, sections.count == stops.count - 1 {
            slice.routeSections = Array(sections[span.fromVisitIndex..<span.toVisitIndex])
        } else {
            slice.routeSections = nil
        }
        return slice
    }

    private static func classify(
        _ train: Train, package: CompactPackage, stationAliases: [String: String]
    ) -> Attempt {
        let result = RailwayRouteInference.search(
            in: train, package: package, stationAliases: stationAliases, maximumExpansions: 200_000)
        if let choice = result.uniqueChoice { return .unique(choice) }
        if !result.choices.isEmpty { return .ambiguous(result.choices) }
        return .none
    }

    /// Boundary outranks a plain section, which outranks an unsolved index.
    /// Equal ranks keep the reason already on the span, including its station.
    private static func preferred(_ current: Reason, _ next: Reason) -> Reason {
        func rank(_ reason: Reason) -> Int {
            switch reason {
            case .boundary: 3
            case .section: 2
            case .unsolved: 1
            }
        }
        return rank(next) > rank(current) ? next : current
    }
}
