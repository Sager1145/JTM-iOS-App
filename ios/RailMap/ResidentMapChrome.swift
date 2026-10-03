import SwiftUI

/// Owned by the workspace so rotating into a docked layout retains the last
/// sheet measurement. Only the resident chrome observes its live value.
@MainActor @Observable
final class ResidentSheetMeasurements {
    var height: CGFloat = 0
}

/// The small layout boundary that follows the system sheet's live edge.
/// Map and menu inputs are built by the workspace, outside this height reader,
/// so dragging does not recompute their data or presentation bindings.
struct ResidentMapChrome<MapContent: View, PlaybackContent: View, Controls: View, Menu: View>: View {
    let metrics: BottomChromeMetrics
    let viewportHeight: CGFloat
    let bottomInset: CGFloat
    let selectedStage: SheetStage
    let hidesMenu: Bool
    let showsPlaybackBar: Bool
    let measurements: ResidentSheetMeasurements
    let morph: PanelMorph
    let controller: RailMapController
    @Binding var detent: PresentationDetent
    let mapContent: MapContent
    let playbackContent: PlaybackContent
    let controls: Controls
    let menu: Menu

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var railHeight: CGFloat = 0
    @State private var playbackBarHeight: CGFloat = 0

    var body: some View {
        // Detent heights exclude the home indicator; window obstructions and
        // control offsets include it. Preserve that distinction during a drag.
        let height = measurements.height
        // Before the first measurement, clear the requested detent and its
        // home-indicator band just as we do for the measured sheet.
        let panelHeight = height > 0 ? height : metrics.height(of: metrics.available(selectedStage))
        let sheetFrame = hidesMenu ? 0 : panelHeight + bottomInset
        let stage = hidesMenu ? .compact : metrics.stage(nearest: panelHeight)
        let lift = sheetFrame + 12
        let transportLift = showsPlaybackBar ? playbackBarHeight + 12 : 0
        let railLift = lift + transportLift
        let transportRoom = max(0, viewportHeight + bottomInset - lift - 12)
        let railCeiling = viewportHeight + bottomInset
        let mediumFrame = metrics.medium + bottomInset
        let above = max(0, sheetFrame - mediumFrame)
        let headroom = max(0, railCeiling - (mediumFrame + 12 + railHeight + transportLift))
        let railFade: Double = above <= headroom
            ? 1 : Double(1 - min((above - headroom) / 60, 1))
        let railPresent = stage != .expanded && railFade > 0
            && railCeiling >= railLift + railHeight + 12

        ZStack(alignment: .bottomTrailing) {
            mapContent
            playbackContent
                .frame(maxHeight: transportRoom, alignment: .bottom)
                .opacity(stage == .expanded ? 0 : 1)
                .allowsHitTesting(stage != .expanded)
                .accessibilityHidden(stage == .expanded)
                .padding(.horizontal, 12)
                .offset(y: -lift)
                .railAnimation(
                    RailMotion.spring, value: showsPlaybackBar,
                    reduceMotion: reduceMotion)
            Group {
                if railPresent { controls }
                else { controls.hidden() }
            }
                .padding(.trailing, 12)
                .background {
                    GeometryReader { rail in
                        Color.clear.preference(
                            key: RailControlHeightKey.self, value: rail.size.height)
                    }
                }
                .offset(y: -railLift)
                .opacity(railPresent ? railFade : 0)
                .allowsHitTesting(railPresent)
                .accessibilityHidden(!railPresent)
        }
        .ignoresSafeArea()
        .onPreferenceChange(RailControlHeightKey.self) { height in
            if abs(height - railHeight) > 0.5 { railHeight = height }
        }
        .onPreferenceChange(PlaybackBarHeightKey.self) { height in
            if abs(height - playbackBarHeight) > 0.5 { playbackBarHeight = height }
        }
        .onAppear {
            controller.leadingObstruction = 0
            syncMeasurements()
        }
        .onChange(of: selectedStage) { _, _ in syncMeasurements() }
        .onChange(of: hidesMenu) { _, _ in syncMeasurements() }
        .onChange(of: metrics) { _, _ in syncMeasurements() }
        .onChange(of: bottomInset) { _, _ in syncMeasurements() }
        .residentBottomSheet(
            metrics: metrics,
            isSuspended: hidesMenu,
            detent: $detent,
            liveHeight: Binding(
                get: { measurements.height },
                set: { height in
                    measurements.height = height
                    syncMeasurements()
                })
        ) {
            menu.environment(morph)
        }
    }

    private func syncMeasurements() {
        let height = measurements.height
        controller.bottomObstruction = !hidesMenu && height > 0 ? height + bottomInset : 0
        morph.update(
            stage: height > 0 ? metrics.stage(nearest: height) : selectedStage,
            expansion: metrics.headerExpansionProgress(
                for: height > 0 ? height : metrics.compact))
    }
}
