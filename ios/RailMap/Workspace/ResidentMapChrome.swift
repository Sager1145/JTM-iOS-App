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

    var body: some View {
        // This body must not read `measurements.height`. It hosts the sheet
        // presentation, and a body that re-ran on every drag frame rebuilt the
        // sheet's root, re-sent its detents and configuration to UIKit and
        // re-created its environment values each frame. Only
        // `ResidentOverlayLayout` follows the live edge.
        ResidentOverlayLayout(
            metrics: metrics,
            viewportHeight: viewportHeight,
            bottomInset: bottomInset,
            selectedStage: selectedStage,
            hidesMenu: hidesMenu,
            showsPlaybackBar: showsPlaybackBar,
            measurements: measurements,
            mapContent: mapContent,
            playbackContent: playbackContent,
            controls: controls)
        .ignoresSafeArea()
        .onAppear {
            controller.leadingObstruction = 0
            controller.dockedMenuEdge = nil
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
        // Before the first measurement, the requested stop stands in for the
        // sheet: the panel's contents are enabled only off the compact stop.
        let shown = height > 0 ? height : metrics.height(of: metrics.available(selectedStage))
        morph.update(
            stage: height > 0 ? metrics.stage(nearest: height) : selectedStage,
            expansion: metrics.headerExpansionProgress(for: shown))
    }
}

/// The map, playback bar and control rail, positioned against the sheet's
/// live edge. The one view that observes the live height while dragging.
private struct ResidentOverlayLayout<MapContent: View, PlaybackContent: View, Controls: View>: View {
    let metrics: BottomChromeMetrics
    let viewportHeight: CGFloat
    let bottomInset: CGFloat
    let selectedStage: SheetStage
    let hidesMenu: Bool
    let showsPlaybackBar: Bool
    let measurements: ResidentSheetMeasurements
    let mapContent: MapContent
    let playbackContent: PlaybackContent
    let controls: Controls

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
        // The room left above the rail's top edge, now and at the half stop.
        // The rail is fully drawn up to the half stop and fades out over the
        // last stretch before its top reaches the window's top, as ONE
        // continuous function of the sheet height. The earlier form removed
        // the rail 12 pt before its fade could begin, and again at the
        // half/full midpoint, so it vanished and reappeared at full opacity —
        // which read as the buttons jumping.
        let roomAbove = railCeiling - (railLift + railHeight + 12)
        let roomAtMedium = railCeiling - (mediumFrame + 12 + transportLift + railHeight + 12)
        let fadeSpan = min(60, max(1, roomAtMedium))
        // One point of slack: a resting half stop arrives rounded, and on a
        // short screen a fraction of a point must not leave the rail dimmed.
        let railFade = Double(min(max((roomAbove + 1) / fadeSpan, 0), 1))
        let railPresent = railFade > 0.01

        WorkspaceMapChrome(
            placement: .compactOverlay(
                transportRoom: transportRoom,
                stageExpanded: stage == .expanded,
                showsPlaybackBar: showsPlaybackBar,
                lift: lift,
                railPresent: railPresent,
                railFade: railFade,
                railLift: railLift),
            map: mapContent,
            playback: playbackContent,
            controls: controls)
        .onPreferenceChange(RailControlHeightKey.self) { height in
            if abs(height - railHeight) > 0.5 { railHeight = height }
        }
        .onPreferenceChange(PlaybackBarHeightKey.self) { height in
            if abs(height - playbackBarHeight) > 0.5 { playbackBarHeight = height }
        }
    }
}
