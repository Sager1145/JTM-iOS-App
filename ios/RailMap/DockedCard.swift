import SwiftUI
import os

/// The docked card's shell: its width, its live height, its surface, its
/// shadow, and the header drag that changes the height. The menu inside is a
/// STORED view built once by the workspace, so a drag frame re-evaluates this
/// view and the header — not the tab controller, not the lists.
struct DockedCard<Content: View>: View {
    let content: Content
    let width: CGFloat
    /// Vertical room the card may occupy (window height minus the dock insets).
    let room: CGFloat
    let metrics: BottomChromeMetrics
    /// The stop the card is settled at, already passed through `metrics.available(_:)`.
    let settledStage: SheetStage
    let morph: PanelMorph
    let reduceMotion: Bool
    /// The release lands on a stop: the workspace records it and animates `settledStage`.
    let onSettle: @MainActor (SheetStage) -> Void

    /// An instance constant, not a static one: Swift does not allow static
    /// stored properties on a generic type.
    private let cornerRadius: CGFloat = 24

    @State private var dragOffset: CGFloat = 0
    @State private var signpost: OSSignpostIntervalState?
    /// Built once, on appear, so the environment value — and with it the
    /// hosted pages' environment — does not change on every frame.
    @State private var headerDrag: RailPanelHeaderDrag?
    /// What the once-built closures read on each frame; refreshed from the
    /// stored properties every time this body runs. A class, not observed.
    @State private var inputs = Inputs()

    /// Only ever touched on the main actor — refreshed from `body` on every
    /// run and read back from the closures `makeHeaderDrag()` builds once —
    /// so `@unchecked` stands in for a `Sendable` conformance the compiler
    /// cannot derive for a mutable class on its own.
    @MainActor final class Inputs: @unchecked Sendable {
        var metrics = BottomChromeMetrics(screenHeight: 0, compactRow: 0, isAccessibilitySize: false)
        var settled: CGFloat = 0
        var room: CGFloat = 0
        var onSettle: @MainActor (SheetStage) -> Void = { _ in }
        /// Read live, like the rest: the closures are built once, and the
        /// reader can switch Reduce Motion on while the card is up.
        var reduceMotion = false
    }

    var body: some View {
        inputs.metrics = metrics
        inputs.settled = metrics.height(of: settledStage)
        inputs.room = room
        inputs.onSettle = onSettle
        inputs.reduceMotion = reduceMotion
        let live = Self.liveHeight(offset: dragOffset, inputs: inputs)
        return content
            .environment(\.railPanelHeaderDrag, headerDrag)
            .frame(width: width, height: live)
            // Liquid Glass, as Apple Maps' own floating panel: the system
            // surface through `railGlass`, which also owns the Reduce
            // Transparency and Increase Contrast fallbacks. Glass casts its
            // own shadow, so there is no separate shadow shape behind it.
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .railGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                if headerDrag == nil { headerDrag = makeHeaderDrag() }
                syncMorph(to: live)
            }
            .onChange(of: metrics.height(of: settledStage)) { _, _ in
                // No animation: the caller (`RailWorkspaceView.settleDock`)
                // already animates `settledStage` with the app's own spring.
                dragOffset = 0
                syncMorph(to: Self.liveHeight(offset: 0, inputs: inputs))
            }
            .onChange(of: room) { _, _ in
                dragOffset = 0
                syncMorph(to: Self.liveHeight(offset: 0, inputs: inputs))
            }
            // A width-only resize used to clear the offset too.
            .onChange(of: width) { _, _ in
                dragOffset = 0
                syncMorph(to: Self.liveHeight(offset: 0, inputs: inputs))
            }
            .onDisappear { dragOffset = 0 }
    }

    /// Identical to the old `live` in `RailWorkspaceView.sideBySideLayout`.
    private static func liveHeight(offset: CGFloat, inputs: Inputs) -> CGFloat {
        min(max(inputs.settled - offset, inputs.metrics.compact), inputs.room)
    }

    private func syncMorph(to height: CGFloat) {
        morph.update(
            stage: inputs.metrics.stage(nearest: height),
            expansion: inputs.metrics.headerExpansionProgress(for: height))
    }

    /// The header drag itself. `changed` writes the live offset with no
    /// animation, so the card follows the finger; `ended` projects the
    /// RELEASE velocity (`predictedEnd`, not the translation at the moment
    /// the finger lifted) onto the same stops and settles there with the
    /// app's spring — the same shape of settle §9.5.5 gives the phone sheet,
    /// driven by a gesture instead of a system detent.
    ///
    /// Captures `inputs`, `morph`, `reduceMotion` and the `$dragOffset` /
    /// `$signpost` bindings — not `self` — so the closures stay valid across
    /// every later `body` run instead of pinning the frame this was built on.
    private func makeHeaderDrag() -> RailPanelHeaderDrag {
        let inputs = inputs
        let morph = morph
        let offset = $dragOffset
        let signpostState = $signpost
        return RailPanelHeaderDrag(
            changed: { translation in
                // Opened on the drag's first frame only. Checked against the
                // offset as well as the state, because with no tool recording
                // `beginAnimation` answers nil and the state alone would be
                // re-tried — and re-written — on every frame.
                if offset.wrappedValue == 0, signpostState.wrappedValue == nil {
                    signpostState.wrappedValue = RailSignpost.ui.beginAnimation("ui.dockDrag")
                }
                offset.wrappedValue = translation.height
                let height = Self.liveHeight(offset: offset.wrappedValue, inputs: inputs)
                morph.update(
                    stage: inputs.metrics.stage(nearest: height),
                    expansion: inputs.metrics.headerExpansionProgress(for: height))
            },
            ended: { _, predicted in
                // `onEnded` already clears this on a normal release; the
                // nil-before-end ordering makes a following `cancelled` call
                // a no-op, and it stays that way.
                if let interval = signpostState.wrappedValue {
                    signpostState.wrappedValue = nil
                    RailSignpost.ui.end("ui.dockDrag", interval)
                }
                let target = inputs.metrics.stage(nearest: inputs.settled - predicted.height)
                withAnimation(RailMotion.animation(RailMotion.spring, reduceMotion: inputs.reduceMotion)) {
                    offset.wrappedValue = 0
                    let settled = inputs.metrics.available(target)
                    morph.update(
                        stage: settled,
                        expansion: inputs.metrics.headerExpansionProgress(
                            for: inputs.metrics.height(of: settled)))
                    inputs.onSettle(target)
                }
            },
            cancelled: {
                // `ended` is followed by `cancelled` on every normal release;
                // ending the signpost twice would be a no-op even without the
                // guard below, because the state is cleared before the end.
                if let interval = signpostState.wrappedValue {
                    signpostState.wrappedValue = nil
                    RailSignpost.ui.end("ui.dockDrag", interval)
                }
                guard offset.wrappedValue != 0 else { return }
                withAnimation(RailMotion.animation(RailMotion.spring, reduceMotion: inputs.reduceMotion)) {
                    offset.wrappedValue = 0
                    let height = Self.liveHeight(offset: 0, inputs: inputs)
                    morph.update(
                        stage: inputs.metrics.stage(nearest: height),
                        expansion: inputs.metrics.headerExpansionProgress(for: height))
                }
            })
    }
}
