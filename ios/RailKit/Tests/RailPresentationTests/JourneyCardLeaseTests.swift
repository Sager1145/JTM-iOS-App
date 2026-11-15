import Foundation
import RailPresentation
import RailTestSupport
import Testing

@Suite("JourneyCardLease")
struct JourneyCardLeaseTests {
    @Test func switchingCardsWhileOpenKeepsTheSelection() {
        #expect(!JourneyCardLease.restoresOnDismiss(presentedDetail: "B", owner: "B", editorOpen: false))
    }

    @Test func aDetailOpenedByAnotherPathDoesNotKeepTheLease() {
        #expect(JourneyCardLease.restoresOnDismiss(presentedDetail: "X", owner: "A", editorOpen: false))
    }

    @Test func normalCloseRestoresThePreviousSelection() {
        #expect(JourneyCardLease.restoresOnDismiss(presentedDetail: nil, owner: "A", editorOpen: false))
    }

    @Test func anOpenEditorKeepsTheSelection() {
        #expect(!JourneyCardLease.restoresOnDismiss(presentedDetail: nil, owner: "A", editorOpen: true))
    }

    @Test func workspaceDismissHandlerUsesTheRule() throws {
        let source = try SourceFiles.text("RailMap/Workspace/RailWorkspaceView.swift")
        let from = try #require(source.range(of: "private func sheetDidDismiss() {"))
        let to = try #require(source.range(of: "private func withPresentations", range: from.upperBound..<source.endIndex))
        let body = source[from.lowerBound..<to.lowerBound]
        #expect(body.contains("JourneyCardLease.restoresOnDismiss("))
        #expect(source.contains("onSheetDismiss: sheetDidDismiss"))
        #expect(source.contains("current == nil, sheet == nil { sheetDidDismiss() }"))
        #expect(source.contains("owner: train.id, previous: previous"))
    }
}
