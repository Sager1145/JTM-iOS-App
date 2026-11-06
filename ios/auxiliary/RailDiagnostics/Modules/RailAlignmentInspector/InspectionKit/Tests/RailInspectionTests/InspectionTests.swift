import Foundation
import Testing
@testable import RailInspection

private func point(_ east: Double, _ north: Double = 0) -> InspectionPoint {
    .init(longitude: east / 111_195, latitude: north / 111_195)
}

private func input(_ id: String, _ points: [InspectionPoint], display: [InspectionPoint]? = nil,
                   override: Bool = false) -> InspectionInput {
    .init(id: id, lineID: id == "other" ? "line2" : "line1", lineName: "线路",
          operatorName: "运营方", intervalIndex: 0, fromStationID: "a", toStationID: "b",
          fromName: "甲", toName: "乙", source: points, display: display ?? points,
          hasDisplayOverride: override)
}

@Test func everyIntervalIncludedAndOrderingStable() throws {
    let inputs = [input("z", [point(0), point(10), point(20)]), input("missing", []),
                  input("a", [point(0), point(10), point(20)]), input("other", [point(0)])]
    let plan = InspectionPlan.build(inputs: inputs, packageVersion: "v1")
    #expect(plan.items.count == inputs.count)
    #expect(Set(plan.items.map(\.id)) == Set(inputs.map(\.id)))
    #expect(plan.lineCount == 2)
    #expect(plan.packageVersion == "v1")
    #expect(plan.format == "jtm-japan-inspection-plan-v1")
    #expect(plan.items.map(\.id) == InspectionPlan.build(inputs: inputs.reversed(), packageVersion: "v1").items.map(\.id))
    let missing = try #require(plan.items.first { $0.id == "missing" })
    let ordinary = try #require(plan.items.first { $0.id == "a" })
    #expect(missing.priority > ordinary.priority)
    #expect(plan.items.filter { $0.priority == ordinary.priority }.map(\.id) == ["a", "z"])
}

@Test func straightLongSpanIsOnlyAReviewCandidate() throws {
    let item = try #require(InspectionPlan.build(inputs: [input("long", [point(0), point(300)])], packageVersion: "v").items.first)
    #expect(item.maxChordMetres > 299)
    #expect(item.signals.contains { $0.contains("直线") && $0.contains("候选") })
    #expect(!item.signals.contains { $0.contains("通过") || $0.contains("PASS") || $0.contains("偏离底图") })
    #expect(item.maxTurnDegrees == 0)
}

@Test func microscopicKinksDoNotRaiseTurnSignals() throws {
    let item = try #require(InspectionPlan.build(inputs: [input("tiny", [point(0), point(1), point(0, 1), point(1, 1)])], packageVersion: "v").items.first)
    #expect(!item.signals.contains { $0.contains("转角") || $0.contains("折返") })
    #expect(item.maxTurnDegrees == 0)
}

@Test func invalidCoordinatesKeepStatisticsJSONSafe() throws {
    let itemInput = input("bad", [point(0), .init(longitude: .nan, latitude: 0), point(300),
                                 .init(longitude: 190, latitude: 100), .init(longitude: .infinity, latitude: 0)])
    let plan = InspectionPlan.build(inputs: [itemInput], packageVersion: "v")
    let item = try #require(plan.items.first)
    #expect(item.signals.contains { $0.contains("无效坐标") })
    #expect(item.maxChordMetres.isFinite && item.maxTurnDegrees.isFinite)
    #expect(item.maxChordMetres == 0) // Never invent a segment across an invalid vertex.
    let data = try JSONEncoder().encode(plan)
    #expect(try JSONDecoder().decode(InspectionPlan.self, from: data).items.count == 1)
}

@Test func reviewFreshnessTracksExactSourceAndDisplay() {
    let original = input("id", [point(0), point(10), point(20)])
    let review = InspectionReview(itemID: original.id, verdict: .aligned, note: "已对照",
                                  reviewedAt: Date(), source: original.source,
                                  display: original.display, evidencePaths: ["capture.png"],
                                  fromStationID: original.fromStationID, toStationID: original.toStationID)
    #expect(review.isCurrent(for: original))
    #expect(!review.isCurrent(for: input("id", [point(0), point(11), point(20)])))
    #expect(!review.isCurrent(for: input("id", original.source, display: [point(0), point(12), point(20)])))
    #expect(!review.isCurrent(for: input("another", original.source)))
}

@Test func reviewFreshnessTracksBothEndpointIdentities() {
    let original = input("id", [point(0), point(10), point(20)])
    let review = InspectionReview(itemID: original.id, verdict: .aligned, note: "",
                                  reviewedAt: Date(), source: original.source, display: original.display,
                                  evidencePaths: [], fromStationID: original.fromStationID,
                                  toStationID: original.toStationID)
    var changedStart = original
    changedStart.fromStationID = "replacement-start"
    var changedEnd = original
    changedEnd.toStationID = "replacement-end"
    #expect(review.isCurrent(for: original))
    #expect(!review.isCurrent(for: changedStart))
    #expect(!review.isCurrent(for: changedEnd))
}

@Test func legacyReviewsWithoutEndpointIdentityRemainReadableButStale() throws {
    let original = input("id", [point(0), point(10), point(20)])
    let legacy = InspectionReview(itemID: original.id, verdict: .aligned, note: "旧记录",
                                  reviewedAt: Date(), source: original.source,
                                  display: original.display, evidencePaths: [])
    let data = try JSONEncoder().encode(legacy)
    let decoded = try JSONDecoder().decode(InspectionReview.self, from: data)
    #expect(decoded.fromStationID == nil && decoded.toStationID == nil)
    #expect(decoded.renderedDisplay == nil && decoded.renderContract == nil && decoded.camera == nil)
    #expect(!decoded.isCurrent(for: original))
}

@Test func renderedReviewContextSurvivesPersistence() throws {
    let original = input("id", [point(0), point(10), point(20)])
    let rendered = [[point(0), point(5, 1), point(20)]]
    let camera = ["zoom": 17.0, "longitude": 139.75, "latitude": 35.74]
    let review = InspectionReview(itemID: original.id, verdict: .aligned, note: "",
                                  reviewedAt: Date(), source: original.source, display: original.display,
                                  evidencePaths: [], fromStationID: original.fromStationID,
                                  toStationID: original.toStationID, renderedDisplay: rendered,
                                  renderContract: "isolated-displayparts-v1", camera: camera)
    let decoded = try JSONDecoder().decode(InspectionReview.self, from: JSONEncoder().encode(review))
    #expect(decoded.renderedDisplay == rendered)
    #expect(decoded.renderContract == "isolated-displayparts-v1")
    #expect(decoded.camera == camera)
    #expect(decoded.isCurrent(for: original))
}

@Test func loopsAndOverridesRemainPendingCandidates() throws {
    let item = try #require(InspectionPlan.build(inputs: [input("loop", [point(0), point(100), point(0)], override: true)], packageVersion: "v").items.first)
    #expect(item.maxTurnDegrees > 150)
    #expect(item.signals.contains { $0.contains("折返") && $0.contains("候选") })
    #expect(item.signals.contains { $0.contains("接缝") })
    #expect(!item.signals.contains { $0.contains("通过") || $0.contains("PASS") })
    #expect(ReviewVerdict.pending.title == "待复核")
}

@Test func displayGeometryAlsoContributesSignals() throws {
    let item = try #require(InspectionPlan.build(inputs: [input("display", [point(0), point(10), point(20)], display: [point(0), point(200), point(0)])], packageVersion: "v").items.first)
    #expect(item.maxChordMetres > 199)
    #expect(item.maxTurnDegrees > 150)
    #expect(item.sourceVertexCount == 3 && item.displayVertexCount == 3)
}
