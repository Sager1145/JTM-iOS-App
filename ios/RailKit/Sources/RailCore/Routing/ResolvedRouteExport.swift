import Foundation

/// Projects confirmed canonical-section selections into the existing import format.
/// The caller owns dated physical proof and canonical section provenance.
public enum ResolvedRouteExport {
    public struct Selection: Sendable {
        public let sectionIndex: Int
        public let fromStationCode: String
        public let toStationCode: String
        public let intervals: [StationIntervalResolver.DirectedInterval]

        public init(sectionIndex: Int, fromStationCode: String, toStationCode: String,
                    intervals: [StationIntervalResolver.DirectedInterval]) {
            self.sectionIndex = sectionIndex
            self.fromStationCode = fromStationCode
            self.toStationCode = toStationCode
            self.intervals = intervals
        }
    }

    public static func applying(to train: Train, selections: [Selection],
                                network: RouteNetwork, isComplete: Bool) -> Train {
        guard isComplete, !train.requiresRouteConfirmation,
              var sections = train.routeSections, !sections.isEmpty,
              selections.count == sections.count else { return train }
        var seen: Set<Int> = []
        for selection in selections {
            let index = selection.sectionIndex
            guard sections.indices.contains(index), seen.insert(index).inserted,
                  sections[index].fromN02StationCode == selection.fromStationCode,
                  sections[index].toN02StationCode == selection.toStationCode,
                  !selection.intervals.isEmpty else { return train }
            let codes = selection.intervals.map(\.code)
            // The import format stores symmetric codes, so replay them to prove
            // that it reconstructs this exact ordered, directed selection.
            guard network.directedIntervals(sectionCodes: codes,
                fromStationCode: selection.fromStationCode,
                toStationCode: selection.toStationCode) == selection.intervals
            else { return train }
            var lineIDs: [String] = []
            for interval in selection.intervals where !lineIDs.contains(interval.lineID) {
                lineIDs.append(interval.lineID)
            }
            if let authored = sections[index].sectionCodes, !authored.isEmpty {
                guard authored == codes else { return train }
                continue
            }
            if let constrained = sections[index].lineIDs, !constrained.isEmpty {
                guard lineIDs.allSatisfy(constrained.contains) else { return train }
            } else {
                sections[index].lineIDs = lineIDs
            }
            sections[index].sectionCodes = codes
        }
        var result = train
        result.routeSections = sections
        return result
    }
}
