import Foundation
import Testing
@testable import RailCore

struct RouteBatchInspectionTests {
    private typealias Inspection = RouteBatchInspection

    private func train(id: String = "ride", codes: [String]? = nil,
                       pending: Bool = false) -> Train {
        Train(id: id, number: "1", origin: "A", destination: "B",
              routeSections: [RouteSection(fromN02StationCode: "A", toN02StationCode: "B",
                                           sectionCodes: codes)],
              stops: [Stop(name: "A", n02StationCode: "A"),
                      Stop(name: "B", n02StationCode: "B")],
              routeConfirmation: pending ? .pending : nil)
    }

    private func selection(codes: [String] = ["ab"], provenance: String = "explicit",
                           direction: Int = 1) -> Inspection.Selection {
        Inspection.Selection(fromCode: "A", toCode: "B", intervals: codes.map {
            StationIntervalResolver.DirectedInterval(lineID: "line", code: $0, direction: direction)
        }, provenance: provenance)
    }

    private func segment(index: Int = 0, part: Int = 0,
                         selection: Inspection.Selection? = nil,
                         current: Bool = true) -> Inspection.Segment {
        Inspection.Segment(index: index, partIndex: part,
                           sourceCoordinates: [Coordinate(lon: 130, lat: 35),
                                               Coordinate(lon: 131, lat: 35)],
                           intervalSelection: selection, isCurrent: current)
    }

    @Test func failedBatchRetainsReasonWithoutClaimingPendingRowsAreFailures() {
        let findings = Inspection.inspect(trains: [train()], results: [], finished: false,
                                          failureReason: "Bundled network unavailable")
        #expect(findings.contains { $0.code == "batch_failed" && $0.severity == .failure
            && $0.message == "Bundled network unavailable" })
        #expect(findings.contains { $0.code == "missing_result" && $0.severity == .review })
        #expect(findings.filter { $0.severity == .failure }.count == 1)
        let decoded = try? JSONDecoder().decode([Inspection.Finding].self,
                                               from: JSONEncoder().encode(findings))
        #expect(decoded == findings)
    }

    @Test func rejectsResolvedStatusWhenPhysicalGapRemains() {
        let result = Inspection.Result(trainID: "ride", expectedSectionCount: 1,
            resolvedSectionCount: 1, isResolved: true,
            physicalGaps: [Inspection.Gap(index: 0, isBoundary: true)],
            segments: [segment(selection: selection())])
        let findings = Inspection.inspect(trains: [train()], results: [result], finished: true)
        #expect(findings.contains { $0.code == "resolved_physical_gap" && $0.severity == .failure })
    }

    @Test func reportsDuplicateAndMissingIdentitiesWithoutLosingFindings() {
        let trains = [train(id: ""), train(), train()]
        let result = Inspection.Result(trainID: "ride", expectedSectionCount: 1,
            resolvedSectionCount: 0, isResolved: false, segments: [])
        let findings = Inspection.inspect(trains: trains, results: [result, result], finished: true)
        #expect(findings.contains { $0.code == "missing_train_id" })
        #expect(findings.filter { $0.code == "duplicate_train_id" }.count == 2)
        #expect(findings.filter { $0.code == "duplicate_result_id" }.count == 2)
        #expect(Set(findings.map(\.id)).count == findings.count)
        #expect(Inspection.inspect(trains: trains, results: [result, result], finished: true) == findings)
    }

    @Test func acceptsMultipartGeometryAsOneResolvedSection() {
        let result = Inspection.Result(trainID: "ride", expectedSectionCount: 1,
            resolvedSectionCount: 1, isResolved: true,
            segments: [segment(selection: selection()), segment(part: 1, selection: selection())])
        #expect(Inspection.inspect(trains: [train(codes: ["ab"])], results: [result], finished: true).isEmpty)
    }

    @Test func detectsConflictingPhysicalChoicesAcrossMultipartStrokes() {
        let result = Inspection.Result(trainID: "ride", expectedSectionCount: 1,
            resolvedSectionCount: 1, isResolved: true,
            segments: [segment(selection: selection()), segment(part: 1, selection: selection(codes: ["other"]))])
        #expect(Inspection.inspect(trains: [train()], results: [result], finished: true)
            .contains { $0.code == "multipart_selection_conflict" && $0.severity == .failure })
    }

    @Test func preservesAuthoredOrderAndRepeatsForCurrentPhysicalChoices() {
        let authored = train(codes: ["ab", "ba", "ab"])
        let result = Inspection.Result(trainID: "ride", expectedSectionCount: 1,
            resolvedSectionCount: 1, isResolved: true,
            segments: [segment(selection: selection(codes: ["ab", "ab", "ba"]))])
        #expect(Inspection.inspect(trains: [authored], results: [result], finished: true)
            .contains { $0.code == "authored_interval_conflict" && $0.severity == .failure })
        for stroke in [segment(selection: selection(provenance: "matchedGeometry")),
                       segment(selection: selection(), current: false)] {
            let exempt = Inspection.Result(trainID: "ride", expectedSectionCount: 1,
                resolvedSectionCount: 1, isResolved: true, segments: [stroke])
            #expect(!Inspection.inspect(trains: [authored], results: [exempt], finished: true)
                .contains { $0.code == "authored_interval_conflict" })
        }
    }

    @Test func rejectsShortAndNonfiniteSourceGeometry() {
        let result = Inspection.Result(trainID: "ride", expectedSectionCount: 1,
            resolvedSectionCount: 1, isResolved: true,
            segments: [Inspection.Segment(index: 0, partIndex: 0,
                sourceCoordinates: [Coordinate(lon: 130, lat: 35)], intervalSelection: selection()),
                Inspection.Segment(index: 0, partIndex: 1,
                sourceCoordinates: [Coordinate(lon: .infinity, lat: 35), Coordinate(lon: 131, lat: .nan)],
                intervalSelection: selection())])
        let findings = Inspection.inspect(trains: [train()], results: [result], finished: true)
        #expect(findings.contains { $0.code == "short_geometry" && $0.severity == .failure })
        #expect(findings.contains { $0.code == "nonfinite_geometry" && $0.severity == .failure })
    }

    @Test func finishedMissingResultsFailButInterruptedResultsRemainReviewable() {
        let trains = [train(), train(id: "pending", pending: true)]
        let finished = Inspection.inspect(trains: trains, results: [], finished: true)
        #expect(finished.filter { $0.code == "missing_result" && $0.severity == .failure }.count == 1)
        #expect(!finished.contains { $0.code == "missing_result" && $0.trainID == "pending" })
        let canceled = Inspection.inspect(trains: trains, results: [], finished: false)
        #expect(!canceled.contains { $0.severity == .failure })
        #expect(canceled.contains { $0.code == "missing_result" && $0.severity == .review })
    }

    @Test func pendingHintMustNotProduceSolvedGeometry() {
        let result = Inspection.Result(trainID: "ride", expectedSectionCount: 0,
            resolvedSectionCount: 0, isResolved: true, segments: [segment(selection: selection())])
        #expect(Inspection.inspect(trains: [train(pending: true)], results: [result], finished: true)
            .contains { $0.code == "pending_result" && $0.severity == .failure })
    }

    @Test func unavailableAndGeometryOnlyResultsNeedReviewWithoutInventingPhysicalProof() {
        for result in [
            Inspection.Result(trainID: "ride", expectedSectionCount: 1, resolvedSectionCount: 0,
                              isResolved: false, segments: []),
            Inspection.Result(trainID: "ride", expectedSectionCount: 1, resolvedSectionCount: 1,
                              isResolved: true, segments: [segment()]),
            Inspection.Result(trainID: "ride", expectedSectionCount: 1, resolvedSectionCount: 1,
                              isResolved: true, segments: [segment(selection: selection(provenance: "matchedGeometry"))])
        ] {
            let findings = Inspection.inspect(trains: [train()], results: [result], finished: true)
            #expect(findings.contains { $0.severity == .review })
            #expect(!findings.contains { $0.severity == .failure })
        }
    }

    @Test func rejectsMalformedSelectionAndDuplicatePartIdentity() {
        let malformed = Inspection.Selection(fromCode: "", toCode: "B", intervals: [
            .init(lineID: "", code: "ab", direction: 0)
        ], provenance: "explicit")
        let result = Inspection.Result(trainID: "ride", expectedSectionCount: 1,
            resolvedSectionCount: 1, isResolved: true,
            segments: [segment(selection: malformed), segment(selection: malformed)])
        let findings = Inspection.inspect(trains: [train()], results: [result], finished: true)
        #expect(findings.contains { $0.code == "malformed_selection" && $0.severity == .failure })
        #expect(findings.contains { $0.code == "duplicate_segment_part" && $0.severity == .failure })
    }

    @Test func selectionStructureRetainsSourceIDsWithoutClaimingIntervalProof() {
        let source = Inspection.Selection(fromCode: "CN-OSM-N1588514426",
            toCode: "CN-OSM-N1588514327", intervals: [], provenance: "matchedGeometry")
        #expect(source.isStructurallyValid)
        let result = Inspection.Result(trainID: "ride", expectedSectionCount: 1,
            resolvedSectionCount: 1, isResolved: true, segments: [segment(selection: source)])
        let findings = Inspection.inspect(trains: [train()], results: [result], finished: true)
        #expect(findings.contains { $0.code == "physical_intervals_unproven" && $0.severity == .review })
        #expect(!findings.contains { $0.code == "malformed_selection" })
        for invalid in [
            Inspection.Selection(fromCode: " ", toCode: source.toCode, intervals: [], provenance: "matchedGeometry"),
            Inspection.Selection(fromCode: source.fromCode, toCode: "", intervals: [], provenance: "matchedGeometry"),
            Inspection.Selection(fromCode: source.fromCode, toCode: source.toCode,
                intervals: [.init(lineID: "source", code: "interval", direction: 0)], provenance: "explicit")
        ] {
            #expect(!invalid.isStructurallyValid)
        }
    }

    @Test func nonauthoritativePrecomputedIndicesDoNotMasqueradeAsSectionCoverage() {
        let result = Inspection.Result(trainID: "ride", expectedSectionCount: 1,
            resolvedSectionCount: 1, isResolved: true, segments: [segment(index: 8)],
            indicesAreAuthoritative: false)
        let findings = Inspection.inspect(trains: [train()], results: [result], finished: true)
        #expect(!findings.contains { $0.severity == .failure })
        #expect(findings.contains { $0.code == "section_indices_unavailable" && $0.severity == .review })
    }

    @Test func reportsForeignResultAndFalseCoverage() {
        let foreign = Inspection.Result(trainID: "unknown", expectedSectionCount: 1,
            resolvedSectionCount: 1, isResolved: true, segments: [segment(selection: selection())])
        let falseCoverage = Inspection.Result(trainID: "ride", expectedSectionCount: 1,
            resolvedSectionCount: 1, isResolved: true, segments: [])
        let findings = Inspection.inspect(trains: [train()], results: [foreign, falseCoverage], finished: true)
        #expect(findings.contains { $0.code == "foreign_result_id" && $0.severity == .failure })
        #expect(findings.contains { $0.code == "resolved_count_mismatch" && $0.severity == .failure })
    }

    @Test func exportInspectionDetectsLostOrReorderedTrains() {
        let originals = [train(id: "first"), train(id: "second")]
        #expect(Inspection.inspectExport(originals: originals, exported: [originals[0]])
            .contains { $0.code == "export.train_count" && $0.severity == .failure })
        #expect(Inspection.inspectExport(originals: originals, exported: Array(originals.reversed()))
            .contains { $0.code == "export.train_identity" && $0.severity == .failure })
    }

    @Test func exportInspectionProtectsTrainAndSectionMetadata() {
        let original = train(codes: ["ab", "ba", "ab"])
        var changedTrain = original
        changedTrain.number = "2"
        #expect(Inspection.inspectExport(originals: [original], exported: [changedTrain])
            .contains { $0.code == "export.train_metadata" })
        var changedSection = original
        changedSection.routeSections?[0].toN02StationCode = "C"
        #expect(Inspection.inspectExport(originals: [original], exported: [changedSection])
            .contains { $0.code == "export.section_metadata" })
        var changedChoice = original
        changedChoice.routeSections?[0].sectionCodes = ["ab", "ab", "ba"]
        #expect(Inspection.inspectExport(originals: [original], exported: [changedChoice])
            .contains { $0.code == "export.authored_codes" })
        var lineConstrained = original
        lineConstrained.routeSections?[0].lineIDs = ["original-line"]
        var changedLine = lineConstrained
        changedLine.routeSections?[0].lineIDs = ["other-line"]
        #expect(Inspection.inspectExport(originals: [lineConstrained], exported: [changedLine])
            .contains { $0.code == "export.authored_line_ids" })
    }

    @Test func exportInspectionAllowsConfirmedIntervalEnrichmentAndJSONRoundTrip() throws {
        let original = train()
        var enriched = original
        enriched.routeSections?[0].sectionCodes = ["ab"]
        enriched.routeSections?[0].lineIDs = ["line"]
        let roundTripped = try JSONDecoder().decode([Train].self, from: JSONEncoder().encode([enriched]))
        #expect(Inspection.inspectExport(originals: [original], exported: roundTripped).isEmpty)
        var removedSection = enriched
        removedSection.routeSections = []
        #expect(Inspection.inspectExport(originals: [original], exported: [removedSection])
            .contains { $0.code == "export.section_count" })
    }

    @Test func exportInspectionAllowsCanonicalSectionsWhenNoneWereAuthored() {
        let absentSections: [[RouteSection]?] = [nil, []]
        for authoredSections in absentSections {
            var original = train()
            original.routeSections = authoredSections
            // Unavailable or ineligible rows are exported without enrichment.
            #expect(Inspection.inspectExport(originals: [original], exported: [original]).isEmpty)
            var enriched = original
            enriched.routeSections = TrainValidation.normalizeExportTrain(
                TrainValidation.restoringRouteSectionEndpointNames(original),
                country: original.region ?? "jp", stations: .empty).routeSections
            enriched.routeSections?[0].sectionCodes = ["ab"]
            enriched.routeSections?[0].lineIDs = ["line"]
            #expect(Inspection.inspectExport(originals: [original], exported: [enriched]).isEmpty)
            enriched.routeSections?[0].toN02StationCode = "C"
            #expect(Inspection.inspectExport(originals: [original], exported: [enriched])
                .contains { $0.code == "export.section_metadata" })
        }
    }
}
