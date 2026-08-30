import CoreText
import SwiftUI
import UIKit

/// 券面 — the printed face of a RailMap ticket, at absolute artboard
/// coordinates.
///
/// ## What this file is
///
/// `TicketJimon` is the security print the stock arrives carrying and
/// `TicketPalette` is the ink it is printed in. This is the third piece: the
/// TYPE a MARS terminal puts down on top of them, and the grid it puts it down
/// on. Together the three are one ticket, and the passport is the only place in
/// the app that issues one.
///
/// ## A picture of a document, not a card of text
///
/// The design gives the face as a **510 × 345 px artboard at 6 px/mm** — a real
/// 85 × 57.5 mm 券紙 — with every element at an absolute coordinate. This file
/// keeps that: the face is laid out 1:1 on the artboard and then scaled by one
/// factor to whatever width the card has, so 「券種名 cx255」 is a line of code
/// rather than an approximation of one, and the proportions cannot drift
/// between devices.
///
/// ### The three bands
///
/// The card is the artboard: **510 × 345 px**, which is 「85×57.5mm を同じ
/// 6px/mm で 510×345px に取り」 and is 85 × 57.5 mm of 券紙 and nothing
/// rounded off it. It divides where the 色帯 divides it:
///
///   - **0 – 239** 券面. Everything the ticket states: 券種名 and its 罫, the
///     識別文字 and the 集計範囲, the two 大字 figures, the 中字 block of four,
///     and the 集計期間 under them.
///   - **239 – 274** 色帯, full width, carrying no type.
///   - **274 – 345** 最下行 — 集計日, the issuer, and the version.
///
/// Nothing is re-ordered and nothing is re-proportioned. Every y below is the
/// artboard's own `top:`, because 位置 in the 組版規則 is a list of
/// coordinates — 「券種名 cx255・y43」「大字二欄 cx150 / cx365（ラベル y92・
/// 数値 y107）」「二段 y158 / y184」「集計期間 x44・y214」「色帯 y239–274」
/// 「最下行 y296」 — and a coordinate that has been scaled to fit a different
/// division of the card is no longer that coordinate. An earlier revision cut
/// the card to 510 × 340, put the band at 60 % and multiplied every y above it
/// by 204/239; that moved 券種名, both 大字 rows, the whole 中字 block and the
/// 集計期間 off the lines the rule names them on.
///
/// ### What a fixed artboard costs
///
/// It cannot reflow, so this card does not answer Dynamic Type — §10.1's
/// 「空间不足时改为纵向」 has nothing to turn vertical, because the layout is a
/// printed 券面 and a ticket does not reset its own type when the reader wants
/// larger text. That is a deliberate exception, and it is paid for twice rather
/// than ignored:
///
///   - **Every figure is an accessibility element with a spoken label and
///     value.** VoiceOver reads 「乗車距離、7,338 キロ」, never a grid of loose
///     numerals. That is the access path for a dense printed card, and it works
///     at any text size.
///   - **Nothing is set in a size that cannot condense.** The four languages
///     set the same field at very different widths, so every string takes
///     `minimumScaleFactor` — allowed here, and only here, because there is no
///     `ViewThatFits` on this card for a self-shrinking candidate to lie to
///     (see `RailType`'s first rule).
///
/// Every other card on the statistics screen keeps the contract in full. This
/// is one card, and it is the one that is a picture.
///
/// ### The rules that are easy to lose
///
///   - **横方向圧縮 0.92**, on every element, never nested. CSS
///     `transform: scaleX()` and SwiftUI `scaleEffect(x:)` are both render
///     transforms that leave layout alone, so this is an exact port — see
///     ``ticketCompressed(_:)``, which exists so that no call site spells the
///     factor and no container can apply it twice.
///   - **純黒 / 純白 のみ**. No greys and no alpha in the type. The ink roles
///     `PassportInk` resolves for stock are exactly this, which is why every
///     `foregroundStyle` here is `ink.title`.
///   - **端まで刷り切る**. The face bleeds to the card's edges — the 44 px
///     margins are inside the ticket and the 色帯 crosses the whole of it —
///     which is also why `PassportTone.feature` is die-cut square.
enum TicketFace {

    // MARK: - the artboard

    /// 「85×57.5mm を同じ 6px/mm で 510×345px に取り」.
    static let width: CGFloat = 510
    static let height: CGFloat = 345
    /// The die-cut's proportion, taken from the artboard rather than rounded
    /// to a ratio: 510 : 345 is 85 × 57.5 mm, and 1.5 : 1 is not.
    static var aspect: CGFloat { width / height }

    /// 色帯 — 「y239–274（高さ 35px、全幅）」.
    static let bandTop: CGFloat = 239
    static let bandHeight: CGFloat = 35
    static var bandBottom: CGFloat { bandTop + bandHeight }

    /// A font's ascent, as a fraction of its size.
    ///
    /// The baselines below are the artboard's `top:` values plus this, which is
    /// what `line-height: 1` resolves to. The PLACEMENT reads `Text`'s own
    /// first baseline (see ``ticketBaseline(_:)``) rather than computing one,
    /// so a face whose ascent is not 0.8 em still sets on these lines rather
    /// than near them — this constant only has to be right about the design.
    static let ascender: CGFloat = 0.8

    /// 全要素に `scaleX(0.92)`。字面を詰めるための横圧縮で、組版位置は動かさない。
    static let compression: CGFloat = 0.92
    /// How far a string may condense before the layout is wrong rather than
    /// tight. Half: a MARS terminal condenses a long station name too.
    static let condense: CGFloat = 0.5

    // MARK: - 字級

    /// 大字 — 乗車距離・乗車時間の数値.
    static let display: CGFloat = 38
    /// その分数値.
    static let displayMinor: CGFloat = 24
    /// 中字 — 四指標の数値, as the artboard nominates it. This is what fixes
    /// the block's two baselines; what the digits are actually SET at is
    /// ``figureSet``.
    static let figure: CGFloat = 23
    /// 小字 — 指標ラベル・大字ラベル・単位. One size for all three, and that is
    /// deliberate: 「小字は全て 18px に統一」 is what makes the block read as a
    /// printed form rather than as a hierarchy.
    static let caption: CGFloat = 18
    /// 集計期間行と最下行の漢字.
    static let line: CGFloat = 16
    /// 集計期間行の数字, as the artboard nominates it — 25 % larger, which is
    /// what fixes that line's baseline. See ``spanNumeralSet`` for the size it
    /// is set at.
    ///
    /// 最下行 takes NO such bump: the issuing line is one run of fine print set
    /// at one size, and a ticket does not strike the date in it larger than the
    /// words beside it.
    static let lineNumeral: CGFloat = 20
    /// 券種名.
    static let kind: CGFloat = 25
    /// 左上の識別文字.
    static let mark: CGFloat = 17

    /// 字間, as fractions of an em.
    ///
    /// Fractions rather than points, because letter-spacing is a property of
    /// the size it is set at.
    enum Tracking {
        static let kind: CGFloat = 0.34
        static let label: CGFloat = 0.06
        static let scope: CGFloat = 0.08
        static let mark: CGFloat = 0.04
        static let figure: CGFloat = 0.01
    }

    // MARK: - 位置 — 券面上部

    /// 左右マージン.
    static let margin: CGFloat = 44
    /// 識別文字の左端 — 42, two pixels outside the margin, because the frame
    /// around it is optically wider than the letters inside it.
    static let markLeft: CGFloat = 42
    static let markPaddingV: CGFloat = 3
    static let markPaddingH: CGFloat = 8
    static let markBorder: CGFloat = 2

    /// 券種名 cx255・y43.
    static let kindCentre: CGFloat = 255
    static let kindBaseline: CGFloat = 43 + kind * ascender

    /// 券種名の下の罫: 126 × 2 px, centred.
    static let kindRuleTop: CGFloat = 79
    static let kindRuleWidth: CGFloat = 126
    static let kindRuleHeight: CGFloat = 2

    /// 大字二欄 — 「cx150 / cx365」, as the two anchors the rule names.
    ///
    /// Anchors rather than columns: two equal columns inside the 44 px margins
    /// centre at 149.5 and 360.5, which is right about the first and four and a
    /// half pixels wrong about the second. The rule gives centres, so these are
    /// centres and ``displayWidths`` is what each is allowed to spread to.
    static let displayCentres: [CGFloat] = [150, 365]
    /// How wide each 大字 column may set before it is condensed — the widest
    /// box that stays centred on its anchor without crossing the margin or the
    /// midpoint between the two.
    static let displayWidths: [CGFloat] = [212, 202]
    /// ラベル y92・数値 y107.
    static let displayLabelBaseline: CGFloat = 92 + caption * ascender
    static let displayValueBaseline: CGFloat = 107 + display * ascender
    /// 大字数値と単位の間隔.
    static let displayGap: CGFloat = 7

    /// 中字四指標は二列 x44 / x290、二段 y158 / y184.
    ///
    /// The columns are 58 : 42 inside the 466 px measure, and they are that
    /// width because 「路線カバー率」 is twice 「会社数」. Equal halves would put
    /// 駅数 under 乗車回数's counter instead of clear of it.
    static let fieldColumns: [CGFloat] = [44, 290]
    static let fieldWidths: [CGFloat] = [246, 176]
    static let fieldFirstBaseline: CGFloat = 158 + figure * ascender
    static let fieldSecondBaseline: CGFloat = 184 + figure * ascender
    /// ラベル・数値・単位の間隔.
    static let fieldGap: CGFloat = 10

    /// 集計期間 x44・y214 — set by its 数字, which are the tallest run on it.
    static let spanBaseline: CGFloat = 214 + lineNumeral * ascender

    // MARK: - 券面上部の水平中線

    /// The one horizontal centreline the head is hung from.
    ///
    /// 「全部地区四个字和 RM 带框应该与乘车记录四个字的水平中线共享一个水平中线」.
    /// The artboard states three separate `top:` values for these three marks
    /// (42/44 for the 識別文字, 43 for the 券種名, 46 for the 集計範囲) and they
    /// agree only for a face whose 漢字 and Latin sit at the same height inside
    /// their em. Unifont's do not, so the three tops resolve to three different
    /// optical centres — the box riding high, the 集計範囲 low.
    ///
    /// So the 券種名 keeps the artboard's own line and the other two are hung
    /// off the centre of its INK rather than off a `top:` of their own.
    static let headCentre: CGFloat =
        kindBaseline + kind * ink.drop - kind * ink.kanji / 2

    /// The baseline that centres `size`-em 漢字 ink on `y`.
    static func baseline(kanji size: CGFloat, centredOn y: CGFloat) -> CGFloat {
        y + size * ink.kanji / 2 - size * ink.drop
    }

    /// 集計範囲 — 右上, centred on ``headCentre``.
    static let scopeBaseline: CGFloat = baseline(kanji: line, centredOn: headCentre)

    // MARK: - 位置 — 色帯の下

    /// 最下行 — 「y296：左に集計日・発行者・端末番号、右に版番号を両端揃え」.
    static let footerBaseline: CGFloat = 296 + line * ascender

    // MARK: - the anchor tables, read safely

    /// The artboard names two 大字 anchors and two 中字 columns and no more, so
    /// a caller that hands over three figures gets the measure rather than a
    /// crash. There is no third anchor to invent: the rule is a printed grid.
    static func displayCentre(_ index: Int) -> CGFloat {
        displayCentres.indices.contains(index) ? displayCentres[index] : width / 2
    }

    static func displayWidth(_ index: Int) -> CGFloat {
        displayWidths.indices.contains(index) ? displayWidths[index] : width - margin * 2
    }

    static func fieldColumn(_ index: Int) -> CGFloat {
        fieldColumns.indices.contains(index) ? fieldColumns[index] : margin
    }

    static func fieldWidth(_ index: Int) -> CGFloat {
        fieldWidths.indices.contains(index) ? fieldWidths[index] : width - margin * 2
    }


    // MARK: - the face's one typeface

    /// GNU Unifont, which is what the design is set in.
    ///
    /// A bitmap face at heart — 16 px per em, one or two 8 px cells per glyph —
    /// and that is the whole reason the design chose it: every 券面 in this
    /// system is imitating a thermal ticket printer, and Unifont's even colour
    /// and fixed pitch are what a thermal head actually produces. It also
    /// covers the whole BMP in one file, so the kanji, the kana and the Latin
    /// on one face come from the same press rather than from three fallbacks at
    /// three different weights.
    ///
    /// Bundled with the app and registered through `UIAppFonts`, because there
    /// is no system font on iOS that is any of those things.
    static let family = "Unifont"

    /// Whether the bundled face is available, having registered it if it was
    /// not already.
    ///
    /// It REGISTERS rather than only asking, because this target generates its
    /// own Info.plist (`GENERATE_INFOPLIST_FILE = YES`) and so has no
    /// `UIAppFonts` array to list the file in. A font that ships in the bundle
    /// unlisted is simply never loaded until something asks CoreText to load
    /// it; this is that ask, and it happens once, the first time a face is set.
    ///
    /// If it fails — a resource that did not copy, a build that dropped the
    /// file — the face falls back to the system's monospaced design. That is
    /// the last entry in the design's own chain (「全文 Unifont（代替 Noto Sans
    /// JP / monospace）」) and it is at least still fixed-pitch, where what
    /// `Font.custom` returns for a name it cannot find is the BODY font, which
    /// is not recognisably a ticket at all.
    static let hasUnifont: Bool = registerUnifont()

    private static func registerUnifont() -> Bool {
        if UIFont(name: family, size: 12) != nil { return true }
        guard let url = Bundle.main.url(forResource: family, withExtension: "otf") else {
            return false
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return UIFont(name: family, size: 12) != nil
    }

    /// One size on the artboard's scale.
    ///
    /// `fixedSize:` rather than `size:relativeTo:` — the artboard is scaled as
    /// a whole by ``TicketFaceCard``, and type that also grew with Dynamic Type
    /// would be scaled twice and leave the grid it is printed on.
    static func font(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        guard hasUnifont else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(family, fixedSize: size).weight(weight)
    }

    // MARK: - 数字 と 漢字 — matched by INK, not by em

    /// What a digit and a full-width 漢字 actually put on the paper, as
    /// fractions of the em, measured from the face that resolved.
    ///
    /// This is the difference between the design's rule and the design's
    /// PICTURE. 「数字を 25 % 大きく」 is written for a face whose figures and
    /// kanji stand at comparable heights; Unifont's do not. Its digits are
    /// 0.625 em of ink sitting exactly on the baseline, and its kanji are a
    /// full em that falls 0.125 em BELOW it — so a digit set 25 % larger than
    /// the kanji beside it renders three quarters of their height, and the row
    /// reads as fine print with small numbers in it rather than as a ticket.
    ///
    /// So the ratio the design states is applied to the INK. A figure asked to
    /// stand 20 % over the 漢字 beside it is given the em that makes its ink
    /// 20 % taller, and then dropped onto their common bottom edge.
    private static let ink: (digit: CGFloat, kanji: CGFloat, drop: CGFloat) = {
        let name = hasUnifont
            ? family
            : UIFont.monospacedSystemFont(ofSize: 100, weight: .medium).fontName
        let face = CTFontCreateWithName(name as CFString, 100, nil)
        func bounds(_ text: String) -> CGRect {
            var chars = Array(text.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: chars.count)
            guard CTFontGetGlyphsForCharacters(face, &chars, &glyphs, chars.count) else {
                return .zero
            }
            return CTFontGetBoundingRectsForGlyphs(face, .default, &glyphs, nil, glyphs.count)
        }
        let digit = bounds("0")
        let kanji = bounds("年")
        // Unifont's own numbers, for a face that reports nothing usable.
        guard digit.height > 0, kanji.height > 0 else { return (0.625, 1, 0.125) }
        return (digit.height / 100, kanji.height / 100, max(0, -kanji.origin.y) / 100)
    }()

    /// The em a numeral needs so its ink stands `ratio` times the ink of
    /// `kanji`-sized 漢字 beside it.
    static func numeralSet(besideKanji kanji: CGFloat, taller ratio: CGFloat) -> CGFloat {
        guard ink.digit > 0 else { return kanji * ratio }
        return kanji * ink.kanji * ratio / ink.digit
    }

    /// How far that numeral is lowered to sit on the 漢字's bottom edge.
    ///
    /// A digit's ink stops at the baseline and a kanji's carries on below it,
    /// so a shared baseline is not a shared bottom. This is the difference, and
    /// it is the whole of what makes the two read as one line of print rather
    /// than as two.
    static func numeralDrop(besideKanji kanji: CGFloat) -> CGFloat { kanji * ink.drop }

    /// 中字四指標のラベルと単位 — 乗車回数 / 駅数 / 路線カバー率 / 会社数 and the
    /// counters beside them.
    ///
    /// The date row's size, not the 大字's label size: 「缩小乘车次数 停靠站
    /// 路线覆盖率 业者数，与下面的日期行字体大小相同」. So the block and the
    /// 集計期間 under it are one system — 漢字 at ``line``, figures 20 % over
    /// them — and ``figureSet`` comes out equal to ``spanNumeralSet``, which is
    /// the point rather than a coincidence.
    static let fieldLabel: CGFloat = line

    /// 中字四指標の数値, set to stand 20 % over that label.
    static let figureSet: CGFloat = numeralSet(besideKanji: fieldLabel, taller: 1.2)
    static let figureDrop: CGFloat = numeralDrop(besideKanji: fieldLabel)

    /// 集計期間行の数字, the same 20 % over the 漢字 of its own sentence.
    static let spanNumeralSet: CGFloat = numeralSet(besideKanji: line, taller: 1.2)
    static let spanNumeralDrop: CGFloat = numeralDrop(besideKanji: line)

    /// 最下行 — 「全部的字体都与上面的日期行的汉字字体大小相同」.
    ///
    /// One em for the whole row, and it is ``line`` itself: the 集計期間 above
    /// sets its 漢字 at 16 and this row matches THAT, not the figures beside it
    /// that stand 20 % over it. So the issuing line takes no bump of any kind —
    /// no larger em for the figures, and no ink compensation either.
    ///
    /// Ink compensation was tried here and is wrong for this row. Raising the
    /// digits to 25.6 em does make their ink equal the kanji's, but Unifont's
    /// digits are 0.375 em wide, so the row came out 1.6 times wider than the
    /// size it was supposed to match and read as the largest print on the card
    /// rather than the smallest. Matching the em is what 「字体大小相同」 asks
    /// for, and on a row of fine print it is also what looks right.
    static let footerSize: CGFloat = line

    /// The app's own version, for the right end of the 最下行 — 「vX.Y.Z」.
    ///
    /// Read from the bundle rather than written down, for the reason
    /// `StatisticsPosterMark` reads the app's NAME from the bundle: a face that
    /// printed a version the app is not would be worse than one that printed
    /// none, and `nil` here simply leaves that end of the row empty.
    static var version: String? {
        guard
            let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String,
            !short.isEmpty
        else { return nil }
        return "v\(short)"
    }
}

extension View {
    /// 横方向圧縮 0.92 — the design's own `scaleX(0.92)`.
    ///
    /// A render transform in both languages, so layout is untouched and the
    /// glyphs simply set 8 % narrower. The anchor follows the element's own
    /// alignment, which is the design's rule spelled as an argument:
    /// 「中央寄せ要素は `translateX(-50%) scaleX(0.92)`、右寄せは
    /// `transform-origin:right center`」.
    ///
    /// Applied to leaves only. 「入れ子で二重にかけない」 — a container that
    /// carried this too would compress its children twice, to 0.85.
    func ticketCompressed(_ anchor: UnitPoint = .leading) -> some View {
        scaleEffect(x: TicketFace.compression, y: 1, anchor: anchor)
    }

    /// Put this element's first baseline on the artboard's line `y`.
    ///
    /// Type is positioned by its baseline on a press and by its bounding box in
    /// SwiftUI, and the difference between the two is a font's ascent — a
    /// property of the FACE, not of the layout. So this reads `Text`'s own
    /// first baseline through the alignment guide rather than subtracting an
    /// assumed one, and the glyphs land on the artboard's lines whichever face
    /// resolves.
    ///
    /// The whole artboard is then framed around it, and that frame is the point
    /// rather than tidiness. A guide that moves a child's `.top` ABOVE its own
    /// origin makes the enclosing `ZStack` grow upward to contain it, and a
    /// stack that has grown upward puts its alignment line one ascent below the
    /// top of the card — which moved every line on this face, the 色帯
    /// included, down by that ascent. Framed to the artboard, each element is
    /// exactly the card's size, the stack is exactly the card's size, and there
    /// is nothing left for it to grow by.
    func ticketBaseline(_ y: CGFloat) -> some View {
        alignmentGuide(.top) { $0[.firstTextBaseline] - y }
            .frame(width: TicketFace.width, height: TicketFace.height, alignment: .topLeading)
    }

    /// Put this element's vertical centre on the artboard's `y` — for the
    /// framed 識別文字, which has no baseline of its own to hang from and is
    /// asked to share the 券種名's centreline.
    func ticketMiddle(_ y: CGFloat) -> some View {
        alignmentGuide(.top) { $0[VerticalAlignment.center] - y }
            .frame(width: TicketFace.width, height: TicketFace.height, alignment: .topLeading)
    }

    /// Put this element's top edge at the artboard's `y` — for the rules and
    /// the 色帯, neither of which has a baseline.
    func ticketTop(_ y: CGFloat) -> some View {
        alignmentGuide(.top) { _ in -y }
            .frame(width: TicketFace.width, height: TicketFace.height, alignment: .topLeading)
    }

    /// Set this element in a box of `width`, centred on the artboard's `x`.
    ///
    /// 「大字二欄 cx150 / cx365」 gives CENTRES, and two equal columns inside
    /// the 44 px margins centre at 149.5 and 360.5 — right about the first and
    /// four and a half pixels wrong about the second. So the anchor is placed
    /// and the box hangs off it, rather than the measure being divided and the
    /// anchors falling where they may.
    ///
    /// The box is bounded because it is what `minimumScaleFactor` condenses
    /// against: an element free to be as wide as its text would never condense,
    /// it would simply run over its neighbour.
    func ticketAnchored(centre x: CGFloat, width: CGFloat) -> some View {
        frame(width: width)
            .offset(x: x - width / 2)
            .frame(width: TicketFace.width, alignment: .leading)
    }

    /// Set this element in a box of `width` whose LEFT edge is the artboard's
    /// `x` — 「中字四指標は二列 x44 / x290」, which the rule gives as edges.
    func ticketAnchored(left x: CGFloat, width: CGFloat) -> some View {
        frame(width: width, alignment: .leading)
            .offset(x: x)
            .frame(width: TicketFace.width, alignment: .leading)
    }

    /// One printed string: condensed rather than wrapped, and never truncated.
    func ticketPrinted() -> some View {
        lineLimit(1).minimumScaleFactor(TicketFace.condense)
    }
}

// MARK: - what a face prints

/// One of the two 大字 figures across the top of the face.
enum TicketDisplay {
    /// 「12,480 KM」 — a figure and its unit.
    case figure(label: String, value: String, unit: String, spoken: String)
    /// 「268 時間 40 分」 — the split組版 a duration is set in, where the hours
    /// are 大字 and the minutes 分数値 at 24 px. The one place on the face a
    /// single value is printed as two, which is why it cannot be a formatted
    /// string handed to the case above.
    case duration(
        label: String, hours: Int, minutes: Int,
        hourUnit: String, minuteUnit: String, spoken: String)

    var label: String {
        switch self {
        case .figure(let label, _, _, _): label
        case .duration(let label, _, _, _, _, _): label
        }
    }

    var spoken: String {
        switch self {
        case .figure(_, _, _, let spoken): spoken
        case .duration(_, _, _, _, _, let spoken): spoken
        }
    }
}

/// One of the four 中字 fields — label, figure and counter on one baseline.
struct TicketField: Identifiable {
    let label: String
    let value: String
    /// The counter, which SOME languages do not have.
    ///
    /// The design prints 「乗車回数 412 回」, and the counter is what tells a
    /// reader that 412 counts rides and not anything else. English has none —
    /// "Rides 412 rides" states the noun twice — so the catalog holds an empty
    /// string for it and nothing is drawn. See `ios.ticket.unit.rides`.
    var unit: String = ""
    let spoken: String

    var id: String { label }
}

// MARK: - the face

/// One ticket, from 券種名 to 最下行, on the artboard.
///
/// Takes the printed CONTENT rather than a `ViewBuilder`: on a fixed grid the
/// caller cannot compose a layout, only fill fields — which is what a ticket
/// terminal does, and what keeps both of this app's faces on one grid instead
/// of two that drifted apart.
struct TicketFaceCard: View {
    @Environment(\.passportInk) private var ink
    @Environment(\.colorScheme) private var colorScheme

    /// 券種名. `Text(verbatim:)` and never localized, for the reason a 乗車券
    /// does not translate its own name: this is what is PRINTED on the stock,
    /// in the same sense that a JR ticket says 乗車券 to a reader who has never
    /// read Japanese.
    let kind: String
    /// 集計範囲 — the region these figures are counted over, in the design's
    /// full-width parentheses. 「（全世界）」「（日本）」.
    let scope: String?
    /// The two 大字 figures, at cx150 and cx365.
    let displays: [TicketDisplay]
    /// The 中字 block — up to four, in two columns of two.
    let fields: [TicketField]
    /// 集計期間 — one sentence, already composed, its figures set 25 % larger
    /// than its kanji.
    let span: String?
    /// 最下行の左: 集計日 and the issuer.
    let issued: String

    var body: some View {
        // One artboard, scaled by one factor to whatever width the card has.
        // `.topLeading` on both the scale and the frame, so the artboard's
        // origin is the card's origin and every constant in `TicketFace` is a
        // coordinate rather than an offset from a centre.
        GeometryReader { proxy in
            artboard
                .frame(width: TicketFace.width, height: TicketFace.height)
                .scaleEffect(proxy.size.width / TicketFace.width, anchor: .topLeading)
        }
        .aspectRatio(TicketFace.aspect, contentMode: .fit)
        .accessibilityElement(children: .contain)
    }

    private var artboard: some View {
        ZStack(alignment: .topLeading) {
            // 色帯 first, so everything else prints OVER it rather than under:
            // the band is stock, not a panel.
            Rectangle()
                .fill(TicketPalette.band(onDarkStock: colorScheme == .dark))
                .frame(width: TicketFace.width, height: TicketFace.bandHeight)
                .ticketTop(TicketFace.bandTop)
                .accessibilityHidden(true)

            head
            displayRow
            fieldRows
            spanLine
            footer
        }
        .frame(width: TicketFace.width, height: TicketFace.height, alignment: .topLeading)
        .clipped()
    }

    // MARK: 券種名, 罫, 識別文字, 集計範囲

    @ViewBuilder private var head: some View {
        Text(verbatim: kind)
            .font(TicketFace.font(TicketFace.kind, weight: .semibold))
            .tracking(TicketFace.kind * TicketFace.Tracking.kind)
            // `tracking` puts a space after the LAST glyph too, so the block
            // sits half a letter-space left of true centre. The artboard
            // compensates with `padding-left:0.34em`; so does this.
            .padding(.leading, TicketFace.kind * TicketFace.Tracking.kind)
            .foregroundStyle(ink.title)
            .ticketPrinted()
            .ticketCompressed(.center)
            .frame(width: TicketFace.width)
            .ticketBaseline(TicketFace.kindBaseline)
            .accessibilityAddTraits(.isHeader)

        Rectangle()
            .fill(ink.title)
            .frame(width: TicketFace.kindRuleWidth, height: TicketFace.kindRuleHeight)
            .frame(width: TicketFace.width)
            .ticketTop(TicketFace.kindRuleTop)
            .accessibilityHidden(true)

        // 「RM」 in its 2 px frame — the issuer's 識別文字, which on a real
        // ticket is the two characters of whoever printed it (東C, 名ハ).
        // Verbatim for the same reason `kind` is.
        Text(verbatim: "RM")
            .font(TicketFace.font(TicketFace.mark))
            .tracking(TicketFace.mark * TicketFace.Tracking.mark)
            .foregroundStyle(ink.title)
            .ticketCompressed()
            .padding(.vertical, TicketFace.markPaddingV)
            .padding(.horizontal, TicketFace.markPaddingH)
            .overlay {
                Rectangle().strokeBorder(ink.title, lineWidth: TicketFace.markBorder)
            }
            .padding(.leading, TicketFace.markLeft)
            .frame(width: TicketFace.width, alignment: .leading)
            .ticketMiddle(TicketFace.headCentre)
            .accessibilityHidden(true)

        if let scope {
            Text(verbatim: "（\(scope)）")
                .font(TicketFace.font(TicketFace.line))
                .tracking(TicketFace.line * TicketFace.Tracking.scope)
                .foregroundStyle(ink.title)
                .ticketPrinted()
                .ticketCompressed(.trailing)
                .padding(.trailing, TicketFace.margin)
                .frame(width: TicketFace.width, alignment: .trailing)
                .ticketBaseline(TicketFace.scopeBaseline)
        }
    }

    // MARK: 大字二欄

    /// The labels and the figures are two absolutely-placed rows, because that
    /// is how the artboard sets them: `top:92` and `top:107` are separate
    /// declarations, and the distance between them is not a stack's spacing.
    ///
    /// So the FIGURE carries the accessibility for the pair — its label is the
    /// field's name, its value is the whole thing spoken — and the printed
    /// label above it is hidden. One element per figure, read the way a person
    /// would say it, rather than three loose runs read left to right.
    /// Four leaves, spelled flat rather than looped.
    ///
    /// Every element of this face is a SIBLING of the ZStack, because that is
    /// what makes ``ticketBaseline(_:)`` work: the guide it sets is read by the
    /// stack that aligns it, so a `ForEach` in between gathers its iterations
    /// into one child and the stack then sees ONE guide for the pair. Looped,
    /// the labels and the figures shared a single baseline and both 大字
    /// columns printed over the 集計期間 near the foot of the card.
    @ViewBuilder private var displayRow: some View {
        displayLabel(0)
        displayLabel(1)
        displayFigure(0)
        displayFigure(1)
    }

    @ViewBuilder private func displayLabel(_ index: Int) -> some View {
        if displays.indices.contains(index) {
            Text(displays[index].label)
                .font(TicketFace.font(TicketFace.caption))
                .tracking(TicketFace.caption * TicketFace.Tracking.label)
                .foregroundStyle(ink.title)
                .ticketPrinted()
                .ticketCompressed(.center)
                .ticketAnchored(
                    centre: TicketFace.displayCentre(index),
                    width: TicketFace.displayWidth(index))
                .ticketBaseline(TicketFace.displayLabelBaseline)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func displayFigure(_ index: Int) -> some View {
        if displays.indices.contains(index) {
            let display = displays[index]
            displayValue(display)
                .ticketAnchored(
                    centre: TicketFace.displayCentre(index),
                    width: TicketFace.displayWidth(index))
                .ticketBaseline(TicketFace.displayValueBaseline)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(display.label))
                .accessibilityValue(Text(display.spoken))
        }
    }

    private func displayValue(_ display: TicketDisplay) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TicketFace.displayGap) {
            switch display {
            case .figure(_, let value, let unit, _):
                bigFigure(value)
                unitText(unit)
            case .duration(_, let hours, let minutes, let hourUnit, let minuteUnit, _):
                if hours > 0 {
                    bigFigure(hours.formatted())
                    unitText(hourUnit)
                    bigFigure(minutes.formatted(), size: TicketFace.displayMinor)
                } else {
                    // Under an hour the minutes ARE the headline, which is what
                    // `StatisticsFormat.duration` does with the same figure.
                    bigFigure(minutes.formatted())
                }
                unitText(minuteUnit)
            }
        }
        .ticketPrinted()
    }

    private func bigFigure(_ text: String, size: CGFloat = TicketFace.display) -> some View {
        Text(text)
            .font(TicketFace.font(size, weight: .semibold))
            .tracking(size * TicketFace.Tracking.figure)
            .foregroundStyle(ink.title)
            .ticketCompressed()
            // Inert unless the change arrives inside an animated transaction,
            // and these land from an async store that has none — so the token
            // is spelled here. §9.4 keeps numeric updates out of
            // `RailMotion.animation`'s Reduce Motion path on purpose.
            .contentTransition(.numericText())
            .animation(RailMotion.replace, value: text)
    }

    @ViewBuilder private func unitText(
        _ text: String, size: CGFloat = TicketFace.caption
    ) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(TicketFace.font(size, weight: .semibold))
                .foregroundStyle(ink.title)
                .ticketCompressed()
        }
    }

    // MARK: 中字四指標

    /// The artboard's columns are 58 : 42 (x44 and x290 inside a 466 px
    /// measure), and they are that width because 「路線カバー率」 is twice
    /// 「会社数」. That split is kept: equal halves would put 駅数 under
    /// 乗車回数's counter instead of clear of it.
    @ViewBuilder private var fieldRows: some View {
        cell(0, column: 0, baseline: TicketFace.fieldFirstBaseline)
        cell(1, column: 1, baseline: TicketFace.fieldFirstBaseline)
        cell(2, column: 0, baseline: TicketFace.fieldSecondBaseline)
        cell(3, column: 1, baseline: TicketFace.fieldSecondBaseline)
    }

    /// One cell of the block, on its own column edge and on the artboard's own
    /// baseline.
    ///
    /// Placed rather than stacked. An `HStack` would share ONE baseline between
    /// the pair, which is the same answer only for as long as both cells set at
    /// the same size — and 「路線カバー率 38.6 ％」 beside 「会社数 74 社」 is
    /// exactly the pair that stops being true of when one of them condenses.
    private func cell(_ index: Int, column: Int, baseline: CGFloat) -> some View {
        field(at: index)
            .ticketAnchored(
                left: TicketFace.fieldColumn(column),
                width: TicketFace.fieldWidth(column))
            .ticketBaseline(baseline)
    }

    @ViewBuilder private func field(at index: Int) -> some View {
        if fields.indices.contains(index) {
            let field = fields[index]
            HStack(alignment: .firstTextBaseline, spacing: TicketFace.fieldGap) {
                Text(field.label)
                    .font(TicketFace.font(TicketFace.fieldLabel))
                    .tracking(TicketFace.fieldLabel * TicketFace.Tracking.label)
                    .foregroundStyle(ink.title)
                    .ticketCompressed()
                Text(field.value)
                    .font(TicketFace.font(TicketFace.figureSet, weight: .semibold))
                    .foregroundStyle(ink.title)
                    .ticketCompressed()
                    // 「数字也需要比汉字高 20 %（底部对齐）」. The size above makes
                    // the ink 20 % taller than the label's; this puts the two
                    // on one bottom edge, which a shared baseline does not —
                    // the digit's ink stops at the baseline and the label's
                    // 漢字 carries 0.125 em below it.
                    .alignmentGuide(.firstTextBaseline) {
                        $0[.firstTextBaseline] - TicketFace.figureDrop
                    }
                    .contentTransition(.numericText())
                    .animation(RailMotion.replace, value: field.value)
                unitText(field.unit, size: TicketFace.fieldLabel)
            }
            .ticketPrinted()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(field.label))
            .accessibilityValue(Text(field.spoken))
        }
    }

    // MARK: 集計期間 と 最下行

    @ViewBuilder private var spanLine: some View {
        if let span {
            sentence(
                span, alignment: .leading,
                narrow: TicketFace.spanNumeralSet, drop: TicketFace.spanNumeralDrop)
                .padding(.leading, TicketFace.margin)
                .frame(width: TicketFace.width, alignment: .leading)
                .ticketBaseline(TicketFace.spanBaseline)
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: TicketFace.fieldGap) {
            // 最下行 is one size throughout — 「最底下那一行文字大小需要相同」.
            sentence(issued, alignment: .leading, narrow: TicketFace.footerSize, drop: 0)
            Spacer(minLength: TicketFace.fieldGap)
            if let version = TicketFace.version {
                sentence(
                    version, alignment: .trailing,
                    narrow: TicketFace.footerSize, drop: 0)
            }
        }
        .padding(.horizontal, TicketFace.margin)
        .frame(width: TicketFace.width)
        .ticketBaseline(TicketFace.footerBaseline)
    }

    /// 集計期間行と最下行 — 「漢字 16 px、数字 20 px（数字を 25 % 大きく）」.
    ///
    /// The design states that about two specific rows, but it is really a rule
    /// about a printed SENTENCE: on a ticket the figures inside a line of prose
    /// are struck larger so they can be read at a glance out of what is
    /// otherwise fine print. So it is applied by finding the figures rather
    /// than by the caller splitting the sentence up — which also means it holds
    /// in all four languages, whatever order they put their numbers in.
    private func sentence(
        _ text: String, alignment: HorizontalAlignment, narrow: CGFloat, drop: CGFloat
    ) -> some View {
        Text(TicketFaceCard.typeset(text, narrow: narrow, drop: drop))
            .foregroundStyle(ink.title)
            .ticketPrinted()
            .ticketCompressed(alignment == .trailing ? .trailing : .leading)
    }

    /// The sentence, with its figures raised to `lineNumeral` and everything
    /// else left at `line`.
    ///
    /// A run counts as a figure when it is made of digits and the punctuation
    /// that belongs INSIDE a number — the group separator, the decimal point,
    /// and the half-width dash a ticket prints in place of a leading zero
    /// (「2026.-3.31」). A run of that punctuation with no digit in it is not a
    /// figure, so it stays at the kanji size and the sentence does not develop
    /// a large full stop.
    /// Split by WIDTH CLASS rather than by "is it a digit".
    ///
    /// 「RAILMAP」 is neither 漢字 nor a figure, and Unifont sets Latin caps on
    /// exactly the digits' 0.625 em of ink — so a rule that only lifted the
    /// numbers left the issuer's name short, and 「2026.-8.29 RAILMAP 發行」 came
    /// out in three heights on a row the design sets in one. Everything that is
    /// not full-width shares one ink and therefore one size.
    static func typeset(_ text: String, narrow: CGFloat, drop: CGFloat) -> AttributedString {
        var out = AttributedString()
        for run in runs(of: text) {
            var piece = AttributedString(run.text)
            piece.font = TicketFace.font(run.isWide ? TicketFace.line : narrow)
            // Negative lowers. One Text, so this moves the run against the 漢字
            // around it rather than against a stack's shared guide.
            if !run.isWide, drop != 0 { piece.baselineOffset = -drop }
            out.append(piece)
        }
        return out
    }

    /// Whether a character is set on a full em — 漢字, kana and the full-width
    /// forms — as against the Latin, digits and punctuation that share the
    /// narrower ink.
    private static func isWide(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first?.value else { return false }
        switch scalar {
        case 0x2E80...0x303F, 0x3040...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
            0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF01...0xFF60, 0xFFE0...0xFFE6:
            return true
        default:
            return false
        }
    }

    private struct Run {
        var text: String
        var isWide: Bool
    }

    private static func runs(of text: String) -> [Run] {
        var runs: [Run] = []
        for character in text {
            let wide = isWide(character)
            if var last = runs.last, last.isWide == wide {
                last.text.append(character)
                runs[runs.count - 1] = last
            } else {
                runs.append(Run(text: String(character), isWide: wide))
            }
        }
        return runs
    }
}
