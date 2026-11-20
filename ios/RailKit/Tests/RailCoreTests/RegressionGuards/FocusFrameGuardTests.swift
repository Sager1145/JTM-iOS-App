import Foundation
import RailTestSupport
import Testing

/// Source-structure guards for the focus fit's free area. The rule is tested
/// in RailPresentation (`RegressionGuardFocusFramePolicy`); these pin that
/// every fit takes its insets and its MapKit padding from that rule, and that
/// the frames feeding it are stored without moving the camera.
@Suite("RegressionGuardFocusFrameWiring")
struct RegressionGuardFocusFrameWiring {
    private static var controller: String { SourceFiles.textRecording("RailMap/Map/RailMapController.swift") }
    private static var focusFrame: String { SourceFiles.textRecording("RailMap/Map/RailMapController+FocusFrame.swift") }
    private static var coordinator: String { SourceFiles.textRecording("RailMap/Map/RailMapCoordinator.swift") }
    private static var playback: String { SourceFiles.textRecording("RailMap/Map/MapPlaybackLayer.swift") }
    private static var workspace: String { SourceFiles.textRecording("RailMap/Workspace/RailWorkspaceView.swift") }
    private static var phoneChrome: String { SourceFiles.textRecording("RailMap/Workspace/ResidentMapChrome.swift") }
    private static var host: String { SourceFiles.textRecording("RailMap/Diagnostics/AppControl/AppControlHost.swift") }

    /// Code lines only: a comment may talk about `edgePadding:` freely.
    private static func codeLines(_ source: String) -> [String] {
        source.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }
    }

    /// Every padded MapKit call on the main map hands over `fitPadding`.
    /// View insets passed as padding count the docked menu twice, which drew
    /// a focused trip under the control buttons.
    @Test func everyPaddedMapCallUsesTheFitPadding() {
        for (name, source) in [
            ("controller", Self.controller), ("coordinator", Self.coordinator), ("playback", Self.playback),
        ] {
            #expect(!source.isEmpty, "\(name) source not found")
            for line in Self.codeLines(source) where line.contains("edgePadding:") {
                #expect(line.contains("edgePadding: fitPadding")
                    || line.contains("edgePadding: controller?.fitPadding(for:"),
                    "\(name): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        // The coordinator and the workspace frame nothing themselves: every
        // camera move that frames a subject goes through the controller.
        for call in ["setVisibleMapRect(", "mapRectThatFits(", "setRegion("] {
            #expect(!Self.codeLines(Self.coordinator).contains { $0.contains(call) }, "coordinator: \(call)")
            #expect(!Self.codeLines(Self.workspace).contains { $0.contains(call) }, "workspace: \(call)")
        }
        // The controller's fits are all still there to be checked.
        #expect(Self.codeLines(Self.controller).filter { $0.contains("edgePadding: fitPadding") }.count >= 5)
    }

    /// One definition of the fit's insets, and it asks the policy.
    @Test func framingInsetsComeFromThePolicy() {
        #expect(!Self.focusFrame.isEmpty)
        #expect(Self.focusFrame.contains("var framingInsets: UIEdgeInsets {"))
        #expect(Self.focusFrame.contains("focusFramePolicy.insets"))
        #expect(Self.focusFrame.contains("FocusFramePolicy("))
        #expect(Self.focusFrame.contains("policy.mapPadding(fittingArea:"))
        #expect(!Self.controller.contains("var framingInsets"))
        #expect(Self.controller.contains("var baseFramingInsets: UIEdgeInsets {"))
        #expect(Self.controller.contains("var playbackFramingInsets: UIEdgeInsets { framingInsets }"))
        // The "already visible" test and the fit agree about the free area.
        #expect(Self.controller.contains("mapView.bounds.inset(by: framingInsets)"))
    }

    /// The two frames come from the laid-out views and are only stored: no
    /// observer, so a resize or the card breathing never refits the map.
    @Test func framesAreMeasuredAndOnlyStored() {
        #expect(Self.controller.contains("@ObservationIgnored var dockedMenuEdge: CGFloat?\n"))
        #expect(Self.controller.contains("@ObservationIgnored var controlColumnFrame: CGRect?\n"))
        #expect(Self.workspace.contains(
            "controller.dockedMenuEdge = panelWidth + Self.dockInset + safeAreaLeading"))
        #expect(Self.workspace.contains("controller.controlColumnFrame = frame"))
        #expect(Self.workspace.contains("proxy.frame(in: .global)"))
        // Layouts with no docked menu say so.
        #expect(Self.workspace.contains("controller.dockedMenuEdge = nil"))
        #expect(Self.phoneChrome.contains("controller.dockedMenuEdge = nil"))
    }

    /// The test-only channel reports the free area and the last fit.
    @Test func stateReportsTheFocusFrame() {
        #expect(Self.host.contains("\"focusFrame\": Self.focusFrame(stores.controller)"))
        #expect(Self.host.contains("controller.lastFitSubjectViewRect"))
    }
}
