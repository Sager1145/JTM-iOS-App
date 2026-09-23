import RailCore
import SwiftUI

/// Presented from the ride editor's stops section so a JP limited-express
/// stop pattern can prefill the draft's stop list. Tapping a row hands the
/// chosen pattern back to the caller and dismisses; the resulting stops stay
/// ordinary, editable rows afterwards.
struct ServicePatternPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let region: String
    let onSelect: (TrainServicePatterns.Pattern, Bool) -> Void

    @State private var query = ""

    private var groups: [(name: String, companyLabel: String, patterns: [TrainServicePatterns.Pattern])] {
        var order: [String] = []
        var byName: [String: [TrainServicePatterns.Pattern]] = [:]
        for pattern in TrainServicePatterns.search(query, region: region) {
            if byName[pattern.name] == nil { order.append(pattern.name) }
            byName[pattern.name, default: []].append(pattern)
        }
        return order.map { name in
            (name: name, companyLabel: byName[name]?.first?.companyLabel ?? "", patterns: byName[name] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.name) { group in
                    Section(header: Text("\(group.name) · \(group.companyLabel)")) {
                        ForEach(group.patterns) { pattern in
                            HStack(spacing: 0) {
                                Button {
                                    onSelect(pattern, false)
                                    dismiss()
                                } label: {
                                    row(for: pattern)
                                }
                                Button {
                                    onSelect(pattern, true)
                                    dismiss()
                                } label: {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("逆方向: \(pattern.destination) → \(pattern.origin)")
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
                if groups.isEmpty {
                    Text("該当する列車パターンが見つかりません")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("列車パターンから入力")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: Text("列車名・行き先で検索"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }

    private func row(for pattern: TrainServicePatterns.Pattern) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(pattern.label)
                if pattern.confidence == "low" {
                    Text("要確認")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            Text("\(pattern.origin) → \(pattern.destination) · \(pattern.stops.count)駅")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !pattern.optionalStops.isEmpty {
                Text("一部列車停車: \(pattern.optionalStops.joined(separator: "、"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
