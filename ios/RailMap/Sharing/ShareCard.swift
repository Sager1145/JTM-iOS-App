import RailCore
import RailPresentation
import SwiftUI

// MARK: - shape and look

/// The card's fixed design canvas. The preview draws it scaled to the screen;
/// the export renders it at 3× (1080 px wide).
enum ShareCardAspect: String, CaseIterable, Identifiable {
    case story, portrait, square
    var id: String { rawValue }

    var size: CGSize {
        switch self {
        case .story: CGSize(width: 360, height: 640)
        case .portrait: CGSize(width: 360, height: 450)
        case .square: CGSize(width: 360, height: 360)
        }
    }

    var localizationKey: String { "ios.share.aspect." + rawValue }

    /// How tall the route map is on this shape.
    var mapHeight: CGFloat {
        switch self {
        case .story: 210
        case .portrait: 130
        case .square: 96
        }
    }


    static let exportScale: CGFloat = 3
}

enum ShareStopsMode: String, CaseIterable, Identifiable {
    case key, all
    var id: String { rawValue }
    var localizationKey: String { "ios.share.stops." + rawValue }
}

// MARK: - content

/// Everything a card prints, already formatted. Built once per scope and
/// option change by ``ShareCardBuilder``; the view only lays it out.
struct ShareCardContent {
    struct Fact: Identifiable {
        let id: String
        let value: String
        let label: String
    }

    struct Row: Identifiable {
        let id: String
        let leading: String
        let title: String
        let trailing: String?
        let emphasised: Bool
    }

    struct Bar: Identifiable {
        let id: String
        let label: String
        let value: String
        let fraction: Double
    }

    enum Body {
        case journey(origin: String, departure: String?, destination: String, arrival: String?)
        case list
        case statistics(hero: String, heroUnit: String, heroCaption: String,
                        months: [Bar], busiestMonth: String?, operators: [Bar])
    }

    var accentHex: String?
    var eyebrow: String
    var title: String
    var subtitle: String?
    var body: Body
    var facts: [Fact]
    var rows: [Row]
    var rowsHeading: String?
    /// Every line the card stands for, for VoiceOver and the share text.
    var spokenText: String
}

// MARK: - the card

/// The one share renderer. Preview and export draw this same view, so they
/// cannot disagree. Text uses fixed sizes: it is a picture, not reading UI.
struct ShareCardView: View {
    let content: ShareCardContent
    let aspect: ShareCardAspect
    let mapImage: UIImage?
    let footer: String
    let showsMap: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        content.accentHex.flatMap { UIColor(railHex: $0) }.map(Color.init) ?? Color(red: 0.85, green: 0.21, blue: 0.31)
    }
    private var paper: Color { colorScheme == .dark ? Color(white: 0.09) : .white }
    private var ink: Color { colorScheme == .dark ? .white : Color(red: 0.08, green: 0.1, blue: 0.13) }
    private var muted: Color { ink.opacity(0.58) }
    private var well: Color { ink.opacity(colorScheme == .dark ? 0.09 : 0.05) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            accent.frame(height: 8)
            VStack(alignment: .leading, spacing: aspect == .square ? 10 : 14) {
                header
                hero
                if !content.facts.isEmpty { factsRow }
                if showsMap { map }
                // The flexible part: whatever room is left, filled with as
                // much detail as fits whole — never a row cut at the edge.
                Group {
                    if case .statistics(_, _, _, let months, let busiest, let operators) = content.body {
                        ViewThatFits(in: .vertical) {
                            statisticsDetail(months: months, busiest: busiest, operators: operators)
                            statisticsDetail(months: months, busiest: busiest, operators: [])
                            Color.clear.frame(height: 0)
                        }
                    } else if !content.rows.isEmpty {
                        ViewThatFits(in: .vertical) {
                            rowsList(limit: 14)
                            rowsList(limit: 10)
                            rowsList(limit: 7)
                            rowsList(limit: 5)
                            rowsList(limit: 3)
                            rowsList(limit: 1)
                            Color.clear.frame(height: 0)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                footerRow
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .frame(width: aspect.size.width, height: aspect.size.height, alignment: .topLeading)
        .background(paper)
        .foregroundStyle(ink)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.eyebrow.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(accent)
                .lineLimit(1)
            Text(content.title)
                .font(.system(size: aspect == .square ? 22 : 26, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let subtitle = content.subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    @ViewBuilder private var hero: some View {
        switch content.body {
        case let .journey(origin, departure, destination, arrival):
            HStack(alignment: .top, spacing: 10) {
                endpoint(origin, time: departure, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.top, departure == nil ? 4 : 22)
                endpoint(destination, time: arrival, alignment: .trailing)
            }
        case let .statistics(hero, unit, caption, _, _, _):
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(hero)
                        .font(.system(size: aspect == .square ? 44 : 54, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(muted)
                }
                Text(caption)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(muted)
            }
        case .list:
            EmptyView()
        }
    }

    private func endpoint(_ name: String, time: String?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            if let time {
                Text(time)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(muted)
            }
            Text(name)
                .font(.system(size: 20, weight: .bold))
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private var factsRow: some View {
        // Three across, or a 2 × 2 grid for four.
        let count = content.facts.count == 4 ? 2 : max(1, min(content.facts.count, 3))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(content.facts) { fact in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.value)
                        .font(.system(size: 19, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(fact.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var map: some View {
        ZStack {
            well
            if let mapImage {
                Image(uiImage: mapImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "map")
                    .font(.system(size: 24))
                    .foregroundStyle(muted)
            }
        }
        .frame(height: aspect.mapHeight)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func statisticsDetail(months: [ShareCardContent.Bar], busiest: String?,
                                  operators: [ShareCardContent.Bar]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
        if !months.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(content.rowsHeading ?? "")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(muted)
                    Spacer()
                    if let busiest {
                        Text(busiest)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                }
                // One hue; height is the only encoding, and the month is
                // printed under every bar. No legend needed.
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(months) { month in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(month.fraction > 0 ? accent : well)
                                .frame(height: max(3, 54 * month.fraction))
                            Text(month.label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 70, alignment: .bottom)
            }
        }
        if !operators.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(operators) { bar in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(bar.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Spacer()
                            Text(bar.value).font(.system(size: 13, weight: .semibold))
                                .monospacedDigit().foregroundStyle(muted)
                        }
                        GeometryReader { proxy in
                            Capsule().fill(well)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(accent)
                                        .frame(width: proxy.size.width * min(max(bar.fraction, 0), 1))
                                }
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
        }
    }

    private func rowsList(limit: Int) -> some View {
        let shown = Array(content.rows.prefix(limit))
        let more = content.rows.count - shown.count
        return VStack(alignment: .leading, spacing: 6) {
            if let heading = content.rowsHeading, !isStatistics {
                Text(heading)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(muted)
            }
            ForEach(shown) { row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.leading)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(row.emphasised ? accent : muted)
                        .frame(width: 58, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(row.title)
                        .font(.system(size: 13, weight: row.emphasised ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    if let trailing = row.trailing {
                        Text(trailing)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(muted)
                            .lineLimit(1)
                    }
                }
            }
            if more > 0 {
                Text("+\(more)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(muted)
            }
        }
    }

    private var isStatistics: Bool {
        if case .statistics = content.body { return true }
        return false
    }

    private var footerRow: some View {
        HStack {
            Image(systemName: "tram.fill").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
            Text("Japan Train Map").font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(footer).font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                .lineLimit(1)
        }
    }
}
