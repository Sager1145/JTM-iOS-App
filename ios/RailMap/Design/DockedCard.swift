import SwiftUI

enum DockedCardDragSpace: Hashable {
    case container
}

/// A docked menu retains its content while changing height. Duo enables a
/// header drag; other docked workspaces keep their existing stage commands.
struct DockedCard<Content: View>: View {
    let content: Content
    let width: CGFloat
    let room: CGFloat
    let metrics: BottomChromeMetrics
    let settledStage: SheetStage
    let morph: PanelMorph
    var headerDragHeight: CGFloat = 0
    /// Header origin in the fixed, bottom-aligned drag container.
    var headerDragTop: CGFloat = 0
    var onStageChange: ((SheetStage) -> Void)? = nil
    @GestureState private var dragTranslation: CGFloat = 0

    private var height: CGFloat {
        let minimum = metrics.height(of: metrics.stages.first ?? .compact)
        return min(room, max(minimum, metrics.height(of: settledStage) - dragTranslation))
    }
    private var shape: some Shape {
        RoundedRectangle(
            cornerRadius: WorkspaceMenuMetrics.cardCornerRadius, style: .continuous)
    }

    var body: some View {
        if onStageChange != nil {
            card.simultaneousGesture(headerDrag)
        } else {
            card
        }
    }

    private var card: some View {
        content
            .frame(width: width, height: height)
            .clipShape(shape)
            .railGlass(in: shape)
            .onAppear { syncMorph() }
            .onChange(of: height) { _, _ in syncMorph() }
    }

    private var headerDrag: some Gesture {
        // The card's own origin moves as it grows. Measuring there feeds
        // that movement back into translation and makes the height oscillate.
        DragGesture(minimumDistance: 10, coordinateSpace: .named(DockedCardDragSpace.container))
            .updating($dragTranslation) { value, translation, _ in
                guard beganInHeader(value) else { return }
                translation = value.translation.height
            }
            .onEnded { value in
                guard beganInHeader(value) else { return }
                let projected = metrics.height(of: settledStage) - value.predictedEndTranslation.height
                onStageChange?(metrics.stage(nearest: projected))
            }
    }

    private func beganInHeader(_ value: DragGesture.Value) -> Bool {
        (headerDragTop...headerDragTop + headerDragHeight).contains(value.startLocation.y)
    }

    private func syncMorph() {
        morph.update(
            stage: metrics.stage(nearest: height),
            expansion: metrics.headerExpansionProgress(for: height))
    }
}
