import Foundation
import RailCore

/// Passenger text for a trip's ridden lines, formatted from
/// ``RiddenLineSequence`` only. `naming` turns one run into the name a reader
/// sees; the default is the run's passenger name.
public enum JourneyLineText {
    public typealias Naming = (RiddenLineSequence.Line) -> String

    public static let separator = " → "

    /// 「東北線 → 赤羽線 → 山手線」. Operator changes fold, so a 東海道線 that
    /// changes operator at 熱海 is shown once. Never the service caption.
    public static func summary(_ sequence: RiddenLineSequence, naming: Naming = defaultNaming) -> String {
        folded(sequence.summary, naming: naming).map(\.name).joined(separator: separator)
    }

    /// One section's runs in order, with its inner boundary stations:
    /// 「東横線 → みなとみらい線 (横浜)」.
    public static func section(
        _ sequence: RiddenLineSequence, index: Int, naming: Naming = defaultNaming
    ) -> String {
        guard let section = sequence.sections.first(where: { $0.sectionIndex == index }) else { return "" }
        return text((section.runs, section.boundaries), naming: naming)
    }

    /// Runs plus the stations where a shown name changes, for any run list.
    public static func text(
        _ runs: (runs: [RiddenLineSequence.Line], boundaries: [RiddenLineSequence.Boundary]),
        naming: Naming = defaultNaming
    ) -> String {
        let shown = folded(runs, naming: naming)
        let names = shown.map(\.name).joined(separator: separator)
        let stations = shown.compactMap { $0.boundary.flatMap(boundaryText) }
        return stations.isEmpty ? names : names + " (" + stations.joined(separator: "・") + ")"
    }

    /// First and last line: 「東北新幹線 → 北海道新幹線」, every line when
    /// there are at most three, else 「first → … → last」.
    public static func compact(_ sequence: RiddenLineSequence, naming: Naming = defaultNaming) -> String {
        let names = folded(sequence.summary, naming: naming).map(\.name)
        guard names.count > 3, let first = names.first, let last = names.last else {
            return names.joined(separator: separator)
        }
        return [first, "…", last].joined(separator: separator)
    }

    /// Number of distinct shown runs in the summary (after folding).
    public static func lineCount(_ sequence: RiddenLineSequence, naming: Naming = defaultNaming) -> Int {
        folded(sequence.summary, naming: naming).count
    }

    /// The boundary's station name, e.g. 「横浜」; nil when unknown.
    public static func boundaryText(_ boundary: RiddenLineSequence.Boundary) -> String? {
        guard let name = boundary.stationName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return name
    }

    public static func defaultNaming(_ line: RiddenLineSequence.Line) -> String {
        line.displayName()
    }

    /// Shown names with the boundary that introduced each one (nil for the
    /// first). Adjacent runs whose shown names are equal fold into one, which
    /// is how an operator change on one named line disappears.
    public static func folded(
        _ runs: (runs: [RiddenLineSequence.Line], boundaries: [RiddenLineSequence.Boundary]),
        naming: Naming = defaultNaming
    ) -> [(name: String, line: RiddenLineSequence.Line, boundary: RiddenLineSequence.Boundary?)] {
        var result: [(name: String, line: RiddenLineSequence.Line, boundary: RiddenLineSequence.Boundary?)] = []
        for (offset, line) in runs.runs.enumerated() {
            let name = naming(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if let last = result.last,
               TrainServiceBranding.canonicalLineName(last.name) == TrainServiceBranding.canonicalLineName(name) {
                continue
            }
            let boundary = result.isEmpty || offset == 0 || offset - 1 >= runs.boundaries.count
                ? nil : runs.boundaries[offset - 1]
            result.append((name, line, boundary))
        }
        return result
    }
}
