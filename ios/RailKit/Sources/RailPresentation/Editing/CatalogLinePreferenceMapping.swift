import Foundation
import RailCore

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
