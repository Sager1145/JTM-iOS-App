import Foundation

/// Checks on the new optional keys (`allStations`, `variants`) of the stop-pattern
/// catalogue. The same checks run in Python as
/// `ios/tools/build-shinkansen-patterns.py --check`; this is the Swift side, run
/// by the RailKit tests on any decoded catalogue.
///
/// Errors are rule breaks that make an answer unsafe. Warnings are conventions
/// that real data may break (odd/even direction, no partner coupling back): they
/// are reported and never change a lookup. The odd/even convention in particular
/// is never an error and never used for lookup.
public enum TrainPatternVariantsValidator {

    public enum Rule: String, Sendable, Hashable {
        case orderMismatch
        case stopNotInCorridor
        case allStationsIncomplete
        case allStationsWithOptionalStops
        case allStationsWithVariants
        case optionalOverlapsRequired
        case missingCitation
        case invalidDate
        case revisionOverlap
        case openEndedRevisionNotLast
        case revisionOutsideRecordDates
        case duplicatePatternID
        case endsOutOfOrder
        case endNotInOrder
        case callNotOptional
        case emptyNumbers
        case nonPositiveNumber
        case duplicateNumber
        case numberInTwoPatterns
        case groupOutsideRevision
        case coupledPartnerMissing
        case coupledPartnerNumbers
        case duplicateStopList
        case extraDates
        case verifiedWithoutOfficialSource
        case verifiedWithoutSecondReader
        // Warnings
        case parityConvention
        case coupledNotReciprocal
    }

    public enum Severity: String, Sendable, Hashable { case error, warning }

    public struct Violation: Sendable, Hashable, CustomStringConvertible {
        public let rule: Rule
        public let severity: Severity
        public let patternID: String
        public let message: String
        public var description: String { "\(severity.rawValue) \(rule.rawValue) \(patternID): \(message)" }
    }

    /// `corridor` returns the ordered stations (down order, from the record's
    /// origin to its destination or beyond) of a base record, or nil when it is
    /// not known; corridor-dependent checks are skipped then.
    public static func validate(
        _ catalogue: [TrainServicePatterns.Pattern],
        corridor: (TrainServicePatterns.Pattern) -> [TrainServicePatterns.Pattern.StationRef]? = { _ in nil }
    ) -> [Violation] {
        var out: [Violation] = []
        for base in catalogue where base.allStations || base.variants != nil {
            checkRecord(base, corridor: corridor(base), catalogue: catalogue, into: &out)
        }
        checkNumberConflicts(catalogue, into: &out)
        return out.sorted { ($0.patternID, $0.rule.rawValue, $0.message) < ($1.patternID, $1.rule.rawValue, $1.message) }
    }

    public static func errors(in violations: [Violation]) -> [Violation] {
        violations.filter { $0.severity == .error }
    }

    // MARK: Per record

    private typealias Pattern = TrainServicePatterns.Pattern
    private typealias Day = Pattern.GregorianDay

    private static func checkRecord(
        _ base: Pattern, corridor: [Pattern.StationRef]?, catalogue: [Pattern],
        into out: inout [Violation]
    ) {
        func add(_ rule: Rule, _ message: String, _ severity: Severity = .error) {
            out.append(Violation(rule: rule, severity: severity, patternID: base.id, message: message))
        }
        let required = base.stopRefs.map(\.sourceCode)
        let optional = base.optionalStopRefs.map(\.sourceCode)
        let corridorCodes = corridor?.map(\.sourceCode)

        if !Set(required).isDisjoint(with: optional) {
            add(.optionalOverlapsRequired, "a station is both always served and optional")
        }
        if let corridorCodes {
            for code in required + optional where !corridorCodes.contains(code) {
                add(.stopNotInCorridor, "\(code) is not a station of the record's corridor")
            }
        }

        if base.allStations {
            if !optional.isEmpty { add(.allStationsWithOptionalStops, "allStations record has optional stops") }
            if base.variants != nil { add(.allStationsWithVariants, "allStations record has variants") }
            if let corridorCodes,
               let low = corridorCodes.firstIndex(of: required.first ?? ""),
               let high = corridorCodes.firstIndex(of: required.last ?? ""), low <= high {
                if Array(corridorCodes[low...high]) != required {
                    add(.allStationsIncomplete, "stops are not every corridor station between the ends")
                }
            } else if corridorCodes != nil {
                add(.allStationsIncomplete, "ends are not on the corridor in order")
            }
        }

        guard let variants = base.variants else { return }
        checkOrder(variants, required: required, optional: optional, corridor: corridorCodes, add: add)
        checkRevisions(base, variants, add: add)
        let known = Set(variants.order)
        for revision in variants.revisions {
            checkPatterns(base, variants, revision, known: known, catalogue: catalogue, add: add)
        }
    }

    private static func checkOrder(
        _ variants: TrainServicePatterns.Variants, required: [String], optional: [String],
        corridor: [String]?, add: (Rule, String, Severity) -> Void
    ) {
        let expected = Set(required + optional)
        if Set(variants.order) != expected || variants.order.count != Set(variants.order).count {
            add(.orderMismatch, "order must hold exactly the always-served and optional stops, once each", .error)
        } else if let corridor {
            let sorted = variants.order.sorted {
                (corridor.firstIndex(of: $0) ?? .max) < (corridor.firstIndex(of: $1) ?? .max)
            }
            if sorted != variants.order {
                add(.orderMismatch, "order is not in corridor order", .error)
            }
        }
    }

    private static func checkRevisions(
        _ base: Pattern, _ variants: TrainServicePatterns.Variants,
        add: (Rule, String, Severity) -> Void
    ) {
        var windows: [(from: Day, until: Day?, name: String)] = []
        for revision in variants.revisions {
            let source = revision.source
            if [source.type, source.publisher, source.title, source.locator, source.accessedAt]
                .contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                add(.missingCitation, "revision \(revision.revision) has an incomplete source", .error)
            }
            if revision.status == .verified {
                if !TrainServicePatterns.Variants.Source.officialTypes.contains(source.type) {
                    add(.verifiedWithoutOfficialSource,
                        "revision \(revision.revision) is verified without an operator or printed timetable source", .error)
                }
                if (source.verifiedBy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    add(.verifiedWithoutSecondReader, "revision \(revision.revision) is verified without verifiedBy", .error)
                }
            }
            let from = Day(revision.validFrom)
            let until = revision.validUntil.flatMap(Day.init)
            let untilBroken = revision.validUntil != nil && until == nil
            let checkedBroken = revision.checkedOn != nil && Day(revision.checkedOn ?? "") == nil
            guard let from, !untilBroken, !checkedBroken else {
                add(.invalidDate, "revision \(revision.revision) has a malformed date", .error)
                continue
            }
            if let until, !(from < until) {
                add(.invalidDate, "revision \(revision.revision) ends before it starts", .error)
                continue
            }
            windows.append((from, until, revision.revision))
            if let recordFrom = base.validFrom.flatMap(Day.init), from < recordFrom {
                add(.revisionOutsideRecordDates, "revision \(revision.revision) starts before the record", .error)
            }
            if let recordUntil = base.validUntil.flatMap(Day.init) {
                if until == nil || until.map({ recordUntil < $0 }) == true {
                    add(.revisionOutsideRecordDates, "revision \(revision.revision) runs past the record", .error)
                }
            }
        }
        let sorted = windows.sorted { $0.from < $1.from }
        for (index, window) in sorted.enumerated() where index + 1 < sorted.count {
            let next = sorted[index + 1]
            guard let until = window.until else {
                add(.openEndedRevisionNotLast, "revision \(window.name) is open-ended but not the last", .error)
                continue
            }
            if next.from < until {
                add(.revisionOverlap, "revisions \(window.name) and \(next.name) overlap", .error)
            }
        }
    }

    private static func checkPatterns(
        _ base: Pattern, _ variants: TrainServicePatterns.Variants,
        _ revision: TrainServicePatterns.Variants.Revision, known: Set<String>,
        catalogue: [Pattern], add: (Rule, String, Severity) -> Void
    ) {
        let optional = Set(base.optionalStopRefs.map(\.sourceCode))
        var seen = Set<String>()
        var stopLists: [[String]: String] = [:]
        for variant in revision.patterns {
            let tag = "revision \(revision.revision) pattern \(variant.id)"
            if !seen.insert(variant.id).inserted {
                add(.duplicatePatternID, "\(tag): id repeats inside the revision", .error)
            }
            for end in [variant.from, variant.to].compactMap({ $0 }) where !known.contains(end) {
                add(.endNotInOrder, "\(tag): end \(end) is not in order", .error)
            }
            if let from = variant.from ?? variants.baseEndCodes(of: base)?.first,
               let to = variant.to ?? variants.baseEndCodes(of: base)?.last,
               let low = variants.order.firstIndex(of: from), let high = variants.order.firstIndex(of: to),
               low > high {
                add(.endsOutOfOrder, "\(tag): ends run against corridor order", .error)
            }
            for call in variant.calls where !optional.contains(call) {
                add(.callNotOptional, "\(tag): call \(call) is not an optional stop of the record", .error)
            }
            if variant.trains.isEmpty || variant.trains.contains(where: { $0.numbers.isEmpty }) {
                add(.emptyNumbers, "\(tag): a pattern or group lists no train numbers", .error)
            }
            let codes = variants.stopCodes(of: variant, in: base)
            if !codes.isEmpty, let first = stopLists.updateValue(variant.id, forKey: codes) {
                add(.duplicateStopList, "\(tag): same stop list as pattern \(first); list its trains as groups of one pattern", .error)
            }
            for group in variant.trains {
                checkGroup(group, tag: tag, revision: revision, add: add)
                checkCoupling(group, base: base, tag: tag, catalogue: catalogue, add: add)
            }
        }
    }

    private static func checkCoupling(
        _ group: TrainServicePatterns.Variants.TrainGroup, base: Pattern, tag: String,
        catalogue: [Pattern], add: (Rule, String, Severity) -> Void
    ) {
        guard let coupled = group.coupled else { return }
        if let number = coupled.number, number != "same" || coupled.partnerNumbers != nil {
            add(.coupledPartnerNumbers, "\(tag): coupled number must be \"same\" and then no partnerNumbers", .error)
        }
        if let partnerNumbers = coupled.partnerNumbers,
           partnerNumbers.contains(where: { key, value in
               value <= 0 || !group.numbers.contains(where: { String($0) == key })
           }) {
            add(.coupledPartnerNumbers, "\(tag): partnerNumbers must map numbers of this group to positive numbers", .error)
        }
        let partners = catalogue.filter { $0.serviceId == coupled.service }
        let partnerCodes = Set(partners.flatMap { ($0.stopRefs + $0.optionalStopRefs).map(\.sourceCode) })
        if partners.isEmpty || !partnerCodes.contains(coupled.from) || !partnerCodes.contains(coupled.to) {
            add(.coupledPartnerMissing, "\(tag): coupled partner \(coupled.service) or its stations do not exist", .error)
        } else if !partners.contains(where: { partner in
            partner.variants?.revisions.contains { rev in
                rev.patterns.contains { $0.trains.contains { $0.coupled?.service == base.serviceId } }
            } ?? false
        }) {
            add(.coupledNotReciprocal, "\(tag): \(coupled.service) does not couple back", .warning)
        }
    }

    private static func checkGroup(
        _ group: TrainServicePatterns.Variants.TrainGroup, tag: String,
        revision: TrainServicePatterns.Variants.Revision, add: (Rule, String, Severity) -> Void
    ) {
        if group.numbers.contains(where: { $0 <= 0 }) {
            add(.nonPositiveNumber, "\(tag): train numbers must be positive", .error)
        }
        if Set(group.numbers).count != group.numbers.count {
            add(.duplicateNumber, "\(tag): a number is listed twice in one group", .error)
        }
        let groupFrom = group.validFrom.flatMap(Day.init)
        let groupUntil = group.validUntil.flatMap(Day.init)
        if (group.validFrom != nil && groupFrom == nil) || (group.validUntil != nil && groupUntil == nil) {
            add(.invalidDate, "\(tag): a group has a malformed date", .error)
        } else if let revisionFrom = Day(revision.validFrom) {
            let revisionUntil = revision.validUntil.flatMap(Day.init)
            if let groupFrom, groupFrom < revisionFrom {
                add(.groupOutsideRevision, "\(tag): a group starts before its revision", .error)
            }
            if let groupUntil, let revisionUntil, revisionUntil < groupUntil {
                add(.groupOutsideRevision, "\(tag): a group runs past its revision", .error)
            }
        }
        // Explicit dates: required for extra trains, not allowed otherwise, each a
        // real date inside the revision and the group's window.
        if group.runs == .extra {
            let parsed = group.dates?.map { ($0, Day($0)) } ?? []
            if parsed.isEmpty {
                add(.extraDates, "\(tag): an extra group must list the exact dates it runs", .error)
            }
            if parsed.contains(where: { $0.1 == nil }) {
                add(.invalidDate, "\(tag): an extra date is malformed", .error)
            }
            let days = parsed.compactMap(\.1)
            if Set(days.map(\.rawValue)).count != days.count {
                add(.extraDates, "\(tag): an extra date is listed twice", .error)
            }
            if days.contains(where: { !revision.covers($0.rawValue) || !group.windowCovers($0) }) {
                add(.groupOutsideRevision, "\(tag): an extra date lies outside its revision or window", .error)
            }
        } else if group.dates != nil {
            add(.extraDates, "\(tag): dates are only for extra groups", .error)
        }
        if let days = group.daysOfWeek, days.isEmpty || Set(days).count != days.count {
            add(.extraDates, "\(tag): daysOfWeek must list each weekday once", .error)
        }
        // Convention only: odd numbers down, even numbers up. Never an error, never
        // used for lookup.
        let expectedOdd = group.direction == .down
        if group.numbers.contains(where: { ($0 % 2 == 1) != expectedOdd }) {
            add(.parityConvention, "\(tag): some \(group.direction.rawValue) numbers break the odd/even convention", .warning)
        }
    }

    // MARK: Number conflicts across patterns

    private typealias Revision = TrainServicePatterns.Variants.Revision
    private typealias Group = TrainServicePatterns.Variants.TrainGroup

    /// A number may map to different patterns on different days, but only when
    /// the days provably do not intersect: the revisions and group windows are
    /// disjoint, the weekday sets or day types are (weekdays vs holidays), or the
    /// explicit dates do not meet the other group. Two groups of the same
    /// pattern (same base record, revision, pattern and direction) never
    /// conflict: they give one answer. Records are grouped by every key a
    /// lookup can match (name and service id), so two services sharing a service
    /// id are compared too.
    private static func checkNumberConflicts(_ catalogue: [Pattern], into out: inout [Violation]) {
        struct Entry {
            let base: Pattern; let revision: Revision
            let variant: String; let group: Group
            var identity: String { "\(base.id)|\(revision.revision)|\(variant)|\(group.direction.rawValue)" }
        }
        var byKey: [String: [Int: [Entry]]] = [:]
        for base in catalogue {
            for revision in base.variants?.revisions ?? [] {
                for variant in revision.patterns {
                    for group in variant.trains {
                        for number in Set(group.numbers) {
                            for key in TrainServicePatterns.serviceKeys(of: base) {
                                byKey[key, default: [:]][number, default: []].append(
                                    Entry(base: base, revision: revision, variant: variant.id, group: group))
                            }
                        }
                    }
                }
            }
        }
        var reported = Set<String>()
        for (key, numbers) in byKey {
            for (number, entries) in numbers where entries.count > 1 {
                for i in entries.indices {
                    for j in entries.indices where j > i {
                        let a = entries[i], b = entries[j]
                        guard a.identity != b.identity,
                              !disjointDays(a.revision, a.group, b.revision, b.group) else { continue }
                        let ids = [a.identity, b.identity].sorted()
                        guard reported.insert("\(number)|\(ids[0])|\(ids[1])").inserted else { continue }
                        out.append(Violation(
                            rule: .numberInTwoPatterns, severity: .error, patternID: a.base.id,
                            message: "\(key) \(number) is listed in \(a.base.id)/\(a.revision.revision)/\(a.variant) and \(b.base.id)/\(b.revision.revision)/\(b.variant) on overlapping days"))
                    }
                }
            }
        }
    }

    /// Could `group` of `revision` run on `day` for some day type?
    private static func couldRun(_ revision: Revision, _ group: Group, on day: Day) -> Bool {
        revision.covers(day.rawValue) && group.applies(on: day, dayKind: nil) != .no
    }

    private static func disjointDays(_ ra: Revision, _ ga: Group, _ rb: Revision, _ gb: Group) -> Bool {
        if (ga.runs == .weekdays && gb.runs == .holidays) || (ga.runs == .holidays && gb.runs == .weekdays) {
            return true
        }
        if let da = ga.daysOfWeek, let db = gb.daysOfWeek, Set(da).isDisjoint(with: db) { return true }
        for (dated, other, otherRevision) in [(ga, gb, rb), (gb, ga, ra)] where dated.runs == .extra {
            let days = dated.dates?.compactMap(Day.init) ?? []
            if !days.contains(where: { couldRun(otherRevision, other, on: $0) }) { return true }
        }
        func interval(_ r: Revision, _ g: Group) -> (String, String?) {
            let from = max(r.validFrom, g.validFrom ?? r.validFrom)
            let untils = [r.validUntil, g.validUntil].compactMap { $0 }
            return (from, untils.min())
        }
        let (fa, ua) = interval(ra, ga), (fb, ub) = interval(rb, gb)
        if let ua, ua <= fb { return true }
        if let ub, ub <= fa { return true }
        return false
    }
}
