import CoreGraphics

/// The spacing scale of JRM_FLIGHTY_UI_REFACTOR_SPEC §6.4.
///
/// Same-layer components take their gaps from here rather than inventing 13,
/// 17 or 19. `ios/tools/check-ui-tokens.sh` flags new numeric literals.
nonisolated enum RailSpacing {
    /// Hairline gap only (label over value); not a layout step.
    static let s2: CGFloat = 2
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32

    /// Content edge in sheets, the panel and cards.
    static let screenInset: CGFloat = s16
    /// Inner padding of every content card (spec: 16-20).
    static let cardPadding: CGFloat = s16
    /// Floating controls over the map.
    static let mapChromeInset: CGFloat = s12
    /// List row vertical inset. A documented exception to the scale.
    static let rowVertical: CGFloat = 6
    /// Label over value.
    static let labelValueGap: CGFloat = s2
    static let sectionGap: CGFloat = s16
}

/// Corner radii of spec §6.4: radius expresses depth (control < card < sheet).
/// A pill is `Capsule()`, not a radius.
nonisolated enum RailRadius {
    static let control: CGFloat = 12
    static let card: CGFloat = 20
    static let sheet: CGFloat = 28
}

/// Control and glyph sizes of spec §6.4.
nonisolated enum RailSize {
    /// Minimum touch target.
    static let touch: CGFloat = 44
    static let compactControl: CGFloat = 32
    static let mapControl: CGFloat = 48
    static let glyph: CGFloat = 18
    static let mapGlyph: CGFloat = 20
    static let textEditorMinHeight: CGFloat = 120
    static let progressBar: CGFloat = 6
}
