import Foundation
import Testing
@testable import RailCore

// SAMPLE DATA ONLY. Every service, station and train number in this file is
// synthetic (service "サンプル", stations 甲…辛, numbers 90xx) and says nothing
// about any real train. The real per-number tables are filled from cited
// timetables elsewhere; none is bundled by this change.

private typealias Pattern = TrainServicePatterns.Pattern
private typealias Variants = TrainServicePatterns.Variants

private enum Sample {
    static let names = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛"]
    static func ref(_ index: Int) -> String {
        #"{"name": "\#(names[index - 1])", "sourceCode": "S0\#(index)"}"#
    }
    static func refs(_ indexes: [Int]) -> String { "[" + indexes.map(ref).joined(separator: ",") + "]" }
    static let corridor: [Pattern.StationRef] = (1...8).map {
        .init(name: names[$0 - 1], sourceCode: "S0\($0)")
    }

    /// Revision 1 (2030-03-01 to 2031-03-01, verified) and revision 2 (open,
    /// unverified). Deliberately not following any parity or block logic:
    /// 9004 is a down train, 9003-9005 is a consecutive range, 9001 is a
    /// different pattern in revision 2, 9021 differs between weekdays and holidays.
    static let revisions = #"""
    [
      {"revision": "2030-03-01", "validFrom": "2030-03-01", "validUntil": "2031-03-01",
       "checkedOn": "2030-06-01", "status": "verified", "citation": "SAMPLE citation one",
       "patterns": [
         {"id": "a", "calls": ["S04"], "trains": [
            {"direction": "down", "numbers": [9001, "9003-9005"]},
            {"direction": "up", "numbers": [9002]}]},
         {"id": "b", "to": "S06", "calls": ["S02"], "trains": [
            {"direction": "down", "numbers": [9011]},
            {"direction": "up", "numbers": [9014]}]},
         {"id": "c", "calls": [], "trains": [
            {"direction": "down", "numbers": [9021], "runs": "weekdays"}]},
         {"id": "d", "calls": ["S05"], "trains": [
            {"direction": "down", "numbers": [9021], "runs": "holidays"}]}
       ]},
      {"revision": "2031-03-01", "validFrom": "2031-03-01", "validUntil": null,
       "checkedOn": "2031-04-01", "status": "unverified", "citation": "SAMPLE citation two",
       "patterns": [
         {"id": "a", "calls": ["S05"], "trains": [{"direction": "down", "numbers": [9001]}]}
       ]}
    ]
    """#

    static func variantBase(
        revisions: String = revisions, order: String = #"["S01","S02","S03","S04","S05","S06","S07","S08"]"#,
        extra: String = ""
    ) -> String {
        #"""
        {"patternId": "sample-x-all", "serviceId": "sample-x", "name": "サンプル", "company": "SAMPLE",
         "label": "甲〜辛", "origin": "甲", "destination": "辛",
         "stops": \#(refs([1, 3, 6, 8])), "optionalStops": \#(refs([2, 4, 5, 7])), "via": [],
         "lines": ["サンプル線"], "validFrom": "2030-01-01", "validUntil": null\#(extra),
         "variants": {"schema": 1, "order": \#(order), "revisions": \#(revisions)}}
        """#
    }

    static let allStationsBase = #"""
    {"patternId": "sample-all-all", "serviceId": "sample-all", "name": "サンプル各停", "company": "SAMPLE",
     "label": "甲〜辛", "origin": "甲", "destination": "辛", "allStations": true,
     "stops": \#(refs(Array(1...8))), "optionalStops": [], "via": [], "lines": ["サンプル線"]}
    """#

    static func decode(_ records: String...) throws -> [Pattern] {
        try JSONDecoder().decode([Pattern].self, from: Data(("[" + records.joined(separator: ",") + "]").utf8))
    }
    static func catalogue(_ base: String = variantBase()) throws -> [Pattern] {
        try decode(base, allStationsBase)
    }
}

struct TrainPatternVariantsTests {

    // MARK: - decoder

    @Test("variants and allStations survive an encode/decode round trip, numbers explicit")
    func roundTrip() throws {
        let original = try Sample.catalogue()
        let data = try JSONEncoder().encode(original)
        let again = try JSONDecoder().decode([Pattern].self, from: data)
        #expect(again == original)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("9003,9004,9005"), "the range is stored as explicit numbers")
        #expect(!text.contains("9003-9005"))
        #expect(again[1].allStations)
        #expect(again[0].variants?.revisions.count == 2)
    }

    @Test("records without the new keys load unchanged; the real bundled file has none yet")
    func backwardsCompatible() throws {
        let plain = try Sample.decode(#"""
        {"patternId": "p", "serviceId": "s", "name": "n", "company": "c", "label": "l",
         "origin": "甲", "destination": "乙", "stops": \#(Sample.refs([1, 2])), "optionalStops": [], "via": []}
        """#)
        #expect(plain[0].allStations == false)
        #expect(plain[0].variants == nil)
        let encoded = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!encoded.contains("allStations") && !encoded.contains("variants"))

        let bundled = TrainServicePatterns.patterns
        #expect(TrainServicePatterns.catalogFailure == nil)
        #expect(bundled.count >= 338)
        // When the data branches land and add records with these keys, this
        // pin should be replaced by the strict validator run (see VERIFICATION.md).
        #expect(bundled.allSatisfy { !$0.allStations && $0.variants == nil })
    }

    @Test("a variants block with an unknown schema reads as no variants")
    func unknownSchemaIgnored() throws {
        let future = Sample.variantBase().replacingOccurrences(of: #""schema": 1"#, with: #""schema": 2"#)
        #expect(try Sample.decode(future)[0].variants == nil)
    }

    @Test("malformed numbers, a missing status and a missing citation key are refused at decode")
    func malformedBlocksThrow() {
        for bad in [
            Sample.revisions.replacingOccurrences(of: "9003-9005", with: "9005-9003"),
            Sample.revisions.replacingOccurrences(of: "9003-9005", with: "9003-9999999"),
            Sample.revisions.replacingOccurrences(of: "9003-9005", with: "odd"),
            Sample.revisions.replacingOccurrences(of: #""status": "verified", "#, with: ""),
            Sample.revisions.replacingOccurrences(of: #""citation": "SAMPLE citation one","#, with: ""),
        ] {
            #expect(throws: (any Error).self) { try Sample.decode(Sample.variantBase(revisions: bad)) }
        }
    }

    @Test("a status other than verified is read as unverified")
    func unknownStatusIsUnverified() throws {
        let weird = Sample.revisions.replacingOccurrences(of: #""status": "verified""#, with: #""status": "probably""#)
        let base = try Sample.decode(Sample.variantBase(revisions: weird))[0]
        #expect(base.variants?.revisions[0].status == .unverified)
    }

    // MARK: - lookup: (service, number, date)

    private func exact(_ resolution: TrainServicePatterns.Resolution) -> TrainServicePatterns.ExactMatch? {
        if case .exact(let match) = resolution { return match }
        return nil
    }

    private func reason(_ resolution: TrainServicePatterns.Resolution) -> TrainServicePatterns.NotKnownReason? {
        if case .notKnown(let reason, _) = resolution { return reason }
        return nil
    }

    @Test("a listed number gives its exact pattern, direction and stops in travel order")
    func exactAnswer() throws {
        let patterns = try Sample.catalogue()
        let down = try #require(exact(TrainServicePatterns.resolve(
            serviceName: "サンプル", number: 9001, day: "2030-05-01", in: patterns)))
        #expect(down.variant.id == "a" && down.direction == .down)
        #expect(down.stops.map(\.sourceCode) == ["S01", "S03", "S04", "S06", "S08"])
        #expect(down.isChecked && down.isVerified && !down.dateIsAfterLastCheck)
        #expect(down.trainKey == .init(serviceId: "sample-x", number: 9001, day: "2030-05-01"))

        let up = try #require(exact(TrainServicePatterns.resolve(
            serviceName: "サンプル", number: 9002, day: "2030-05-01", in: patterns)))
        #expect(up.direction == .up)
        #expect(up.stops.map(\.sourceCode) == ["S08", "S06", "S04", "S03", "S01"])

        let cut = try #require(exact(TrainServicePatterns.resolve(
            serviceName: "サンプル", number: 9011, day: "2030-05-01", in: patterns)))
        #expect(cut.stops.map(\.sourceCode) == ["S01", "S02", "S03", "S06"], "ends at S06, a pattern with `to`")
    }

    @Test("range shorthand matches each expanded number and nothing beside it")
    func rangeExpandsToExplicitNumbers() throws {
        let patterns = try Sample.catalogue()
        for number in [9003, 9004, 9005] {
            #expect(exact(TrainServicePatterns.resolve(
                serviceName: "サンプル", number: number, day: "2030-05-01", in: patterns))?.variant.id == "a")
        }
        // Neighbours, a gap in parity and a block edge are all unlisted.
        for number in [9000, 9006, 9007, 9010, 9012, 9013, 9022, 1] {
            let answer = TrainServicePatterns.resolve(
                serviceName: "サンプル", number: number, day: "2030-05-01", in: patterns)
            #expect(reason(answer) == .notListed, "\(number) must not be inferred")
        }
    }

    @Test("direction is the stored one, not odd/even: a listed even down train is down")
    func directionIsStoredNotDerived() throws {
        let patterns = try Sample.catalogue()
        let m = try #require(exact(TrainServicePatterns.resolve(
            serviceName: "サンプル", number: 9004, day: "2030-05-01", in: patterns)))
        #expect(m.direction == .down)
    }

    @Test("the same number is read from the revision that covers the date, never another")
    func revisionsAreNotMixed() throws {
        let patterns = try Sample.catalogue()
        let early = try #require(exact(TrainServicePatterns.resolve(
            serviceName: "サンプル", number: 9001, day: "2031-02-28", in: patterns)))
        #expect(early.revision.revision == "2030-03-01")
        #expect(early.stops.map(\.sourceCode).contains("S04"))
        let late = try #require(exact(TrainServicePatterns.resolve(
            serviceName: "サンプル", number: 9001, day: "2031-03-01", in: patterns)))
        #expect(late.revision.revision == "2031-03-01")
        #expect(late.stops.map(\.sourceCode) == ["S01", "S03", "S05", "S06", "S08"])
        #expect(!late.isVerified && !late.dateIsAfterLastCheck, "inside the checked period, but unverified")
        let stale = try #require(exact(TrainServicePatterns.resolve(
            serviceName: "サンプル", number: 9001, day: "2031-05-01", in: patterns)))
        #expect(stale.dateIsAfterLastCheck && !stale.isChecked,
                "open revision queried after its last check is unchecked")
        // 9003 is listed only in revision 1: revision 2 must not reuse it.
        #expect(reason(TrainServicePatterns.resolve(
            serviceName: "サンプル", number: 9003, day: "2031-05-01", in: patterns)) == .notListed)
    }

    @Test("a date outside every revision, a malformed date and no date never give a pattern")
    func noTableCases() throws {
        let patterns = try Sample.catalogue()
        let before = TrainServicePatterns.resolve(
            serviceName: "サンプル", number: 9001, day: "2030-02-28", in: patterns)
        #expect(reason(before) == .noTableForDate)
        #expect(reason(TrainServicePatterns.resolve(
            serviceName: "サンプル", number: 9001, day: "2029-01-01", in: patterns)) == .noTableForDate)
        #expect(reason(TrainServicePatterns.resolve(
            serviceName: "サンプル", number: 9001, day: "not a date", in: patterns)) == .noTableForDate)
        let noDay = TrainServicePatterns.resolve(serviceName: "サンプル", number: 9001, day: nil, in: patterns)
        #expect(reason(noDay) == .noDate)
        if case .notKnown(_, let bases) = noDay { #expect(bases.map(\.id) == ["sample-x-all"]) }
    }

    @Test("a number listed for weekdays and for holidays with different stops needs the day type")
    func sameNumberDifferentDays() throws {
        let patterns = try Sample.catalogue()
        func variant(_ kind: Variants.DayKind?) -> String? {
            exact(TrainServicePatterns.resolve(
                serviceName: "サンプル", number: 9021, day: "2030-05-01", dayKind: kind, in: patterns))?.variant.id
        }
        #expect(variant(.weekday) == "c")
        #expect(variant(.holiday) == "d")
        #expect(variant(nil) == nil)
        #expect(reason(TrainServicePatterns.resolve(
            serviceName: "サンプル", number: 9021, day: "2030-05-01", in: patterns)) == .ambiguous)
    }

    @Test("an all-stops service answers any number, with or without a date")
    func allStationsAnswersEverything() throws {
        let patterns = try Sample.catalogue()
        for (number, day) in [(1, "2030-05-01"), (12345, "2040-01-01"), (9001, nil)] as [(Int, String?)] {
            let answer = TrainServicePatterns.resolve(
                serviceName: "サンプル各停", number: number, day: day, in: patterns)
            guard case .allStations(let bases) = answer else {
                Issue.record("expected allStations for \(number)"); continue
            }
            #expect(bases.map(\.id) == ["sample-all-all"])
        }
    }

    @Test("service names match by name, service id and case; unknown services say so")
    func serviceNames() throws {
        let patterns = try Sample.catalogue()
        for name in ["サンプル", "sample-x", "SAMPLE-X", "  サンプル "] {
            #expect(exact(TrainServicePatterns.resolve(
                serviceName: name, number: 9001, day: "2030-05-01", in: patterns)) != nil, "\(name)")
        }
        #expect(reason(TrainServicePatterns.resolve(
            serviceName: "ナシ", number: 9001, day: "2030-05-01", in: patterns)) == .unknownService)
    }

    @Test("a record whose variants are ignored (unknown schema) is never confident")
    func noVariantsNeverConfident() throws {
        let ignored = try Sample.decode(Sample.variantBase().replacingOccurrences(
            of: #""schema": 1"#, with: #""schema": 9"#))
        #expect(reason(TrainServicePatterns.resolve(
            serviceName: "サンプル", number: 9001, day: "2030-05-01", in: ignored)) == .noTableForDate)
    }

    // MARK: - lookup: (service) -> patterns

    @Test("patterns of a service on a date come most numbers first, with the stops that differ")
    func summariesForService() throws {
        let patterns = try Sample.catalogue()
        let list = TrainServicePatterns.patternSummaries(
            serviceName: "サンプル", day: "2030-05-01", in: patterns)
        // a: 5 numbers, b: 2, then the tie c and d (1 each) ordered by id.
        #expect(list.map(\.variant.id) == ["a", "b", "c", "d"])
        #expect(list.map(\.trainCount) == [5, 2, 1, 1])
        #expect(list[0].exampleNumbers == [9001, 9002, 9003])
        // Calls S04 / S02 / none / S05: each pattern's own call differs from the common set (empty).
        #expect(list[0].extraStops.map(\.sourceCode) == ["S04"])
        #expect(list[2].extraStops.isEmpty)
        // Only the revision covering the date is read.
        let later = TrainServicePatterns.patternSummaries(
            serviceName: "サンプル", day: "2031-05-01", in: patterns)
        #expect(later.map(\.revision.revision) == ["2031-03-01"])
        #expect(TrainServicePatterns.patternSummaries(serviceName: "サンプル", day: nil, in: patterns).isEmpty)
        #expect(TrainServicePatterns.patternSummaries(serviceName: "サンプル", day: "2029-01-01", in: patterns).isEmpty)
    }

    // MARK: - lookup: (origin, destination) -> services

    @Test("stations lookup lists services calling at both, marks optional ones and gives direction")
    func servicesCallingBoth() throws {
        let patterns = try Sample.catalogue()
        let optionalOnly = TrainServicePatterns.servicesCalling(at: "S02", and: "S07", in: patterns)
        #expect(optionalOnly.map(\.serviceName) == ["サンプル", "サンプル各停"])
        #expect(optionalOnly.map(\.someTrains) == [true, false])
        let required = TrainServicePatterns.servicesCalling(at: "S01", and: "S03", in: patterns)
        #expect(required.map(\.someTrains) == [false, false])
        #expect(required.first?.direction == .down)
        #expect(TrainServicePatterns.servicesCalling(at: "S03", and: "S01", in: patterns).first?.direction == .up)
        #expect(TrainServicePatterns.servicesCalling(at: "S01", and: "ZZ", in: patterns).isEmpty)
        #expect(TrainServicePatterns.servicesCalling(at: "S01", and: "S01", in: patterns).isEmpty)
        // The dated record is not in force in 2029; the undated all-stops one is.
        #expect(TrainServicePatterns.servicesCalling(at: "S01", and: "S03", day: "2029-01-01", in: patterns)
            .map(\.serviceName) == ["サンプル各停"])
    }

    // MARK: - train-number parser

    @Test("the parser reads names and numbers in the usual spellings")
    func parser() {
        let cases: [(String, String, Int?)] = [
            ("のぞみ 23", "のぞみ", 23), ("のぞみ23号", "のぞみ", 23), ("Nozomi 23", "Nozomi", 23),
            ("のぞみ２３号", "のぞみ", 23), ("　のぞみ　23　", "のぞみ", 23), ("のぞみ第23号", "のぞみ", 23),
            ("のぞみ 23 号", "のぞみ", 23), ("のぞみ", "のぞみ", nil), ("のぞみ号", "のぞみ", nil),
            ("のぞみ 0023", "のぞみ", 23),
        ]
        for (text, name, number) in cases {
            let parsed = TrainNumberParser.parse(text)
            #expect(parsed?.name == name && parsed?.number == number, "\(text)")
        }
        #expect(TrainNumberParser.parse("") == nil)
        #expect(TrainNumberParser.parse("23") == nil)
        #expect(TrainNumberParser.parse("23号") == nil)
        #expect(TrainNumberParser.parse("のぞみ 12345678") == nil)
    }
}

// MARK: - validator

struct TrainPatternVariantsValidatorTests {

    private func violations(
        _ base: String = Sample.variantBase(), corridor: [Pattern.StationRef]? = Sample.corridor
    ) throws -> [TrainPatternVariantsValidator.Violation] {
        TrainPatternVariantsValidator.validate(try Sample.catalogue(base)) { _ in corridor }
    }

    private func rules(_ items: [TrainPatternVariantsValidator.Violation], _ severity: TrainPatternVariantsValidator.Severity = .error)
        -> Set<TrainPatternVariantsValidator.Rule> {
        Set(items.filter { $0.severity == severity }.map(\.rule))
    }

    @Test("the sample fixtures pass; only the odd/even convention is reported, as a warning")
    func sampleFixturesPass() throws {
        let found = try violations()
        #expect(TrainPatternVariantsValidator.errors(in: found).isEmpty, "\(found)")
        #expect(rules(found, .warning) == [.parityConvention])
        // Without a corridor the corridor-dependent checks are skipped, nothing else changes.
        #expect(TrainPatternVariantsValidator.errors(in: try violations(corridor: nil)).isEmpty)
    }

    @Test("each violation class is reported on its fixture")
    func eachClassFails() throws {
        func mutate(_ transform: (String) -> String) throws -> Set<TrainPatternVariantsValidator.Rule> {
            rules(try violations(Sample.variantBase(revisions: transform(Sample.revisions))))
        }
        #expect(try rules(violations(Sample.variantBase(order: #"["S01","S03","S02","S04","S05","S06","S07","S08"]"#))) == [.orderMismatch])
        #expect(try rules(violations(Sample.variantBase(order: #"["S01","S02","S03","S04","S05","S06","S07"]"#))) == [.orderMismatch])
        #expect(try mutate { $0.replacingOccurrences(of: #""calls": ["S04"]"#, with: #""calls": ["S03"]"#) } == [.callNotOptional])
        #expect(try mutate { $0.replacingOccurrences(of: "SAMPLE citation one", with: "  ") } == [.missingCitation])
        #expect(try mutate { $0.replacingOccurrences(of: #""validUntil": "2031-03-01""#, with: #""validUntil": "2031-06-01""#) } == [.revisionOverlap, .numberInTwoPatterns])
        #expect(try mutate { $0.replacingOccurrences(of: #""validUntil": "2031-03-01""#, with: #""validUntil": null"#) } == [.openEndedRevisionNotLast, .numberInTwoPatterns])
        #expect(try mutate { $0.replacingOccurrences(of: #""checkedOn": "2030-06-01""#, with: #""checkedOn": "2030-13-01""#) } == [.invalidDate])
        #expect(try mutate { $0.replacingOccurrences(of: #""id": "b""#, with: #""id": "a""#) } == [.duplicatePatternID])
        #expect(try mutate { $0.replacingOccurrences(of: #""to": "S06""#, with: #""from": "S08", "to": "S01""#) } == [.endsOutOfOrder])
        #expect(try mutate { $0.replacingOccurrences(of: #""to": "S06""#, with: #""to": "S99""#) } == [.endNotInOrder])
        #expect(try mutate { $0.replacingOccurrences(of: "[9011]", with: "[]") } == [.emptyNumbers])
        #expect(try mutate { $0.replacingOccurrences(of: "[9011]", with: "[0]") } == [.nonPositiveNumber])
        #expect(try mutate { $0.replacingOccurrences(of: "[9011]", with: "[9011, 9011]") } == [.duplicateNumber])
        // The same number in two patterns on overlapping days.
        #expect(try mutate { $0.replacingOccurrences(of: "[9011]", with: "[9001]") } == [.numberInTwoPatterns])
        // Seasonal windows that do not intersect make the same number legal.
        #expect(try mutate {
            $0.replacingOccurrences(of: #"{"direction": "down", "numbers": [9011]}"#,
                                    with: #"{"direction": "down", "numbers": [9001], "validFrom": "2030-09-01", "validUntil": "2030-10-01"}"#)
                .replacingOccurrences(of: #"{"direction": "down", "numbers": [9001, "9003-9005"]}"#,
                                      with: #"{"direction": "down", "numbers": [9001, "9003-9005"], "validFrom": "2030-03-01", "validUntil": "2030-09-01"}"#)
        }.isEmpty)
        #expect(try mutate {
            $0.replacingOccurrences(of: #"{"direction": "down", "numbers": [9011]}"#,
                                    with: #"{"direction": "down", "numbers": [9011], "validFrom": "2029-01-01"}"#)
        } == [.groupOutsideRevision])
    }

    @Test("record-level classes: corridor, all-stations, required/optional overlap, coupling")
    func recordClasses() throws {
        // A stop that is not on the corridor.
        let short = Array(Sample.corridor.dropLast())
        #expect(rules(try violations(corridor: short)).contains(.stopNotInCorridor))
        // allStations record missing a station, with optional stops, with variants.
        let missingOne = Sample.allStationsBase.replacingOccurrences(
            of: #"{"name": "戊", "sourceCode": "S05"},"#, with: "")
        let incomplete = TrainPatternVariantsValidator.validate(
            try Sample.decode(Sample.variantBase(), missingOne)) { _ in Sample.corridor }
        #expect(rules(incomplete) == [.allStationsIncomplete])
        let withOptional = Sample.allStationsBase.replacingOccurrences(
            of: #""optionalStops": []"#, with: #""optionalStops": [{"name": "甲", "sourceCode": "S01"}]"#)
        #expect(rules(TrainPatternVariantsValidator.validate(
            try Sample.decode(Sample.variantBase(), withOptional)) { _ in Sample.corridor })
            .contains(.allStationsWithOptionalStops))
        let withVariants = Sample.allStationsBase.replacingOccurrences(
            of: #""lines": ["サンプル線"]}"#,
            with: #""lines": ["サンプル線"], "variants": {"schema": 1, "order": [], "revisions": []}}"#)
        #expect(rules(TrainPatternVariantsValidator.validate(
            try Sample.decode(Sample.variantBase(), withVariants)) { _ in Sample.corridor })
            .contains(.allStationsWithVariants))
        // A station both always served and optional.
        let overlapping = Sample.variantBase().replacingOccurrences(
            of: #""optionalStops": [{"name": "乙""#, with: #""optionalStops": [{"name": "甲", "sourceCode": "S01"}, {"name": "乙""#)
        #expect(rules(try violations(overlapping)).contains(.optionalOverlapsRequired))
        // Coupling to a service that does not exist, and to one that exists but does not couple back.
        let coupled = { (service: String) in Sample.variantBase(revisions: Sample.revisions.replacingOccurrences(
            of: #"{"id": "c", "calls": []"#,
            with: #"{"id": "c", "coupled": {"service": "\#(service)", "from": "S01", "to": "S03"}, "calls": []"#)) }
        #expect(rules(try violations(coupled("sample-nowhere"))) == [.coupledPartnerMissing])
        let reciprocal = try violations(coupled("sample-all"))
        #expect(TrainPatternVariantsValidator.errors(in: reciprocal).isEmpty)
        #expect(rules(reciprocal, .warning).contains(.coupledNotReciprocal))
    }

    @Test("a record's revisions must lie inside the record's own dates")
    func revisionsInsideRecord() throws {
        let tooEarly = Sample.variantBase().replacingOccurrences(of: #""validFrom": "2030-01-01""#, with: #""validFrom": "2030-04-01""#)
        #expect(rules(try violations(tooEarly)).contains(.revisionOutsideRecordDates))
        let ended = Sample.variantBase(extra: "").replacingOccurrences(of: #""validUntil": null,"#, with: #""validUntil": "2031-01-01","#)
        #expect(rules(try violations(ended)).contains(.revisionOutsideRecordDates))
    }

    @Test("the real bundled catalogue has no new-key violations (strict base-data check is in Python)")
    func bundledCatalogueNewKeys() {
        let found = TrainPatternVariantsValidator.validate(TrainServicePatterns.patterns)
        #expect(TrainPatternVariantsValidator.errors(in: found).isEmpty, "\(found)")
    }
}
