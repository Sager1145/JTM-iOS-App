import Foundation
import Testing
@testable import WorkbenchCore

struct TemporalDocumentTests {
    let base = Data(#"{"schemaVersion":2,"coverageFrom":"2005-01-01","checkedAt":"2026-10-02","scope":"partial","futureField":{"keep":1},"connectors":[],"coverage":[],"patterns":[{"id":"service","serviceCode":"S","name":"Service","aliases":[],"kind":"throughRunning","sourceURLs":["https://example.org/original"],"notes":"","legs":[{"lineID":"a","fromStationCode":"A","toStationCode":"B"},{"lineID":"b","fromStationCode":"B","toStationCode":"C"}]}]}"#.utf8)

    @Test func explicitVariantsReuseLegsAndRejectAmbiguousPaths() throws {
        var root = try #require(JSONValue(data: base).objectValue)
        var pattern = try #require(root["patterns"]?.arrayValue?.first?.objectValue)
        let variant: JSONValue = .object(["validFrom": .string("2005-01-01"), "validTo": .string("2010-01-01"), "legIndices": .array([.number(0)]), "sourceURLs": .array([.string("https://example.org/history")]), "notes": .string("Short working")])
        let current: JSONValue = .object(["validFrom": .string("2010-01-01"), "legIndices": .array([.number(0), .number(1)]), "sourceURLs": .array([.string("https://example.org/history")]), "notes": .string("Extension")])
        pattern["legVariants"] = .array([variant, current]); root["patterns"] = .array([.object(pattern)])
        let doc = WorkbenchDocument(catalog: .object(root))
        #expect(try doc.patterns(on: "2009-12-31")[0].legs.filter(\.isActive).count == 1)
        #expect(try doc.patterns(on: "2010-01-01")[0].legs.filter(\.isActive).count == 2)
        #expect(try doc.patterns(on: "1996-12-31")[0].isActive == false)
        #expect(try doc.differences(from: "2009-12-31", to: "2010-01-01").count == 1)
        var edited = doc
        #expect(throws: (any Error).self) {
            try edited.add(TemporalPatch(patternID: "service", effectiveFrom: "2010-01-01", changes: ["legs": .array(Array((pattern["legs"]?.arrayValue ?? []).reversed()))], sourceURL: "https://example.org/reorder", note: "Reorder shared legs"))
        }
        pattern["legVariants"] = .array([current, current]); root["patterns"] = .array([.object(pattern)])
        #expect(throws: (any Error).self) { try WorkbenchDocument(catalog: .object(root)).catalog(on: "2010-01-01") }
    }

    @Test func sparseChangeIsHalfOpenAndLossless() throws {
        var doc = WorkbenchDocument(catalog: try JSONValue(data: base))
        try doc.add(TemporalPatch(patternID: "service", effectiveFrom: "2010-01-01", effectiveTo: "2011-01-01",
            legChanges: [LegPatch(index: 1, changes: ["toStationCode": .string("D")])],
            sourceURL: "https://example.org/notice", note: "Temporary extension"))
        #expect(try doc.patterns(on: "2009-12-31")[0].legs[1].toStationCode == "C")
        #expect(try doc.patterns(on: "2010-01-01")[0].legs[1].toStationCode == "D")
        #expect(try doc.patterns(on: "2011-01-01")[0].legs[1].toStationCode == "C")
        let restored = try JSONDecoder().decode(WorkbenchDocument.self, from: JSONEncoder().encode(doc))
        #expect(try restored.catalog(on: "2010-06-01")["futureField"] == .object(["keep": .number(1)]))
        #expect(restored.patches.count == 1)
        #expect(try restored.differences(from: "2009-12-31", to: "2010-01-01").count == 1)
    }

    @Test func coverageFloorDoesNotCertifyAncientService() throws {
        let doc = WorkbenchDocument(catalog: try JSONValue(data: base))
        #expect(try doc.audit(on: "1996-12-31").contains { $0.id == "coverage-before-floor" && $0.severity == .unknown })
        #expect(try doc.audit(on: "2026-10-10").contains { $0.id == "coverage-after-check" })
        #expect(doc.targetFrom == "1996-12-31")
        #expect(try doc.patterns(on: "1996-12-31")[0].statusLabel == "Unknown")
        #expect(try doc.patterns(on: "1996-12-31")[0].activeLegs.isEmpty)
        #expect(try doc.patterns(on: "2005-01-01")[0].statusLabel == "Active")
    }

    @Test func evidenceInvalidDateAndStaleLegAreRejectedWithoutMutation() throws {
        var doc = WorkbenchDocument(catalog: try JSONValue(data: base))
        #expect(throws: (any Error).self) { try doc.add(TemporalPatch(patternID: "service", effectiveFrom: "2024-02-30", sourceURL: "https://example.org/a", note: "bad day")) }
        #expect(throws: (any Error).self) { try doc.add(TemporalPatch(patternID: "service", effectiveFrom: "2024-01-01", sourceURL: "", note: "No evidence")) }
        #expect(throws: (any Error).self) { try doc.add(TemporalPatch(patternID: "service", effectiveFrom: "2024-01-01", legChanges: [LegPatch(index: 99, changes: ["validTo": .string("2024-01-02")])], sourceURL: "https://example.org/a", note: "bad index")) }
        #expect(doc.patches.isEmpty)
    }

    @Test func nullRemovesFieldAndNewPatternCanBeAdded() throws {
        var doc = WorkbenchDocument(catalog: try JSONValue(data: base))
        try doc.add(TemporalPatch(patternID: "service", effectiveFrom: "2005-01-01", changes: ["notes": .null], sourceURL: "https://example.org/a", note: "Remove obsolete note"))
        #expect(try doc.catalog(on: "2005-01-01")["patterns"]?.arrayValue?[0]["notes"] == nil)
        var pattern = try #require(JSONValue(data: base)["patterns"]?.arrayValue?.first?.objectValue)
        pattern["id"] = .string("new")
        try doc.add(TemporalPatch(patternID: "new", effectiveFrom: "2006-01-01", changes: pattern, sourceURL: "https://example.org/b", note: "Add reviewed service"))
        #expect(try doc.patterns(on: "2005-12-31").count == 1)
        #expect(try doc.patterns(on: "2006-01-01").count == 2)
    }

    @Test func continuingGeometryIncludesOmittedSeam() throws {
        let package = try JSONValue(data: Data(#"{"format":"compact-v1","lines":[{"id":"a","stations":[["A","Alpha",139,35],["B","Beta",140,36],["C","Gamma",141,37]],"segments":[[1,0,[[139,35],[140,36]]],[1,1,[[141,37]]]]},{"id":"b","stations":[["B","Beta",140,36],["C","Gamma",141,37]],"segments":[[1,0,[[140,36],[141,37]]]]}]}"#.utf8))
        var doc = WorkbenchDocument(catalog: try JSONValue(data: base), package: package)
        try doc.add(TemporalPatch(patternID: "service", effectiveFrom: "2005-01-01", legChanges: [LegPatch(index: 0, changes: ["fromStationCode": .string("B"), "toStationCode": .string("C")])], sourceURL: "https://example.org/a", note: "Select continuing row"))
        #expect(try doc.patterns(on: "2005-01-01")[0].legs[0].coordinates == [[140,36],[141,37]])
        #expect(try doc.audit(on: "2005-01-01").contains { $0.id == "service-join-0" })
    }
    @Test func exportedSnapshotRetainsRepairEvidence() throws {
        var doc = WorkbenchDocument(catalog: try JSONValue(data: base))
        try doc.add(TemporalPatch(patternID: "service", effectiveFrom: "2010-01-01", changes: ["validFrom": .string("2001-12-01")], sourceURL: "https://example.org/official-onset", note: "Confirmed onset"))
        let exported = try doc.catalog(on: "2010-01-01")
        #expect(exported["workbenchSnapshotDay"] == .string("2010-01-01"))
        #expect(exported["workbenchAppliedPatches"]?.arrayValue?.first?["sourceURL"] == .string("https://example.org/official-onset"))
    }

    @Test func onsetConstraintExcludesServiceBeforeOfficialOpening() throws {
        let seeds = try WorkbenchDocument.reviewedOnsetPatches()
        let patch = try #require(seeds.first { $0.patternID == "JS-utsunomiya-zushi" })
        var root = try #require(JSONValue(data: base).objectValue)
        var pattern = try #require(root["patterns"]?.arrayValue?.first?.objectValue)
        pattern["id"] = .string(patch.patternID)
        root["patterns"] = .array([.object(pattern)])
        var doc = WorkbenchDocument(catalog: .object(root))
        try doc.add(patch)
        #expect(try doc.patterns(on: "2001-11-30").first?.isActive == false)
        #expect(try doc.patterns(on: "2001-12-01").first?.isActive == true)
        #expect(try doc.audit(on: "2001-12-01").contains { $0.severity == .unknown })
    }

    @Test func olderReorderCannotRetargetLaterIndexedCorrection() throws {
        var doc = WorkbenchDocument(catalog: try JSONValue(data: base))
        try doc.add(TemporalPatch(patternID: "service", effectiveFrom: "2010-01-01", legChanges: [LegPatch(index: 1, changes: ["validTo": .string("2020-01-01")])], sourceURL: "https://example.org/a", note: "Close B to C"))
        let reversed = try #require(JSONValue(data: base)["patterns"]?.arrayValue?.first?["legs"]?.arrayValue).reversed()
        #expect(throws: (any Error).self) {
            try doc.add(TemporalPatch(patternID: "service", effectiveFrom: "2009-01-01", changes: ["legs": .array(Array(reversed))], sourceURL: "https://example.org/b", note: "Older reorder"))
        }
        #expect(doc.patches.count == 1)
        #expect(try doc.patterns(on: "2010-01-01")[0].legs[1].lineID == "b")
    }

    @Test func geometryRetainsSurveyedEndpointsForInspection() throws {
        let package = try JSONValue(data: Data(#"{"format":"compact-v1","lines":[{"id":"a","stations":[["A","Alpha",139,35],["B","Beta",140,36]],"segments":[[1,0,[[139.01,35],[139.5,35.5],[140.01,36]]]]},{"id":"b","stations":[["B","Beta",140,36],["C","Gamma",141,37]],"segments":[[1,0,[[140.01,36],[141.01,37]]]]}]}"#.utf8))
        let doc = WorkbenchDocument(catalog: try JSONValue(data: base), package: package)
        let legs = try doc.patterns(on: "2005-01-01")[0].legs
        #expect(legs[0].coordinates == [[139.01,35],[139.5,35.5],[140.01,36]])
        #expect(legs[1].coordinates == [[140.01,36],[141.01,37]])
    }

    @Test func sharedCodeDoesNotProveCoincidentPhysicalEndpoints() throws {
        let package = try JSONValue(data: Data(#"{"format":"compact-v1","lines":[{"id":"a","stations":[["A","Alpha",139,35],["B","Beta",140,36]],"segments":[[1,0,[[139,35],[140,36]]]]},{"id":"b","stations":[["B","Beta",140.001,36],["C","Gamma",141,37]],"segments":[[1,0,[[140.001,36],[141,37]]]]}]}"#.utf8))
        let doc = WorkbenchDocument(catalog: try JSONValue(data: base), package: package)
        #expect(try doc.audit(on: "2005-01-01").contains { $0.id == "service-physical-gap-0" && $0.severity == .warning })
    }

    @Test func onsetEvidenceKeepsEndpointCoverageUnresolvedAfterCoverageFloor() throws {
        let patch = try #require(WorkbenchDocument.reviewedOnsetPatches().first)
        var root = try #require(JSONValue(data: base).objectValue)
        var pattern = try #require(root["patterns"]?.arrayValue?.first?.objectValue)
        pattern["id"] = .string(patch.patternID)
        root["patterns"] = .array([.object(pattern)])
        var doc = WorkbenchDocument(catalog: .object(root))
        try doc.add(patch)
        #expect(try doc.audit(on: "2005-01-01").contains { $0.id == "\(patch.patternID)-onset-scope" && $0.severity == .unknown })
    }

}
