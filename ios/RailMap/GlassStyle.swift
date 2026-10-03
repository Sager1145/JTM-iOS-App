import SwiftUI

/// Liquid Glass where the system has it, a material where it does not.
///
/// `glassEffect(_:in:)` and `GlassEffectContainer` are iOS 26 and later
/// (checked against the iOS 27 SDK's own interface, not remembered). The app
/// deploys to iOS 17, so every use goes through here rather than being spelled
/// out at each call site with its own `#available` — one place to change when
/// the floor moves, and no chance of a control that is glass on one screen and
/// material on the next.
///
/// The fallback is `.regularMaterial`, which is what glass degrades to in
/// spirit: a surface that takes its colour from what is behind it. Over a map
/// that is the whole point, because the same control sits over pale city fill
/// and dark water within one pan.
extension View {

    /// A floating surface — a control capsule, a panel.
    ///
    /// `interactive` is worth passing for anything the finger lands on: it is
    /// what makes glass respond to touch rather than sit there as a texture,
    /// and leaving it off is the difference between a control that feels
    /// pressed and one that merely changes colour.
    ///
    /// Two accessibility settings are answered here rather than at the call
    /// sites, for the same reason the availability check is (§10.5):
    ///
    ///   - **Reduce Transparency** replaces the material with an opaque
    ///     surface. Glass over a map is a legibility bet — the control takes
    ///     its colour from whatever the reader has panned under it — and this
    ///     is the setting that says not to take it.
    ///   - **Increase Contrast** adds a hairline border, because a surface
    ///     that is defined only by its blur has no edge to find.
    func railGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        modifier(RailGlassSurface(shape: AnyShape(shape), interactive: interactive))
    }

    /// Leave sheet and popover glass to the system on iOS 26 and later.
    /// An explicit color here would replace the native presentation material.
    @ViewBuilder
    func railMenuPresentationBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            presentationBackground(Color.railMenuBackground)
        }
    }

    /// Native sheets keep their lower corners concentric with the display.
    /// A fixed radius overrides that geometry as the sheet changes height.
    @ViewBuilder
    func railMenuPresentationCornerRadius() -> some View {
        if #available(iOS 26.0, *) {
            presentationCornerRadius(nil)
        } else {
            presentationCornerRadius(WorkspaceMenuMetrics.cardCornerRadius)
        }
    }

    /// A menu's custom circular label, with the system's touch response.
    /// Standard menu popups supply their own material independently of labels.
    @ViewBuilder
    func railMenuControlSurface(in shape: some Shape, isActive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(
                isActive ? .regular.tint(.accentColor.opacity(0.16)).interactive()
                    : .regular.interactive(),
                in: shape)
        } else {
            background(
                isActive ? AnyShapeStyle(Color.accentColor.opacity(0.16))
                    : AnyShapeStyle(.quaternary.opacity(0.5)),
                in: shape)
                .overlay {
                    shape.stroke(
                        isActive ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.06),
                        lineWidth: 0.5)
                }
        }
    }

    /// Text menu labels use the native glass button style and its sizing.
    @ViewBuilder
    func railMenuButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            self
        }
    }
}

private struct RailGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var shape: AnyShape
    var interactive: Bool

    func body(content: Content) -> some View {
        surface(content)
            .overlay {
                if contrast == .increased {
                    shape.stroke(Color.primary.opacity(0.55), lineWidth: 1)
                }
            }
    }

    @ViewBuilder
    private func surface(_ content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(.secondarySystemBackground), in: shape)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: shape
            )
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

// MARK: - card colours

extension Color {
    /// Keep menu content transparent above native presentation glass.
    /// Earlier systems retain the original color at the base interface level.
    static var railMenuBackground: Color {
        if #available(iOS 26.0, *) { return .clear }
        return Color(
            UIColor { traits in
                let semantic: UIColor = traits.userInterfaceStyle == .dark
                    ? .secondarySystemBackground : .systemBackground
                return semantic.resolvedColor(
                    with: traits.modifyingTraits {
                        $0.userInterfaceLevel = .base
                    })
            })
    }

    /// Resolves a semantic colour at the elevated interface level.
    ///
    /// The printed passport ticket and share images use this for their fill.
    static func railElevated(_ semantic: UIColor) -> Color {
        Color(
            UIColor { traits in
                semantic.resolvedColor(
                    with: traits.modifyingTraits {
                        $0.userInterfaceLevel = .elevated
                    })
            })
    }
}

/// Groups glass surfaces so the system can treat them as one piece of material
/// — which is what lets neighbouring capsules pick up each other's light
/// instead of each rendering its own slab.
///
/// A plain `VStack` on older systems, where there is nothing to coordinate.
struct RailGlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - The half-height sheets

extension View {
    /// The stops of a sheet that is ABOUT the map or the transport — half by
    /// default, full when the reader pulls it up (§4.2) — declared once so the
    /// layers, legend, station card, ride chooser and export options agree.
    ///
    /// Not on Mac Catalyst. A form sheet there is a centred window that
    /// ignores detents, yet declaring them still changed the opening: a small
    /// light bar, about a grabber's width, rose from the window's bottom edge
    /// for a third of a second while the sheet itself faded in place, and ran
    /// back down when it closed. Recorded at 60 fps on the layers sheet; the
    /// import sheet, which declares no detents, fades in with no bar. Which
    /// UIKit view the bar is was not confirmed — the ride chooser already
    /// hides its drag indicator, so do not expect `presentationDragIndicator`
    /// alone to cure a new case; leave the detents off instead.
    ///
    /// This is a gate on a capability the platform lacks, not a layout
    /// branch: which composition a window gets is still decided by its size
    /// alone (README, "no idiom check, no Catalyst check").
    func railHalfSheetDetents() -> some View {
        #if targetEnvironment(macCatalyst)
        self
        #else
        presentationDetents([.medium, .large])
        #endif
    }
}

private struct RailOnDockSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether this subtree is drawn on the docked card (the iPad and Mac
    /// sidebar) rather than in the phone sheet.
    var railOnDockSurface: Bool {
        get { self[RailOnDockSurfaceKey.self] }
        set { self[RailOnDockSurfaceKey.self] = newValue }
    }
}
