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
    @State private var statusFilter: TrainServicePatterns.Filter.Status = .any
    @State private var companyFilter: String?
    @State private var lineFilter: String?

    private var groups: [(name: String, companyLabel: String, patterns: [TrainServicePatterns.Pattern])] {
        var order: [String] = []
        var byName: [String: [TrainServicePatterns.Pattern]] = [:]
        let filter = TrainServicePatterns.Filter(
            company: companyFilter, status: statusFilter, line: lineFilter)
        for pattern in TrainServicePatterns.search(query, region: region, filter: filter) {
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
                Section {
                    Picker("運行状況", selection: $statusFilter) {
                        Text("すべて").tag(TrainServicePatterns.Filter.Status.any)
                        Text("運行中").tag(TrainServicePatterns.Filter.Status.current)
                        Text("廃止・終了").tag(TrainServicePatterns.Filter.Status.discontinued)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("servicePatternStatusFilter")

                    HStack {
                        Menu {
                            Button("すべての会社") { companyFilter = nil }
                            ForEach(TrainServicePatterns.companyLabels(region: region), id: \.self) { label in
                                Button(label) { companyFilter = label }
                            }
                        } label: {
                            Label(companyFilter ?? "すべての会社", systemImage: "building.2")
                        }
                        .accessibilityIdentifier("servicePatternCompanyFilter")

                        Spacer()

                        Menu {
                            Button("すべての路線") { lineFilter = nil }
                            ForEach(TrainServicePatterns.lineNames(region: region), id: \.self) { line in
                                Button(line) { lineFilter = line }
                            }
                        } label: {
                            Label(lineFilter ?? "すべての路線", systemImage: "arrow.triangle.swap")
                        }
                        .accessibilityIdentifier("servicePatternLineFilter")
                    }
                }
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
                if pattern.isCurrent == false {
                    Text("廃止")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Capsule())
                }
                if pattern.completeness.stops == .missing
                    || pattern.completeness.lines == .missing
                    || pattern.completeness.validity == .missing
                {
                    Text("資料不完全")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text("\(pattern.origin) → \(pattern.destination) · \(pattern.stops.count)駅")
                .font(.caption)
                .foregroundStyle(.secondary)
            if pattern.validFrom != nil || pattern.validTo != nil {
                Text(validityCaption(for: pattern))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !pattern.lines.isEmpty {
                Text("経由: \(pattern.lines.joined(separator: "・"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !pattern.optionalStops.isEmpty {
                Text("一部列車停車: \(pattern.optionalStops.joined(separator: "、"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func validityCaption(for pattern: TrainServicePatterns.Pattern) -> String {
        let from = pattern.validFrom ?? "?"
        if let to = pattern.validTo {
            return "\(from)〜\(to)"
        }
        return "\(from)〜"
    }
}
