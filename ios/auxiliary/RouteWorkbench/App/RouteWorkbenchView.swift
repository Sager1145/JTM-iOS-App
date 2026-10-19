import Foundation
import Observation
import RailCore
import SwiftUI
import UniformTypeIdentifiers

typealias RouteWorkbenchView = RouteWorkbenchContentView

struct RouteWorkbenchContentView: View {
    let model: RouteWorkbenchModel
    @State private var commands = RouteWorkbenchCommandBridge()
    @State private var selectedID: String?
    @State private var importing = false
    @State private var exporting = false
    @State private var severityFilter: FindingFilter = .all
    @State private var selectedOnly = false
    @State private var journeyQuery = ""
    @State private var findingQuery = ""
    @State private var preparingExport = false
    @State private var exportName = "resolved-journeys"
    @State private var document = RouteWorkbenchDocument()
    @FocusState private var journeySearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TextField("搜索行程、端点或编号  ⌘F", text: $journeyQuery)
                    .textFieldStyle(.roundedBorder).padding(12)
                    .focused($journeySearchFocused)
                List(selection: $selectedID) {
                    ForEach(visibleTrains, id: \.id) { train in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(train.number.isEmpty ? train.id : train.number).font(.headline)
                            Text("\(train.origin) → \(train.destination)").font(.subheadline)
                            Text(model.status(train)).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(train.id)
                    }
                }
                .overlay {
                    if !model.trains.isEmpty && visibleTrains.isEmpty {
                        ContentUnavailableView.search(text: journeyQuery)
                    }
                }
            }
            .navigationTitle("行程 · \(model.trains.count)")
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 400)
        } detail: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 16) {
                            Image("RouteWorkbenchLogo").resizable().scaledToFit()
                                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 14))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("线路检查台").font(.largeTitle.bold())
                                Text("Route Workbench").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Text(model.sourceName).foregroundStyle(.secondary)
                        Text(model.message).textSelection(.enabled)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { actions }
                        VStack(alignment: .leading, spacing: 12) { actions }
                    }
                    .buttonStyle(.bordered)
                    HStack(spacing: 32) {
                        metric("已返回结果", "\(model.completedCount) / \(model.trains.count)")
                        metric("本次耗时", String(format: "%.1f 秒", model.elapsed))
                    }
                    if model.isRunning {
                        ProgressView(value: Double(model.completedCount), total: Double(max(1, model.trains.count)))
                            .accessibilityLabel("已返回 \(model.completedCount) 条结果")
                    }
                    if let train = model.trains.first(where: { $0.id == selectedID }) {
                        journeyDetails(train)
                        Divider()
                    }
                    LazyVStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("检查结果").font(.title2.bold())
                            Spacer()
                            if model.isInspecting { ProgressView().controlSize(.small) }
                        }
                        Text(model.inspectionMessage).foregroundStyle(.secondary).textSelection(.enabled)
                        Text("输入身份 · 结果覆盖 · 几何有效性 · 物理区段一致性 · 导出回读")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("提示类型", selection: $severityFilter) {
                            ForEach(FindingFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        TextField("搜索提示、行程 ID 或检查代码", text: $findingQuery)
                            .textFieldStyle(.roundedBorder)
                        Toggle("仅当前行程", isOn: $selectedOnly).toggleStyle(.switch)
                            .disabled(selectedID == nil)
                        Text("显示 \(visibleFindings.count) / \(model.findings.count) 项；报告保留全部提示。")
                            .font(.caption).foregroundStyle(.secondary)
                        if !model.findings.isEmpty && visibleFindings.isEmpty {
                            Text("没有符合筛选条件的提示。")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(visibleFindings) { finding in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: finding.severity == .failure ? "xmark.circle.fill" : "exclamationmark.circle")
                                    .foregroundStyle(finding.severity == .failure ? Color.red : Color.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(finding.message).textSelection(.enabled)
                                    Text([finding.trainID, finding.sectionIndex.map { "区段 \($0 + 1)" }, finding.code]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let id = finding.trainID {
                                    Button("查看") { journeyQuery = ""; selectedID = id }.buttonStyle(.borderless)
                                }
                            }
                            .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    Divider()
                    if selectedID == nil {
                        ContentUnavailableView("选择行程查看结果", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                            description: Text("已确认的区段可导出给 iOS；无法确认的记录会保留。"))
                    }
                }
                .padding(32)
                .frame(maxWidth: 850, alignment: .leading)
            }
            .navigationTitle("Route Workbench")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text("搜索行程 ⌘F · 上一行程 ⌥⌘← · 下一行程 ⌥⌘→ · 导入 JSON ⌘O · 导出行程 ⌥⌘E · 导出报告 ⇧⌥⌘E")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(.bar)
                .accessibilityLabel("Search journeys: Command F. Previous journey: Option Command Left Arrow. Next journey: Option Command Right Arrow. Import JSON: Command O. Export journeys: Option Command E. Export report: Shift Option Command E.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): Task { await model.read(url, retainingForTask: true) }
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: exportName) { result in
            if case .failure(let error) = result { model.error = error.localizedDescription }
        }
        .alert("处理失败", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("关闭", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onChange(of: model.routes.rides.count) { _, _ in model.refresh() }
        .onChange(of: model.phaseKey) { _, _ in model.refresh() }
        .onChange(of: model.trains.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) {
                self.selectedID = nil
                selectedOnly = false
            }
            installCommands()
        }
        .focusedSceneValue(\.routeWorkbenchCommands, commands)
        .onAppear(perform: installCommands)
        .onChange(of: selectedID) { _, _ in installCommands() }
        .onChange(of: journeyQuery) { _, _ in installCommands() }
        .onChange(of: model.isRunning) { _, _ in installCommands() }
        .onChange(of: model.isReading) { _, _ in installCommands() }
        .onChange(of: model.isInspecting) { _, _ in installCommands() }
        .onChange(of: preparingExport) { _, _ in installCommands() }
    }

    private enum FindingFilter: String, CaseIterable { case all = "全部", failure = "失败", review = "待审阅" }

    private var visibleTrains: [Train] {
        let query = journeyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.trains }
        return model.trains.filter {
            [$0.id, $0.number, $0.origin, $0.destination].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var visibleFindings: [RouteBatchInspection.Finding] {
        let candidates = selectedOnly ? (selectedID.flatMap { model.findingsByTrainID[$0] } ?? []) : model.findings
        let query = findingQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if severityFilter == .all && query.isEmpty { return candidates }
        return candidates.filter {
            (severityFilter == .all || (severityFilter == .failure ? $0.severity == .failure : $0.severity == .review))
                && (query.isEmpty || [$0.message, $0.code, $0.trainID ?? ""].contains {
                    $0.localizedCaseInsensitiveContains(query)
                })
        }
    }

    @ViewBuilder private func journeyDetails(_ train: Train) -> some View {
        let diagnostic = model.diagnostic(for: train)
        VStack(alignment: .leading, spacing: 12) {
            Text(train.number).font(.title2.bold())
            Text("\(train.origin) → \(train.destination)")
            Text(diagnostic.status).font(.headline)
            Text(train.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let expected = diagnostic.expectedSectionCount, let solved = diagnostic.resolvedSectionCount {
                Text("已解析区段 \(solved) / \(expected) · \(diagnostic.parts.count) 段显示几何")
            } else if !diagnostic.parts.isEmpty {
                Text("\(diagnostic.parts.count) 段显示几何；规范区段覆盖未知。")
            }
            if diagnostic.indicesAreAuthoritative == false {
                Text("显示分段编号不对应规范行程区段，不能据此冻结物理选择。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(diagnostic.unresolvedSections.enumerated()), id: \.offset) { _, gap in
                Label("区段 \(gap.sectionIndex + 1) · \(gap.from ?? "未知") → \(gap.to ?? "未知")：\(gap.isBoundary ? "连接待证明" : "路径未解决")",
                      systemImage: "exclamationmark.triangle")
            }
            ForEach(Array(diagnostic.physicalGaps.enumerated()), id: \.offset) { _, gap in
                Text("区段 \(gap.segmentIndex + 1)：\(gap.isBoundary ? "进入该区段的物理连接未证明" : "该区段物理路径未证明")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("区段身份与来源") {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(diagnostic.parts.enumerated()), id: \.offset) { _, part in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("区段 \(part.sectionIndex + 1) · 分段 \(part.partIndex + 1) · \(part.from ?? "未知") → \(part.to ?? "未知")")
                            if let selection = part.physicalSelection {
                                Text("\(selection.fromStationCode) → \(selection.toStationCode) · \(selection.provenance.rawValue)")
                                Text(selection.intervals.map { "\($0.code) [\($0.direction)]" }.joined(separator: " → "))
                                if let database = selection.databaseProvenance {
                                    Text("班次 \(database.tripID) · \(database.serviceDate) · 版本 \(database.timetableVersionID)")
                                }
                            } else { Text("只有几何，缺少物理区段选择。") }
                        }.font(.caption).textSelection(.enabled)
                    }
                }.padding(.top, 8)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        Button("导入 JSON  ⌘O", systemImage: "square.and.arrow.down") { importing = true }
            .disabled(model.isRunning || model.isReading || model.isInspecting || preparingExport)
        if model.isRunning {
            Button("取消", systemImage: "stop.fill") { model.cancel() }
        } else {
            Button("批量解析", systemImage: "play.fill") { model.requestSolve() }
                .disabled(model.trains.isEmpty || model.isReading || model.isInspecting || preparingExport)
        }
        Button("检查结果", systemImage: "checklist") { model.inspect() }
            .disabled(model.trains.isEmpty || model.isRunning || model.isReading || model.isInspecting || preparingExport)
        Menu("导出", systemImage: "square.and.arrow.up") {
            Button("行程与已确认区段  ⌥⌘E") { prepareExport(reportOnly: false) }
            Button("处理报告  ⇧⌥⌘E") { prepareExport(reportOnly: true) }
        }
        .disabled(model.trains.isEmpty || model.isRunning || model.isReading || model.isInspecting || preparingExport)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.monospacedDigit())
        }
    }

    private func prepareExport(reportOnly: Bool) {
        preparingExport = true
        Task {
            defer { preparingExport = false }
            do {
                document = RouteWorkbenchDocument(data: try await model.export(reportOnly: reportOnly))
                exportName = reportOnly ? "route-report" : "resolved-journeys"
                exporting = true
            } catch { model.error = error.localizedDescription }
        }
    }

    private func navigateJourney(_ delta: Int) {
        let trains = visibleTrains
        guard !trains.isEmpty else { return }
        let current = selectedID.flatMap { id in trains.firstIndex { $0.id == id } }
            ?? (delta > 0 ? -1 : trains.count)
        selectedID = trains[min(max(0, current + delta), trains.count - 1)].id
    }

    private func installCommands() {
        let busy = model.isRunning || model.isReading || model.isInspecting || preparingExport
        commands.canOpen = !busy
        commands.canNavigate = !visibleTrains.isEmpty
        commands.canExport = !model.trains.isEmpty && !busy
        commands.open = { self.importing = true }
        commands.search = { self.journeySearchFocused = true }
        commands.previous = { self.navigateJourney(-1) }
        commands.next = { self.navigateJourney(1) }
        commands.exportResolved = { self.prepareExport(reportOnly: false) }
        commands.exportReport = { self.prepareExport(reportOnly: true) }
    }
}

@MainActor @Observable
final class RouteWorkbenchCommandBridge {
    var canOpen = false
    var canNavigate = false
    var canExport = false
    @ObservationIgnored var open: (@MainActor () -> Void)?
    @ObservationIgnored var search: (@MainActor () -> Void)?
    @ObservationIgnored var previous: (@MainActor () -> Void)?
    @ObservationIgnored var next: (@MainActor () -> Void)?
    @ObservationIgnored var exportResolved: (@MainActor () -> Void)?
    @ObservationIgnored var exportReport: (@MainActor () -> Void)?
}

private struct RouteWorkbenchCommandKey: FocusedValueKey {
    typealias Value = RouteWorkbenchCommandBridge
}

extension FocusedValues {
    var routeWorkbenchCommands: RouteWorkbenchCommandBridge? {
        get { self[RouteWorkbenchCommandKey.self] }
        set { self[RouteWorkbenchCommandKey.self] = newValue }
    }
}

struct RouteWorkbenchCommands: Commands {
    @FocusedValue(\.routeWorkbenchCommands) private var bridge

    var body: some Commands {
        #if RAIL_DIAGNOSTICS
        UnifiedDiagnosticCommands()
        #else
        CommandGroup(replacing: .newItem) {
            Button("Import JSON") { bridge?.open?() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(bridge?.canOpen != true)
        }
        CommandMenu("Route Inspection") { RouteWorkbenchCommandItems(bridge: bridge) }
        #endif
    }
}

struct RouteWorkbenchDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct RouteWorkbenchCommandItems: View {
    let bridge: RouteWorkbenchCommandBridge?

    var body: some View {
        Group {
            Button("Search journeys") { bridge?.search?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(bridge == nil)
            Divider()
            Button("Previous journey") { bridge?.previous?() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(bridge?.canNavigate != true)
            Button("Next journey") { bridge?.next?() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(bridge?.canNavigate != true)
            Divider()
            Button("Export resolved journeys") { bridge?.exportResolved?() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(bridge?.canExport != true)
            Button("Export processing report") { bridge?.exportReport?() }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                .disabled(bridge?.canExport != true)
        
        }
    }
}
