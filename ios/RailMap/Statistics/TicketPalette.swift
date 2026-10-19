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
///   - **RailMap 青** — the blue of the app's own mark, in the two strengths
///     the 字模様 is printed at: one for white stock, and one for 暗色 G, the
///     navy stock the passport is issued on after dark. It is also the ink the
///     色帯 across the foot of the face is laid in.
///   - **暗色 G の地色** — that navy itself.
///
/// The 朱 of a 改札印 used to be here too, for the frame a date was stamped
/// in. The face the design gives this card prints its date instead of stamping
/// it — 集計日 at the foot, and the 集計範囲 in the corner — so the vermillion
/// left with the mark it was mixed for rather than staying on as a hue in
/// search of a use.
///
/// The blue is the one hue here that is not a ticket's. It is the issuer's,
/// which is the same thing: a real 地紋 carries the letters of whoever issued
/// the ticket, and for these tickets that is this app. The shapes it is
/// printed in live in `TicketJimon` — this file is the hues, that one is the
/// geometry, the same split `PassportCardStyle` keeps.
///
/// ## One card
///
/// This file used to dress the whole statistics screen: an apricot 地紋 wash
/// under every chart card, that apricot again for keylines, chips and bar
/// tracks, and 磁気券's orange for every bar. It does not any more. The
/// passport is the only card issued on ticket stock, and everything around it
/// draws in the system's semantic colours — so the hues that only ever served
/// those other cards (the apricot, the orange, and the `wash` helper that
/// resolved them at an alpha) are gone rather than kept warm.
///
/// ## §6.2, and why these are hex
///
/// §6.2 bans **scattered** hex and reserves green / orange / red for status.
/// Both rules are read here rather than ignored.
///
/// *Scattered* is the operative word in the first: this file is the one place
/// these hues exist, every surface below is derived from them, and no call
/// site anywhere else in the app names a colour. That is the property the rule
/// protects, and it is stronger now than it was under `systemBlue` — which was
/// a system name in one file and a private deepening factor beside it.
///
/// The second is a rule about **meaning**, not about wavelength. Green, orange
/// and red are reserved so that a badge, a label or a row cannot be misread as
/// a state. Nothing below is a badge, a label or a row: they are the paper one
/// card is printed on and the ink it is printed in. The status roles keep the
/// semantic colours they have everywhere else in the app, and this screen
/// draws no status. A card cannot be misread as "success" when nothing on the
/// screen it belongs to ever reports success.
///
/// ## One ink per stock, not one ink dimmed
///
/// The reason §6.2 gives for banning hex is that a literal will not follow the
/// appearance. These do, and they do it by being TWO inks rather than one ink
/// resolved twice: 「浅色版 #1f8fe0（紙白）／暗色 G 版 #5cb8f7（地色 #0B2440）」
/// is the design stating a light stock and a dark stock as separate printings,
/// each with its own ground and its own ink, and every entry point below takes
/// `onDarkStock` and hands back the pair that belong together. A blue drawn to
/// read on white paper has nothing left to read against on navy, so deriving
/// one from the other by a brightness factor — which is what this file used to
/// do — was answering the appearance with arithmetic where the design had
/// already answered it with a second plate.
///
/// Increase Contrast is answered where it can be: `TicketJimon` damps the
/// print (a security 地紋 must get QUIETER, not louder, when the figures over
/// it need to stand out) and `PassportCardStyle` strikes the card a keyline.
/// Neither is a change of hue, which is §6.5's instruction exactly.
enum TicketPalette {

    // MARK: - the inks, written down once

    /// The blue of the app's own mark, which is the ink its 字模様 is printed
    /// in on white stock. 「浅色版 #1f8fe0（紙白）」.
    private static let issuerBlue = "#1F8FE0"
    /// The same ink lightened for 暗色 G, where the ground is navy instead of
    /// paper and a blue drawn to read on white has nothing left to read
    /// against. 「暗色 G 版 #5cb8f7」.
    private static let issuerBlueOnDark = "#5CB8F7"
    /// 暗色 G の地色 — the navy the passport is issued on after dark, and the
    /// one ground the design names outright: 「地色 #0B2440」.
    private static let darkGround = "#0B2440"

    // MARK: - the paper

    /// 暗色 G — the stock the passport is issued on in the dark appearance.
    ///
    /// Flat, and deliberately not a gradient. 「地色を全面に刷り、線と文字を
    /// 明色で抜く」 is what the dark stock IS: one ground laid edge to edge
    /// with the print knocked out of it in light ink. A gradient underneath a
    /// 地紋 would make the print look like it fades, which is the one thing a
    /// security print must never appear to do.
    ///
    /// It carries white ink at about 17:1, which is the margin the printed
    /// letters and rings on top of it spend without costing the figures
    /// anything.
    ///
    /// There is no matching constant for the light appearance because there is
    /// nothing to name: 「紙自体は白」 — the stock is white, so the passport takes
    /// the same system card surface every other card takes, under the wash
    /// ``jimonTint(onDarkStock:)`` lays over it.
    static var darkStock: Color { printed(darkGround) }

    /// The ink the 字模様 is printed in, for the appearance it is read in.
    ///
    /// Two literals rather than one hue deepened, because these are two
    /// different inks on two different stocks and not one ink under two
    /// lights: a blue drawn to read on white paper has nothing left to read
    /// against on 暗色 G's navy.
    static func jimonInk(onDarkStock: Bool) -> Color {
        printed(onDarkStock ? issuerBlueOnDark : issuerBlue)
    }

    /// The wash between a stock's paper and its print.
    ///
    /// Both stocks carry one, at the two strengths the artboard lays down
    /// under the 地紋: `rgba(31,143,224,0.06)` over paper white, and
    /// `rgba(255,255,255,0.04)` over the navy.
    ///
    /// This was `.clear` on white for a while, on the reading that 「紙自体は
    /// 白」 — the paper is not dyed, and what looks tinted is the line density
    /// of the print. That reading is right about a real 券紙 and wrong about
    /// this card: the panel behind it resolves to `#FFFFFF`, so a stock that
    /// is white to the last percent has no edge against the surface it is
    /// lying on. Six percent is what the design itself paints, and it is what
    /// makes the ticket a card.
    static func jimonTint(onDarkStock: Bool) -> Color {
        onDarkStock
            ? .white.opacity(0.04)
            : printed(issuerBlue).opacity(0.06)
    }

    /// 色帯 — the stripe across the foot of the face.
    ///
    /// 「色帯は地紋色の 28 %（暗色版は白 7 %）を全幅に敷く」. Two different
    /// answers rather than one, and the asymmetry is the design's: over paper
    /// the band is the 地紋's own ink laid solid, and over the navy a blue band
    /// on a blue ground would not be a band at all, so it is struck in white
    /// instead.
    static func band(onDarkStock: Bool) -> Color {
        onDarkStock
            ? .white.opacity(0.07)
            : printed(issuerBlue).opacity(0.28)
    }

    // MARK: - one hex, resolved

    /// One printed hue, as a `Color`.
    ///
    /// The whole of what this does is turn a hex the design wrote down into a
    /// colour, in the ONE file allowed to name one. It used to carry five
    /// brightness multipliers so a single ink could be re-resolved per
    /// appearance and per contrast setting; the design's own two-plate answer
    /// (see the note on this type) made every one of them the identity, and a
    /// parameter that is always defaulted is a claim about the code that is
    /// not true.
    private static func printed(_ hex: String) -> Color {
        // A malformed literal is a programmer error in THIS file and nowhere
        // else — there is no call site that can pass one in — so it resolves
        // to the label colour rather than to a colour that would look
        // deliberate.
        Color(UIColor(railHex: hex) ?? .label)
    }
}
