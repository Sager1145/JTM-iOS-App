import Foundation
import RailPresentation
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
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RailMap/Workspace/RailWorkspaceView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let from = try #require(source.range(of: "onSheetDismiss: {"))
        let to = try #require(source.range(of: "sheetContent: presentedSheet", range: from.upperBound..<source.endIndex))
        let body = source[from.lowerBound..<to.lowerBound]
        #expect(body.contains("JourneyCardLease.restoresOnDismiss("))
        #expect(source.contains("owner: train.id, previous: previous"))
    }
}
