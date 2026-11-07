import SwiftUI

/// Text controls share the visible height of the circular sheet controls.
struct RailCapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var visualHeight: CGFloat? = nil
    /// Stretch the label to the proposed width (full-width action rows).
    var fillsWidth = false
    /// Build the 44-pt touch area into the style (frame plus content shape
    /// around the capsule) so call sites need no `railMinimumTouchTarget()`.
    var minimumTouch = false

    func makeBody(configuration: Configuration) -> some View {
        CapsuleBody(
            configuration: configuration, prominent: prominent, visualHeight: visualHeight,
            fillsWidth: fillsWidth, minimumTouch: minimumTouch)
    }

    private struct CapsuleBody: View {
        let configuration: Configuration
        let prominent: Bool
        let visualHeight: CGFloat?
        let fillsWidth: Bool
        let minimumTouch: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            capsule
                .frame(
                    minWidth: minimumTouch ? RailSize.touch : nil,
                    minHeight: minimumTouch ? RailSize.touch : nil)
                .contentShape(.rect)
                .scaleEffect(configuration.isPressed && isEnabled ? RailMotion.pressedScale : 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : RailMotion.disabledOpacity)
                .animation(RailMotion.press, value: configuration.isPressed && isEnabled)
        }

        private var capsule: some View {
            configuration.label
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .padding(.horizontal, 12)
                .padding(.vertical, WorkspaceMenuMetrics.compactButtonVerticalInset)
                // Compact labels align with circular controls at normal sizes,
                // but must be allowed to grow with Dynamic Type.
                .frame(minHeight: visualHeight ?? SheetIconButton<Image>.visualSide)
                .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tint))
                .background(
                    prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary.opacity(0.5)),
                    in: Capsule())
        }
    }
}

/// Tertiary action: tinted label, no fill, 44-pt touch area.
struct RailTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TextBody(configuration: configuration)
    }

    private struct TextBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(.tint)
                .frame(minHeight: RailSize.touch)
                .contentShape(.rect)
                .scaleEffect(configuration.isPressed && isEnabled ? RailMotion.pressedScale : 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : RailMotion.disabledOpacity)
                .animation(RailMotion.press, value: configuration.isPressed && isEnabled)
        }
    }
}

extension ButtonStyle where Self == RailCapsuleButtonStyle {
    /// Prominent capsule with the 44-pt touch area built in.
    static var railPrimary: Self { .init(prominent: true, minimumTouch: true) }
    /// Quiet capsule with the 44-pt touch area built in.
    static var railSecondary: Self { .init(prominent: false, minimumTouch: true) }
    static func railPrimary(fillsWidth: Bool) -> Self {
        .init(prominent: true, fillsWidth: fillsWidth, minimumTouch: true)
    }
    static func railSecondary(fillsWidth: Bool) -> Self {
        .init(prominent: false, fillsWidth: fillsWidth, minimumTouch: true)
    }
}

extension ButtonStyle where Self == RailTextButtonStyle {
    static var railTertiary: Self { RailTextButtonStyle() }
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
