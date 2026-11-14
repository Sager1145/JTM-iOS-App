import Foundation
import Testing

/// Source-structure guards for panel-hosted popups. The host decision is tested
/// in RailPresentation (`WorkspaceSurfacePolicyTests`); these pin that the app
/// asks the policy, never the platform, and that the panel path stays whole.
@Suite("RegressionGuardPanelHostedPopups")
struct RegressionGuardPanelHostedPopups {
    private static let ios: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RegressionGuards
            .deletingLastPathComponent() // RailCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // RailKit
            .deletingLastPathComponent() // ios
    }()

    private static func read(_ path: String) -> String {
        (try? String(contentsOf: ios.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    private static let menu = read("RailMap/Journeys/JourneyMenuView.swift")
    private static let workspace = read("RailMap/Workspace/RailWorkspaceView.swift")
    private static let presentations = read("RailMap/Workspace/WorkspacePresentations.swift")
    private static let sheetContent = read("RailMap/Workspace/WorkspaceSheetContent.swift")
    private static let notes = read("RailMap/Journeys/TripNotesCard.swift")
    private static let row = read("RailMap/Journeys/JourneyListRow.swift")
    private static let host = read("RailMap/Diagnostics/AppControl/AppControlHost.swift")

    /// `dismiss` from a view that is not in a presentation can close a Catalyst
    /// window, and the platform test is the policy's job.
    @Test func journeyMenuHasNoPlatformBranchAndNoDismiss() {
        #expect(!Self.menu.isEmpty)
        #expect(!Self.menu.contains("targetEnvironment(macCatalyst)"))
        #expect(!Self.menu.contains("\\.dismiss"))
        #expect(!Self.menu.contains("dismiss()"))
        #expect(Self.menu.contains("let host: WorkspaceSurfaceHost"))
        #expect(Self.menu.contains("let onClose: () -> Void"))
    }

    @Test func governedPresentationFilesAskThePolicy() {
        #expect(Self.sheetContent.contains("WorkspaceSurfacePolicy.host("))
        #expect(Self.workspace.contains("WorkspaceSurfacePolicy.host("))
        #expect(Self.workspace.contains("isHinged: hasHingedDisplay"))
        #expect(Self.presentations.contains("isHinged: isHinged"))
        // Every host decision in the workspace is passed the hinge state.
        let calls = Self.workspace.components(separatedBy: "WorkspaceSurfacePolicy.host(").dropFirst()
        for call in calls {
            #expect(call.prefix(200).contains("isHinged: hasHingedDisplay"))
        }
    }

    /// Panel-hosted sheets never reach the system sheet; the panel presents
    /// them over the tabs, which stay mounted (so the list keeps its scroll).
    @Test func panelSheetsBypassTheSystemSheetAndKeepTheTabsMounted() {
        #expect(Self.presentations.contains(".sheet(item: systemSheet,"))
        #expect(!Self.presentations.contains(".sheet(item: $sheet"))
        #expect(Self.workspace.contains("func workspaceTabs(panelSheet: WorkspaceSheet?"))
        #expect(Self.workspace.contains(".allowsHitTesting(panelSheet == nil)"))
        #expect(Self.workspace.contains(".id(panelSheet.id)"))
        #expect(Self.workspace.contains(".keyboardShortcut(.cancelAction)"))
    }

    /// One cleanup for both hosts, run on every path that clears the sheet.
    @Test func sheetCleanupRunsForBothHosts() {
        #expect(Self.workspace.contains("private func sheetDidDismiss()"))
        #expect(Self.workspace.contains("onSheetDismiss: sheetDidDismiss"))
        #expect(Self.workspace.contains("if previous != nil, current == nil { sheetDidDismiss() }"))
    }

    /// In the docked layout the map's obstruction does not follow the card:
    /// no dock offset or zero branch keyed on the menu hiding.
    @Test func dockedLayoutKeepsTheMapObstructionConstant() {
        let start = Self.workspace.range(of: "private func sideBySideLayout(")
        let end = Self.workspace.range(of: "private func dockedMenuContent(")
        #expect(start != nil && end != nil)
        guard let start, let end, start.lowerBound < end.lowerBound else { return }
        let docked = String(Self.workspace[start.lowerBound..<end.lowerBound])
        #expect(!docked.contains("hidesWorkspaceMenu"))
        let obstruction = Self.workspace.range(of: "private func applyDockObstruction(")
        #expect(obstruction != nil)
        if let obstruction {
            let body = String(Self.workspace[obstruction.lowerBound...].prefix(400))
            #expect(!body.contains("hidesWorkspaceMenu"))
        }
    }

    /// Only the shapes that are not popups stay full-window covers.
    @Test func fullScreenCoversAreAllowlisted() throws {
        let allowed: Set<String> = [
            "Workspace/RailWorkspaceView.swift", "Journeys/RideCard.swift",
            "JourneyEditor/TicketScanView.swift",
        ]
        let root = Self.ios.appendingPathComponent("RailMap")
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
        for file in files where !allowed.contains(file) {
            let text = (try? String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)) ?? ""
            #expect(!text.contains(".fullScreenCover("), "\(file) presents a full-screen cover")
        }
    }

    @Test func tripNotesAndGroupPickerAreGatedByHost() {
        #expect(!Self.notes.contains("content.sheet(item: $flow.screen)"))
        #expect(Self.notes.contains(".sheet(item: systemScreen)"))
        #expect(Self.notes.contains("host == .panel"))
        #expect(!Self.row.contains(".sheet(isPresented: $showsGroupAssignment)"))
        #expect(Self.row.contains(".sheet(isPresented: systemGroupAssignment)"))
    }

    @Test func harnessStateReportsHostAndPresentation() {
        #expect(Self.host.contains("\"sheetHost\""))
        #expect(Self.host.contains("\"presented\""))
        #expect(Self.host.contains("presentedViewController"))
    }
}
