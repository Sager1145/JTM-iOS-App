import Foundation
import Testing
@testable import RailInspection

@Test @MainActor func captureAdmissionExcludesEverySnapshotScope() throws {
    for first in [InspectionCaptureAdmission.Scope.manual, .batch, .analysis] {
        let admission = InspectionCaptureAdmission()
        let lease = try #require(admission.begin(first))
        #expect(admission.begin(.manual) == nil)
        #expect(admission.begin(.batch) == nil)
        #expect(admission.begin(.analysis) == nil)
        admission.finish(lease)
        #expect(admission.scope == nil)
        let next = try #require(admission.begin(.analysis))
        admission.finish(next)
    }
}

@Test @MainActor func captureAdmissionKeepsLeaseUntilItsOwnerFinishes() throws {
    let admission = InspectionCaptureAdmission()
    let batchLease = try #require(admission.begin(.batch))
    // Requesting cancellation does not finish the in-flight snapshot. Its
    // owner releases admission only after the cancelled task has returned.
    #expect(admission.begin(.manual) == nil)
    admission.finish(UUID())
    #expect(admission.begin(.manual) == nil)
    admission.finish(batchLease)
    let manualLease = try #require(admission.begin(.manual))
    admission.finish(batchLease)
    #expect(admission.scope == .manual)
    admission.finish(manualLease)
    #expect(admission.scope == nil)
}

private func batchPoint(_ metres: Double, _ north: Double = 0) -> InspectionPoint {
    .init(longitude: metres / 111_195, latitude: north / 111_195)
}

private func batchInput(_ id: String, _ display: [InspectionPoint]) -> InspectionInput {
    .init(id: id, lineID: "line", lineName: "line", operatorName: "operator",
          intervalIndex: 0, fromStationID: "a", toStationID: "b", fromName: "a", toName: "b",
          source: display, display: display, hasDisplayOverride: false)
}

@Test func batchUsesDisplayArclengthAndIncludesTail() throws {
    var input = batchInput("span", [batchPoint(0), batchPoint(400), batchPoint(800)])
    input.source = [batchPoint(0), batchPoint(10)]
    let plan = BatchInspectionPlan.build(inputs: [input], packageVersion: "v")
    #expect(plan.viewpoints.count == 4)
    #expect(plan.viewpoints.map(\.pointOrdinal) == [0, 1, 2, 3])
    #expect(plan.viewpoints.first?.coordinate == input.display.first)
    #expect(plan.viewpoints.last?.coordinate == input.display.last)
    #expect(abs(plan.viewpoints[1].distanceMetres - 350) < 0.0001)
    #expect(abs(plan.viewpoints[2].distanceMetres - 700) < 0.0001)
    #expect(abs(plan.viewpoints[1].coordinate.longitude * 111_195 - 350) < 0.01)
}

@Test func specifiedHighZoomRetainsOverlappingCoverageAndEndpoints() throws {
    let input = batchInput("span", [batchPoint(0), batchPoint(400), batchPoint(813)])
    let settings = DiagnosticCaptureSettings(zoom: 20, width: 256, height: 256)
    let plan = try BatchInspectionPlan.build(inputs: [input], packageVersion: "v", settings: settings)
    // At the equator a z20 256-point viewport is about 38.2m wide.
    #expect(plan.spacingMetres < 16)
    #expect(plan.viewpoints.count > 50)
    #expect(plan.viewpoints.first?.coordinate == input.display.first)
    #expect(plan.viewpoints.last?.coordinate == input.display.last)
    #expect(zip(plan.viewpoints, plan.viewpoints.dropFirst()).allSatisfy { pair in pair.1.distanceMetres - pair.0.distanceMetres < 16 })
    let northern = batchInput("north", input.display.map { .init(longitude: $0.longitude, latitude: 60) })
    #expect(try settings.coverageSpacingMetres(inputs: [northern]) < 8)
    var saved = BatchInspectionCheckpoint(plan: plan)
    saved.record(viewpoint: plan.viewpoints[0], status: .captured, evidencePaths: ["smooth.png"])
    let dark = DiagnosticCaptureSettings(zoom: 20, width: 256, height: 256, appearance: .dark)
    let changed = try BatchInspectionPlan.build(inputs: [input], packageVersion: "v", settings: dark)
    #expect(saved.resumed(for: changed).progress.allSatisfy { $0.status == .pending })
}

@Test func scopedEvidencePlanPreservesOriginalTargetsAndRejectsChangedInputs() throws {
    let selected = batchInput("z-selected", [batchPoint(0), batchPoint(813)])
    let northern = batchInput("a-north", [.init(longitude: 0, latitude: 60), .init(longitude: 0.01, latitude: 60)])
    let settings = DiagnosticCaptureSettings(zoom: 20, width: 256, height: 256)
    let broader = try BatchInspectionPlan.build(inputs: [selected, northern], packageVersion: "v", settings: settings)
    let independent = try BatchInspectionPlan.build(inputs: [selected], packageVersion: "v", settings: settings)
    #expect(broader.spacingMetres < independent.spacingMetres)
    let scoped = try broader.scoped(to: [selected], packageVersion: "next", settings: settings)
    #expect(scoped.items == broader.items.filter { $0.itemID == selected.id })
    #expect(scoped.spacingMetres == broader.spacingMetres)
    #expect(scoped.viewpoints.first?.coordinate == selected.display.first)
    #expect(scoped.viewpoints.last?.coordinate == selected.display.last)
    #expect(broader.captureDirectoryIndices[selected.id] == 1)
    var changed = selected
    changed.source[0] = batchPoint(1)
    #expect(throws: DiagnosticError.self) { try broader.scoped(to: [changed], packageVersion: "v", settings: settings) }
    let addition = batchInput("new", [batchPoint(0), batchPoint(10)])
    #expect(throws: DiagnosticError.self) { try broader.scoped(to: [selected, addition], packageVersion: "v", settings: settings) }
    #expect(throws: DiagnosticError.self) { try broader.scoped(to: [selected], packageVersion: "v", settings: .init(zoom: 19)) }
}

@Test func batchSamplesClosedLoopDespiteCoincidentEndpoints() {
    let input = batchInput("loop", [batchPoint(0), batchPoint(400), batchPoint(0)])
    let plan = BatchInspectionPlan.build(inputs: [input], packageVersion: "v")
    #expect(plan.viewpoints.count == 4)
    #expect(plan.viewpoints.first?.coordinate == plan.viewpoints.last?.coordinate)
    #expect(Set(plan.viewpoints.map(\.id)).count == 4)
    #expect(plan.viewpoints[1].coordinate != plan.viewpoints[2].coordinate)
}

@Test func batchRetainsUnknownGeometryWithoutInventedBridges() throws {
    let inputs = [batchInput("empty", []), batchInput("invalid", [batchPoint(0),
        .init(longitude: .nan, latitude: 0), batchPoint(900)]),
        batchInput("outOfRange", [.init(longitude: 181, latitude: 0)]),
        batchInput("point", [batchPoint(10)])]
    let plan = BatchInspectionPlan.build(inputs: inputs, packageVersion: "v")
    #expect(Set(plan.items.map(\.itemID)) == Set(inputs.map(\.id)))
    #expect(plan.items.first { $0.itemID == "empty" }?.geometryStatus == .empty)
    #expect(plan.items.first { $0.itemID == "invalid" }?.geometryStatus == .invalid)
    #expect(plan.items.first { $0.itemID == "outOfRange" }?.geometryStatus == .invalid)
    #expect(plan.viewpoints.count == 1)
    #expect(plan.viewpoints.first?.itemID == "point")
    let checkpoint = BatchInspectionCheckpoint(plan: plan)
    let decoded = try JSONDecoder().decode(BatchInspectionCheckpoint.self,
                                            from: JSONEncoder().encode(checkpoint))
    #expect(decoded.resumed(for: plan) == checkpoint)
}

@Test func batchOrderingAndIdentitiesAreDeterministic() throws {
    let inputs = [batchInput("ordinary", [batchPoint(0), batchPoint(10), batchPoint(20)]),
                  batchInput("priority", [])]
    let first = BatchInspectionPlan.build(inputs: inputs, packageVersion: "v")
    let reversed = BatchInspectionPlan.build(inputs: inputs.reversed(), packageVersion: "v")
    #expect(first == reversed)
    #expect(first.items.map(\.itemID) == ["priority", "ordinary"])
    let ordered = BatchInspectionPlan.build(inputs: inputs, packageVersion: "v",
                                            orderedItemIDs: ["ordinary", "ordinary", "missing"])
    #expect(ordered.items.map(\.itemID) == ["ordinary", "priority"])
    #expect(try JSONDecoder().decode(BatchInspectionPlan.self,
                                    from: JSONEncoder().encode(first)) == first)
}

@Test func batchResumeRetainsCaptureOnlyForExactGeometryAndEndpoints() throws {
    let original = batchInput("id", [batchPoint(0), batchPoint(500)])
    let plan = BatchInspectionPlan.build(inputs: [original], packageVersion: "v")
    var checkpoint = BatchInspectionCheckpoint(plan: plan)
    checkpoint.record(viewpoint: plan.viewpoints[0], status: .captured,
                      evidencePaths: ["capture.png"], note: "Evidence collected; awaiting review")
    checkpoint.record(viewpoint: plan.viewpoints[1], status: .failed, note: "Capture failed")
    #expect(checkpoint.status(for: plan.viewpoints[0].id) == .captured)
    #expect(checkpoint.resumed(for: plan) == checkpoint)
    let nextVersion = BatchInspectionPlan.build(inputs: [original], packageVersion: "new")
    #expect(checkpoint.resumed(for: nextVersion).status(for: plan.viewpoints[0].id) == .captured)
    for change in 0..<4 {
        var changed = original
        switch change {
        case 0: changed.source[1] = batchPoint(501)
        case 1: changed.display[1] = batchPoint(501)
        case 2: changed.fromStationID = "replacement"
        default: changed.toStationID = "replacement"
        }
        let resumed = checkpoint.resumed(for: .build(inputs: [changed], packageVersion: "v"))
        #expect(resumed.progress.allSatisfy { $0.status == .pending && $0.evidencePaths.isEmpty })
    }
    let persisted = try JSONDecoder().decode(BatchInspectionCheckpoint.self,
                                              from: JSONEncoder().encode(checkpoint))
    #expect(persisted == checkpoint)
    var restored = BatchInspectionCheckpoint(plan: plan)
    restored.record(progress: checkpoint.progress)
    #expect(restored == checkpoint)
    var changed = original
    changed.display[0] = batchPoint(1)
    let changedPlan = BatchInspectionPlan.build(inputs: [changed], packageVersion: "v")
    var staleTargets = BatchInspectionCheckpoint(plan: changedPlan)
    staleTargets.record(progress: [checkpoint.progress[0]])
    #expect(staleTargets.progress[0].status == .pending)
    checkpoint.record(viewpoint: plan.viewpoints[0], status: .pending)
    #expect(checkpoint.progress[0].evidencePaths.isEmpty)
}

@Test func batchZeroLengthAndExactSpacingDoNotDuplicateTail() {
    let exactMetresPerDegree = 6_371_008.8 * .pi / 180
    let endpoint = InspectionPoint(longitude: 700 / exactMetresPerDegree, latitude: 0)
    let inputs = [batchInput("zero", [batchPoint(0), batchPoint(0)]),
                  batchInput("exact", [batchPoint(0), endpoint])]
    let plan = BatchInspectionPlan.build(inputs: inputs, packageVersion: "v")
    #expect(plan.items.first { $0.itemID == "zero" }?.viewpoints.count == 1)
    let points = plan.items.first { $0.itemID == "exact" }?.viewpoints ?? []
    #expect(points.count == 3)
    #expect(points.last?.coordinate == endpoint)
}
