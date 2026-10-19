import SwiftUI

struct StatsWidgetRow: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let value: String
    let fraction: Double
    var emblem: String? = nil
}

struct StatsWidgetColumn: Identifiable, Hashable, Sendable {
    let id: Int
    let label: String
    let value: Int
}

/// A presentation snapshot of values already computed by the statistics stores.
/// It deliberately contains no aggregation logic so the full cards and widgets
/// cannot disagree about what a ride contributes.
struct StatsWidgetData: Hashable, Sendable {
    var title: String
    var hero: String
    var unit: String = ""
    var supporting: String? = nil
    var scopeLabel: String? = nil
    var contextDetail: String? = nil
    var secondaryValue: String? = nil
    var secondaryLabel: String? = nil
    var rows: [StatsWidgetRow] = []
    var alternateRows: [StatsWidgetRow] = []
    var columns: [StatsWidgetColumn] = []
    var emptyMessage: String

    var isEmpty: Bool { hero.isEmpty && rows.isEmpty && columns.isEmpty }

#if DEBUG
    static func preview(for kind: StatisticsCardKind) -> StatsWidgetData {
        StatsWidgetData(
            title: kind.fallbackTitle,
            hero: kind == .time ? "18 h 42 min" : kind == .coverage ? "68%" : "1,284",
            unit: kind == .distance ? "km" : "",
            supporting: "Tokyo → Kyoto",
            scopeLabel: "Japan", contextDetail: "20 Feb 2025 · 09:00 → 11:15",
            secondaryValue: "42",
            secondaryLabel: "Rides",
            rows: (1...8).map {
                StatsWidgetRow(id: "\($0)", label: "Railway \($0)",
                               value: "\(95 - $0 * 7)%", fraction: Double(9 - $0) / 8)
            },
            alternateRows: (1...7).map {
                StatsWidgetRow(id: "weekday-\($0)", label: "\($0)", value: "\($0 * 3)",
                               fraction: Double($0) / 7)
            },
            columns: (1...12).map { StatsWidgetColumn(id: $0, label: "\($0)", value: ($0 * 7) % 19) },
            emptyMessage: "No data for this scope")
    }
#endif
}

struct StatsWidgetView: View {
    let kind: StatisticsCardKind
    let shape: CardShape
    let data: StatsWidgetData

    var body: some View {
        Group {
            if shape.isCompact {
                compactContent
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if data.isEmpty {
                        Spacer(minLength: 0)
                        Text(data.emptyMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    } else {
                        content
                    }
                }
            }
        }
        .padding(shape.isCompact ? 8 : shape == .small ? 14 : 16)
        .frame(width: shape.designSize.width, height: shape.designSize.height,
               alignment: .topLeading)
        .passportWidgetSurface(cornerRadius: shape.isCompact ? 11 : 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(data.title)
        .accessibilityValue(accessibilitySummary)
    }

    @ViewBuilder private var compactContent: some View {
        if (kind == .distance || kind == .time) && !data.isEmpty {
            compactJourneyContent
        } else {
            compactSummary
        }
    }

    /// A strip keeps the winning ride's identity alongside its metric.
    /// Older documents can still contain mini journey cards; they retain the
    /// same facts in a denser layout, while new cards offer the readable strip.
    @ViewBuilder private var compactJourneyContent: some View {
        if shape == .strip {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(data.hero)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.45)
                        if !data.unit.isEmpty {
                            Text(data.unit).font(.system(size: 7)).foregroundStyle(.secondary)
                        }
                    }
                    if let scope = data.scopeLabel {
                        Text(scope).font(.system(size: 7)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .frame(width: 58, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    if let endpoints = data.supporting {
                        Text(endpoints).font(.system(size: 8, weight: .medium))
                            .lineLimit(2).minimumScaleFactor(0.7)
                    }
                    if let detail = data.contextDetail {
                        Text(detail).font(.system(size: 8)).foregroundStyle(.secondary)
                            .lineLimit(4).minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(data.title).font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(data.hero)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.45)
                    if !data.unit.isEmpty { Text(data.unit).font(.system(size: 6)) }
                }
                if let endpoints = data.supporting {
                    Text(endpoints).font(.system(size: 6, weight: .medium)).lineLimit(2)
                }
                if let detail = data.contextDetail {
                    Text(detail).font(.system(size: 5)).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
    }

    private var compactSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(data.title, systemImage: kind.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(shape == .mini ? 2 : 1)
                .minimumScaleFactor(0.7)
            if let scope = data.scopeLabel, kind == .coverage || shape == .strip {
                Text(scope)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(kind == .coverage && shape == .mini ? 2 : 1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            if data.isEmpty {
                Text(data.emptyMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(data.hero)
                        .font(.system(size: shape == .mini ? 18 : 23,
                                      weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if shape == .strip, !data.unit.isEmpty {
                        Text(data.unit).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                if shape == .mini, !data.unit.isEmpty {
                    Text(data.unit).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(data.title, systemImage: kind.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let scope = data.scopeLabel {
                Text(scope).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            if kind != .distance && kind != .time, let detail = data.contextDetail {
                Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .dailyTicket:
            dailyTicketContent
        case .rhythm:
            rhythmContent
        case .coverage:
            coverageContent
        case .service:
            serviceContent
        case .distance, .time:
            metricContent(rows: shape == .small || shape == .medium ? 0 : 2)
        case .rides:
            metricContent(rows: 0)
        case .stations, .operators, .routes, .topSegments, .regions, .lineDetail:
            rankedContent
        case .recordTicket:
            metricContent(rows: 0)
        }
    }

    private var dailyTicketContent: some View {
        Group {
            if shape == .medium {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        hero
                        Spacer(minLength: 8)
                        if let value = data.secondaryValue, let label = data.secondaryLabel {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(label).font(.caption2).foregroundStyle(.secondary)
                                Text(value).font(.title3.bold()).monospacedDigit()
                            }
                        }
                    }
                    Text(data.supporting ?? "")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Rectangle().fill(Color.accentColor).frame(height: 7)
                    Text("RAILMAP")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.2).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    hero
                    if let value = data.secondaryValue, let label = data.secondaryLabel {
                        Text("\(label) · \(value)")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if shape != .small, let supporting = data.supporting {
                        Text(supporting).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private func metricContent(rows count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            hero
            if let supporting = data.supporting, !supporting.isEmpty {
                Text(supporting)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(kind == .distance || kind == .time ? 2 : 1)
            }
            if let detail = data.contextDetail, kind == .distance || kind == .time {
                Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
            }
            if let value = data.secondaryValue, let label = data.secondaryLabel,
               shape != .small {
                HStack(alignment: .firstTextBaseline) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
            }
            if count > 0 { rowsView(Array(data.rows.prefix(count))) }
        }
    }

    private var rhythmContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shape == .small {
                hero
                Text(data.supporting ?? "")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else if shape == .tall {
                rowsView(Array(data.alternateRows.prefix(7)))
            } else {
                columnChart
                if shape == .large, let supporting = data.supporting {
                    Text(supporting).font(.caption.weight(.semibold)).lineLimit(1)
                }
            }
        }
    }

    private var coverageContent: some View {
        HStack(alignment: .top, spacing: 12) {
            coverageRing
            if shape != .small {
                rowsView(Array(data.rows.dropFirst().prefix(shape == .medium ? 3 : 8)))
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var serviceContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if shape == .small {
                hero
                if let supporting = data.supporting {
                    Text(supporting).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            else {
                stackedBar
                if shape == .large || shape == .tall {
                    rowsView(Array(data.rows.prefix(3)))
                } else if let supporting = data.supporting {
                    Text(supporting).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }

    private var rankedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shape == .small || kind == .regions { hero }
            if shape == .small || kind == .regions, let supporting = data.supporting {
                Text(supporting).font(.caption).lineLimit(shape == .small ? 2 : 1)
            }
            rowsView(Array(data.rows.prefix(rowLimit)))
        }
    }

    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(data.hero)
                .font(.system(size: shape == .small ? 32 : 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            if !data.unit.isEmpty {
                Text(data.unit).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }

    private var coverageRing: some View {
        let progress = data.rows.first?.fraction ?? 0
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.16), lineWidth: 10)
            Circle().trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(data.hero)
                .font(.system(size: shape == .small ? 28 : 25, weight: .bold, design: .rounded))
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
        }
        .frame(width: shape == .small ? 90 : 76, height: shape == .small ? 90 : 76)
    }

    private var stackedBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(data.rows.prefix(3)) { row in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.opacity(0.35 + 0.2 * row.fraction))
                        .frame(width: max(2, proxy.size.width * row.fraction))
                }
            }
        }
        .frame(height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var columnChart: some View {
        let peak = max(data.columns.map(\.value).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(data.columns.prefix(12)) { column in
                VStack(spacing: 3) {
                    Capsule()
                        .fill(column.value == 0 ? Color.secondary.opacity(0.15) : Color.accentColor)
                        .frame(height: max(2, 64 * CGFloat(column.value) / CGFloat(peak)))
                    Text(column.label).font(.system(size: 7)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func rowsView(_ rows: [StatsWidgetRow]) -> some View {
        VStack(spacing: shape == .tall || shape == .large ? 6 : 5) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if let emblem = row.emblem { Text(emblem).font(.caption2) }
                        Text(row.label).font(.caption2.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(row.value).font(.caption2.weight(.semibold)).monospacedDigit().lineLimit(1)
                    }
                    GeometryReader { proxy in
                        Capsule().fill(Color.secondary.opacity(0.13))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.accentColor)
                                    .frame(width: proxy.size.width * min(max(row.fraction, 0), 1))
                            }
                    }
                    .frame(height: 4)
                }
            }
        }
    }

    private var rowLimit: Int {
        switch shape {
        case .mini, .strip: 0
        case .small: 0
        case .medium: 3
        case .tall: 6
        case .large: 8
        }
    }

    private var accessibilitySummary: String {
        if data.isEmpty {
            return [data.scopeLabel, data.contextDetail, data.emptyMessage]
                .compactMap { $0 }.joined(separator: ", ")
        }
        return ([data.hero, data.unit, data.scopeLabel, data.supporting, data.contextDetail,
                 data.secondaryLabel, data.secondaryValue]
            .compactMap { $0 }.filter { !$0.isEmpty } + data.rows.prefix(3).map { "\($0.label) \($0.value)" })
            .joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Statistics widgets · light and dark") {
    ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: 24) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                LazyVGrid(columns: [.init(.fixed(250)), .init(.fixed(250))], spacing: 14) {
                    ForEach(StatisticsCardKind.allCases.filter { $0 != .recordTicket }) { kind in
                        ForEach(kind.widgetShapes) { shape in
                            StatsWidgetView(kind: kind, shape: shape, data: .preview(for: kind))
                                .scaleEffect(0.72, anchor: .topLeading)
                                .frame(width: shape.designSize.width * 0.72,
                                       height: shape.designSize.height * 0.72,
                                       alignment: .topLeading)
                        }
                    }
                }
                .environment(\.colorScheme, scheme)
            }
        }
        .padding()
    }
}
#endif
