import RailCore
import RailPresentation
import SwiftUI

// MARK: - card chrome

extension View {
    /// One ordinary content card: §6.4's card radius on a system surface, one
    /// visual step above the panel so the group remains identifiable.
    ///
    /// The surface itself is spelled once, in ``PassportTone/plain``. The
    /// statistics screen now draws three tones of card (§6.1's Memory
    /// personality — see `PassportCardStyle.swift`), and two surfaces that
    /// agree only by coincidence are two that disagree after the next edit.
    /// Every non-statistics card in the Passport workspace keeps calling this
    /// name and keeps getting exactly the card it had.
    func statisticsCard() -> some View {
        passportCard(.plain)
    }
}

// MARK: - §7.8 ProgressSummary

/// What is being computed, how far it has got, and whether the reader has to
/// wait for it.
///
/// §13.2: this is only ever mounted once the work has been running for about
/// 400 ms, so a fast recompute does not flash a spinner. The caller owns that
/// delay because it also owns the answer this replaces.
struct StatisticsProgressSummary: View {
    @Environment(AppLocalization.self) private var localization
    let progress: MileageStatisticsStore.Progress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(localization.statsText("ios.stats.calculating"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            Text(localization.statsText(progress.stage.localizationKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let completed = progress.completed, let total = progress.total, total > 0 {
                ProgressView(value: Double(min(completed, total)), total: Double(total))
                Text(countLabel(completed: completed, total: total))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if progress.interactionContinues {
                Text(localization.statsText("ios.stats.keepUsing"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .statisticsCard()
        .accessibilityElement(children: .combine)
    }

    private func countLabel(completed: Int, total: Int) -> String {
        localization.statsText(
            "ios.stats.matchedOf",
            params: ["done": .number(Double(completed)), "total": .number(Double(total))])
    }
}

// MARK: - the one bar the whole panel is drawn with

/// A labelled proportion bar.
///
/// §5.7 and §6.2: the fill is the tint role, never the positive/green one — a
/// large number is not a success state. §10.2: the figure is always spelled
/// out next to the bar, and the whole row reads to VoiceOver as one sentence
/// carrying the same numbers, so the chart is never the only place a value
/// exists.
struct StatisticsBar: View {
    /// Which paper this bar is being drawn on.
    ///
    /// It used to read `Color.accentColor` over `Color.secondary` directly,
    /// which agreed with the ink roles only by coincidence — the accent WAS
    /// ``PassportInk/fill`` at the time. It is not any more (`TicketPalette`),
    /// and the coincidence would have shown as a blue bar in a row of orange
    /// ones the moment a soft card carried both this and a ranked row. Every
    /// proportion on this screen now comes out of the same two roles.
    @Environment(\.passportInk) private var ink
    let label: String
    /// The number shown at the trailing edge of the head row.
    let value: String
    /// The line under the bar — usually "ridden / total km".
    var detail: String?
    /// 0…1.
    let fraction: Double
    /// The whole row, spoken.
    let spoken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(ink.title)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ink.title)
            }
            GeometryReader { geometry in
                Capsule()
                    .fill(ink.track)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(ink.fill)
                            .frame(width: geometry.size.width * clamped)
                    }
            }
            .frame(height: 7)
            // The bar and the figure above it are one statement, so they move
            // on one clock. The figures on this screen already roll — Passport's
            // metrics carry `contentTransition(.numericText())` on the same
            // `replace` token — and a bar that jumped while its own number
            // rolled was two clocks inside one card.
            //
            // Not degraded under Reduce Motion, for the reason §9.4 keeps
            // numeric updates: this is a value changing, not a thing moving
            // across the screen, and the width IS the value.
            .animation(RailMotion.replace, value: clamped)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(ink.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spoken))
    }

    private var clamped: CGFloat {
        guard fraction.isFinite else { return 0 }
        return CGFloat(min(max(fraction, 0), 1))
    }
}

// MARK: - metric row

/// One label and one figure, on a row.
///
/// Takes `metricValueStacked` rather than `metricValue`: nothing below this
/// re-lays it out, so the figure has to be allowed to wrap inside the card
/// rather than state a width the card cannot give it. (`metricValue` exists
/// for the opposite case — a `ViewThatFits` candidate, which has to state its
/// TRUE width or the arrangements below it are never reached. See `RailType`.)
struct StatisticsMetricRow: View {
    /// The same reason ``StatisticsBar`` reads the ink: the semantic roles and
    /// the passport's own agree on a soft card and nowhere else, and a
    /// component on this screen should not be the one that finds that out.
    @Environment(\.passportInk) private var ink
    let label: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(ink.title)
                .railType(.metricValueStacked)
        } label: {
            Text(label)
                .foregroundStyle(ink.caption)
                .railType(.metricLabel)
        }
    }
}

// MARK: - a distribution, as columns

/// The reference's "FLIGHTS PER Year / Month / Weekday" — one bucket per
/// column, counted.
///
/// ## Why the count is printed on every column instead of drawn on an axis
///
/// The reference puts a 0–4 scale down the left edge and leaves the columns
/// bare, which is the right trade when a chart has forty bars and no room for
/// forty numbers. This one has at most twelve, and §10.2 asks for the figure
/// beside the chart rather than only in it — so each column carries its own,
/// and the card needs no axis, no gridlines and no gutter. The figure is then
/// exact rather than estimated off a rule, which is what a passport wants.
///
/// ## And why it stops being columns at accessibility sizes
///
/// Twelve columns share the card's width. At `.accessibility3` a two-character
/// label under each one no longer fits, and the honest answers are to truncate
/// (which §10.1 rules out), to scale the text down (same), or to change the
/// arrangement. So above the accessibility threshold the same buckets are
/// drawn as ``StatisticsBar`` rows — the component this screen already ranks
/// everything else with — carrying identical numbers in the identical order.
struct StatisticsColumnChart: View {
    struct Column: Identifiable {
        let id: Int
        /// The axis label — as short as the bucket can be named: `26`, `7`,
        /// `Mon`. Twelve of these share the card's width.
        let label: String
        /// The same bucket said in full — `2026`, `July`, `Monday`. What
        /// VoiceOver reads, and what the row form uses once there is room for
        /// it, because "7" is not a thing anyone can hear.
        let name: String
        let count: Int
        /// The whole column, spoken.
        let spoken: String
    }

    @Environment(\.passportInk) private var ink
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The plot's own height. Scaled, so the chart grows with the text under
    /// it rather than becoming a strip between two large labels.
    @ScaledMetric(relativeTo: .caption) private var plotHeight: CGFloat = 118
    /// How wide a bar may get. A column's LANE is a twelfth of the card, and a
    /// bar that filled its lane would make a seven-column chart read as a
    /// solid block — so a weekday bar is capped at the width a month bar
    /// happens to have, and the two charts look like the same chart.
    @ScaledMetric(relativeTo: .caption) private var barWidth: CGFloat = 22

    let columns: [Column]
    /// What a row says instead of a bare number once the chart is a list.
    let rowValue: (Column) -> String

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                ForEach(columns.filter { $0.count > 0 }) { column in
                    StatisticsBar(
                        label: column.name,
                        value: rowValue(column),
                        fraction: fraction(column),
                        spoken: column.spoken)
                }
            }
        } else {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(columns) { column in cell(column) }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func cell(_ column: Column) -> some View {
        VStack(spacing: 5) {
            Text(column.count > 0 ? column.count.formatted() : " ")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ink.caption)
                .lineLimit(1)
            ZStack(alignment: .bottom) {
                // The column's own lane, so every bar is measured against the
                // same height whether or not it has anything in it.
                Color.clear.frame(height: plotHeight)
                Capsule()
                    .fill(column.count > 0 ? ink.fill : ink.track)
                    // An empty bucket keeps a hairline rather than vanishing:
                    // a missing column reads as a missing day, and 0 is an
                    // answer (§5.7's reason for `--` over `0 km`, from the
                    // other side).
                    .frame(maxWidth: barWidth)
                    .frame(height: max(2, plotHeight * fraction(column)))
                    // One clock with the figure above it, exactly as
                    // ``StatisticsBar``: the height IS the number, so it is
                    // not degraded under Reduce Motion either.
                    .animation(RailMotion.replace, value: fraction(column))
            }
            Text(column.label)
                .font(.caption2)
                .foregroundStyle(ink.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(column.name))
        .accessibilityValue(Text(column.spoken))
    }

    private var peak: Int { columns.map(\.count).max() ?? 0 }

    private func fraction(_ column: Column) -> CGFloat {
        guard peak > 0 else { return 0 }
        return CGFloat(min(max(Double(column.count) / Double(peak), 0), 1))
    }
}

// MARK: - a ranked row

/// One row of the reference's ranked lists — Top Airlines, Top Routes, Top
/// Visited Airports — and of the scale comparisons under the distance total.
///
/// Inline at ordinary text sizes, because eight of these read as a chart only
/// when the bars share a left edge. Above the accessibility threshold it is
/// ``StatisticsBar`` instead, for the reason ``StatisticsColumnChart`` gives:
/// a fixed label gutter beside a bar beside a figure has three columns to fit
/// and no arrangement that fits them all at `.accessibility5`.
struct StatisticsRankedRow: View {
    /// Where the name goes.
    ///
    /// The reference can keep every ranked row inline because an airport is
    /// three letters. A station is 「三島（みしま）」 and a ROUTE is two of
    /// them with an arrow between, which in a fixed gutter wraps to three
    /// lines and breaks inside a reading's own brackets. So a list whose names
    /// are that long asks for ``stacked`` and gets the card's full width for
    /// the name, with the bar under it — which is ``StatisticsBar``, the shape
    /// this screen has always drawn a long-labelled proportion in.
    enum Layout {
        case inline
        case stacked
    }

    @Environment(\.passportInk) private var ink
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The label gutter. Scaled rather than fixed, so the name still has room
    /// on the way up to the threshold where the row changes shape entirely.
    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 92
    @ScaledMetric(relativeTo: .caption) private var valueWidth: CGFloat = 44

    let label: String
    /// The glyph a scale row is drawn with.
    var systemImage: String?
    /// A character that stands for the row — a passport's own stamp, which
    /// here is a region's flag. Decoration, and hidden from VoiceOver: the
    /// name is right beside it, and 「🇯🇵 日本」 read aloud is the country
    /// twice.
    var emblem: String?
    /// The line under the name — an operator, a second reading, a count.
    var caption: String?
    let value: String
    /// 0…1.
    let fraction: Double
    /// The whole row, spoken.
    let spoken: String
    var layout: Layout = .inline

    var body: some View {
        Group {
            if layout == .stacked || dynamicTypeSize.isAccessibilitySize {
                StatisticsBar(
                    label: label, value: value, detail: caption,
                    fraction: fraction, spoken: spoken)
            } else {
                inline
            }
        }
    }

    private var inline: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(ink.eyebrow)
                        .accessibilityHidden(true)
                }
                if let emblem {
                    Text(emblem)
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ink.title)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption {
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(ink.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(width: labelWidth, alignment: .leading)
            GeometryReader { geometry in
                Capsule()
                    .fill(ink.track)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(ink.fill)
                            .frame(width: geometry.size.width * clamped)
                    }
            }
            .frame(height: 8)
            // The bar and the figure beside it on one clock, and neither
            // degraded under Reduce Motion — ``StatisticsBar`` above carries
            // the argument: §9.4 keeps progress and numeric updates, because
            // the width IS the value and the figure changing IS the
            // information. Repeated rather than referenced because a raw
            // `RailMotion` token is what an audit greps for.
            .animation(RailMotion.replace, value: clamped)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ink.title)
                .lineLimit(1)
                .frame(minWidth: valueWidth, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(RailMotion.replace, value: value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spoken))
    }

    private var clamped: CGFloat {
        guard fraction.isFinite else { return 0 }
        return CGFloat(min(max(fraction, 0), 1))
    }
}

// MARK: - a ranked list, with the rest of it folded away

/// The reference's ranked lists and their "Show More" — the leading rows, and
/// a disclosure holding whatever else there is.
///
/// The bars are a share of the LEADING row rather than of the total, which is
/// what makes a list of ones read as a list of ones: eight equal rows at full
/// width say "all the same", where eight rows at an eighth each would say
/// nothing at all. The figure beside every bar is the real number (§10.2), so
/// the normalisation cannot mislead — it only decides how wide the ink is.
struct StatisticsRankedList: View {
    /// A share image shows the rows it can show and stops there — a collapsed
    /// disclosure in a picture is a control that cannot be opened.
    @Environment(\.passportPoster) private var isPoster

    struct Row: Identifiable {
        let id: String
        let label: String
        var caption: String?
        let value: String
        /// What the bar is drawn from — a count, or a distance.
        let magnitude: Double
        let spoken: String
    }

    let rows: [Row]
    /// How many are shown before the disclosure. The reference shows eight.
    var visible: Int = 8
    /// The disclosure's own label, already counted and translated.
    let moreLabel: String
    /// Inline unless the names are long enough to need the width — see
    /// ``StatisticsRankedRow/Layout``.
    var layout: StatisticsRankedRow.Layout = .inline

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(rows.prefix(visible)) { row in bar(row) }
            if rows.count > visible, !isPoster {
                DisclosureGroup {
                    VStack(spacing: rowSpacing) {
                        ForEach(rows.dropFirst(visible)) { row in bar(row) }
                    }
                    .padding(.top, rowSpacing)
                } label: {
                    Text(moreLabel)
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private func bar(_ row: Row) -> some View {
        StatisticsRankedRow(
            label: row.label,
            caption: row.caption,
            value: row.value,
            fraction: peak > 0 ? row.magnitude / peak : 0,
            spoken: row.spoken,
            layout: layout)
    }

    /// A stacked row is three lines tall, so it needs the gap a one-line row
    /// does not: at 10 points the name of the next row sits closer to the bar
    /// above it than to its own.
    private var rowSpacing: CGFloat { layout == .stacked ? 16 : 10 }

    private var peak: Double {
        let top = rows.map(\.magnitude).max() ?? 0
        return top.isFinite ? top : 0
    }
}

// MARK: - a superlative

/// The reference's "Shortest flight" / "Longest flight" — one journey, named,
/// with the figure it won on.
///
/// ## Why it is the journey row rather than two lines of text
///
/// It used to be a bespoke block: the two endpoints in `subheadline`, the
/// train and the day in `caption2`, the figure on the right. Every one of
/// those strings was already a thing the app knows how to draw a journey with,
/// and drawing them again here meant a journey looked like a journey
/// everywhere except on the one screen that is about journeys — no operator
/// mark, no service badge, no route line, and no way in.
///
/// So it quotes ``JourneySummaryRow`` — the same row All Journeys is read
/// through, in ``JourneySummaryRow/Surface/inherited`` so that this card
/// supplies the surface (§6.4) and the row supplies the journey.
///
/// ## What the eyebrow and the figure still carry
///
/// The row names the JOURNEY; the line above it names the MEASUREMENT. They
/// are not the same statement, and one case makes that visible: the figure is
/// the distance or the time of the stretch the record says was **ridden**,
/// while the row's title is the journey's own endpoints. On a journey ridden
/// end to end those are the same two stations; on one where only part was
/// confirmed they are not, and the honest thing is to keep both — the number
/// is what won, the row is what it belongs to.
///
/// ## Tapping
///
/// `open` is the journey's detail (§3.1's L4), which is a sheet and therefore
/// reachable from Passport — this screen has no journey panel of its own to
/// hand a selection to, and §5.3's note on the removed 乘車記録 list is why:
/// the log lives one tab away. `nil` on the share image, where a control that
/// cannot be pressed is furniture (``SwiftUI/EnvironmentValues/passportPoster``).
struct StatisticsSuperlative: View {
    /// The journey this row is about, and the surface state §11.2 resolved for
    /// it.
    ///
    /// Carried together because they are meaningless apart, and OPTIONAL
    /// because the two halves of this screen do not update in one step: the
    /// per-journey grouping arrives from `MileageStatisticsStore` while the
    /// working set is being replaced, so for a frame after an edit a
    /// superlative can name a journey the store no longer holds. Without the
    /// journey the row falls back to the two lines of text it always drew,
    /// which keeps the card the same height rather than dropping a row out of
    /// the middle of it.
    struct Ride {
        var train: Train
        var presentation: JourneyPresentation
    }

    @Environment(\.passportInk) private var ink
    let eyebrow: String
    /// The two endpoints, already through the readings table — the fallback
    /// title, and what VoiceOver reads either way.
    let title: String
    /// The train, and the day.
    let detail: String
    let value: String
    /// The whole block, spoken.
    let spoken: String
    var ride: Ride?
    /// Open this journey. `nil` makes the block inert.
    var open: (() -> Void)?

    var body: some View {
        if let open {
            Button(action: open) { block }
                // §14.3: the row this screen is tapped through gives something
                // back before the sheet arrives. `.plain` alone draws nothing
                // inside a card.
                .buttonStyle(RailRowPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
        } else {
            block
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(eyebrow))
                .accessibilityValue(Text(spoken))
        }
    }

    private var block: some View {
        VStack(alignment: .leading, spacing: ride == nil ? 4 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                PassportEyebrow(eyebrow)
                Spacer(minLength: 8)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(ink.title)
                    .railType(.metricValueStacked)
            }
            if let ride {
                JourneySummaryRow(
                    train: ride.train,
                    presentation: ride.presentation,
                    // Passport selects nothing: the selection is the map's and
                    // the journeys panel's, and a row here that drew itself as
                    // selected would be reporting a state this screen has no
                    // way to enter or leave.
                    isSelected: false,
                    showsDate: true,
                    surface: .inherited)
            } else {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink.title)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(ink.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passportBlock()
    }
}
