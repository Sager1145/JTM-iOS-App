import SwiftUI

/// A directly selectable time range, with the selected label on a quiet capsule.
struct StatisticsYearBar: View {
    let allTimeLabel: String
    let years: [Int]
    let selectedYear: Int?
    let accessibilityPrefix: String
    let select: (Int?) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    choice(allTimeLabel, year: nil)
                    ForEach(years, id: \.self) { year in
                        choice(String(year), year: year)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedYear) { _, year in
                proxy.scrollTo(identifier(for: year), anchor: .center)
            }
        }
    }

    private func choice(_ label: String, year: Int?) -> some View {
        let selected = selectedYear == year
        return Button {
            select(year)
        } label: {
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .padding(.horizontal, 14)
                .frame(minHeight: WorkspaceMenuMetrics.buttonSide)
                .background {
                    if selected {
                        Capsule().fill(.primary.opacity(0.09))
                    }
                }
                .frame(minHeight: WorkspaceMenuMetrics.touchSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier(for: year))
        .id(identifier(for: year))
    }

    private func identifier(for year: Int?) -> String {
        "\(accessibilityPrefix)-\(year.map(String.init) ?? "allTime")"
    }
}
