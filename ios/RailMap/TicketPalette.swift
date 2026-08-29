import SwiftUI
import UIKit

/// 「きっぷ」 — the colours a Japanese railway ticket is printed in, and the
/// only place in this app that spells them.
///
/// §6.1 gives Statistics, replay covers and share images the **Memory**
/// personality: "expressive / railway-signage / route-colour / ticket-and-map
/// metaphors / editorial / souvenir-like". The word in that list this file
/// answers is **ticket**. Until now the passport's stationery was drawn in two
/// borrowed system hues — `systemBlue` into `systemIndigo` — which is a
/// perfectly good gradient and is also the gradient every other iOS app
/// reaches for first. It said nothing about railways and nothing about Japan.
///
/// A Japanese ticket does. There are only a handful of colours involved and
/// every one of them is load-bearing to somebody who has held one:
///
///   - **地紋 (jimon)** — the warm apricot security print an ordinary
///     磁気乗車券 is stocked on. This is *the* colour of a Japanese ticket.
///   - **みどり** — the green a reserved-seat 特急券 is issued on, and the
///     green of the みどりの窓口 it is issued at.
///   - **濃紺** — the navy the data on a ticket is actually printed in, which
///     is what the green runs into on the data page below.
///   - **朱 (shu)** — the vermillion of a 改札印, the round gate stamp a
///     station master inks onto the face of the ticket.
///   - **橙** — the orange the magnetic stock's own figures are set in, which
///     is this screen's bar ink.
///
/// ## §6.2, and why these are hex
///
/// §6.2 bans **scattered** hex and reserves green / orange / red for status.
/// Both rules are read here rather than ignored.
///
/// *Scattered* is the operative word in the first: this file is the one place
/// the five hues exist, every surface below is derived from them, and no call
/// site anywhere else in the app names a colour. That is the property the rule
/// protects, and it is stronger now than it was under `systemBlue` — which was
/// a system name in one file and a private deepening factor beside it.
///
/// The second is a rule about **meaning**, not about wavelength. Green, orange
/// and red are reserved so that a badge, a label or a row cannot be misread as
/// a state. Nothing below is a badge, a label or a row: they are the paper the
/// figures are printed on and the ink they are printed in, on the one screen
/// §6.1 hands to the Memory personality. The status roles keep the semantic
/// colours they have everywhere else in the app, and this screen draws no
/// status. A card cannot be misread as "success" when nothing on the screen it
/// belongs to ever reports success.
///
/// ## Derived, not literal
///
/// The reason §6.2 gives for banning hex — that a literal will not follow the
/// appearance, will not answer Increase Contrast, and will not move when the
/// system revises its palette — is answered by ``printed(_:light:dark:lightContrast:darkContrast:saturate:)``
/// rather than by refusing to name a colour. Each hue is written down ONCE, as
/// the ink it is on paper, and every appearance of it is that ink resolved
/// through a trait closure: darker under the dark appearance where a saturated
/// surface would otherwise glow, further from its background under Increase
/// Contrast, and — for the bar ink, which has to stand OUT of the paper rather
/// than sink into it — brighter in the dark rather than darker.
enum TicketPalette {

    // MARK: - the five inks, written down once

    /// 地紋 — the warm stock an ordinary 磁気乗車券 is printed on, and the
    /// brown its keylines and washes are drawn from.
    private static let stock = "#C98A3E"
    /// みどりの窓口 — the green a 指定席券 is issued on.
    private static let midori = "#0E6B4F"
    /// The navy a ticket's own data is printed in.
    private static let navy = "#123A52"
    /// 改札印 — the vermillion of a gate stamp.
    private static let vermillion = "#C1372B"
    /// The orange the magnetic stock sets its figures in — this screen's bars.
    private static let orange = "#C85A1E"

    // MARK: - the paper

    /// The data page: みどり into 濃紺 along the diagonal the eye reads the
    /// card in.
    ///
    /// Both ends carry white ink at better than 6:1 in the light appearance
    /// (green ≈ 6.6, navy ≈ 11.9), which is the whole reason the deep pair was
    /// chosen over the apricot stock a 乗車券 is actually printed on: a real
    /// ticket is dark ink on light paper, and a light card cannot be the one
    /// loud surface on a screen of light cards. The apricot is on every OTHER
    /// card instead (``stockWash``), which is where a ticket's stock belongs —
    /// under the figures, not shouting over them.
    static var dataPage: LinearGradient {
        LinearGradient(
            colors: [
                printed(midori, dark: 0.80, lightContrast: 0.86, darkContrast: 0.86),
                printed(navy, dark: 0.82, lightContrast: 0.88, darkContrast: 0.88),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }

    /// The tint wash on a soft card — 地紋 at the alpha where it colours the
    /// paper without colouring the text on it.
    ///
    /// Warmer in the dark appearance rather than fainter: a low-alpha warm hue
    /// over `secondarySystemBackground` disappears completely once that
    /// surface is nearly black, and a card that is only tinted in one
    /// appearance is a card that changes personality at sunset.
    static var stockWash: LinearGradient {
        LinearGradient(
            colors: [
                wash(stock, light: 0.16, dark: 0.20, contrast: 0.24),
                wash(stock, light: 0.05, dark: 0.08, contrast: 0.10),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }

    /// §6.5: a surface gains an EDGE under Increase Contrast rather than more
    /// colour. The soft card carries this always — the wash alone is too faint
    /// to say where the card stops.
    static var keyline: Color {
        wash(stock, light: 0.30, dark: 0.34, contrast: 0.66)
    }

    /// The translucent block a card nests inside itself — the reference's
    /// footer chip, and the field a ticket stamps a single day into.
    static var chip: Color {
        wash(stock, light: 0.13, dark: 0.18, contrast: 0.24)
    }

    /// The unfilled part of a proportion bar: the paper a bar has not been
    /// printed on yet, so it is the stock's own hue rather than a grey.
    static var track: Color {
        wash(stock, light: 0.20, dark: 0.24, contrast: 0.34)
    }

    // MARK: - the ink

    /// …and the filled part. 磁気券's own orange.
    ///
    /// It is the one colour here that has to stand OUT of the paper rather
    /// than sink into it, so it is the one that goes BRIGHTER in the dark
    /// appearance and further from its ground in both under Increase Contrast.
    ///
    /// Never the positive/green role: §5.3.5 is explicit that a large number
    /// is not a success state, and that is why the green in this file is the
    /// paper a ticket is issued on and never the ink a figure is drawn in.
    static var fill: Color {
        printed(orange, dark: 1.34, lightContrast: 0.86, darkContrast: 1.12, saturate: 0.04)
    }

    /// 改札印 — the vermillion the date stamp is inked with.
    ///
    /// Decoration on paper, and on the data page it is the one hue that cannot
    /// simply be deepened: vermillion on deep green is barely a colour change
    /// at all. So ``stampInkOnColor`` is the same ink LIGHTENED instead, to
    /// the coral it reads at over the green — and both are used for the
    /// stamp's RULE only. The words inside a stamp stay on the ink roles that
    /// answer to Increase Contrast, which is why neither of these has to carry
    /// text contrast.
    static var stampInk: Color {
        printed(vermillion, dark: 1.22, lightContrast: 0.88, darkContrast: 1.10)
    }

    /// The same stamp, over the data page.
    static var stampInkOnColor: Color {
        printed(vermillion, light: 1.62, dark: 1.62, lightContrast: 1.14, darkContrast: 1.14,
            saturate: -0.32)
    }

    // MARK: - resolving one ink for the appearance it is read in

    /// One printed hue, resolved for the appearance and the contrast setting
    /// it is being read under.
    ///
    /// Every argument is a multiplier on the ink's own BRIGHTNESS, which is
    /// the only component that decides whether the thing on top of it is
    /// legible — the hue is preserved exactly, so a deepened みどり is still
    /// the green a 特急券 is issued on and not a different colour that happens
    /// to be dark.
    ///
    ///   - `light` / `dark`: the appearance the card is drawn in.
    ///   - `lightContrast` / `darkContrast`: applied ON TOP of those under
    ///     Increase Contrast. Two of them rather than one because "more
    ///     contrast" is *darker* for a surface carrying white ink and
    ///     *brighter* for ink carried on a dark surface, and a single factor
    ///     would improve one and ruin the other.
    ///   - `saturate`: an additive nudge, for the two cases where brightness
    ///     alone leaves the hue looking washed (a brightened orange) or
    ///     leaves it too hot to read as a stamp over green (a lightened
    ///     vermillion).
    private static func printed(
        _ hex: String,
        light: CGFloat = 1,
        dark: CGFloat = 1,
        lightContrast: CGFloat = 1,
        darkContrast: CGFloat = 1,
        saturate: CGFloat = 0
    ) -> Color {
        Color(
            UIColor { traits in
                // A malformed literal is a programmer error in THIS file and
                // nowhere else — there is no call site that can pass one in —
                // so it resolves to the label colour rather than to a colour
                // that would look deliberate.
                guard let base = UIColor(railHex: hex) else { return .label }
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                guard
                    base.getHue(
                        &hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                else { return base }
                let isDark = traits.userInterfaceStyle == .dark
                var factor = isDark ? dark : light
                if traits.accessibilityContrast == .high {
                    factor *= isDark ? darkContrast : lightContrast
                }
                return UIColor(
                    hue: hue,
                    saturation: min(1, max(0, saturation + saturate)),
                    brightness: min(1, max(0, brightness * factor)),
                    alpha: alpha)
            })
    }

    /// The same ink at an ALPHA that follows the appearance — a wash, a
    /// keyline, a track.
    ///
    /// Separate from ``printed(_:light:dark:lightContrast:darkContrast:saturate:)``
    /// because these are not surfaces in their own right: they are one hue laid
    /// over whatever the system card underneath resolved to, and what has to
    /// change between appearances is how much of it there is, not how dark it
    /// is.
    private static func wash(
        _ hex: String, light: CGFloat, dark: CGFloat, contrast: CGFloat
    ) -> Color {
        Color(
            UIColor { traits in
                guard let base = UIColor(railHex: hex) else { return .separator }
                if traits.accessibilityContrast == .high {
                    return base.withAlphaComponent(contrast)
                }
                return base.withAlphaComponent(
                    traits.userInterfaceStyle == .dark ? dark : light)
            })
    }
}
