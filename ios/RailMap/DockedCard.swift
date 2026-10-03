import SwiftUI

/// The wide-window menu uses ordinary state-driven resizing. Its header has
/// no custom gesture; the adjacent panel toggle changes the settled stop.
struct DockedCard<Content: View>: View {
    let content: Content
    let width: CGFloat
    let room: CGFloat
    let metrics: BottomChromeMetrics
    let settledStage: SheetStage
    let morph: PanelMorph

    private var height: CGFloat { min(metrics.height(of: settledStage), room) }
    private var shape: some Shape {
        RoundedRectangle(
            cornerRadius: WorkspaceMenuMetrics.cardCornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .frame(width: width, height: height)
            .clipShape(shape)
            .railGlass(in: shape)
            .onAppear { syncMorph() }
            .onChange(of: height) { _, _ in syncMorph() }
    }

    private func syncMorph() {
        morph.update(
            stage: metrics.stage(nearest: height),
            expansion: metrics.headerExpansionProgress(for: height))
    }
}
