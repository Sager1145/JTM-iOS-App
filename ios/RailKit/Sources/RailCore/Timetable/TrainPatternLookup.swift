import Foundation

// Lookup over the stop-pattern variants of ``TrainServicePatterns``. Pure and
// read-only. See TrainPatternVariants.swift for the ground rule: nothing here
// infers a stop pattern from a train number.
//
// Rules, all enforced below:
// - A number is matched exactly, by value, in the revisions that cover the
//   ride date. There is no interpolation, no extrapolation, and no use of
//   neighbouring numbers, number blocks, odd/even parity or another revision's
//   table. A number that is not listed answers "pattern not known" with the base
//   records, even when its neighbours are listed.
// - If the number is listed in several patterns that all apply on the date
//   (conflicting data), the answer is "pattern not known" (`ambiguous`), never a
//   pick.
// - A service answers `allStations` only when every applicable base record of it
//   is flagged `allStations`; then no number is needed.

extension TrainServicePatterns {

    /// The natural key a timed train would later share with a stop pattern:
    /// service, public number, ride date. This is the seam for optional
    /// per-train times (design point 4): a timed-train source keyed by
    /// ``TrainKey`` can be consulted before a pattern; nothing in this file reads
    /// or stores times.
    public struct TrainKey: Sendable, Hashable {
        public let serviceId: String
        public let number: Int
        public let day: String
    }

    /// An exact answer: one pattern of one revision that lists the number.
    public struct ExactMatch: Sendable, Hashable {
        public let base: Pattern
        public let revision: Variants.Revision
        public let variant: Variants.Variant
        public let group: Variants.TrainGroup
        public let trainKey: TrainKey
        /// The pattern's stations in the train's travel order (reversed for `up`).
        public let stops: [Pattern.StationRef]

        public var direction: Variants.Direction { group.direction }
        public var coupled: Variants.Coupling? { variant.coupled }
        public var isExtraTrain: Bool { group.runs == .extra }
        /// The revision was transcribed from a source read twice.
        public var isVerified: Bool { revision.status == .verified }
        /// An open-ended revision queried for a date after it was last confirmed
        /// in force: numbers are re-allocated at each revision, so it is stale.
        public var dateIsAfterLastCheck: Bool {
            guard revision.validUntil == nil else { return false }
            guard let checked = revision.checkedOn.flatMap(Pattern.GregorianDay.init),
                  let day = Pattern.GregorianDay(trainKey.day)
            else { return true }
            return day > checked
        }
        public var isChecked: Bool { isVerified && !dateIsAfterLastCheck }
    }

    public enum NotKnownReason: Sendable, Hashable {
        /// No service of that name.
        case unknownService
        /// A number needs a ride date to pick a revision; none was given.
        case noDate
        /// No revision of the service covers the date (or the date is malformed),
        /// or the service has no variants at all.
        case noTableForDate
        /// Revisions cover the date but the number is listed in none of them
        /// (for the day type asked, if known).
        case notListed
        /// The number is listed in more than one pattern that applies on the date.
        case ambiguous
    }

    public enum Resolution: Sendable, Hashable {
        case exact(ExactMatch)
        /// Every train of the service calls at every station of the record.
        case allStations(bases: [Pattern])
        /// The base records to choose from; never a confident stop list.
        case notKnown(NotKnownReason, bases: [Pattern])
    }

    /// One pattern of a service on a date, for browsing without a number.
    public struct PatternSummary: Sendable, Hashable, Identifiable {
        public var id: String { "\(base.id)@\(revision.revision)#\(variant.id)" }
        public let base: Pattern
        public let revision: Variants.Revision
        public let variant: Variants.Variant
        /// Stations in down order.
        public let stops: [Pattern.StationRef]
        /// Optional stops this pattern serves that not every listed pattern of
        /// the same base record and revision serves (the stops that differ).
        public let extraStops: [Pattern.StationRef]
        /// Distinct numbers across non-extra groups (counted, not ranked by rule).
        public let trainCount: Int
        /// The lowest listed numbers, for display.
        public let exampleNumbers: [Int]
    }

    /// A service that calls at both of two stations.
    public struct ServiceCall: Sendable, Hashable {
        public let serviceName: String
        public let bases: [Pattern]
        /// Either station is an optional stop in every record that has both.
        public let someTrains: Bool
        /// Direction origin to destination when the record's own order is known.
        public let direction: Variants.Direction?
    }

    // MARK: Service name

    static func normalizedServiceName(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Base records whose displayed name or service id equals `name`
    /// (case-insensitive, full-width folded): "のぞみ", "Nozomi", "nozomi".
    public static func baseRecords(
        named name: String, in catalogue: [Pattern] = patterns
    ) -> [Pattern] {
        let wanted = normalizedServiceName(name)
        guard !wanted.isEmpty else { return [] }
        return catalogue.filter {
            normalizedServiceName($0.name) == wanted || $0.serviceId.lowercased() == wanted
        }
    }

    private static func applicable(_ bases: [Pattern], on day: String?) -> [Pattern] {
        guard let day else { return bases }
        return bases.filter { $0.applicability(on: day) != .notApplicable }
    }

    // MARK: (service, number, date) -> answer

    /// Exact lookup on (service name, train number, date, optional day type).
    public static func resolve(
        serviceName: String, number: Int, day: String?, dayKind: Variants.DayKind? = nil,
        in catalogue: [Pattern] = patterns
    ) -> Resolution {
        let named = baseRecords(named: serviceName, in: catalogue)
        guard !named.isEmpty else { return .notKnown(.unknownService, bases: []) }
        let bases = applicable(named, on: day)
        guard !bases.isEmpty else { return .notKnown(.noTableForDate, bases: named) }
        if bases.allSatisfy(\.allStations) { return .allStations(bases: bases) }
        guard let day else { return .notKnown(.noDate, bases: bases) }
        guard let parsedDay = Pattern.GregorianDay(day) else {
            return .notKnown(.noTableForDate, bases: bases)
        }

        var covered = false
        var matches: [ExactMatch] = []
        for base in bases where !base.allStations {
            guard let variants = base.variants else { continue }
            for revision in variants.revisions where revision.covers(day) {
                covered = true
                for variant in revision.patterns {
                    for group in variant.trains
                    where group.numbers.contains(number)
                        && group.windowCovers(parsedDay)
                        && runs(group.runs, on: dayKind) {
                        matches.append(ExactMatch(
                            base: base, revision: revision, variant: variant, group: group,
                            trainKey: TrainKey(serviceId: base.serviceId, number: number, day: day),
                            stops: stops(of: variant, in: base, variants: variants, direction: group.direction)))
                    }
                }
            }
        }
        guard covered else { return .notKnown(.noTableForDate, bases: bases) }
        guard let first = matches.first else { return .notKnown(.notListed, bases: bases) }
        let distinct = Set(matches.map {
            "\($0.base.id)|\($0.revision.revision)|\($0.variant.id)|\($0.group.direction.rawValue)"
        })
        return distinct.count == 1 ? .exact(first) : .notKnown(.ambiguous, bases: bases)
    }

    private static func runs(_ runs: Variants.RunDay, on kind: Variants.DayKind?) -> Bool {
        switch (runs, kind) {
        case (.daily, _), (.extra, _), (_, nil): true
        case (.weekdays, .weekday), (.holidays, .holiday): true
        default: false
        }
    }

    private static func stops(
        of variant: Variants.Variant, in base: Pattern, variants: Variants,
        direction: Variants.Direction
    ) -> [Pattern.StationRef] {
        let refs = Dictionary(
            (base.stopRefs + base.optionalStopRefs).map { ($0.sourceCode, $0) },
            uniquingKeysWith: { first, _ in first })
        let down = variants.stopCodes(of: variant, in: base).compactMap { refs[$0] }
        return direction == .down ? down : down.reversed()
    }

    // MARK: (service) -> patterns

    /// The patterns of a service on `day`, most listed numbers first (ties by
    /// base record, revision and pattern id so the order is stable). Only
    /// revisions covering `day` are read; with no day, or a day no revision
    /// covers, the result is empty because a number table means nothing without
    /// its date. Base records with no variants contribute nothing.
    public static func patternSummaries(
        serviceName: String, day: String?, in catalogue: [Pattern] = patterns
    ) -> [PatternSummary] {
        guard let day, Pattern.GregorianDay(day) != nil else { return [] }
        var summaries: [PatternSummary] = []
        for base in applicable(baseRecords(named: serviceName, in: catalogue), on: day)
        where !base.allStations {
            guard let variants = base.variants else { continue }
            let refs = Dictionary(
                (base.stopRefs + base.optionalStopRefs).map { ($0.sourceCode, $0) },
                uniquingKeysWith: { first, _ in first })
            for revision in variants.revisions where revision.covers(day) {
                let common = revision.patterns.map { Set($0.calls) }
                    .reduce(nil as Set<String>?) { $0?.intersection($1) ?? $1 } ?? []
                for variant in revision.patterns {
                    let numbers = Set(variant.trains.filter { $0.runs != .extra }.flatMap(\.numbers))
                    let extra = Set(variant.calls).subtracting(common)
                    summaries.append(PatternSummary(
                        base: base, revision: revision, variant: variant,
                        stops: variants.stopCodes(of: variant, in: base).compactMap { refs[$0] },
                        extraStops: variants.order.filter(extra.contains).compactMap { refs[$0] },
                        trainCount: numbers.count,
                        exampleNumbers: Array(numbers.sorted().prefix(3))))
                }
            }
        }
        return summaries.sorted {
            ($1.trainCount, $0.base.id, $0.revision.revision, $0.variant.id)
                < ($0.trainCount, $1.base.id, $1.revision.revision, $1.variant.id)
        }
    }

    // MARK: (origin, destination) -> services

    /// Services with a base record whose stops or optional stops contain both
    /// stations (station codes: the Shinkansen row's identity), by service name.
    public static func servicesCalling(
        at originCode: String, and destinationCode: String, day: String? = nil,
        in catalogue: [Pattern] = patterns
    ) -> [ServiceCall] {
        guard originCode != destinationCode else { return [] }
        var byName: [String: [Pattern]] = [:]
        for base in applicable(catalogue, on: day) {
            let required = Set(base.stopRefs.map(\.sourceCode))
            let all = required.union(base.optionalStopRefs.map(\.sourceCode))
            if all.contains(originCode), all.contains(destinationCode) {
                byName[base.name, default: []].append(base)
            }
        }
        return byName.keys.sorted().map { name in
            let bases = byName[name] ?? []
            let someTrains = bases.allSatisfy { base in
                let required = Set(base.stopRefs.map(\.sourceCode))
                return !required.contains(originCode) || !required.contains(destinationCode)
            }
            let direction = bases.lazy.compactMap { direction(from: originCode, to: destinationCode, in: $0) }.first
            return ServiceCall(serviceName: name, bases: bases, someTrains: someTrains, direction: direction)
        }
    }

    private static func direction(
        from origin: String, to destination: String, in base: Pattern
    ) -> Variants.Direction? {
        let sequence: [String]
        if let order = base.variants?.order {
            sequence = order
        } else if base.allStations {
            sequence = base.stopRefs.map(\.sourceCode)
        } else {
            return nil
        }
        guard let a = sequence.firstIndex(of: origin), let b = sequence.firstIndex(of: destination)
        else { return nil }
        return a < b ? .down : .up
    }
}
