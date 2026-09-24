import Foundation
import RailCore

public struct JourneyDraftStop: Hashable, Sendable, Identifiable {
    public var occurrenceID: UUID
    public var stationKey: StationKey?
    public var displayName: String
    public var lineID: String?
    public var operatorID: String?
    public var membershipID: String?
    public var conflict: JourneyDraftConflict?
    public var id: UUID { occurrenceID }

    public init(
        occurrenceID: UUID,
        stationKey: StationKey? = nil,
        displayName: String,
        lineID: String? = nil,
        operatorID: String? = nil,
        membershipID: String? = nil,
        conflict: JourneyDraftConflict? = nil
    ) {
        self.occurrenceID = occurrenceID
        self.stationKey = stationKey
        self.displayName = displayName
        self.lineID = lineID
        self.operatorID = operatorID
        self.membershipID = membershipID
        self.conflict = conflict
    }
}

public enum JourneyDraftConflict: Hashable, Sendable {
    /// The stop's station is not a member of its current line. Both stay; nothing is deleted.
    case stationNotOnLine(stationKey: StationKey, lineID: String)
}

public struct LineChoice: Hashable, Sendable {
    public var lineID: String
    public var regionCode: String
    public var operatorID: String
    public var lineName: String
    public var operatorName: String

    public init(
        lineID: String, regionCode: String, operatorID: String, lineName: String, operatorName: String
    ) {
        self.lineID = lineID
        self.regionCode = regionCode
        self.operatorID = operatorID
        self.lineName = lineName
        self.operatorName = operatorName
    }
}

public enum JourneySelectionPrompt: Hashable, Sendable {
    case chooseLine(occurrenceID: UUID, choices: [LineChoice])
    case ambiguousName(occurrenceID: UUID, query: String, candidates: [StationKey])
    case possibleTransfer(earlierOccurrenceID: UUID, laterOccurrenceID: UUID)
}

public enum JourneySelectionEvent: Hashable, Sendable {
    case selectStation(occurrenceID: UUID, stationKey: StationKey)
    case selectLine(occurrenceID: UUID, regionCode: String, lineID: String)
    case selectName(occurrenceID: UUID, query: String, regionCode: String?)
}

public struct JourneySelectionResult: Hashable, Sendable {
    public var stops: [JourneyDraftStop]
    public var prompt: JourneySelectionPrompt?

    public init(stops: [JourneyDraftStop], prompt: JourneySelectionPrompt? = nil) {
        self.stops = stops
        self.prompt = prompt
    }
}

public struct JourneyDraftDeletion: Hashable, Sendable {
    public var offset: Int
    public var stop: JourneyDraftStop

    public init(offset: Int, stop: JourneyDraftStop) {
        self.offset = offset
        self.stop = stop
    }
}

public enum JourneyDraftEdits {
    public static func insert(
        _ stop: JourneyDraftStop, at index: Int, in stops: [JourneyDraftStop]
    ) -> [JourneyDraftStop] {
        var next = stops
        let clamped = min(max(index, 0), next.count)
        next.insert(stop, at: clamped)
        return next
    }

    public static func delete(
        at offsets: IndexSet, in stops: [JourneyDraftStop]
    ) -> (stops: [JourneyDraftStop], deleted: [JourneyDraftDeletion]) {
        let valid = offsets.filter { stops.indices.contains($0) }.sorted()
        let deleted = valid.map { JourneyDraftDeletion(offset: $0, stop: stops[$0]) }
        var next = stops
        for offset in valid.reversed() {
            next.remove(at: offset)
        }
        return (next, deleted)
    }

    public static func move(
        from offsets: IndexSet, to destination: Int, in stops: [JourneyDraftStop]
    ) -> [JourneyDraftStop] {
        let moving = offsets.sorted().filter { stops.indices.contains($0) }.map { stops[$0] }
        var next = stops
        for offset in offsets.sorted(by: >) where stops.indices.contains(offset) {
            next.remove(at: offset)
        }
        let removedBefore = offsets.filter { stops.indices.contains($0) && $0 < destination }.count
        let index = min(max(destination - removedBefore, 0), next.count)
        next.insert(contentsOf: moving, at: index)
        return next
    }

    public static func undo(
        _ deletions: [JourneyDraftDeletion], in stops: [JourneyDraftStop]
    ) -> [JourneyDraftStop] {
        var next = stops
        for deletion in deletions.sorted(by: { $0.offset < $1.offset }) {
            let index = min(max(deletion.offset, 0), next.count)
            next.insert(deletion.stop, at: index)
        }
        return next
    }
}

public enum JourneyDraftSelection {
    public static func reduce(
        stops: [JourneyDraftStop],
        event: JourneySelectionEvent,
        catalog: EditorCatalog
    ) -> JourneySelectionResult {
        switch event {
        case .selectStation(let occurrenceID, let stationKey):
            return applyStation(occurrenceID: occurrenceID, stationKey: stationKey, stops: stops, catalog: catalog)
        case .selectLine(let occurrenceID, let regionCode, let lineID):
            return applyLine(
                occurrenceID: occurrenceID, regionCode: regionCode, lineID: lineID, stops: stops, catalog: catalog)
        case .selectName(let occurrenceID, let query, let regionCode):
            return applyName(
                occurrenceID: occurrenceID, query: query, regionCode: regionCode, stops: stops, catalog: catalog)
        }
    }

    /// Line IDs present on both stations, in the same region as both keys.
    /// Sorted. Empty if either station is unknown or they share no line. Never picks one.
    public static func sharedLineIDs(
        _ a: StationKey, _ b: StationKey, catalog: EditorCatalog
    ) -> [String] {
        guard a.regionCode == b.regionCode else { return [] }
        guard catalog.station(a) != nil, catalog.station(b) != nil else { return [] }
        let aLines = Set(
            catalog.memberships(stationKey: a).filter { $0.regionCode == a.regionCode }.map(\.lineID))
        let bLines = Set(
            catalog.memberships(stationKey: b).filter { $0.regionCode == b.regionCode }.map(\.lineID))
        return aLines.intersection(bLines).sorted()
    }

    /// After both stops have stations, if they share exactly one line AND neither stop
    /// already has a different lineID, fill that line on both and return nil prompt.
    /// If they share several, change nothing and return chooseLine for the LATER stop
    /// (choices are only the shared lines).
    /// If they share none, change nothing and return possibleTransfer.
    /// If one already has the unique shared line and the other has nil line, fill the empty one.
    /// If one has a line that is NOT the unique shared line, do not overwrite it; set
    /// conflict on the stop whose line is incompatible with its station, and still return
    /// possibleTransfer only when the shared set is empty. When shared count is 1 but an
    /// existing line conflicts, keep the existing line, set stationNotOnLine on that stop,
    /// and return nil prompt (the conflict is on the stop).
    public static func reconcileNeighbors(
        earlierOccurrenceID: UUID,
        laterOccurrenceID: UUID,
        stops: [JourneyDraftStop],
        catalog: EditorCatalog
    ) -> JourneySelectionResult {
        guard
            let earlierIndex = stops.firstIndex(where: { $0.occurrenceID == earlierOccurrenceID }),
            let laterIndex = stops.firstIndex(where: { $0.occurrenceID == laterOccurrenceID }),
            earlierIndex != laterIndex,
            let earlierKey = stops[earlierIndex].stationKey,
            let laterKey = stops[laterIndex].stationKey
        else {
            return JourneySelectionResult(stops: stops, prompt: nil)
        }

        let shared = sharedLineIDs(earlierKey, laterKey, catalog: catalog)
        if shared.isEmpty {
            var next = stops
            flagIfStationNotOnItsLine(&next[earlierIndex], catalog: catalog)
            flagIfStationNotOnItsLine(&next[laterIndex], catalog: catalog)
            return JourneySelectionResult(
                stops: next,
                prompt: .possibleTransfer(
                    earlierOccurrenceID: earlierOccurrenceID, laterOccurrenceID: laterOccurrenceID)
            )
        }
        if shared.count > 1 {
            let allowed = Set(shared)
            let choices = lineChoices(
                catalog.memberships(stationKey: laterKey).filter { allowed.contains($0.lineID) },
                catalog: catalog
            )
            return JourneySelectionResult(
                stops: stops,
                prompt: .chooseLine(occurrenceID: laterOccurrenceID, choices: choices)
            )
        }

        var next = stops
        applyUniqueSharedLine(&next[earlierIndex], lineID: shared[0], catalog: catalog)
        applyUniqueSharedLine(&next[laterIndex], lineID: shared[0], catalog: catalog)
        return JourneySelectionResult(stops: next, prompt: nil)
    }

    private static func applyName(
        occurrenceID: UUID,
        query: String,
        regionCode: String?,
        stops: [JourneyDraftStop],
        catalog: EditorCatalog
    ) -> JourneySelectionResult {
        guard stops.contains(where: { $0.occurrenceID == occurrenceID }) else {
            return JourneySelectionResult(stops: stops, prompt: nil)
        }
        let matches = catalog.candidates(named: query, regionCode: regionCode)
        if matches.isEmpty {
            return JourneySelectionResult(stops: stops, prompt: nil)
        }
        if matches.count == 1, let key = matches.first?.key {
            return applyStation(occurrenceID: occurrenceID, stationKey: key, stops: stops, catalog: catalog)
        }
        let keys = matches.map(\.key).sorted { lhs, rhs in
            if lhs.regionCode != rhs.regionCode { return lhs.regionCode < rhs.regionCode }
            return lhs.sourceCode < rhs.sourceCode
        }
        return JourneySelectionResult(
            stops: stops,
            prompt: .ambiguousName(occurrenceID: occurrenceID, query: query, candidates: keys)
        )
    }

    private static func applyStation(
        occurrenceID: UUID,
        stationKey: StationKey,
        stops: [JourneyDraftStop],
        catalog: EditorCatalog
    ) -> JourneySelectionResult {
        guard let index = stops.firstIndex(where: { $0.occurrenceID == occurrenceID }) else {
            return JourneySelectionResult(stops: stops, prompt: nil)
        }
        guard let station = catalog.station(stationKey) else {
            return JourneySelectionResult(stops: stops, prompt: nil)
        }

        var next = stops
        var stop = next[index]
        let members = catalog.memberships(stationKey: stationKey)
        stop.displayName = station.name
        stop.stationKey = stationKey

        if let lineID = stop.lineID {
            if let member = members.first(where: {
                $0.lineID == lineID && $0.regionCode == stationKey.regionCode
            }) {
                stop.membershipID = member.membershipID
                stop.operatorID = operatorID(lineID: lineID, regionCode: stationKey.regionCode, catalog: catalog)
                stop.conflict = nil
                next[index] = stop
                return JourneySelectionResult(stops: next, prompt: nil)
            }
            stop.membershipID = nil
            stop.conflict = .stationNotOnLine(stationKey: stationKey, lineID: lineID)
            next[index] = stop
            return JourneySelectionResult(stops: next, prompt: nil)
        }

        if members.isEmpty {
            stop.membershipID = nil
            stop.conflict = nil
            next[index] = stop
            return JourneySelectionResult(stops: next, prompt: nil)
        }
        if members.count == 1, let member = members.first {
            stop.lineID = member.lineID
            stop.membershipID = member.membershipID
            stop.operatorID = operatorID(lineID: member.lineID, regionCode: member.regionCode, catalog: catalog)
            stop.conflict = nil
            next[index] = stop
            return JourneySelectionResult(stops: next, prompt: nil)
        }

        stop.lineID = nil
        stop.operatorID = nil
        stop.membershipID = nil
        stop.conflict = nil
        next[index] = stop
        return JourneySelectionResult(
            stops: next,
            prompt: .chooseLine(occurrenceID: occurrenceID, choices: lineChoices(members, catalog: catalog))
        )
    }

    private static func applyLine(
        occurrenceID: UUID,
        regionCode: String,
        lineID: String,
        stops: [JourneyDraftStop],
        catalog: EditorCatalog
    ) -> JourneySelectionResult {
        guard let index = stops.firstIndex(where: { $0.occurrenceID == occurrenceID }) else {
            return JourneySelectionResult(stops: stops, prompt: nil)
        }
        guard catalog.line(id: lineID, regionCode: regionCode) != nil else {
            return JourneySelectionResult(stops: stops, prompt: nil)
        }

        var next = stops
        var stop = next[index]
        let resolvedOperator = operatorID(lineID: lineID, regionCode: regionCode, catalog: catalog)
        guard let stationKey = stop.stationKey else {
            stop.lineID = lineID
            stop.operatorID = resolvedOperator
            stop.membershipID = nil
            stop.conflict = nil
            next[index] = stop
            return JourneySelectionResult(stops: next, prompt: nil)
        }

        if let member = catalog.memberships(stationKey: stationKey).first(where: {
            $0.lineID == lineID && $0.regionCode == regionCode && $0.regionCode == stationKey.regionCode
        }) {
            stop.lineID = lineID
            stop.operatorID = resolvedOperator
            stop.membershipID = member.membershipID
            stop.conflict = nil
            next[index] = stop
            return JourneySelectionResult(stops: next, prompt: nil)
        }

        stop.lineID = lineID
        stop.operatorID = resolvedOperator
        stop.membershipID = nil
        stop.conflict = .stationNotOnLine(stationKey: stationKey, lineID: lineID)
        next[index] = stop
        return JourneySelectionResult(stops: next, prompt: nil)
    }

    private static func applyUniqueSharedLine(
        _ stop: inout JourneyDraftStop, lineID: String, catalog: EditorCatalog
    ) {
        guard let stationKey = stop.stationKey else { return }
        if let existing = stop.lineID, existing != lineID {
            guard membership(stationKey: stationKey, lineID: existing, catalog: catalog) == nil else { return }
            stop.membershipID = nil
            stop.conflict = .stationNotOnLine(stationKey: stationKey, lineID: existing)
            return
        }
        guard let member = membership(stationKey: stationKey, lineID: lineID, catalog: catalog) else { return }
        stop.lineID = lineID
        stop.operatorID = operatorID(lineID: lineID, regionCode: stationKey.regionCode, catalog: catalog)
        stop.membershipID = member.membershipID
        stop.conflict = nil
    }

    private static func flagIfStationNotOnItsLine(_ stop: inout JourneyDraftStop, catalog: EditorCatalog) {
        guard let stationKey = stop.stationKey, let lineID = stop.lineID else { return }
        guard membership(stationKey: stationKey, lineID: lineID, catalog: catalog) == nil else { return }
        stop.membershipID = nil
        stop.conflict = .stationNotOnLine(stationKey: stationKey, lineID: lineID)
    }

    private static func membership(
        stationKey: StationKey, lineID: String, catalog: EditorCatalog
    ) -> StationLineMembership? {
        catalog.memberships(stationKey: stationKey).first {
            $0.lineID == lineID && $0.regionCode == stationKey.regionCode
        }
    }

    private static func operatorID(lineID: String, regionCode: String, catalog: EditorCatalog) -> String? {
        catalog.line(id: lineID, regionCode: regionCode)?.operatorIDs.first
    }

    private static func lineChoices(
        _ memberships: [StationLineMembership], catalog: EditorCatalog
    ) -> [LineChoice] {
        memberships.compactMap { member in
            guard let line = catalog.line(id: member.lineID, regionCode: member.regionCode) else { return nil }
            let operatorID = line.operatorIDs.first ?? ""
            let operatorName = catalog.operators(in: member.regionCode).first { $0.id == operatorID }?.name
                ?? operatorID
            return LineChoice(
                lineID: line.id,
                regionCode: line.regionCode,
                operatorID: operatorID,
                lineName: line.name,
                operatorName: operatorName
            )
        }
        .sorted { lhs, rhs in
            if lhs.operatorName != rhs.operatorName { return lhs.operatorName < rhs.operatorName }
            if lhs.lineName != rhs.lineName { return lhs.lineName < rhs.lineName }
            return lhs.lineID < rhs.lineID
        }
    }
}

public struct CatalogLinePreference: Hashable, Sendable {
    public var lineNames: [String]
    public var operatorNames: [String]
}

public enum CatalogLinePreferenceMapping {
    /// Selected catalog lines → names the existing route policy can store.
    /// lineNames unique, stable order by lineID. operatorNames unique official names, stable by operatorID.
    /// Skip unknown ids. Use catalog.line(id:regionCode:) and the operator's `name` (not shortName).
    public static func preferences(
        lineIDs: [String], regionCode: String, catalog: EditorCatalog
    ) -> CatalogLinePreference {
        let officialName = Dictionary(
            uniqueKeysWithValues: catalog.operators(in: regionCode).map { ($0.id, $0.name) })
        var seenIDs: Set<String> = []
        var lines: [CatalogLine] = []
        for id in lineIDs {
            guard seenIDs.insert(id).inserted else { continue }
            guard let line = catalog.line(id: id, regionCode: regionCode) else { continue }
            lines.append(line)
        }
        lines.sort { $0.id < $1.id }

        var lineNames: [String] = []
        var seenNames: Set<String> = []
        var operatorIDs: [String] = []
        var seenOperatorIDs: Set<String> = []
        for line in lines {
            if seenNames.insert(line.name).inserted { lineNames.append(line.name) }
            for operatorID in line.operatorIDs where seenOperatorIDs.insert(operatorID).inserted {
                operatorIDs.append(operatorID)
            }
        }
        operatorIDs.sort()

        var operatorNames: [String] = []
        var seenOperatorNames: Set<String> = []
        for operatorID in operatorIDs {
            guard let name = officialName[operatorID], !name.isEmpty else { continue }
            if seenOperatorNames.insert(name).inserted { operatorNames.append(name) }
        }
        return CatalogLinePreference(lineNames: lineNames, operatorNames: operatorNames)
    }

    /// Inverse. A line is selected when its name is in lineNames AND its official operator name is in operatorNames.
    /// If operatorNames is empty and exactly one line in the region has that name, select it.
    /// If operatorNames is empty and several lines share that name, select none of them; return the name in `unresolvedNames`.
    /// Names that match nothing go in `unresolvedNames` too.
    public static func matching(
        lineNames: [String], operatorNames: [String], regionCode: String, catalog: EditorCatalog
    ) -> (lineIDs: [String], unresolvedNames: [String]) {
        let regionLines = catalog.lines(in: regionCode)
        let officialName = Dictionary(
            uniqueKeysWithValues: catalog.operators(in: regionCode).map { ($0.id, $0.name) })
        let operatorSet = Set(operatorNames)
        var lineIDs: [String] = []
        var seenIDs: Set<String> = []
        var unresolvedNames: [String] = []
        var seenQueries: Set<String> = []

        for name in lineNames {
            guard seenQueries.insert(name).inserted else { continue }
            let named = regionLines.filter { $0.name == name }
            let hits: [CatalogLine]
            if operatorNames.isEmpty {
                hits = named.count == 1 ? named : []
            } else {
                hits = named.filter { line in
                    line.operatorIDs.contains { id in
                        guard let official = officialName[id], !official.isEmpty else { return false }
                        return operatorSet.contains(official)
                    }
                }
            }
            if hits.isEmpty {
                unresolvedNames.append(name)
            } else {
                for line in hits where seenIDs.insert(line.id).inserted {
                    lineIDs.append(line.id)
                }
            }
        }
        lineIDs.sort()
        return (lineIDs, unresolvedNames)
    }
}
