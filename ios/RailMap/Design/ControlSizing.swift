import SwiftUI

/// The label colour of a button with the `.destructive` role: the accessible red
/// the status labels use (`RailStatusKind.error`), never the stock system red,
/// which is 3.6:1 on a light capsule. A destructive button is never drawn as the
/// prominent (filled) capsule: HIG forbids the primary role for destructive
/// actions, and `check-ui-tokens.sh` rejects `.railPrimary` on one.
private func railButtonLabelStyle(role: ButtonRole?, prominent: Bool) -> AnyShapeStyle {
    if role == .destructive { return AnyShapeStyle(RailStatusKind.error.tint) }
    return prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tint)
}

/// Text controls share the visible height of the circular sheet controls.
struct RailCapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var visualHeight: CGFloat? = nil
    /// Stretch the label to the proposed width (full-width action rows).
    var fillsWidth = false
    /// Leading and trailing padding of the capsule. 12 everywhere except the
    /// journey row's compact candidate, which narrows it to fit five controls.
    var horizontalPadding: CGFloat = 12
    /// Build the 44-pt touch area into the style (frame plus content shape
    /// around the capsule) so call sites need no `railMinimumTouchTarget()`.
    var minimumTouch = false

    func makeBody(configuration: Configuration) -> some View {
        CapsuleBody(
            configuration: configuration, prominent: prominent, visualHeight: visualHeight,
            fillsWidth: fillsWidth, minimumTouch: minimumTouch,
            horizontalPadding: horizontalPadding)
    }

    private struct CapsuleBody: View {
        let configuration: Configuration
        let prominent: Bool
        let visualHeight: CGFloat?
        let fillsWidth: Bool
        let minimumTouch: Bool
        let horizontalPadding: CGFloat
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

        /// A destructive button keeps the quiet capsule even when asked for the
        /// prominent one: the red label on the filled tint would be unreadable.
        private var filled: Bool { prominent && configuration.role != .destructive }

        private var capsule: some View {
            configuration.label
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, WorkspaceMenuMetrics.compactButtonVerticalInset)
                // Compact labels align with circular controls at normal sizes,
                // but must be allowed to grow with Dynamic Type.
                .frame(minHeight: visualHeight ?? SheetIconButton<Image>.visualSide)
                .foregroundStyle(railButtonLabelStyle(role: configuration.role, prominent: filled))
                .background(
                    filled ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary.opacity(0.5)),
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
                .foregroundStyle(railButtonLabelStyle(role: configuration.role, prominent: false))
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
    static func railPrimary(visualHeight: CGFloat?, fillsWidth: Bool = false) -> Self {
        .init(prominent: true, visualHeight: visualHeight, fillsWidth: fillsWidth, minimumTouch: true)
    }
    static func railPrimary(visualHeight: CGFloat?, horizontalPadding: CGFloat) -> Self {
        .init(prominent: true, visualHeight: visualHeight,
              horizontalPadding: horizontalPadding, minimumTouch: true)
    }
    static func railSecondary(visualHeight: CGFloat?, fillsWidth: Bool = false) -> Self {
        .init(prominent: false, visualHeight: visualHeight, fillsWidth: fillsWidth, minimumTouch: true)
    }
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
    /// The bar that holds a sheet's or screen's bottom action buttons: the
    /// screen inset on every side over the bar material. One padding for all
    /// four places that had their own (import, transfer guide, share, video).
    func railActionBar() -> some View {
        padding(RailSpacing.screenInset).background(.bar)
    }

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
