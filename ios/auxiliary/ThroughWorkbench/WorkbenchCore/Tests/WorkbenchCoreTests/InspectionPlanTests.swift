import Foundation
import Testing
@testable import WorkbenchCore

struct InspectionPlanTests {
    func json(_ text: String) throws -> JSONValue { try JSONValue(data: Data(text.utf8)) }
    func catalog(_ patterns: [JSONValue], connectors: [JSONValue] = []) -> JSONValue {
        .object(["schemaVersion": .number(2), "coverageFrom": .string("2005-01-01"),
                 "checkedAt": .string("2026-10-02"), "patterns": .array(patterns), "connectors": .array(connectors)])
    }
    func pattern(_ fields: [String: JSONValue] = [:]) -> JSONValue {
        var value: [String: JSONValue] = ["id": .string("service"), "name": .string("Service"),
            "serviceCode": .string("S"), "sourceURLs": .array([.string("https://example.org/source")]),
            "legs": .array([.object(["lineID": .string("a"), "fromStationCode": .string("A"), "toStationCode": .string("B")])])]
        value.merge(fields) { _, new in new }
        return .object(value)
    }
    func variant(from: String, to: String? = nil, indices: [Int] = [0], url: String = "https://example.org/history") -> JSONValue {
        var value: [String: JSONValue] = ["validFrom": .string(from), "legIndices": .array(indices.map { .number(Double($0)) }),
            "sourceURLs": .array([.string(url)]), "notes": .string("Reviewed period")]
        if let to { value["validTo"] = .string(to) }
        return .object(value)
    }
    let simplePackage = #"{"format":"compact-v1","lines":[{"id":"a","stations":[["A","Alpha",139,35],["B","Beta",140,36]],"segments":[[1,0,[[139,35],[140,36]]]]}]}"#

    @Test func planSamplesEveryBoundaryAndGroupsRepeatedFindings() throws {
        let leg: JSONValue = .object(["lineID": .string("a"), "fromStationCode": .string("A"), "toStationCode": .string("B"), "validFrom": .string("2006-02-02")])
        let connector: JSONValue = .object(["id": .string("join"), "fromLineID": .string("a"), "fromStationCode": .string("A"),
            "toLineID": .string("a"), "toStationCode": .string("B"), "validFrom": .string("2007-03-03"), "validTo": .string("2008-04-04")])
        var doc = WorkbenchDocument(catalog: catalog([pattern(["validFrom": .string("2001-01-01"), "legs": .array([leg]),
            "legVariants": .array([variant(from: "2009-05-05", to: "2010-06-06")])])], connectors: [connector]))
        doc.patches = [TemporalPatch(patternID: "service", effectiveFrom: "2011-07-07", effectiveTo: "2012-08-08",
            sourceURL: "https://example.org/patch", note: "Review")]
        let plan = try doc.inspectionPlan(through: "2013-01-01")
        for boundary in ["2001-01-01", "2006-02-02", "2007-03-03", "2008-04-04", "2009-05-05", "2010-06-06", "2011-07-07", "2012-08-08"] {
            #expect(plan.sampledDays.contains(boundary))
            #expect(plan.sampledDays.contains(ISODay.string(try #require(ISODay.date(boundary)).addingTimeInterval(-86400))))
        }
        #expect(plan.sampledDays.first == "1996-12-31")
        #expect(plan.sampledDays.last == "2013-01-01")
        #expect(plan.findings.filter { $0.id == "variants:service:period-gap" }.count == 1)
        #expect((plan.findings.first { $0.id == "variants:service:period-gap" }?.days.count ?? 0) > 1)
        #expect(try doc.inspectionPlan(through: "2013-01-01").findings.map(\.id) == plan.findings.map(\.id))
        let roundTrip = try JSONDecoder().decode(InspectionPlan.self, from: JSONEncoder().encode(plan))
        #expect(roundTrip.sampledDays == plan.sampledDays)
    }

    @Test func malformedImportStillYieldsFullIndependentFindings() throws {
        let broken = pattern(["validFrom": .number(2005), "validTo": .string("2004-02-30"),
            "sourceURLs": .array([.string("https://example.org/contains space")]),
            "legVariants": .array([variant(from: "2010-01-01", indices: [99])])])
        let healthy = pattern(["id": .string("other"), "historicalReview": .object(["status": .string("periodsUnresolved")])])
        let plan = try WorkbenchDocument(catalog: catalog([broken, broken, healthy])).inspectionPlan(through: "2026-10-10")
        #expect(plan.findings.contains { $0.category == "catalog" && $0.title.contains("重复") })
        #expect(plan.findings.contains { $0.category == "windows" && $0.severity == .error })
        #expect(plan.findings.contains { $0.category == "variants" && $0.severity == .error })
        #expect(plan.findings.contains { $0.category == "sources" && $0.title.contains("空白") })
        #expect(plan.findings.contains { $0.patternID == "other" && $0.title.contains("未完整确认") })
        #expect(plan.findings.contains { $0.category == "catalog" && !$0.days.isEmpty })
        #expect(plan.checks.count == 10)
        #expect(plan.checks.first { $0.id == "inventory" }?.result == "unknown")
        #expect(plan.checks.first { $0.id == "parity" }?.result == "unknown")
    }

    @Test func connectorsRequireValidIdentityWindowsAnchorsAndEvidence() throws {
        let connector: JSONValue = .object(["id": .string("bad"), "validFrom": .string("2010-01-01"), "validTo": .string("2009-01-01"),
            "fromLineID": .string("a"), "fromStationCode": .string("missing"), "toLineID": .string("a"), "toStationCode": .string("B")])
        let doc = WorkbenchDocument(catalog: catalog([pattern()], connectors: [connector, connector]), package: try json(simplePackage))
        let plan = try doc.inspectionPlan(through: "2020-01-01")
        #expect(plan.findings.contains { $0.id == "windows::connector-bad" && $0.severity == .error })
        #expect(plan.findings.contains { $0.id == "junctions::connector-bad-from" && $0.severity == .error })
        #expect(plan.findings.contains { $0.id == "junctions::connector-id-1" })
        #expect(plan.findings.contains { $0.id == "sources::connector-bad" && $0.severity == .unknown })
    }

    @Test func missingVariantPeriodIsUnknownWithinDeclaredEvidenceRange() throws {
        let doc = WorkbenchDocument(catalog: catalog([pattern(["validFrom": .string("2005-01-01"), "legVariants": .array([
            variant(from: "2005-01-01", to: "2010-01-01"), variant(from: "2012-01-01")])])]))
        let plan = try doc.inspectionPlan(through: "2027-01-01")
        let gap = try #require(plan.findings.first { $0.id == "variants:service:period-gap" })
        #expect(gap.severity == .unknown)
        #expect(gap.requiresEvidence)
        #expect(gap.days.contains("2010-01-01"))
        #expect(!gap.days.contains("2027-01-01"))
        #expect(try doc.patterns(on: "2011-01-01")[0].statusLabel == "Unknown")
    }

    @Test func statusDifferenceIncludesUnknownToInactiveWithoutServiceClaim() throws {
        let leg: JSONValue = .object(["lineID": .string("a"), "fromStationCode": .string("A"), "toStationCode": .string("B"), "validTo": .string("2000-01-01")])
        let doc = WorkbenchDocument(catalog: catalog([pattern(["legs": .array([leg])])]))
        #expect(try doc.patterns(on: "1996-12-31")[0].statusLabel == "Unknown")
        #expect(try doc.patterns(on: "2005-01-01")[0].statusLabel == "Inactive")
        let change = try #require(doc.differences(from: "1996-12-31", to: "2005-01-01").first)
        #expect(change.change.contains("Unknown → Inactive"))
        #expect(!change.change.contains("服务停用"))
    }

    @Test func sourceEndpointsRemainUntouchedAndMismatchIsDetected() throws {
        let package = try json(#"{"lines":[{"id":"a","stations":[["A","Alpha",139,35],["B","Beta",140,36]],"segments":[[1,0,[[139.01,35],[140.01,36]]]]}]}"#)
        let doc = WorkbenchDocument(catalog: catalog([pattern()]), package: package)
        #expect(try doc.patterns(on: "2005-01-01")[0].legs[0].coordinates == [[139.01,35],[140.01,36]])
        #expect(try doc.audit(on: "2005-01-01").contains { $0.id == "service-leg-0-anchor-mismatch" })
        #expect(try doc.inspectionPlan(through: "2020-01-01").findings.contains { $0.id == "physical:service:leg-0-anchor" && $0.severity == .warning })
    }

    @Test func missingFirstSeamAndWrongRowCountDoNotInventGeometry() throws {
        for rows in [#"[[1,1,[[140,36]]]]"#, #"[[1,0,[[139,35],[140,36]]],[1,0,[[140,36],[141,37]]]]"#] {
            let package = try json("{\"lines\":[{\"id\":\"a\",\"stations\":[[\"A\",\"Alpha\",139,35],[\"B\",\"Beta\",140,36]],\"segments\":\(rows)}]}")
            let doc = WorkbenchDocument(catalog: catalog([pattern()]), package: package)
            #expect(try doc.patterns(on: "2005-01-01")[0].legs[0].coordinates.isEmpty)
            #expect(try doc.inspectionPlan(through: "2020-01-01").findings.contains { $0.id == "physical:service:leg-0-geometry" && $0.severity == .error })
        }
    }

    @Test func continuedIntervalUsesActualPreviousSurveyEndpoint() throws {
        let package = try json(#"{"lines":[{"id":"a","stations":[["A","Alpha",139,35],["B","Beta",140,36],["C","Gamma",141,37]],"segments":[[1,0,[[139,35],[140.01,36]]],[1,1,[[141,37]]]]}]}"#)
        let leg: JSONValue = .object(["lineID": .string("a"), "fromStationCode": .string("B"), "toStationCode": .string("C")])
        let doc = WorkbenchDocument(catalog: catalog([pattern(["legs": .array([leg])])]), package: package)
        #expect(try doc.patterns(on: "2005-01-01")[0].legs[0].coordinates == [[140.01,36],[141,37]])
    }

    @Test func permittedTraversalUsesProductionForwardAndReverseValues() throws {
        for (traversal, from, to) in [("forward", "B", "A"), ("reverse", "A", "B")] {
            var package = try #require(json(simplePackage).objectValue)
            var line = try #require(package["lines"]?.arrayValue?.first?.objectValue)
            line["permittedTraversal"] = .string(traversal)
            package["lines"] = .array([.object(line)])
            let leg: JSONValue = .object(["lineID": .string("a"), "fromStationCode": .string(from), "toStationCode": .string(to)])
            let doc = WorkbenchDocument(catalog: catalog([pattern(["legs": .array([leg])])]), package: .object(package))
            #expect(try doc.inspectionPlan(through: "2020-01-01").findings.contains { $0.id == "physical:service:leg-0-direction" && $0.severity == .error })
        }
    }

    @Test func temporalIntroductionsAreIncludedInPatternCountAndBoundarySampling() throws {
        var doc = WorkbenchDocument(catalog: catalog([pattern()]))
        doc.patches = [TemporalPatch(patternID: "new", effectiveFrom: "2010-01-01", changes: [
            "name": .string("New"), "serviceCode": .string("N"), "legs": try #require(pattern()["legs"]),
            "sourceURLs": .array([.string("https://example.org/new")])], sourceURL: "https://example.org/new", note: "New service")]
        let plan = try doc.inspectionPlan(through: "2020-01-01")
        #expect(plan.patternCount == 2)
        #expect(plan.sampledDays.contains("2009-12-31"))
        #expect(plan.sampledDays.contains("2010-01-01"))
    }
    @Test func reverseMateGeometryAndOppositeJourneyDirectionAreInspected() throws {
        for (segments, traversal, expected) in [
            ("[]", "reverse", "physical:service:leg-0-reverse-path-geometry"),
            ("[[1,0,[[139,35],[140,36]]]]", "forward", "physical:service:leg-0-reverse-path-direction")
        ] {
            var package = try #require(json(simplePackage).objectValue)
            var mate = try #require(package["lines"]?.arrayValue?.first?.objectValue)
            mate["id"] = .string("mate"); mate["alignmentOf"] = .string("a")
            mate["permittedTraversal"] = .string(traversal)
            mate["segments"] = try json(segments)
            package["lines"] = .array((package["lines"]?.arrayValue ?? []) + [.object(mate)])
            let leg: JSONValue = .object(["lineID": .string("a"), "reverseLineID": .string("mate"), "fromStationCode": .string("A"), "toStationCode": .string("B")])
            let plan = try WorkbenchDocument(catalog: catalog([pattern(["legs": .array([leg])])]), package: .object(package)).inspectionPlan(through: "2020-01-01")
            #expect(plan.findings.contains { $0.id == expected && $0.severity == .error })
        }
    }

    @Test func directionalLoopUsesClosingIntervalAndRejectsMissingClosure() throws {
        let loop = try json(#"{"lines":[{"id":"a","isLoop":1,"permittedTraversal":"forward","stations":[["A","Alpha",139,35],["B","Beta",140,36],["C","Gamma",141,37]],"segments":[[1,0,[[139,35],[140,36]]],[1,1,[[141,37]]],[1,1,[[140,37],[139,35]]]]}]}"#)
        let leg: JSONValue = .object(["lineID": .string("a"), "fromStationCode": .string("C"), "toStationCode": .string("A")])
        let doc = WorkbenchDocument(catalog: catalog([pattern(["legs": .array([leg])])]), package: loop)
        #expect(try doc.patterns(on: "2005-01-01")[0].legs[0].coordinates == [[141,37],[140,37],[139,35]])
        let plan = try doc.inspectionPlan(through: "2020-01-01")
        #expect(!plan.findings.contains { $0.patternID == "service" && $0.category == "physical" && $0.severity == .error })
        var package = try #require(loop.objectValue)
        var line = try #require(package["lines"]?.arrayValue?.first?.objectValue)
        line["segments"] = .array(Array((line["segments"]?.arrayValue ?? []).dropLast()))
        package["lines"] = .array([.object(line)])
        let missing = WorkbenchDocument(catalog: doc.catalog, package: .object(package))
        #expect(try missing.patterns(on: "2005-01-01")[0].legs[0].coordinates.isEmpty)
        #expect(try missing.inspectionPlan(through: "2020-01-01").findings.contains { $0.id == "physical:service:leg-0-geometry" && $0.severity == .error })
    }

    @Test func bidirectionalLoopWithoutSelectedPathRemainsUnknown() throws {
        let loop = try json(#"{"lines":[{"id":"a","isLoop":true,"stations":[["A","Alpha",139,35],["B","Beta",140,36],["C","Gamma",141,37]],"segments":[[1,0,[[139,35],[140,36]]],[1,1,[[141,37]]],[1,1,[[139,35]]]]}]}"#)
        let doc = WorkbenchDocument(catalog: catalog([pattern()]), package: loop)
        let plan = try doc.inspectionPlan(through: "2020-01-01")
        #expect(plan.findings.contains { $0.id == "physical:service:leg-0-geometry" && $0.severity == .unknown })
        #expect(!plan.findings.contains { $0.patternID == "service" && $0.category == "physical" && $0.severity == .error })
        #expect(try doc.audit(on: "2005-01-01").contains { $0.id == "service-leg-0-geometry" && $0.severity == .unknown })
    }

    @Test func malformedStationCoordinateIsAnAnchorErrorRatherThanSurveyWarning() throws {
        let package = try json(#"{"lines":[{"id":"a","stations":[["A","Alpha","139",35],["B","Beta",140,36]],"segments":[[1,0,[[139,35],[140,36]]]]}]}"#)
        let doc = WorkbenchDocument(catalog: catalog([pattern()]), package: package)
        let plan = try doc.inspectionPlan(through: "2020-01-01")
        #expect(plan.findings.contains { $0.id == "physical:service:leg-0" && $0.severity == .error && $0.title.contains("坐标无效") })
        #expect(!plan.findings.contains { $0.id == "physical:service:leg-0-anchor" && $0.severity == .warning })
        #expect(try doc.audit(on: "2005-01-01").contains { $0.id == "service-leg-0-station" && $0.severity == .error })
    }

    func junctionDocument() throws -> WorkbenchDocument {
        let package = try json(#"{"country":"jp","lines":[{"id":"a","railwayIdentity":"jp-Operator-First","stations":[["A","Alpha",139,35],["B","Beta",140,36]],"segments":[[1,0,[[139,35],[140,36]]]]},{"id":"b","railwayIdentity":"jp-Operator-Second","stations":[["B","Beta",140,36],["C","Gamma",141,37]],"segments":[[1,0,[[140,36],[141,37]]]]}]}"#)
        let evidence = try json(#"{"format":"jtm-physical-rail-junctions-v1","junctions":[{"id":"reviewed","region":"jp","lineIDs":["a","b"],"from":{"identity":{"operatorName":"Operator","lineName":"First","railwayClassCode":"11"},"coordinate":[140,36]},"to":{"identity":{"operatorName":"Operator","lineName":"Second","railwayClassCode":"11"},"coordinate":[140,36]},"evidence":["https://example.org/railway"],"geometryEvidence":"Reviewed identical surveyed vertex","temporalEvidence":"Named connection opened on this day","reviewedAt":"2026-10-02","validFrom":"2005-01-01","validTo":"2020-01-01"}]}"#)
        let legs = try json(#"[{"lineID":"a","fromStationCode":"A","toStationCode":"B"},{"lineID":"b","fromStationCode":"B","toStationCode":"C"}]"#)
        return WorkbenchDocument(catalog: catalog([pattern(["validFrom": .string("2005-01-01"), "legs": legs])]),
                                 package: package, physicalJunctions: evidence)
    }

    @Test func reviewedJunctionMatchesOnlyAdjacentSurveyEndpointsWithinItsWindow() throws {
        let doc = try junctionDocument()
        let plan = try doc.inspectionPlan(through: "2021-01-01")
        let missing = try #require(plan.findings.first { $0.id == "junctions:service:physical-proof-0-1" })
        #expect(!missing.days.contains("2005-01-01"))
        #expect(!missing.days.contains("2019-12-31"))
        #expect(missing.days.contains("2020-01-01"))
        #expect(missing.days.contains("2021-01-01"))
        #expect(plan.findings.contains { $0.id == "history::historical" && $0.severity == .unknown })
        #expect(try !doc.audit(on: "2019-12-31").contains { $0.id == "service-junction-evidence-0" })
        #expect(try doc.audit(on: "2020-01-01").contains { $0.id == "service-junction-evidence-0" })
    }

    @Test func wrongIdentityEndpointOrLineIDCannotBorrowReviewedJunctionEvidence() throws {
        for (key, replacement) in [
            ("from", try json(#"{"identity":{"operatorName":"Other","lineName":"First","railwayClassCode":"11"},"coordinate":[140,36]}"#)),
            ("from", try json(#"{"identity":{"operatorName":"Operator","lineName":"First","railwayClassCode":"11"},"coordinate":[139,35]}"#)),
            ("lineIDs", try json(#"["a","unrelated"]"#))
        ] {
            var doc = try junctionDocument()
            var root = try #require(doc.physicalJunctions?.objectValue)
            var record = try #require(root["junctions"]?.arrayValue?.first?.objectValue)
            record[key] = replacement; root["junctions"] = .array([.object(record)])
            doc.physicalJunctions = .object(root)
            let finding = try #require(doc.inspectionPlan(through: "2019-12-31").findings.first { $0.id == "junctions:service:physical-proof-0-1" })
            #expect(finding.days.contains("2019-12-31"))
        }
    }

    @Test func undatedJunctionAndDaysAfterReviewRemainUnknown() throws {
        for key in ["validFrom", "reviewedAt"] {
            var doc = try junctionDocument()
            var root = try #require(doc.physicalJunctions?.objectValue)
            var record = try #require(root["junctions"]?.arrayValue?.first?.objectValue)
            record.removeValue(forKey: key); root["junctions"] = .array([.object(record)])
            doc.physicalJunctions = .object(root)
            let finding = try #require(doc.inspectionPlan(through: "2019-12-31").findings.first { $0.id == "junctions:service:physical-proof-0-1" })
            #expect(finding.days.contains("2019-12-31"))
        }
        var doc = try junctionDocument()
        var root = try #require(doc.physicalJunctions?.objectValue)
        var record = try #require(root["junctions"]?.arrayValue?.first?.objectValue)
        record.removeValue(forKey: "validTo"); root["junctions"] = .array([.object(record)])
        doc.physicalJunctions = .object(root)
        let finding = try #require(doc.inspectionPlan(through: "2026-10-03").findings.first { $0.id == "junctions:service:physical-proof-0-1" })
        #expect(!finding.days.contains("2026-10-02"))
        #expect(finding.days.contains("2026-10-03"))
    }

    @Test func physicalJunctionEvidencePersistsAndOldDocumentsRemainReadable() throws {
        let doc = try junctionDocument()
        let encoded = try JSONEncoder().encode(doc)
        #expect(try JSONDecoder().decode(WorkbenchDocument.self, from: encoded).physicalJunctions == doc.physicalJunctions)
        var old = try #require(JSONValue(data: encoded).objectValue)
        old.removeValue(forKey: "physicalJunctions")
        #expect(try JSONDecoder().decode(WorkbenchDocument.self, from: JSONValue.object(old).data()).physicalJunctions == nil)
    }

    @Test func explicitLoopTraversalChoosesWrapAndOverridesInferredDirection() throws {
        let package = try json(#"{"lines":[{"id":"a","isLoop":true,"permittedTraversal":"reverse","stations":[["A","Alpha",139,35],["B","Beta",140,36],["C","Gamma",141,37]],"segments":[[1,0,[[139,35],[140,36]]],[1,1,[[141,37]]],[1,1,[[140,37],[139,35]]]]}]}"#)
        for (direction, expected) in [("forward", [[141.0,37.0],[140,37],[139,35]]), ("reverse", [[141.0,37.0],[140,36],[139,35]])] {
            let leg: JSONValue = .object(["lineID": .string("a"), "fromStationCode": .string("C"), "toStationCode": .string("A"),
                "loopTraversal": .string(direction), "loopTraversalSourceURLs": .array([.string("https://example.org/current-loop")])])
            let doc = WorkbenchDocument(catalog: catalog([pattern(["legs": .array([leg])])]), package: package)
            #expect(try doc.patterns(on: "2005-01-01")[0].legs[0].coordinates == expected)
            #expect(try !doc.inspectionPlan(through: "2020-01-01").findings.contains { $0.id == "physical:service:leg-0-geometry" })
        }
    }

    @Test func sameIdentityTrackMayOmitLineIDsAndMalformedJunctionsRemainRejected() throws {
        var doc = try junctionDocument()
        var root = try #require(doc.physicalJunctions?.objectValue)
        var track = try #require(root["junctions"]?.arrayValue?.first?.objectValue)
        track["kind"] = .string("osmTrack"); track.removeValue(forKey: "lineIDs")
        track["to"] = track["from"]
        root["junctions"] = .array([.object(track)]); doc.physicalJunctions = .object(root)
        let trackPlan = try doc.inspectionPlan(through: "2019-12-31")
        #expect(!trackPlan.findings.contains { $0.id == "junctions::physical-reviewed-lines" })
        #expect(trackPlan.findings.contains { $0.id == "junctions:service:physical-proof-0-1" })
        var broken = try #require(junctionDocument().physicalJunctions?["junctions"]?.arrayValue?.first?.objectValue)
        broken["validTo"] = .string("2004-01-01")
        root["junctions"] = .array([.object(broken), .object(broken)]); doc.physicalJunctions = .object(root)
        let invalid = try doc.inspectionPlan(through: "2019-12-31")
        #expect(invalid.findings.contains { $0.id == "windows::physical-reviewed" && $0.severity == .error })
        #expect(invalid.findings.contains { $0.id == "junctions::physical-id-1" && $0.severity == .error })
        #expect(invalid.findings.contains { $0.id == "junctions:service:physical-proof-0-1" })
    }

    @Test func canonicalUppercasePackageCountryMatchesReviewedJunctions() throws {
        var doc = try junctionDocument()
        var package = try #require(doc.package?.objectValue)
        package["country"] = .string("JP")
        doc.package = .object(package)
        let plan = try doc.inspectionPlan(through: "2019-12-31")
        #expect(!plan.findings.contains { $0.id == "junctions:service:physical-proof-0-1" })
        #expect(plan.checks.first { $0.id == "junctions" }?.detail.contains("已匹配 1") == true)
    }

    @Test func loopTraversalRejectsInvalidHintsAndReportsMissingOrInvalidSources() throws {
        let loop = try json(#"{"lines":[{"id":"a","isLoop":true,"stations":[["A","Alpha",139,35],["B","Beta",140,36]],"segments":[[1,0,[[139,35],[140,36]]],[1,1,[[139,35]]]]}]}"#)
        for (hint, source, expectedID, severity) in [
            ("sideways", JSONValue.array([.string("https://example.org/loop")]), "physical:service:leg-0-loop-traversal", Severity.error),
            ("forward", .array([]), "sources:service:leg-0-loop-traversal", .unknown),
            ("forward", .array([.string("https://example.org/has space")]), "sources:service:leg-0-loop-traversal-invalid", .error)
        ] {
            let leg: JSONValue = .object(["lineID": .string("a"), "fromStationCode": .string("A"), "toStationCode": .string("B"),
                "loopTraversal": .string(hint), "loopTraversalSourceURLs": source])
            let doc = WorkbenchDocument(catalog: catalog([pattern(["legs": .array([leg])])]), package: loop)
            #expect(try doc.inspectionPlan(through: "2020-01-01").findings.contains { $0.id == expectedID && $0.severity == severity })
            #expect(try doc.patterns(on: "2005-01-01")[0].legs[0].coordinates.isEmpty)
        }
        let leg: JSONValue = .object(["lineID": .string("a"), "fromStationCode": .string("A"), "toStationCode": .string("B"),
            "loopTraversal": .string("forward"), "loopTraversalSourceURLs": .array([.string("https://example.org/loop")])])
        let doc = WorkbenchDocument(catalog: catalog([pattern(["legs": .array([leg])])]), package: try json(simplePackage))
        #expect(try doc.inspectionPlan(through: "2020-01-01").findings.contains { $0.id == "physical:service:leg-0-loop-traversal" && $0.severity == .error })
        #expect(try doc.patterns(on: "2005-01-01")[0].legs[0].coordinates.isEmpty)
    }

    @Test func explicitBoundedSuspensionIsInactiveAndDistinctFromUnknownPeriodGap() throws {
        var suspended = try #require(variant(from: "2010-01-01", to: "2010-01-02", indices: []).objectValue)
        suspended["suspended"] = .bool(true)
        let p = pattern(["validFrom": .string("2005-01-01"), "legVariants": .array([
            variant(from: "2005-01-01", to: "2010-01-01"), .object(suspended), variant(from: "2010-01-03")])])
        let doc = WorkbenchDocument(catalog: catalog([p]), package: try json(simplePackage))
        #expect(try doc.patterns(on: "2010-01-01")[0].statusLabel == "Inactive")
        #expect(try doc.patterns(on: "2010-01-02")[0].statusLabel == "Unknown")
        let plan = try doc.inspectionPlan(through: "2020-01-01")
        #expect(!plan.findings.contains { $0.category == "variants" && $0.severity == .error })
        let gap = try #require(plan.findings.first { $0.id == "variants:service:period-gap" })
        #expect(!gap.days.contains("2010-01-01"))
        #expect(gap.days.contains("2010-01-02"))
        for invalid in [
            variant(from: "2010-01-01", to: "2010-01-02", indices: []),
            JSONValue.object(suspended.merging(["legIndices": .array([.number(0)])]) { _, new in new }),
            JSONValue.object(suspended.filter { $0.key != "validTo" })
        ] {
            #expect(throws: WorkbenchError.self) { try WorkbenchDocument.validateLegVariants(pattern(["legVariants": .array([invalid])])) }
        }
    }

}
