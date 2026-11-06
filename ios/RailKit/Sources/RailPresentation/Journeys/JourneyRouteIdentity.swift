import Foundation
import RailCore

/// Service identity is independent of the railways a train travels over.
public enum JourneyRouteIdentity {
    /// Recorded names in section order, from ``RiddenLineSequence`` with no
    /// route evidence. Policy hints (alternative corridors that may never have
    /// been ridden) appear only when no section records a name.
    public static func recordedLineNames(of train: Train) -> [String] {
        unique(RiddenLineSequence(train: train, continuations: nil).summary.runs.map(\.name))
    }

    /// Recorded section names only, never policy hints.
    private static func recordedSectionLineNames(of train: Train) -> [String] {
        let sequence = RiddenLineSequence(train: train, continuations: nil)
        return unique(sequence.sections.filter { $0.source == .recorded }.flatMap(\.runs).map(\.name))
    }

    // MARK: - From the ridden line sequence

    /// Shown line names in travel order. Adjacent equal names fold (an
    /// operator change on one line); a line ridden again later stays.
    public static func lineNames(
        of sequence: RiddenLineSequence, naming: JourneyLineText.Naming = JourneyLineText.defaultNaming
    ) -> [String] {
        JourneyLineText.folded(sequence.summary, naming: naming).map(\.name)
    }

    /// Operators in travel order. A solved route names its own operators;
    /// otherwise the record's (section operators, else policy operators,
    /// then `company`) come first and derived runs add theirs.
    public static func operatorNames(of train: Train, sequence: RiddenLineSequence) -> [String] {
        guard !train.requiresRouteConfirmation else { return unique([train.company].compactMap { $0 }) }
        let runOperators = sequence.summary.runs.compactMap(\.operatorName)
        if sequence.hasSolvedSection { return unique(runOperators) }
        let sections = unique((train.routeSections ?? []).flatMap { $0.operatorNames ?? [] })
        let recorded = (sections.isEmpty ? train.routePolicy?.preferredOperatorNames ?? [] : sections)
            + [train.company].compactMap { $0 }
        return unique(recorded + runOperators)
    }

    public static func operatorIDs(of train: Train, sequence: RiddenLineSequence) -> [String] {
        operatorIDs(of: train, names: operatorNames(of: train, sequence: sequence))
    }

    public static func operatorLabels(
        of train: Train, sequence: RiddenLineSequence,
        language: String = OperatorIdentity.displayLanguage
    ) -> [String] {
        operatorLabels(of: train, names: operatorNames(of: train, sequence: sequence), language: language)
    }

    public static func operatorLogo(of train: Train, sequence: RiddenLineSequence) -> String? {
        operatorLogo(of: train, names: operatorNames(of: train, sequence: sequence))
    }

    // MARK: - From train-level detection

    public static func detectedApplies(_ train: Train, detected: [Statistics.TraversedLine]) -> Bool {
        !train.requiresRouteConfirmation && !detected.isEmpty
            && (detected.contains { $0.selectedLineID != nil }
                || TrainServiceBranding.usesDetectedLines(train) || recordedLineNames(of: train).isEmpty)
    }

    public static func lineNames(of train: Train, detected: [Statistics.TraversedLine]) -> [String] {
        guard !train.requiresRouteConfirmation else { return [] }
        if detected.contains(where: { $0.selectedLineID != nil }) {
            return unique(detected.map { line in
                line.selectedLineID.flatMap { RiddenLineSequence.passengerName(forLineID: $0) } ?? line.name
            })
        }
        let recorded = recordedLineNames(of: train)
        guard detectedApplies(train, detected: detected) else { return recorded }
        // Detection may cover only the loaded portion. Keep recorded legs
        // that detection doesn't already cover until the entire route has
        // finished resolving. Policy alternatives never contribute here —
        // only route sections that were actually ridden. Coverage compares
        // canonical forms so 東海道本線 and its detected 東海道線 count as
        // the same line.
        let observed = unique(detected.map(\.name))
        let observedCanonical = Set(observed.map(TrainServiceBranding.canonicalLineName))
        let sectionLines = recordedSectionLineNames(of: train)
        let uncovered = sectionLines.filter {
            observedCanonical.contains(TrainServiceBranding.canonicalLineName($0)) == false
        }
        return unique(observed + uncovered)
    }

    public static func operatorNames(of train: Train, detected: [Statistics.TraversedLine]) -> [String] {
        guard !train.requiresRouteConfirmation else { return unique([train.company].compactMap { $0 }) }
        if detected.contains(where: { $0.selectedLineID != nil }) {
            return unique(detected.compactMap(\.operatorName))
        }
        let sections = unique((train.routeSections ?? []).flatMap { $0.operatorNames ?? [] })
        let recorded = (sections.isEmpty ? train.routePolicy?.preferredOperatorNames ?? [] : sections)
            + [train.company].compactMap { $0 }
        return unique(recorded + (detectedApplies(train, detected: detected)
            ? detected.compactMap(\.operatorName) : []))
    }

    /// Operator ids for the recorded names, plus `train.operatorID` when set.
    /// A name that does not convert is omitted. With no registry, only `train.operatorID` remains.
    public static func operatorIDs(of train: Train, detected: [Statistics.TraversedLine] = []) -> [String] {
        operatorIDs(of: train, names: operatorNames(of: train, detected: detected))
    }

    private static func operatorIDs(of train: Train, names: [String]) -> [String] {
        var ids: [String] = []
        if let operatorID = train.operatorID, !operatorID.isEmpty { ids.append(operatorID) }
        if let more = train.operatorIDs { ids.append(contentsOf: more) }
        if let identity = identity(for: train) {
            for name in names {
                ids.append(contentsOf: identity.operatorIDs(forCatalogName: name))
            }
        }
        return unique(ids)
    }

    /// Facade label when the name converts. An unconverted name stays as stored text.
    /// `language` is the interface language (``OperatorIdentity/displayLanguage``
    /// by default): English shows each operator's English label where it has one.
    public static func operatorLabels(
        of train: Train, detected: [Statistics.TraversedLine] = [],
        language: String = OperatorIdentity.displayLanguage
    ) -> [String] {
        operatorLabels(of: train, names: operatorNames(of: train, detected: detected), language: language)
    }

    private static func operatorLabels(of train: Train, names: [String], language: String) -> [String] {
        if let operatorIDs = train.operatorIDs, !operatorIDs.isEmpty,
           let identity = identity(for: train) {
            return operatorIDs.map { identity.operatorLabel($0, language: language) ?? $0 }
        }
        guard let identity = identity(for: train) else { return names }
        return unique(names.flatMap { name -> [String] in
            let ids = identity.operatorIDs(forCatalogName: name)
            if ids.isEmpty { return [name] }
            return ids.map { identity.operatorLabel($0, language: language) ?? name }
        })
    }

    /// Logo for a known operator id, else the first catalog name that converts.
    public static func operatorLogo(of train: Train, detected: [Statistics.TraversedLine] = []) -> String? {
        operatorLogo(of: train, names: operatorNames(of: train, detected: detected))
    }

    private static func operatorLogo(of train: Train, names: [String]) -> String? {
        let identity = identity(for: train)
        if let operatorID = train.operatorID, let logo = identity?.operatorLogo(operatorID) { return logo }
        guard let identity else { return nil }
        for name in names {
            if let identifier = identity.operatorIDs(forCatalogName: name).first,
               let logo = identity.operatorLogo(identifier) {
                return logo
            }
        }
        return nil
    }

    private static func identity(for train: Train) -> RegistryIdentity? {
        guard let region = train.region, !region.isEmpty else { return nil }
        return RegistryIdentityCache.identity(forRegion: region)
    }

    /// A limited express never wears a line mark: it resolves the service mark
    /// for the trip date, then falls back to its operator's logo, then to the
    /// default train glyph (a nil result) — never to a line mark.
    public static func logoPath(
        for train: Train, lineLogo: @autoclosure () -> String?,
        operatorLogo: @autoclosure () -> String?
    ) -> String? {
        if TrainServiceBranding.isLimitedExpress(train) {
            return TrainServiceBranding.service(for: train)?.logoPath(on: train.date) ?? operatorLogo()
        }
        return lineLogo()
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
