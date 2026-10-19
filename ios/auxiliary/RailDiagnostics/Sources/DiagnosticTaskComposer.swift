import RailCore
import RailInspection
import SwiftUI
import UniformTypeIdentifiers

/// People and agents produce the same immutable request; this form does not
/// maintain a second capture workflow.
struct DiagnosticTaskComposer: View {
    @Environment(\.dismiss) private var dismiss
    let start: (DiagnosticRequest) -> Void
    @State private var workspace = DiagnosticRequest.Workspace.alignment
    @State private var action = DiagnosticRequest.Action.capture
    @State private var requestID = "task-" + String(UUID().uuidString.prefix(8)).lowercased()
    @State private var directory = Self.newDirectory()
    @State private var lineID = ""
    @State private var search = ""
    @State private var intervals = ""
    @State private var stations = ""
    @State private var inputPath = ""
    @State private var packagePath = ""
    @State private var patternID = ""
    @State private var reviewDay = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
    @State private var zoom = 18.0
    @State private var width = 1024
    @State private var height = 768
    @State private var dark = false
    @State private var basemapStyle = DiagnosticCaptureSettings.BasemapStyle.standard
    @State private var basemap = true
    @State private var display = true
    @State private var smooth = true
    @State private var captureLimit = ""
    @State private var viewpointIDs = ""
    @State private var lines: [CompactPackage.Headers.Line] = []
    @State private var error: String?
    @State private var importing = false
    @State private var retainingInput = false
    @State private var inputRetentionFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    Picker("Workspace", selection: $workspace) {
                        Text("Alignment & screenshots").tag(DiagnosticRequest.Workspace.alignment)
                        Text("Physical route solve").tag(DiagnosticRequest.Workspace.route)
                        Text("Through-service history").tag(DiagnosticRequest.Workspace.through)
                    }.disabled(retainingInput || importing)
                    Picker("Action", selection: $action) {
                        Text("Prepare only").tag(DiagnosticRequest.Action.prepare)
                        switch workspace {
                        case .alignment: Text("Capture screenshots").tag(DiagnosticRequest.Action.capture)
                        case .route: Text("Solve journeys").tag(DiagnosticRequest.Action.solve)
                        case .through: Text("Inspect selected date").tag(DiagnosticRequest.Action.inspect)
                        }
                    }.disabled(retainingInput || importing)
                    TextField("Task ID", text: $requestID)
                    TextField("Session directory · absolute path", text: $directory)
                        .font(.callout.monospaced())
                    Text("Each task keeps its request, progress, screenshots and results together. Use a new directory when requirements change.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                switch workspace {
                case .alignment: alignmentFields
                case .route:
                    Section("Journeys") {
                        TextField("Input JSON · absolute path", text: $inputPath).font(.callout.monospaced()).disabled(retainingInput)
                        Button("Choose journeys JSON…") { importing = true }.disabled(retainingInput)
                        if retainingInput { ProgressView("Retaining selected input…") }
                        Text("Only journeys in this file are solved.").font(.caption).foregroundStyle(.secondary)
                    }
                case .through:
                    Section("Historical scope") {
                        TextField("Exact pattern ID", text: $patternID)
                        TextField("Review date · YYYY-MM-DD", text: $reviewDay)
                    }
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled) } }
            }
            .formStyle(.grouped)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle("New diagnostic task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel  Esc") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start task  ⌘↩", action: submit).keyboardShortcut(.return, modifiers: .command)
                        .accessibilityLabel("Start task, Command Return").disabled(retainingInput || inputRetentionFailed)
                }
            }
        }
        .frame(idealWidth: 720, idealHeight: 780)
        .onChange(of: workspace) { _, value in
            action = value == .alignment ? .capture : value == .route ? .solve : .inspect
            error = nil
            inputRetentionFailed = false
        }
        .onChange(of: packagePath) { _, _ in inputRetentionFailed = false }
        .onChange(of: inputPath) { _, _ in inputRetentionFailed = false }
        .task(id: packagePath) {
            lines = []
            error = nil
            let path = packagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = path.isEmpty ? Bundle.main.url(forResource: "jp-2025", withExtension: "json") : URL(fileURLWithPath: path)
            guard let url else { error = "Missing bundled jp-2025.json."; return }
            do {
                let loaded = try await Task.detached { try CompactPackage.Headers.load(contentsOf: url).lines }.value
                guard !Task.isCancelled else { return }
                lines = loaded
            } catch { if !Task.isCancelled { self.error = DiagnosticSession.explain(error) } }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let selectedWorkspace = workspace
                retainingInput = true
                inputRetentionFailed = false
                error = nil
                Task {
                    defer { retainingInput = false }
                    do {
                        let retained = try await RouteWorkbenchModel.importForTask(url).path
                        if selectedWorkspace == .alignment { packagePath = retained } else { inputPath = retained }
                    } catch {
                        inputRetentionFailed = true
                        self.error = DiagnosticSession.explain(error)
                    }
                }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }

    private var alignmentFields: some View {
        Group {
            Section("Railway package") {
                TextField("Optional compact JSON · absolute path", text: $packagePath)
                    .font(.callout.monospaced()).disabled(retainingInput)
                Button("Choose candidate compact JSON…") { importing = true }.disabled(retainingInput)
                if retainingInput { ProgressView("Retaining selected package…") }
                Text("Leave blank to use bundled jp-2025.json. A selected package supplies this task's railway geometry.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Owning railway") {
                TextField("Search line name, operator or ID", text: $search)
                if !search.isEmpty {
                    ForEach(Array(matches.prefix(6)), id: \.id) { line in
                        Button { lineID = line.id; search = "" } label: {
                            VStack(alignment: .leading) {
                                Text(line.name + " · " + (line.operatorShort ?? line.operator ?? ""))
                                Text(line.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                TextField("Exact line ID", text: $lineID).font(.callout.monospaced())
                TextField("Intervals · optional, zero-based, comma-separated", text: $intervals)
                TextField("Station IDs · optional, comma-separated", text: $stations)
                Text("Leave intervals and stations empty for the complete line. Cameras follow this railway, including both station approaches and interval ends.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Automatic screenshots") {
                Picker("Basemap", selection: $basemapStyle) {
                    Text("Standard").tag(DiagnosticCaptureSettings.BasemapStyle.standard)
                    Text("Imagery").tag(DiagnosticCaptureSettings.BasemapStyle.imagery)
                }
                Stepper(value: $zoom, in: 10...20, step: 0.5) { Text("Zoom \(zoom, specifier: "%.1f") · 256-point tiles") }
                HStack {
                    TextField("Width", value: $width, format: .number)
                    Text("×")
                    TextField("Height", value: $height, format: .number)
                    Text("points · 1×").foregroundStyle(.secondary)
                }
                Toggle("Dark basemap", isOn: $dark)
                Toggle("Original basemap", isOn: $basemap)
                Toggle("Display geometry", isOn: $display)
                Toggle("Smoothed geometry", isOn: $smooth)
                LabeledContent("Viewpoint IDs") {
                    TextField("Optional exact IDs, comma separated", text: $viewpointIDs)
                }
                TextField("Optional capture limit · blank captures all pending views", text: $captureLimit)
                Text("The app plans overlapping views at this scale and captures them serially. Failed or unfinished views remain available to resume.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var matches: [CompactPackage.Headers.Line] {
        lines.filter { [$0.id, $0.name, $0.operator ?? ""].contains { $0.localizedCaseInsensitiveContains(search) } }
    }

    private func submit() {
        guard !retainingInput, !inputRetentionFailed else { return }
        do {
            let indices: [Int]?
            let limit: Int?
            if workspace == .alignment {
                indices = try parseIndices()
                let trimmedLimit = captureLimit.trimmingCharacters(in: .whitespacesAndNewlines)
                limit = Int(trimmedLimit)
                if !trimmedLimit.isEmpty && limit == nil { throw DiagnosticError.invalidRequest("Capture limit must be an integer.") }
            } else {
                indices = nil
                limit = nil
            }
            var modes: [DiagnosticCaptureSettings.OutputMode] = []
            if basemap { modes.append(.basemap) }; if display { modes.append(.display) }; if smooth { modes.append(.smooth) }
            let settings = DiagnosticCaptureSettings(zoom: zoom, width: width, height: height,
                appearance: dark ? .dark : .light, basemapStyle: basemapStyle, outputModes: modes)
            let selectedStations = stations.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let request = DiagnosticRequest(requestID: requestID.trimmingCharacters(in: .whitespacesAndNewlines),
                workspace: workspace, action: action, sessionDirectory: directory.trimmingCharacters(in: .whitespacesAndNewlines),
                lineID: workspace == .alignment ? lineID.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                intervalIndices: workspace == .alignment ? indices : nil,
                stationIDs: workspace == .alignment && !selectedStations.isEmpty ? selectedStations : nil,
                inputPath: workspace == .alignment
                    ? (packagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : packagePath.trimmingCharacters(in: .whitespacesAndNewlines))
                    : workspace == .route ? inputPath.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                patternID: workspace == .through ? patternID : nil,
                reviewDay: workspace == .through ? reviewDay : nil,
                captureLimit: workspace == .alignment ? limit : nil,
                viewpointIDs: workspace == .alignment && !viewpointIDs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? viewpointIDs.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } : nil,
                captureSettings: workspace == .alignment ? settings : nil)
            try request.validate()
            start(request); dismiss()
        } catch { self.error = DiagnosticSession.explain(error) }
    }

    private func parseIndices() throws -> [Int]? {
        guard !intervals.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try intervals.split(separator: ",", omittingEmptySubsequences: false).map {
            guard let value = Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw DiagnosticError.invalidRequest("Interval indices must be comma-separated integers.")
            }
            return value
        }
    }

    private static func newDirectory() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("RailDiagnostics/Sessions/" + UUID().uuidString.lowercased()).path
    }
}
