import QuickLook
import RailInspection
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct RailDiagnosticsApp: App {
    var body: some Scene {
        WindowGroup {
            DiagnosticWorkspaceView()
                .dynamicTypeSize(AppTypographyPolicy.supportedSizes)
        }
        .commands { UnifiedDiagnosticCommands() }
    }
}

enum DiagnosticWorkspace: String, CaseIterable, Identifiable {
    case tasks = "Tasks & evidence", alignment = "Alignment", route = "Physical routes", through = "Through history"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .tasks: "checklist"; case .alignment: "point.topleft.down.to.point.bottomright.curvepath"; case .route: "arrow.triangle.branch"; case .through: "calendar" }
    }
    var shortcut: String { "⌃⌘" + String((Self.allCases.firstIndex(of: self) ?? 0) + 1) }
}

struct DiagnosticWorkspaceView: View {
    @State private var session = DiagnosticSession()
    @State private var workspace = DiagnosticWorkspace.tasks
    @State private var commands = DiagnosticTaskCommandBridge()
    private enum Presentation: Equatable { case compose, importRequest, screenshot(URL) }
    @State private var presentation: Presentation?
    @State private var pendingRequest: DiagnosticRequest?
    @State private var recentRequests: [DiagnosticRequest] = []
    @State private var notice: String?
    @State private var reviewCandidate = ""
    @State private var reviewConclusion = "insufficientEvidence"
    @State private var reviewNote = ""
    @State private var reviewPaths = ""
    @State private var candidateSearch = ""

    private var composing: Bool {
        get { presentation == .compose }
        nonmutating set { if newValue { presentation = .compose } else if composing { presentation = nil } }
    }
    private var importing: Bool {
        get { presentation == .importRequest }
        nonmutating set { if newValue { presentation = .importRequest } else if importing { presentation = nil } }
    }
    private var previewImage: URL? {
        get {
            guard let presentation else { return nil }
            if case .screenshot(let url) = presentation { return url }
            return nil
        }
        nonmutating set {
            if let newValue { presentation = .screenshot(newValue) }
            else if previewImage != nil { presentation = nil }
        }
    }
    private var busy: Bool { session.running || session.workspaceBusy }
    private var canRun: Bool { !busy && presentation == nil && (pendingRequest != nil || session.request != nil) }

    var body: some View {
        VStack(spacing: 0) {
            workspaceBar
            if let notice {
                Label(notice, systemImage: "info.circle").font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 10)
            }
            Divider()
            Group {
                switch workspace {
                case .tasks: taskDashboard
                case .alignment: InspectorView(model: session.alignment).id(session.identity)
                case .route: RouteWorkbenchContentView(model: session.route).id(session.identity)
                case .through: WorkbenchView(store: session.through).id(session.identity)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            statusBar
        }
        .focusedSceneValue(\.diagnosticTaskCommands, commands)
        .task(id: session.identity) {
            installCommands()
            await session.open()
            installCommands()
        }
        .onAppear {
            recentRequests = Self.readRecentRequests()
            installCommands()
        }
        .onChange(of: busy) { _, _ in installCommands() }
        .onChange(of: session.canPause) { _, _ in installCommands() }
        .onChange(of: session.alignment.batch.isRunning) { _, _ in session.refreshWorkspaceCaptureResult() }
        .onChange(of: session.alignment.batch.evidenceRevision) { _, _ in session.refreshWorkspaceCaptureResult() }
        .onChange(of: presentation) { _, _ in installCommands() }
        .onChange(of: pendingRequest) { _, _ in installCommands() }
        .sheet(isPresented: Binding(get: { composing }, set: { composing = $0 })) { DiagnosticTaskComposer(start: start) }
        .quickLookPreview(Binding(get: { previewImage }, set: { previewImage = $0 }))
        .onOpenURL(perform: loadRequest)
        .fileImporter(isPresented: Binding(get: { importing }, set: { importing = $0 }), allowedContentTypes: [.json]) { result in
            // The picker has finished. Other presentations still block opens.
            if importing { presentation = nil }
            switch result {
            case .success(let url): loadRequest(url)
            case .failure(let error): notice = DiagnosticSession.explain(error)
            }
        }
    }

    private var workspaceBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { brand; workspacePicker; taskActions }
            VStack(alignment: .leading, spacing: 10) { HStack { brand; Spacer(); taskActions }; workspacePicker }
            VStack(alignment: .leading, spacing: 10) { brand; workspacePicker; taskActions }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private var brand: some View {
        Label("Rail Diagnostics", systemImage: "tram.fill").font(.headline).fixedSize()
    }

    private var workspacePicker: some View {
        Picker("Workspace", selection: $workspace) {
            ForEach(DiagnosticWorkspace.allCases) { Text($0.rawValue + "  " + $0.shortcut).tag($0) }
        }.pickerStyle(.segmented).disabled(busy)
            .accessibilityHint(busy ? "Wait for the current operation to settle before switching workspaces." : "Control Command 1 through 4 switch workspace.")
    }

    private var taskActions: some View {
        HStack(spacing: 8) {
            Button { composing = true } label: { Label("New task  ⌃⌘N", systemImage: "plus") }
                .disabled(busy || presentation != nil).accessibilityLabel("New task, Control Command N")
            Button { importing = true } label: { Label("Open task  ⇧⌘O", systemImage: "folder") }
                .disabled(busy || presentation != nil).accessibilityLabel("Open task request, Shift Command O")
        }.buttonStyle(.bordered).fixedSize()
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if busy { ProgressView().controlSize(.small) }
            Label(statusTitle, systemImage: statusSymbol).font(.callout.weight(.medium))
            Text(session.request?.requestID ?? "No active task").font(.caption.monospaced()).lineLimit(1)
            if let request = session.request, request.workspace == .alignment {
                let settings = request.normalizedCaptureSettings
                Text("z\(settings.zoom, specifier: "%.1f") · \(settings.width)×\(settings.height)").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if busy {
                Button(session.canPause ? "Pause  Esc" : "Finishing operation…") { session.pause() }
                    .disabled(!session.canPause)
                    .accessibilityLabel("Pause current operation, Escape")
            } else {
                Button("\(pendingRequest == nil ? "Run / resume" : "Run request")  ⌘↩", action: run)
                    .disabled(!canRun).accessibilityLabel("Run or resume task, Command Return")
            }
        }.padding(.horizontal, 16).padding(.vertical, 9).background(.bar)
    }

    private var taskDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tasks & evidence").font(.title.bold())
                        Text("One request. Exact scope. Native evidence.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if session.request != nil {
                        Button("Copy result path") { UIPasteboard.general.string = session.outputPath; notice = "Result path copied." }
                            .buttonStyle(.bordered)
                    }
                }
                if session.state == "failed", session.request == nil {
                    Label(session.message, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
                }
                if let pendingRequest {
                    requestCard(pendingRequest, title: "Ready to run")
                } else if let request = session.request {
                    requestCard(request, title: statusTitle)
                } else {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Create a diagnostic task", systemImage: "plus.circle").font(.title3.weight(.semibold))
                            Text("Choose a railway and screenshot scale, solve a journey file, or inspect a through-service date.")
                                .foregroundStyle(.secondary)
                            Button("New task  ⌃⌘N") { composing = true }.buttonStyle(.borderedProminent)
                            Text("Open task  ⇧⌘O previews a request JSON. Open a request with Rail Diagnostics to preview it in the existing window, then Run  ⌘↩.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }
                }
                if session.request != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Progress").font(.headline)
                        Text(session.message).textSelection(.enabled)
                        if session.request?.workspace == .alignment {
                            HStack(spacing: 24) {
                                count("Captured", session.alignmentSummary.capturedCount)
                                count("Pending", session.alignmentSummary.pendingCount)
                                count("Failed", session.alignmentSummary.failedCount)
                            }
                        }
                        Text(session.outputPath).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if let request = session.request, request.workspace == .alignment {
                        DiagnosticCaptureGallery(indexPath: request.sessionDirectory + "/capture-index.json",
                                                 revision: session.evidenceRevision,
                                                 controlsEnabled: !busy && presentation == nil,
                                                 commands: commands,
                                                 preview: { previewImage = $0 })
                    }
                    evidenceSection
                    if !session.candidates.isEmpty { reviewSection }
                }
                if !recentRequests.isEmpty {
                    Divider()
                    Text("Recent tasks").font(.headline)
                    ForEach(recentRequests, id: \.sessionDirectory) { request in
                        Button {
                            pendingRequest = request; notice = nil
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(request.requestID).font(.callout.weight(.medium))
                                    Text(summary(request)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }.buttonStyle(.plain).disabled(busy)
                    }
                }
                Text("Evidence collection and reviewer conclusions are separate. Main is the final production composition check.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 1120, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private func requestCard(_ request: DiagnosticRequest, title: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Label(title, systemImage: "doc.text").font(.headline); Spacer(); Text(request.workspace.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }
                Text(request.requestID).font(.title3.weight(.semibold)).textSelection(.enabled)
                Text(summary(request)).font(.callout.monospaced()).textSelection(.enabled)
                if request.workspace == .alignment {
                    Text("Package: " + (request.inputPath ?? "Bundled jp-2025.json"))
                        .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    let settings = request.normalizedCaptureSettings
                    Text("Zoom \(settings.zoom, specifier: "%.1f") · \(settings.width) × \(settings.height) pt · \(settings.basemapStyle.rawValue) · \(settings.appearance.rawValue) · \(settings.outputModes.map(\.rawValue).joined(separator: ", "))")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text(request.sessionDirectory).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button("Run / resume  ⌘↩", action: run).buttonStyle(.borderedProminent).disabled(!canRun)
                    Button("Copy request JSON") { copyRequest(request) }.buttonStyle(.bordered)
                }
                DisclosureGroup("Agent request") {
                    Text(Self.requestText(request)).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    Text("Launch with --diagnostic-request /absolute/request.json. Read run-status.json while active, then result.json and capture-index.json.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Evidence files").font(.headline)
            ForEach(session.evidence, id: \.self) { path in
                HStack(alignment: .top) {
                    Image(systemName: "doc")
                    Text(path).font(.caption.monospaced()).textSelection(.enabled)
                    Spacer()
                    Button("Copy path") { UIPasteboard.general.string = path }.buttonStyle(.borderless)
                }
            }
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review observations · \(session.reviewNotes.count) / \(session.candidates.count)").font(.headline)
            GroupBox("Record an observation") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Candidate", selection: $reviewCandidate) {
                        Text("Choose candidate").tag("")
                        ForEach(session.candidates) { Text($0.id).tag($0.id) }
                    }
                    Picker("Conclusion", selection: $reviewConclusion) {
                        Text("Needs repair").tag("needsRepair")
                        Text("No issue observed").tag("noIssueObserved")
                        Text("Insufficient evidence").tag("insufficientEvidence")
                    }
                    TextField("Observation and limits", text: $reviewNote, axis: .vertical).lineLimit(2...5)
                    TextField("Evidence file paths · one absolute path per line", text: $reviewPaths, axis: .vertical)
                        .lineLimit(2...4).font(.callout.monospaced())
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("Save observation  ⌃⌘S") {
                        session.saveReview(candidateID: reviewCandidate, conclusion: reviewConclusion, note: reviewNote, paths: reviewPaths)
                    }.keyboardShortcut("s", modifiers: [.command, .control]).disabled(busy || presentation != nil || reviewCandidate.isEmpty)
                    Text(session.reviewMessage).font(.caption).textSelection(.enabled)
                }.padding(8)
            }
            TextField("Filter review candidates", text: $candidateSearch).textFieldStyle(.roundedBorder)
            ForEach(session.candidates.filter { candidateSearch.isEmpty || $0.id.localizedCaseInsensitiveContains(candidateSearch) || $0.category.localizedCaseInsensitiveContains(candidateSearch) }) { candidate in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(candidate.category).font(.callout.weight(.semibold))
                        Spacer()
                        Text(session.reviewNotes[candidate.id]?.conclusion ?? "Pending review").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(candidate.id).font(.caption.monospaced()).textSelection(.enabled)
                    Text(candidate.note).font(.caption).foregroundStyle(.secondary)
                    if let distance = candidate.measuredMetres { Text(String(format: "Endpoint separation %.2f m", distance)).font(.caption) }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func count(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(value, format: .number).font(.title2.monospacedDigit()); Text(title).font(.caption).foregroundStyle(.secondary) }
    }
    private var statusTitle: String {
        if busy && !["preparing", "running"].contains(session.state) { return "Workspace operation" }
        return switch session.state {
        case "interactive": "Ready"
        case "preparing": "Preparing"
        case "running": "Running"
        case "prepared": "Prepared"
        case "partial": "Partial evidence"
        case "evidenceReady": "Evidence ready · review pending"
        case "paused": "Paused"
        case "failed": "Task failed"
        default: session.state
        }
    }
    private var statusSymbol: String { session.state == "failed" ? "exclamationmark.triangle" : busy ? "clock" : session.state == "evidenceReady" ? "doc.text.magnifyingglass" : "circle" }
    private func summary(_ request: DiagnosticRequest) -> String {
        switch request.workspace {
        case .alignment:
            let scope = request.intervalIndices.map { " · intervals " + $0.map(String.init).joined(separator: ", ") }
                ?? (request.stationIDs == nil ? " · complete line" : " · station approaches")
            return (request.lineID ?? "") + scope + (request.viewpointIDs.map { " · \($0.count) exact viewpoints" } ?? "") + (request.stationIDs.map { " · stations " + $0.joined(separator: ", ") } ?? "")
        case .route: return request.inputPath ?? ""
        case .through: return (request.patternID ?? "") + " · " + (request.reviewDay ?? "")
        }
    }
    private func start(_ request: DiagnosticRequest) {
        guard !busy else { return }
        presentation = nil
        pendingRequest = nil; notice = nil; reviewCandidate = ""; reviewNote = ""; reviewPaths = ""
        recentRequests.removeAll { $0.sessionDirectory == request.sessionDirectory }
        recentRequests.insert(request, at: 0); recentRequests = Array(recentRequests.prefix(12))
        if let data = try? JSONEncoder().encode(recentRequests) { UserDefaults.standard.set(data, forKey: "RailDiagnostics.recentRequests") }
        session = DiagnosticSession(request: request); workspace = .tasks
        installCommands()
    }
    private func loadRequest(_ url: URL) {
        do {
            guard !busy, presentation == nil else {
                throw DiagnosticError.invalidRequest("Finish the current operation and close any open dialog before opening another task. The current task is unchanged.")
            }
            guard url.isFileURL, url.pathExtension.lowercased() == "json" else {
                throw DiagnosticError.invalidRequest("Open a local request file with the .json extension.")
            }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let request = try JSONDecoder().decode(DiagnosticRequest.self, from: Data(contentsOf: url))
            try request.validate()
            start(request)
        } catch {
            notice = DiagnosticSession.explain(error)
        }
    }
    private func run() {
        guard canRun, let request = pendingRequest ?? session.request else { return }
        start(request)
    }
    private func copyRequest(_ request: DiagnosticRequest) { UIPasteboard.general.string = Self.requestText(request); notice = "Request JSON copied." }
    private static func requestText(_ request: DiagnosticRequest) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? String(decoding: encoder.encode(request), as: UTF8.self)) ?? ""
    }
    private static func readRecentRequests() -> [DiagnosticRequest] {
        guard let data = UserDefaults.standard.data(forKey: "RailDiagnostics.recentRequests") else { return [] }
        return (try? JSONDecoder().decode([DiagnosticRequest].self, from: data)) ?? []
    }
    private func captureFromWorkspace(lineID: String, intervalIndex: Int?) {
        guard !busy, presentation == nil else { return }
        do {
            let settings: DiagnosticCaptureSettings
            if let request = session.request, request.workspace == .alignment { settings = request.normalizedCaptureSettings }
            else { settings = .init(zoom: session.alignment.cameraRecord["zoom256"] ?? 17) }
            try settings.validate()
            let id = "capture-" + String(UUID().uuidString.prefix(8)).lowercased()
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let request = DiagnosticRequest(requestID: id, workspace: .alignment, action: .capture,
                sessionDirectory: base.appendingPathComponent("RailDiagnostics/Sessions/" + id).path,
                lineID: lineID, intervalIndices: intervalIndex.map { [$0] },
                inputPath: session.request?.workspace == .alignment ? session.request?.inputPath : nil,
                captureSettings: settings)
            start(request)
        } catch { notice = DiagnosticSession.explain(error); workspace = .tasks }
    }

    private func installCommands() {
        commands.canCreate = !busy && presentation == nil
        commands.canRun = canRun
        commands.canPause = session.canPause && presentation == nil
        commands.canSwitch = !busy && presentation == nil
        commands.canUseWorkspaceCommands = !busy && presentation == nil
        session.alignment.captureTaskRequested = { lineID, interval in captureFromWorkspace(lineID: lineID, intervalIndex: interval) }
        session.route.solveTaskRequested = { input in
            guard !busy, presentation == nil else { return }
            let id = "route-" + String(UUID().uuidString.prefix(8)).lowercased()
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            start(DiagnosticRequest(requestID: id, workspace: .route, action: .solve,
                sessionDirectory: base.appendingPathComponent("RailDiagnostics/Sessions/" + id).path,
                inputPath: input.path))
        }
        commands.newTask = { composing = true }
        commands.openTask = { importing = true }
        commands.runTask = run
        commands.pauseTask = { session.pause() }
        commands.switchWorkspace = { index in
            guard DiagnosticWorkspace.allCases.indices.contains(index), !busy else { return }
            workspace = DiagnosticWorkspace.allCases[index]
        }
    }
}
