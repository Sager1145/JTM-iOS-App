import RailCore
import SwiftUI

/// Presented from the ride editor's stops section so a JP limited-express
/// stop pattern can prefill the draft's stop list. Tapping a row hands the
/// chosen pattern back to the caller and dismisses; the resulting stops stay
/// ordinary, editable rows afterwards.
struct ServicePatternPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let region: String
    let rideDate: String?
    let onSelect: (TrainServicePatterns.Pattern, Bool) -> Void

    @State private var query = ""
    @State private var showsAllHistory = false
    @State private var companyFilter: String?
    @State private var lineFilter: String?

    private var groups: [(name: String, companyLabel: String, patterns: [TrainServicePatterns.Pattern])] {
        var order: [String] = []
        var byName: [String: [TrainServicePatterns.Pattern]] = [:]
        let filter = TrainServicePatterns.Filter(
            company: companyFilter,
            status: showsAllHistory || rideDate == nil ? .any : .onDate,
            line: lineFilter, rideDate: rideDate)
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
                    if let rideDate {
                        Toggle("すべての履歴を表示", isOn: $showsAllHistory)
                            .accessibilityIdentifier("servicePatternHistoryFilter")
                        Text("乗車日: \(rideDate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("乗車日を設定すると、その日に有効なパターンを表示します")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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
                if let rideDate, pattern.isValid(on: rideDate) == false {
                    Text("乗車日の対象外")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Capsule())
                }
                if pattern.completeness.stops != .complete
                    || pattern.completeness.lines != .complete
                    || pattern.completeness.validity != .complete
                {
                    Text("停站\(mark(pattern.completeness.stops)) 路線\(mark(pattern.completeness.lines)) 日付\(mark(pattern.completeness.validity))")
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
            if pattern.validFrom != nil || pattern.validUntil != nil {
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
        if let until = pattern.validUntil {
            return "\(from)〜\(until)未満"
        }
        return "\(from)〜"
    }

    private func mark(_ level: TrainServicePatterns.Pattern.Level) -> String {
        switch level {
        case .complete: "✓"
        case .partial: "△"
        case .missing: "?"
        }
    }
}
