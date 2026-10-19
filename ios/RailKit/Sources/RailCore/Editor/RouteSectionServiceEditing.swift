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
    /// Applies one identity to every physical section in the recorded stop range.
    /// Existing identity outside the range and all station codes are preserved.
    /// Valid authored boundary chains stay exact; manually changed stop lists
    /// use the existing adjacent-pair fallback before their ranges are mapped.
    public static func applying(
        _ info: RouteSectionServiceInfo, to train: Train,
        fromStopIndex: Int, toStopIndex: Int
    ) -> Train {
        guard fromStopIndex >= 0, toStopIndex < train.stops.count,
              fromStopIndex < toStopIndex else { return train }
        let sections = sections(for: train)
        guard let mapping = RecordedRouteMapping(stops: train.stops, sections: sections),
              let sectionRange = mapping.sectionRange(fromStopIndex: fromStopIndex, toStopIndex: toStopIndex)
        else { return train }
        return updating(info, train: train, sections: sections, sectionRange: sectionRange)
    }

    /// Edits an existing service leg's exact physical span. Two legs can share
    /// an enclosing recorded interval while meeting at a source-only boundary.
    /// `toSectionIndex` is exclusive, matching JourneyServiceSections.Leg.
    public static func applying(
        _ info: RouteSectionServiceInfo, to train: Train,
        fromSectionIndex: Int, toSectionIndex: Int
    ) -> Train {
        let sections = sections(for: train)
        guard fromSectionIndex >= 0, fromSectionIndex < toSectionIndex,
              toSectionIndex <= sections.count else { return train }
        return updating(info, train: train, sections: sections, sectionRange: fromSectionIndex..<toSectionIndex)
    }

    private static func sections(for train: Train) -> [RouteSection] {
        let source = train.routeSections ?? []
        return RecordedRouteMapping(stops: train.stops, sections: source) != nil
            ? source : StoreOperations.rideRouteSections(for: train)
    }

    private static func updating(
        _ info: RouteSectionServiceInfo, train: Train, sections: [RouteSection], sectionRange: Range<Int>
    ) -> Train {
        var result = train
        var sections = sections
        let cleaned = RouteSectionServiceInfo(
            lineNames: info.lineNames, operatorNames: info.operatorNames,
            number: info.number, name: info.name)
        for index in sectionRange {
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
