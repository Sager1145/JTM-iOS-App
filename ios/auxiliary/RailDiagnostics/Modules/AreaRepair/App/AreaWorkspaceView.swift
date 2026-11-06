import MapKit
import SwiftUI

/// Area repair: select, resolve, review problems, stack fixes and preview in-app; repository writes
/// happen only through the exported patch and the guarded CLI command.
struct AreaWorkspaceView: View {
    @Bindable var model: AreaRepairModel
    @State private var commands = AreaRepairCommandBridge()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                selectionForm
                if let error = model.errorText {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
                }
                if model.hasResolved { problemsSection; proposalSection; stackSection }
                if let preview = model.preview { previewSection(preview) }
                if let export = model.export { exportSection(export) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .focusedSceneValue(\.areaRepairCommands, commands)
        .sheet(isPresented: $model.confirmingExport) { exportSheet }
        .onAppear(perform: installCommands)
        .onChange(of: model.busy) { _, _ in installCommands() }
        .onChange(of: model.ops) { _, _ in installCommands() }
        .onChange(of: model.hasResolved) { _, _ in installCommands() }
    }

    private func installCommands() {
        commands.canResolve = !model.busy
        commands.canPreview = !model.busy && !model.ops.isEmpty
        commands.canUndo = !model.busy && !model.ops.isEmpty
        commands.canExport = model.canExport
        commands.resolve = { model.resolve() }
        commands.preview = { model.runPreview() }
        commands.undo = { model.undoLast() }
        commands.export = { model.confirmingExport = true }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Area repair").font(.title.bold())
                Text(model.message).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            if model.busy { ProgressView() }
        }
    }

    private var selectionForm: some View {
        GroupBox("Area") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Selection", selection: $model.kind) {
                    ForEach(AreaRepairModel.Kind.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                switch model.kind {
                case .rect:
                    HStack { TextField("Min lon", text: $model.minLon); TextField("Min lat", text: $model.minLat)
                             TextField("Max lon", text: $model.maxLon); TextField("Max lat", text: $model.maxLat) }
                case .stationPair:
                    HStack { TextField("Line ID", text: $model.lineID); TextField("From station ID", text: $model.fromStation)
                             TextField("To station ID", text: $model.toStation) }
                case .lineSection:
                    HStack { TextField("Line ID", text: $model.lineID); TextField("First interval", text: $model.firstInterval)
                             TextField("Last interval", text: $model.lastInterval) }
                case .centre:
                    HStack { TextField("Longitude", text: $model.centreLon); TextField("Latitude", text: $model.centreLat)
                             TextField("Radius · m", text: $model.radius) }
                }
                HStack {
                    TextField("Margin · m", text: $model.margin).frame(maxWidth: 140)
                    Spacer()
                    Button("Resolve area  ⌃⌘R") { model.resolve() }.buttonStyle(.borderedProminent).disabled(model.busy)
                        .keyboardShortcut("r", modifiers: [.control, .command])
                }
            }.textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never).padding(6)
        }
    }

    private var problemsSection: some View {
        GroupBox("Problems (\(model.problems.count))") {
            VStack(alignment: .leading, spacing: 0) {
                if model.problems.isEmpty { Text("No problems detected in this area.").foregroundStyle(.secondary).padding(8) }
                ForEach(model.problems) { problem in
                    Button { model.selectProblem(problem.id) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: problem.hasProposal ? "wrench.and.screwdriver" : "magnifyingglass")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(problem.kind) · \(problem.severity)").font(.callout.weight(.semibold))
                                Text(problem.message).font(.caption).foregroundStyle(.secondary)
                                Text(problem.lineIDs.joined(separator: ", ")).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }.padding(8).background(model.selectedProblemID == problem.id ? Color.accentColor.opacity(0.15) : .clear)
                    }.buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder private var proposalSection: some View {
        if model.selectedProblemID != nil {
            GroupBox("Proposed fix") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.proposalSummary).font(.callout.monospaced()).textSelection(.enabled)
                    TextField("Reason (required)", text: $model.proposalReason).textFieldStyle(.roundedBorder)
                    TextField("Source — URL or document, one per line or comma-separated (required)", text: $model.proposalSource, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...4)
                    Button("Add to patch stack") { model.addProposal() }.disabled(!model.canAddProposal || model.busy)
                }.padding(6)
            }
        }
    }

    private var stackSection: some View {
        GroupBox("Patch stack (\(model.ops.count))") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.ops) { op in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(op.title, systemImage: op.writable ? "square.and.pencil" : "doc.text").font(.callout.weight(.semibold))
                        Text(op.file + " [" + op.key + "]" + (op.writable ? "" : "  · report-only")).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(op.reason).font(.caption)
                    }
                }
                HStack {
                    Button("Undo last fix  ⌃⌘Z") { model.undoLast() }.disabled(model.ops.isEmpty || model.busy)
                        .keyboardShortcut("z", modifiers: [.control, .command])
                    Button("Preview  ⌃⌘P") { model.runPreview() }.disabled(model.ops.isEmpty || model.busy)
                        .keyboardShortcut("p", modifiers: [.control, .command])
                    Spacer()
                    Button("Export patch for guarded write…") { model.confirmingExport = true }.buttonStyle(.borderedProminent)
                        .disabled(!model.canExport)
                }
            }.padding(6)
        }
    }

    private func previewSection(_ preview: AreaPreviewData) -> some View {
        GroupBox("Preview · \(preview.problemsBefore) → \(preview.problemsAfter) problems · \(preview.cleared) cleared · \(preview.introduced) introduced") {
            VStack(alignment: .leading, spacing: 10) {
                Map {
                    ForEach(Array(preview.baseline.enumerated()), id: \.offset) { _, path in
                        MapPolyline(coordinates: path).stroke(.gray.opacity(0.7), lineWidth: 2)
                    }
                    ForEach(Array(preview.patched.enumerated()), id: \.offset) { _, path in
                        MapPolyline(coordinates: path).stroke(.blue, lineWidth: 3)
                    }
                    ForEach(Array(preview.stations.enumerated()), id: \.offset) { _, station in
                        Annotation(station.name, coordinate: station.coordinate) { Circle().fill(.white).stroke(.black, lineWidth: 2).frame(width: 9, height: 9) }
                    }
                    ForEach(Array(preview.junctions.enumerated()), id: \.offset) { _, point in
                        Annotation("", coordinate: point) { Image(systemName: "diamond.fill").foregroundStyle(.orange).font(.caption) }
                    }
                }.frame(height: 420).clipShape(RoundedRectangle(cornerRadius: 8))
                Text("Grey: baseline. Blue: patched. Dots: stations. Diamonds: junctions.").font(.caption).foregroundStyle(.secondary)
                if preview.rides.isEmpty { Text("No rides cross this area.").font(.caption) }
                ForEach(preview.rides) { ride in
                    HStack {
                        Text(ride.id).font(.caption.monospaced())
                        Spacer()
                        Label(ride.before ? "certified" : "uncertified", systemImage: ride.before ? "checkmark.circle" : "xmark.circle")
                        Image(systemName: "arrow.right")
                        Label(ride.after ? "certified" : "uncertified", systemImage: ride.after ? "checkmark.circle" : "xmark.circle")
                            .foregroundStyle(ride.after ? .green : .red)
                    }.font(.caption)
                }
            }.padding(6)
        }
    }

    private func exportSection(_ export: AreaPatchExport) -> some View {
        GroupBox("Exported patch") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Patch: " + export.patchPath).font(.caption.monospaced()).textSelection(.enabled)
                if let reportOnly = export.reportOnlyPath {
                    Text("Report-only ops (mirror into their sources): " + reportOnly).font(.caption.monospaced()).textSelection(.enabled)
                }
                Text("Run from " + export.repository + ":").font(.caption)
                Text(export.command).font(.callout.monospaced()).textSelection(.enabled)
                Button("Copy command") { model.copyCommand() }
                Text("The command backs up the files, writes the patch, runs the regression guards and restores the backup automatically if any guard fails.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }

    private var exportSheet: some View {
        NavigationStack {
            Form {
                Section("Writable (written by the guarded command)") {
                    ForEach(model.ops.filter(\.writable)) { Text("\($0.title) → \($0.file) [\($0.key)]").font(.callout.monospaced()) }
                }
                Section("Report-only (refused by the write; mirror instead)") {
                    ForEach(model.ops.filter { !$0.writable }) { op in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(op.title) → \(op.file) [\(op.key)]").font(.callout.monospaced()).foregroundStyle(.secondary)
                            if let mirror = op.mirror { Text("Mirror into " + mirror).font(.caption) }
                        }
                    }
                }
                Section {
                    Text("This app does not write repository data. Export saves patch.json in the evidence archive's area-repairs folder and copies the command `bash ios/verify.sh area write --patch <path> --confirm`, which writes with backups, guards and auto-revert.")
                        .font(.caption)
                }
            }
            .navigationTitle("Export \(model.writableCount) change(s)?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.confirmingExport = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Export") { model.exportPatch() } }
            }
        }.frame(idealWidth: 560, idealHeight: 480)
    }
}
