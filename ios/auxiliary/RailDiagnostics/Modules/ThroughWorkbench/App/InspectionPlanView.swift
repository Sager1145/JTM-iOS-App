import SwiftUI
import WorkbenchCore

struct InspectionPlanView: View {
    @Bindable var store: WorkbenchStore
    let export: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var category = ""
    @State private var severity = ""

    private var categories: [String] {
        Array(Set(store.inspectionPlan?.findings.map(\.category) ?? [])).sorted()
    }

    private var filteredFindings: [InspectionFinding] {
        (store.inspectionPlan?.findings ?? []).filter {
            (category.isEmpty || $0.category == category) &&
            (severity.isEmpty || $0.severity.rawValue == severity)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image("WorkbenchLogo")
                            .resizable().scaledToFit().frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("历史直通运行检查").font(.headline)
                            Text("检查范围、发现与后续证据计划").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("检查已收录的历史直通运行模式。结构检查通过不能证明全国覆盖完整，也不能证明物理路由可解；未知或受阻的检查仍需补充证据。")
                        .foregroundStyle(.secondary)
                    if store.isInspecting {
                        HStack { ProgressView(); Text("正在生成检查计划…") }
                    }
                    if let error = store.inspectionError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                if let plan = store.inspectionPlan {
                    Section("检查范围") {
                        LabeledContent("日期范围", value: "\(plan.startDay) — \(plan.endDay)")
                        LabeledContent("模式数量", value: "\(plan.patternCount)")
                        LabeledContent("检查日期数量", value: "\(plan.sampledDays.count)")
                        DisclosureGroup("检查日期") {
                            Text(plan.sampledDays.joined(separator: "、"))
                                .font(.caption).textSelection(.enabled)
                        }
                    }
                    Section("检查结果") {
                        ForEach(plan.checks, id: \.id) { check in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(check.title).font(.headline)
                                Text("\(checkResultLabel(check.result)) · \(check.scope)")
                                    .font(.subheadline)
                                    .foregroundStyle(check.result == "failed" || check.result == "fail" ? Color.red : check.result == "unknown" || check.result == "blocked" || check.result == "warning" ? Color.orange : Color.primary)
                                Text(check.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("筛选发现（\(filteredFindings.count) / \(plan.findings.count)）") {
                        Picker("类别", selection: $category) {
                            Text("全部类别").tag("")
                            ForEach(categories, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("严重程度", selection: $severity) {
                            Text("全部程度").tag("")
                            Text("错误").tag("error")
                            Text("警告").tag("warning")
                            Text("未知 / 待证据").tag("unknown")
                        }
                        if filteredFindings.isEmpty {
                            Text(plan.findings.isEmpty ? "现有检查未产生发现；请同时查看未知或受阻的检查。" : "当前筛选没有发现。")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(Set(filteredFindings.map(\.category))).sorted(), id: \.self) { group in
                        Section(group) {
                            ForEach(filteredFindings.filter { $0.category == group }, id: \.id) { finding in
                                findingRow(finding)
                            }
                        }
                    }
                } else if !store.isInspecting && store.inspectionError == nil {
                    Text("尚未生成检查计划。请刷新计划。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("检查计划")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await store.refreshInspectionPlan() }
                    } label: { Label("刷新计划", systemImage: "arrow.clockwise") }
                        .disabled(store.isBusy || store.isInspecting || store.snapshot == nil)
                    Button {
                        dismiss()
                        export()
                    } label: { Label("导出 JSON", systemImage: "square.and.arrow.up") }
                        .disabled(store.inspectionPlan == nil || store.isInspecting || store.isBusy)
                }
            }
        }
        .frame(minHeight: 420)
        .dynamicTypeSize(.xSmall ... .xLarge)
        .onChange(of: categories) { _, values in
            if !values.contains(category) { category = "" }
        }
    }

    private func findingRow(_ finding: InspectionFinding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(severityLabel(finding.severity), systemImage: finding.severity == .unknown ? "questionmark.circle" : "exclamationmark.triangle")
                .font(.caption).foregroundStyle(finding.severity == .error ? Color.red : Color.secondary)
            Text(finding.title).font(.headline)
            if !finding.patternID.isEmpty {
                Button("查看模式：\(finding.patternID)") {
                    store.search = ""
                    if store.snapshot?.patterns.contains(where: { $0.id == finding.patternID }) != true,
                       let day = finding.days.compactMap({ ISODay.date($0) }).first {
                        store.day = day
                    }
                    store.selectedID = finding.patternID
                    dismiss()
                }
            }
            Text("涉及日期：\(finding.days.joined(separator: "、"))")
                .font(.caption).foregroundStyle(.secondary)
            Text("建议：\(finding.recommendation)").textSelection(.enabled)
            if finding.requiresEvidence {
                Label("需要补充来源或物理证据", systemImage: "doc.text.magnifyingglass")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func severityLabel(_ value: Severity) -> String {
        switch value {
        case .error: "错误"
        case .warning: "警告"
        case .unknown: "未知 / 待证据"
        }
    }

    private func checkResultLabel(_ value: String) -> String {
        switch value {
        case "passed", "pass": "通过"
        case "failed", "fail": "未通过"
        case "unknown": "未知 / 待证据"
        case "blocked": "受阻 / 需要补充输入"
        case "warning": "需复核"
        default: value
        }
    }
}
