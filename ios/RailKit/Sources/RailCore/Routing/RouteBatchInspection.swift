import Foundation

/// Read-only consistency checks over actual route inputs and published results.
/// This does not solve routes or certify topology, dates, or surveyed geometry.
public enum RouteBatchInspection {
    public enum Severity: String, Codable, Sendable { case failure, review, info }

    public struct Finding: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let severity: Severity
        public let code: String
        public let trainID: String?
        public let sectionIndex: Int?
        public let message: String

        public init(id: String, severity: Severity, code: String, trainID: String?,
                    sectionIndex: Int?, message: String) {
            self.id = id
            self.severity = severity
            self.code = code
            self.trainID = trainID
            self.sectionIndex = sectionIndex
            self.message = message
        }
    }

    public struct Gap: Codable, Equatable, Sendable {
        public let index: Int
        public let isBoundary: Bool

        public init(index: Int, isBoundary: Bool) {
            self.index = index
            self.isBoundary = isBoundary
        }
    }

    public struct Selection: Codable, Equatable, Sendable {
        public let fromCode: String
        public let toCode: String
        public let intervals: [StationIntervalResolver.DirectedInterval]
        public let provenance: String

        public init(fromCode: String, toCode: String,
                    intervals: [StationIntervalResolver.DirectedInterval], provenance: String) {
            self.fromCode = fromCode
            self.toCode = toCode
            self.intervals = intervals
            self.provenance = provenance
        }

        /// Metadata shape only; this does not establish physical interval proof.
        public var isStructurallyValid: Bool {
            func blank(_ value: String) -> Bool {
                value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return !blank(fromCode) && !blank(toCode) && !intervals.contains {
                blank($0.lineID) || blank($0.code) || ![-1, 1].contains($0.direction)
            }
        }
    }

    public struct Segment: Sendable {
        public let index: Int
        public let partIndex: Int
        public let sourceCoordinates: [Coordinate]
        public let intervalSelection: Selection?
        /// Historical replacement intervals need not share today's authored codes.
        public let isCurrent: Bool

        public init(index: Int, partIndex: Int, sourceCoordinates: [Coordinate],
                    intervalSelection: Selection? = nil, isCurrent: Bool = true) {
            self.index = index
            self.partIndex = partIndex
            self.sourceCoordinates = sourceCoordinates
            self.intervalSelection = intervalSelection
            self.isCurrent = isCurrent
        }
    }

    public struct Result: Sendable {
        public let trainID: String
        public let expectedSectionCount: Int
        /// Canonical sections with geometry and no recorded physical gap.
        /// Multipart strokes count once. Legacy nonauthoritative indices do not
        /// establish this count; pass the published outcome's count instead.
        public let resolvedSectionCount: Int
        public let isResolved: Bool
        public let physicalGaps: [Gap]
        public let segments: [Segment]
        public let indicesAreAuthoritative: Bool

        public init(trainID: String, expectedSectionCount: Int, resolvedSectionCount: Int,
                    isResolved: Bool, physicalGaps: [Gap] = [], segments: [Segment],
                    indicesAreAuthoritative: Bool = true) {
            self.trainID = trainID
            self.expectedSectionCount = expectedSectionCount
            self.resolvedSectionCount = resolvedSectionCount
            self.isResolved = isResolved
            self.physicalGaps = physicalGaps
            self.segments = segments
            self.indicesAreAuthoritative = indicesAreAuthoritative
        }
    }

    /// `finished` means the batch completed, not that it was canceled or failed.
    /// Finding IDs use input/result/segment positions, so duplicate or absent
    /// train IDs remain individually addressable and repeat inspection is stable.
    public static func inspect(trains: [Train], results: [Result], finished: Bool,
                               failureReason: String? = nil) -> [Finding] {
        var findings: [Finding] = []
        func add(_ scope: String, _ severity: Severity, _ code: String,
                 _ trainID: String?, section: Int? = nil, _ message: String) {
            findings.append(Finding(id: scope + "/" + code, severity: severity, code: code,
                                    trainID: trainID, sectionIndex: section, message: message))
        }
        func blank(_ value: String) -> Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let failureReason, !blank(failureReason) {
            add("batch", .failure, "batch_failed", nil, failureReason)
        }
        let trainsByID = Dictionary(grouping: trains.indices, by: { trains[$0].id })
        let resultsByID = Dictionary(grouping: results.indices, by: { results[$0].trainID })

        for (index, train) in trains.enumerated() {
            let scope = "input/\(index)"
            if blank(train.id) {
                add(scope, .failure, "missing_train_id", nil, "Input train has no usable ID.")
            } else if (trainsByID[train.id]?.count ?? 0) > 1 {
                add(scope, .failure, "duplicate_train_id", train.id, "Input train ID occurs more than once.")
            }
            if train.requiresRouteConfirmation {
                add(scope, .info, "pending_confirmation", train.id,
                    "Pending route hints remain outside physical route resolution.")
            } else if !blank(train.id), resultsByID[train.id] == nil {
                add(scope, finished ? .failure : .review, "missing_result", train.id,
                    finished ? "Completed batch did not publish a result for this train."
                             : "Batch has not completed; this train has no published result yet.")
            }
        }

        for (resultIndex, result) in results.enumerated() {
            let scope = "result/\(resultIndex)"
            if blank(result.trainID) {
                add(scope, .failure, "missing_result_id", nil, "Result has no usable train ID.")
            } else if trainsByID[result.trainID] == nil {
                add(scope, .failure, "foreign_result_id", result.trainID, "Result refers to a train outside this batch.")
            }
            if (resultsByID[result.trainID]?.count ?? 0) > 1 {
                add(scope, .failure, "duplicate_result_id", result.trainID,
                    "More than one result was published for this train ID.")
            }
            // An ambiguous input ID cannot support a comparison to one author.
            let train = trainsByID[result.trainID].flatMap { indices in
                indices.count == 1 ? trains[indices[0]] : nil
            }
            let sections = train.map { TrainValidation.routeSectionsForSolving(for: $0) }
            if train?.requiresRouteConfirmation == true {
                if result.isResolved || result.resolvedSectionCount > 0 || !result.segments.isEmpty {
                    add(scope, .failure, "pending_result", result.trainID,
                        "A pending route hint unexpectedly produced a solved route or geometry.")
                }
                continue
            }
            if let sections, result.expectedSectionCount != sections.count {
                add(scope, .failure, "expected_count_mismatch", result.trainID,
                    "Result expects \(result.expectedSectionCount) sections; input has \(sections.count).")
            }
            if result.expectedSectionCount < 0 || result.resolvedSectionCount < 0
                || result.resolvedSectionCount > result.expectedSectionCount {
                add(scope, .failure, "invalid_section_counts", result.trainID,
                    "Section counts are negative or resolved count exceeds expected count.")
            }
            if result.isResolved && result.resolvedSectionCount != result.expectedSectionCount {
                add(scope, .failure, "resolved_status_mismatch", result.trainID,
                    "Resolved status disagrees with the published section counts.")
            }
            if result.isResolved && !result.physicalGaps.isEmpty {
                add(scope, .failure, "resolved_physical_gap", result.trainID,
                    "Resolved status still carries a physical section or boundary gap.")
            }
            if !result.isResolved {
                add(scope, .review, result.segments.isEmpty ? "route_unavailable" : "route_partial", result.trainID,
                    "Published route is incomplete; review available evidence and unresolved sections.")
            }
            if !result.indicesAreAuthoritative {
                add(scope, .review, "section_indices_unavailable", result.trainID,
                    "Legacy stroke indices cannot prove coverage of canonical route sections.")
            }

            var partsBySection: [Int: Set<Int>] = [:]
            var selectionsBySection: [Int: Selection] = [:]
            for (segmentIndex, segment) in result.segments.enumerated() {
                let segmentScope = scope + "/segment/\(segmentIndex)"
                if segment.index < 0 || segment.partIndex < 0
                    || (result.indicesAreAuthoritative && segment.index >= result.expectedSectionCount) {
                    add(segmentScope, .failure, "invalid_segment_index", result.trainID, section: segment.index,
                        "Segment section or multipart index is outside its declared range.")
                }
                if !partsBySection[segment.index, default: []].insert(segment.partIndex).inserted {
                    add(segmentScope, .failure, "duplicate_segment_part", result.trainID, section: segment.index,
                        "Section and multipart index identify more than one stroke.")
                }
                if segment.sourceCoordinates.count < 2 {
                    add(segmentScope, .failure, "short_geometry", result.trainID, section: segment.index,
                        "Source railway stroke has fewer than two coordinates.")
                }
                if !segment.sourceCoordinates.allSatisfy({ $0.lon.isFinite && $0.lat.isFinite }) {
                    add(segmentScope, .failure, "nonfinite_geometry", result.trainID, section: segment.index,
                        "Source railway geometry contains a nonfinite coordinate.")
                }
                guard let selection = segment.intervalSelection else {
                    add(segmentScope, .review, "physical_intervals_unavailable", result.trainID, section: segment.index,
                        "Geometry has no physical interval selection; drawing alone does not certify a route.")
                    continue
                }
                if !selection.isStructurallyValid {
                    add(segmentScope, .failure, "malformed_selection", result.trainID, section: segment.index,
                        "Physical selection has an empty identity or endpoint, or an invalid direction.")
                }
                if selection.intervals.isEmpty || selection.provenance == "matchedGeometry" {
                    add(segmentScope, .review, "physical_intervals_unproven", result.trainID, section: segment.index,
                        "Missing or geometry-matched intervals require physical evidence review.")
                }
                if let previous = selectionsBySection[segment.index],
                   previous.fromCode != selection.fromCode || previous.toCode != selection.toCode
                    || previous.intervals != selection.intervals {
                    add(segmentScope, .failure, "multipart_selection_conflict", result.trainID, section: segment.index,
                        "Multipart strokes of one section carry different physical choices.")
                } else {
                    selectionsBySection[segment.index] = selection
                }
                if result.indicesAreAuthoritative, segment.isCurrent,
                   selection.provenance != "matchedGeometry", !selection.intervals.isEmpty,
                   let sections, sections.indices.contains(segment.index),
                   let authored = sections[segment.index].sectionCodes, !authored.isEmpty,
                   authored != selection.intervals.map(\.code) {
                    add(segmentScope, .failure, "authored_interval_conflict", result.trainID, section: segment.index,
                        "Current physical selection changed the authored interval order or repetitions.")
                }
            }
            for (gapIndex, gap) in result.physicalGaps.enumerated() {
                if gap.index < 0 || (result.indicesAreAuthoritative && gap.index >= result.expectedSectionCount) {
                    add(scope + "/gap/\(gapIndex)", .failure, "invalid_gap_index", result.trainID, section: gap.index,
                        "Physical gap refers to a section outside its declared range.")
                }
            }
            if result.indicesAreAuthoritative {
                let drawn = Set(result.segments.map(\.index).filter {
                    $0 >= 0 && $0 < result.expectedSectionCount
                })
                let certified = drawn.subtracting(result.physicalGaps.map(\.index))
                if certified.count != result.resolvedSectionCount {
                    add(scope, .failure, "resolved_count_mismatch", result.trainID,
                        "Published resolved count disagrees with unique drawn sections after physical gaps.")
                }
            }
        }
        return findings
    }

    /// Checks the actual exported payload after decoding it. Physical enrichment
    /// may populate empty interval/line choices, while every other train and
    /// section field and every existing ordered choice must survive unchanged.
    public static func inspectExport(originals: [Train], exported: [Train]) -> [Finding] {
        var findings: [Finding] = []
        func add(_ scope: String, _ code: String, _ trainID: String?,
                 section sectionIndex: Int? = nil, _ message: String) {
            findings.append(Finding(id: scope + "/" + code, severity: .failure,
                                    code: code, trainID: trainID, sectionIndex: sectionIndex,
                                    message: message))
        }
        if originals.count != exported.count {
            add("export", "export.train_count", nil,
                "Export changed the number of trains from \(originals.count) to \(exported.count).")
        }
        for (index, pair) in zip(originals, exported).enumerated() {
            let (original, candidate) = pair
            let scope = "export/train/\(index)"
            if original.id != candidate.id {
                add(scope, "export.train_identity", original.id,
                    "Export changed train identity or train order at this position.")
            }
            var originalMetadata = original
            var candidateMetadata = candidate
            originalMetadata.routeSections = nil
            candidateMetadata.routeSections = nil
            if originalMetadata != candidateMetadata {
                add(scope, "export.train_metadata", original.id,
                    "Export changed train fields outside its physical route sections.")
            }
            // The export path may generate sections for a train whose author
            // supplied none. Compare those boundaries with the same production
            // template; an existing authored chain remains the exact authority.
            let originalSections: [RouteSection]
            if let authored = original.routeSections, !authored.isEmpty {
                originalSections = authored
            } else if candidate.routeSections?.isEmpty == false {
                originalSections = TrainValidation.normalizeExportTrain(
                    TrainValidation.restoringRouteSectionEndpointNames(original),
                    country: original.region ?? "jp", stations: .empty).routeSections ?? []
            } else {
                originalSections = original.routeSections ?? []
            }
            let candidateSections = candidate.routeSections ?? []
            if originalSections.count != candidateSections.count {
                add(scope, "export.section_count", original.id,
                    "Export changed the number of authored route sections.")
            }
            for (sectionIndex, sectionPair) in zip(originalSections, candidateSections).enumerated() {
                let (authored, selected) = sectionPair
                let sectionScope = scope + "/section/\(sectionIndex)"
                if let codes = authored.sectionCodes, !codes.isEmpty, codes != selected.sectionCodes {
                    add(sectionScope, "export.authored_codes", original.id, section: sectionIndex,
                        "Export changed the authored interval order or repetitions.")
                }
                if let lineIDs = authored.lineIDs, !lineIDs.isEmpty, lineIDs != selected.lineIDs {
                    add(sectionScope, "export.authored_line_ids", original.id, section: sectionIndex,
                        "Export changed the authored line identities or their order.")
                }
                var authoredMetadata = authored
                var selectedMetadata = selected
                authoredMetadata.sectionCodes = nil
                authoredMetadata.lineIDs = nil
                selectedMetadata.sectionCodes = nil
                selectedMetadata.lineIDs = nil
                if authoredMetadata != selectedMetadata {
                    add(sectionScope, "export.section_metadata", original.id, section: sectionIndex,
                        "Export changed section boundaries or service metadata.")
                }
            }
        }
        return findings
    }
}
