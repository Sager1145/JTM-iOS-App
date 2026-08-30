import SwiftUI

/// §6.1's **Memory JRM** personality, as stationery.
///
/// The spec gives this app two visual personalities and names exactly which
/// surfaces get which. Lists, map, detail, editor and import are *Operational*
/// — "calm / system-native / map-first". Statistics, replay covers and share
/// images are *Memory* — "expressive / railway-signage / route-colour /
/// ticket-and-map metaphors / editorial / souvenir-like". Passport is the one
/// screen the second column is written for, and until now it was drawn in the
/// first: seven identical `secondarySystemBackground` cards, each opening with
/// a `.headline` label, in the same stationery as the delete confirmation.
///
/// So this file is the passport's paper and ink and nothing else. It carries
/// no numbers and knows nothing about statistics — ``StatisticsDashboardContent``
/// composes the pages out of it — which is what keeps the Memory personality
/// from leaking anywhere §6.1 forbids it: a view has to ASK for a tone.
///
/// ## Three tones, and why not seven
///
/// A screen where every card shouts has no hero. The reference this is drawn
/// from (Flighty's Passport) is mostly quiet: one printed data page, a
/// couple of tinted cards, and plain surfaces under the dense lists — so the
/// eye lands on the page that carries the headline numbers.
///
///   - ``PassportTone/feature`` is the data page: real ticket stock, 字模様
///     and all, for the ONE card that answers the screen's question. It is
///     the only card in the app that carries the print.
///   - ``PassportTone/soft`` is the system card surface with a hairline
///     keyline, for the cards that carry charts.
///   - ``PassportTone/plain`` is exactly the card this app already had, kept
///     for dense lists and for every non-statistics card in the workspace.
///
/// ## The colours
///
/// A Japanese railway ticket's, and ON THE PASSPORT ONLY. Every other card
/// here draws in the system's semantic colours, the same as the rest of the
/// app — one card carries the metaphor and the screen around it stays
/// stationery, which is the only way one card can be the hero of it.
///
/// The ticket's hues live in `TicketPalette.swift` rather than here — this
/// file is shape, spacing and ink ROLES, and that one is the hues those roles
/// resolve to. The split is what lets a card ask for "the block a figure sits
/// in" without also deciding what colour the stock is.
///
/// Three files make one ticket, and this is the third of them by depth: see
/// `TicketPalette` for the reading of §6.2 the ticket palette rests on,
/// `TicketJimon` for the 字模様 both stocks are printed with, and
/// `PassportTicketFace` for the TYPE that goes on top — the 組版規則 the
/// design states as a 510 × 345 artboard, which is what a `.feature` card
/// carries and no other card does.
enum PassportTone: Equatable {
    /// The data page — printed ticket stock. At most one per screen, and the
    /// only tone the 字模様 is laid under.
    case feature
    /// A system surface with a hairline keyline.
    case soft
    /// The ordinary content card (§6.4's `radius-card` on a system surface).
    case plain
}

extension View {
    /// Draw this as one passport card.
    ///
    /// Also publishes ``PassportInk`` into the subtree, which is how the
    /// components below know whether they are drawing on colour without every
    /// call site having to say so twice (and get it wrong once).
    func passportCard(_ tone: PassportTone = .plain) -> some View {
        modifier(PassportCardSurface(tone: tone))
    }
}

// MARK: - ink

/// Which colours a card's contents draw in.
///
/// On a `.soft` or `.plain` card these are the semantic roles and nothing
/// else, so Increase Contrast and the dark appearance stay the system's
/// business.
///
/// On the passport they are not, because the passport is the one card printed
/// on stock. See ``faceInk``.
struct PassportInk: Equatable {
    /// Whether this is the passport itself — a card printed on ticket stock
    /// rather than drawn on a system surface.
    var onStock: Bool = false
    /// Whether that stock is 暗色 A rather than white paper. Only ever true
    /// alongside ``onStock``.
    var onColor: Bool = false
    var increasedContrast: Bool = false

    static let plain = PassportInk()

    /// The single ink a ticket's face is printed in.
    ///
    /// Solid, at full alpha, and either pure black or pure white — never a
    /// grey, never a percentage. 「券面文字は地紋より必ず濃く」 is the design's
    /// own rule and it is not a preference: the face type has to be darker
    /// than the 地紋 under it, and `secondaryLabel` — sixty percent of a dark
    /// grey — is not darker than a security print at any density that still
    /// reads as one. A ticket has no second ink to fall back to.
    ///
    /// So the passport gives up the type hierarchy that colour was carrying
    /// and lets size, weight and tracking carry it instead, which is what a
    /// press does when it has one plate. `Color.black` and `Color.white` are
    /// safe as literals here precisely because ``onColor`` tracks the stock:
    /// white paper is only ever issued in the light appearance and 暗色 A only
    /// in the dark one, so neither literal can turn up against its own ground.
    private var faceInk: Color { onColor ? .white : .black }

    /// A heading or a figure — the thing being read.
    var title: Color { onStock ? faceInk : .primary }
    /// The small tracked label above a figure.
    var eyebrow: Color { onStock ? faceInk : .secondary }
    /// A caption under a figure, a footnote, a unit.
    var caption: Color { onStock ? faceInk : .secondary }
    /// A rule or divider.
    var rule: Color { onColor ? .white.opacity(0.24) : Color(.separator) }
    /// The translucent block a card nests inside itself — the reference's
    /// footer chip, and the highlight above a list.
    ///
    /// On the passport this is ``faceInk`` at an alpha, for the same reason
    /// the type is: one plate, one ink. A screened block on a ticket is the
    /// same ink laid down lighter, never a second colour.
    ///
    /// Off the passport it is `tertiarySystemFill` — the system's own answer
    /// for a block nested inside a card, and the answer every card here gives
    /// now that the ticket's colours are the passport's alone.
    var chip: Color {
        guard onStock else { return Color(.tertiarySystemFill) }
        return faceInk.opacity(increasedContrast ? 0.26 : 0.16)
    }
    /// The unfilled part of a proportion bar — the same ink again, and the
    /// same split.
    var track: Color {
        guard onStock else { return Color(.tertiarySystemFill) }
        return faceInk.opacity(0.26)
    }
    /// …and the filled part.
    ///
    /// On the passport it is the issuer's blue — the same ink the 字模様 under
    /// it is printed in, at full strength instead of at a third of one. That
    /// is the second plate a ticket is allowed: 地紋 in one colour and the
    /// figures in another, both of them the issuer's. A bar in a THIRD hue
    /// would be the only mark on the card that came from nowhere.
    ///
    /// Off the passport it is the app's own tint, which is what iOS fills a
    /// bar with. That is a deliberate re-reading of §6.2, not an oversight of
    /// it: the rule hands the tint to 可点击 / 选中 / 当前路线 so that nothing
    /// INERT borrows an interactive colour, and it was written when the
    /// alternative on offer was a bespoke hue. Between a bespoke hue on a
    /// chart bar and the system's, the system's is the one a reader has to
    /// learn nothing about — say the word and this goes back to a neutral.
    ///
    /// Never the positive/green role, here or on any other card: §5.3.5 is
    /// explicit that a large number is not a success state.
    var fill: Color {
        guard onStock else { return .accentColor }
        return TicketPalette.jimonInk(onDarkStock: onColor)
    }
}

private struct PassportInkKey: EnvironmentKey {
    static let defaultValue = PassportInk.plain
}

extension EnvironmentValues {
    var passportInk: PassportInk {
        get { self[PassportInkKey.self] }
        set { self[PassportInkKey.self] = newValue }
    }
}

private struct PassportPosterKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether this subtree is being drawn into a SHARE IMAGE rather than onto
    /// the screen. §6.1 names share images as Memory surfaces alongside the
    /// statistics themselves, which is why the flag lives in this file.
    ///
    /// A poster is a picture of an answer, not of the screen that answers it.
    /// So the cards drop the controls that only mean anything to a finger —
    /// the segmented pickers that choose an axis, and the disclosure that
    /// folds the tail of a ranked list — and commit to whatever the reader had
    /// set when they asked for the picture. Nothing else changes: same
    /// figures, same order, same wording.
    var passportPoster: Bool {
        get { self[PassportPosterKey.self] }
        set { self[PassportPosterKey.self] = newValue }
    }
}

// MARK: - the paper

private struct PassportCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    var tone: PassportTone

    /// §6.4's `radius-card`, except on the ticket.
    ///
    /// A 券紙 is die-cut, not rounded, and a rounded one reads as a picture OF
    /// a ticket rather than as one. The face inside it is drawn to the same
    /// premise — 「端まで刷り切る（塗り足しなし）。余白を残すと券紙らしさが消え
    /// ます」 — so a corner radius here would have been the one place the card
    /// stopped agreeing with its own contents.
    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: tone == .feature ? 0 : RailStyle.cardCornerRadius,
            style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            // §6.4: card padding 16–20, and NONE on the ticket. The face sets
            // its own 44 px margins inside the die-cut edge (see `TicketFace`),
            // and the 色帯 crosses the whole of it — both of which a card
            // inset would cut short.
            .padding(tone == .feature ? 0 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { fill }
            .clipShape(shape)
            .overlay { edge }
            .environment(
                \.passportInk,
                PassportInk(
                    onStock: tone == .feature,
                    onColor: tone == .feature && issuedOnDarkStock,
                    increasedContrast: contrast == .increased))
    }

    /// The passport is a piece of ticket stock — a ground, the wash between
    /// ground and print, and the 字模様 printed onto it. Every other card is
    /// the stationery it always was.
    ///
    /// That is the whole of the rule, and it is a rule about ONE card rather
    /// than about a family of them. A 地紋 is the loudest thing this file can
    /// put on a surface, and a screen where every card carries one has no
    /// passport on it — just nine tickets, none of which is the document. The
    /// tone that already means "at most one per screen" is the tone that gets
    /// the print.
    ///
    /// Which of the two stocks it is issued on follows the appearance, because
    /// that is the only thing the choice can follow once there is one card: by
    /// day the stock is white and takes the brand blue, and after dark it is
    /// 暗色 A, the variant the design draws for exactly the case where white
    /// paper is not the premise (「白紙前提でない面に用います」).
    @ViewBuilder private var fill: some View {
        switch tone {
        case .feature:
            ZStack {
                if issuedOnDarkStock {
                    TicketPalette.darkStock
                } else {
                    Color.railElevated(.secondarySystemBackground)
                }
                TicketPalette.jimonTint(onDarkStock: issuedOnDarkStock)
                TicketJimon(stock: issuedOnDarkStock ? .darkA : .jrm)
            }
        case .soft:
            // The system card surface and nothing over it. The wash that used
            // to warm this tone was a ticket's stock, and stock is now the one
            // thing that tells the passport apart from every other card on the
            // screen — a second card wearing a paler version of it made the
            // hero look like the first of a set.
            Color.railElevated(.secondarySystemBackground)
        case .plain:
            Color.railElevated(.secondarySystemBackground)
        }
    }

    /// Whether the passport is issued on 暗色 A rather than on white stock.
    ///
    /// This is also what decides the ink on top of it, which is why it is one
    /// property and not two: white type belongs on the navy stock and nowhere
    /// else, and the day the two answers disagree is the day the card becomes
    /// unreadable in one appearance.
    private var issuedOnDarkStock: Bool { colorScheme == .dark }

    /// §6.5: under Increase Contrast a surface gains an edge rather than more
    /// colour. The soft tone carries its keyline always — the wash alone is
    /// too faint to say where the card stops.
    @ViewBuilder private var edge: some View {
        switch tone {
        case .feature:
            if contrast == .increased {
                // The edge has to be drawn out of whichever stock is under it,
                // and a white hairline on white paper is not an edge.
                shape.strokeBorder(
                    issuedOnDarkStock ? Color.white.opacity(0.55) : Color(.separator),
                    lineWidth: 1)
            }
        case .soft:
            // Carried always rather than only under Increase Contrast: with
            // the wash gone this hairline is the whole of what separates a
            // soft card from a plain one.
            shape.strokeBorder(Color(.separator), lineWidth: 1)
        case .plain:
            if contrast == .increased {
                shape.strokeBorder(Color(.separator), lineWidth: 1)
            }
        }
    }
}

// MARK: - the pieces a page is set from

/// The small tracked label above a figure — the reference's "FLIGHTS",
/// "DISTANCE", "FLIGHT TIME".
///
/// Uppercased through the environment rather than in the string, so the
/// Japanese and Chinese labels (乗車時間, 停靠站) pass through untouched while
/// the English ones read as the document labels they are imitating. The
/// tracking does the same job in every script.
struct PassportEyebrow: View {
    @Environment(\.passportInk) private var ink
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(ink.eyebrow)
            .railType(.metricLabel)
    }
}

/// A card's head row: its label, and whatever control belongs to that card.
struct PassportCardHeader<Accessory: View>: View {
    @Environment(\.passportInk) private var ink
    let title: String
    var systemImage: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink.eyebrow)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.subheadline.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(ink.title)
                .railType(.title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            accessory()
        }
    }
}

extension PassportCardHeader where Accessory == EmptyView {
    init(_ title: String, systemImage: String? = nil) {
        self.init(title: title, systemImage: systemImage) { EmptyView() }
    }
}

/// The one figure a card is about: value, unit, and the line under it.
struct PassportHeadline: View {
    /// How loud this figure is. A card has ONE ``page`` headline; a figure
    /// nested inside a block on that card is a ``field``, or it would shout
    /// down the total it is a part of.
    enum Prominence {
        case page
        case field
    }

    @Environment(\.passportInk) private var ink
    /// What the figure IS, for VoiceOver — the eyebrow is not always the
    /// answer, because a headline sometimes sits under a card header instead.
    let label: String
    let value: String
    /// The whole block, spoken. `--` read as dashes says nothing, so the
    /// caller spells the unset state as a sentence.
    let spoken: String
    var unit: String?
    var caption: String?
    var prominence: Prominence = .page

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(
                        .system(
                            prominence == .page ? .largeTitle : .title,
                            design: .rounded
                        ).bold())
                    .monospacedDigit()
                    .foregroundStyle(ink.title)
                    .railType(.metricValueStacked)
                    // Inert unless the change arrives inside an animated
                    // transaction, and these land from an async store that has
                    // none — so the token is spelled here. §9.4 keeps numeric
                    // updates out of `RailMotion.animation`'s Reduce Motion
                    // path on purpose.
                    .contentTransition(.numericText())
                    .animation(RailMotion.replace, value: value)
                if let unit {
                    Text(unit)
                        .font(
                            (prominence == .page ? Font.title3 : Font.subheadline)
                                .weight(.semibold))
                        .foregroundStyle(ink.caption)
                        .railType(.metricLabel)
                }
            }
            if let caption {
                Text(caption)
                    .font(prominence == .page ? .subheadline : .caption)
                    .monospacedDigit()
                    .foregroundStyle(ink.caption)
                    .railType(.content)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spoken))
    }
}

/// The translucent block a card nests inside itself — the reference's footer
/// chip, and the ground a highlighted row is lifted onto.
///
/// §6.4: a block INSIDE a card takes `radius-control`, never the card's own
/// radius, because radius is what expresses depth here.
extension View {
    func passportBlock() -> some View { modifier(PassportBlockSurface()) }
}

private struct PassportBlockSurface: ViewModifier {
    @Environment(\.passportInk) private var ink

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ink.chip,
                in: RoundedRectangle(
                    cornerRadius: RailStyle.controlCornerRadius, style: .continuous))
    }
}

/// A hairline that follows the paper it is drawn on. `Divider()` resolves the
/// system separator, which is a dark grey line and invisible on a feature
/// card.
struct PassportRule: View {
    @Environment(\.passportInk) private var ink

    var body: some View {
        Rectangle()
            .fill(ink.rule)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A label and its figure on one line — the compact form of a group the card
/// has already stated in full.
struct PassportRow: View {
    @Environment(\.passportInk) private var ink
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(ink.title)
                .railType(.content)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(ink.caption)
                .multilineTextAlignment(.trailing)
                .railType(.content)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The reference's metric block: a tiny label, a figure, and an optional line
/// of colour under it ("4 Long Haul", "1.4x around the world").
///
/// Laid out by an ADAPTIVE grid rather than by `ViewThatFits`. That is the
/// difference worth knowing: a `ViewThatFits` candidate walk needs every
/// figure to state its true width on one line (see `RailType`'s contract),
/// whereas here the column count comes from a scaled minimum instead — so a
/// long figure may wrap INSIDE its cell, and a caption underneath cannot break
/// the row's shared baseline, because there is no shared baseline to break.
///
/// The statistics screen draws its metric row with this too
/// (`StatisticsDashboardContent`), so the two surfaces have one grid rather
/// than a Passport copy of a statistics one. An earlier revision of this note
/// named a `StatisticsMetricGrid` as the component this one deliberately
/// differed from; there is no such type any more.
struct PassportMetricGrid: View {
    /// How loud a grid's figures are.
    ///
    /// A card has ONE ``page`` grid — the row that answers its question — and
    /// the rest are ``field``. Two loud rows is two cards.
    enum Prominence {
        case page
        case field
    }

    struct Item: Identifiable {
        let label: String
        let value: String
        var caption: String?
        /// 0…1 for a cell whose figure is a proportion, drawn as a bar between
        /// the figure and its caption. `nil` for every ordinary cell.
        var fraction: Double?
        var id: String { label }

        init(
            _ label: String, _ value: String, caption: String? = nil,
            fraction: Double? = nil
        ) {
            self.label = label
            self.value = value
            self.caption = caption
            self.fraction = fraction
        }
    }

    @Environment(\.passportInk) private var ink
    /// Two across on a phone at the default text size, one at accessibility
    /// sizes — §10.1's "空间不足时改为纵向", reached by measurement rather than
    /// by a size class.
    @ScaledMetric(relativeTo: .title2) private var columnMinimum: CGFloat = 120

    let items: [Item]
    var prominence: Prominence = .field

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: columnMinimum), spacing: 16, alignment: .topLeading)
            ],
            alignment: .leading,
            spacing: 18
        ) {
            ForEach(items) { item in cell(item) }
        }
    }

    private func cell(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            PassportEyebrow(item.label)
            Text(item.value)
                .font(
                    .system(
                        prominence == .page ? .title : .title2,
                        design: .rounded
                    ).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(ink.title)
                .railType(.metricValueStacked)
                // `replace` directly, not through `RailMotion.animation(_:reduceMotion:)`,
                // for the reason ``PassportMetric`` gives above: §9.4 keeps
                // numeric updates. Noted here as well because a raw token is
                // what an audit greps for, and this is the deliberate case.
                .contentTransition(.numericText())
                .animation(RailMotion.replace, value: item.value)
            if let fraction = item.fraction {
                GeometryReader { geometry in
                    Capsule()
                        .fill(ink.track)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(ink.fill)
                                .frame(width: geometry.size.width * Self.clamp(fraction))
                        }
                }
                .frame(height: 5)
                .padding(.top, 2)
                // One clock for the cell: the figure above this bar already
                // rolls on `replace`, and the proportion under it is the same
                // statement in the other notation.
                .animation(RailMotion.replace, value: Self.clamp(fraction))
            }
            if let caption = item.caption {
                Text(caption)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(ink.caption)
                    .railType(.metricLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private static func clamp(_ fraction: Double) -> CGFloat {
        guard fraction.isFinite else { return 0 }
        return CGFloat(min(max(fraction, 0), 1))
    }
}

/// The one row a list is worth opening for, lifted out of the list — the
/// reference's "Most flown aircraft".
struct PassportHighlight: View {
    @Environment(\.passportInk) private var ink
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PassportEyebrow(eyebrow)
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(ink.title)
                .railType(.content)
            Text(detail)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(ink.caption)
                .railType(.metricLabel)
        }
        .passportBlock()
        .accessibilityElement(children: .combine)
    }
}

/// A quiet note at the foot of a card — §5.7's neutral wording for unmatched
/// distance, which is information about coverage rather than a data error and
/// must not borrow the critical role's colour.
struct PassportNote: View {
    @Environment(\.passportInk) private var ink
    let title: String
    let message: String
    var systemImage: String = "info.circle"

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .railType(.content)
                Text(message)
                    .font(.footnote)
                    .railType(.content)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(ink.caption)
        .accessibilityElement(children: .combine)
    }
}
