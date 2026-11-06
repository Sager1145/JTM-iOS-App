import SwiftUI

struct PatchEditorView: View {
    let store: WorkbenchStore
    let initial: PatchDraft
    @Environment(\.dismiss) private var dismiss
    @State private var draft = PatchDraft(patternID: "", from: "")
    @State private var initialized = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Effective period") {
                    TextField("Pattern ID", text: $draft.patternID)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .disabled(!draft.isNew)
                    TextField("Effective from (YYYY-MM-DD)", text: $draft.from)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Effective to (exclusive, optional)", text: $draft.to)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                Section("Source evidence") {
                    TextField("Source URL (https://…)", text: $draft.source)
                        .autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
                    TextField("Review note", text: $draft.note, axis: .vertical).lineLimit(3 ... 8)
                }
                Section(draft.isNew ? "Complete pattern JSON" : "Patch JSON") {
                    Text(draft.isNew ? "Include every pattern field and ordered legs. Preserve surveyed line and station identities. The JSON id must match Pattern ID." : "Use changes for pattern fields and legChanges for indexed leg edits (zero-based). Unknown fields are retained. Use null to clear a field.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $draft.editor)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .frame(minHeight: 260)
                        .accessibilityLabel(draft.isNew ? "Complete pattern JSON" : "Patch JSON")
                    if !draft.isNew { Toggle("Remove this pattern during the effective period", isOn: $draft.remove) }
                }
                if let error = store.errorMessage {
                    Section("Cannot save patch") { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
                Section {
                    Text("Saving records the patch and autosaves the working document. Export an expanded catalog for the selected review date when ready.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(initial.isNew ? "Add historical pattern" : "Create dated patch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save patch  ⌘S") {
                        Task { if await store.apply(draft) { dismiss() } }
                    }.keyboardShortcut("s", modifiers: .command)
                        .disabled(store.isBusy || draft.patternID.isEmpty || draft.source.isEmpty || draft.note.isEmpty)
                }
            }
            .task {
                if !initialized { draft = initial; initialized = true; store.errorMessage = nil }
            }
        }
        .frame(idealWidth: 720, idealHeight: 760)
        .interactiveDismissDisabled(store.isBusy)
    }
}
