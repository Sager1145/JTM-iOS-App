import SwiftUI

struct StatsWidgetGridItem: Identifiable {
    let kind: StatisticsCardKind
    let shape: CardShape
    let data: StatsWidgetData
    var id: String { kind.rawValue }
}

struct StatsWidgetGrid: View {
    @Environment(AppLocalization.self) private var localization
    let items: [StatsWidgetGridItem]
    let openDetails: (StatisticsCardKind) -> Void

    var body: some View {
        StatsWidgetModuleLayout(spacing: 10) {
            ForEach(items) { item in
                Button { openDetails(item.kind) } label: {
                    GeometryReader { proxy in
                        let design = item.shape.designSize
                        let scale = min(proxy.size.width / design.width,
                                        proxy.size.height / design.height)
                        StatsWidgetView(kind: item.kind, shape: item.shape, data: item.data)
                            .scaleEffect(scale, anchor: .topLeading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .statsWidgetSpan(item.shape.baseSpan)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.data.title)
                .accessibilityValue(widgetSummary(item.data))
                .accessibilityHint(localization.text("ios.stats.widget.openDetails"))
                .accessibilityIdentifier("statisticsWidget-\(item.kind.rawValue)")
                .accessibilityAction(named: Text(localization.text("ios.stats.widget.openDetails"))) {
                    openDetails(item.kind)
                }
            }
        }
    }

    private func widgetSummary(_ data: StatsWidgetData) -> String {
        [data.hero, data.unit, data.supporting].compactMap { $0 }
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

private struct StatsWidgetSpanKey: LayoutValueKey {
    static let defaultValue = GridSpan(columns: 2, rows: 2)
}

private extension View {
    func statsWidgetSpan(_ span: GridSpan) -> some View {
        layoutValue(key: StatsWidgetSpanKey.self, value: span)
    }
}

private struct StatsWidgetModuleLayout: Layout {
    let spacing: CGFloat

    struct Placement {
        let column: Int
        let row: Int
        let span: GridSpan
    }

    struct Cache {
        var width: CGFloat = 0
        var columns = 6
        var rows = 0
        var placements: [Placement] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.width = 0
    }

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache
    ) -> CGSize {
        let width = proposal.width ?? 360
        prepare(width: width, subviews: subviews, cache: &cache)
        let cell = (width - spacing * CGFloat(cache.columns - 1)) / CGFloat(cache.columns)
        return CGSize(width: width, height: CGFloat(cache.rows) * cell
                      + CGFloat(max(0, cache.rows - 1)) * spacing)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
        cache: inout Cache
    ) {
        prepare(width: bounds.width, subviews: subviews, cache: &cache)
        let cell = (bounds.width - spacing * CGFloat(cache.columns - 1)) / CGFloat(cache.columns)
        for (index, placement) in cache.placements.enumerated() where index < subviews.count {
            let x = bounds.minX + CGFloat(placement.column) * (cell + spacing)
            let y = bounds.minY + CGFloat(placement.row) * (cell + spacing)
            let width = CGFloat(placement.span.columns) * cell
                + CGFloat(placement.span.columns - 1) * spacing
            let height = CGFloat(placement.span.rows) * cell
                + CGFloat(placement.span.rows - 1) * spacing
            subviews[index].place(
                at: CGPoint(x: x, y: y), anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: height))
        }
    }

    private func prepare(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        guard cache.width != width || cache.placements.count != subviews.count else { return }
        let columns = width >= 1_080 ? 12 : width >= 720 ? 9 : 6
        var occupied = Set<Int>()
        var placements: [Placement] = []
        var bottom = 0
        for subview in subviews {
            let span = subview[StatsWidgetSpanKey.self]
            var row = 0
            var placed: Placement?
            while placed == nil {
                if span.columns <= columns {
                    for column in 0...(columns - span.columns) {
                        let cells = (row..<(row + span.rows)).flatMap { y in
                            (column..<(column + span.columns)).map { y * columns + $0 }
                        }
                        if cells.allSatisfy({ !occupied.contains($0) }) {
                            occupied.formUnion(cells)
                            placed = Placement(column: column, row: row, span: span)
                            bottom = max(bottom, row + span.rows)
                            break
                        }
                    }
                }
                row += 1
            }
            if let placed { placements.append(placed) }
        }
        cache = Cache(width: width, columns: columns, rows: bottom, placements: placements)
    }
}
