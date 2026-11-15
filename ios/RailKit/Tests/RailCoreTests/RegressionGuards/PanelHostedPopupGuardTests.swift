import Foundation
import RailTestSupport
import Testing

/// Source-structure guards for panel-hosted popups. The host decision is tested
/// in RailPresentation (`WorkspaceSurfacePolicyTests`); these pin that the app
/// asks the policy, never the platform, and that the panel path stays whole.
@Suite("RegressionGuardPanelHostedPopups")
struct RegressionGuardPanelHostedPopups {
    private static let menu = SourceFiles.textRecording("RailMap/Journeys/JourneyMenuView.swift")
    private static let workspace = SourceFiles.textRecording("RailMap/Workspace/RailWorkspaceView.swift")
    private static let presentations = SourceFiles.textRecording("RailMap/Workspace/WorkspacePresentations.swift")
    private static let sheetContent = SourceFiles.textRecording("RailMap/Workspace/WorkspaceSheetContent.swift")
    private static let notes = SourceFiles.textRecording("RailMap/Journeys/TripNotesCard.swift")
    private static let row = SourceFiles.textRecording("RailMap/Journeys/JourneyListRow.swift")
    private static let host = SourceFiles.textRecording("RailMap/Diagnostics/AppControl/AppControlHost.swift")

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
        #expect(Self.workspace.contains("if previous != nil, current == nil, sheet == nil { sheetDidDismiss() }"))
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
        let root = SourceFiles.ios.appendingPathComponent("RailMap")
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

    private static let station = SourceFiles.textRecording("RailMap/Map/StationCardView.swift")
    private static let lineCard = SourceFiles.textRecording("RailMap/Map/RailwayLineCardView.swift")
    private static let lineSheet = SourceFiles.textRecording("RailMap/Map/NetworkLineSheetView.swift")
    private static let picker = SourceFiles.textRecording("RailMap/Journeys/JourneyGroupPicker.swift")
    private static let hosting = SourceFiles.textRecording("RailMap/Workspace/WorkspacePopupHosting.swift")

    /// A popup root's close goes through `closePanelSurface` when there is one.
    @Test func popupRootsNeverDismissWithoutCheckingThePanel() {
        #expect(Self.lineCard.contains("onClose: (() -> Void)?"))
        #expect(Self.lineCard.contains("if let onClose { onClose() } else { dismiss() }"))
        #expect(Self.lineSheet.contains("onClose: { if let closePanelSurface { closePanelSurface() } else { dismiss() } })"))
        for (name, source) in [
            ("StationCardView", Self.station), ("RideChooserView", SourceFiles.textRecording("RailMap/Journeys/RideChooserView.swift")),
            ("JourneyGroupPicker", Self.picker), ("NetworkLineSheetView", Self.lineSheet),
        ] {
            for line in source.split(separator: "\n") where line.contains("dismiss()") {
                #expect(line.contains("closePanelSurface") || line.contains("// ui-token-ok"),
                        "\(name): \(line)")
            }
        }
    }

    /// Locate runs in the panel: no detent change, no wait for a compact height.
    @Test func locateDoesNotWaitForADetentInThePanel() {
        #expect(Self.lineSheet.contains("guard popupHost == .panel || dynamicTypeSize.isAccessibilitySize"))
        #expect(Self.station.contains("guard popupHost == .panel || dynamicTypeSize.isAccessibilitySize"))
        #expect(Self.lineSheet.contains("if popupHost != .panel {"))
        #expect(Self.station.contains("if popupHost != .panel {"))
    }

    /// Esc stands down over a nested surface, and a popup closes only itself.
    @Test func escapeAndCloseAreScopedToTheirPopup() {
        let w = Self.workspace
        #expect(Self.hosting.contains("struct PanelNestedSurfaceKey: PreferenceKey"))
        #expect(w.contains(".onPreferenceChange(PanelNestedSurfaceKey.self)"))
        #expect(w.contains(".disabled(panelNestedSurface)"))
        #expect(Self.menu.contains(".panelNestedSurface("))
        #expect(Self.picker.contains(".panelNestedSurface(saving)"))
        #expect(w.contains("if self.sheet?.id == presented.id { self.sheet = nil }"))
    }

    /// Hidden tabs take no keys: no search focus, no Space, no ⌘F.
    @Test func hiddenTabsTakeNoKeyboardInput() {
        let w = Self.workspace
        #expect(w.contains("searchFocused = false\n                    if stageSelection == .compact"))
        #expect(w.contains("guard !self.presentedEditorOwnsShortcuts, self.panelSheet == nil else { return }"))
        #expect(w.contains(".keyboardShortcut(.space, modifiers: [])\n        .disabled(panelSheet != nil)"))
    }

    /// The journey editor replaces a panel popup; the dock stays open for a card.
    @Test func editorReplacesPopupAndDockStaysOpen() {
        let w = Self.workspace
        #expect(w.contains("if panelSheet != nil { sheet = nil }"))
        #expect(w.contains("panelSheet != nil && requested == .compact ? .medium : requested"))
        #expect(w.contains("stageBeforePopup"))
    }

    /// The environment carries Equatable wrappers, never bare closures.
    @Test func environmentActionsAreEquatableWrappers() {
        #expect(Self.hosting.contains("@Entry var closePanelSurface: PanelCloseAction?"))
        #expect(Self.hosting.contains("@Entry var presentGroupPicker: PanelGroupPickerAction?"))
    }

    /// `presented` looks at every window, not only the key one.
    @Test func presentedLooksAtEveryWindow() {
        #expect(Self.host.contains("windows.contains { $0.rootViewController?.presentedViewController != nil }"))
        #expect(!Self.host.contains("windows.first(where: \\.isKeyWindow)?.rootViewController"))
    }
}
