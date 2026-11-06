import SwiftUI
import UniformTypeIdentifiers
import RailInspection
import Observation

struct ViewRecord: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct InspectorView: View {
    let model: InspectorModel
    @State private var exporting = false
    @State private var record = ViewRecord(data: Data())
    @State private var exportError: String?
    @State private var evidenceExport = false
    @State private var evidenceDocument = EvidenceDocument(files: [:])
    @State private var exportingBundle: EvidenceBundle?
    @State private var importing = false
    @State private var queueMode = true
    @State private var filename = "jp-rail-view"
    @State private var commands = InspectorCommandBridge()
    @FocusState private var queryFocused: Bool
    @FocusState private var cameraFocused: Bool
    @State private var cameraEntry = ""

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image("InspectorLogo").resizable().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading) {
                        Text("Rail Inspector").font(.title2.bold())
                        Text("日本铁路 · 底图审查").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(model.progressText).font(.caption.monospaced())
                Picker("浏览", selection: $queueMode) {
                    Text("检查队列").tag(true); Text("线路").tag(false)
                }.pickerStyle(.segmented)
                TextField(queueMode ? "搜索线路 / 公司 / 站点 / ID" : "搜索线路 / 公司 / ID", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($queryFocused)
                    .accessibilityHint("Command F focuses search. Return selects a unique matching line.")
                    .onSubmit { selectUniqueFilteredLine() }
                TextField("经度,纬度,缩放级别", text: $cameraEntry)
                    .textFieldStyle(.roundedBorder)
                    .focused($cameraFocused)
                    .accessibilityHint("Shift Command G focuses coordinates. Return moves the camera.")
                    .onSubmit { model.requestCamera(cameraEntry) }
                if let error = model.error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                } else if model.lines.isEmpty {
                    ProgressView("读取日本线路…")
                }
                if queueMode {
                    Toggle("只看待检区间", isOn: $model.pendingOnly)
                    List(selection: Binding(get: { model.currentItem?.id }, set: { if let id = $0 { model.selectItem(id) } })) {
                        ForEach(model.filteredItems) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(item.lineName) · \(item.fromName) → \(item.toName)").font(.callout)
                                Text("优先级 \(item.priority) · \(model.reviewTitle(item.id))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.tag(Optional(item.id))
                        }
                    }
                } else {
                List(selection: Binding(get: { model.lineID }, set: { model.select($0) })) {
                    ForEach(model.filteredLines, id: \.id) { line in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.name)
                            Text(line.operator ?? line.id).font(.caption).foregroundStyle(.secondary)
                        }.tag(Optional(line.id))
                    }
                }
                }
                Text(queueMode
                     ? "\(model.filteredItems.count) / \(model.totalCount) 个区间 · \(model.version)"
                     : "\(model.filteredLines.count) / \(model.lines.count) 条线路 · \(model.version)")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                if let item = model.currentItem {
                    Text("结论仅针对当前视点；长区间须逐段检查。").font(.caption).foregroundStyle(.secondary)
                    Text(item.signals.joined(separator: "；")).font(.caption).textSelection(.enabled)
                    Text(String(format: "最长弦 %.0f m · 转角 %.0f° · 顶点 %d / %d", item.maxChordMetres, item.maxTurnDegrees, item.sourceVertexCount, item.displayVertexCount)).font(.caption)
                    Picker("结论", selection: $model.draftVerdict) {
                        ForEach([ReviewVerdict.pending, .aligned, .needsRepair, .insufficientBasemap, .repaired], id: \.rawValue) {
                            Text($0.title).tag($0)
                        }
                    }
                    TextField("检查说明 / 证据来源", text: $model.draftNote, axis: .vertical).lineLimit(2...4)
                    HStack {
                        Button("保存结论") { model.saveReview() }
                            .disabled(model.draftVerdict != .pending && model.draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("下一待检  ⇧⌘N") { model.navigateQueue(1) }
                    }
                }
                if let line = model.line {
                    Text(line.id).font(.caption).textSelection(.enabled)
                    Picker("站点", selection: Binding(get: { model.stationIndex }, set: { model.stationIndex = $0; model.focusStation() })) {
                        ForEach(Array(line.stations.enumerated()), id: \.offset) { index, station in
                            Text("\(index + 1). \(station.name)").tag(index)
                        }
                    }.id(line.id)
                    HStack {
                        Button("上一站  ⇧⌥⌘←") { model.navigate(-1) }
                            .disabled(model.stationIndex <= 0)
                        Button("下一站  ⇧⌥⌘→") { model.navigate(1) }
                            .disabled(model.stationIndex >= line.stations.count - 1)
                    }
                    HStack {
                        Button("上个视点  ⌥⌘←") { model.navigateInspectionPoint(-1) }
                            .disabled(model.inspectionPoints.isEmpty)
                        Text(model.inspectionPoints.isEmpty ? "站点视图" : "\(model.inspectionPointIndex + 1)/\(model.inspectionPoints.count)").font(.caption)
                        Button("下个视点  ⌥⌘→") { model.navigateInspectionPoint(1) }
                            .disabled(model.inspectionPoints.isEmpty)
                    }
                    Button("从首个详细视点开始  ⌘↖") { model.inspectionPointIndex = 0; model.navigateInspectionPoint(0) }
                        .disabled(model.inspectionPoints.isEmpty)
                    HStack {
                        Button("站点附近  ⌘9") { model.focusStation() }
                        Button("下一站区间  ⌘0") { model.focusInterval() }
                        Button("全线  ⇧⌘0") { model.focusLine() }
                    }
                }
                }
                }.frame(maxHeight: 390)
            }
            .padding(16).frame(width: 330)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Picker("对照", selection: $model.mode) {
                        ForEach(Array(ComparisonMode.allCases.enumerated()), id: \.element.id) { index, mode in
                            Text("\(mode.title)  ⌘\(index + 1)").tag(mode)
                        }
                    }.pickerStyle(.segmented)
                    Button(model.peek ? "恢复叠加  ⌘B" : "只看底图  ⌘B") { model.peek.toggle() }
                }.padding(12)
                HStack {
                    Text("叠加透明度")
                    Slider(value: $model.opacity, in: 0.05 ... 1).frame(maxWidth: 220)
                    Text("\(Int(model.opacity * 100))%")
                    Spacer()
                    Button("导出视点记录  ⇧⌘S") {
                        prepareViewExport()
                    }.disabled(model.line == nil)
                    Button("导出完整计划") {
                        do { filename = "jp-inspection-plan"; record = ViewRecord(data: try model.planData()); exporting = true }
                        catch { exportError = error.localizedDescription }
                    }.disabled(model.plan == nil)
                }.padding(.horizontal, 12).padding(.bottom, 8)
                HStack {
                    Button(model.busyCapture ? "生成证据…  ⌥⌘S" : "导出同视点证据  ⌥⌘S") { model.captureRequested() }
                        .disabled(!model.canCaptureEvidence)
                    Button("导入轨道 GeoJSON") { importing = true }
                    Text(model.referenceLabel ?? "未加载外部轨道参考").font(.caption).lineLimit(1)
                    Button("z17  ⌘7") { model.requestDetail(17) }
                    Button("z18  ⌘8") { model.requestDetail(18) }
                    Spacer()
                }.padding(.horizontal, 12).padding(.bottom, 8)
                HStack {
                    Toggle("地铁示意线", isOn: $model.transitCartography)
                        .disabled(model.analysisBusy || model.captureAdmission.isBusy)
                        .onChange(of: model.transitCartography) { model.invalidateAnalysis() }
                    Toggle("蓝色铁路（排除青线） ⇧⌥⌘B", isOn: $model.blueRailwayOnly)
                        .keyboardShortcut("b", modifiers: [.command, .option, .shift])
                        .disabled(!model.transitCartography || model.analysisBusy || model.captureAdmission.isBusy)
                        .onChange(of: model.blueRailwayOnly) { model.invalidateAnalysis() }
                    Button(model.analysisBusy ? "抽离分析中…  ⌥⌘E" : "抽离铁路与车站  ⌥⌘E") { model.analysisRequested() }
                        .accessibilityIdentifier("appleMapExtractButton")
                        .disabled(model.line == nil || model.analysisBusy || model.captureAdmission.isBusy)
                    if model.analysisBusy {
                        Button("取消") { model.invalidateAnalysis() }
                    }
                    Button("导出抽离结果  ⇧⌥⌘E") {
                        prepareAnalysisExport()
                    }.disabled(model.analysisReport == nil)
                    if model.mode == .extracted {
                        Toggle("显示底图", isOn: $model.showAnalysisBasemap)
                        Toggle("构建线", isOn: $model.showAnalysisConstructed)
                    }
                    Spacer()
                }.padding(.horizontal, 12).padding(.bottom, 8)
                HStack {
                    Button("检查当前区间  ⇧⌘C") { model.startBatch(selectedOnly: true) }
                        .disabled(model.currentInput == nil || model.captureAdmission.isBusy || model.analysisBusy)
                    Button("检查当前线路  ⇧⌥⌘C") { model.startBatch() }
                        .disabled(model.line == nil || model.captureAdmission.isBusy || model.analysisBusy)
                    Button("暂停") { model.batch.pause() }.disabled(!model.batch.isRunning)
                    #if RAIL_DIAGNOSTICS
                    Button("重试当前区间失败") { if let id = model.currentInput?.id { model.batch.retryFailed(scope: [id]) } }
                        .disabled(model.captureAdmission.isBusy || model.analysisBusy || model.batch.failedCount == 0)
                    #else
                    Button("重试失败") { model.batch.retryFailed() }
                        .disabled(model.captureAdmission.isBusy || model.analysisBusy || model.batch.failedCount == 0)
                    #endif
                    Button("批量报告") {
                        do { filename = "jp-batch-inspection-report"; record = ViewRecord(data: try model.batch.reportData()); exporting = true }
                        catch { exportError = error.localizedDescription }
                    }.disabled(model.plan == nil)
                    Text("证据 \(model.batch.completedCount)/\(model.batch.totalCount) · 失败 \(model.batch.failedCount)")
                        .font(.caption.monospaced())
                    Spacer()
                }.padding(.horizontal, 12).padding(.bottom, 8)
                if let batchError = model.batch.lastError {
                    Text(batchError).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                ZStack {
                    InspectorMap(model: model)
                        .opacity(model.mode == .extracted ? 0 : 1)
                        .allowsHitTesting(model.mode != .extracted)
                    if model.mode == .extracted {
                        if let report = model.analysisReport {
                            AppleMapExtractionView(report: report, basemap: model.showAnalysisBasemap, constructed: model.showAnalysisConstructed)
                        } else {
                            ContentUnavailableView("尚未抽离当前视点", systemImage: "point.3.connected.trianglepath.dotted",
                                description: Text("选择详细视点后点击“抽离铁路与车站”。"))
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.mode == .extracted, let report = model.analysisReport {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("绿：Apple 像素候选 · 青：构建中心线（平滑） · 黄：Apple 车站 POI · 粉：构建站点")
                        Text(report.summary)
                        Text("仅比较有图像支持的区段；文字、道路/建筑竞争和缺失处留空。车站 POI 不等于平台中心。")
                        ForEach(report.stations, id: \.seed.id) { station in
                            Text("\(station.seed.name)：\(station.matches.count) 个 Apple 车站候选" +
                                (station.matches.first.map { String(format: " · 点位距离 %.1fm", $0.distance) } ?? "") + " · \(station.note)")
                        }
                    }.font(.caption).textSelection(.enabled).padding(.horizontal, 12).padding(.top, 6)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("搜索 ⌘F · 唯一线路确认 ↩ · 坐标 ⇧⌘G，定位 ↩ · 上一待检 ⇧⌘P · 下一待检 ⇧⌘N")
                    Text("对照模式 " + ComparisonMode.allCases.enumerated().map { "\($0.element.title) ⌘\($0.offset + 1)" }.joined(separator: " · "))
                    Text("详细缩放 z17 ⌘7 · z18 ⌘8 · z19 ⇧⌘8 · 首个详细视点 ⌘↖（Home）")
                    Text("视点 上/下 ⌥⌘←/→ · 站点 上/下 ⇧⌥⌘←/→ · 站点附近 ⌘9 · 区间 ⌘0 · 全线 ⇧⌘0")
                    Text("底图切换 ⌘B · 蓝色铁路 ⇧⌥⌘B · 视点证据 ⌥⌘S · 区间取证 ⇧⌘C · 线路取证 ⇧⌥⌘C")
                    Text("抽离 ⌥⌘E · 导出抽离 ⇧⌥⌘E · 导出视点 ⇧⌘S")
                }
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled).padding(.horizontal, 12).padding(.top, 6)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Search: Command F. Confirm unique line: Return. Coordinates: Shift Command G. Move camera: Return. Previous pending interval: Shift Command P. Next pending interval: Shift Command N. Detail zoom 17: Command 7. Zoom 18: Command 8. Zoom 19: Shift Command 8. First detailed viewpoint: Command Home. Previous or next viewpoint: Option Command Left or Right Arrow. Previous or next station: Shift Option Command Left or Right Arrow. Frame station: Command 9. Frame interval: Command 0. Frame line: Shift Command 0. Basemap peek: Command B. Blue railway: Shift Option Command B. Viewpoint evidence: Option Command S. Capture interval: Shift Command C. Capture line: Shift Option Command C. Extract: Option Command E. Export extraction: Shift Option Command E. Export viewpoint: Shift Command S.")
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.status).font(.caption.monospaced()).textSelection(.enabled)
                    if model.batch.isRunning {
                        Text(model.batch.status).textSelection(.enabled)
                    }
                    Text("批量证据保存：\(model.batch.outputURL.path)").textSelection(.enabled)
                    Text("批量取证与偏移候选不等于底图对齐结论；复核通过后才更新区间结论。").foregroundStyle(.secondary)
                    Text("蓝：包解码几何（含站点端点） · 青：显示几何 · 洋红：单线中心线平滑 · 橙：外部参考")
                    Text("直接对照底图铁路线；底图未画出的轨道无法判定。此预览未包含主程序的多线错位、共享走廊、连接与折叠。")
                        .foregroundStyle(.secondary)
                    if let exportError { Text(exportError).foregroundStyle(.red) }
                }.font(.caption).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 1000, minHeight: 650)
        .task { await model.load() }
        .focusedSceneValue(\.inspectorCommands, commands)
        .onAppear(perform: installCommands)
        .onChange(of: model.lineID) { _, _ in installCommands() }
        .onChange(of: model.stationIndex) { _, _ in installCommands() }
        .onChange(of: model.inspectionPointIndex) { _, _ in installCommands() }
        .onChange(of: model.filteredItems.map(\.id)) { _, _ in installCommands() }
        .onChange(of: model.mode) { _, _ in installCommands() }
        .onChange(of: model.analysisBusy) { _, _ in installCommands() }
        .onChange(of: model.captureAdmission.isBusy) { _, _ in installCommands() }
        .onChange(of: model.analysisReport != nil) { _, _ in installCommands() }
        .fileExporter(isPresented: $exporting, document: record, contentType: .json,
                      defaultFilename: filename) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .onChange(of: model.evidence?.name) { _, _ in
            guard let bundle = model.evidence else { return }
            exportingBundle = bundle
            evidenceDocument = EvidenceDocument(files: bundle.files)
            evidenceExport = true
        }
        .fileExporter(isPresented: $evidenceExport, document: evidenceDocument, contentType: .folder,
                      defaultFilename: exportingBundle?.name ?? (model.mode == .extracted ? "apple-map-extraction" : "jp-rail-evidence")) { result in
            switch result {
            case .success(let url):
                if let bundle = exportingBundle { model.recordEvidenceSuccess(bundle, paths: [url.path]) }
            case .failure(let error): exportError = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, UTType(filenameExtension: "geojson") ?? .json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                try model.importReference(data: Data(contentsOf: url))
            } catch { exportError = error.localizedDescription }
        }
    }

    private func prepareViewExport() {
        do {
            filename = "jp-rail-view"
            record = ViewRecord(data: try model.viewRecord())
            exporting = true
        } catch { exportError = error.localizedDescription }
    }

    private func prepareAnalysisExport() {
        do {
            exportingBundle = nil
            evidenceDocument = EvidenceDocument(files: try model.analysisFiles())
            evidenceExport = true
        } catch { exportError = error.localizedDescription }
    }

    private func selectUniqueFilteredLine() {
        let modalPresented = exporting || evidenceExport || importing
        guard !queueMode, !modalPresented,
              !model.captureAdmission.isBusy, !model.analysisBusy,
              model.filteredLines.count == 1,
              let line = model.filteredLines.first else { return }
        model.select(line.id)
        queryFocused = false
    }

    private func installCommands() {
        let busy = model.captureAdmission.isBusy || model.analysisBusy
        let viewpointCount = model.inspectionPoints.count
        let stationCount = model.line?.stations.count ?? 0
        commands.canNavigateViewpoint = viewpointCount > 0
        commands.canPreviousViewpoint = model.inspectionPointIndex > 0
        commands.canNextViewpoint = model.inspectionPointIndex + 1 < viewpointCount
        commands.canNavigateStation = stationCount > 0
        commands.canPreviousStation = model.stationIndex > 0
        commands.canNextStation = model.stationIndex + 1 < stationCount
        commands.canNavigatePending = !model.filteredItems.isEmpty
        commands.canUseLine = model.line != nil
        commands.canFocusInterval = model.currentInput != nil
        commands.canUseCurrentInterval = model.currentInput != nil && !busy
        commands.canUseCurrentLine = model.line != nil && !busy
        commands.canCaptureEvidence = model.canCaptureEvidence
        commands.canExtract = model.line != nil && !busy
        commands.canExportExtraction = model.analysisReport != nil
        commands.search = { self.queryFocused = true }
        commands.camera = { self.cameraFocused = true }
        commands.setMode = { self.model.mode = $0 }
        commands.requestDetail = { self.model.requestDetail($0) }
        commands.firstDetailedViewpoint = {
            self.model.inspectionPointIndex = 0
            self.model.navigateInspectionPoint(0)
        }
        commands.focusStation = { self.model.focusStation() }
        commands.focusInterval = { self.model.focusInterval() }
        commands.focusLine = { self.model.focusLine() }
        commands.togglePeek = { self.model.peek.toggle() }
        commands.previousViewpoint = { self.model.navigateInspectionPoint(-1) }
        commands.nextViewpoint = { self.model.navigateInspectionPoint(1) }
        commands.previousStation = { self.model.navigate(-1) }
        commands.nextStation = { self.model.navigate(1) }
        commands.previousPending = { self.model.navigateQueue(-1) }
        commands.nextPending = { self.model.navigateQueue(1) }
        commands.captureEvidence = { self.model.captureRequested() }
        commands.captureCurrentInterval = { self.model.startBatch(selectedOnly: true) }
        commands.captureCurrentLine = { self.model.startBatch() }
        commands.extract = { self.model.analysisRequested() }
        commands.exportExtraction = { self.prepareAnalysisExport() }
        commands.exportView = { self.prepareViewExport() }
    }
}

@MainActor @Observable
final class InspectorCommandBridge {
    var canNavigateViewpoint = false
    var canPreviousViewpoint = false
    var canNextViewpoint = false
    var canNavigateStation = false
    var canPreviousStation = false
    var canNextStation = false
    var canNavigatePending = false
    var canUseLine = false
    var canFocusInterval = false
    var canUseCurrentInterval = false
    var canUseCurrentLine = false
    var canCaptureEvidence = false
    var canExtract = false
    var canExportExtraction = false
    @ObservationIgnored var search: (@MainActor () -> Void)?
    @ObservationIgnored var camera: (@MainActor () -> Void)?
    @ObservationIgnored var setMode: (@MainActor (ComparisonMode) -> Void)?
    @ObservationIgnored var requestDetail: (@MainActor (Double) -> Void)?
    @ObservationIgnored var firstDetailedViewpoint: (@MainActor () -> Void)?
    @ObservationIgnored var focusStation: (@MainActor () -> Void)?
    @ObservationIgnored var focusInterval: (@MainActor () -> Void)?
    @ObservationIgnored var focusLine: (@MainActor () -> Void)?
    @ObservationIgnored var togglePeek: (@MainActor () -> Void)?
    @ObservationIgnored var previousViewpoint: (@MainActor () -> Void)?
    @ObservationIgnored var nextViewpoint: (@MainActor () -> Void)?
    @ObservationIgnored var previousStation: (@MainActor () -> Void)?
    @ObservationIgnored var nextStation: (@MainActor () -> Void)?
    @ObservationIgnored var previousPending: (@MainActor () -> Void)?
    @ObservationIgnored var nextPending: (@MainActor () -> Void)?
    @ObservationIgnored var captureEvidence: (@MainActor () -> Void)?
    @ObservationIgnored var captureCurrentInterval: (@MainActor () -> Void)?
    @ObservationIgnored var captureCurrentLine: (@MainActor () -> Void)?
    @ObservationIgnored var extract: (@MainActor () -> Void)?
    @ObservationIgnored var exportExtraction: (@MainActor () -> Void)?
    @ObservationIgnored var exportView: (@MainActor () -> Void)?
}

private struct InspectorCommandKey: FocusedValueKey {
    typealias Value = InspectorCommandBridge
}

extension FocusedValues {
    var inspectorCommands: InspectorCommandBridge? {
        get { self[InspectorCommandKey.self] }
        set { self[InspectorCommandKey.self] = newValue }
    }
}

struct InspectorCommands: Commands {
    @FocusedValue(\.inspectorCommands) private var bridge

    var body: some Commands {
        CommandMenu("Rail Inspection") {
            InspectorCommandItems(bridge: bridge)
        }
    }
}

struct EvidenceDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    var files: [String: Data]
    init(files: [String: Data]) { self.files = files }
    init(configuration: ReadConfiguration) throws { files = [:] }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(directoryWithFileWrappers: files.mapValues { FileWrapper(regularFileWithContents: $0) })
    }
}

private struct AppleMapExtractionView: View {
    let report: AppleMapExtractionReport
    let basemap: Bool
    let constructed: Bool

    var body: some View {
        Canvas { original, size in
            var context = original
            let scale = min(size.width / report.pixelSize.width, size.height / report.pixelSize.height)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.08, green: 0.10, blue: 0.13)))
            context.translateBy(x: (size.width - report.pixelSize.width * scale) / 2,
                                y: (size.height - report.pixelSize.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            if basemap {
                context.draw(Image(uiImage: report.image), in: CGRect(origin: .zero, size: report.pixelSize))
            }
            func draw(_ paths: [[CGPoint]], color: Color, dash: [CGFloat] = []) {
                for points in paths where points.count > 1 {
                    var path = Path()
                    path.move(to: points[0]); points.dropFirst().forEach { path.addLine(to: $0) }
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2 / scale, lineCap: .round, lineJoin: .round, dash: dash))
                }
            }
            if constructed { draw(report.constructed, color: .cyan, dash: [5 / scale, 4 / scale]) }
            draw(report.analysis.paths, color: .green)
            func dot(_ point: CGPoint, color: Color) {
                context.stroke(Path(ellipseIn: CGRect(x: point.x - 5 / scale, y: point.y - 5 / scale,
                    width: 10 / scale, height: 10 / scale)), with: .color(color), lineWidth: 2 / scale)
            }
            for candidate in report.platformCandidates {
                let color: Color = candidate.railMidpoint == nil ? .orange : .purple
                draw([candidate.polygon, candidate.axis], color: color)
                dot(candidate.midpoint, color: color)
                if let point = candidate.railMidpoint { dot(point, color: .purple) }
            }
            for station in report.stations {
                if constructed { dot(station.seedPixel, color: .pink) }
                for match in station.matches {
                    dot(match.pixel, color: .yellow)
                    context.draw(Text(match.name).font(.caption).foregroundStyle(.yellow),
                        at: CGPoint(x: match.pixel.x + 8 / scale, y: match.pixel.y), anchor: .leading)
                }
            }
        }
        .accessibilityLabel("Apple Maps 抽离图：\(report.analysis.paths.count) 段铁路候选；\(report.summary)")
    }
}

struct InspectorCommandItems: View {
    let bridge: InspectorCommandBridge?

    var body: some View {
        Group {
            Button("Search") { bridge?.search?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(bridge == nil)
            Button("Go to coordinates") { bridge?.camera?() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(bridge == nil)
            Divider()
            ForEach(Array(ComparisonMode.allCases.enumerated()), id: \.element.id) { index, mode in
                Button(mode.title) { bridge?.setMode?(mode) }
                    .keyboardShortcut(KeyEquivalent(String(index + 1).first!), modifiers: .command)
                    .disabled(bridge == nil)
            }
            Divider()
            Button("Detail z17") { bridge?.requestDetail?(17) }
                .keyboardShortcut("7", modifiers: .command)
                .disabled(bridge?.canUseLine != true)
            Button("Detail z18") { bridge?.requestDetail?(18) }
                .keyboardShortcut("8", modifiers: .command)
                .disabled(bridge?.canUseLine != true)
            Button("Detail z19") { bridge?.requestDetail?(19) }
                .keyboardShortcut("8", modifiers: [.command, .shift])
                .disabled(bridge?.canUseLine != true)
            Button("First detailed viewpoint") { bridge?.firstDetailedViewpoint?() }
                .keyboardShortcut(.home, modifiers: .command)
                .disabled(bridge?.canNavigateViewpoint != true)
            Button("Frame station") { bridge?.focusStation?() }
                .keyboardShortcut("9", modifiers: .command)
                .disabled(bridge?.canNavigateStation != true)
            Button("Frame next interval") { bridge?.focusInterval?() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(bridge?.canFocusInterval != true)
            Button("Frame full line") { bridge?.focusLine?() }
                .keyboardShortcut("0", modifiers: [.command, .shift])
                .disabled(bridge?.canUseLine != true)
            Button("Toggle basemap peek") { bridge?.togglePeek?() }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(bridge == nil)
            Divider()
            Button("Previous viewpoint") { bridge?.previousViewpoint?() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(bridge?.canPreviousViewpoint != true)
            Button("Next viewpoint") { bridge?.nextViewpoint?() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(bridge?.canNextViewpoint != true)
            Button("Previous station") { bridge?.previousStation?() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option, .shift])
                .disabled(bridge?.canPreviousStation != true)
            Button("Next station") { bridge?.nextStation?() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option, .shift])
                .disabled(bridge?.canNextStation != true)
            Button("Previous pending interval") { bridge?.previousPending?() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(bridge?.canNavigatePending != true)
            Button("Next pending interval") { bridge?.nextPending?() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(bridge?.canNavigatePending != true)
            Divider()
            Button("Export same-view evidence") { bridge?.captureEvidence?() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(bridge?.canCaptureEvidence != true)
            Button("Capture current interval") { bridge?.captureCurrentInterval?() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(bridge?.canUseCurrentInterval != true)
            Button("Capture current line") { bridge?.captureCurrentLine?() }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                .disabled(bridge?.canUseCurrentLine != true)
            Button("Extract railway and stations") { bridge?.extract?() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(bridge?.canExtract != true)
            Button("Export extraction") { bridge?.exportExtraction?() }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                .disabled(bridge?.canExportExtraction != true)
            Button("Export viewpoint record") { bridge?.exportView?() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(bridge?.canNavigateStation != true)
        
        }
    }
}
