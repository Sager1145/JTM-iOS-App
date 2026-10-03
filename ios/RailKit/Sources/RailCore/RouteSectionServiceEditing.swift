import Foundation

/// Passenger service identity for one portion of a through-running train.
/// Line and operator names retain the route section's existing routing meaning.
public struct RouteSectionServiceInfo: Equatable, Sendable {
    public var lineNames: [String]
    public var operatorNames: [String]
    public var number: String?
    public var name: String?

    public init(
        lineNames: [String] = [], operatorNames: [String] = [],
        number: String? = nil, name: String? = nil
    ) {
        self.lineNames = Self.names(lineNames)
        self.operatorNames = Self.names(operatorNames)
        self.number = Self.text(number)
        self.name = Self.text(name)
    }

    public init(section: RouteSection) {
        self.init(lineNames: section.lineNames ?? [], operatorNames: section.operatorNames ?? [],
                  number: section.number, name: section.name)
    }

    public var isEmpty: Bool {
        lineNames.isEmpty && operatorNames.isEmpty && number == nil && name == nil
    }

    private static func text(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func names(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap(text).filter { seen.insert($0).inserted }
    }
}

public enum RouteSectionServiceEditing {
    /// Applies one identity to the adjacent stop pairs in the selected range.
    /// Existing identity outside the range and all station codes are preserved.
    /// Rebuilding by stop pair first prevents a reordered stop list assigning a
    /// previous operator's number to a different stretch of railway.
    public static func applying(
        _ info: RouteSectionServiceInfo, to train: Train,
        fromStopIndex: Int, toStopIndex: Int
    ) -> Train {
        guard fromStopIndex >= 0, toStopIndex < train.stops.count,
              fromStopIndex < toStopIndex else { return train }
        var result = train
        var sections = StoreOperations.rideRouteSections(for: train)
        let cleaned = RouteSectionServiceInfo(
            lineNames: info.lineNames, operatorNames: info.operatorNames,
            number: info.number, name: info.name)
        for index in fromStopIndex..<toStopIndex {
            // Stable physical identities constrain the old line and operator.
            // A manual route change must not leave those constraints pointing
            // to a different corridor; number/name-only edits retain them.
            if (sections[index].lineNames ?? []) != cleaned.lineNames
                || (sections[index].operatorNames ?? []) != cleaned.operatorNames {
                sections[index].lineIDs = nil
                sections[index].sectionCodes = nil
            }
            sections[index].lineNames = cleaned.lineNames.isEmpty ? nil : cleaned.lineNames
            sections[index].operatorNames = cleaned.operatorNames.isEmpty ? nil : cleaned.operatorNames
            sections[index].number = cleaned.number
            sections[index].name = cleaned.name
        }
        result.routeSections = sections
        return result
    }
}
