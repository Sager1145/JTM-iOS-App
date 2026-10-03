import SwiftUI

/// Text controls share the visible height of the circular sheet controls.
struct RailCapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var visualHeight: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        CapsuleBody(configuration: configuration, prominent: prominent, visualHeight: visualHeight)
    }

    private struct CapsuleBody: View {
        let configuration: Configuration
        let prominent: Bool
        let visualHeight: CGFloat?
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(
                    minHeight: visualHeight ?? SheetIconButton<Image>.visualSide,
                    maxHeight: visualHeight)
                .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tint))
                .background(
                    prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary.opacity(0.5)),
                    in: Capsule())
                .scaleEffect(configuration.isPressed && isEnabled ? RailMotion.pressedScale : 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : RailMotion.disabledOpacity)
                .animation(RailMotion.press, value: configuration.isPressed && isEnabled)
        }
    }
}

extension View {
    /// Keeps a compact control's visual style while giving the control the
    /// minimum landing area used throughout the app.
    ///
    /// Apply this to the semantic control, after its style, rather than to a
    /// surrounding row. A row-sized frame does not enlarge the button inside
    /// it, and fixed heights can clip labels when Dynamic Type needs more room.
    func railMinimumTouchTarget() -> some View {
        frame(
            minWidth: RailStyle.minimumTouchTarget,
            minHeight: RailStyle.minimumTouchTarget)
            .contentShape(.rect)
    }
}
