import SwiftUI
import UniformTypeIdentifiers
import WorkbenchCore
import Observation

struct WorkbenchJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct WorkbenchView: View {
    @Bindable var store: WorkbenchStore
    @State private var importing = false
    @State private var importKind: ImportKind = .workdoc
    @State private var exportFile: WorkbenchJSONDocument?
    @State private var exporting = false
    @State private var exportName = "through-workdoc"
    @State private var draft: PatchDraft?
    @State private var showingInspectionPlan = false
    @State private var reviewDateInput = "2026-10-10"
    @State private var comparisonDateInput = "2005-01-01"
    @State private var commands = ThroughWorkbenchCommandBridge()
    @State private var searchPresented = false

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedID) {
                Section("Patterns on \(store.dayString)") {
                    ForEach(store.filteredPatterns) { pattern in
                        NavigationLink(value: pattern.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pattern.name).font(.headline)
                                Text("\(pattern.id) · \(pattern.statusLabel)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Through Workbench")
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
            .searchable(
                text: $store.search,
                isPresented: $searchPresented,
                prompt: "Name, pattern ID or service code")
            .overlay {
                if store.snapshot != nil && store.filteredPatterns.isEmpty {
                    ContentUnavailableView.search(text: store.search)
                }
            }
        } detail: {
            VStack(spacing: 0) {
                dateControls
                Divider()
                if let pattern = store.selection {
                    PatternDetailView(pattern: pattern, snapshot: store.snapshot, day: store.dayString) {
                        draft = PatchDraft(patternID: pattern.id, from: store.dayString)
                    }
                } else {
                    ReviewOverviewView(snapshot: store.snapshot, select: { store.selectedID = $0 })
                }
                Divider()
                HStack {
                    if store.isBusy { ProgressView().controlSize(.small) }
                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.horizontal).padding(.vertical, 8)
            }
            .navigationTitle(store.selection?.name ?? "Historical review")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        ForEach(ImportKind.allCases) { kind in
                            Button(kind == .workdoc ? "\(kind.rawValue)  ⌘O" : kind.rawValue) { importKind = kind; importing = true }
                        }
                    } label: { Label("Import JSON", systemImage: "square.and.arrow.down") }
                    .disabled(store.isBusy)
                    Menu {
                        Button("Working document  ⌥⌘E") { prepareExport(.workdoc) }
                        Button("Expanded catalog on \(store.dayString)  ⇧⌥⌘E") { prepareExport(.catalog) }
                        Button("检查计划") { prepareExport(.inspectionPlan) }
                            .disabled(store.inspectionPlan == nil || store.isInspecting)
                    } label: { Label("Export JSON", systemImage: "square.and.arrow.up") }
                    .disabled(store.snapshot == nil || store.isBusy)
                    Button { draft = .new(on: store.dayString) } label: { Label("Add pattern  ⌘N", systemImage: "plus") }
                        .keyboardShortcut("n", modifiers: .command)
                        .disabled(store.snapshot == nil || store.isBusy)
                    Button { store.selectedID = nil } label: { Label("Review overview  ⌘1", systemImage: "checklist") }
                        .keyboardShortcut("1", modifiers: .command)
                    Button { showingInspectionPlan = true } label: { Label("检查计划", systemImage: "list.bullet.clipboard") }
                        .disabled(store.snapshot == nil)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Search ⌘F · Previous pattern ⌥⌘← · Next pattern ⌥⌘→ · Import working document ⌘O")
                Text("Add pattern ⌘N · Overview ⌘1 · Export document ⌥⌘E · Export catalog ⇧⌥⌘E · Apply date field ↩")
            }
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(.bar)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Search: Command F. Previous pattern: Option Command Left Arrow. Next pattern: Option Command Right Arrow. Import working document: Command O. Add pattern: Command N. Review overview: Command 1. Export working document: Option Command E. Export catalog: Shift Option Command E. Apply date field: Return.")
        }
        .task(id: "\(store.dayString)/\(store.comparisonString)") {
            if store.snapshotKey != "\(store.dayString)/\(store.comparisonString)" { await store.refresh() }
        }
        .onChange(of: store.dayString) { _, value in reviewDateInput = value }
        .onChange(of: store.comparisonString) { _, value in comparisonDateInput = value }
        .focusedSceneValue(\.throughWorkbenchCommands, commands)
        .onAppear {
            reviewDateInput = store.dayString
            comparisonDateInput = store.comparisonString
            installCommands()
        }
        .onChange(of: store.selectedID) { _, _ in installCommands() }
        .onChange(of: store.filteredPatterns.map(\.id)) { _, _ in installCommands() }
        .onChange(of: store.isBusy) { _, _ in installCommands() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): Task { await store.importFile(url, kind: importKind) }
            case .failure(let error): store.report(error)
            }
        }
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: .json, defaultFilename: exportName) { result in
            if case .failure(let error) = result { store.report(error) }
        }
        .sheet(item: $draft) { draft in
            PatchEditorView(store: store, initial: draft)
                .dynamicTypeSize(.xSmall ... .xLarge)
        }
        .sheet(isPresented: $showingInspectionPlan) {
            InspectionPlanView(store: store, export: { prepareExport(.inspectionPlan) })
                .dynamicTypeSize(.xSmall ... .xLarge)
        }
        .alert("Needs attention", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var dateControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) { dates }
            VStack(alignment: .leading, spacing: 12) { dates }
        }
        .padding()
        .environment(\.calendar, Calendar(identifier: .gregorian))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
    }

    @ViewBuilder private var dates: some View {
        VStack(alignment: .leading) {
            Text("Review date (YYYY-MM-DD)").font(.caption)
            TextField("Review date", text: $reviewDateInput).textFieldStyle(.roundedBorder)
                .onSubmit(applyDates)
        }
        VStack(alignment: .leading) {
            Text("Compare with (YYYY-MM-DD)").font(.caption)
            TextField("Comparison date", text: $comparisonDateInput).textFieldStyle(.roundedBorder)
                .onSubmit(applyDates)
        }
        Button("Apply dates", action: applyDates).disabled(store.isBusy)
    }

    private func applyDates() {
        guard let day = ISODay.date(reviewDateInput), let comparison = ISODay.date(comparisonDateInput) else {
            store.errorMessage = "Enter valid dates in YYYY-MM-DD format."
            return
        }
        store.day = day
        store.comparisonDay = comparison
    }

    private func prepareExport(_ kind: ExportKind) {
        let day = store.dayString
        Task {
            guard let data = await store.export(kind, on: day) else { return }
            exportFile = WorkbenchJSONDocument(data: data)
            switch kind {
            case .workdoc: exportName = "through-workdoc"
            case .catalog: exportName = "japan-through-services-\(day)"
            case .inspectionPlan: exportName = "inspection-plan-\(store.inspectionPlan?.endDay ?? day)"
            }
            exporting = true
        }
    }

    private func navigatePattern(_ delta: Int) {
        let patterns = store.filteredPatterns
        guard !patterns.isEmpty else { return }
        let current = store.selectedID.flatMap { id in patterns.firstIndex { $0.id == id } }
            ?? (delta > 0 ? -1 : patterns.count)
        store.selectedID = patterns[min(max(0, current + delta), patterns.count - 1)].id
    }

    private func installCommands() {
        commands.canOpen = !store.isBusy
        commands.canNavigate = !store.filteredPatterns.isEmpty
        commands.canExport = store.snapshot != nil && !store.isBusy
        commands.open = { self.importKind = .workdoc; self.importing = true }
        commands.search = { self.searchPresented = true }
        commands.previous = { self.navigatePattern(-1) }
        commands.next = { self.navigatePattern(1) }
        commands.exportWorkdoc = { self.prepareExport(.workdoc) }
        commands.exportCatalog = { self.prepareExport(.catalog) }
    }
}

@MainActor @Observable
final class ThroughWorkbenchCommandBridge {
    var canOpen = false
    var canNavigate = false
    var canExport = false
    @ObservationIgnored var open: (@MainActor () -> Void)?
    @ObservationIgnored var search: (@MainActor () -> Void)?
    @ObservationIgnored var previous: (@MainActor () -> Void)?
    @ObservationIgnored var next: (@MainActor () -> Void)?
    @ObservationIgnored var exportWorkdoc: (@MainActor () -> Void)?
    @ObservationIgnored var exportCatalog: (@MainActor () -> Void)?
}

private struct ThroughWorkbenchCommandKey: FocusedValueKey {
    typealias Value = ThroughWorkbenchCommandBridge
}

extension FocusedValues {
    var throughWorkbenchCommands: ThroughWorkbenchCommandBridge? {
        get { self[ThroughWorkbenchCommandKey.self] }
        set { self[ThroughWorkbenchCommandKey.self] = newValue }
    }
}

struct ThroughWorkbenchCommands: Commands {
    @FocusedValue(\.throughWorkbenchCommands) private var bridge

    var body: some Commands {
        #if !RAIL_DIAGNOSTICS
        CommandGroup(replacing: .newItem) {
            Button("Import working document") { bridge?.open?() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(bridge?.canOpen != true)
        }
        #endif
        CommandMenu("Through-service Review") {
            ThroughWorkbenchCommandItems(bridge: bridge)
        }
    }
}

struct ReviewOverviewView: View {
    let snapshot: WorkbenchSnapshot?
    let select: (String) -> Void

    var body: some View {
        if let snapshot {
            List {
                Section {
                    Text("Review historical through-service display patterns from \(snapshot.targetFrom). Source gaps and physical-reference warnings require review; they do not certify service coverage or route solvability.")
                        .foregroundStyle(.secondary)
                }
                Section("Review issues (\(snapshot.issues.count))") {
                    if snapshot.issues.isEmpty { Text("No issues found by the available checks.") }
                    ForEach(snapshot.issues) { issue in
                        Button { select(issue.patternID) } label: { IssueRow(issue: issue) }
                            .buttonStyle(.plain)
                    }
                }
                Section("Changes between selected dates (\(snapshot.differences.count))") {
                    if snapshot.differences.isEmpty { Text("No pattern changes between these dates.") }
                    ForEach(snapshot.differences, id: \.id) { difference in
                        Button { select(difference.patternID) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(difference.name).font(.headline)
                                Text(difference.change).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        } else {
            ContentUnavailableView("Open a through-service catalog", systemImage: "tram", description: Text("The bundled catalog loads automatically. Import JSON to recover or replace the working document."))
        }
    }
}

struct IssueRow: View {
    let issue: ReviewIssue
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(issue.severity.rawValue.capitalized) · \(issue.patternID)", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.secondary)
            Text(issue.message).foregroundStyle(.primary)
        }
    }
}

struct ThroughWorkbenchCommandItems: View {
    let bridge: ThroughWorkbenchCommandBridge?

    var body: some View {
        Group {
            Button("Search patterns") { bridge?.search?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(bridge == nil)
            Divider()
            Button("Previous pattern") { bridge?.previous?() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(bridge?.canNavigate != true)
            Button("Next pattern") { bridge?.next?() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(bridge?.canNavigate != true)
            Divider()
            Button("Export working document") { bridge?.exportWorkdoc?() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(bridge?.canExport != true)
            Button("Export expanded catalog") { bridge?.exportCatalog?() }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                .disabled(bridge?.canExport != true)
        
        }
    }
}
